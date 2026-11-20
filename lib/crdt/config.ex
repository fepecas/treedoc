defmodule Crdt.Config do
  @moduledoc "Reads the node table from the file in NODES_FILE (REQ14, DES6)."

  @doc "`{:ok, file, nodes}` with the names as atoms, or `{:error, file, reason}`."
  def nodes do
    file = System.get_env("NODES_FILE", "nodes.local.txt")

    case File.read(file) do
      {:ok, text} -> {:ok, file, parse(text)}
      {:error, reason} -> {:error, file, reason}
    end
  end

  # DES6: trim also drops the \r of Windows CRLF; skip blank lines and # comments
  defp parse(text) do
    for line <- String.split(text, "\n"),
        name = String.trim(line),
        name != "" and not String.starts_with?(name, "#"),
        do: String.to_atom(name)
  end
end
