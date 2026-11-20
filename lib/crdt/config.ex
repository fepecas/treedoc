defmodule Crdt.Config do
  @moduledoc "Reads the optional node table from the file in NODES_FILE (REQ14, DES6)."

  @doc "`{:ok, file, nodes}` with the names as atoms, or `{:error, file, reason}`; no NODES_FILE: `{:ok, \"none\", []}`."
  def nodes do
    case System.get_env("NODES_FILE") do
      nil -> {:ok, "none", []}
      file -> read(file)
    end
  end

  defp read(file) do
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
