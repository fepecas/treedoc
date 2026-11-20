defmodule CrdtDistributedTest do
  # Real nodes on this computer with :peer (OTP 25+, docs/DESIGN.md DES12).
  # Excluded by default; run with: mix test --include distributed
  use ExUnit.Case, async: false

  @moduletag :distributed
  # Every replica keeps its history file in a temporary folder
  @moduletag :tmp_dir

  alias Crdt.Discovery
  alias Crdt.Replica

  @b :b@x
  @b1 %{op: :ins, from: @b, vc: %{@b => 1}, pos: [{1, 1, @b}], ch: "x"}
  @b2 %{op: :ins, from: @b, vc: %{@b => 2}, pos: [{1, 1, @b}, {1, 2, @b}], ch: "y"}

  setup_all do
    start_distribution()
    on_exit(fn -> Node.stop() end)
  end

  setup do
    {peer_t, table} = start_peer(:crdt_table)
    {peer_o, other} = start_peer(:crdt_other)

    on_exit(fn ->
      :peer.stop(peer_t)
      :peer.stop(peer_o)
    end)

    %{table: table, other: other}
  end

  # A peer node that can run our code and is not connected to this node
  defp start_free_peer(name) do
    cookie = Atom.to_charlist(Node.get_cookie())
    paths = for app <- [:crdt, :elixir], do: ~c"#{:code.lib_dir(app)}/ebin"

    {:ok, peer, node} =
      :peer.start(%{
        name: name,
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args: [~c"-setcookie", cookie, ~c"-pa" | paths]
      })

    on_exit(fn -> :peer.stop(peer) end)
    {peer, node}
  end

  # Crdt.Discovery on a peer, not linked to the short-lived :peer.call process
  defp start_discovery(peer, port) do
    opts = [ip: {127, 0, 0, 1}, port: port]
    {:ok, _} = :peer.call(peer, :gen_server, :start, [{:local, Discovery}, Discovery, opts, []])
  end

  # Node.start needs epmd; "epmd -daemon" does nothing if epmd already runs
  defp start_distribution do
    erts_bin = Path.join([:code.root_dir(), "erts-#{:erlang.system_info(:version)}", "bin"])
    epmd = :os.find_executable(~c"epmd") || :os.find_executable(~c"epmd", ~c"#{erts_bin}")
    System.cmd(to_string(epmd), ["-daemon"])
    {:ok, _} = Node.start(:"crdt_test@127.0.0.1", :longnames)
  end

  # A peer node with a fake Crdt.Replica: a process that never reads its
  # mailbox, so the mailbox keeps every message sent to it.
  defp start_peer(name) do
    cookie = Atom.to_charlist(Node.get_cookie())

    # :standard_io keeps the peer alive when the test disconnects from it
    {:ok, peer, node} =
      :peer.start(%{
        name: name,
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args: [~c"-setcookie", cookie]
      })

    true = Node.connect(node)
    fake = Node.spawn(node, :timer, :sleep, [:infinity])
    true = :rpc.call(node, :erlang, :register, [Replica, fake])
    {peer, node}
  end

  # The replica's notices, also those of init, go to a StringIO. The test
  # supervisor starts with the first start_supervised (one per test here)
  # and its children take the group leader the test process has then.
  defp start_replica(dir, nodes) do
    {:ok, io} = StringIO.open("")
    group_leader = Process.group_leader()
    Process.group_leader(self(), io)

    try do
      start_supervised!({Replica, me: node(), nodes: nodes, data_dir: dir, name: Replica})
    after
      Process.group_leader(self(), group_leader)
    end
  end

  # The casts that the fake Crdt.Replica on `node` has received
  defp received(node) do
    fake = :rpc.call(node, :erlang, :whereis, [Replica])
    {:messages, msgs} = :rpc.call(node, :erlang, :process_info, [fake, :messages])
    for {:"$gen_cast", m} <- msgs, do: m
  end

  defp count(node, m), do: Enum.count(received(node), &(&1 == m))

  # Polls for up to 3 s
  defp eventually(fun, tries \\ 60) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> wait_and_retry(fun, tries)
    end
  end

  defp wait_and_retry(fun, tries) do
    Process.sleep(50)
    eventually(fun, tries - 1)
  end

  @tag :req11
  @tag :req15
  test "(a) b2 waits, b1 arrives: both are forwarded to a connected node, with no table", %{
    table: table,
    tmp_dir: dir
  } do
    start_replica(dir, [])
    GenServer.cast(Replica, {:remote, @b2})
    GenServer.cast(Replica, {:remote, @b1})
    assert Crdt.text() == "xy"

    assert eventually(fn -> count(table, {:remote, @b1}) == 1 end)
    assert eventually(fn -> count(table, {:remote, @b2}) == 1 end)
  end

  @tag :req15
  @tag :req17
  test "(b) a connected node outside the table receives the ops like a table node", %{
    table: t,
    other: o,
    tmp_dir: dir
  } do
    pid = start_replica(dir, [t])
    :ok = Crdt.insert(0, "ab")
    GenServer.cast(Replica, {:remote, @b1})
    [op1, op2, _] = :sys.get_state(pid).history

    for n <- [t, o], m <- [op1, op2, @b1] do
      assert eventually(fn -> count(n, {:remote, m}) == 1 end)
    end

    # REQ17: how each connected node was found
    lines = String.split(ExUnit.CaptureIO.capture_io(&Crdt.status/0), "
")
    assert "discovery: off" in lines

    assert "connected: #{t} (table), #{o} (other)" in lines or
             "connected: #{o} (other), #{t} (table)" in lines
  end

  @tag :req12
  @tag :req15
  test "(c) the history is resent on nodeup and on hello, with no table",
       %{table: table, tmp_dir: dir} do
    pid = start_replica(dir, [])
    :ok = Crdt.insert(0, "ab")
    [op1, op2] = :sys.get_state(pid).history
    assert eventually(fn -> count(table, {:remote, op2}) == 1 end)

    GenServer.cast(Replica, {:hello, table})
    assert eventually(fn -> count(table, {:remote, op1}) == 2 end)
    assert eventually(fn -> count(table, {:remote, op2}) == 2 end)

    # disconnect: the replica's timer (or this test) connects again -> :nodeup
    Node.disconnect(table)
    Node.connect(table)
    assert eventually(fn -> count(table, {:remote, op1}) == 3 end)
    assert eventually(fn -> count(table, {:remote, op2}) == 3 end)
  end

  @tag :req14
  @tag :req16
  test "(d) an unreachable node in the table does not block Crdt.insert", %{tmp_dir: dir} do
    # 192.0.2.1 is a documentation address: Node.connect hangs for ~7 s
    start_replica(dir, [:"crdt@192.0.2.1"])
    {micros, :ok} = :timer.tc(fn -> Crdt.insert(0, "x") end)
    assert micros < 1_000_000
  end

  @tag :req12
  @tag :req13
  @tag :req15
  test "(e) the history loaded from the file is sent once to a connected node",
       %{table: table, tmp_dir: dir} do
    me = node()
    op1 = %{op: :ins, from: me, vc: %{me => 1}, pos: [{1, 1, me}], ch: "a"}
    op2 = %{op: :ins, from: me, vc: %{me => 2}, pos: [{1, 1, me}, {1, 2, me}], ch: "b"}
    file = Path.join(dir, "crdt_test.jsonl")
    File.write!(file, Crdt.LogFormat.to_json_line(op1) <> Crdt.LogFormat.to_json_line(op2))

    # the node is already connected when the replica starts (DES4.4, step 3)
    start_replica(dir, [])
    assert Crdt.text() == "ab"
    assert eventually(fn -> count(table, {:remote, op1}) == 1 end)
    assert eventually(fn -> count(table, {:remote, op2}) == 1 end)
    # no second copy arrives later
    Process.sleep(300)
    assert count(table, {:remote, op1}) == 1
    assert count(table, {:remote, op2}) == 1
  end

  # What the replica does while `fun` runs, in order: :sync (a call to
  # :file.sync/1), :notice (an "applied" notice) and :send (an op cast to a
  # node). Other notices (connected, hello) can come at any time; skipped.
  defp replica_steps(fun) do
    pid = Process.whereis(Replica)
    :erlang.trace_pattern({:file, :sync, 1}, true, [])
    :erlang.trace(pid, true, [:call, :send])
    fun.()
    :erlang.trace(pid, false, [:call, :send])
    :erlang.trace_pattern({:file, :sync, 1}, false, [])
    collect_steps(pid)
  end

  defp collect_steps(pid) do
    receive do
      {:trace, ^pid, :call, {:file, :sync, _}} -> [:sync | collect_steps(pid)]
      {:trace, ^pid, :send, {:io_request, _, _, request}, _} -> notice(request, pid)
      {:trace, ^pid, :send, {:"$gen_cast", {:remote, _}}, _} -> [:send | collect_steps(pid)]
      {:trace, ^pid, _, _, _} -> collect_steps(pid)
    after
      300 -> []
    end
  end

  defp notice({:put_chars, _encoding, chars}, pid) do
    if IO.chardata_to_string(chars) =~ "applied",
      do: [:notice | collect_steps(pid)],
      else: collect_steps(pid)
  end

  @tag :req13
  @tag :req20
  test "(f) local call: one sync, then the sends; remote op: sync, notice, forward",
       %{tmp_dir: dir} do
    start_replica(dir, [])
    # DES4.5: nothing leaves the node before the sync; 2 ops to 2 connected nodes
    assert replica_steps(fn -> :ok = Crdt.insert(0, "ab") end) ==
             [:sync, :send, :send, :send, :send]

    # DES4.5: on disk before the notice and the forwarding
    steps =
      replica_steps(fn ->
        GenServer.cast(Replica, {:remote, @b1})
        Crdt.text()
      end)

    assert steps == [:sync, :notice, :send, :send]
  end

  @tag :req14
  test "(g) two nodes with no table find each other by discovery; one listens, one announces" do
    {peer1, node1} = start_free_peer(:crdt_disc1)
    {peer2, node2} = start_free_peer(:crdt_disc2)
    start_discovery(peer1, 45_990)
    start_discovery(peer2, 45_990)

    assert eventually(fn -> node2 in :peer.call(peer1, Node, :list, []) end)
    assert eventually(fn -> node1 in :peer.call(peer2, Node, :list, []) end)

    modes = for p <- [peer1, peer2], do: elem(:peer.call(p, Discovery, :info, []), 0)
    assert Enum.sort(modes) == ["announce only", "listening on 45990"]
  end

  # An announcement sent to the discovery group on this computer
  defp announce(port, packet) do
    {:ok, socket} = :gen_udp.open(0, multicast_if: {127, 0, 0, 1}, multicast_loop: true)
    :ok = :gen_udp.send(socket, {233, 252, 1, 32}, port, packet)
    :gen_udp.close(socket)
  end

  @tag :req14
  @tag :req17
  test "(h) an announcement connects; own name, connected nodes and other packets do not",
       %{table: table, tmp_dir: dir} do
    {_peer, free} = start_free_peer(:crdt_free)
    start_replica(dir, [])
    # no :ip: the interface is the IP of this node's name, 127.0.0.1
    pid = start_supervised!({Discovery, port: 45_991})
    # each Node.connect runs in a process spawned by Crdt.Discovery (DES7.1)
    :erlang.trace(pid, true, [:procs])

    announce(45_991, "hello " <> Atom.to_string(free))
    announce(45_991, Discovery.packet(node()))
    announce(45_991, Discovery.packet(table))
    Process.sleep(300)
    refute free in Node.list()
    refute_received {:trace, ^pid, :spawn, _, _}

    announce(45_991, Discovery.packet(free))
    assert eventually(fn -> free in Node.list() end)
    assert_received {:trace, ^pid, :spawn, _, _}
    {"listening on 45991", heard} = Discovery.info()
    assert MapSet.equal?(heard, MapSet.new([table, free]))

    lines = String.split(ExUnit.CaptureIO.capture_io(&Crdt.status/0), "
")
    assert "discovery: listening on 45991" in lines
    assert Enum.any?(lines, &(&1 =~ "#{free} (announced)"))
  end

  @tag :req14
  test "(i) busy port: the second node of a machine only announces", %{tmp_dir: dir} do
    # first, so its notices go to a StringIO (see start_replica/2)
    start_replica(dir, [])
    # the first one is not registered, so the second can take the name
    {:ok, _} = GenServer.start(Discovery, ip: {127, 0, 0, 1}, port: 45_992)
    # a host that is not an IPv4: the system's default interface
    start_supervised!({Discovery, me: :a@x, port: 45_992})
    assert {"announce only", _} = Discovery.info()

    assert "discovery: announce only" in String.split(
             ExUnit.CaptureIO.capture_io(&Crdt.status/0),
             "
"
           )
  end

  # Windows ignores errors of the multicast options, so a foreign interface
  # does not fail there; on macOS and Linux it does
  if match?({:unix, _}, :os.type()) do
    @tag :req14
    test "(k) a socket that cannot open: :ignore and a message" do
      out =
        ExUnit.CaptureIO.capture_io(fn ->
          assert Discovery.start_link(ip: {192, 0, 2, 1}, port: 45_993) == :ignore
        end)

      assert out =~ "discovery off: cannot open UDP port 45993"
      assert out =~ "Use a node table (NODES_FILE)."
    end
  end

  @tag :req14
  test "(j) the application starts discovery on a named node unless DISCOVERY=off" do
    assert Crdt.Application.children() == [Replica, Discovery]
    System.put_env("DISCOVERY", "off")
    assert Crdt.Application.children() == [Replica]
  after
    System.delete_env("DISCOVERY")
  end
end
