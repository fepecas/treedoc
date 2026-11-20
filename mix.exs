defmodule Crdt.MixProject do
  use Mix.Project

  def project do
    [
      app: :crdt,
      version: "0.1.0",
      # CON1: must compile with Elixir 1.18.3 and OTP 27 (Raspberry Pi OS)
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Replica networking is tested by hand (MAN1 to MAN8), docs/DESIGN.md DES12
      test_coverage: [summary: [threshold: 0]]
    ]
  end

  # See "mix help compile.app" for application options.
  def application do
    [
      extra_applications: [:logger],
      mod: {Crdt.Application, []}
    ]
  end

  # CON1: no external dependencies.
  defp deps do
    []
  end
end
