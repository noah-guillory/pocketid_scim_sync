defmodule PocketidScimSync.MixProject do
  use Mix.Project

  def project do
    [
      app: :pocketid_scim_sync,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PocketidScimSync.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  def deps do
    [
      {:req, "~> 0.5.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
