defmodule CrdtHistoryTest do
  # The history file (docs/DESIGN.md DES4.5). Registers Crdt.Replica, so it does not run async.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Crdt.LogFormat
  alias Crdt.Replica

  @moduletag :tmp_dir

  @me :a@x
  @b :b@x
  @b1 %{op: :ins, from: @b, vc: %{@b => 1}, pos: [{1, 1, @b}], ch: "x"}
  @b2 %{op: :ins, from: @b, vc: %{@b => 2}, pos: [{1, 1, @b}, {1, 2, @b}], ch: "y"}

  # Own ops a1 "h", a2 "ñ", a3 "c", each the right child of the previous one
  @a1 %{op: :ins, from: @me, vc: %{@me => 1}, pos: [{1, 1, @me}], ch: "h"}
  @a2 %{op: :ins, from: @me, vc: %{@me => 2}, pos: [{1, 1, @me}, {1, 2, @me}], ch: "ñ"}
  @a3 %{
    op: :ins,
    from: @me,
    vc: %{@me => 3},
    pos: [{1, 1, @me}, {1, 2, @me}, {1, 3, @me}],
    ch: "c"
  }

  defp path(dir), do: Path.join(dir, "a.jsonl")

  defp lines(msgs), do: Enum.map_join(msgs, &LogFormat.to_json_line/1)

  # Starts the replica; its notices, also those of init, go to `io`. The test
  # supervisor starts with the first start_supervised and its children take
  # the group leader the test process has then, so a restart reuses `io`.
  defp start(dir) do
    {:ok, io} = StringIO.open("")
    start(dir, io)
  end

  defp start(dir, io, me \\ @me) do
    group_leader = Process.group_leader()
    Process.group_leader(self(), io)

    try do
      start_supervised!({Replica, me: me, nodes: [], data_dir: dir, name: Replica})
    after
      Process.group_leader(self(), group_leader)
    end

    io
  end

  # Only the notices printed after the restart stay in `io`
  defp restart(dir, io) do
    :ok = stop_supervised(Replica)
    StringIO.flush(io)
    start(dir, io)
  end

  defp notices(io) do
    # a call after the casts makes sure they were handled
    Crdt.text()
    {_, out} = StringIO.contents(io)
    out
  end

  defp remote(msg), do: GenServer.cast(Replica, {:remote, msg})

  defp file_ops(dir) do
    for line <- String.split(File.read!(path(dir)), "\n", trim: true) do
      {:ok, msg} = LogFormat.from_json_line(line)
      msg
    end
  end

  defp history_all, do: capture_io(fn -> Crdt.history(:all) end)

  @tag :req13
  test "first start without a file", %{tmp_dir: dir} do
    io = start(dir)
    assert Crdt.text() == ""
    assert notices(io) == "[a@x] history loaded: 0 ops\n"
    assert capture_io(&Crdt.status/0) =~ "history: 0 ops"
  end

  @tag :req13
  test "first start with an empty file", %{tmp_dir: dir} do
    File.write!(path(dir), "")
    io = start(dir)
    assert Crdt.text() == ""
    assert notices(io) == "[a@x] history loaded: 0 ops\n"
  end

  @tag :req13
  @tag :req18
  test "reload: same text, clock and history, and loading writes nothing", %{tmp_dir: dir} do
    io = start(dir)
    :ok = Crdt.insert(0, "hola")
    :ok = Crdt.delete(0)
    remote(@b1)
    text = Crdt.text()
    vc = :sys.get_state(Replica).vc
    history = history_all()
    file = File.read!(path(dir))
    assert text == "olax"

    restart(dir, io)
    assert notices(io) == "[a@x] history loaded: 6 ops\n"
    assert Crdt.text() == text
    assert :sys.get_state(Replica).vc == vc
    assert history_all() == history
    assert File.read!(path(dir)) == file
  end

  @tag :req13
  test "after a reload the next local op uses seq = vc[me] + 1", %{tmp_dir: dir} do
    io = start(dir)
    :ok = Crdt.insert(0, "hola")
    :ok = Crdt.delete(0)
    restart(dir, io)
    :ok = Crdt.insert(0, "z")
    last = List.last(file_ops(dir))
    assert last.vc[@me] == 6
    assert last.pos |> List.last() |> elem(1) == 6
  end

  # DES4.5: the incomplete last line is reported, cut and the rest is loaded
  defp check_incomplete(dir, good_msgs, bad) do
    good = lines(good_msgs)
    File.write!(path(dir), good <> bad)

    io = start(dir)

    assert notices(io) ==
             "[a@x] history: last line was incomplete; removed from file\n" <>
               "[a@x] history loaded: #{length(good_msgs)} ops\n"

    assert File.read!(path(dir)) == good
    assert Crdt.text() == Enum.map_join(good_msgs, & &1.ch)

    :ok = Crdt.insert(0, "z")
    restart(dir, io)
    assert notices(io) == "[a@x] history loaded: #{length(good_msgs) + 1} ops\n"
    assert Crdt.text() == "z" <> Enum.map_join(good_msgs, & &1.ch)
  end

  @tag :req13
  @tag :req19
  test "(a) last line without a newline", %{tmp_dir: dir} do
    check_incomplete(dir, [@a1], ~s({"op":"ins","from":"a@x"))
  end

  @tag :req13
  @tag :req19
  test "(b) last line with a newline but invalid JSON", %{tmp_dir: dir} do
    check_incomplete(dir, [@a1], "not json at all\n")
  end

  @tag :req13
  @tag :req19
  test "(c) the line before the cut has an ñ: the offset counts bytes", %{tmp_dir: dir} do
    check_incomplete(dir, [@a1, @a2], ~s({"op":"del","from":"a@))
  end

  @tag :req19
  test "a damaged line in the middle: :ignore, path and line, file untouched",
       %{tmp_dir: dir} do
    content = lines([@a1]) <> "garbage\n" <> lines([@a3])
    File.write!(path(dir), content)

    out =
      capture_io(fn ->
        assert Replica.start_link(me: @me, nodes: [], data_dir: dir, name: Replica) == :ignore
      end)

    assert out =~ "[a@x] history corrupted at line 2 of #{path(dir)}: replica not started."
    assert out =~ "Delete that file and restart the node"
    assert Crdt.text() == {:error, :no_replica}
    assert File.read!(path(dir)) == content
  end

  @tag :req13
  test "a new IP in the node name: same file, same text, new ops from 1 under the new name",
       %{tmp_dir: dir} do
    io = start(dir)
    :ok = Crdt.insert(0, "ab")
    :ok = stop_supervised(Replica)
    StringIO.flush(io)

    # same name part "a", another host: the file is still a.jsonl
    new_me = :"a@10.0.0.9"
    start(dir, io, new_me)
    assert notices(io) == "[a@10.0.0.9] history loaded: 2 ops
"
    assert Crdt.text() == "ab"

    :ok = Crdt.insert(2, "c")
    assert Crdt.text() == "abc"
    assert :sys.get_state(Replica).vc == %{@me => 2, new_me => 1}
    assert [_, _, %{from: ^new_me, vc: %{^new_me => 1}}] = file_ops(dir)
  end

  # DES4.5, DES6: start_link output when the history file cannot be read or opened
  defp start_ignored(data_dir) do
    capture_io(fn ->
      assert Replica.start_link(me: @me, nodes: [], data_dir: data_dir, name: Replica) ==
               :ignore
    end)
  end

  @tag :req13
  @tag :req19
  test "data_dir does not exist: :ignore, a message with the path, no folder created",
       %{tmp_dir: dir} do
    missing = Path.join(dir, "missing")
    file = Path.join(missing, "a.jsonl")

    assert start_ignored(missing) ==
             "[a@x] cannot open history file #{file} (no such file or directory): " <>
               "replica not started. Check that the folder exists and restart the node.\n"

    refute File.exists?(missing)
    assert Crdt.text() == {:error, :no_replica}
  end

  @tag :req13
  @tag :req19
  test "a folder where the history file should be: :ignore and a message", %{tmp_dir: dir} do
    File.mkdir_p!(path(dir))
    out = start_ignored(dir)
    # the reason depends on the system; on Windows it is :eisdir
    reason = :file.format_error(elem(File.read(path(dir)), 1))

    assert out ==
             "[a@x] cannot open history file #{path(dir)} (#{reason}): " <>
               "replica not started. Check that the folder exists and restart the node.\n"

    refute out =~ "history loaded"
    assert Crdt.text() == {:error, :no_replica}
  end

  @tag :req4
  @tag :req13
  test "an invalid index, an empty text or count 0 do not change the file", %{tmp_dir: dir} do
    start(dir)
    :ok = Crdt.insert(0, "ab")
    file = File.read!(path(dir))

    assert Crdt.insert(5, "x") == {:error, :invalid_index}
    assert Crdt.delete(2) == {:error, :invalid_index}
    assert Crdt.insert(1, "") == :ok
    assert Crdt.delete(1, 0) == :ok
    assert File.read!(path(dir)) == file
  end

  @tag :req13
  @tag :req20
  test "insert of several characters writes one line per character, in order",
       %{tmp_dir: dir} do
    start(dir)
    :ok = Crdt.insert(0, "mundo")
    ops = file_ops(dir)
    assert Enum.map(ops, & &1.ch) == ["m", "u", "n", "d", "o"]
    assert ops == :sys.get_state(Replica).history
  end

  # Counts the calls to :file.sync/1 made by the replica while `fun` runs
  defp count_syncs(fun) do
    pid = Process.whereis(Replica)
    :erlang.trace_pattern({:file, :sync, 1}, true, [])
    :erlang.trace(pid, true, [:call])
    fun.()
    :erlang.trace(pid, false, [:call])
    :erlang.trace_pattern({:file, :sync, 1}, false, [])
    count_trace_messages(pid, 0)
  end

  defp count_trace_messages(pid, n) do
    receive do
      {:trace, ^pid, :call, {:file, :sync, _}} -> count_trace_messages(pid, n + 1)
    after
      100 -> n
    end
  end

  @tag :req13
  @tag :req20
  test "a local call does one sync for all its lines; an empty one does none",
       %{tmp_dir: dir} do
    start(dir)
    assert count_syncs(fn -> :ok = Crdt.insert(0, "mundo") end) == 1
    assert count_syncs(fn -> :ok = Crdt.delete(0, 3) end) == 1
    assert count_syncs(fn -> :ok = Crdt.insert(0, "") end) == 0
  end

  @tag :req9
  @tag :req10
  @tag :req13
  test "a waiting op is written only once applied, in causal order; a duplicate writes nothing",
       %{tmp_dir: dir} do
    start(dir)
    remote(@b2)
    Crdt.text()
    assert File.read!(path(dir)) == ""

    remote(@b1)
    Crdt.text()
    assert file_ops(dir) == [@b1, @b2]

    file = File.read!(path(dir))
    remote(@b1)
    Crdt.text()
    assert File.read!(path(dir)) == file
  end
end
