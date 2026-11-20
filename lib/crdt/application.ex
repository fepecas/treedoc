defmodule Crdt.Application do
  @moduledoc """
  OTP application: starts `Crdt.Replica` only on a named node (CON2, DES6).
  Without `--name` it prints the commands for Windows, macOS and Linux (CON3, DES11).
  """

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(), strategy: :one_for_one, name: Crdt.Supervisor)
  end

  defp children do
    if Node.alive?() do
      [Crdt.Replica]
    else
      IO.puts("""
      Node has no name: Crdt.Replica not started. Start it like this (docs/DESIGN.md, section 11):
        PowerShell:   $env:NODES_FILE="nodes.local.txt"; iex.bat --name crdt1@127.0.0.1 --cookie cpd2026 -S mix
        macOS, Linux: NODES_FILE=nodes.local.txt iex --name crdt1@127.0.0.1 --cookie cpd2026 -S mix
      """)

      []
    end
  end
end
