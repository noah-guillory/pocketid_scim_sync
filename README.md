# PocketID SCIM Sync

An Elixir service that continuously synchronizes users from a self-hosted [PocketID](https://github.com/stonith404/pocket-id) instance into **AWS IAM Identity Center** using the SCIM 2.0 protocol.

## How It Works

The service runs a reconciliation loop on startup and every **30 minutes** thereafter:

1. **Fetch** all users from your PocketID instance via its REST API.
2. **Upsert** each PocketID user into AWS IAM Identity Center via the SCIM `/Users` endpoint (creates new users, skips existing ones).
3. **Delete** any users found in AWS IAM Identity Center that no longer exist in PocketID, keeping both systems in sync.

## Prerequisites

- A running [PocketID](https://github.com/stonith404/pocket-id) instance with an admin API key.
- AWS IAM Identity Center with SCIM provisioning enabled. You will need the SCIM endpoint URL and an access token (generated from the IAM Identity Center console under *Settings → Automatic provisioning*).
- Docker (recommended) **or** Elixir 1.18+ with Mix for running from source.

## Environment Variables

| Variable | Description |
|---|---|
| `POCKET_ID_URL` | Base URL of your PocketID instance, e.g. `https://id.example.com` |
| `POCKETID_ADMIN_KEY` | Admin API key for PocketID |
| `AWS_SCIM_ENDPOINT` | AWS IAM Identity Center SCIM endpoint, e.g. `https://scim.us-east-1.amazonaws.com/xxx/scim/v2` |
| `AWS_SCIM_TOKEN` | Bearer token for the AWS SCIM endpoint |

## Setup & Deployment

### Docker (recommended)

A pre-built image is published to the GitHub Container Registry on every push to `main`:

```bash
docker pull ghcr.io/noah-guillory/pocketid_scim_sync:latest
```

Run the container, passing your environment variables:

```bash
docker run -d \
  -e POCKET_ID_URL=https://id.example.com \
  -e POCKETID_ADMIN_KEY=your_admin_key \
  -e AWS_SCIM_ENDPOINT=https://scim.us-east-1.amazonaws.com/xxx/scim/v2 \
  -e AWS_SCIM_TOKEN=your_scim_token \
  ghcr.io/noah-guillory/pocketid_scim_sync:latest
```

### Docker Compose

```yaml
services:
  pocketid-scim-sync:
    image: ghcr.io/noah-guillory/pocketid_scim_sync:latest
    restart: unless-stopped
    environment:
      POCKET_ID_URL: https://id.example.com
      POCKETID_ADMIN_KEY: your_admin_key
      AWS_SCIM_ENDPOINT: https://scim.us-east-1.amazonaws.com/xxx/scim/v2
      AWS_SCIM_TOKEN: your_scim_token
```

### Running from Source

Requires Elixir 1.18+.

```bash
# Install dependencies
mix deps.get

# Run the application
POCKET_ID_URL=https://id.example.com \
POCKETID_ADMIN_KEY=your_admin_key \
AWS_SCIM_ENDPOINT=https://scim.us-east-1.amazonaws.com/xxx/scim/v2 \
AWS_SCIM_TOKEN=your_scim_token \
mix run --no-halt
```

### Building the Docker Image Locally

```bash
docker build -t pocketid_scim_sync .
```

## Notes

- The service only **creates** users in AWS on each cycle (HTTP 409 Conflict responses for existing users are silently ignored). It does not update user attributes after initial creation.
- AWS IAM Identity Center SCIM pagination is not implemented; the service relies on the default page size (50 users). This is suitable for small homelabs.
- The sync interval is hardcoded to 30 minutes. The first sync runs 1 second after startup.

