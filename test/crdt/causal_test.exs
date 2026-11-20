defmodule Crdt.CausalTest do
  use ExUnit.Case, async: true

  alias Crdt.Causal
  alias Crdt.Treedoc

  # A message with a label; the test doc is the list of applied labels.
  defp msg(from, vc, label), do: %{from: from, vc: vc, label: label}

  defp log_apply(doc, msg), do: doc ++ [msg.label]

  defp empty, do: %{vc: %{}, buffer: [], doc: []}

  # Receives the messages in order and returns the final state and every event.
  defp receive_all(state, msgs) do
    Enum.reduce(msgs, {state, []}, fn m, {st, evs} ->
      {st, new} = Causal.receive_message(st, m, &log_apply/2)
      {st, evs ++ new}
    end)
  end

  defp labels(events), do: Enum.map(events, fn ev -> {elem(ev, 0), elem(ev, 1).label} end)

  describe "next_local/2 (docs/DESIGN.md DES4.1)" do
    @tag :req4
    @tag :req13
    test "a node missing from the clock starts at 1" do
      assert Causal.next_local(%{n2: 4}, :n1) == {1, %{n1: 1, n2: 4}}
    end

    @tag :req4
    @tag :req13
    test "a known node gets the next seq; the input clock is unchanged" do
      vc = %{n1: 2, n2: 4}
      assert Causal.next_local(vc, :n1) == {3, %{n1: 3, n2: 4}}
      assert Causal.next_local(vc, :n1) == {3, %{n1: 3, n2: 4}}
      assert vc == %{n1: 2, n2: 4}
    end
  end

  describe "duplicate?/2 and deliverable?/2 (docs/DESIGN.md DES4.2)" do
    @tag :req9
    @tag :req10
    test "sender entry: equal, next and with a gap" do
      vc = %{a: 2, b: 1}
      equal = msg(:a, %{a: 2, b: 1}, :x)
      next = msg(:a, %{a: 3, b: 1}, :x)
      gap = msg(:a, %{a: 4, b: 1}, :x)

      assert Causal.duplicate?(vc, equal)
      refute Causal.deliverable?(vc, equal)
      refute Causal.duplicate?(vc, next)
      assert Causal.deliverable?(vc, next)
      refute Causal.duplicate?(vc, gap)
      refute Causal.deliverable?(vc, gap)
      assert Causal.duplicate?(vc, msg(:a, %{a: 1}, :x))
    end

    @tag :req9
    test "other node entry: equal is fine, greater must wait" do
      vc = %{a: 2, b: 1}
      assert Causal.deliverable?(vc, msg(:a, %{a: 3, b: 1}, :x))
      refute Causal.deliverable?(vc, msg(:a, %{a: 3, b: 2}, :x))
    end

    @tag :req9
    @tag :req10
    test "missing keys count as 0, in vc and in m" do
      # sender missing in vc
      assert Causal.deliverable?(%{}, msg(:a, %{a: 1}, :x))
      refute Causal.duplicate?(%{}, msg(:a, %{a: 1}, :x))
      # other node missing in m
      assert Causal.deliverable?(%{a: 2, b: 1}, msg(:a, %{a: 3}, :x))
      # other node missing in vc
      refute Causal.deliverable?(%{a: 2}, msg(:a, %{a: 3, c: 1}, :x))
      # sender missing in m: seq 0 is always a duplicate
      assert Causal.duplicate?(%{}, msg(:a, %{b: 1}, :x))
    end
  end

  describe "receive_message/3 (docs/DESIGN.md DES4.2)" do
    @tag :req9
    test "applies a message in order" do
      {st, events} = Causal.receive_message(empty(), msg(:a, %{a: 1}, :a1), &log_apply/2)
      assert labels(events) == [applied: :a1]
      assert st == %{vc: %{a: 1}, buffer: [], doc: [:a1]}
    end

    @tag :req9
    test "a message that arrives before its dependency waits and is applied right after it" do
      a1 = msg(:a, %{a: 1}, :a1)
      b1 = msg(:b, %{a: 1, b: 1}, :b1)

      {st, events} = Causal.receive_message(empty(), b1, &log_apply/2)
      assert events == [{:waiting, b1, %{a: 1}}]
      assert st.buffer == [b1] and st.doc == [] and st.vc == %{}

      {st, events} = Causal.receive_message(st, a1, &log_apply/2)
      assert labels(events) == [applied: :a1, applied: :b1]
      assert st == %{vc: %{a: 1, b: 1}, buffer: [], doc: [:a1, :b1]}
    end

    @tag :req9
    test "a dependency chain that arrives backwards is applied in order in one call" do
      chain = [
        msg(:a, %{a: 1}, :a1),
        msg(:b, %{a: 1, b: 1}, :b1),
        msg(:a, %{a: 2, b: 1}, :a2),
        msg(:a, %{a: 3, b: 1}, :a3),
        msg(:b, %{a: 3, b: 2}, :b2)
      ]

      [first | rest] = chain
      {st, _} = receive_all(empty(), Enum.reverse(rest))
      assert st.doc == [] and length(st.buffer) == 4

      {st, events} = Causal.receive_message(st, first, &log_apply/2)
      assert labels(events) == Enum.map(chain, &{:applied, &1.label})
      assert st == %{vc: %{a: 3, b: 2}, buffer: [], doc: [:a1, :b1, :a2, :a3, :b2]}
    end

    @tag :req9
    @tag :req17
    test "waiting reports the last seq missing from each node" do
      # gap from the sender itself: m[i] - 1
      a3 = msg(:a, %{a: 3}, :a3)
      assert {_, [{:waiting, ^a3, %{a: 2}}]} = Causal.receive_message(empty(), a3, &log_apply/2)

      # dependency on another node only: the sender is not listed
      st = %{empty() | vc: %{a: 1}}
      b1 = msg(:b, %{a: 2, b: 1}, :b1)
      assert {_, [{:waiting, ^b1, %{a: 2}}]} = Causal.receive_message(st, b1, &log_apply/2)

      # both at once; keys already covered by vc are not listed
      st = %{empty() | vc: %{a: 1, c: 5}}
      b3 = msg(:b, %{a: 4, b: 3, c: 5}, :b3)

      assert {_, [{:waiting, ^b3, %{a: 4, b: 2}}]} =
               Causal.receive_message(st, b3, &log_apply/2)
    end
  end

  describe "duplicates (REQ10)" do
    @tag :req10
    test "a duplicate received directly is dropped and changes nothing" do
      a1 = msg(:a, %{a: 1}, :a1)
      {st, _} = Causal.receive_message(empty(), a1, &log_apply/2)
      assert Causal.receive_message(st, a1, &log_apply/2) == {st, [{:duplicate, a1}]}
    end

    @tag :req10
    test "a message received twice while waiting is buffered once and applied once" do
      a1 = msg(:a, %{a: 1}, :a1)
      a2 = msg(:a, %{a: 2}, :a2)

      {st, events} = receive_all(empty(), [a2, a2])
      assert events == [{:waiting, a2, %{a: 1}}, {:waiting, a2, %{a: 1}}]
      assert st.buffer == [a2]

      {st, events} = Causal.receive_message(st, a1, &log_apply/2)
      assert labels(events) == [applied: :a1, applied: :a2]
      assert st == %{vc: %{a: 2}, buffer: [], doc: [:a1, :a2]}
    end

    @tag :req10
    test "a buffered copy of an op already applied by another path is dropped" do
      # b1 was applied while a copy stayed in the buffer
      b1 = msg(:b, %{b: 1}, :b1)
      st = %{vc: %{b: 1}, buffer: [b1], doc: [:b1]}

      {st, events} = Causal.receive_message(st, msg(:a, %{a: 1}, :a1), &log_apply/2)
      assert labels(events) == [applied: :a1, duplicate: :b1]
      assert st == %{vc: %{a: 1, b: 1}, buffer: [], doc: [:b1, :a1]}
    end
  end

  describe "simulation with Treedoc (docs/DESIGN.md DES4.3)" do
    @nodes [:n1, :n2, :n3]

    defp new_world(alive) do
      reps = Map.new(@nodes, &{&1, %{vc: %{}, buffer: [], doc: Treedoc.new()}})
      %{reps: reps, pool: [], alive: alive, stats: %{applied: 0, waiting: 0, duplicate: 0}}
    end

    # Local edit at node me, as the replica does it (docs/DESIGN.md DES4.1).
    defp local_edit(w, me) do
      rep = w.reps[me]
      len = String.length(Treedoc.value(rep.doc))

      edit =
        if len > 0 and :rand.uniform(3) == 1,
          do: {:delete, :rand.uniform(len) - 1},
          else: {:insert, :rand.uniform(len + 1) - 1, Enum.random(["a", "b", "c"])}

      {seq, vc} = Causal.next_local(rep.vc, me)
      {:ok, op} = Treedoc.prepare(rep.doc, edit, {seq, me})
      rep = %{rep | doc: Treedoc.effect(rep.doc, op), vc: vc}
      {%{w | reps: Map.put(w.reps, me, rep)}, Map.merge(op, %{from: me, vc: vc})}
    end

    # Sends to a random non-empty subset of the other live nodes.
    defp random_edit(w) do
      me = Enum.random(w.alive)
      {w, m} = local_edit(w, me)
      others = w.alive -- [me]
      targets = Enum.take_random(others, :rand.uniform(length(others)))
      %{w | pool: w.pool ++ for(k <- targets, do: {k, m})}
    end

    # Delivers a random packet; one time in four it stays in the pool (duplicate).
    defp deliver(w) do
      i = :rand.uniform(length(w.pool)) - 1
      {to, m} = Enum.at(w.pool, i)
      pool = if :rand.uniform(4) == 1, do: w.pool, else: List.delete_at(w.pool, i)
      {rep, events} = Causal.receive_message(w.reps[to], m, &Treedoc.effect/2)
      # DES4.3: forward once every op applied from the network
      fwd = for {:applied, op} <- events, k <- w.alive, k != to, do: {k, op}
      stats = Enum.reduce(events, w.stats, &Map.update!(&2, elem(&1, 0), fn n -> n + 1 end))
      %{w | reps: Map.put(w.reps, to, rep), pool: pool ++ fwd, stats: stats}
    end

    defp run(w, steps) do
      w =
        Enum.reduce(1..steps, w, fn _, w ->
          if w.pool == [] or :rand.uniform(5) <= 2, do: random_edit(w), else: deliver(w)
        end)

      flush(w)
    end

    defp flush(%{pool: []} = w), do: w
    defp flush(w), do: w |> deliver() |> flush()

    defp assert_converged(w) do
      [first | rest] = Enum.map(w.alive, &w.reps[&1])

      for rep <- rest,
          do: assert({Treedoc.value(rep.doc), rep.vc} == {Treedoc.value(first.doc), first.vc})

      for rep <- [first | rest], do: assert(rep.buffer == [])
      first
    end

    @tag :req7
    @tag :req9
    @tag :req10
    @tag :req11
    test "three replicas converge with disorder, duplicates and forwarding (100 seeds)" do
      totals =
        Enum.reduce(1..100, %{applied: 0, waiting: 0, duplicate: 0}, fn seed, acc ->
          :rand.seed(:exsss, {seed, seed, seed})
          w = run(new_world(@nodes), 60)
          rep = assert_converged(w)
          assert Enum.sum(Map.values(rep.vc)) > 0
          Map.merge(acc, w.stats, fn _, a, b -> a + b end)
        end)

      # the runs really hit every branch of DES4.2
      assert totals.applied > 0 and totals.waiting > 0 and totals.duplicate > 0
    end

    @tag :req7
    @tag :req11
    test "an op sent to one node by an origin that then vanishes reaches everyone (100 seeds)" do
      for seed <- 1..100 do
        :rand.seed(:exsss, {seed, seed, seed})
        w = new_world(@nodes)
        k = :rand.uniform(5)

        # n1 edits, sends only to n2 and disappears
        w =
          Enum.reduce(1..k, w, fn _, w ->
            {w, m} = local_edit(w, :n1)
            %{w | pool: w.pool ++ [{:n2, m}]}
          end)

        rep = run(%{w | alive: [:n2, :n3]}, 30) |> assert_converged()
        assert rep.vc[:n1] == k
        for {pos, ch} <- w.reps[:n1].doc.chars, do: assert(rep.doc.chars[pos] == ch)
      end
    end
  end
end
