defmodule Crdt.Replica do
  @moduledoc """
  The one process that owns the node's state, so no races (REQ16, DES7); same on every node (REQ1).
  Joins Treedoc, causal delivery, network and console (docs/DESIGN.md DES4, DES6, DES9).
  """

  use GenServer

  alias Crdt.Causal
  alias Crdt.LogFormat
  alias Crdt.Treedoc

  @connect_every 2_000

  @doc "Options: `:me`, `:nodes`, `:data_dir` and `:name` (docs/DESIGN.md DES8)."
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  # DES4.4 start order: step 0 table, step 1 history, then network.
  # DES6: invalid configuration returns :ignore; the VM and IEx stay alive.
  @impl true
  def init(opts) do
    me = Keyword.get(opts, :me, node())
    path = history_path(Keyword.get(opts, :data_dir, "data"), me)

    with {:ok, nodes_file, nodes} <- node_table(opts),
         {:ok, ops, log} <- load_history(me, path) do
      {:ok, start(me, nodes_file, nodes, path, ops, log)}
    else
      {:error, file, reason} ->
        say(
          me,
          "cannot read nodes file #{file} (#{:file.format_error(reason)}): " <>
            "replica not started. Fix NODES_FILE and restart the node."
        )

        :ignore

      {:error, reason} ->
        say(
          me,
          "cannot open history file #{path} (#{:file.format_error(reason)}): " <>
            "replica not started. Check that the folder exists and restart the node."
        )

        :ignore

      {:corrupted, line} ->
        say(
          me,
          "history corrupted at line #{line} of #{path}: replica not started. " <>
            "Delete that file and restart the node to catch up with the others. " <>
            "Do not edit on this node until its text matches the others."
        )

        :ignore
    end
  end

  defp node_table(opts) do
    if Keyword.has_key?(opts, :nodes),
      do: {:ok, "option :nodes", opts[:nodes]},
      else: Crdt.Config.nodes()
  end

  # REQ13, DES4.5: <data_dir>/<name>.jsonl, the part before "@": it does not depend on the IP
  defp history_path(data_dir, me) do
    [name | _] = String.split(Atom.to_string(me), "@")
    Path.join(data_dir, name <> ".jsonl")
  end

  defp start(me, nodes_file, nodes, path, ops, log) do
    state = %{
      me: me,
      nodes_file: nodes_file,
      nodes: nodes,
      path: path,
      log: log,
      # REQ13, DES4.5: effect and vc[from] := m[from], without Crdt.Causal; no seq reused (DES4.6)
      doc: Enum.reduce(ops, Treedoc.new(), &Treedoc.effect(&2, &1)),
      vc: Enum.reduce(ops, %{}, fn op, vc -> Map.put(vc, op.from, op.vc[op.from]) end),
      buffer: [],
      history: ops
    }

    :net_kernel.monitor_nodes(true)
    send_history(state)
    broadcast({:hello, me})
    send(self(), :connect)
    state
  end

  # REQ13, DES4.5: {:ok, ops, log} with the file open for appending (only after loading
  # and cutting), {:corrupted, line}, or {:error, reason} if it cannot be read or opened
  defp load_history(me, path) do
    with {:ok, text} <- read_file(path),
         {:ok, ops} <- check_lines(me, path, text),
         {:ok, log} <- :file.open(path, [:append, :binary]) do
      say(me, "history loaded: #{length(ops)} ops")
      {:ok, ops, log}
    end
  end

  # A missing file is an empty history (first start)
  defp read_file(path) do
    case File.read(path) do
      {:error, :enoent} -> {:ok, ""}
      other -> other
    end
  end

  defp check_lines(me, path, text) do
    case read_lines(String.split(text, "\n"), 1, 0, []) do
      {:incomplete, ops, good_bytes} ->
        say(me, "history: last line was incomplete; removed from file")
        truncate(path, good_bytes)
        {:ok, ops}

      ok_or_corrupted ->
        ok_or_corrupted
    end
  end

  # REQ19: a line is complete if it ends in "\n" and is valid (DES4.5). The pieces of
  # String.split/2 all end in "\n" except the last one, which is "" if the file
  # ends in "\n". good_bytes counts bytes, not characters.
  defp read_lines([""], _line, _good_bytes, ops), do: {:ok, Enum.reverse(ops)}

  defp read_lines([piece | rest], line, good_bytes, ops) do
    case {rest, LogFormat.from_json_line(piece)} do
      {[_ | _], {:ok, op}} ->
        read_lines(rest, line + 1, good_bytes + byte_size(piece) + 1, [op | ops])

      {last, _} when last in [[], [""]] ->
        {:incomplete, Enum.reverse(ops), good_bytes}

      _ ->
        {:corrupted, line}
    end
  end

  defp truncate(path, good_bytes) do
    {:ok, file} = :file.open(path, [:read, :write, :binary])
    {:ok, _} = :file.position(file, good_bytes)
    :ok = :file.truncate(file)
    :ok = :file.sync(file)
    :ok = :file.close(file)
  end

  # DES4.5: one write and one sync for all the lines; a failure crashes the replica
  defp write_log(_state, []), do: :ok

  defp write_log(state, msgs) do
    :ok = :file.write(state.log, Enum.map(msgs, &LogFormat.to_json_line/1))
    :ok = :file.sync(state.log)
  end

  # Local edits (DES4.5, DES7): validate first, then one call does every character

  @impl true
  def handle_call({:insert, index, text}, _from, state) do
    if in_range?(index, size(state)) do
      edits = for {ch, k} <- Enum.with_index(String.graphemes(text)), do: {:insert, index + k, ch}
      {:reply, :ok, local_edit(state, edits)}
    else
      {:reply, {:error, :invalid_index}, state}
    end
  end

  def handle_call({:delete, index, count}, _from, state) do
    size = size(state)

    # REQ4: not enough characters means nothing is deleted
    if in_range?(index, size - 1) and in_range?(count, size - index) do
      {:reply, :ok, local_edit(state, List.duplicate({:delete, index}, count))}
    else
      {:reply, {:error, :invalid_index}, state}
    end
  end

  # Queries (DES9): the caller prints the lines

  def handle_call(:text, _from, state), do: {:reply, Treedoc.value(state.doc), state}

  def handle_call(:status, _from, state), do: {:reply, status_lines(state), state}

  def handle_call({:history, which}, _from, state) do
    lines = Enum.map(state.history, &describe(state, &1))
    {:reply, last_lines(lines, which), state}
  end

  def handle_call(:debug, _from, state) do
    lines =
      for {ch, pos, dead} <- Treedoc.debug_rows(state.doc),
          do: "#{inspect(ch)} #{inspect(pos)}" <> if(dead, do: " deleted", else: "")

    {:reply, lines, state}
  end

  # Network messages (DES4.2, DES4.3, DES4.4)

  @impl true
  def handle_cast({:remote, msg}, state) do
    {state, events} = Causal.receive_message(state, msg, &Treedoc.effect/2)
    {:noreply, Enum.reduce(events, state, &handle_event/2)}
  end

  # REQ12: resend the history on hello and on nodeup, from any node (DES4.4, DES6)
  def handle_cast({:hello, n}, state) do
    resend_history(state, "hello from #{n}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodeup, n}, state) do
    resend_history(state, "connected #{n}")
    {:noreply, state}
  end

  def handle_info({:nodedown, n}, state) do
    say(state.me, "disconnected #{n}")
    {:noreply, state}
  end

  # DES6, DES7.1: Node.connect runs in a short-lived process, never in the replica
  def handle_info(:connect, state) do
    for n <- state.nodes, n != state.me, n not in Node.list() do
      spawn(fn -> Node.connect(n) end)
    end

    Process.send_after(self(), :connect, @connect_every)
    {:noreply, state}
  end

  # DES4.1: per character, on the state left by the previous one
  defp local_edit(state, edits) do
    {state, msgs} = Enum.reduce(edits, {state, []}, &local_op/2)
    # DES4.5: on disk with one sync before anything leaves the node
    write_log(state, msgs)
    state = %{state | history: state.history ++ msgs}
    # REQ5: send each new op, in order, as a {:remote, msg} cast (DES5.1)
    Enum.each(msgs, &broadcast({:remote, &1}))
    state
  end

  defp local_op(edit, {state, msgs}) do
    {seq, vc} = Causal.next_local(state.vc, state.me)
    # DES4.1: the index was validated, so prepare returns {:ok, _} and the clock is kept
    {:ok, op} = Treedoc.prepare(state.doc, edit, {seq, state.me})
    msg = Map.merge(op, %{from: state.me, vc: vc})
    {%{state | vc: vc, doc: Treedoc.effect(state.doc, msg)}, msgs ++ [msg]}
  end

  defp handle_event({:applied, msg}, state) do
    # DES4.5: on disk before the notice, the history and the forwarding
    write_log(state, [msg])
    say(state.me, "applied " <> describe(state, msg))
    # REQ11: forward once, unchanged, even if msg.from is this node (DES4.3)
    broadcast({:remote, msg})
    %{state | history: state.history ++ [msg]}
  end

  defp handle_event({:waiting, msg, _missing}, state) do
    say(state.me, waiting_text(state, msg))
    state
  end

  defp handle_event({:duplicate, msg}, state) do
    say(state.me, "duplicate dropped: " <> op_ref(msg))
    state
  end

  # REQ15: the history goes to every connected node, in order
  defp resend_history(state, why) do
    say(state.me, "#{why}: resending history (#{length(state.history)} ops)")
    send_history(state)
  end

  defp send_history(state), do: Enum.each(state.history, &broadcast({:remote, &1}))

  # REQ15, DES6: membership is every connected node, Node.list(); no table filter
  defp broadcast(message) do
    for n <- Node.list(), do: GenServer.cast({__MODULE__, n}, message)
  end

  # REQ17, DES9: discovery state and how each connected node was found
  defp status_lines(state) do
    {discovery, heard} =
      if Process.whereis(Crdt.Discovery), do: Crdt.Discovery.info(), else: {"off", []}

    peers = for n <- Node.list(), do: "#{n} (#{found(n, state.nodes, heard)})"

    [
      "node: #{state.me}",
      "nodes file: #{state.nodes_file}",
      "history file: #{state.path}",
      "table: #{inspect(List.delete(state.nodes, state.me))}",
      "discovery: #{discovery}",
      "connected: #{if peers == [], do: "none", else: Enum.join(peers, ", ")}",
      "clock: #{inspect(state.vc)}",
      "history: #{length(state.history)} ops",
      "buffer: #{length(state.buffer)} ops"
    ] ++ Enum.map(state.buffer, &waiting_text(state, &1))
  end

  defp found(n, nodes, heard) do
    cond do
      n in nodes -> "table"
      n in heard -> "announced"
      true -> "other"
    end
  end

  defp last_lines(lines, :last) when length(lines) > 10 do
    ["... #{length(lines) - 10} earlier ops" | Enum.take(lines, -10)]
  end

  defp last_lines(lines, _which), do: lines

  defp waiting_text(state, msg) do
    missing = for {n, seq} <- Causal.missing(state.vc, msg), do: "#{n} up to #{seq}"
    "waiting #{op_ref(msg)} (missing: #{Enum.join(missing, ", ")})"
  end

  # DES9: a delete shows the character kept by its tombstone
  defp describe(state, msg) do
    "#{op_ref(msg)}: #{msg.op} #{inspect(state.doc.chars[msg.pos])}"
  end

  defp op_ref(msg), do: "op #{msg.vc[msg.from]} from #{msg.from}"

  defp say(me, text), do: IO.puts("[#{me}] #{text}")

  defp in_range?(n, max), do: is_integer(n) and n >= 0 and n <= max

  # Visible characters (stored positions, docs/DESIGN.md DES14)
  defp size(state), do: Enum.count(Treedoc.debug_rows(state.doc), fn {_, _, dead} -> not dead end)
end
