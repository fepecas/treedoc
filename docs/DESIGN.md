# CRDT project: design

Written for the course ISIS-4218 (Universidad de los Andes); ASG and CLS refer to course material.

This document describes **how** the system is built. Together with `REQUIREMENTS.md` (**what** it must do), it is the specification of the project, which is the source of truth. Each section says with "Covers:" which requirements it implements.

The code follows the specification: if they differ, the code is fixed, or the specification is changed first.

References:
- Project assignment (ISIS-4218, "Distribution Project"): course material, not included.
- Treedoc paper: Preguiça, Marquès, Shapiro, Leția, *A commutative replicated data type for cooperative editing*, ICDCS 2009, DOI [10.1109/ICDCS.2009.20](https://doi.org/10.1109/ICDCS.2009.20). When this document says "PAP3.1", it means section 3.1 of that paper.
- Course slides on causality and operation-based CRDTs, and on state-based CRDTs: course material, not included.

---

## 1. What the assignment asks and where it is covered

| What the assignment asks | Requirements | Where it is covered |
|---|---|---|
| There must be no central server | REQ1 | DES6: all nodes are equal and connect to each other |
| Take into account the concurrency problems of the first part of the course | REQ16 | DES7: a single process owns the state on each node |
| A CRDT that keeps the whole document on each node | REQ2, REQ7, REQ8 | DES3: Treedoc |
| Nodes discover each other on the network (dynamic connection, or explicit connection) | REQ14 | DES6 and DES6.1: multicast announcement on the local network, plus an optional list of node names in a file |
| All communication is a broadcast to every connected node | REQ15 | DES4 and DES6: every message is sent to every connected node |
| Send the local changes and receive the others' | REQ5, REQ6 | DES4 and DES5: `ins` and `del` messages |

---

## 2. Decisions and where they come from

| Decision | Origin |
|---|---|
| Treedoc text CRDT, operation-based | PAP |
| Granularity: one character per atom | OUR (allowed by PAP2: an atom can be a character) |
| PosID identifiers, ordered by in-order traversal | PAP2.1 and PAP3.1 |
| Disambiguator `{seq, node}` (UDIS variant) | PAP3.3.1 |
| Deletes as tombstones that keep the character, no *flatten* | OUR (with UDIS, PAP3.3.1, and a set of pairs, PAP3.1, the order does not need deleted nodes; we keep them to show deleted characters in notices, the history and `Crdt.debug()`; the paper needs tombstones only for SDIS, PAP3.3.2). OUR (no *flatten*, PAP4.2, to keep it simple) |
| State as a map `PosID → character` + a set of deletes | PAP2.2 (the state is a set of atom/PosID pairs; storage can be kept apart from the tree, PAP3.1) |
| PosID generation with two cases (DES3.4) instead of Algorithm 1 | OUR (an insert only needs a fresh, unique PosID between its neighbours: density, PAP2.1; insert, PAP2.2) |
| Empty virtual root | OUR (the paper does not define the empty document) |
| Causal delivery with vector clocks; apply/wait/drop rule | CLS (the paper requires happened-before order, PAP1 and PAP2.2, but gives no protocol) |
| Forward each received operation once | CLS (reliable delivery) |
| Resend the whole history on reconnection | OUR |
| History in a readable file, written before sending | OUR (avoids repeating sequence numbers after a restart) |
| Use the clock's sequence number as the disambiguator counter | OUR (a single counter) |
| Erlang distribution, shared cookie, discovery by UDP multicast plus an optional node list in a file | ASG (dynamic or explicit connection between nodes, assignment Task 1), OUR (Erlang distribution, shared cookie, our own multicast announcement, optional list) |
| Membership: every connected node (`Node.list()`); the table only says whom to connect to | ASG (broadcast to all connected nodes, assignment Task 1), OUR (DES6) |
| Discovery: a packet `crdt-treedoc-1 <node>` every 2 s to the group 233.252.1.32, UDP port 45892, TTL 1, on the interface of the IP of the node name; only packets with that tag count; own announcements and nodes already connected are ignored | OUR (no dependencies; tested on a phone hotspot, DES6.1) |
| One discovery listener per machine: if the port is busy, the node only announces | OUR (sharing a UDP port needs options that differ per OS, DES6.1) |
| If the discovery socket cannot be opened, or with `DISCOVERY=off`, the node runs without discovery | OUR (same general rule of DES6; the table still works, DES6.1) |
| Node name `<hostname>@<IPv4>`, lowercased; a suffix `-N` for several nodes on one machine; never `.local` | OUR (the IP changes between networks; a name per machine avoids repeating sequence numbers when another machine gets an old IP, DES6) |
| Start scripts `scripts/start.ps1` and `scripts/start.sh`: pick the Wi-Fi IPv4, print it, accept a forced IP and name, fix the distribution ports 4218 to 4228 | OUR (one command per machine; fixed firewall rules, DES6, DES11) |
| Interface with functions in IEx | OUR |
| Console messages for the demo | OUR |
| `hello` message when the replica starts | OUR (avoids losing the catch-up, DES4.4) |
| Insert or delete several characters in one call | OUR (the text stays together, DES7) |
| A single `:file.sync/1` per local call | OUR (a call of several characters does not do one sync per character, DES4.5) |
| Truncate the incomplete last line of the history before writing again | OUR (otherwise the next line would be glued to the fragment, DES4.5) |
| With a damaged line in the middle, the replica returns `:ignore` | OUR (the virtual machine and IEx stay alive and systemd does not loop, DES4.5) |
| `Node.connect/1` in a separate, short-lived process for each missing node | OUR (a slow connect does not block the replica, DES6 and DES7.1) |
| `status`, `history` and `debug` ask for the data with a `call` and print in the calling process | OUR (they also show from a remote console, DES9) |
| `Crdt.history/0,1` to see the applied operations | OUR (REQ17: see the history, DES9) |
| In the demo, the node of each Pi runs in the foreground in an SSH session | OUR (the commands and the notices are visible, DES13) |
| An index or `count` that is not an integer ≥ 0: `{:error, :invalid_index}`; a `Crdt.insert` text that is not a string: fails in the calling process | OUR (DES9) |
| Local edits do not print the "applied" notice | OUR (notices are for what arrives from the network and for connections, DES9) |
| Invalid configuration (no `--name`, unreadable table, damaged history): the replica does not start, the console says what to fix, and the virtual machine and IEx stay alive | OUR (general rule, DES6) |
| `Crdt.status()` shows the table file and the nodes of the table, the state of discovery, and every connected node with how it was found | OUR (DES9) |
| For `delete`, the valid index goes from 0 to length - 1, also with `count` 0 | OUR (DES9) |
| Tests with real nodes (`:peer`), excluded by default | OUR (they test forwarding, membership, discovery and connect with real nodes, DES12) |
| Read the table before loading the history; a single broadcast of the history at start | OUR (DES4.4) |
| The "history loaded: N ops" notice is always printed at start, also with 0 ops | OUR (DES9) |
| If the history file cannot be read or opened for appending (for example, `data_dir` is missing), the replica does not start, and the folder is not created | OUR (same general rule of DES6, DES4.5) |
| `Crdt.LogFormat.from_json_line/1` is tolerant: it accepts extra keys and does not check that `ch` is one grapheme or that `from` is in `vc` | OUR (the lines are written by our code, DES5.2) |
| The first start creates an empty history file | OUR (the append-mode open creates it, DES4.5) |
| "history loaded" is printed before the network notices and not at all if the replica does not start | OUR (DES9) |
| Test network: a lab network, a phone hotspot or a home router (`name@IP`, and an Ethernet cable or Wi-Fi added by SSH with `nmcli`) | OUR (DES13) |
| History file at `<data_dir>/<name>.jsonl`, with the part of the node name before `@` | OUR (it does not depend on the IP, DES4.5; the `:data_dir` option of DES8 and the `:me` of the tests) |
| Remote operation: write and sync before the "applied" notice | OUR ("applied" means it is already on disk, DES4.5) |
| If the disk keeps failing, the `crdt` application stops and the virtual machine stays alive | OUR (same general rule of DES6, DES4.5) |
| The message without `--name` shows the PowerShell command and the macOS and Linux one | OUR (nodes also run on macOS and Linux, CON3, DES6, DES11) |
| The `connected:` line of `Crdt.status()` shows every connected node with `table`, `announced` or `other` | OUR (the same set as the broadcast; hidden remote consoles are not shown, DES6, DES9) |
| MAN6 with two Pis: MAN2 with two nodes; MAN4 is halting one Pi, writing on the other, starting it again and seeing that it catches up; a third node (a computer with `crdt@IP`) is optional. REQ1 is tested locally with three nodes | OUR (there are two Pis, DES13) |
| `deploy/crdt.service` (not included yet) runs the node without IEx as the user created in Raspberry Pi Imager, in the project folder, with the name and IP of `scripts/start.sh`, after the network and with `Restart=on-failure`; `mix compile` is done before, by hand | OUR (the service has no terminal and does not compile, DES13) |
| A node of another team receives and sends our operations once it is connected to ours (by its table, ours or discovery); it receives `{:remote, msg}` and `{:hello, node}` casts on a process registered as `Crdt.Replica` | OUR (the replica sends to every connected node, DES6; the messages of DES5.1) |
| A Raspberry Pi 4 can run the node with Nerves firmware: a separate project `firmware/` (poncho) that depends on `:crdt` with `path: ".."` and `runtime: false`; in its release `:crdt` is only loaded, so `Crdt.Application` does not run | ASG (Raspberry Pi), OUR (Nerves; `lib/` does not change, DES15) |
| On Nerves, `CrdtFw` starts the node at run time: wait for the IPv4 of `wlan0`, fix the distribution ports, start `epmd`, `Node.start/1`, `Node.set_cookie/1`, create `/data/crdt`, then `Crdt.Replica` and `Crdt.Discovery` under its own `one_for_one` supervisor, `CrdtFw.NodeSupervisor`; the steps run after `init/1`, and a restarted `CrdtFw` repeats them safely | OUR (Nerves does not start Erlang distribution; the root file system is read-only and `/data` is writable, DES15) |
| On Nerves, the distribution ports 4218 to 4228 are set with `Application.put_env(:kernel, ...)` before `Node.start/1`, not in `vm.args.eex` | OUR (OTP reads them when the listen socket opens; the same firewall rules as DES6, DES15) |
| On Nerves, the node name is `<Nerves hostname>@<IPv4 of wlan0>`, with the default hostname `nerves-XXXX` | OUR (the default hostname is different on each device, as DES6 asks; DES15) |
| On Nerves, Wi-Fi is a list of `vintage_net_wifi` networks, with each SSID and password read from environment variables at build time, never in Git: the hotspot with the higher priority, the lab network optional | OUR (DES15) |
| On Nerves, the SSH keys (the user's and the partner's) are read at build time from a file outside Git, given by an environment variable | OUR (DES15) |
| On Nerves, the firmware application is `:temporary`: if it stops, the virtual machine stays alive and the Pi does not reboot, except a crash loop at boot, which the startup guard turns into a reboot after 15 minutes | OUR (same as DES13 with systemd; the startup guard validates a new firmware, DES15) |
| On Nerves, the replica's notices go to the Pi's console (HDMI screen); DES9 does not change | OUR (DES15) |
| On Nerves, another Wi-Fi network can be added at run time from the IEx console with `VintageNetWiFi.quick_configure/2`, kept across restarts | OUR (the Pi also works outside the hotspot and the lab, DES15) |
| On Nerves, the node table is a `:nodes` list in the firmware configuration, empty by default | OUR (discovery first, as DES6; DES15) |
| On Nerves, a change of IP is handled by restarting the Pi | OUR (as on the other platforms; the history file does not depend on the IP, REQ13, DES4.5, DES14) |
---

## 3. Treedoc

*Covers: REQ2, REQ3, REQ4, REQ6, REQ7, REQ8, CON4.*

### 3.1 Identifiers (PosID)

Each character has a unique, immutable PosID. A PosID is a **path** in an extended binary tree (PAP3.1): a list of steps, starting at the root.

In this project, **every step carries a disambiguator**:

```elixir
# A step:  {bit, seq, node}
#   bit:  0 = left child, 1 = right child
#   {seq, node}: disambiguator (identifies the mini-node)
# A PosID: a list of steps, for example
[{1, 1, :"crdt1@127.0.0.1"}, {1, 2, :"crdt1@127.0.0.1"}]
```

- The **virtual root** is the empty path `[]`. It has no character and is never shown.
- The paper allows steps without a disambiguator (children of the major node). With our way of generating PosIDs (DES3.4) they never occur, so all steps have the same format. This is valid according to PAP3.1: the disambiguator is included "whenever the path follows a child of a mini-node explicitly".

### 3.2 Disambiguator

- The disambiguator is `{seq, node}`. `seq` is the number of the operation according to the vector clock of the node that created it (DES4.1), and `node` is the name of the node (an atom).
- It is unique because each node numbers its operations 1, 2, 3… and never repeats a number (DES4.6).
- Order (PAP3.3.1, UDIS): first `seq` and then `node`. In Elixir it is enough to compare the tuples `{seq, node}` with `<`; atoms are compared by their text, the same on every machine.

### 3.3 Order (PAP3.1)

The text is the **in-order** traversal of the tree: for each mini-node, first its left subtree, then the character and then its right subtree. The mini-nodes of the same major node are ordered by disambiguator.

Comparison function `compare(a, b)` that returns `:lt`, `:eq` or `:gt`:

1. Walk the two paths step by step while the steps are equal.
2. If both end at the same time: `:eq`.
3. If `a` ends first (`a` is a prefix of `b`), `b` is in the subtree of `a`. Look at the next step of `b`: if its bit is `0`, `b` goes before `a` (`:gt`); if it is `1`, `b` goes after (`:lt`).
4. If `b` ends first: the symmetric case.
5. If they differ at a step: if the bits are different, the one with bit `0` goes first. If the bits are equal, the one with the smaller disambiguator (`{seq, node}`) goes first.

This is exactly the formal definition of PAP3.1 applied to paths where every step has a disambiguator.

### 3.4 Generating a new PosID (our simplification)

*Covers: REQ3, REQ8.*

To insert a character between two visible characters `p` (the left one) and `f` (the right one):

- `p` is the PosID of the visible character to the left of the cursor, or `[]` (the root) if the cursor is at the start.
- `f` is the PosID of the visible character to the right of the cursor, or `nil` if the cursor is at the end.
- `d = {seq, node}` is the disambiguator of the new operation.

Rule:

```
if f != nil and p is a prefix of f:   new = f ++ [{0, seq, node}]   # left child of f
otherwise:                            new = p ++ [{1, seq, node}]   # right child of p
```

Why it is correct: in the in-order traversal, the right subtree of `p` comes right after `p`, and the left subtree of `f` comes right before `f`.
- If `f` is in the right subtree of `p` (that is, `p` is a prefix of `f`), the left subtree of `f` lies between `p` and `f`.
- Otherwise, the subtree of `p` ends before `f`, and its right subtree lies between `p` and `f`.

There may be tombstones between `p` and `f`; it does not matter, because they are not shown.

This rule replaces Algorithm 1 of the paper (PAP3.2), which has four cases. An insert only needs a fresh, unique PosID that falls between `p` and `f` (density, PAP2.1; insert, PAP2.2), so any rule that gives one is valid.

Difference with Algorithm 1: its lines 4 and 5 make a child of the major node (a step without a disambiguator); ours makes a child of the mini-node. The rule was checked with a simulation of 400 random runs with three replicas: each character ended where the user typed it, there were no repeated PosIDs and the replicas converged.

### 3.5 State and functions of the CRDT

The `Crdt.Treedoc` module knows nothing about the network or clocks. It follows the shape seen in class (`new`, `prepare`, `effect`, `value`):

```elixir
# State
%{chars: %{posid => "a"}, dead: MapSet.new([posid, ...])}

new() :: state

# prepare runs only on the node where the user edits. It reads the state and decides the operation.
prepare(state, {:insert, index, ch}, {seq, node}) :: {:ok, %{op: :ins, pos: posid, ch: ch}} | {:error, :invalid_index}
prepare(state, {:delete, index}, _dot)            :: {:ok, %{op: :del, pos: posid}}         | {:error, :invalid_index}

# effect runs on every node, the origin included.
effect(state, %{op: :ins, pos: pos, ch: ch}) :: state   # adds pos => ch to chars
effect(state, %{op: :del, pos: pos})         :: state   # adds pos to dead (tombstone)

# value returns the visible text
value(state) :: String.t()
```

Details:
- A "character" is a grapheme (`String.graphemes/1`): what the user sees as one letter, for example `"á"` or `"ñ"`, even if internally it takes several Unicode code points.
- `index` starts at 0 and counts only visible characters. Inserting at `index` leaves the new character at that position. Deleting at `index` deletes the visible character at that position.
- `value` sorts the keys of `chars` with `compare/2`, removes the ones in `dead` and concatenates.
- A tombstone keeps its character: `chars` still has `pos => ch`. The paper's tombstone discards the atom (PAP3.3.2). (OUR: to show `del "a"`, DES9.)
- Helper function `debug_rows(state)`: sorted list of `{ch, pos, deleted?}`, for `Crdt.debug()`. `Crdt.Replica` also uses it to count the visible characters when it checks an index.
- With short documents, sorting on every call is enough. There is no need to optimize.
- `ch` is exactly one grapheme; the caller guarantees it (`Crdt.insert` splits the text with `String.graphemes/1`).

### 3.6 Example (scenario of figures 3 and 4 of the paper)

1. One node types "abcdef" in a row. Each character becomes the right child of the previous one.
2. Two nodes insert `W` and `Y` between `c` and `d` at the same time. Both become left children of `d`, in the same major node, ordered by disambiguator. If `W`'s is smaller: "abcWYdef".
3. Then someone inserts `X` between `W` and `Y`. Result: "abcWXYdef".

The tree that forms is not the same as in figure 2 of the paper (there `c` is the root; here "abcdef" is a chain of right children). What is reproduced is the scenario and the result.

This scenario must be in the tests.

---

## 4. Causal and reliable delivery

*Covers: REQ4, REQ9, REQ10, REQ11, REQ12, REQ13, REQ19, REQ20.*

This layer guarantees that each operation is applied exactly once on each node and after the operations it depends on. The paper assumes this delivery; here we implement it.

### 4.1 Vector clock

- A map `%{node => integer}`: how many operations of each node have been applied. A missing key counts as 0 (`Map.get(vc, k, 0)`).
- Local operation on node `me`:
  1. The candidate `seq = vc[me] + 1` and the candidate clock `Map.put(vc, me, seq)` are computed, without storing them yet. `Crdt.Causal.next_local/2` does this computation and has no side effects.
  2. `prepare` is called with the disambiguator `{seq, me}`.
  3. **Only if `prepare` returns `{:ok, op}`**, the candidate clock becomes the node's clock and travels in the message. If `prepare` returns an error (for example, an invalid index), nothing is stored.
- A call with several characters repeats steps 1 to 3 for each character, on the clock and state left by the previous one. The full order of the call, with the file and the sending, is in DES4.5.
- Why it matters: if a sequence number were left without a message, the other nodes would wait for that number forever and would not apply any later operation of that node.

### 4.2 Rule when receiving a message from `i` with clock `m`

- **Drop** (duplicate) if `m[i] <= vc[i]`.
- **Apply** if `m[i] == vc[i] + 1` and for every other node `k`: `m[k] <= vc[k]`. To apply: `effect`, then `vc[i] = m[i]`.
- **Wait** in the buffer in any other case. If the buffer already has a message with the same `from` and the same `m[from]`, no other copy is added.
- What a waiting message still needs is described as a map `%{node => seq}` with the last number needed from each node: for `i`, `m[i] - 1` if `m[i] > vc[i] + 1`; for each other `k`, `m[k]` if `m[k] > vc[k]`. It is used in the "waiting" console message and in `Crdt.status()` (DES9); `Crdt.Causal.missing/2` computes it.
- After each applied operation, check the buffer: apply those that can now be applied, drop the duplicates and repeat until nothing changes.

### 4.3 Forwarding (reliable delivery)

- Every operation that a node applies after receiving it from the network (by any path, even if its `from` is the node itself) is forwarded once by broadcast, unchanged, with its original `from` and `vc`. Duplicates are dropped with the rule of DES4.2, so the forwarding ends.
- So, if the origin managed to send it to only one node and then went down, it still reaches everyone.
- Note: Erlang keeps the order of messages between each pair of nodes, so on a single computer "waiting" is almost never seen. Disorder shows up with forwards along different paths between three or more nodes (an operation arrives by a forward before its dependency arrives from the origin) and when catching up after a reconnection; that is why causal delivery is needed. (OUR.)

### 4.4 History

- Each node keeps, in memory and in a file, the list of all the operations it has applied (its own and the others'), in the order in which it applied them. That order respects causality.
- A node broadcasts its whole history, in order, in three cases:
  1. When it receives `:nodeup` from any node.
  2. When `Crdt.Replica` starts, if there are nodes already connected (because their `:nodeup` may have arrived before the replica existed): a single broadcast of the history to the nodes already connected (REQ15). (OUR.)
  3. When it receives a `{:hello, node}` message from any node.
- Start order of the replica (`init`):
  0. Read the table (DES6), if `NODES_FILE` is set; if it cannot be read, report it and return `:ignore`. It comes before loading the history, so that a bad table never opens the file. (OUR.)
  1. Load the history from the file (DES4.5). If the file is damaged, report it and return `:ignore`.
  2. Turn on `:net_kernel.monitor_nodes(true)`.
  3. A single broadcast of the history to the nodes already connected (case 2).
  4. Broadcast `{:hello, me}`.
  5. Start the connection timer: a first attempt right away and then one every 2 seconds. Each attempt spawns a separate process for each node of the table that is not in `Node.list()`; that process only calls `Node.connect/1` (DES6 and DES7.1).
- Why the `hello` is needed: Erlang connects the nodes as soon as the virtual machine starts, before `Crdt.Replica` exists. If another node sends its history at that moment, the message is lost silently, because there is no registered process yet to receive it. The `hello` asks the others to send it again once the replica exists.
- The others drop what they already have.

### 4.5 History file

- File `<data_dir>/<name>.jsonl`, where `<name>` is the part of the node name before `@`; with the default options (DES8), `data/crdt1.jsonl` for `crdt1@127.0.0.1` and `data/pi-pe.jsonl` for `pi-pe@172.20.10.4`. It does not depend on the IP, so a node that comes back with a new IP finds its file (REQ13). (OUR.)
- The clock and the PosIDs keep the full node name. After a new IP, the loaded operations keep their old name and the node starts a new clock entry: its new operations are numbered from 1 under the new name. No number repeats, because each name is used by one machine only (DES6) and all its own operations are in its own file. The clock gains one entry per new IP. One JSON line per operation (format in DES5.2).
- A line is **complete** if it ends in `"\n"` and its content is valid JSON.

**Required order for a local call** (`insert` or `delete`, of one or several characters; see also DES7):
1. Check the index and, if it applies, `count`. If they are not valid, return `{:error, :invalid_index}` without changing anything: not the document, not the clock, not the file.
2. If they are valid, generate and apply in memory all the operations, one per character, each on the state left by the previous one (`next_local`, `prepare`, keep the clock and `effect`; DES4.1).
3. Write all the lines to the file and do **a single** `:file.sync/1`.
4. Add the operations to the in-memory history and send all the messages, in order.

Nothing leaves the node before the `:file.sync/1`. If the text is empty or `count` is 0 and the index is valid, the call answers as a successful edit without generating operations.

**Applied remote operation:** first write its line and do its own `:file.sync/1`; then the "applied" notice (DES9), forward it (DES4.3) and add it to the history. So "applied" means it is already on disk. (OUR.) The order of the last two is not observable: both happen inside the same call of the single replica process (DES7).

**If the write or the `:file.sync/1` fails:** the replica is let crash. The supervisor restarts it and the replica reloads from disk. Since nothing was sent, there is no inconsistency with the other nodes. If the disk keeps failing, the supervisor gives up (by default, more than 3 restarts in 5 seconds) and the `crdt` application stops; the virtual machine and IEx stay alive and the `Crdt` functions return `{:error, :no_replica}`, as the general rule of DES6 says. (OUR.)

**At start** (step 1 of the start order of DES4.4):
- Read the file line by line. For each operation, apply `effect` directly and do `vc[from] := m[from]`, without going through `Crdt.Causal`, without forwarding it and without writing it again. This recovers the document, the clock and the history. The file has no gaps, because each operation is written in the order in which it was applied.
- **If the last line is not complete** (for example, after a power cut while it was being written): report it in the console, truncate the file at the byte where that line starts (`:file.position/2`, then `:file.truncate/1` and `:file.sync/1`) and go on. That operation never left the node, because nothing is sent before the sync. Without truncating, the next line would be glued to the fragment and there would be a damaged line in the middle.
- Only after loading (and truncating, if needed) is the file opened in append mode. If the file does not exist, this open creates it empty: the first start leaves a 0-byte file. (OUR.)
- **If the file cannot be read** (an error other than it not existing) **or cannot be opened for appending** (for example, because the `data_dir` folder is missing): `init` prints `cannot open history file <path> (<reason>): replica not started. Check that the folder exists and restart the node.`, with the reason from `:file.format_error/1`, and returns `:ignore`. It does not create the folder or print "history loaded". (OUR.)
- **If a line that is not the last one is not complete**, the file is damaged. `init` prints what happened and what to do (delete that file and restart the node, so that it catches up with the others) and returns `:ignore`. So the virtual machine and IEx stay alive and systemd does not enter a restart loop. While the replica is not running, the `Crdt` functions return `{:error, :no_replica}` (DES9). Skipping that line would leave a gap in the clock that could never be recovered.

### 4.6 Why the file is needed

Without the file, a node that restarts numbers its operations from 1 again. The others would drop them as duplicates and the texts would differ.

---

## 5. Messages

*Covers: REQ5, REQ6, REQ18.*

### 5.1 In memory and over the network (Elixir terms)

```elixir
%{op: :ins, from: :"crdt1@127.0.0.1", vc: %{:"crdt1@127.0.0.1" => 3}, pos: [{1, 3, :"crdt1@127.0.0.1"}], ch: "a"}
%{op: :del, from: :"crdt2@127.0.0.1", vc: %{:"crdt1@127.0.0.1" => 3, :"crdt2@127.0.0.1" => 1}, pos: [{1, 3, :"crdt1@127.0.0.1"}]}
```

They are sent with `GenServer.cast({Crdt.Replica, node}, {:remote, msg})`.

There is also a control message, with no operation: `GenServer.cast({Crdt.Replica, node}, {:hello, me})` (DES4.4). It is not stored in the history.

### 5.2 In the file (JSON, one line per operation)

```json
{"op":"ins","from":"crdt1@127.0.0.1","vc":{"crdt1@127.0.0.1":3},"pos":[[1,3,"crdt1@127.0.0.1"]],"ch":"a"}
{"op":"del","from":"crdt2@127.0.0.1","vc":{"crdt1@127.0.0.1":3,"crdt2@127.0.0.1":1},"pos":[[1,3,"crdt1@127.0.0.1"]]}
```

- Conversion in `Crdt.LogFormat`: atoms to text, step tuples to lists `[bit, seq, "node"]`, and back with `String.to_atom/1`.
- `from_json_line/1` is tolerant: it checks the types (`op` is `"ins"` with a text `ch`, or `"del"`; `from` is text; `vc`, a map of integers; `pos`, a list of `[0 or 1, integer, text]`), but it accepts extra keys (a `ch` in a `del` is ignored) and does not check that `ch` is a single grapheme or that `from` is in `vc`. The lines are written by our own code. (OUR.)
- The `JSON` module included in Elixir 1.18 is used (`JSON.encode!/1`, `JSON.decode/1`). No external libraries.

---

## 6. Network

*Covers: REQ1, REQ12, REQ14, REQ15, CON2, CON3.*

- **Erlang distribution.** Each node starts with `--name` and `--cookie`. On Nerves the firmware gives them at run time (DES15). The cookie is a shared key: only nodes with the same cookie connect. The cookie is `cpd2026`, agreed with the other teams so we can test with each other. With a shared cookie, nodes of other teams can connect to ours and then receive our operations, like any connected node (DES14). (OUR.)
- **Node names:** `<hostname>@<IPv4>`, always with the IPv4, never `.local`. (OUR.)
  - The start scripts (DES11) build it: the machine's hostname, lowercased, with every character that is not `a-z`, `0-9`, `_` or `-` changed to `_`; for example `pi-pe@172.20.10.4`.
  - Several nodes on one machine get a suffix: `pi-pe-1@IP`, `pi-pe-2@IP`. Locally the tests use the names `crdt1@127.0.0.1`, `crdt2@127.0.0.1` and `crdt3@127.0.0.1`, given to the script.
  - Every machine needs its own hostname: two Pis left as `raspberrypi` would use the same name part, and therefore the same clock entries after a change of IP.
  - Why the hostname and not a fixed `crdt`: the IP changes between networks, so the node name changes too (DES4.5). If every machine were `crdt@IP`, a machine that later gets the IP another machine used before would continue that machine's numbering, and could repeat sequence numbers that the others drop as duplicates.
- **Membership:** the nodes of the cluster are all the connected nodes, `Node.list()`. Operations, forwards, histories and `hello` go to all of them. Hidden nodes (remote consoles started with `--hidden`, the control node of the tests) are not in `Node.list()` and receive nothing. (ASG, OUR.)
- **How a node gets connected (hybrid):**
  - **Discovery** (DES6.1), always on unless `DISCOVERY=off`: our nodes announce themselves on the local network and connect to each other.
  - **Node table** (optional): a text file with one node name per line; lines that start with `#` are comments. Each line is cleaned with `String.trim/1`, because of Windows CRLF line endings. The file is chosen with the `NODES_FILE` environment variable; without it the table is empty. `nodes.example.txt` is an example. The same file works on every machine; each node skips itself. It is for nodes that discovery cannot reach (multicast blocked, another network).
  - **Erlang connects the rest:** when two nodes connect, each one also connects to the nodes the other already knows (`global`, on by default). So if another node has my IP in its table, my node takes part with no change on my side.
- **Connection to the table:** at start (last step of the start order of DES4.4) and then every 2 seconds, `Crdt.Replica` spawns a separate, short-lived process (`spawn/1`) for each node of the table that is not in `Node.list()`. That process only calls `Node.connect/1` and does not touch the replica's state. If it connects, the `{:nodeup, n}` notice reaches the replica's mailbox like any other message. Why it is not done inside the replica: DES7.1. (OUR.)
- **Trust:** the messages of connected nodes are trusted; a malformed one crashes the replica, which restarts from its file (DES4.5). (OUR.)
- **Up and down:** with `:net_kernel.monitor_nodes(true)`, the node receives `{:nodeup, n}` and `{:nodedown, n}` for every visible node. With `:nodeup`, it resends its history (DES4.4). With `:nodedown`, it only reports it in the console.
- **Broadcast:** send the message to each node in `Node.list()`. A node without a process `Crdt.Replica` (for example a remote console started without `--hidden`) drops the cast silently.
- **Ports:** Erlang uses 4369 (EPMD) and one distribution port per node. The start scripts fix the distribution ports to the range 4218 to 4228 with `ERL_AFLAGS="-kernel inet_dist_listen_min 4218 inet_dist_listen_max 4228"`, so a firewall needs fixed rules only: TCP 4369, TCP 4218 to 4228 and UDP 45892 (discovery). (OUR.)
- If the node is started without `--name`, the application does not start `Crdt.Replica` or `Crdt.Discovery` and shows a clear message with the right command, but it does not fail either. The message has two commands: the PowerShell one and the macOS and Linux one (DES11). (OUR.) The `Crdt` functions return `{:error, :no_replica}` (DES9). So `mix test`, which runs without `--name`, keeps working.
- **Invalid configuration (general rule):** if the configuration is not valid, the replica does not start, the console says what to fix, and the virtual machine and IEx stay alive; the `Crdt` functions return `{:error, :no_replica}`. Same as without `--name`. Cases: no `--name` (above); `NODES_FILE` points to a file that does not exist or cannot be read (`init` prints the file name and what to do, fix `NODES_FILE` and restart the node, and returns `:ignore`); damaged history or a history file that cannot be read or opened (DES4.5). If the discovery socket cannot be opened, only discovery is missing: `Crdt.Discovery` prints why and returns `:ignore`, and the replica and the table keep working (DES6.1). (OUR.)

### 6.1 Discovery

*Covers: REQ14.*

- `Crdt.Discovery` is a small GenServer, started by the application after `Crdt.Replica` on a named node, unless the environment variable `DISCOVERY` is `off`. (OUR.)
- **Announcement:** every 2 seconds, starting at once, it sends one UDP packet with the text `crdt-treedoc-1 <node name>` (for example `crdt-treedoc-1 pi-pe@172.20.10.4`) to the multicast group 233.252.1.32, port 45892, with TTL 1 (it does not leave the local network) and loop on (other nodes of the same machine hear it). The multicast interface is the IP of the node name (`127.0.0.1` locally, the Wi-Fi IP on a network); if the host part is not an IPv4, the system default.
- **Listening:** the socket binds port 45892 and joins the group on that interface. Only one socket per machine can bind the port (sharing it needs socket options that differ per OS). If the port is busy, for example because another node of the same machine has it, the node opens a socket on a free port and only announces: the listener of its machine, or of another machine, hears it and connects, and Erlang connects the rest (DES6).
- **On a packet:** if it starts with the tag `crdt-treedoc-1 `, the rest is a node name. The node remembers it as "announced" (for `Crdt.status()`). If the name is not its own and is not in `Node.list()`, it spawns a short-lived process that calls `Node.connect/1`, the same rule as DES7.1. A packet without the tag, its own announcement, or a node already connected open no connection. So two connected nodes do not reconnect every 2 seconds.
- **Failure:** if the socket cannot be opened at all, it prints `discovery off: cannot open UDP port 45892 (<reason>). Use a node table (NODES_FILE).` and returns `:ignore`. A failed send (for example, the Wi-Fi is down for a moment) is ignored; the next announcement tries again.
- The name in a packet becomes an atom only after the tag check. On our own network that is enough (DES14).
- If multicast is filtered by the network, `scripts/multicast_check.exs` shows it (NETWORK.md), and a node table is the way out.

---

## 7. Concurrency inside each node

*Covers: REQ16, REQ20.*

- A single GenServer, `Crdt.Replica`, owns all the state: document, vector clock, buffer, history and open file.
- Local edits (`GenServer.call`) and remote messages (`GenServer.cast`) are handled one at a time, so there are no race conditions.
- **Inserting or deleting several characters is a single call.** `Crdt.insert(index, "text")` and `Crdt.delete(index, count)` make a single `GenServer.call`. First the index (and `count`) is checked; if it is not valid, the call answers with an error without changing anything. If it is valid, inside that call all the operations are generated and applied, one per character, each on the state left by the previous one; then all the lines are written with a single `:file.sync/1` and the messages are sent in order (DES4.5). So no remote message slips in between two characters of the same text, which stays together.
- `delete(index, count)` deletes `count` times at `index`, each time on the state left by the previous one, in the same call.

### 7.1 One GenServer per node: benefit and cost

- There is a single GenServer per node. It handles one message at a time and its state is private: nobody else reads or changes it. That is why there are no race conditions.
- The flip side: a slow task inside the GenServer blocks everything else, local edits included.
- Example: `Node.connect/1` to a node that is down can take several seconds, and `GenServer.call` gives up after 5 seconds (the default), so `Crdt.insert` would fail meanwhile.
- That is why the connect runs in a separate, short-lived process that does not touch the state (DES6). The result reaches the replica as one more `:nodeup` message. (OUR.)

---

## 8. Modules

*Covers: CON1, CON5.*

`lib/` has no external dependencies: only Elixir 1.18 or later and OTP (CON1). `firmware/` depends on Nerves (DES15). Each module is small and has a single responsibility, so the code can be understood and explained in class.

| Module | Responsibility | Has effects (network, file) | Budget (lines) |
|---|---|---|---|
| `Crdt` | API to use from IEx: edit, `text`, `status`, `history` and `debug` | No (calls `Crdt.Replica`) | 60 |
| `Crdt.Application` | Starts the supervisor and checks that the node has a name; starts discovery unless `DISCOVERY=off` | Yes | 25 |
| `Crdt.Treedoc` | The CRDT: `new`, `prepare`, `effect`, `value`, `compare`, `debug_rows` | No | 90 |
| `Crdt.Causal` | Causal delivery rules: duplicate, deliverable, check the buffer, what is missing (`missing/2`, for `status` and the "waiting" notice) | No | 70 |
| `Crdt.LogFormat` | Conversion of messages to JSON and back | No | 40 |
| `Crdt.Config` | Read the optional node table | Reads a file | 20 |
| `Crdt.Discovery` | Announce the node and connect to the nodes heard on the local network (DES6.1) | Yes (UDP) | 60 |
| `Crdt.Replica` | GenServer: joins everything, handles network, file and console | Yes | 250 |
| `CrdtFw` (in `firmware/`, only on Nerves, DES15) | Starts the node on Nerves: waits for the IPv4, starts the distribution, then the replica and discovery under its own supervisor | Yes | 80 (not counted with `lib/`) |
| `CrdtFw.Application` (in `firmware/`, only on Nerves, DES15) | Starts `CrdtFw.Supervisor` with `CrdtFw` | No | 15 (not counted with `lib/`) |

The budget counts physical lines that are not empty, are not comments and do not belong to `@moduledoc` or `@doc`. It is a reference cap, not a goal. `CrdtFw` and `CrdtFw.Application` are not in `lib/`: they are outside the budget of `lib/` and have their own (DES15). `CrdtFw` has 80: DES15 has seven steps, and each one that can fail gives its own message instead of a crash (DES6), in one process with one job (CON5).

`Crdt.Treedoc`, `Crdt.Causal` and `Crdt.LogFormat` are pure functions: they are tested with tests without network.

`Crdt.Replica.start_link/1` accepts options so it can be tested in `mix test`, which runs without `--name`:
- `:me`: node identifier (default `node()`).
- `:nodes`: node table (default, the one from `Crdt.Config`; empty without `NODES_FILE`).
- `:data_dir`: history folder (default `"data"`).
- `:name`: registered name of the process (default `Crdt.Replica`).

If the history is damaged in the middle or the history file cannot be read or opened (DES4.5), or if `:nodes` is not given and the table file cannot be read (DES6), `start_link/1` returns `:ignore`.

In a test there are no connected nodes (`Node.list()` is empty), so the replica sends nothing over the network.

`Crdt.Discovery.start_link/1` accepts, for the tests, `:me` (the name it announces, default `node()`), `:ip` (the multicast interface, default the IP of the node name) and `:port` (default 45892); it registers as `Crdt.Discovery`. If the socket cannot be opened it returns `:ignore` (DES6.1).

---

## 9. Interface (IEx)

*Covers: REQ3, REQ4, REQ17, REQ19, REQ20, CON6.*

```elixir
Crdt.insert(index, "text")    # inserts each character starting at index
Crdt.delete(index)            # deletes one character
Crdt.delete(index, count)     # deletes count characters starting at index; if there are not enough, error and nothing is deleted
Crdt.text()                   # visible text
Crdt.status()                 # node, table file and nodes, discovery, connected nodes and how each was found, clock, history size, waiting operations and path of the history file
Crdt.history()                # the last 10 applied operations
Crdt.history(:all)            # every applied operation, in the order in which they were applied
Crdt.debug()                  # each character with its PosID and whether it is deleted
```

- `insert` and `delete` check the index (and `count`) first. If it is not valid, they return `{:error, :invalid_index}` without changing anything.
- Valid indices: for `insert`, from 0 to the length; for `delete`, from 0 to length - 1, also with `count` 0 (`delete(0, 0)` on the empty document is an error). (OUR.)
- An index or a `count` that is not an integer greater than or equal to 0 is invalid: `{:error, :invalid_index}`, without changing anything. If the text of `Crdt.insert` is not a string, the function fails in the calling process (guard in `Crdt`), without reaching the replica. (OUR.)
- With an empty text or `count` 0 and a valid index, they answer as a successful edit, without generating operations.
- If the replica is not running (because `--name` is missing, because the table file cannot be read, DES6, or because the history is damaged or cannot be read or opened, DES4.5), every `Crdt` function returns `{:error, :no_replica}`.
- `Crdt.status()` shows the node, the table file (`none` without `NODES_FILE`), the nodes of the table (without the node itself), the state of discovery (line `discovery: listening on 45892`, `discovery: announce only` or `discovery: off`), every connected node (line `connected: ...`: those of `Node.list()`, the same set as the broadcast, DES6, each followed by how it was found: `(table)` if it is in the table, `(announced)` if discovery heard it, `(other)` otherwise, for example connected by another node; `none` if there are none; OUR.), the clock, the size of the history and each waiting operation with what it is missing, in the format of the "waiting" notice (below). It also shows the path of the history file, in a line `history file: ...`, so it is not confused with the table file (`nodes file: ...`). (OUR.) This is how it meets REQ17 for the buffer.
- `Crdt.history()` shows the last 10 applied operations, one per line (`op 3 from crdt1@127.0.0.1: ins "a"`), after `... N earlier ops` if there are more. `Crdt.history(:all)` shows them all, in the order in which they were applied. This is how it meets REQ17 for the history. (OUR.)
- A delete is shown with the deleted character: `op 4 from crdt1@127.0.0.1: del "a"`, both in `history` and in the "applied" notice. The character is taken from the document: the tombstone keeps it (DES3.5), and causal delivery guarantees that the insert was applied before the delete (DES4.2). (OUR.)
- `status`, `history` and `debug` ask the replica for the data with a `GenServer.call` and print in the calling process. So the output appears in the console where the command was typed, also if it is a remote console (`--remsh`, DES13). They return `:ok`, or `{:error, :no_replica}` if the replica is not running. The tests capture the output with `ExUnit.CaptureIO`. (OUR.)
- The replica's notices (list below) are printed by the replica, so they appear in the node's console.
- Local edits do not print the "applied" notice. Notices are for what arrives from the network and for connections. (OUR.)

Console messages, always with the node name at the start:
- `[crdt2@127.0.0.1] applied op 3 from crdt1@127.0.0.1: ins "a"`
- `[crdt2@127.0.0.1] applied op 4 from crdt1@127.0.0.1: del "a"`
- `[crdt2@127.0.0.1] waiting op 5 from crdt3@127.0.0.1 (missing: crdt1@127.0.0.1 up to 4)`
- `[crdt2@127.0.0.1] duplicate dropped: op 3 from crdt1@127.0.0.1`
- `[crdt2@127.0.0.1] connected crdt3@127.0.0.1: resending history (12 ops)`
- `[crdt2@127.0.0.1] disconnected crdt3@127.0.0.1`
- `[crdt2@127.0.0.1] hello from crdt3@127.0.0.1: resending history (12 ops)`
- `[crdt2@127.0.0.1] cannot read nodes file nodes.txt (no such file or directory): replica not started. Fix NODES_FILE and restart the node.`
- `[crdt2@127.0.0.1] history loaded: 12 ops` (always when loading ends, also with 0 ops. It comes before the network notices, such as "connected" or "hello from", and it is not printed if the replica does not start. OUR)
- `[crdt2@127.0.0.1] cannot open history file data/crdt2.jsonl (no such file or directory): replica not started. Check that the folder exists and restart the node.`
- `[crdt2@127.0.0.1] history: last line was incomplete; removed from file`
- `[crdt2@127.0.0.1] history corrupted at line 7 of data/crdt2.jsonl: replica not started. Delete that file and restart the node to catch up with the others. Do not edit on this node until its text matches the others.`
- `[crdt2@127.0.0.1] discovery off: cannot open UDP port 45892 (address already in use). Use a node table (NODES_FILE).` (printed by `Crdt.Discovery`, DES6.1)

---

## 10. Repository files

```
mix.exs
.formatter.exs
.gitignore
.gitattributes                          (LF line endings in every working copy)
lib/crdt.ex
lib/crdt/application.ex
lib/crdt/treedoc.ex
lib/crdt/causal.ex
lib/crdt/log_format.ex
lib/crdt/config.ex
lib/crdt/replica.ex
test/...
nodes.example.txt                       (example node table, only comments)
scripts/start.ps1                       (start script, Windows, DES11)
scripts/start.sh                        (start script, macOS and Linux, DES11)
scripts/multicast_check.exs             (checks whether multicast works on a network, DES6.1)
data/            (only data/.gitkeep goes to Git)
deploy/README-pi.md                     (guide for the Raspberry Pis with Raspberry Pi OS)
deploy/README-nerves.md                 (guide for a Pi 4 with Nerves: ready image or own build, DES15)
deploy/crdt.service                     (systemd service, DES13; not included yet)
README.md
LICENSE                                 (MIT)
docs/REQUIREMENTS.md
docs/DESIGN.md
docs/TESTS.md                           (guide to the automated tests)
docs/MANUAL-TESTS.md                    (manual test guide with three terminals)
docs/NETWORK.md                         (several computers on the same network)
docs/CODE-MAP.md                        (guide to study the code)
docs/INTEGRATION.md                     (contract for another team: join the cluster, discovery, our operation protocol)
firmware/mix.exs                        (Nerves firmware project, target rpi4; depends on :crdt with path: ".." and runtime: false, DES15)
firmware/mix.lock                       (versions of Nerves and its dependencies, written by the first build)
firmware/.formatter.exs                 (mix format in firmware/; plain inputs, no import_deps)
firmware/config/config.exs              (common configuration; imports host.exs or target.exs)
firmware/config/host.exs                (configuration on the computer)
firmware/config/target.exs              (Wi-Fi, SSH keys and node table, read from environment variables at build time)
firmware/rel/vm.args.eex                (VM flags; no distribution lines, DES15)
firmware/lib/crdt_fw/application.ex     (the firmware application, :temporary, and CrdtFw.Supervisor)
firmware/lib/crdt_fw.ex                 (CrdtFw: start order of DES15 and CrdtFw.NodeSupervisor)
```

---

## 11. Start scripts and running locally

*Covers: CON3.*

- One start command per machine: `scripts/start.ps1` on Windows (PowerShell) and `scripts/start.sh` on macOS and Linux (also the Pi). (OUR.) A Pi with Nerves has no start script: the firmware does the same steps (DES15).
- What the script does, in order:
  1. Name: the hostname, made safe (DES6), unless a name is given (`-Name` / `--name`, or `CRDT_NAME`). With `-Node N` / `--node N` it adds the suffix `-N`.
  2. IP: the IPv4 of the Wi-Fi, by the rule below, unless an IP is given (`-Ip` / `--ip`, or `CRDT_IP`).
  3. It prints the node name, the IP and the interface.
  4. `mix compile`.
  5. It sets `ERL_AFLAGS` with the distribution port range 4218 to 4228 (DES6) and runs `iex --name <name>@<IP> --cookie cpd2026 -S mix` (`iex.bat` on Windows: plain `iex` is another Windows command). The environment variables `NODES_FILE` and `DISCOVERY` reach the node as they are.
- Rule to pick the IP (the multicast interface is the same, DES6.1):
  - Windows: the default IPv4 routes (`0.0.0.0/0`) whose adapter is physical and up (`Get-NetAdapter -Physical`), so Hyper-V `vEthernet` adapters and VPNs are skipped. Among them, the Wi-Fi one (802.11); if there is no Wi-Fi one, the only one left. Its IPv4, skipping `169.254.*`.
  - macOS: the interface of `route -n get default`, if it is not a VPN tunnel (`utun*`, `ppp*`); its IPv4 with `ipconfig getifaddr`.
  - Linux and Pi: the devices of `ip -4 route show default`; the Wi-Fi one (`wl*`), or else the only one; its IPv4 with `ip -4 -o addr show dev`.
  - If it cannot decide (no default route, several candidates, no IPv4), the script lists what it found and exits, asking for the IP. It never guesses.
- Locally, three nodes on one computer: `crdt1@127.0.0.1`, `crdt2@127.0.0.1` and `crdt3@127.0.0.1`, started with the script and a given name and IP (for example `.\scripts\start.ps1 -Name crdt1 -Ip 127.0.0.1`), one terminal per node, with no node table: discovery on `127.0.0.1` finds them (DES6.1).
- First, once and in a single terminal: `mix compile`. That way the three nodes do not try to compile at the same time in the same folder.
- The commands, for PowerShell and for macOS and Linux, are in [README.md, "Quick start"](../README.md#quick-start).
- To start from scratch: halt every node and delete the `.jsonl` files of `data/` on all of them (`data/.gitkeep` stays). Deleting the history of a single node has its own rules (DES14).
- The manual tests MAN1 to MAN8 are defined in `REQUIREMENTS.md`; their steps are in `MANUAL-TESTS.md` (MAN1: Case 2; MAN2: Cases 5 and 6; MAN3: Case 4; MAN4: Cases 11 and 12; MAN5: Case 13; MAN7: Case 9; MAN8: Case 10). MAN9 to MAN13, between computers, are in its section "Between computers: tests run".

---

## 12. Automated tests (`mix test`)

Each test carries the tag of the requirement it tests (`@tag :req7`). To run only the tests of one requirement: `mix test --only req7`.

The `mix test --cover` threshold is 0 (`test_coverage` in `mix.exs`) because the network of `Crdt.Replica` is tested by hand (MAN1 to MAN8); the coverage report is reviewed, not enforced.

- `compare/2`: prefixes with bit 0 and 1, different bits, same bit with a different disambiguator.
- `prepare` + `effect` on a single node: insert at the start, in the middle and at the end, in an empty document and after deletes. Each character lands at the requested index.
- Scenario of DES3.6 (figures 3 and 4 of the paper).
- Convergence: several simulated replicas that edit at random and exchange messages in random orders, with duplicates, using `Crdt.Causal`. All end with the same text. Use `:rand` with fixed seeds (no external libraries).
- `Crdt.Causal`: apply, wait and drop; the buffer empties in the right order.
- `Crdt.LogFormat`: round trip to JSON with no loss.
- `Crdt.Config`: reads the node table and ignores blank lines and comments; without `NODES_FILE` the table is empty.
- `Crdt.Discovery`: the packet and its parsing; a packet without the tag is ignored.
- `Crdt.Replica` restarted with another node name and the same name part: same text, and the new operations are numbered from 1 under the new name.
- `Crdt.Replica` without network: an invalid index does not change the clock, and `insert` of several characters leaves the text together.
- With real nodes: `test/crdt_distributed_test.exs` starts nodes with `:peer` (OTP 25 or later) on the same computer. It carries `@tag :distributed`, is excluded by default (`test/test_helper.exs`) and runs with `mix test --include distributed`. It checks the forwarding of what leaves the buffer, that a connected node outside any table receives the operations, the history on `:nodeup` and `hello` from any node, that an unreachable node in the table does not block `Crdt.insert`, that the history loaded from the file is sent only once to a node already connected, discovery (two nodes with no table find each other; an announcement connects, its own announcement and a packet without the tag do not; a busy port gives announce only), and the file order (DES4.5): in a local call, a single `:file.sync/1` and then the sends; in a remote operation, sync, "applied" notice and forwarding. (OUR.)
- `Crdt` without a running replica returns `{:error, :no_replica}`.
- `firmware/` and `CrdtFw` are not part of `mix test`: they need the Nerves target. `MIX_TARGET=rpi4 mix firmware` must build with no warnings, and `CrdtFw` is tested by hand on the Pi (MAN14, MAN15). `lib/` does not change for Nerves, so its tests cover it. (OUR.)
- `Crdt.status()` includes the waiting operations with what they are missing; `Crdt.history()` shows the last 10 (with `... N earlier ops` if there are more) and `Crdt.history(:all)` all of them, in order.
- Loading a history: with the last line cut in half, the others are loaded; then a new operation is written and the history loads again with no errors. With a damaged line in the middle, `start_link/1` returns `:ignore`.

---

## 13. Raspberry Pi

*Covers: CON1, CON3.*

- Raspberry Pi OS (64-bit), Lite or with desktop, flashed with Raspberry Pi Imager. The hostname, different on each Pi (for example `crdt-pi1`, `crdt-pi2`; never two left as `raspberrypi`, DES6), the user, SSH and the Wi-Fi of the test network (below) are set there too. (OUR.)
- Install Elixir: `sudo apt install elixir`. On current Raspberry Pi OS (Debian trixie) it installs Elixir 1.18.3 with Erlang/OTP 27. That is why `mix.exs` declares `elixir: "~> 1.18"` and the code uses nothing from Elixir 1.19 or later or from OTP 28 or later, even if it is developed on Windows with newer versions. When in doubt, the simplest alternative is used.
- On the Pi, after getting the code: `mix compile` and `mix test`. What was compiled on Windows does not work on the Pi (another OTP version), so `_build/` is not copied.
- `deploy/README-pi.md` has the steps for the Pis, written without hardware and checked with the Pis.
- The node starts with `scripts/start.sh` (DES11): name `<hostname>@<Wi-Fi IPv4>`, discovery on, no node table. If multicast is blocked on the test network, a table with `NODES_FILE` (DES6).
- MAN6 is done with two Pis (`REQUIREMENTS.md`): MAN2 with two nodes, and MAN4 is halting one Pi, writing on the other, starting it again and seeing that it catches up. A third node is optional: a computer on the same network started with its start script, as in `NETWORK.md`. REQ1 is tested locally with three nodes. The steps of MAN6 go in `deploy/README-pi.md` (not included yet). (OUR.)
- Before MAN6, the connection test, without our code (agreed with the other teams): ping, `Node.connect/1` and `Node.list()`. The steps, and the other network steps, are in [NETWORK.md](NETWORK.md).
- Test network: a lab network, a phone hotspot or a home router. If a Pi cannot join the Wi-Fi, an Ethernet cable, or the Wi-Fi added by SSH with `nmcli` (for example `sudo nmcli device wifi connect "<network>" password "<password>"`). (OUR.)
- With the other Pi off or unreachable, `Crdt.insert` answers at once: the slow `Node.connect/1` runs in a separate process and does not block the replica (DES7.1). It is checked before MAN6. (OUR.)
- systemd service (`deploy/crdt.service`, not included yet) so that the node starts with the Pi and restarts if it fails. What it runs (OUR.):
  - `ExecStart`: the node without IEx (`elixir ... -S mix run --no-halt`, with the full path of `elixir`, `/usr/bin/elixir` with the Debian package), with the name, IP and ports of `scripts/start.sh`. No `iex`: the service has no terminal.
  - `WorkingDirectory`: the project folder on the Pi (for example `/home/<user>/crdt`).
  - `User`: the user created in Raspberry Pi Imager, not a fixed `pi`.
  - `After=network-online.target` and `Wants=network-online.target`.
  - `Restart=on-failure`.
  - `mix compile` is done before, by hand, in the project folder: the service does not compile.
  - If the `crdt` application stops because the disk keeps failing (DES4.5), or if the replica does not start because of an invalid configuration (DES6), the virtual machine stays alive and systemd does not restart it: there is no process failure. It shows in `journalctl` and is fixed by hand.
  - The installation and usage steps go in `deploy/README-pi.md` (not included yet), section "Run as a service".
- Console on a node that runs as a service, on the Pi itself: `iex --name console@127.0.0.1 --cookie cpd2026 --hidden --remsh <node name>`, with the node name printed by the script. With `--hidden`, the console is not in `Node.list()` and receives no operations (DES6).
- For the demo, the node of each Pi runs in the foreground in an SSH session (`./scripts/start.sh`), as on Windows: the commands and the replica's notices are visible there (DES9). Before that the service must be stopped (`sudo systemctl stop crdt`), only if it is installed, because two nodes cannot have the same name. (OUR.)
- Instead of Raspberry Pi OS, a Raspberry Pi 4 can run the node with Nerves firmware (DES15). There is no service, no start script and no `mix compile` on the Pi: the firmware starts the node when the Pi boots.

---

## 14. Known limitations

- **PosIDs grow when typing in a row:** each new character is a child of the previous one, so its path is one step longer. The same happens with Algorithm 1 of the paper, as PAP4.1 says. Every step also repeats the full node name, so the history grows about quadratically when typing in a row (observed between computers: 14 characters gave a history of about 6 KB). For the demo, short texts are enough (fewer than about 300 characters). Balancing, which the same section proposes, is out of scope.
- **`prepare` sorts the whole document on each edit.** With texts of a few hundred characters it is not noticeable; it does not need optimizing.
- **The history grows without limit and is resent whole** on each connection. With short texts it does not matter. The future improvement would be to send each node only what it is missing, using its vector clock.
- **Catching up costs one sync per operation.** When receiving a large history, each new remote operation does its own `:file.sync/1`. On the Pi that can take seconds, and meanwhile a local call may have to wait.
- **Tombstones forever**, with no *flatten* or garbage collection. It is our choice, not a need: with UDIS a deleted leaf could be discarded at once (PAP3.3.1); the paper keeps tombstones for SDIS (PAP3.3.2). We keep them to show deleted characters (DES2).
- **The cookie gives full access to the nodes.** On our own network it is not a problem.
- **Discovery only reaches the local network.** Multicast does not cross routers (TTL 1), and some networks filter it (lab Wi-Fi, client isolation). Then a node table is needed; with `name@IP` in the table, it must be edited when the network changes the IPs (DES6).
- **One discovery listener per machine.** If the node that listens on a machine halts, the other nodes of that machine only announce until one of them restarts. They stay connected to each other, and the listeners of other machines still hear them (DES6.1).
- **Any connected node receives our operations.** Membership is `Node.list()`: a node of another team with the same cookie, or a remote console started without `--hidden`, receives every cast. Without a process `Crdt.Replica` the cast is dropped; a foreign `Crdt.Replica` that sends another format makes ours crash and restart from its file (INTEGRATION.md).
- **Names from announcements become atoms.** A packet with our tag creates an atom with the name it carries. On our own network that is not a problem.
- **Reconnection may be slow.** Once, on a home Wi-Fi, a restarted node reconnected after about 30 s (observed, not measured); on a phone hotspot it was immediate.
- **Node names are public inside the cluster.** The node name is announced to every node and stored in every op and history file. On a corporate computer, start with a neutral name (`-Name` / `--name`, DES11).
- **The clock grows with each new IP.** Each name `<hostname>@<IP>` that a machine used keeps its entry in the clock and in the PosIDs (DES4.5), so one machine used on two networks shows as two authors. It does not affect convergence; for a demo it does not matter.
- **On Nerves, a new IP needs a restart.** The node name is fixed when the firmware starts the node (DES15). If the Pi gets another IP, it is restarted: the history file does not depend on the IP (REQ13), and the clock grows with the new name (above).
- **On Nerves, burning the SD card again deletes `/data`.** A firmware update over the network keeps `/data`; burning the card again clears it, which is the same as deleting the history of that node (below).
- **On Nerves, a crash loop at boot reboots the Pi.** If `crdt_fw` is not running when the startup guard checks at boot, the guard reboots the Pi after 15 minutes (DES15). Without the loop, a stopped `crdt_fw` leaves the Pi on, as with systemd (DES13).
- **On Nerves, the notices are not seen over SSH.** The replica's notices go to the Pi's console (HDMI screen); an SSH session shows only what its commands print (`Crdt.status()`, `Crdt.history()`, `Crdt.debug()`, DES9).
- **A combining accent inserted alone takes its own position.** It joins the previous character into one grapheme (for example `"e"` and then `"́"` look like `"é"`), but it still takes its own position: indices count stored positions, not graphemes of the visible text. It does not happen when typing normally, because the keyboard produces precomposed characters such as `"é"`.
- **Deleting the history of a single node.** If `data/<node>.jsonl` of a single node is deleted (for example, because it was damaged, DES4.5), the node starts with its clock at 0 and the others resend everything to it. If someone edits on that node before it catches up, its new operations repeat sequence numbers, the others drop them as duplicates and the texts diverge. Rule: do not edit on that node until its text is the same as the others'.
- **Repeated notices on reconnection.** With each `:nodeup` and each `hello`, every node resends its whole history by broadcast (REQ15, DES4.4), and each repeated copy prints "duplicate dropped" (and an operation that is already waiting prints "waiting" again). With 3 nodes and 200 characters (MAN8), one reconnection can print hundreds of lines. It is not an error.

---

## 15. Raspberry Pi with Nerves

*Covers: REQ21, CON1, CON3, REQ13, REQ14.*

A Raspberry Pi 4 can run the node with Nerves firmware instead of Raspberry Pi OS: firmware written to the SD card, with no shell and no start script. `lib/` does not change. (ASG for the Raspberry Pi, OUR for Nerves.)

- **Target and versions.** `MIX_TARGET=rpi4`, with the official system `nerves_system_rpi4` 2.2 (Erlang/OTP 29.1.2). The computer that builds the firmware has the same Erlang/OTP and an Elixir that supports it (1.20, `-otp-29`). `lib/` keeps CON1: it still compiles with Elixir 1.18.3 and OTP 27 on Raspberry Pi OS. (OUR.)
- **Project.** `firmware/` is a separate Mix project next to `lib/` (a "poncho" project) that depends on `{:crdt, path: "..", runtime: false}` and on Nerves. Only `firmware/` has external dependencies (CON1). (OUR.)
- **Release.** In the release of `firmware/`, `applications: [crdt: :load, crdt_fw: :temporary]`. `:crdt` is only loaded (`:load`): its modules are there but `Crdt.Application` does not run, because on Nerves the node has no name when the applications start (DES6). The firmware application `crdt_fw` is `:temporary`: if it stops, the virtual machine stays alive and the Pi does not reboot, as with systemd (DES13). Exception: the startup guard of `nerves_runtime` (`startup_guard_enabled: true`), which validates a new firmware once every application has started (for example after `mix upload`), reboots the Pi after 15 minutes if `crdt_fw` is not running when it checks at boot, for example because it stopped in a crash loop. Mix refuses a release where an app started as `:temporary` depends on an app in `:load`, so `runtime: false` keeps `:crdt` out of the applications of `crdt_fw`; the release still includes it because it is listed. (OUR.)
- **`vm.args.eex`** is the one of the Nerves template, with no distribution lines: the name, the cookie and the ports are given at run time (below). (OUR.)
- **Processes.** `CrdtFw.Application` starts the supervisor `CrdtFw.Supervisor` (`one_for_one`) with one child, `CrdtFw`, a GenServer. `CrdtFw` starts its own supervisor, registered as `CrdtFw.NodeSupervisor` (`one_for_one`, with `Supervisor.start_link/2`, so it is linked to `CrdtFw`), for `Crdt.Replica` and `Crdt.Discovery`. (OUR.)
- **Start order of `CrdtFw`.** `init/1` only returns `{:ok, state, {:continue, :start}}`; the steps run after it, in `handle_continue/2`, so `CrdtFw.Supervisor` is not blocked while `CrdtFw` waits for the network. In order (OUR):
  1. Waits for an IPv4 on `wlan0`: it reads it from `vintage_net` and subscribes to its changes (`VintageNet.subscribe/1`) until there is one. Meanwhile it prints `waiting for an IPv4 on wlan0`, so the HDMI screen shows why the node has not started.
  2. Fixes the distribution ports: `Application.put_env(:kernel, :inet_dist_listen_min, 4218)` and `:inet_dist_listen_max` to `4228`, the range of DES6. They must be set before `Node.start/1`: OTP reads them when it opens the listen socket.
  3. Starts `epmd`: `System.cmd("epmd", ["-daemon"])`. Nerves does not start it.
  4. `Node.start(:"<hostname>@<IPv4>")`, with long names. The hostname is the Nerves default, `nerves-XXXX` (from `:inet.gethostname/0`), made safe as in DES6.
  5. `Node.set_cookie(:cpd2026)`, the cookie of DES6.
  6. `File.mkdir_p("/data/crdt")`: the root file system is read-only; `/data` is writable and survives firmware updates.
  7. If `CrdtFw.NodeSupervisor` or `Crdt.Replica` is still registered (an old one that is still stopping after a restart, below), it monitors them (`Process.monitor/1`) and waits for their `:DOWN` messages, at most 10 seconds for each one; if one does not arrive, step 7 fails like any other step (`:timeout`), and the HDMI console says so. Then it starts `CrdtFw.NodeSupervisor` with `Crdt.Replica` (`data_dir: "/data/crdt"` and `nodes:` the list of the configuration) and then `Crdt.Discovery`, with their default names (DES8). The history file is `/data/crdt/nerves-XXXX.jsonl` (DES4.5). The wait means there are never two replicas writing the same file.
  - It prints `node: <name> (interface: wlan0)`, as the start scripts do (DES11).
  - If a step fails, it prints which step and why, does not start the replica and stays waiting, without crashing, so it does not loop; the virtual machine stays alive (general rule of DES6). A `Crdt.Replica` that returns `:ignore` (DES6) does not stop `CrdtFw.NodeSupervisor`.
  - Later changes of the IP are ignored: a new IP needs a restart of the Pi (DES14, REQ13).
- **Restarts.** `CrdtFw.NodeSupervisor` restarts `Crdt.Replica` or `Crdt.Discovery` when one of them crashes. If it gives up (more than 3 restarts in 5 seconds, the default; for example the disk keeps failing, DES4.5), it stops, and `CrdtFw` stops with it, because they are linked. `CrdtFw.Supervisor` then starts a new `CrdtFw`, which runs the steps again (OUR):
  - Steps 2 to 5 are skipped if the node is already alive (`Node.alive?()`): the name, the ports and the cookie stay the same.
  - Step 6 does nothing if the folder exists.
  - Step 7 starts a new `CrdtFw.NodeSupervisor`. The old one stops with the old `CrdtFw`, but closing `Crdt.Replica` takes time, and the new `CrdtFw` can reach step 7 before. That is why step 7 waits for the `:DOWN` of the old `CrdtFw.NodeSupervisor` and `Crdt.Replica` if they are still registered.
  - If `CrdtFw.Supervisor` also gives up, the application `crdt_fw` stops; it is `:temporary`, so the virtual machine stays alive and the Pi does not reboot (DES13). Exception: at boot, before the startup guard has checked, it reboots the Pi after 15 minutes ("Release", above).
- **Why this structure (CON5).** Each process does one thing: `CrdtFw` waits and starts the node, and `CrdtFw.NodeSupervisor` restarts the replica and discovery. No process adds children to the supervisor it belongs to; a restarted `CrdtFw` only waits for the old processes to end, and never adds children to a supervisor that already has them. (OUR.)
- **Discovery and table.** Discovery is always on: the firmware has no `DISCOVERY` variable. The node table is the list `:nodes` of `config :crdt_fw` in `firmware/config/target.exs`, empty by default; `NODES_FILE` is not used. (OUR.)
- **Wi-Fi.** `firmware/config/target.exs` configures `wlan0` with a list of `vintage_net_wifi` networks. Each SSID and password is read from an environment variable when the firmware is built, never written in Git: `CRDT_HOTSPOT_SSID` and `CRDT_HOTSPOT_PSK` (the phone hotspot, higher priority), and optionally `CRDT_LAB_SSID` and `CRDT_LAB_PSK` (the lab network). Without the hotspot variables the build stops with a message. The ready image (below) is built with the test hotspot, whose SSID and password are published in `deploy/README-nerves.md` (CON7). (OUR.)
- **Ready image.** The author's image, for a team that does not build its own. It is in no repository: it holds the hotspot password and the author's SSH key. It is shared through a Google Drive link with restricted access, asked for through GitHub (an issue or the author's profile). `deploy/README-nerves.md` gives the date it was built from the code of the repository, says that `lib/` and `firmware/` have not changed since, and gives its SHA-256, with the commands to check it on macOS, Linux and Windows; every build changes the hash. Its SSH accepts only the author's key. (OUR.)
- **Another Wi-Fi network at run time.** From the IEx console of the Pi (the HDMI screen with a USB keyboard, or SSH), `VintageNetWiFi.quick_configure("<SSID>", "<password>")` connects to another network, and `vintage_net` keeps the configuration across restarts (`persist` is `true` by default). That is how the Pi works outside the hotspot and the lab. That call may replace the networks of the build instead of adding one; `VintageNet.reset_to_defaults("wlan0")` goes back to them. (OUR.)
- **SSH.** `nerves_ssh` with the public keys of the user and the partner, read when the firmware is built from the file named by `CRDT_SSH_KEYS`, outside Git, one key per line. Without `CRDT_SSH_KEYS`, or if its file cannot be read, the build stops with a message, as without the hotspot variables. The IEx console of the Pi: `ssh nerves-XXXX.local` (never `nerves.local`, shared by every Nerves device). (OUR.)
- **Console.** The replica's notices go to the Pi's console, the HDMI screen; DES9 does not change. Over SSH, `Crdt.status()`, `Crdt.history()` and `Crdt.debug()` print in the session, because they print in the calling process (DES9). (OUR.)
- **Firmware updates.** `mix upload nerves-XXXX.local` installs a new firmware over the network and keeps `/data`. Burning the SD card again clears `/data` (DES14). (OUR.)
- **Assumptions**, not verified without the hardware; MAN14 checks them, and MAN15 the USB keyboard and `quick_configure/2`:
  - UDP multicast (DES6.1) works on `wlan0` with Nerves.
  - The replica's notices appear on the HDMI console and not in the SSH session.
  - `$HOME` (`/root`) is writable, so `Node.start/1` can create the cookie file before `Node.set_cookie/1` replaces the cookie.
  - The address list of `vintage_net` for `wlan0` gives the IPv4 as a tuple.
  - A USB keyboard works on the HDMI console, and `VintageNetWiFi.quick_configure/2` replaces the networks of the build (or adds one).
  - A computer whose Erlang/OTP patch version differs from 29.1.2 builds the firmware with no problem.

---

## 16. Open questions

None.
