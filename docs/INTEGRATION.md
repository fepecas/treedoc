# Integration

The contract for another team that wants its nodes to talk to ours.
There are three levels. A and B are supported and described here. C is
out of scope. The words used here (op, PosID, vector clock, tombstone)
are in the [glossary](MANUAL-TESTS.md#glossary).

The contract needs Erlang distribution, so Elixir or Erlang is the simple
path; other languages need an Erlang distribution library.

- [A. Connect](#a-connect)
- [B. Receive and send our operations](#b-receive-and-send-our-operations)
- [C. Edit together for real](#c-edit-together-for-real)
- [Minimal example](#minimal-example)
- [Where to start](#where-to-start)

## A. Connect

- Our nodes use Erlang distribution (`DESIGN.md` DES6).
- Cookie: `cpd2026`. Only nodes with the same cookie connect.
- Long names: `--name name@IP`. Our nodes are named
  `<hostname>@<IPv4>`, for example `crdt-pi1@192.168.1.21`, by our start
  scripts. Short names (`--sname`) cannot talk to long names.
- Ports: EPMD on TCP 4369, plus one distribution port per node. Our
  start scripts fix it to the range 4218 to 4228
  (`-kernel inet_dist_listen_min 4218 inet_dist_listen_max 4228`, for
  example in `ERL_AFLAGS`). Our discovery uses UDP 45892.
- Firewall: allow those ports. How, on Windows and macOS:
  [NETWORK.md](NETWORK.md), section 2.
- OTP versions: "Erlang nodes can communicate across at least two
  preceding and two subsequent releases"
  ([Erlang documentation](https://www.erlang.org/doc/system/misc.html),
  "Compatibility"). Our nodes run OTP 27 or later. Check yours:

  ```elixir
  :erlang.system_info(:otp_release)
  ```

  It returns, for example, `~c"27"`.
- Check the connection before any code of ours (ping,
  `Node.connect/1`, `Node.list()`): [NETWORK.md](NETWORK.md), section 5.

## B. Receive and send our operations

### Connect to one of our nodes

- Our nodes send to every connected node (`Node.list()`, `DESIGN.md`
  DES6). No table is needed: call `Node.connect/1` with the name of one
  of our nodes, as its start script printed it. Erlang then connects
  you to the others it knows.
- Or ask us to put your exact node name, for example
  `team@192.168.1.30`, in the node table (`NODES_FILE`) of one of our
  nodes: it connects to you every 2 seconds until it reaches you.
- Our discovery only acts on packets with our tag
  (`crdt-treedoc-1 <node name>`, UDP 45892, `DESIGN.md` DES6.1). You may
  send that packet too, but `Node.connect/1` is simpler.
- A node with a hidden name (`--hidden`) is not in `Node.list()` and
  receives nothing.

### Receive

- Register a process under the name `Crdt.Replica`. In Erlang the name
  is `'Elixir.Crdt.Replica'`.
- It receives two kinds of `GenServer` casts. A GenServer gets them in
  `handle_cast/2`. A plain process gets `{:"$gen_cast", message}`.
  - `{:remote, msg}`: one operation (format below).
  - `{:hello, node}`: a node of ours started. It asks you to send your
    whole history again.
- Each of our nodes forwards every op it applies to every connected
  node. You get each op several times: drop the copies.
- When you connect, and when you send us `{:hello, node()}`, each of
  our nodes sends you its whole history, one `{:remote, msg}` per op,
  in order.

### Send

```elixir
GenServer.cast({Crdt.Replica, :"crdt1@192.168.1.21"}, {:remote, msg})
```

In Erlang: `gen_server:cast({'Elixir.Crdt.Replica', 'crdt1@192.168.1.21'}, {remote, Msg})`.

### The format of `msg` (`DESIGN.md` DES5.1)

```elixir
%{op: :ins, from: node, vc: %{node => integer}, pos: [{bit, seq, node}], ch: "a"}
%{op: :del, from: node, vc: %{node => integer}, pos: [{bit, seq, node}]}
```

- `from`: the node that made the op, an atom.
- `vc`: the vector clock of the op. `vc[from]` is the op's number on
  that node. For every other node, how many of its ops you had applied.
- `pos`: the PosID, a path from the root. Each step is `{bit, seq,
  node}`: bit 0 is left, 1 is right; `{seq, node}` is the disambiguator
  (`DESIGN.md` DES3.1, DES3.2).
- `ch`: the character, one grapheme.
- A delete names the PosID of the character it deletes.

### Rules for an op you send us

What really happens if a rule is broken was seen in a test with a
foreign node (section "Minimal example").

1. `vc[from]` counts 1, 2, 3… per node, with no gaps and no reuse
   (`DESIGN.md` DES4.1, DES4.2).
   - A gap: the op waits in our buffer forever and is not forwarded.
     `Crdt.status()` shows
     `waiting op 3 from team@127.0.0.1 (missing: team@127.0.0.1 up to 2)`.
     Every later op of yours waits too. The buffer is in memory: a
     restart loses it.
   - A number already used: we drop the op as `duplicate dropped`.
2. `vc[k]` for another node `k`: at most what that node had really sent.
   More than that, and the op waits for ops that never come.
3. `ch` is exactly one grapheme (`DESIGN.md` DES3.5). With `"ab"`, both
   letters take one position: the text was `"Tabhola"`, 7 letters, but
   `Crdt.insert(7, "x")` returned `{:error, :invalid_index}` and
   `Crdt.insert(6, "x")` wrote at the end.
4. `pos` is new, unique and in the right place by our order
   (`DESIGN.md` DES3.3, DES3.4): the last step carries your `{seq, from}`.
   - A PosID already used replaces our character on every node:
     `"Tabholax"` became `"TabHolax"`.
   - A PosID in the wrong place shows the character in that place.
5. The keys of the format are all there.
   - With `{:remote, %{}}`, our replica crashed (`KeyError`), the
     supervisor restarted it, it loaded its file and sent its history
     again. No text was lost; the buffer was. More than 3 crashes in 5
     seconds stop the editor on that node (the default of the
     supervisor, `DESIGN.md` DES4.5; not tested).

## C. Edit together for real

To keep a copy of the document that converges with ours, a node needs:

- Treedoc with our PosIDs and our comparison (`DESIGN.md` DES3.3).
- Causal delivery with vector clocks: apply, wait or drop (DES4.2).
- Forwarding of every applied op, once (DES4.3), and a history that is
  sent again on connection and on `hello` (DES4.4).

This is out of scope: we document it, we do not support it. A
different CRDT (RGA, Logoot) cannot interoperate with ours: its
positions do not compare with our PosIDs.

## Minimal example

On one computer. Our nodes are `crdt1@127.0.0.1` and `crdt2@127.0.0.1`;
yours is `team@127.0.0.1`, a node without our code, with Elixir.

First, our two nodes. In the folder of this project, from an empty
`data` folder (see [README.md, "Quick start"](../README.md#quick-start)),
run `mix compile` once. Then start crdt1 and crdt2, each in its own
terminal. No node table is needed.

PowerShell (Windows):

```powershell
.\scripts\start.ps1 -Name crdt1 -Ip 127.0.0.1
.\scripts\start.ps1 -Name crdt2 -Ip 127.0.0.1
```

macOS / Linux:

```sh
./scripts/start.sh --name crdt1 --ip 127.0.0.1
./scripts/start.sh --name crdt2 --ip 127.0.0.1
```

Then yours, in a third terminal, in any folder outside this project:

```
iex --name team@127.0.0.1 --cookie cpd2026
```

(on Windows, `iex.bat`). Paste, in one go:

```elixir
Node.connect(:"crdt1@127.0.0.1")

spy =
  spawn(fn ->
    loop = fn loop ->
      receive do
        message ->
          IO.inspect(message, label: "Crdt.Replica got")
          loop.(loop)
      end
    end

    loop.(loop)
  end)

Process.register(spy, Crdt.Replica)
GenServer.cast({Crdt.Replica, :"crdt1@127.0.0.1"}, {:hello, node()})
```

It returns `:ok`. crdt1 prints
`connected team@127.0.0.1: resending history (0 ops)` and
`hello from team@127.0.0.1: resending history (0 ops)`; crdt2 prints
`connected team@127.0.0.1: ...`, because Erlang connected your node to
crdt2 too. Now, on crdt1,
`Crdt.insert(0, "hola")`. Your console shows each op, twice (from crdt1
and forwarded by crdt2), for example:

```
Crdt.Replica got: {:"$gen_cast",
 {:remote,
  %{
    op: :ins,
    pos: [{1, 1, :"crdt1@127.0.0.1"}],
    from: :"crdt1@127.0.0.1",
    vc: %{"crdt1@127.0.0.1": 1},
    ch: "h"
  }}}
```

Send one valid insert, at the start of the text:

```elixir
msg = %{op: :ins, from: node(), vc: %{node() => 1}, pos: [{0, 1, node()}], ch: "T"}
GenServer.cast({Crdt.Replica, :"crdt1@127.0.0.1"}, {:remote, msg})
```

- crdt1 prints `applied op 1 from team@127.0.0.1: ins "T"` and forwards
  it; crdt2 prints the same line.
- `Crdt.text()` returns `"Thola"` on crdt1 and on crdt2.
- Your own op comes back to you twice, forwarded by crdt1 and crdt2.
- `pos: [{0, 1, node()}]` is a left child of the root, so it comes
  before every character typed at index 0 by our nodes, which are right
  children (`DESIGN.md` DES3.4).

To finish, `System.halt()` on the three nodes, then delete
`data/*.jsonl`.

## Where to start

[README.md, "Adopt it step by step"](../README.md#adopt-it-step-by-step):
run three nodes, try the manual tests, then come back here.
