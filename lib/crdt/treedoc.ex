defmodule Crdt.Treedoc do
  @moduledoc """
  Treedoc CRDT (CON4, DES3, PAP2.2): one character per atom (PAP2), keyed by its PosID.
  Pure module (DES3.5): no processes, network or files. Paper scenario of DES3.6 in the tests.
  """

  @doc "Empty document: only the virtual root `[]`, which holds no character (DES3.1)."
  def new, do: %{chars: %{}, dead: MapSet.new()}

  @doc "Orders two PosIDs by in-order traversal; returns `:lt`, `:eq` or `:gt` (REQ7, REQ8)."
  # PosID as a path, formal order of PAP3.1 (DES3.3); disambiguator on every step (DES3.1)
  def compare([], []), do: :eq
  def compare([step | rest_a], [step | rest_b]), do: compare(rest_a, rest_b)
  # a is a prefix of b: b sits in a's left (0) or right (1) subtree
  def compare([], [{0, _, _} | _]), do: :gt
  def compare([], [{1, _, _} | _]), do: :lt
  def compare([{0, _, _} | _], []), do: :lt
  def compare([{1, _, _} | _], []), do: :gt
  # Steps differ: tuple order is bit first, then {seq, node} (DES3.2, UDIS, PAP3.3.1)
  def compare([step_a | _], [step_b | _]), do: if(step_a < step_b, do: :lt, else: :gt)

  @doc "Decides the operation at the origin replica, without changing the state (REQ3, REQ4)."
  def prepare(state, {:insert, index, ch}, {seq, node}) do
    visible = visible_positions(state)

    if valid_index?(index, length(visible) + 1) do
      left = if index == 0, do: [], else: Enum.at(visible, index - 1)
      right = Enum.at(visible, index)
      {:ok, %{op: :ins, pos: new_pos(left, right, seq, node), ch: ch}}
    else
      {:error, :invalid_index}
    end
  end

  def prepare(state, {:delete, index}, _dot) do
    visible = visible_positions(state)

    if valid_index?(index, length(visible)) do
      {:ok, %{op: :del, pos: Enum.at(visible, index)}}
    else
      {:error, :invalid_index}
    end
  end

  @doc "Applies an operation at every replica, the origin included (REQ6)."
  def effect(state, %{op: :ins, pos: pos, ch: ch}), do: put_in(state.chars[pos], ch)
  # Tombstone that keeps ch (OUR, DES3.5); REQ10: deleting twice leaves the same tombstone
  def effect(state, %{op: :del, pos: pos}), do: %{state | dead: MapSet.put(state.dead, pos)}

  @doc "Visible text: the whole document, kept on every node (REQ2)."
  def value(state) do
    state |> visible_positions() |> Enum.map_join(&state.chars[&1])
  end

  @doc "Every character in order as `{ch, pos, deleted?}`, for `Crdt.debug()` (REQ17)."
  def debug_rows(state) do
    for pos <- sorted_positions(state),
        do: {state.chars[pos], pos, MapSet.member?(state.dead, pos)}
  end

  # REQ8, DES3.4: left child of the right neighbour, or right child of the left one.
  # Replaces Algorithm 1: a fresh PosID in between is enough (density PAP2.1, insert PAP2.2).
  defp new_pos(left, right, seq, node) do
    if right != nil and List.starts_with?(right, left) do
      right ++ [{0, seq, node}]
    else
      left ++ [{1, seq, node}]
    end
  end

  defp valid_index?(index, limit), do: is_integer(index) and index >= 0 and index < limit

  defp sorted_positions(state), do: Enum.sort(Map.keys(state.chars), {:asc, __MODULE__})

  defp visible_positions(state) do
    Enum.reject(sorted_positions(state), &MapSet.member?(state.dead, &1))
  end
end
