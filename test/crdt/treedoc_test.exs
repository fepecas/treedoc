defmodule Crdt.TreedocTest do
  use ExUnit.Case, async: true

  alias Crdt.Treedoc

  # Prepares an operation and applies it locally, as the origin replica does.
  defp edit(state, edit, dot) do
    {:ok, op} = Treedoc.prepare(state, edit, dot)
    {Treedoc.effect(state, op), op}
  end

  defp type(state, text, node, first_seq) do
    text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reduce(state, fn {ch, i}, acc ->
      {acc, _op} = edit(acc, {:insert, i, ch}, {first_seq + i, node})
      acc
    end)
  end

  describe "compare/2 (docs/DESIGN.md DES3.3)" do
    @tag :req7
    @tag :req8
    test "a prefix comes after its left subtree and before its right subtree" do
      a = [{1, 1, :n1}]
      assert Treedoc.compare(a, a ++ [{0, 2, :n1}]) == :gt
      assert Treedoc.compare(a, a ++ [{1, 2, :n1}]) == :lt
      assert Treedoc.compare(a ++ [{0, 2, :n1}], a) == :lt
      assert Treedoc.compare(a ++ [{1, 2, :n1}], a) == :gt
    end

    @tag :req7
    @tag :req8
    test "different bits: the 0 side goes first" do
      assert Treedoc.compare([{0, 9, :n9}], [{1, 1, :n1}]) == :lt
      assert Treedoc.compare([{1, 1, :n1}], [{0, 9, :n9}]) == :gt
    end

    @tag :req7
    @tag :req8
    test "same bit: the smaller disambiguator {seq, node} goes first" do
      assert Treedoc.compare([{0, 1, :n2}], [{0, 2, :n1}]) == :lt
      assert Treedoc.compare([{0, 3, :n1}], [{0, 3, :n2}]) == :lt
      assert Treedoc.compare([{0, 3, :n2}], [{0, 3, :n1}]) == :gt
    end

    @tag :req7
    test "equal paths, including the root" do
      assert Treedoc.compare([], []) == :eq
      assert Treedoc.compare([{1, 1, :n1}, {0, 2, :n1}], [{1, 1, :n1}, {0, 2, :n1}]) == :eq
    end
  end

  describe "new/0, effect/2 and value/1" do
    @tag :req2
    @tag :req6
    test "a new document is empty and effect builds the text" do
      assert Treedoc.value(Treedoc.new()) == ""
      ins = %{op: :ins, pos: [{1, 1, :n1}], ch: "a"}
      state = Treedoc.effect(Treedoc.new(), ins)
      assert Treedoc.value(state) == "a"
      assert Treedoc.value(Treedoc.effect(state, %{op: :del, pos: [{1, 1, :n1}]})) == ""
    end

    @tag :req7
    @tag :req10
    test "deleting the same character twice has the same effect as once" do
      state = type(Treedoc.new(), "ab", :n1, 1)
      del = %{op: :del, pos: [{1, 1, :n1}]}
      once = Treedoc.effect(state, del)
      assert Treedoc.effect(once, del) == once
    end
  end

  describe "prepare/3 for insert (docs/DESIGN.md DES3.4)" do
    @tag :req3
    test "into an empty document" do
      {state, op} = edit(Treedoc.new(), {:insert, 0, "h"}, {1, :n1})
      assert op == %{op: :ins, pos: [{1, 1, :n1}], ch: "h"}
      assert Treedoc.value(state) == "h"
    end

    @tag :req3
    test "at the start, in the middle and at the end" do
      state = type(Treedoc.new(), "bd", :n1, 1)
      {state, _} = edit(state, {:insert, 0, "a"}, {3, :n1})
      assert Treedoc.value(state) == "abd"
      {state, _} = edit(state, {:insert, 2, "c"}, {4, :n1})
      assert Treedoc.value(state) == "abcd"
      {state, _} = edit(state, {:insert, 4, "e"}, {5, :n1})
      assert Treedoc.value(state) == "abcde"
    end

    @tag :req3
    test "next to tombstones, the character lands at the requested index" do
      state = type(Treedoc.new(), "abcd", :n1, 1)
      {state, _} = edit(state, {:delete, 1}, {5, :n1})
      {state, _} = edit(state, {:delete, 1}, {6, :n1})
      assert Treedoc.value(state) == "ad"
      {state, _} = edit(state, {:insert, 1, "x"}, {7, :n1})
      assert Treedoc.value(state) == "axd"
    end

    @tag :req3
    @tag :req8
    test "uses the two cases: left child of the right neighbour, or right child of the left" do
      state = type(Treedoc.new(), "ab", :n1, 1)
      # "b" is the right child of "a", so the new one is the left child of "b"
      {_, op} = edit(state, {:insert, 1, "x"}, {3, :n1})
      assert op.pos == [{1, 1, :n1}, {1, 2, :n1}, {0, 3, :n1}]
      # At the end there is no right neighbour: right child of the last one
      {_, op} = edit(state, {:insert, 2, "y"}, {3, :n1})
      assert op.pos == [{1, 1, :n1}, {1, 2, :n1}, {1, 3, :n1}]
    end
  end

  describe "prepare/3 for delete and invalid indices" do
    @tag :req3
    test "deletes the visible character at the index" do
      state = type(Treedoc.new(), "abc", :n1, 1)
      {state, op} = edit(state, {:delete, 1}, {4, :n1})
      assert op == %{op: :del, pos: [{1, 1, :n1}, {1, 2, :n1}]}
      assert Treedoc.value(state) == "ac"
    end

    @tag :req4
    test "rejects out-of-range indices without an operation" do
      state = type(Treedoc.new(), "ab", :n1, 1)
      assert Treedoc.prepare(state, {:insert, 3, "x"}, {3, :n1}) == {:error, :invalid_index}
      assert Treedoc.prepare(state, {:insert, -1, "x"}, {3, :n1}) == {:error, :invalid_index}
      assert Treedoc.prepare(state, {:delete, 2}, {3, :n1}) == {:error, :invalid_index}
      assert Treedoc.prepare(state, {:delete, -1}, {3, :n1}) == {:error, :invalid_index}
      assert Treedoc.prepare(Treedoc.new(), {:delete, 0}, {1, :n1}) == {:error, :invalid_index}
    end

    @tag :req4
    test "rejects an index that is not an integer" do
      state = type(Treedoc.new(), "ab", :n1, 1)
      assert Treedoc.prepare(state, {:insert, 1.0, "x"}, {3, :n1}) == {:error, :invalid_index}
      assert Treedoc.prepare(state, {:delete, 0.0}, {3, :n1}) == {:error, :invalid_index}
    end
  end

  describe "debug_rows/1" do
    @tag :req17
    test "lists every character in order, tombstones included" do
      state = type(Treedoc.new(), "ab", :n1, 1)
      {state, _} = edit(state, {:delete, 0}, {3, :n1})

      assert Treedoc.debug_rows(state) == [
               {"a", [{1, 1, :n1}], true},
               {"b", [{1, 1, :n1}, {1, 2, :n1}], false}
             ]
    end
  end

  describe "scenario of paper figures 3 and 4 (docs/DESIGN.md DES3.6)" do
    @tag :req8
    test "concurrent W and Y between c and d, then X between W and Y" do
      base = type(Treedoc.new(), "abcdef", :n1, 1)
      # Two replicas insert at the same place at the same time; {7, :n2} < {7, :n3}
      {:ok, w} = Treedoc.prepare(base, {:insert, 3, "W"}, {7, :n2})
      {:ok, y} = Treedoc.prepare(base, {:insert, 3, "Y"}, {7, :n3})
      replica2 = base |> Treedoc.effect(w) |> Treedoc.effect(y)
      replica3 = base |> Treedoc.effect(y) |> Treedoc.effect(w)
      assert Treedoc.value(replica2) == "abcWYdef"
      assert Treedoc.value(replica3) == "abcWYdef"

      {:ok, x} = Treedoc.prepare(replica2, {:insert, 4, "X"}, {8, :n2})
      assert Treedoc.value(Treedoc.effect(replica2, x)) == "abcWXYdef"
      assert Treedoc.value(Treedoc.effect(replica3, x)) == "abcWXYdef"
    end
  end

  describe "convergence without network" do
    @nodes [:n1, :n2, :n3]

    @tag :req7
    @tag :req3
    test "replicas that apply the same operations in different orders end equal" do
      for seed <- 1..100 do
        :rand.seed(:exsss, {seed, seed, seed})
        base = type(Treedoc.new(), "hello", :n0, 1)
        ops_by_node = Map.new(@nodes, &{&1, local_session(base, &1)})
        all_ops = ops_by_node |> Map.values() |> List.flatten()

        values =
          for node <- @nodes do
            own = Enum.reduce(ops_by_node[node], base, &Treedoc.effect(&2, &1))
            foreign = all_ops -- ops_by_node[node]
            own |> apply_in_random_order(foreign) |> Treedoc.value()
          end

        assert length(Enum.uniq(values)) == 1, "seed #{seed}: #{inspect(values)}"

        positions = for %{op: :ins, pos: pos} <- all_ops, do: pos
        assert length(positions) == length(Enum.uniq(positions)), "seed #{seed}"
      end
    end

    @tag :req7
    @tag :req3
    test "replicas that edit without having seen everything from the others end equal" do
      for seed <- 1..100 do
        :rand.seed(:exsss, {seed, 7, 7})
        base = type(Treedoc.new(), "hello", :n0, 1)
        start = Map.new(@nodes, &{&1, %{state: base, seen: MapSet.new(), next_seq: 101}})

        {replicas, log} =
          Enum.reduce(1..4, {start, []}, fn _round, {replicas, log} ->
            {replicas, log} = Enum.reduce(@nodes, {replicas, log}, &edit_round/2)
            {Map.new(replicas, fn {node, r} -> {node, receive_some(r, log)} end), log}
          end)

        values = for {_, r} <- replicas, do: Treedoc.value(receive_all(r, log))
        assert length(Enum.uniq(values)) == 1, "seed #{seed}: #{inspect(values)}"

        positions = for %{op: :ins, pos: pos} <- log, do: pos
        assert length(positions) == length(Enum.uniq(positions)), "seed #{seed}"
      end
    end
  end

  describe "edge cases" do
    @tag :req4
    test "empty document: value, insert at 0, delete at 0 is an error" do
      assert Treedoc.value(Treedoc.new()) == ""
      {state, _} = edit(Treedoc.new(), {:insert, 0, "a"}, {1, :n1})
      assert Treedoc.value(state) == "a"
      assert Treedoc.prepare(Treedoc.new(), {:delete, 0}, {1, :n1}) == {:error, :invalid_index}
    end

    @tag :req3
    @tag :req4
    test "insert at the end is valid; at length + 1 and at -1 it is an error" do
      state = type(Treedoc.new(), "abc", :n1, 1)
      {end_state, _} = edit(state, {:insert, 3, "d"}, {4, :n1})
      assert Treedoc.value(end_state) == "abcd"
      assert Treedoc.prepare(state, {:insert, 4, "x"}, {4, :n1}) == {:error, :invalid_index}
      assert Treedoc.prepare(state, {:insert, -1, "x"}, {4, :n1}) == {:error, :invalid_index}
    end

    @tag :req3
    test "right neighbour is an ancestor of the left one: right child of the left" do
      # "b", then "a" at 0 (left child of b), then "x" at 1 (right child of a)
      state = type(Treedoc.new(), "b", :n1, 1)
      {state, a} = edit(state, {:insert, 0, "a"}, {2, :n1})
      {state, x} = edit(state, {:insert, 1, "x"}, {3, :n1})
      assert Treedoc.value(state) == "axb"
      assert x.pos == a.pos ++ [{1, 3, :n1}]
    end

    @tag :req3
    @tag :req8
    test "right neighbour is an ancestor, with a mini-sibling of larger disambiguator" do
      # n2 put "a" left of "b" with {5, :n2}; n1 then inserts after "a" with the smaller {2, :n1}.
      # A left child of "b" would sort before "a"; the right child of "a" lands between.
      state = type(Treedoc.new(), "b", :n1, 1)
      {state, _} = edit(state, {:insert, 0, "a"}, {5, :n2})
      {state, _} = edit(state, {:insert, 1, "x"}, {2, :n1})
      assert Treedoc.value(state) == "axb"
    end

    @tag :req3
    test "delete everything and write again at the start, middle and end, among tombstones" do
      state = type(Treedoc.new(), "abc", :n1, 1)

      state =
        Enum.reduce(4..6, state, fn seq, acc -> elem(edit(acc, {:delete, 0}, {seq, :n1}), 0) end)

      assert Treedoc.value(state) == ""
      {state, _} = edit(state, {:insert, 0, "m"}, {7, :n1})
      {state, _} = edit(state, {:insert, 0, "s"}, {8, :n1})
      {state, _} = edit(state, {:insert, 2, "e"}, {9, :n1})
      {state, _} = edit(state, {:insert, 1, "i"}, {10, :n1})
      assert Treedoc.value(state) == "sime"
      assert length(Treedoc.debug_rows(state)) == 7
    end

    @tag :req3
    test "multi-codepoint graphemes take one position each" do
      accented = "á"
      state = type(Treedoc.new(), "#{accented}ñ👍", :n1, 1)
      assert Treedoc.value(state) == "#{accented}ñ👍"
      assert length(Treedoc.debug_rows(state)) == 3
      {state, _} = edit(state, {:insert, 1, "x"}, {4, :n1})
      assert String.graphemes(Treedoc.value(state)) == [accented, "x", "ñ", "👍"]
      {state, _} = edit(state, {:delete, 3}, {5, :n1})
      assert Treedoc.value(state) == "#{accented}xñ"
    end
  end

  describe "random checks: list model and total order" do
    @tag :req3
    @tag :req7
    test "matches a plain list of graphemes over random valid and invalid edits" do
      for seed <- 1..200 do
        :rand.seed(:exsss, {seed, 11, 13})

        Enum.reduce(1..300, {Treedoc.new(), []}, fn seq, {state, model} ->
          {state, model} = model_step(state, model, seq)
          assert Treedoc.value(state) == Enum.join(model), "seed #{seed}, seq #{seq}"
          {state, model}
        end)
      end
    end

    @tag :req7
    test "compare/2 is a total order on random PosIDs" do
      for seed <- 1..200 do
        :rand.seed(:exsss, {seed, 17, 19})
        paths = random_paths(15)

        for a <- paths, b <- paths do
          ab = Treedoc.compare(a, b)
          ba = Treedoc.compare(b, a)
          assert ab == :lt == (ba == :gt), "seed #{seed}: #{inspect(a)} #{inspect(b)}"
          assert ab == :eq == (a == b), "seed #{seed}: #{inspect(a)} #{inspect(b)}"
        end

        for a <- paths,
            b <- paths,
            c <- paths,
            Treedoc.compare(a, b) == :lt and Treedoc.compare(b, c) == :lt do
          assert Treedoc.compare(a, c) == :lt, "seed #{seed}: #{inspect({a, b, c})}"
        end
      end
    end
  end

  # One random edit, valid or not, applied to both Treedoc and the model list.
  defp model_step(state, model, seq) do
    len = length(model)
    index = :rand.uniform(len + 5) - 3

    if :rand.uniform(3) == 1 do
      result = Treedoc.prepare(state, {:delete, index}, {seq, :n1})
      model_apply(state, model, result, index in 0..(len - 1)//1, &List.delete_at(&1, index))
    else
      ch = Enum.random(["a", "b", "á", "ñ", "👍"])
      result = Treedoc.prepare(state, {:insert, index, ch}, {seq, :n1})
      model_apply(state, model, result, index in 0..len//1, &List.insert_at(&1, index, ch))
    end
  end

  defp model_apply(state, model, result, valid?, change) do
    if valid? do
      assert {:ok, op} = result
      {Treedoc.effect(state, op), change.(model)}
    else
      assert result == {:error, :invalid_index}
      {state, model}
    end
  end

  # Few distinct steps, so prefixes, equal steps and equal disambiguators show up often.
  defp random_paths(count) do
    base = for _ <- 1..count, do: random_path(:rand.uniform(5) - 1)

    prefixes =
      for path <- Enum.take(base, 5), do: Enum.take(path, :rand.uniform(length(path) + 1) - 1)

    base ++ prefixes
  end

  defp random_path(length) do
    for _ <- 1..length//1, do: {:rand.uniform(2) - 1, :rand.uniform(2), Enum.random([:n1, :n2])}
  end

  # One replica edits at random on its own copy; each character must land where requested.
  defp local_session(base, node), do: elem(local_edits(base, node, 101, 8), 1)

  defp local_edits(state, node, first_seq, count) do
    {state, ops} =
      Enum.reduce(first_seq..(first_seq + count - 1), {state, []}, fn seq, {state, ops} ->
        {state, op} = random_edit(state, {seq, node})
        {state, [op | ops]}
      end)

    {state, Enum.reverse(ops)}
  end

  defp random_edit(state, dot) do
    len = String.length(Treedoc.value(state))

    if len > 0 and :rand.uniform(3) == 1 do
      edit(state, {:delete, :rand.uniform(len) - 1}, dot)
    else
      index = :rand.uniform(len + 1) - 1
      ch = Enum.random(~w(x y z w))
      {state, op} = edit(state, {:insert, index, ch}, dot)
      assert String.at(Treedoc.value(state), index) == ch
      {state, op}
    end
  end

  # One replica makes three local edits on what it has seen so far.
  defp edit_round(node, {replicas, log}) do
    r = replicas[node]
    {state, ops} = local_edits(r.state, node, r.next_seq, 3)
    r = %{r | state: state, next_seq: r.next_seq + 3, seen: MapSet.union(r.seen, MapSet.new(ops))}
    {Map.put(replicas, node, r), log ++ ops}
  end

  # Delivers a random half of the unseen operations, as far as their deletes allow.
  defp receive_some(r, log) do
    picked = Enum.filter(unseen(r, log), fn _ -> :rand.uniform(2) == 1 end)
    {state, left} = deliver(r.state, picked)
    %{r | state: state, seen: MapSet.union(r.seen, MapSet.new(picked -- left))}
  end

  defp receive_all(r, log) do
    {state, left} = deliver(r.state, unseen(r, log))
    assert left == []
    state
  end

  defp unseen(r, log), do: Enum.reject(log, &MapSet.member?(r.seen, &1))

  # Random delivery order; a delete waits until its insert has been applied.
  defp apply_in_random_order(state, ops) do
    {state, left} = deliver(state, ops)
    assert left == [], "deletes without their insert: #{inspect(left)}"
    state
  end

  # Applies in passes; returns the state and the deletes whose insert never came.
  defp deliver(state, ops) do
    {ready, waiting} =
      Enum.split_with(Enum.shuffle(ops), fn op ->
        op.op == :ins or Map.has_key?(state.chars, op.pos)
      end)

    state = Enum.reduce(ready, state, &Treedoc.effect(&2, &1))
    if ready == [] or waiting == [], do: {state, waiting}, else: deliver(state, waiting)
  end
end
