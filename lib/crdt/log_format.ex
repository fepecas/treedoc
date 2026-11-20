defmodule Crdt.LogFormat do
  @moduledoc """
  One operation per JSON line, readable in a text editor (REQ18, DES5, DES5.2).
  Pure module: no processes, network or files.
  """

  @doc "JSON line for `msg`, ending in \"\\n\", keys in the order of DES5.2."
  def to_json_line(msg) do
    pairs = [op: msg.op, from: msg.from, vc: msg.vc, pos: Enum.map(msg.pos, &Tuple.to_list/1)]
    pairs = if msg.op == :ins, do: pairs ++ [ch: msg.ch], else: pairs
    # JSON writes atoms as strings
    "{" <> Enum.map_join(pairs, ",", fn {k, v} -> "\"#{k}\":" <> JSON.encode!(v) end) <> "}\n"
  end

  @doc "`{:ok, msg}`, or `{:error, reason}` for bad JSON or a bad shape; never raises."
  def from_json_line(line) do
    case JSON.decode(line) do
      {:ok, map} -> to_msg(map)
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_msg(%{"op" => "ins", "ch" => ch} = map) when is_binary(ch),
    do: with_base(map, %{op: :ins, ch: ch})

  defp to_msg(%{"op" => "del"} = map), do: with_base(map, %{op: :del})
  defp to_msg(_), do: {:error, :bad_shape}

  # DES5.2: node names back to atoms, steps back to {bit, seq, node}
  defp with_base(%{"from" => from, "vc" => vc, "pos" => pos}, msg)
       when is_binary(from) and is_map(vc) and is_list(pos) do
    if Enum.all?(Map.values(vc), &is_integer/1) and Enum.all?(pos, &step?/1) do
      vc = Map.new(vc, fn {node, n} -> {String.to_atom(node), n} end)
      pos = Enum.map(pos, fn [bit, seq, node] -> {bit, seq, String.to_atom(node)} end)
      {:ok, Map.merge(msg, %{from: String.to_atom(from), vc: vc, pos: pos})}
    else
      {:error, :bad_shape}
    end
  end

  defp with_base(_map, _msg), do: {:error, :bad_shape}

  defp step?([bit, seq, node]), do: bit in [0, 1] and is_integer(seq) and is_binary(node)
  defp step?(_), do: false
end
