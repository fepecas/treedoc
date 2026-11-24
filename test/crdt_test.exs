defmodule CrdtTest do
  # Registers a replica as Crdt.Replica, so it does not run async
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # Every replica keeps its history file in a temporary folder
  @moduletag :tmp_dir

  alias Crdt.Replica

  @me :a@x
  @b :b@x

  # Two inserts from b@x: b2 goes after b1 and depends on it
  @b1 %{op: :ins, from: @b, vc: %{@b => 1}, pos: [{1, 1, @b}], ch: "x"}
  @b2 %{op: :ins, from: @b, vc: %{@b => 2}, pos: [{1, 1, @b}, {1, 2, @b}], ch: "y"}

  @loaded "[a@x] history loaded: 0 ops\n"

  # The replica's notices, also those of init, go to a StringIO. The test
  # supervisor starts with the first start_supervised (one per test here)
  # and its children take the group leader the test process has then.
  defp start_quiet(child_spec) do
    {:ok, io} = StringIO.open("")
    group_leader = Process.group_leader()
    Process.group_leader(self(), io)

    try do
      {start_supervised!(child_spec), io}
    after
      Process.group_leader(self(), group_leader)
    end
  end

  @tag :req19
  test "without a replica every function returns {:error, :no_replica}" do
    refute Process.whereis(Replica)

    for result <- [
          Crdt.insert(0, "a"),
          Crdt.delete(0),
          Crdt.delete(0, 2),
          Crdt.text(),
          Crdt.status(),
          Crdt.history(),
          Crdt.history(:all),
          Crdt.debug()
        ] do
      assert result == {:error, :no_replica}
    end
  end

  describe "replica without network" do
    # No connected nodes, so nothing is sent; notices go to a StringIO
    setup %{tmp_dir: dir} do
      {pid, io} = start_quiet({Replica, me: @me, nodes: [], data_dir: dir, name: Replica})
      %{pid: pid, io: io}
    end

    defp notices(io) do
      # a call after the casts makes sure they were handled
      Crdt.text()
      {_, out} = StringIO.contents(io)
      out
    end

    defp remote(msg), do: GenServer.cast(Replica, {:remote, msg})

    defp printed(fun), do: capture_io(fun) |> String.split("\n", trim: true)

    @tag :req3
    @tag :req20
    test "insert of several characters leaves them in order", %{pid: pid} do
      assert Crdt.insert(0, "hola") == :ok
      assert Crdt.insert(2, "XY") == :ok
      assert Crdt.text() == "hoXYla"
      assert :sys.get_state(pid).vc == %{@me => 6}
    end

    @tag :req3
    test "each grapheme takes one position, also with several code points" do
      assert Crdt.insert(0, "éx😀") == :ok
      assert length(printed(&Crdt.debug/0)) == 3
      assert Crdt.insert(2, "-") == :ok
      assert Crdt.text() == "éx-😀"
    end

    @tag :req3
    @tag :req4
    test "insert at 0 and at the length is valid; length + 1 and -1 are not", %{pid: pid} do
      :ok = Crdt.insert(0, "ab")
      assert Crdt.insert(0, "<") == :ok
      assert Crdt.insert(3, ">") == :ok
      assert Crdt.text() == "<ab>"
      before = :sys.get_state(pid)

      for index <- [5, -1, 1.0, "1", nil] do
        assert Crdt.insert(index, "z") == {:error, :invalid_index}
        assert Crdt.insert(index, "") == {:error, :invalid_index}
      end

      assert :sys.get_state(pid) == before
    end

    @tag :req4
    test "insert of an empty text at a valid index succeeds with no operations", %{pid: pid} do
      :ok = Crdt.insert(0, "ab")
      before = :sys.get_state(pid)
      assert Crdt.insert(2, "") == :ok
      assert :sys.get_state(pid) == before
    end

    @tag :req4
    test "insert of something that is not a string fails in the caller" do
      assert_raise FunctionClauseError, fn -> apply(Crdt, :insert, [0, ~c"ab"]) end
      assert Crdt.text() == ""
    end

    @tag :req3
    @tag :req17
    test "delete one and several characters; history shows the deleted ones" do
      :ok = Crdt.insert(0, "hola")
      assert Crdt.delete(0) == :ok
      assert Crdt.delete(1, 2) == :ok
      assert Crdt.text() == "o"

      assert Enum.take(printed(fn -> Crdt.history(:all) end), -3) == [
               ~s(op 5 from a@x: del "h"),
               ~s(op 6 from a@x: del "l"),
               ~s(op 7 from a@x: del "a")
             ]
    end

    @tag :req4
    test "invalid deletes change nothing: text, clock and history", %{pid: pid} do
      assert Crdt.delete(0) == {:error, :invalid_index}
      assert Crdt.delete(0, 0) == {:error, :invalid_index}
      :ok = Crdt.insert(0, "hola")
      before = :sys.get_state(pid)

      # one past the end, count past the end by one, negative, not integers
      for {index, count} <- [{4, 1}, {1, 4}, {0, 5}, {0, -1}, {-1, 1}, {1.0, 1}, {0, 1.0}] do
        assert Crdt.delete(index, count) == {:error, :invalid_index}
      end

      assert :sys.get_state(pid) == before
    end

    @tag :req4
    test "delete with count 0 at a valid index succeeds with no operations", %{pid: pid} do
      :ok = Crdt.insert(0, "ab")
      before = :sys.get_state(pid)
      assert Crdt.delete(1, 0) == :ok
      assert :sys.get_state(pid) == before
    end

    @tag :req17
    test "local edits print no notice", %{io: io} do
      :ok = Crdt.insert(0, "ab")
      :ok = Crdt.delete(0)
      assert notices(io) == @loaded
    end

    @tag :req20
    test "a remote op that arrives during a multi-character insert does not split it",
         %{pid: pid} do
      :ok = Crdt.insert(0, "m")
      [m] = :sys.get_state(pid).history
      # left child of "m", written by b@x after seeing it
      y = %{op: :ins, from: @b, vc: %{@me => 1, @b => 1}, pos: m.pos ++ [{0, 1, @b}], ch: "y"}

      :sys.suspend(pid)
      task = Task.async(fn -> Crdt.insert(1, "undo") end)
      wait_for_mailbox(pid)
      remote(y)
      :sys.resume(pid)

      assert Task.await(task) == :ok
      assert Crdt.text() == "ymundo"
    end

    @tag :req6
    @tag :req9
    @tag :req17
    test "a remote op that arrives before its dependency waits, then both apply in order",
         %{io: io} do
      remote(@b2)
      assert notices(io) == @loaded <> "[a@x] waiting op 2 from b@x (missing: b@x up to 1)\n"
      assert Crdt.text() == ""

      assert Enum.take(printed(&Crdt.status/0), -2) == [
               "buffer: 1 ops",
               "waiting op 2 from b@x (missing: b@x up to 1)"
             ]

      remote(@b1)
      assert Crdt.text() == "xy"

      assert printed(fn -> Crdt.history(:all) end) == [
               ~s(op 1 from b@x: ins "x"),
               ~s(op 2 from b@x: ins "y")
             ]

      assert notices(io) =~
               ~s([a@x] applied op 1 from b@x: ins "x"\n) <>
                 ~s([a@x] applied op 2 from b@x: ins "y"\n)
    end

    @tag :req6
    @tag :req17
    test "a remote delete shows the deleted character", %{io: io} do
      remote(@b1)
      remote(%{op: :del, from: @b, vc: %{@b => 2}, pos: @b1.pos})
      assert Crdt.text() == ""
      assert notices(io) =~ ~s([a@x] applied op 2 from b@x: del "x")
      assert printed(&Crdt.debug/0) == [~s("x" #{inspect(@b1.pos)} deleted)]
    end

    @tag :req10
    test "a remote duplicate does not change the history", %{pid: pid, io: io} do
      remote(@b1)
      before = :sys.get_state(pid)
      remote(@b1)
      assert notices(io) =~ "[a@x] duplicate dropped: op 1 from b@x"
      assert :sys.get_state(pid) == before
    end

    @tag :req10
    @tag :req11
    test "an echo of an own op (from == me) is dropped as a duplicate", %{pid: pid, io: io} do
      :ok = Crdt.insert(0, "h")
      before = :sys.get_state(pid)
      [own] = before.history
      remote(own)
      assert notices(io) == @loaded <> "[a@x] duplicate dropped: op 1 from a@x\n"
      assert :sys.get_state(pid) == before
    end

    @tag :req17
    test "history shows the last 10 ops; history(:all) shows every one in order" do
      :ok = Crdt.insert(0, "abcdefghij")
      assert length(printed(&Crdt.history/0)) == 10
      refute hd(printed(&Crdt.history/0)) =~ "earlier"

      :ok = Crdt.insert(10, "kl")
      last = printed(&Crdt.history/0)
      assert length(last) == 11
      assert hd(last) == "... 2 earlier ops"
      assert Enum.at(last, 1) == ~s(op 3 from a@x: ins "c")
      assert List.last(last) == ~s(op 12 from a@x: ins "l")

      all = printed(fn -> Crdt.history(:all) end)
      assert length(all) == 12
      assert hd(all) == ~s(op 1 from a@x: ins "a")
    end

    @tag :req17
    test "status shows node, table, history file, connected nodes, clock and history size",
         %{tmp_dir: dir} do
      :ok = Crdt.insert(0, "ab")

      assert capture_io(fn -> assert Crdt.status() == :ok end) ==
               """
               node: a@x
               nodes file: option :nodes
               history file: #{Path.join(dir, "a.jsonl")}
               table: []
               discovery: off
               connected: none
               clock: #{inspect(%{@me => 2})}
               history: 2 ops
               buffer: 0 ops
               """
    end
  end

  describe "received messages (docs/DESIGN.md DES5.1)" do
    setup %{tmp_dir: dir} do
      {pid, io} = start_quiet({Replica, me: @me, nodes: [], data_dir: dir, name: Replica})
      :ok = Crdt.insert(0, "ab")
      %{pid: pid, io: io, history_file: Path.join(dir, "a.jsonl")}
    end

    defp kept(pid), do: Map.take(:sys.get_state(pid), [:doc, :vc, :buffer, :history])

    defp last_notice(io) do
      Crdt.text()
      {_, out} = StringIO.contents(io)
      out |> String.split("\n", trim: true) |> List.last()
    end

    defp dropped(term),
      do: "[a@x] malformed message dropped: " <> inspect(term, limit: 5, printable_limit: 40)

    @bad_remote [
      %{},
      :x,
      %{op: :upd, from: @b, vc: %{@b => 1}, pos: [{1, 1, @b}]},
      %{op: :ins, from: @b, vc: %{@b => 1}, pos: [{1, 1, @b}]},
      %{op: :ins, from: @b, vc: %{@b => 1}, pos: [{1, 1, @b}], ch: "xy"},
      %{op: :ins, from: @b, vc: %{@b => 1}, pos: [{1, 1, @b}], ch: <<255>>},
      %{op: :ins, from: @b, vc: %{@b => 1}, pos: [], ch: "x"},
      %{op: :ins, from: @b, vc: %{@b => 1}, pos: [{2, 1, @b}], ch: "x"},
      %{op: :ins, from: @b, vc: %{@b => 1}, pos: [{1, 1, nil}], ch: "x"},
      # the old code dropped this one as a duplicate, and applied the next one
      %{op: :ins, from: @b, vc: %{@b => 0}, pos: [{1, 1, @b}], ch: "x"},
      %{op: :ins, from: nil, vc: %{nil => 1}, pos: [{1, 1, @b}], ch: "x"},
      %{op: :ins, from: @b, vc: %{@b => 1, "c" => 1}, pos: [{1, 1, @b}], ch: "x"},
      %{op: :del, from: @b, vc: %{@b => -1}, pos: [{1, 1, @b}]}
    ]

    @tag :req23
    test "each malformed or unknown message prints the notice and changes nothing", %{
      pid: pid,
      io: io,
      history_file: file
    } do
      before = kept(pid)
      bytes = File.read!(file)

      for msg <- @bad_remote do
        GenServer.cast(Replica, {:remote, msg})
        assert last_notice(io) == dropped({:remote, msg})
      end

      for msg <- [{:hello, %{}}, {:hello, "b@x"}, :unknown, {:remote, @b1, :extra}] do
        GenServer.cast(Replica, msg)
        assert last_notice(io) == dropped(msg)
      end

      for msg <- [:unknown, {:nodeup}, {:remote, @b1}] do
        send(pid, msg)
        assert last_notice(io) == dropped(msg)
      end

      for request <- [:unknown, {:insert, 0, 123}, {:history, :last}] do
        assert GenServer.call(Replica, request) == {:error, :unknown}
        assert last_notice(io) == dropped(request)
      end

      {_, out} = StringIO.contents(io)
      refute out =~ "hello from"
      assert Process.whereis(Replica) == pid
      assert kept(pid) == before
      assert File.read!(file) == bytes

      # a valid op after them is applied
      GenServer.cast(Replica, {:remote, @b1})
      assert Crdt.text() == "abx"
    end

    @tag :req23
    test "random terms with a fixed seed are dropped and the replica stays", %{pid: pid} do
      :rand.seed(:exsss, {23, 8, 2026})
      before = kept(pid)

      for _ <- 1..300 do
        term = random_term(3)
        GenServer.cast(Replica, {:remote, term})
        GenServer.cast(Replica, term)
        send(pid, term)
      end

      Crdt.text()
      assert Process.whereis(Replica) == pid
      assert kept(pid) == before
    end

    # Never a valid op: the maps lack :from or have a bad :vc
    defp random_term(0), do: Enum.random([nil, true, @b, -1, 0, 1, 1.5, "", "x", <<255>>])

    defp random_term(depth) do
      case :rand.uniform(4) do
        1 -> random_term(0)
        2 -> for _ <- 1..:rand.uniform(3), do: random_term(depth - 1)
        3 -> {random_term(depth - 1), random_term(depth - 1), random_term(depth - 1)}
        4 -> %{op: Enum.random([:ins, :del]), pos: random_term(depth - 1), vc: random_term(0)}
      end
    end

    @tag :req23
    test "a long term prints one short notice", %{io: io} do
      GenServer.cast(Replica, {:remote, List.duplicate(String.duplicate("x", 10_000), 50)})
      # five strings of 40 characters at most, not 50 of 10 000
      assert String.length(last_notice(io)) < 300
    end

    @tag :req23
    test "extra keys are removed before the op is applied, kept and stored", %{pid: pid} do
      GenServer.cast(Replica, {:remote, Map.put(@b1, :extra, 1)})
      del = %{op: :del, from: @b, vc: %{@b => 2}, pos: @b1.pos}
      GenServer.cast(Replica, {:remote, Map.put(del, :ch, "z")})
      Crdt.text()
      assert Enum.take(:sys.get_state(pid).history, -2) == [@b1, del]
    end

    @tag :req22
    @tag :req23
    test "an insert of the other implementation's shape lands in the right place" do
      # several chars in one call, balanced: "b" sits between, "a" and "c" are its children,
      # and the first op goes through the step {1, 2, c} of an op not applied yet
      c = :c@x
      a = %{op: :ins, from: c, vc: %{c => 1}, pos: [{1, 2, c}, {0, 1, c}], ch: "1"}
      b = %{op: :ins, from: c, vc: %{c => 2}, pos: [{1, 2, c}], ch: "2"}
      d = %{op: :ins, from: c, vc: %{c => 3}, pos: [{1, 2, c}, {1, 3, c}], ch: "3"}
      for op <- [a, b, d], do: GenServer.cast(Replica, {:remote, op})
      assert Crdt.text() == "ab123"
    end
  end

  describe "node table from NODES_FILE" do
    setup do
      on_exit(fn -> System.delete_env("NODES_FILE") end)
    end

    @tag :req14
    @tag :req17
    test "status shows the nodes file and the table without me", %{tmp_dir: dir} do
      path = Path.join(dir, "nodes.txt")
      File.write!(path, "a@x\nb@x\n")
      System.put_env("NODES_FILE", path)
      start_quiet({Replica, me: @me, data_dir: dir, name: Replica})

      lines = String.split(capture_io(&Crdt.status/0), "\n")
      assert "nodes file: #{path}" in lines
      assert "table: #{inspect([@b])}" in lines
    end

    @tag :req14
    @tag :req19
    test "a missing nodes file: no replica, a clear message, the caller keeps running",
         %{tmp_dir: dir} do
      System.put_env("NODES_FILE", "missing_nodes.txt")

      out =
        capture_io(fn ->
          assert Replica.start_link(me: @me, data_dir: dir, name: Replica) == :ignore
        end)

      assert out ==
               "[a@x] cannot read nodes file missing_nodes.txt (no such file or directory): " <>
                 "replica not started. Fix NODES_FILE and restart the node.\n"

      assert Crdt.text() == {:error, :no_replica}
      # step 0 comes before step 1 (docs/DESIGN.md DES4.4): the history file is not created
      assert File.ls!(dir) == []
    end
  end

  @tag :req12
  @tag :req17
  @tag :req15
  test "nodeup, nodedown and hello count for every node, also outside the table",
       %{tmp_dir: dir} do
    # the table includes me, which is skipped when connecting
    opts = [me: @me, nodes: [@me, @b], data_dir: dir, name: :with_table]
    {pid, io} = start_quiet(Supervisor.child_spec({Replica, opts}, id: :with_table))

    for n <- [@b, :z@x] do
      send(pid, {:nodeup, n})
      send(pid, {:nodedown, n})
      GenServer.cast(pid, {:hello, n})
    end

    :sys.get_state(pid)

    assert StringIO.contents(io) ==
             {"",
              """
              [a@x] history loaded: 0 ops
              [a@x] connected b@x: resending history (0 ops)
              [a@x] disconnected b@x
              [a@x] hello from b@x: resending history (0 ops)
              [a@x] connected z@x: resending history (0 ops)
              [a@x] disconnected z@x
              [a@x] hello from z@x: resending history (0 ops)
              """}
  end

  defp wait_for_mailbox(pid) do
    if Process.info(pid, :message_queue_len) == {:message_queue_len, 0} do
      Process.sleep(1)
      wait_for_mailbox(pid)
    end
  end
end
