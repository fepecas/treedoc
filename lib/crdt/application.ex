defmodule Crdt.Application do
  @moduledoc """
  OTP application: on a named node starts `Crdt.Replica` and, unless DISCOVERY=off, `Crdt.Discovery`
  (CON2, DES6, DES6.1). Without `--name` it prints the start commands for Windows, macOS and Linux (CON3, DES11).
  """

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(), strategy: :one_for_one, name: Crdt.Supervisor)
  end

  @doc "The children for this node: none without a name (DES6)."
  def children do
    cond do
      not Node.alive?() -> no_name()
      System.get_env("DISCOVERY") == "off" -> [Crdt.Replica]
      true -> [Crdt.Replica, Crdt.Discovery]
    end
  end

  defp no_name do
    IO.puts("""
    Node has no name: Crdt.Replica not started. Start it with the start script (docs/DESIGN.md, section 11):
      PowerShell:   .\\scripts\\start.ps1
      macOS, Linux: ./scripts/start.sh
    """)

    []
  end
end
