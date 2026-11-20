# Requirements

This document says **what** the system must do. The **how** is in `DESIGN.md`.

Each requirement has an identifier (REQ1, REQ2…), its origin and a verifiable acceptance criterion. Automated tests carry the tag of the requirement they test (for example, `@tag :req7`), so they can be run per requirement with `mix test --only req7`. The manual tests (MAN1, MAN2…) are at the end.

Origin:
- **ASG** (assignment): the project assignment of the course (course material, not included). It asks for a collaborative editor with a CRDT, no central server, the whole document on each node and every message broadcast to the connected nodes.
- **PAP** (paper): the Treedoc paper, DOI [10.1109/ICDCS.2009.20](https://doi.org/10.1109/ICDCS.2009.20).
- **CLS** (class): the course slides on causality and operation-based CRDTs (course material, not included). They contribute causal delivery with vector clocks (apply, wait or drop) and reliable delivery by forwarding.
- **OUR** (ours): our own decision.

## Codes

All codes have three letters, abbreviations in English.

| Code | What it is | Where it lives |
|---|---|---|
| REQ1, REQ2… | Requirement | This file, "Functional requirements" |
| CON1, CON2… | Constraint | This file, "Constraints" |
| MAN1, MAN2… | Manual test | This file, "Manual tests" |
| ASG, PAP, CLS, OUR | Origin: assignment, paper, class, ours | This file, "Origin", and `DESIGN.md` DES2 |
| PAP3.1 | Section 3.1 of the Treedoc paper | The paper, DOI 10.1109/ICDCS.2009.20 |
| DES4.2 | Section 4.2 of `DESIGN.md` | `DESIGN.md` |
| `@tag :req7` | Test tag of requirement REQ7; `mix test --only req7` | `test/` |
| `@tag :distributed` | Tag of the tests with real nodes (`:peer`); excluded by default, `mix test --include distributed` | `test/crdt_distributed_test.exs` |

---

## Functional requirements

| ID | Requirement | Origin | Acceptance criterion | Verified with |
|---|---|---|---|---|
| REQ1 | The system must work with no node in a special role: all run the same program and any of them can edit. | ASG | With three nodes, any one of them is halted and the other two keep editing and replicating between them. | MAN4 |
| REQ2 | Each node must keep the whole document. | ASG | `Crdt.text()` returns the whole document on any node, without asking the others. | Treedoc tests, MAN1 |
| REQ3 | When the user inserts or deletes a character at a valid position, the node must apply the change at once in its copy, at the given position. | ASG | After `insert(i, c)`, the character `c` is at position `i`. After `delete(i)`, the character that was at `i` is gone. | Treedoc tests, MAN3 |
| REQ4 | If the position of an edit is not valid, the node must refuse it without changing the document or the vector clock. | OUR | `insert` or `delete` with an index out of range, or `delete(i, count)` with more characters than there are, returns `{:error, :invalid_index}`, and the text and the clock stay the same. | Treedoc and replica tests |
| REQ5 | When a node applies a local edit, it must send it to every connected node. | ASG | What is typed on one node appears on the other connected nodes. | MAN1 |
| REQ6 | When a node receives an edit from another node, it must apply it in its copy. | ASG | Same as REQ5, seen from the receiving node. | MAN1, MAN3 |
| REQ7 | When all nodes have applied the same operations, they must show the same text, whatever the order in which the operations arrived. | ASG, PAP | In simulations with random arrival orders, all replicas end with the same text. | Convergence tests, MAN2, MAN8 |
| REQ8 | If several nodes insert at the same place at the same time, all characters must be kept, in the same order on every node. | PAP | In the scenario of figures 3 and 4 of the paper, the result is "abcWXYdef" on every replica. | Scenario test, MAN2 |
| REQ9 | A node must not apply an operation before the operations it depends on. If it arrives earlier, it must wait for them. | CLS | A message that arrives before its dependency waits and is applied right after it. | Causal delivery tests |
| REQ10 | If a node receives an operation it already applied, it must drop it. | CLS | A duplicate message, received directly or from the buffer, does not change the state. | Causal delivery tests |
| REQ11 | If an operation reached some node that is still connected, it must end up reaching every connected node, even if its origin is gone. | CLS | In a simulation where the origin sends only to one node and disappears, the operation reaches all the others. | Forwarding test, MAN4 |
| REQ12 | When a node connects or reconnects, it must receive every operation it is missing, even if the connection happens while it is still starting up. | OUR | A node that was off while others were writing ends with the same text as the others, whatever the moment of its start-up at which it connected. | Replica test, distributed tests, MAN4 |
| REQ13 | If a node restarts, it must recover its document and its clock from disk, even if the others are off, and it must not repeat operation identifiers. | OUR | After a restart with the other nodes off, the text is the same. The new operations are not dropped as duplicates on the other nodes. | History loading test, MAN5 |
| REQ14 | Each node must connect by itself to the nodes of a configurable list and keep retrying while they are not available. If the list file does not exist or cannot be read, the replica does not start, the console says what to fix, and the virtual machine and IEx stay alive. | ASG (discovery, explicit connection), OUR (list in a file, retry, unreadable file) | When the nodes are started in any order, they all end up connected with no intervention. With `NODES_FILE` pointing to a file that does not exist, `Crdt.Replica.start_link/1` returns `:ignore` and the console names the file. | Configuration test, replica test, distributed tests, MAN4 |
| REQ15 | All communication between nodes must be sent to every connected node of the list. | ASG | Edits, forwards and histories are sent to every connected node of the list, never to just one. | Distributed tests, code review, MAN1 |
| REQ16 | Local edits and remote messages that arrive at the same time must not corrupt the node's state. | ASG | Two nodes inserting in a loop at the same time end with the same text, with no errors. | Distributed test, design review, MAN8 |
| REQ17 | While the node runs, the user must be able to see the text, the node table, the nodes of the table that are connected, the clock, the buffer, the history and each character with its identifier. The console must report when an operation is applied, waits or is dropped, and when a node connects or disconnects. | OUR | `Crdt.status()`, `Crdt.history()` and `Crdt.debug()` show that information, and the notices appear in the console. | Replica tests, MAN7 |
| REQ18 | The history on disk must be readable with a text editor: one operation per line. | OUR | Each line of the file is a readable JSON object, and the round-trip conversion loses no information. | Format tests, MAN7 |
| REQ19 | A history line is complete if it ends in `"\n"` and is valid JSON. If the last line is not complete, the node must report it, remove it from the file and go on starting. If an earlier line is damaged, the replica must not start and must explain what to do, but the virtual machine and IEx must stay alive; meanwhile, the `Crdt` functions return `{:error, :no_replica}`. | OUR | A history whose last line is cut in half loads all the others; then a new operation is written and the history loads again with no errors. With a damaged line in the middle, `Crdt.Replica.start_link/1` returns `:ignore` and the console says which file to delete. | History loading tests |
| REQ20 | Inserting or deleting several characters at once must behave as a single local edit: the inserted text stays together even if remote edits arrive at the same time. | OUR | `Crdt.insert(i, "mundo")` leaves "mundo" together on every node, also during MAN2. | Replica test, MAN2 |

---

## Constraints

| ID | Constraint | Origin |
|---|---|---|
| CON1 | The code must compile and run with Elixir 1.18.3 and Erlang/OTP 27, the versions of Raspberry Pi OS (Debian trixie), even if it is developed with newer versions. Nothing from Elixir 1.19 or later or from OTP 28 or later is used. No external dependencies. | OUR |
| CON2 | All nodes are written in Elixir and communicate with Erlang distribution. | OUR |
| CON3 | It must run on Windows and on macOS (several nodes on one computer) and on Raspberry Pi OS. | ASG (Raspberry Pi), OUR (Windows, macOS) |
| CON4 | The CRDT is Treedoc, operation-based, with a granularity of one character. | ASG (a CRDT), OUR (Treedoc, operation-based; one-character granularity, allowed by PAP2) |
| CON5 | The code must be simple and understandable by students. | OUR |
| CON6 | The interface is functions in IEx. | OUR |

---

## Out of scope

- *Flatten* and garbage collection of tombstones.
- Tree balancing (PAP4.1).
- A graphical interface or a full-screen editor.
- Dynamic discovery of nodes that are not in the list.
- Security beyond the Erlang cookie.
- Editing together with another team's implementation, in Elixir or in another language (level C of `INTEGRATION.md`); levels A (connect) and B (receive and send our operations, also from Erlang) are documented in `INTEGRATION.md`.
- Several documents, undo and redo.

---

## Manual tests

The exact commands are in `README.md` and, case by case, in `MANUAL-TESTS.md`. Locally three nodes are used: `crdt1`, `crdt2` and `crdt3`.

| ID | Test | Requirements |
|---|---|---|
| MAN1 | Write on one node and check with `Crdt.text()` that the text appears the same on the other two. | REQ2, REQ5, REQ6, REQ15 |
| MAN2 | Write at the same time on two nodes, at the same place and at different places. The three end with the same text, no character is lost and each inserted word stays together. | REQ7, REQ8, REQ20 |
| MAN3 | Delete on one node and check that the delete appears on the others. | REQ3, REQ6 |
| MAN4 | Halt a node with `System.halt()` and keep writing on the others. Then start it again: it connects by itself and catches up. | REQ1, REQ11, REQ12, REQ14 |
| MAN5 | Halt the three nodes. Start only one: it recovers its text. Write on it right away. Start the others: they receive those operations and none is dropped as a duplicate. | REQ13 |
| MAN6 | Repeat MAN1 to MAN5 between two Raspberry Pis. MAN2 with two nodes. MAN4: halt one Pi, write on the other, start it again and see that it catches up. Optional: a third node, a computer on the same network with `crdt@IP` in a temporary table (as in `NETWORK.md`). REQ1 does not change: it is tested locally with three nodes (MAN4). Raspberry Pi guide not included yet. | CON3 |
| MAN7 | Check `Crdt.status()`, `Crdt.history()`, `Crdt.debug()`, the console notices and the `data/*.jsonl` file. | REQ17, REQ18 |
| MAN8 | On two nodes at the same time, run `for _ <- 1..100, do: Crdt.insert(0, "a")`. At the end, the text grew by 200 characters on each node, the three texts are equal and there were no errors. | REQ7, REQ16 |
