# Integration

How another team, or a classmate, can join our nodes. There are three
levels; each one builds on the one before. The words used here (op,
PosID, vector clock, tombstone) are in the
[glossary](MANUAL-TESTS.md#glossary).

- [Security first](#security-first)
- [L1. Join the Erlang cluster](#l1-join-the-erlang-cluster)
- [L2. Compatible discovery](#l2-compatible-discovery)
- [L3. Edit the same document](#l3-edit-the-same-document)
- [Add another Raspberry Pi](#add-another-raspberry-pi)
- [Minimal example](#minimal-example)
- [Where to start](#where-to-start)

The contract needs Erlang distribution, so Elixir or Erlang is the
simple path; other languages need an Erlang distribution library.

## Security first

The cookie `cpd2026` is shared by the whole course. Anyone who has it
and reaches your node can run any code on it (for example with
`:rpc.call/4`), with your user's rights. Run nodes only on trusted
networks (your home Wi-Fi, a phone hotspot, a lab you trust), never on
a public network, and halt them when you are done.

## L1. Join the Erlang cluster

What any Erlang node needs to connect to ours (`DESIGN.md` DES6).

- Cookie: `cpd2026`. Only nodes with the same cookie connect.
- Long names: `--name name@IPv4`. Our nodes are named
  `<hostname>@<IPv4>`, for example `pi-pe@172.20.10.4`, by our start
  scripts. Short names (`--sname`) cannot talk to long names. Use the
  IPv4 of the network you share with us, never `.local`.
- The node name travels to every node and is stored in every op. On a
  corporate computer, choose a neutral name: `-Name <name>` or
  `--name <name>` with our scripts, or your own `--name`.
- Ports: EPMD on TCP 4369, and one distribution port per node. Our
  start scripts fix it to the range 4218 to 4228
  (`ERL_AFLAGS="-kernel inet_dist_listen_min 4218 inet_dist_listen_max 4228 prevent_overlapping_partitions false"`).
- Partitions: start your node with
  `-kernel prevent_overlapping_partitions false`, as ours do, so a
  dropped link does not cut the other links (`DESIGN.md` DES6,
  "Partitions"). Keep `net_ticktime` at the OTP default (60 s): nodes
  with different values drop each other when idle.
- Firewall: allow TCP 4369 and TCP 4218 to 4228 (and UDP 45892 for L2).
  On Windows the network profile must be Private. Exact commands for
  Windows and macOS: [NETWORK.md](NETWORK.md), section 2.
- OTP versions: "Erlang nodes can communicate across at least two
  preceding and two subsequent releases"
  ([Erlang documentation](https://www.erlang.org/doc/system/misc.html),
  "Compatibility"). Our nodes have run on OTP 27 (Raspberry Pi) and OTP
  29 (Windows and macOS), together. Check yours:

  ```elixir
  :erlang.system_info(:otp_release)
  ```

- Connect: `Node.connect(:"<one of our node names>")` returns `true`.
  Erlang then connects you to every node that one knows. Check with
  `Node.list()`. If it fails: [NETWORK.md](NETWORK.md), section 5.
- A node started with `--hidden` is not in `Node.list()` and receives
  none of our ops.

## L2. Compatible discovery

Our nodes find each other with a UDP multicast announcement
(`DESIGN.md` DES6.1). A node of yours can announce itself the same way,
so ours connect to it with no `Node.connect/1` on either side. The
values, from `lib/crdt/discovery.ex`:

- Group `233.252.1.32`, UDP port `45892`.
- TTL 1 (it does not leave the local network); multicast loop on.
- Every 2 seconds, one packet whose bytes are the text
  `crdt-treedoc-1 ` (with the space) followed by the full node name,
  with no newline. For example: `crdt-treedoc-1 pi-pe@172.20.10.4`.
- Send it on the interface of the IPv4 in your node name.
- Our nodes act only on packets that start with that tag. If the name
  is not their own and not already connected, they call
  `Node.connect/1` on it. Anything else is ignored.
- To hear ours, join the group on your interface and read the same
  packets. Only one socket per computer can listen on the port; a
  second node on the same computer only announces.
- `elixir scripts/multicast_check.exs <your IPv4>` tells whether the
  network carries multicast at all.

L2 is optional: L1 with `Node.connect/1`, or a node table
(`NODES_FILE`) on one of our nodes, gives the same cluster.

## L3. Edit the same document

To edit with us, a node either runs our program (the simple way: clone
this repository and use the start script) or speaks our operation
protocol, described here (`DESIGN.md` DES3 to DES5).

### The target process

- Register a process under the name `Crdt.Replica`. In Erlang the name
  is `'Elixir.Crdt.Replica'`.
- It receives two kinds of `GenServer` casts. A GenServer gets them in
  `handle_cast/2`. A plain process gets `{:"$gen_cast", message}`.
  - `{:remote, msg}`: one operation (format below).
  - `{:hello, node}`: a node started. It asks you to send your whole
    history again.
- A node without a process `Crdt.Replica` drops our casts silently.

### History exchange

- Our nodes send every op to every connected node, and forward each op
  they apply once, unchanged (`DESIGN.md` DES4.3). You get each op
  several times: drop the copies.
- When you connect (`{:nodeup, node}` on our side), and when you send
  us `{:hello, node()}`, each of our nodes sends you its whole history,
  one `{:remote, msg}` per op, in the order it applied them
  (`DESIGN.md` DES4.4).
- To get our ops you must apply them in causal order: apply, wait or
  drop by the vector clock (`DESIGN.md` DES4.2).

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
  (`DESIGN.md` DES3.1, DES3.2). Paths are ordered by in-order traversal;
  steps with the same bit, by the disambiguator, `seq` first and then
  the node name (PAP3.1, PAP3.3.1, `DESIGN.md` DES3.3).
- `ch`: the character, one grapheme.
- A delete names the PosID of the character it deletes; the character
  stays as a tombstone.

### Rules for an op you send us

What really happens if one of rules 1 to 4 is broken was seen in a test
with a foreign node (section "Minimal example"). Rule 5 is checked by
our replica before anything else, and our tests send it many malformed
and unknown messages (REQ23, `DESIGN.md` DES12).

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
5. The message has exactly the format above (`DESIGN.md` DES5.1).
   - `op` is `:ins` with a `ch`, or `:del`; `from` is an atom other
     than `nil`, `true` and `false`; `vc` maps at most 10 000 atoms to
     integers >= 0, with `vc[from] >= 1`; `pos` is a non-empty list of
     `{0 or 1, integer >= 1, atom}`, where the atom is not `nil`,
     `true` or `false`; `ch` is one valid grapheme. `{:hello, node}`
     needs an atom.
   - The step atom is stricter than in some other implementations: our
     history file could not load `nil`, `true` or `false` back.
   - Anything else is dropped. Our node prints
     `malformed message dropped: ...`, nothing changes, and the replica
     keeps running. Unknown calls answer `{:error, :unknown}`.
   - Extra keys are removed before the op is stored or forwarded.

### A full implementation

To keep a copy of the document that converges with ours, a node needs
Treedoc with our PosIDs and our comparison (`DESIGN.md` DES3.3), causal
delivery with vector clocks (DES4.2), forwarding of every applied op
once (DES4.3), and a history sent again on connection and on `hello`
(DES4.4). An implementation that does all of this, with the rules
above, edits the same document with ours, with no change on either side
(REQ22). Tested with another team's implementation: MAN16 (on
computers) and MAN17 (with our Pi with Nerves) passed, MAN18 (Pi to Pi)
pending (`MANUAL-TESTS.md`). Each team checked so far, and our
code for each rule: [teams/](../teams/README.md). A different CRDT (RGA, Logoot) cannot
interoperate with ours: its positions do not compare with our PosIDs.

## Add another Raspberry Pi

1. Raspberry Pi OS (64-bit) with its own hostname: two Pis left as
   `raspberrypi` would collide (`sudo hostnamectl set-hostname <name>`,
   then `sudo reboot`).
2. Elixir 1.18 or later with Erlang/OTP 27 to 29:
   `sudo apt install -y elixir git` (Raspberry Pi OS trixie gives
   Elixir 1.18.3 with OTP 27).
3. The same network as the other nodes.
4. Clone and start:

   ```sh
   git clone <repository URL> ~/crdt
   cd ~/crdt
   mix compile
   mix test
   ./scripts/start.sh
   ```

   It prints its node name, `<hostname>@<IPv4>`; `hostname -I` shows
   the IPv4. Within a few seconds `Node.list()` shows the other nodes
   and the text arrives.

A Raspberry Pi 4 can also run our node as Nerves firmware, with no
Raspberry Pi OS: see [README-nerves.md](../deploy/README-nerves.md).

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
crdt2 too. Now, on crdt1, `Crdt.insert(0, "hola")`. Your console shows
each op, twice (from crdt1 and forwarded by crdt2), for example:

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
