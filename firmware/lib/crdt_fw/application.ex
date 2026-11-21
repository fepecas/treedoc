defmodule CrdtFw.Application do
  @moduledoc """
  The firmware application, `:temporary` in the release (DES13, DES15): starts `CrdtFw.Supervisor`
  with one child, `CrdtFw` (REQ21, CON3). `Crdt.Application` does not run: `:crdt` is only loaded.
  """

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([CrdtFw], strategy: :one_for_one, name: CrdtFw.Supervisor)
  end
end
