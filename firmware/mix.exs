defmodule CrdtFw.MixProject do
  @moduledoc """
  Nerves firmware for a Raspberry Pi 4 that runs our node (REQ21, DES15). A separate project:
  only it depends on Nerves, `lib/` keeps no dependencies (CON1).
  """

  use Mix.Project

  @app :crdt_fw
  @version "0.1.0"
  @all_targets [:rpi4]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      archives: [nerves_bootstrap: "~> 1.17"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {CrdtFw.Application, []}
    ]
  end

  def cli do
    [preferred_targets: [run: :host, test: :host]]
  end

  defp deps do
    [
      # DES15: runtime: false keeps :crdt out of the applications of :crdt_fw (release below)
      {:crdt, path: "..", runtime: false},
      {:nerves, "~> 1.15", runtime: false},
      {:shoehorn, "~> 0.9"},
      {:nerves_runtime, "~> 0.13"},
      {:nerves_pack, "~> 0.7", targets: @all_targets},
      # CrdtFw calls VintageNet; nerves_pack brings it, listed so the compiler knows it
      {:vintage_net, "~> 0.13", targets: @all_targets},
      # DES15: the official system, Erlang/OTP 29.1.2
      {:nerves_system_rpi4, "~> 2.2.0", runtime: false, targets: :rpi4}
    ]
  end

  def release do
    [
      overwrite: true,
      # DES6: the cookie of every node; CrdtFw also sets it with Node.set_cookie/1 (DES15)
      cookie: "cpd2026",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]],
      # DES15: :crdt is only loaded, so Crdt.Application does not run; crdt_fw is
      # :temporary, so if it stops the VM stays alive and the Pi does not reboot (DES13)
      applications: [crdt: :load, crdt_fw: :temporary]
    ]
  end
end
