# --- Stage 1: Build ---
FROM elixir:1.18.3-alpine AS builder

ENV MIX_ENV=prod

WORKDIR /app

RUN apk add --no-cache build-base git

RUN mix local.hex --force && \
  mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY lib lib

RUN mix compile
RUN mix release

# --- Stage 2: Runner ---
FROM alpine:3.19

# Install dependencies needed for the BEAM
RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

# Copy the release from the builder stage
COPY --from=builder /app/_build/prod/rel/pocketid_scim_sync ./

# Set runtime environment
ENV MIX_ENV=prod

# Run the release
ENTRYPOINT ["bin/pocketid_scim_sync"]
CMD ["start"]