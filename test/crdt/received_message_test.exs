defmodule Crdt.ReceivedMessageTest do
  # The checks of a received message (docs/DESIGN.md DES5.1): pure, no network
  use ExUnit.Case, async: true

  alias Crdt.Causal
  alias Crdt.Treedoc

  @b :b@x
  @ins %{op: :ins, from: @b, vc: %{@b => 1}, pos: [{1, 1, @b}], ch: "x"}
  @del %{op: :del, from: @b, vc: %{@b => 2}, pos: [{1, 1, @b}]}

  defp valid?(msg), do: Treedoc.valid_op?(msg) and Causal.valid_clock?(msg)

  # An op made as Crdt.Replica makes it (DES4.1)
  defp local(doc, edit, vc, me) do
    {seq, vc} = Causal.next_local(vc, me)
    {:ok, op} = Treedoc.prepare(doc, edit, {seq, me})
    msg = Map.merge(op, %{from: me, vc: vc})
    {Treedoc.effect(doc, msg), vc, msg}
  end

  @tag :req23
  @tag :req22
  test "the ops our replicas make are valid, accents and an emoji included" do
    {doc, vc, msgs} =
      Enum.reduce(Enum.with_index(String.graphemes("añ😀z")), {Treedoc.new(), %{}, []}, fn
        {ch, i}, {doc, vc, msgs} ->
          {doc, vc, msg} = local(doc, {:insert, i, ch}, vc, :a@x)
          {doc, vc, [msg | msgs]}
      end)

    {_doc, _vc, del} = local(doc, {:delete, 1}, vc, :a@x)

    for msg <- [del | msgs], do: assert(valid?(msg))
    assert valid?(@ins) and valid?(@del)
  end

  @tag :req23
  test "valid_op?/1 rejects each broken rule of op, pos and ch" do
    for msg <- [
          %{@ins | op: :upd},
          Map.delete(@ins, :ch),
          Map.delete(@ins, :pos),
          %{@ins | pos: []},
          %{@ins | pos: :root},
          %{@ins | pos: [{1, 1, @b} | :tail]},
          %{@ins | pos: [{2, 1, @b}]},
          %{@ins | pos: [{1.0, 1, @b}]},
          %{@ins | pos: [{1, 0, @b}]},
          %{@ins | pos: [{1, "1", @b}]},
          %{@ins | pos: [{1, 1, "b@x"}]},
          %{@ins | pos: [{1, 1}]},
          %{@ins | ch: ""},
          %{@ins | ch: "ab"},
          %{@ins | ch: <<255>>},
          %{@ins | ch: ~c"x"},
          %{@del | pos: [{1, 1, @b}, {0, 0, @b}]},
          :ins,
          [@ins]
        ] do
      refute Treedoc.valid_op?(msg), inspect(msg)
    end
  end

  @tag :req23
  test "valid_op?/1 drops a step node nil, true or false, the one difference with the other implementation" do
    for node <- [nil, true, false] do
      refute Treedoc.valid_op?(%{@ins | pos: [{1, 1, node}]})
      refute Treedoc.valid_op?(%{@del | pos: [{1, 1, @b}, {0, 1, node}]})
    end
  end

  @tag :req23
  test "valid_clock?/1 rejects each broken rule of from and vc" do
    many = Map.new(1..10_001, fn i -> {:"n#{i}", 0} end)

    for msg <- [
          %{@ins | from: nil, vc: %{nil => 1}},
          %{@ins | from: true, vc: %{true => 1}},
          %{@ins | from: false, vc: %{false => 1}},
          %{@ins | from: "b@x", vc: %{"b@x" => 1}},
          %{@ins | vc: [{@b, 1}]},
          %{@ins | vc: %{}},
          %{@ins | vc: %{@b => 0}},
          %{@ins | vc: %{@b => 1, :c@x => -1}},
          %{@ins | vc: %{@b => 1, :c@x => 1.0}},
          %{@ins | vc: %{@b => 1, "c@x" => 1}},
          %{@ins | vc: Map.put(many, @b, 1)},
          Map.delete(@ins, :vc),
          Map.delete(@ins, :from)
        ] do
      refute Causal.valid_clock?(msg), inspect(msg, limit: 5)
    end

    # exactly 10 000 keys, b@x included, is still valid
    assert Causal.valid_clock?(%{@ins | vc: many |> Map.drop([:n1, :n2]) |> Map.put(@b, 1)})
  end

  # Random terms with fixed seeds: atoms, numbers, binaries, lists, steps, maps
  defp random_term(0),
    do: Enum.random([nil, true, :b@x, -1, 0, 1, 2, 1.5, "", "x", "xy", <<255>>])

  defp random_term(depth) do
    case :rand.uniform(6) do
      1 -> random_term(0)
      2 -> for _ <- 1..:rand.uniform(3), do: random_term(depth - 1)
      3 -> {random_term(depth - 1), random_term(depth - 1), random_term(depth - 1)}
      4 -> [Enum.random([0, 1, 2]) | random_term(depth - 1)]
      _ -> random_map(depth - 1)
    end
  end

  defp random_map(depth) do
    keys = Enum.take_random([:op, :from, :vc, :pos, :ch, :extra], :rand.uniform(6))
    Map.new(keys, fn k -> {k, random_value(k, depth)} end)
  end

  defp random_value(:op, _depth), do: Enum.random([:ins, :del, :upd, "ins"])

  defp random_value(:vc, depth),
    do: Map.new([{random_term(0), random_term(0)}, {@b, random_term(depth)}])

  defp random_value(:pos, depth),
    do: for(_ <- 1..:rand.uniform(3), do: {random_term(0), random_term(0), random_term(depth)})

  defp random_value(_key, depth), do: random_term(depth)

  @tag :req23
  test "1000 random terms never raise; each gives a boolean" do
    for seed <- 1..10 do
      :rand.seed(:exsss, {seed, 23, 8})

      for _ <- 1..100 do
        term = random_term(3)
        assert is_boolean(Treedoc.valid_op?(term)), inspect(term)
        assert is_boolean(Causal.valid_clock?(term)), inspect(term)
      end
    end
  end
end
