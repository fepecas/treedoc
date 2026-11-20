# Manual tests

A step-by-step guide to try the collaborative editor by hand on one
computer, with three terminals (one per node) and a fourth one for file
checks. No previous knowledge of the system is needed.

Every terminal command comes in two versions, one under the other:
"PowerShell (Windows)" and "macOS / Linux". Use the one of your
system. The IEx commands (`Crdt.insert(...)`, `System.halt()` and so
on) appear once: they are the same on every system. Both versions of a
check print the same; on macOS, `wc` puts spaces before the number.

Every "Expected" block was copied from a real run of this guide, in
order, starting from an empty `data` folder. Your numbers match if you
follow the cases in the same order without extra edits.

## Short path

[Before you start](#before-you-start), then Case 1 to
Case 13 in order, and [Case 22](#case-22-clean-up) to clean up. They
cover MAN1 to MAN5, MAN7 and MAN8. With two or more computers, add the
[network case](#network-case-edit-while-disconnected). Cases 14 to 21
are edge cases (damaged files, bad configuration, concurrent deletes);
skipping them changes no number of the cases you run.

## Glossary

The words used in this guide and in the other documents:

- **CRDT, operation-based**: a replicated data type. Each node sends its
  edits as operations; replicas that apply the same operations show the
  same text, whatever the order they arrive in. This one is Treedoc.
- **Causal delivery**: a node applies an op only after the ops it
  depends on; one that arrives earlier waits in a buffer.
- **Node**: one running copy of the editor (`crdt1`, `crdt2`, `crdt3`).
  Each node keeps the whole document.
- **Op**: one change to one character, an insert (`ins`) or a delete
  (`del`). `op 3 from crdt1` is the third op typed on crdt1.
- **History file**: `data\<name>.jsonl` (the node name before `@`), one
  op per line, in JSON. A node reloads it when it restarts.
- **Discovery**: each node announces its name on the local network every
  2 seconds; the nodes that hear it connect to it. No node table is
  needed.
- **PosID**: the position identifier of a character, a path in a binary
  tree; the text is the characters in tree order. You see it in
  `Crdt.debug()`.
- **Tombstone**: a deleted character that is kept, hidden, with its
  position, so notices, the history and `Crdt.debug()` can show it.
- **Vector clock**: for each node, how many of its ops this node has
  applied, for example `%{"crdt1@127.0.0.1": 4}`. You see it in
  `Crdt.status()`.

## Index

| Case | What it checks |
|---|---|
| [Short path](#short-path) | Cases 1 to 13 and the network case |
| [Before you start](#before-you-start) | Start from scratch, compile, open the terminals (Windows, macOS or Linux), start the three nodes |
| [Case 1](#case-1-the-three-nodes-connect) | The three nodes connect by themselves |
| [Case 2](#case-2-one-node-writes-the-others-see-it) | One node writes, the others see it (MAN1) |
| [Case 3](#case-3-several-characters-in-one-call) | Several characters in one call stay together |
| [Case 4](#case-4-delete) | Delete one and several characters (MAN3) |
| [Case 5](#case-5-two-nodes-write-at-the-same-place-at-the-same-time) | Two nodes write at the same place at the same time (MAN2) |
| [Case 6](#case-6-two-nodes-write-at-different-places-at-the-same-time) | Two nodes write at different places at the same time (MAN2) |
| [Case 7](#case-7-ñ-accents-and-emoji) | ñ, accents and emoji |
| [Case 8](#case-8-invalid-input-changes-nothing) | Invalid input changes nothing |
| [Case 9](#case-9-look-inside-status-history-and-debug) | Look inside: status, history and debug (MAN7) |
| [Case 10](#case-10-two-nodes-insert-100-characters-each-at-once) | Two nodes insert 100 characters each at once (MAN8) |
| [Case 11](#case-11-a-node-goes-down-and-catches-up) | A node goes down and catches up (MAN4) |
| [Case 12](#case-12-start-order-the-last-node-starts-first) | Start order: one node alone, then the others (MAN4) |
| [Case 13](#case-13-restart-with-the-others-off) | Restart with the others off (MAN5) |
| [Case 14](#case-14-the-history-of-one-node-is-deleted) | The history of one node is deleted |
| [Case 15](#case-15-the-last-line-of-a-history-is-incomplete) | The last line of a history is incomplete |
| [Case 16](#case-16-a-line-in-the-middle-of-a-history-is-damaged) | A line in the middle of a history is damaged |
| [Case 17](#case-17-nodes_file-names-a-file-that-does-not-exist) | `NODES_FILE` names a file that does not exist |
| [Case 18](#case-18-a-node-without---name) | A node without `--name` |
| [Case 19](#case-19-the-data-folder-is-missing) | The `data` folder is missing |
| [Case 20](#case-20-two-nodes-delete-the-same-character-at-once) | Two nodes delete the same character at once |
| [Case 21](#case-21-one-node-deletes-a-character-while-another-inserts-after-it) | One node deletes a character while another inserts after it |
| [Case 22](#case-22-clean-up) | Clean up |
| [Not by hand: "waiting"](#not-by-hand-an-op-that-waits) | Why "waiting" does not show up here |
| [With network (two or three computers)](#with-network-two-or-three-computers) | One node per computer: the start script, the clocks, which cases apply |
| [Network case](#network-case-edit-while-disconnected) | Edit while disconnected, then converge (no clock needed) |

## Before you start

**Goal:** an empty start, three nodes running, and a fourth terminal
for checks.

**Steps**

1. Open the project folder in VS Code (or in File Explorer, or in
   Finder on macOS).
2. Open four terminals in the project folder. In VS Code: menu
   Terminal > New Terminal, four times. On Windows, the "+" menu of the
   terminal panel must say "PowerShell"; without VS Code, open four
   "Windows PowerShell" windows and `cd` to the project folder in each.
   On macOS or Linux, any terminal (zsh or bash) works: open four and
   `cd` to the project folder in each.
   This guide calls them **crdt1**, **crdt2**, **crdt3** and **ps** (the
   fourth one, for the file checks, also on macOS and Linux).
3. Windows only: in each terminal, check that it is PowerShell:

   ```powershell
   $PSVersionTable.PSVersion
   ```

   It prints a version table (for example `5.1`). If it prints an error,
   that terminal is not PowerShell: close it and open a PowerShell one.
4. In **ps**, if nodes ran before, make sure they are all closed, then
   delete the old histories (it prints nothing, also when there are
   none):

   PowerShell (Windows):

   ```powershell
   Remove-Item data\*.jsonl
   ```

   macOS / Linux:

   ```sh
   rm -f data/*.jsonl
   ```

5. In **ps**, compile once, so the three nodes do not compile at the
   same time (the same command on every system):

   ```
   mix compile
   ```

6. In **crdt1**:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt1 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt1 --ip 127.0.0.1
   ```

7. In **crdt2**:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt2 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt2 --ip 127.0.0.1
   ```

8. In **crdt3**:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt3 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt3 --ip 127.0.0.1
   ```

**Expected:** each terminal shows the node name the script chose, the
Erlang and IEx banner, then its first notice and the IEx input line,
such as `iex(crdt1@127.0.0.1)1>`:

```
node: crdt1@127.0.0.1 (interface: given)
...
[crdt1@127.0.0.1] history loaded: 0 ops
```

- Windows: if PowerShell refuses to run the script ("running scripts
  is disabled on this system"), run once
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` and try again.
  If the firewall asks about `erl.exe` or `epmd.exe`, allow it.
- macOS and Linux: on macOS, if the firewall asks whether `beam.smp`
  may accept incoming connections, allow it.
- The script gives each node the name and IP of the command
  (`crdt1@127.0.0.1`); there is no node table: the nodes find each
  other by discovery.
- To leave a node at any time: `System.halt()`.

From here on, "In **crdt2**: `Crdt.text()`" means: type `Crdt.text()`
in the IEx of crdt2 and press Enter.

## Case 1: the three nodes connect

**Goal:** the three nodes find each other with no central server and
no node table (REQ1, REQ14).

**Steps**

1. Wait about 5 seconds after starting the third node.
2. In **crdt1**:

   ```elixir
   Crdt.status()
   ```

3. Repeat step 2 in **crdt2** and in **crdt3**.

**Expected:** right after starting, each console shows `connected`
notices. Which ones depends on the order and speed of the start. In
the real run:

```
crdt1:
[crdt1@127.0.0.1] history loaded: 0 ops
[crdt1@127.0.0.1] connected crdt2@127.0.0.1: resending history (0 ops)
[crdt1@127.0.0.1] connected crdt3@127.0.0.1: resending history (0 ops)

crdt2:
[crdt2@127.0.0.1] history loaded: 0 ops
[crdt2@127.0.0.1] connected crdt1@127.0.0.1: resending history (0 ops)
[crdt2@127.0.0.1] connected crdt3@127.0.0.1: resending history (0 ops)

crdt3:
[crdt3@127.0.0.1] history loaded: 0 ops
[crdt3@127.0.0.1] connected crdt1@127.0.0.1: resending history (0 ops)
[crdt3@127.0.0.1] connected crdt2@127.0.0.1: resending history (0 ops)
```

`Crdt.status()` in crdt1:

```
node: crdt1@127.0.0.1
nodes file: none
history file: data/crdt1.jsonl
table: []
discovery: listening on 45892
connected: crdt2@127.0.0.1 (announced), crdt3@127.0.0.1 (announced)
clock: %{}
history: 0 ops
buffer: 0 ops
:ok
```

In crdt2 and crdt3 the same form, with their own name and:

```
discovery: announce only
connected: crdt1@127.0.0.1 (other), crdt3@127.0.0.1 (other)
```

**Pass if:** on each node, `connected:` lists the other two nodes.

**Why:** only one node per computer can listen for announcements, the
first one started (`listening on 45892`); the others only announce
(`announce only`). crdt1 hears them and connects to both, and Erlang
connects crdt2 and crdt3 to each other. `(announced)`: this node heard
its announcement; `(other)`: another node made the connection.

## Case 2: one node writes, the others see it

**Goal:** an edit on one node reaches the others, and copies are dropped (REQ2, REQ5, REQ6, REQ10,
REQ15; MAN1).

**Steps**

1. In **crdt1**:

   ```elixir
   Crdt.insert(0, "hola")
   ```

2. In **crdt2**:

   ```elixir
   Crdt.text()
   ```

3. In **crdt3**:

   ```elixir
   Crdt.text()
   ```

4. In **ps**, look at the first line of crdt2's history:

   PowerShell (Windows):

   ```powershell
   Get-Content data\crdt2.jsonl -TotalCount 1
   ```

   macOS / Linux:

   ```sh
   head -n 1 data/crdt2.jsonl
   ```

**Expected**

- crdt1 returns `:ok` and prints 8 lines, two per op, such as
  `[crdt1@127.0.0.1] duplicate dropped: op 1 from crdt1@127.0.0.1`.
- crdt2 (and crdt3, with its own name):

  ```
  [crdt2@127.0.0.1] applied op 1 from crdt1@127.0.0.1: ins "h"
  [crdt2@127.0.0.1] applied op 2 from crdt1@127.0.0.1: ins "o"
  [crdt2@127.0.0.1] applied op 3 from crdt1@127.0.0.1: ins "l"
  [crdt2@127.0.0.1] applied op 4 from crdt1@127.0.0.1: ins "a"
  [crdt2@127.0.0.1] duplicate dropped: op 1 from crdt1@127.0.0.1
  [crdt2@127.0.0.1] duplicate dropped: op 2 from crdt1@127.0.0.1
  [crdt2@127.0.0.1] duplicate dropped: op 3 from crdt1@127.0.0.1
  [crdt2@127.0.0.1] duplicate dropped: op 4 from crdt1@127.0.0.1
  ```

- `Crdt.text()` returns `"hola"` on crdt2 and on crdt3.
- **ps**:

  ```
  {"op":"ins","from":"crdt1@127.0.0.1","vc":{"crdt1@127.0.0.1":1},"pos":[[1,1,"crdt1@127.0.0.1"]],"ch":"h"}
  ```

**Pass if:** `Crdt.text()` is `"hola"` on crdt2 and crdt3.

**Why:** every node forwards each op it receives once, in case the
sender went down; the extra copies arrive later and are dropped. That is
what `duplicate dropped` means: not an error.

## Case 3: several characters in one call

**Goal:** a word typed in one call stays together (REQ3, REQ20).

**Steps**

1. In **crdt2**:

   ```elixir
   Crdt.insert(4, " mundo")
   ```

2. In **crdt1**:

   ```elixir
   Crdt.text()
   ```

3. In **ps**, count the lines of crdt3's history:

   PowerShell (Windows):

   ```powershell
   (Get-Content data\crdt3.jsonl | Measure-Object -Line).Lines
   ```

   macOS / Linux:

   ```sh
   wc -l < data/crdt3.jsonl
   ```

**Expected**

- crdt2 returns `:ok` and prints 12 `duplicate dropped` lines for its
  own ops 1 to 6.
- crdt1 (and crdt3):

  ```
  [crdt1@127.0.0.1] applied op 1 from crdt2@127.0.0.1: ins " "
  [crdt1@127.0.0.1] applied op 2 from crdt2@127.0.0.1: ins "m"
  [crdt1@127.0.0.1] applied op 3 from crdt2@127.0.0.1: ins "u"
  [crdt1@127.0.0.1] applied op 4 from crdt2@127.0.0.1: ins "n"
  [crdt1@127.0.0.1] applied op 5 from crdt2@127.0.0.1: ins "d"
  [crdt1@127.0.0.1] applied op 6 from crdt2@127.0.0.1: ins "o"
  ```

  followed by 6 `duplicate dropped` lines.
- `Crdt.text()` returns `"hola mundo"`.
- **ps** prints `10` (4 ops of case 2 + 6).

**Pass if:** the three nodes show `"hola mundo"` and the file has 10
lines.

**Why:** one call creates one op per character, all in a row, and the
node handles one request at a time, so no edit from another node can
land in the middle of the word.

## Case 4: delete

**Goal:** a delete on one node reaches the others (REQ3, REQ6; MAN3).

**Steps**

1. In **crdt3**, delete the first character:

   ```elixir
   Crdt.delete(0)
   ```

2. In **crdt3**, delete 6 characters from index 3:

   ```elixir
   Crdt.delete(3, 6)
   ```

3. In **crdt1**, **crdt2** and **crdt3**:

   ```elixir
   Crdt.text()
   ```

4. In **ps**, count the deletes in crdt1's history:

   PowerShell (Windows):

   ```powershell
   (Select-String -Path data\crdt1.jsonl -Pattern '"op":"del"' | Measure-Object).Count
   ```

   macOS / Linux:

   ```sh
   grep -c '"op":"del"' data/crdt1.jsonl
   ```

**Expected**

- Both calls return `:ok`. crdt3 prints 14 `duplicate dropped` lines.
- crdt1 (and crdt2), between `duplicate dropped` lines:

  ```
  [crdt1@127.0.0.1] applied op 1 from crdt3@127.0.0.1: del "h"
  [crdt1@127.0.0.1] applied op 2 from crdt3@127.0.0.1: del " "
  [crdt1@127.0.0.1] applied op 3 from crdt3@127.0.0.1: del "m"
  [crdt1@127.0.0.1] applied op 4 from crdt3@127.0.0.1: del "u"
  [crdt1@127.0.0.1] applied op 5 from crdt3@127.0.0.1: del "n"
  [crdt1@127.0.0.1] applied op 6 from crdt3@127.0.0.1: del "d"
  [crdt1@127.0.0.1] applied op 7 from crdt3@127.0.0.1: del "o"
  ```

- `Crdt.text()` returns `"ola"` on the three nodes.
- **ps** prints `7`.

**Pass if:** the three nodes show `"ola"`.

**Why:** a deleted character becomes a tombstone: it is kept, hidden,
with its position, so the notice can name it (`del "h"`).

## Case 5: two nodes write at the same place at the same time

**Goal:** concurrent inserts at the same place keep every character, in
the same order on every node (REQ7, REQ8; MAN2).

A person cannot press Enter in two terminals within the same
millisecond, and the nodes exchange an edit in about a millisecond. So
both commands below first wait until the clock reaches the next multiple
of 10 seconds, and then run together. Paste the first one, then the
second one, within a few seconds.

**Steps**

1. In **crdt1**:

   ```elixir
   Process.sleep(10_000 - rem(System.os_time(:millisecond), 10_000)); Crdt.insert(3, " A")
   ```

2. In **crdt2**, right after:

   ```elixir
   Process.sleep(10_000 - rem(System.os_time(:millisecond), 10_000)); Crdt.insert(3, " B")
   ```

3. When both have returned, in **crdt1**, **crdt2** and **crdt3**:

   ```elixir
   Crdt.text()
   ```

**Expected**

- Both return `:ok` at the same moment (up to 10 seconds after you
  paste them).
- Besides `duplicate dropped` lines:

  ```
  crdt1:
  [crdt1@127.0.0.1] applied op 7 from crdt2@127.0.0.1: ins " "
  [crdt1@127.0.0.1] applied op 8 from crdt2@127.0.0.1: ins "B"

  crdt2:
  [crdt2@127.0.0.1] applied op 5 from crdt1@127.0.0.1: ins " "
  [crdt2@127.0.0.1] applied op 6 from crdt1@127.0.0.1: ins "A"

  crdt3:
  [crdt3@127.0.0.1] applied op 7 from crdt2@127.0.0.1: ins " "
  [crdt3@127.0.0.1] applied op 8 from crdt2@127.0.0.1: ins "B"
  [crdt3@127.0.0.1] applied op 5 from crdt1@127.0.0.1: ins " "
  [crdt3@127.0.0.1] applied op 6 from crdt1@127.0.0.1: ins "A"
  ```

- The order of the applied lines may differ; the final text may not.
- `Crdt.text()` returns `"ola A B"` on the three nodes.

**Pass if:** the three texts are equal and contain both `" A"` and
`" B"`. If the two calls returned at different moments, they did not run
together: the text is then `"ola B A"`, which is also correct, but the
case tested two edits one after the other. The 10-second command is
reliable only on one computer; between computers, see [The clocks and the 10-second command](#the-clocks-and-the-10-second-command).

**Why:** both new characters land in the same spot of the tree; every
node breaks the tie the same way, by op number and node name, so all
end with the same order.

## Case 6: two nodes write at different places at the same time

**Goal:** concurrent inserts at different places (MAN2).

**Steps**

1. In **crdt2**:

   ```elixir
   Process.sleep(10_000 - rem(System.os_time(:millisecond), 10_000)); Crdt.insert(0, "<")
   ```

2. In **crdt3**, right after:

   ```elixir
   Process.sleep(10_000 - rem(System.os_time(:millisecond), 10_000)); Crdt.insert(7, ">")
   ```

3. When both have returned, in **crdt1**, **crdt2** and **crdt3**:

   ```elixir
   Crdt.text()
   ```

**Expected**

- Both return `:ok`. Besides `duplicate dropped` lines:

  ```
  crdt1:
  [crdt1@127.0.0.1] applied op 8 from crdt3@127.0.0.1: ins ">"
  [crdt1@127.0.0.1] applied op 9 from crdt2@127.0.0.1: ins "<"

  crdt2:
  [crdt2@127.0.0.1] applied op 8 from crdt3@127.0.0.1: ins ">"

  crdt3:
  [crdt3@127.0.0.1] applied op 9 from crdt2@127.0.0.1: ins "<"
  ```

- The order of the applied lines may differ; the final text may not.
- `Crdt.text()` returns `"<ola A B>"` on the three nodes.

**Pass if:** the three texts are equal, start with `<` and end with `>`.

## Case 7: ñ, accents and emoji

**Goal:** characters outside plain English work and count as one
position each (REQ3, REQ18).

**Steps**

1. In **crdt1**:

   ```elixir
   Crdt.insert(0, "ñandú 🙂 ")
   ```

   If your terminal cannot type or show `ñ`, `ú` or `🙂`, use this line
   instead; it inserts exactly the same text:

   ```elixir
   Crdt.insert(0, "\u00F1and\u00FA \u{1F642} ")
   ```

2. In **crdt2**:

   ```elixir
   Crdt.text()
   ```

3. In **crdt3**:

   ```elixir
   String.length(Crdt.text())
   ```

4. In **ps**, find the line of `ñ` in crdt3's history:

   PowerShell (Windows):

   ```powershell
   Select-String -Path data\crdt3.jsonl -Pattern '"ch":"ñ"' -Encoding UTF8 | Select-Object -ExpandProperty LineNumber
   ```

   macOS / Linux:

   ```sh
   grep -n '"ch":"ñ"' data/crdt3.jsonl | cut -d: -f1
   ```

**Expected**

- crdt2 (and crdt3):

  ```
  [crdt2@127.0.0.1] applied op 7 from crdt1@127.0.0.1: ins "ñ"
  [crdt2@127.0.0.1] applied op 8 from crdt1@127.0.0.1: ins "a"
  [crdt2@127.0.0.1] applied op 9 from crdt1@127.0.0.1: ins "n"
  [crdt2@127.0.0.1] applied op 10 from crdt1@127.0.0.1: ins "d"
  [crdt2@127.0.0.1] applied op 11 from crdt1@127.0.0.1: ins "ú"
  [crdt2@127.0.0.1] applied op 12 from crdt1@127.0.0.1: ins " "
  [crdt2@127.0.0.1] applied op 13 from crdt1@127.0.0.1: ins "🙂"
  [crdt2@127.0.0.1] applied op 14 from crdt1@127.0.0.1: ins " "
  ```

- `Crdt.text()` returns `"ñandú 🙂 <ola A B>"`.
- `String.length(Crdt.text())` returns `17`.
- **ps** prints `24`.

**Pass if:** the text is the same on the three nodes and its length is
17.

**Why:** a "character" is what you see as one letter, even if it takes
several bytes; `🙂` is one position. To read the history file with
`Get-Content` in Windows PowerShell, add `-Encoding UTF8`; without it
`ñ` shows as `Ã±` (the file is fine). On macOS and Linux,
`cat data/crdt3.jsonl` shows it right.

## Case 8: invalid input changes nothing

**Goal:** a bad index, a bad count or a bad text is refused and nothing
changes (REQ4).

**Steps**

1. In **crdt1**, note the `clock` and `history` lines:

   ```elixir
   Crdt.status()
   ```

2. In **crdt1**, one by one:

   ```elixir
   Crdt.insert(99, "x")
   ```

   ```elixir
   Crdt.insert(-1, "x")
   ```

   ```elixir
   Crdt.delete(99)
   ```

   ```elixir
   Crdt.delete(0, 99)
   ```

   ```elixir
   Crdt.insert(0, "")
   ```

   ```elixir
   Crdt.delete(0, 0)
   ```

   ```elixir
   Crdt.delete(0, -1)
   ```

   ```elixir
   Crdt.insert(0, 42)
   ```

3. In **crdt1**, again:

   ```elixir
   Crdt.status()
   ```

4. In **ps**:

   PowerShell (Windows):

   ```powershell
   (Get-Content data\crdt1.jsonl | Measure-Object -Line).Lines
   ```

   macOS / Linux:

   ```sh
   wc -l < data/crdt1.jsonl
   ```

**Expected**

- Step 1 and step 3 print the same:

  ```
  node: crdt1@127.0.0.1
  nodes file: none
  history file: data/crdt1.jsonl
  table: []
  discovery: listening on 45892
  connected: crdt2@127.0.0.1 (announced), crdt3@127.0.0.1 (announced)
  clock: %{"crdt1@127.0.0.1": 14, "crdt2@127.0.0.1": 9, "crdt3@127.0.0.1": 8}
  history: 31 ops
  buffer: 0 ops
  :ok
  ```

  (the order of the nodes inside `clock` may differ).
- Step 2, in order:

  ```
  {:error, :invalid_index}      # insert at 99: the text has 17 characters
  {:error, :invalid_index}      # insert at -1
  {:error, :invalid_index}      # delete at 99
  {:error, :invalid_index}      # delete 99 characters: there are not enough
  :ok                           # empty text: nothing to insert
  :ok                           # count 0: nothing to delete
  {:error, :invalid_index}      # count -1
  ** (FunctionClauseError) no function clause matching in Crdt.insert/2
  ```

  The last one is followed by the arguments it got (`0` and `42`) and
  the clause it tried. The node keeps running.
- No console prints any notice.
- **ps** prints `31`.

**Pass if:** `clock` and `history` are the same before and after, and
the file still has 31 lines.

**Why:** the index and the count are checked before anything is created,
so a refused edit leaves no gap in the op numbers.

## Case 9: look inside: status, history and debug

**Goal:** see the node's state (REQ17; MAN7).

**Steps**

1. In **crdt2**:

   ```elixir
   Crdt.status()
   ```

2. In **crdt2**:

   ```elixir
   Crdt.history()
   ```

3. In **crdt2**:

   ```elixir
   Crdt.history(:all)
   ```

4. In **crdt2**:

   ```elixir
   Crdt.debug()
   ```

5. In **ps**, count all the lines, the inserts and the deletes of
   crdt2's history:

   PowerShell (Windows):

   ```powershell
   (Get-Content data\crdt2.jsonl | Measure-Object -Line).Lines
   ```

   macOS / Linux:

   ```sh
   wc -l < data/crdt2.jsonl
   ```

   PowerShell (Windows):

   ```powershell
   (Select-String -Path data\crdt2.jsonl -Pattern '"op":"ins"' | Measure-Object).Count
   ```

   macOS / Linux:

   ```sh
   grep -c '"op":"ins"' data/crdt2.jsonl
   ```

   PowerShell (Windows):

   ```powershell
   (Select-String -Path data\crdt2.jsonl -Pattern '"op":"del"' | Measure-Object).Count
   ```

   macOS / Linux:

   ```sh
   grep -c '"op":"del"' data/crdt2.jsonl
   ```

**Expected**

- `Crdt.status()`:

  ```
  node: crdt2@127.0.0.1
  nodes file: none
  history file: data/crdt2.jsonl
  table: []
  discovery: announce only
  connected: crdt1@127.0.0.1 (other), crdt3@127.0.0.1 (other)
  clock: %{"crdt2@127.0.0.1": 9, "crdt1@127.0.0.1": 14, "crdt3@127.0.0.1": 8}
  history: 31 ops
  buffer: 0 ops
  :ok
  ```

  `table` is the optional node table (`NODES_FILE`, empty here);
  `discovery` says whether this node listens for announcements;
  `connected` shows every connected node and how it was found
  (Case 1); `clock` is the vector
  clock; `buffer` counts ops waiting for an earlier op (see
  [Not by hand](#not-by-hand-an-op-that-waits)).
- `Crdt.history()`, the last 10 ops in the order this node applied
  them:

  ```
  ... 21 earlier ops
  op 9 from crdt2@127.0.0.1: ins "<"
  op 8 from crdt3@127.0.0.1: ins ">"
  op 7 from crdt1@127.0.0.1: ins "ñ"
  op 8 from crdt1@127.0.0.1: ins "a"
  op 9 from crdt1@127.0.0.1: ins "n"
  op 10 from crdt1@127.0.0.1: ins "d"
  op 11 from crdt1@127.0.0.1: ins "ú"
  op 12 from crdt1@127.0.0.1: ins " "
  op 13 from crdt1@127.0.0.1: ins "🙂"
  op 14 from crdt1@127.0.0.1: ins " "
  :ok
  ```

- `Crdt.history(:all)`, 31 lines starting with:

  ```
  op 1 from crdt1@127.0.0.1: ins "h"
  op 2 from crdt1@127.0.0.1: ins "o"
  op 3 from crdt1@127.0.0.1: ins "l"
  op 4 from crdt1@127.0.0.1: ins "a"
  op 1 from crdt2@127.0.0.1: ins " "
  ```

- `Crdt.debug()`, 24 lines (one per inserted character, deleted ones
  included, 7 of them marked `deleted`), starting with:

  ```
  "h" [{1, 1, :"crdt1@127.0.0.1"}] deleted
  "ñ" [{1, 1, :"crdt1@127.0.0.1"}, {1, 2, :"crdt1@127.0.0.1"}, {0, 9, :"crdt2@127.0.0.1"}, {0, 7, :"crdt1@127.0.0.1"}]
  "a" [{1, 1, :"crdt1@127.0.0.1"}, {1, 2, :"crdt1@127.0.0.1"}, {0, 9, :"crdt2@127.0.0.1"}, {0, 7, :"crdt1@127.0.0.1"}, {1, 8, :"crdt1@127.0.0.1"}]
  ```

  Each step of a PosID is `{side, op number, node}`: side 0 is left,
  1 is right.
- **ps** prints `31`, `24` and `7`.

**Pass if:** `history: 31 ops` matches the 31 lines of the file, and the
24 inserts of the file match the 24 lines of `Crdt.debug()`.

## Case 10: two nodes insert 100 characters each at once

**Goal:** a node handles its own edits and the other node's edits at
the same time without errors, and all end equal (REQ7, REQ16; MAN8).

**Steps**

1. In **crdt3**:

   ```elixir
   String.length(Crdt.text())
   ```

2. In **crdt1**:

   ```elixir
   Process.sleep(10_000 - rem(System.os_time(:millisecond), 10_000)); for _ <- 1..100, do: Crdt.insert(0, "a")
   ```

3. In **crdt2**, right after:

   ```elixir
   Process.sleep(10_000 - rem(System.os_time(:millisecond), 10_000)); for _ <- 1..100, do: Crdt.insert(0, "a")
   ```

4. When both have returned, in **crdt1**, **crdt2** and **crdt3**:

   ```elixir
   String.length(Crdt.text())
   ```

5. In **ps**:

   PowerShell (Windows):

   ```powershell
   (Get-Content data\crdt3.jsonl | Measure-Object -Line).Lines
   ```

   macOS / Linux:

   ```sh
   wc -l < data/crdt3.jsonl
   ```

**Expected**

- Step 1 returns `17`.
- crdt1 and crdt2 each return a list of 100 `:ok` (IEx shows the first
  50):

  ```
  [:ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok,
   :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok,
   :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok,
   :ok, :ok, ...]
  ```

- The consoles scroll: crdt1 and crdt2 print 100 `applied` and 300
  `duplicate dropped` lines each; crdt3 prints 200 `applied` and 200
  `duplicate dropped`. For example, on crdt3:

  ```
  [crdt3@127.0.0.1] applied op 15 from crdt1@127.0.0.1: ins "a"
  [crdt3@127.0.0.1] applied op 10 from crdt2@127.0.0.1: ins "a"
  [crdt3@127.0.0.1] applied op 16 from crdt1@127.0.0.1: ins "a"
  ```

- The order of the applied lines may differ; the final text may not.
- Step 4 returns `217` on the three nodes (17 + 200).
- **ps** prints `231`.

**Pass if:** no error, and `217` on the three nodes.

## Case 11: a node goes down and catches up

**Goal:** the other nodes keep working without one node, and that node
catches up when it comes back (REQ1, REQ11, REQ12, REQ14; MAN4).

**Steps**

1. In **crdt3**:

   ```elixir
   System.halt()
   ```

2. In **crdt1**:

   ```elixir
   Crdt.insert(0, "[off]")
   ```

3. In **crdt2**:

   ```elixir
   Crdt.delete(0)
   ```

4. In **crdt1** and **crdt2**:

   ```elixir
   String.slice(Crdt.text(), 0, 10)
   ```

5. In **crdt3**, start the node again:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt3 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt3 --ip 127.0.0.1
   ```

6. Wait about 5 seconds. Do not edit on crdt3 yet. In **crdt3**:

   ```elixir
   String.slice(Crdt.text(), 0, 10)
   ```

**Expected**

- After step 1, crdt1 and crdt2 print
  `disconnected crdt3@127.0.0.1`.
- After step 2, crdt2 prints `applied op 115` to `op 119 from
  crdt1@127.0.0.1` (`ins "["`, `"o"`, `"f"`, `"f"`, `"]"`). After step 3,
  crdt1 prints `applied op 110 from crdt2@127.0.0.1: del "["`.
- Step 4 returns `"off]aaaaaa"` on both.
- After step 5, crdt3 prints:

  ```
  [crdt3@127.0.0.1] history loaded: 231 ops
  [crdt3@127.0.0.1] applied op 115 from crdt1@127.0.0.1: ins "["
  [crdt3@127.0.0.1] applied op 116 from crdt1@127.0.0.1: ins "o"
  [crdt3@127.0.0.1] applied op 117 from crdt1@127.0.0.1: ins "f"
  [crdt3@127.0.0.1] applied op 118 from crdt1@127.0.0.1: ins "f"
  [crdt3@127.0.0.1] applied op 119 from crdt1@127.0.0.1: ins "]"
  [crdt3@127.0.0.1] applied op 110 from crdt2@127.0.0.1: del "["
  ```

  mixed with several hundred `duplicate dropped` lines and with
  `connected crdt1@127.0.0.1: resending history (231 ops)` and
  `connected crdt2@127.0.0.1: resending history (237 ops)` (the count
  grows while the missing ops arrive). crdt1 and crdt2 print
  `connected crdt3@127.0.0.1: resending history (237 ops)`.
- Step 6 returns `"off]aaaaaa"`.

**Pass if:** crdt3's text is again equal to the others.

**Why:** each node keeps every op it applied and sends the whole list
when a node connects; the newcomer applies what it misses and drops the
rest.

## Case 12: start order: the last node starts first

**Goal:** the nodes can start in any order and still end equal (REQ12,
REQ14; MAN4).

**Steps**

1. In **crdt1**, then **crdt2**, then **crdt3**:

   ```elixir
   System.halt()
   ```

2. In **crdt3**, start only this node:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt3 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt3 --ip 127.0.0.1
   ```

3. In **crdt3**:

   ```elixir
   Crdt.insert(0, "first ")
   ```

4. In **crdt1**:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt1 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt1 --ip 127.0.0.1
   ```

5. In **crdt2**:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt2 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt2 --ip 127.0.0.1
   ```

6. Wait about 5 seconds. In **crdt1**, **crdt2** and **crdt3**:

   ```elixir
   String.slice(Crdt.text(), 0, 10)
   ```

**Expected**

- Step 1: crdt2 prints `disconnected crdt1@127.0.0.1`; crdt3 prints
  `disconnected crdt1@127.0.0.1` and `disconnected crdt2@127.0.0.1`.
- Step 2: crdt3 prints `history loaded: 237 ops` and nothing else (no
  other node is running). Step 3 returns `:ok`.
- crdt1, besides `duplicate dropped` lines (the `connected` lines may
  come in another order, between the `applied` ones):

  ```
  [crdt1@127.0.0.1] history loaded: 237 ops
  [crdt1@127.0.0.1] applied op 9 from crdt3@127.0.0.1: ins "f"
  [crdt1@127.0.0.1] applied op 10 from crdt3@127.0.0.1: ins "i"
  [crdt1@127.0.0.1] applied op 11 from crdt3@127.0.0.1: ins "r"
  [crdt1@127.0.0.1] applied op 12 from crdt3@127.0.0.1: ins "s"
  [crdt1@127.0.0.1] applied op 13 from crdt3@127.0.0.1: ins "t"
  [crdt1@127.0.0.1] applied op 14 from crdt3@127.0.0.1: ins " "
  [crdt1@127.0.0.1] connected crdt3@127.0.0.1: resending history (237 ops)
  [crdt1@127.0.0.1] connected crdt2@127.0.0.1: resending history (243 ops)
  ```

- crdt2 prints the same `history loaded` and `applied` lines, and
  `connected` lines for crdt3 and crdt1.
- crdt3:

  ```
  [crdt3@127.0.0.1] connected crdt1@127.0.0.1: resending history (243 ops)
  [crdt3@127.0.0.1] connected crdt2@127.0.0.1: resending history (243 ops)
  ```

- Step 6 returns `"first off]"` on the three nodes.

**Pass if:** the three nodes return `"first off]"`.

## Case 13: restart with the others off

**Goal:** a node restarted alone gets its text back from its file, and
its new ops are accepted by the others (REQ13; MAN5).

**Steps**

1. In **crdt2**, note the `clock` value of `crdt2@127.0.0.1`:

   ```elixir
   Crdt.status()
   ```

2. In **crdt2**:

   ```elixir
   String.length(Crdt.text())
   ```

3. In **crdt1**, then **crdt2**, then **crdt3**:

   ```elixir
   System.halt()
   ```

4. In **crdt2**, start only this node:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt2 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt2 --ip 127.0.0.1
   ```

5. In **crdt2**:

   ```elixir
   String.length(Crdt.text())
   ```

6. In **crdt2**, right away:

   ```elixir
   Crdt.insert(0, "new ")
   ```

7. In **crdt1**:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt1 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt1 --ip 127.0.0.1
   ```

8. In **crdt3**:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt3 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt3 --ip 127.0.0.1
   ```

9. Wait about 5 seconds. In **crdt1**, **crdt2** and **crdt3**:

   ```elixir
   String.slice(Crdt.text(), 0, 10)
   ```

10. In **ps**:

    PowerShell (Windows):

    ```powershell
    (Get-Content data\crdt1.jsonl | Measure-Object -Line).Lines
    ```

    macOS / Linux:

    ```sh
    wc -l < data/crdt1.jsonl
    ```

**Expected**

- Step 1: `clock: %{"crdt2@127.0.0.1": 110, "crdt3@127.0.0.1": 14,
  "crdt1@127.0.0.1": 119}` and `history: 243 ops`.
- Steps 2 and 5 both return `227`. Step 4 prints
  `[crdt2@127.0.0.1] history loaded: 243 ops`. Step 6 returns `:ok`.
- crdt1 (and crdt3, with its name):

  ```
  [crdt1@127.0.0.1] history loaded: 243 ops
  [crdt1@127.0.0.1] applied op 111 from crdt2@127.0.0.1: ins "n"
  [crdt1@127.0.0.1] applied op 112 from crdt2@127.0.0.1: ins "e"
  [crdt1@127.0.0.1] applied op 113 from crdt2@127.0.0.1: ins "w"
  [crdt1@127.0.0.1] applied op 114 from crdt2@127.0.0.1: ins " "
  ```

  crdt1 also prints `connected crdt2@127.0.0.1: resending history
  (243 ops)` and `connected crdt3@127.0.0.1: resending history
  (247 ops)`; crdt3 prints `connected` lines for crdt2 and crdt1. Both
  print many `duplicate dropped`.
- Step 9 returns `"new first "` on the three nodes. **ps** prints `247`.

**Pass if:** crdt2's new ops are numbered 111 to 114 (110 + 1 onwards),
and the first line about `op 111 from crdt2@127.0.0.1` on crdt1 and
crdt3 is `applied`, not `duplicate dropped`.

**Why:** the file brings back the clock, so crdt2 goes on from 111. If
it started again at 1, the others would drop its new ops as old ones.

## Case 14: the history of one node is deleted

**Goal:** a node that lost its file catches up from the others, as long
as nobody edits on it before (usage rule of the README).

**Steps**

1. In **crdt3**, note the `clock` and `history` lines:

   ```elixir
   Crdt.status()
   ```

2. In **crdt3**:

   ```elixir
   System.halt()
   ```

3. In **ps**:

   PowerShell (Windows):

   ```powershell
   Remove-Item data\crdt3.jsonl
   ```

   macOS / Linux:

   ```sh
   rm data/crdt3.jsonl
   ```

4. In **crdt3**, start the node again. Do not edit on it in this case:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt3 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt3 --ip 127.0.0.1
   ```

5. Wait about 5 seconds. In **crdt3**:

   ```elixir
   Crdt.status()
   ```

6. In **ps**:

   PowerShell (Windows):

   ```powershell
   (Get-Content data\crdt3.jsonl | Measure-Object -Line).Lines
   ```

   macOS / Linux:

   ```sh
   wc -l < data/crdt3.jsonl
   ```

**Expected**

- Step 1: `clock: %{"crdt3@127.0.0.1": 14, "crdt2@127.0.0.1": 114,
  "crdt1@127.0.0.1": 119}` and `history: 247 ops`.
- Step 4, crdt3:

  ```
  [crdt3@127.0.0.1] history loaded: 0 ops
  [crdt3@127.0.0.1] applied op 1 from crdt1@127.0.0.1: ins "h"
  [crdt3@127.0.0.1] applied op 2 from crdt1@127.0.0.1: ins "o"
  [crdt3@127.0.0.1] applied op 3 from crdt1@127.0.0.1: ins "l"
  [crdt3@127.0.0.1] applied op 4 from crdt1@127.0.0.1: ins "a"
  ```

  and so on: 247 `applied` lines in all, mixed with `duplicate dropped`.
- Step 5: the same `clock` values as step 1 (`crdt3@127.0.0.1: 14`) and
  `history: 247 ops`. **ps** prints `247`.

**Pass if:** step 5 shows the clock of step 1.

**Why:** the others send back everything, including crdt3's own 14 ops.
Editing on crdt3 before that would reuse op numbers 1 to 14, and the
others would drop those edits as duplicates.

## Case 15: the last line of a history is incomplete

**Goal:** a line cut in half at the end (for example by a power cut) is
removed and the node starts (REQ19).

**Steps**

1. In **crdt1**:

   ```elixir
   System.halt()
   ```

2. In **ps**, note the size of the file in bytes:

   PowerShell (Windows):

   ```powershell
   (Get-Item data\crdt1.jsonl).Length
   ```

   macOS / Linux:

   ```sh
   wc -c < data/crdt1.jsonl
   ```

3. In **ps**, add half a line at the end:

   PowerShell (Windows):

   ```powershell
   Add-Content -Path data\crdt1.jsonl -Value '{"op":"ins","from":"crdt1@127' -NoNewline
   ```

   macOS / Linux:

   ```sh
   printf '%s' '{"op":"ins","from":"crdt1@127' >> data/crdt1.jsonl
   ```

4. In **ps**, the size again:

   PowerShell (Windows):

   ```powershell
   (Get-Item data\crdt1.jsonl).Length
   ```

   macOS / Linux:

   ```sh
   wc -c < data/crdt1.jsonl
   ```

5. In **crdt1**, start the node again:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt1 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt1 --ip 127.0.0.1
   ```

6. In **ps**, the size once more:

   PowerShell (Windows):

   ```powershell
   (Get-Item data\crdt1.jsonl).Length
   ```

   macOS / Linux:

   ```sh
   wc -c < data/crdt1.jsonl
   ```

**Expected**

- Steps 2, 4 and 6 printed `345528`, `345557` (29 bytes more) and
  `345528` in the real run, and other numbers in other runs: the size
  depends on how the two loops of Case 10 interleaved, so your numbers
  may differ. Step 4 is always 29 bytes
  more than step 2, and step 6 equals step 2.
- Step 5, crdt1:

  ```
  [crdt1@127.0.0.1] history: last line was incomplete; removed from file
  [crdt1@127.0.0.1] history loaded: 247 ops
  ```

**Pass if:** the node starts, and step 6 prints the same number as
step 2.

**Why:** that op was never sent (nothing leaves a node before it is
safely on disk), so dropping it loses nothing.

## Case 16: a line in the middle of a history is damaged

**Goal:** a damaged history stops the node's editor with a clear
message; IEx stays usable (REQ19).

**Steps**

1. In **crdt2**:

   ```elixir
   System.halt()
   ```

2. In **ps**, damage line 5 of crdt2's history.

   PowerShell (Windows), these four commands:

   ```powershell
   $f = (Resolve-Path data\crdt2.jsonl).Path
   ```

   ```powershell
   $lines = [IO.File]::ReadAllLines($f)
   ```

   ```powershell
   $lines[4] = '{"op":"ins", DAMAGED'
   ```

   ```powershell
   [IO.File]::WriteAllText($f, ($lines -join "`n") + "`n")
   ```

   macOS / Linux, these two commands (the first one also leaves a
   `.bak` copy, which the second one deletes):

   ```sh
   sed -i.bak '5s/.*/{"op":"ins", DAMAGED/' data/crdt2.jsonl
   ```

   ```sh
   rm data/crdt2.jsonl.bak
   ```

3. In **ps**, look at line 5:

   PowerShell (Windows):

   ```powershell
   Get-Content data\crdt2.jsonl -TotalCount 5 | Select-Object -Last 1
   ```

   macOS / Linux:

   ```sh
   sed -n 5p data/crdt2.jsonl
   ```

4. In **crdt2**, start the node:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt2 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt2 --ip 127.0.0.1
   ```

5. In **crdt2**:

   ```elixir
   Crdt.text()
   ```

6. Fix it as the message says. In **crdt2**:

   ```elixir
   System.halt()
   ```

7. In **ps**:

   PowerShell (Windows):

   ```powershell
   Remove-Item data\crdt2.jsonl
   ```

   macOS / Linux:

   ```sh
   rm data/crdt2.jsonl
   ```

8. In **crdt2**, start the node again and do not edit on it in this
   case:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt2 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt2 --ip 127.0.0.1
   ```

9. Wait about 5 seconds. In **crdt2**:

   ```elixir
   String.slice(Crdt.text(), 0, 10)
   ```

**Expected**

- Step 3 prints `{"op":"ins", DAMAGED`.
- Step 4, crdt2:

  ```
  [crdt2@127.0.0.1] history corrupted at line 5 of data/crdt2.jsonl: replica not started. Delete that file and restart the node to catch up with the others. Do not edit on this node until its text matches the others.
  ```

- Step 5 returns `{:error, :no_replica}` (so does every `Crdt`
  function). crdt1 and crdt3 print
  `connected crdt2@127.0.0.1: resending history (247 ops)`: they reach
  crdt2's IEx, but no editor is there to receive it. That is harmless.
- Step 8: `history loaded: 0 ops`, then 247 `applied` lines.
- Step 9 returns `"new first "`.

**Pass if:** step 5 returns `{:error, :no_replica}`, IEx still
accepts commands, and step 9 returns `"new first "`.

**Why:** skipping a damaged line in the middle would leave a hole in the
op numbers that could never be filled, so the node refuses to start
instead.

## Case 17: NODES_FILE names a file that does not exist

**Goal:** a wrong node list stops the editor with a clear message
(REQ14).

**Steps**

1. In **crdt3**:

   ```elixir
   System.halt()
   ```

2. In **crdt3**, start with a wrong file name:

   PowerShell (Windows):

   ```powershell
   $env:NODES_FILE="nodes.missing.txt"; .\scripts\start.ps1 -Name crdt3 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   NODES_FILE=nodes.missing.txt ./scripts/start.sh --name crdt3 --ip 127.0.0.1
   ```

3. In **crdt3**:

   ```elixir
   Crdt.text()
   ```

4. In **crdt3**:

   ```elixir
   System.halt()
   ```

5. In **crdt3**, start without `NODES_FILE` (on Windows, the first
   command removes it from this terminal):

   PowerShell (Windows):

   ```powershell
   Remove-Item Env:NODES_FILE; .\scripts\start.ps1 -Name crdt3 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt3 --ip 127.0.0.1
   ```

**Expected**

- Step 2, crdt3:

  ```
  [crdt3@127.0.0.1] cannot read nodes file nodes.missing.txt (no such file or directory): replica not started. Fix NODES_FILE and restart the node.
  ```

- Step 3 returns `{:error, :no_replica}`. crdt1 and crdt2 print
  `connected crdt3@127.0.0.1: resending history (247 ops)`, harmless as
  in case 16: discovery still runs on crdt3, only its editor is off.
- Step 5, crdt3: `history loaded: 247 ops`.

**Pass if:** step 2 shows the message with the file name, and after
step 5 crdt3 works again.

## Case 18: a node without --name

**Goal:** without a node name the editor does not start, and the
console shows the right command (CON2).

**Steps**

1. In **crdt3**:

   ```elixir
   System.halt()
   ```

2. In **crdt3**, start without `--name`:

   PowerShell (Windows):

   ```powershell
   iex.bat -S mix
   ```

   macOS / Linux:

   ```sh
   iex -S mix
   ```

3. In **crdt3**:

   ```elixir
   Crdt.text()
   ```

4. In **crdt3**:

   ```elixir
   System.halt()
   ```

5. In **crdt3**, start normally:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt3 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt3 --ip 127.0.0.1
   ```

**Expected**

- Step 2:

  ```
  Node has no name: Crdt.Replica not started. Start it with the start script (docs/DESIGN.md, section 11):
    PowerShell:   .\scripts\start.ps1
    macOS, Linux: ./scripts/start.sh
  ```

- Step 3 returns `{:error, :no_replica}`.
- Step 5: `history loaded: 247 ops`.

**Pass if:** step 2 shows both commands and step 3 returns
`{:error, :no_replica}`.

## Case 19: the data folder is missing

**Goal:** if the history folder is missing, the editor does not start
and does not create it (REQ19).

All nodes share the `data` folder on this computer, so all three are
halted first.

**Steps**

1. Wait about 5 seconds after case 18. In **crdt1**:

   ```elixir
   String.length(Crdt.text())
   ```

2. In **crdt1**, then **crdt2**, then **crdt3**:

   ```elixir
   System.halt()
   ```

3. In **ps**:

   PowerShell (Windows):

   ```powershell
   Rename-Item data data.off
   ```

   macOS / Linux:

   ```sh
   mv data data.off
   ```

4. In **crdt1**:

   PowerShell (Windows):

   ```powershell
   .\scripts\start.ps1 -Name crdt1 -Ip 127.0.0.1
   ```

   macOS / Linux:

   ```sh
   ./scripts/start.sh --name crdt1 --ip 127.0.0.1
   ```

5. In **crdt1**:

   ```elixir
   Crdt.text()
   ```

6. In **ps**, check that no folder was created:

   PowerShell (Windows):

   ```powershell
   Test-Path data
   ```

   macOS / Linux:

   ```sh
   test -e data && echo True || echo False
   ```

7. In **crdt1**:

   ```elixir
   System.halt()
   ```

8. In **ps**:

   PowerShell (Windows):

   ```powershell
   Rename-Item data.off data
   ```

   macOS / Linux:

   ```sh
   mv data.off data
   ```

9. Start **crdt1**, **crdt2** and **crdt3** with the commands of
   [Before you start](#before-you-start), steps 6 to 8.
10. Wait about 5 seconds. In **crdt1**, **crdt2** and **crdt3**:

    ```elixir
    String.length(Crdt.text())
    ```

**Expected**

- Step 1 returns `231`.
- Step 4, crdt1:

  ```
  [crdt1@127.0.0.1] cannot open history file data/crdt1.jsonl (no such file or directory): replica not started. Check that the folder exists and restart the node.
  ```

- Step 5 returns `{:error, :no_replica}`. Step 6 prints `False`.
- Step 10 returns `231` on the three nodes.

**Pass if:** step 4 shows the message, step 6 prints `False`, and step
10 returns `231` on the three nodes.

## Case 20: two nodes delete the same character at once

**Goal:** two nodes delete the same character at the same time; it is
gone once, and all end equal (REQ7).

The two commands use the 10-second command of
[Case 5](#case-5-two-nodes-write-at-the-same-place-at-the-same-time).

**Steps**

1. In **crdt1**, **crdt2** and **crdt3**:

   ```elixir
   String.slice(Crdt.text(), 0, 10)
   ```

2. In **crdt1**:

   ```elixir
   Process.sleep(10_000 - rem(System.os_time(:millisecond), 10_000)); Crdt.delete(0)
   ```

3. In **crdt2**, right after:

   ```elixir
   Process.sleep(10_000 - rem(System.os_time(:millisecond), 10_000)); Crdt.delete(0)
   ```

4. When both have returned, in **crdt1**, **crdt2** and **crdt3**:

   ```elixir
   String.slice(Crdt.text(), 0, 10)
   ```

   ```elixir
   String.length(Crdt.text())
   ```

5. In **ps**, count the deletes in crdt3's history:

   PowerShell (Windows):

   ```powershell
   (Select-String -Path data\crdt3.jsonl -Pattern '"op":"del"' | Measure-Object).Count
   ```

   macOS / Linux:

   ```sh
   grep -c '"op":"del"' data/crdt3.jsonl
   ```

**Expected**

- Step 1 returns `"new first "` on the three nodes.
- Both return `:ok` at the same moment. Besides `duplicate dropped`
  lines:

  ```
  crdt1:
  [crdt1@127.0.0.1] applied op 115 from crdt2@127.0.0.1: del "n"

  crdt2:
  [crdt2@127.0.0.1] applied op 120 from crdt1@127.0.0.1: del "n"

  crdt3:
  [crdt3@127.0.0.1] applied op 115 from crdt2@127.0.0.1: del "n"
  [crdt3@127.0.0.1] applied op 120 from crdt1@127.0.0.1: del "n"
  ```

- The order of the applied lines may differ; the final text may not.
- Step 4 returns `"ew first o"` and `230` on the three nodes (231 - 1).
- **ps** prints `10` (8 before, plus the two deletes).

**Pass if:** both return `:ok`, the three texts are equal, and the
character is gone once: the length went down by 1, not 2.

**Why:** both deletes name the same character (the same PosID), so
both mark the same tombstone; the second one changes nothing. There are
two ops in the history, but one character less in the text.

## Case 21: one node deletes a character while another inserts after it

**Goal:** a delete and an insert right after the deleted character, at
the same time: the deleted one is gone and the new one stays (REQ7,
REQ8).

**Steps**

1. In **crdt2**, delete the first character, `e`:

   ```elixir
   Process.sleep(10_000 - rem(System.os_time(:millisecond), 10_000)); Crdt.delete(0)
   ```

2. In **crdt3**, right after, insert `X` right after that `e`:

   ```elixir
   Process.sleep(10_000 - rem(System.os_time(:millisecond), 10_000)); Crdt.insert(1, "X")
   ```

3. When both have returned, in **crdt1**, **crdt2** and **crdt3**:

   ```elixir
   String.slice(Crdt.text(), 0, 10)
   ```

   ```elixir
   String.length(Crdt.text())
   ```

**Expected**

- Both return `:ok` at the same moment. Besides `duplicate dropped`
  lines:

  ```
  crdt1:
  [crdt1@127.0.0.1] applied op 116 from crdt2@127.0.0.1: del "e"
  [crdt1@127.0.0.1] applied op 15 from crdt3@127.0.0.1: ins "X"

  crdt2:
  [crdt2@127.0.0.1] applied op 15 from crdt3@127.0.0.1: ins "X"

  crdt3:
  [crdt3@127.0.0.1] applied op 116 from crdt2@127.0.0.1: del "e"
  ```

- The order of the applied lines may differ; the final text may not.
- Step 3 returns `"Xw first o"` and `230` on the three nodes (one
  character less, one more).

**Pass if:** the three texts are equal, the `e` is gone and the `X` is
there.

**Why:** crdt3 gave `X` a new PosID right after `e`. A PosID is ordered
by its path alone, so the deleted neighbour is not needed: whether the
delete or the insert arrives first, `X` lands in the same place on
every node.

## Case 22: clean up

**Goal:** leave everything as at the start.

**Steps**

1. In **crdt1**, **crdt2** and **crdt3**:

   ```elixir
   System.halt()
   ```

2. In **ps**:

   PowerShell (Windows):

   ```powershell
   Remove-Item data\*.jsonl
   ```

   macOS / Linux:

   ```sh
   rm -f data/*.jsonl
   ```

3. In **ps**:

   PowerShell (Windows):

   ```powershell
   Get-ChildItem -Force data | Select-Object -ExpandProperty Name
   ```

   macOS / Linux:

   ```sh
   ls -A data
   ```

**Expected:** step 3 prints only `.gitkeep`.

**Pass if:** only `.gitkeep` is left. To run the guide again, go back to
[Before you start](#before-you-start).

## Not by hand: an op that waits

A node keeps an op in its buffer (`waiting op ...`, and `buffer: 1 ops`
in `Crdt.status()`) when it arrives before an op it depends on (REQ9). On one
computer the messages between two nodes always arrive in order, so this
does not happen in the cases above. It is covered by automated tests
(the same command on every system):

```
mix test --only req9
```

for example "a remote op that arrives before its dependency waits, then
both apply in order" in `test/crdt_test.exs` and "(a) b2 waits, b1
arrives: both are forwarded to a connected node, with no table" in
`test/crdt_distributed_test.exs`.

## With network (two or three computers)

The same system runs with one node on each of two or three computers on
the same network, for example a Windows computer, a Mac and a Raspberry
Pi. [NETWORK.md](NETWORK.md) has the full steps for a Mac and a Windows
computer, with the Windows firewall (not yet validated on two
computers). This section says what changes in this guide.

### Start the nodes

The full steps, with the Windows firewall, are in
[NETWORK.md](NETWORK.md) (not yet validated between computers). In
short, once per computer: clone the repository, `mix compile`, and on
Windows the firewall rules and the execution policy of NETWORK.md,
section 2. Every computer needs its own hostname.

On each computer, in the project folder, after deleting old histories
(`Remove-Item data\*.jsonl` or `rm -f data/*.jsonl`):

PowerShell (Windows):

```powershell
.\scripts\start.ps1
```

macOS / Linux:

```sh
./scripts/start.sh
```

The script prints the node name it chose, `<hostname>@<IP>`, for
example `node: pi-pe@172.20.10.4 (interface: wlan0)`. If it cannot pick
the network adapter, it says so: give the IP with `-Ip <IP>`
(`--ip <IP>`). Each node prints `history loaded: 0 ops`. Within a few
seconds, `Node.list()` and `Crdt.status()` (`connected:`) list the
other nodes, with no node table.

In the cases, read that node name where the guide says
`crdt1@127.0.0.1`, and the history file is `data/<hostname>.jsonl`, for
example `data/pi-pe.jsonl`.

If the nodes do not find each other, [NETWORK.md](NETWORK.md), section
5: the firewall, `scripts/multicast_check.exs`, and a node table with
`NODES_FILE` as the way out.

### The clocks and the 10-second command

The 10-second command (Case 5, Case 6, Case 10, Case 20, Case 21) waits
for the clock of each computer. It is reliable only on one computer,
where all the nodes read the same clock. Between computers the clocks
would have to agree within a few milliseconds, the time an edit takes
to go from one computer to the other, and they usually do not: the
computer of the real run was 1.1 s off an internet clock. So between
computers, show concurrent edits with the next case, the edit while
disconnected, which does not depend on the clocks.

To see how far a computer's clock is:

PowerShell (Windows): the last number of each line is how far this
clock is from an internet clock, for example `+00.0123456s`:

```powershell
w32tm /stripchart /computer:time.windows.com /samples:3 /dataonly
```

macOS: the first number is the same offset, in seconds:

```sh
sntp time.apple.com
```

Linux, for example a Raspberry Pi: line `Offset:`:

```sh
timedatectl timesync-status
```

If you still try the 10-second command between computers, the case
passes, but the edits are most likely one after the other, not
concurrent.

### Network case: edit while disconnected

**Goal:** two computers edit the same place while they cannot see each
other, and they converge when they reconnect (REQ8, REQ12). It does
not depend on the clocks.

Do not do it on a computer you reach over SSH (for example a Raspberry
Pi without a keyboard): when its network goes off, the SSH session
drops. Disconnect a computer where you type directly.

**Steps**

1. On each computer:

   ```elixir
   Crdt.text()
   ```

2. On one computer, B, disconnect it from the network: turn off its
   Wi-Fi or unplug its cable.
3. Wait until A, the other computer, prints
   `disconnected <B's node name>`, and B prints `disconnected` for each
   other node. It may take about a minute.
4. On A:

   ```elixir
   Crdt.insert(0, "on ")
   ```

5. On B:

   ```elixir
   Crdt.insert(0, "off ")
   ```

6. Reconnect B to the network (Wi-Fi on, or plug the cable).
7. Wait about 10 seconds. On each computer:

   ```elixir
   Crdt.text()
   ```

**Expected**

- Steps 4 and 5 return `:ok` at once, also while disconnected.
- After step 6, B prints `connected <A's node name>: resending history
  (N ops)`, and each computer prints
  `applied op ...` for the other's word: `ins "o"`, `ins "n"`, `ins " "`
  or `ins "o"`, `ins "f"`, `ins "f"`, `ins " "`.
- Step 7 returns the same text on every computer, starting with
  `"on off "` or `"off on "`.

**Pass if:** the texts are equal and both words are whole.

**Why:** neither computer saw the other's word before writing its own,
so the two edits are surely concurrent; on reconnection each node
resends its whole history and the other applies what it misses.

### Which cases apply

With two nodes (one per computer):

- Case 1, Case 2, Case 3, Case 4, Case 7, Case 8 and Case 9: the same,
  with two nodes instead of three.
- Case 5, Case 6, Case 10, Case 20 and Case 21: not between computers;
  the 10-second command needs one clock (see above). The network case
  takes their place.
- Case 11 becomes: halt one node, write on the other, start it again
  and check that it catches up. [NETWORK.md](NETWORK.md) also checks
  that `Crdt.insert` answers at once while the other node is off.
- The network case above.

With three nodes (one per computer), besides the above:

- Case 11 as written: one node down, the other two keep working.
- Case 12 and Case 13: the start order and a restart with the others
  off, one node per computer.
- The network case above, with the third node on A's side.

Cases 14 to 19 are about the files and the start of one node: do them
on one computer, with the rest of this guide.
