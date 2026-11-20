defmodule Crdt do
  @moduledoc """
  Collaborative text editor with no central server (REQ1), on Treedoc; small modules (CON5, DES8).
  IEx API (CON6, DES9). Codes such as REQ7 or PAP3.1: README.md, "How to read this project".
  """

  alias Crdt.Replica

  @doc "Inserts each character of `text` starting at `index`, in one call (REQ3, REQ20)."
  def insert(index, text) when is_binary(text), do: call({:insert, index, text})

  @doc "Deletes `count` characters starting at `index`; all or nothing (REQ4)."
  def delete(index, count \\ 1), do: call({:delete, index, count})

  @doc "Visible text of this node's whole copy (REQ2)."
  def text, do: call(:text)

  @doc "Prints node, files, table, discovery, connected nodes, clock, history, waiting ops (REQ17)."
  def status, do: print(call(:status))

  @doc "Prints the last 10 applied ops, after `... N earlier ops` if there are more (REQ17)."
  def history, do: print(call({:history, :last}))

  @doc "With `:all`, prints every applied op in the order it was applied."
  def history(:all), do: print(call({:history, :all}))

  @doc "Prints every character with its PosID and whether it is deleted."
  def debug, do: print(call(:debug))

  # DES9: without a replica every function returns {:error, :no_replica}
  defp call(request) do
    if Process.whereis(Replica),
      do: GenServer.call(Replica, request),
      else: {:error, :no_replica}
  end

  # DES9: print in the caller's console, also from a remote shell
  defp print(lines) when is_list(lines), do: Enum.each(lines, &IO.puts/1)
  defp print(error), do: error
end
