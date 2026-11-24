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
| REQ12 | When a node connects or reconnects, it must receive every operation it is missing, even if the connection happens while it is still starting up. | OUR | A node that was off while others were writing ends with the same text as the others, whatever the moment of its start-up at which it connected, also with no node table. | Replica test, distributed tests, MAN4 |
| REQ13 | If a node restarts, it must recover its document and its clock from disk, even if the others are off, and it must not repeat operation identifiers. Its history file must not depend on the IP: a node restarted with a new IP (same machine name, new node name) finds the same file. | OUR | After a restart with the other nodes off, the text is the same. The new operations are not dropped as duplicates on the other nodes. After a restart with another IP in the node name, the text is the same and the new operations are numbered from 1 under the new name. | History loading test, MAN5 |
| REQ14 | Each node must find by itself our other nodes on its local network and connect to them (discovery), and also connect to the nodes of an optional list, retrying while they are not available. Only announcements of our nodes count. If discovery cannot work (blocked network, busy port, `DISCOVERY=off`), the node keeps running and the list still works. If the list file is given and does not exist or cannot be read, the replica does not start, the console says what to fix, and the virtual machine and IEx stay alive. | ASG (discovery, dynamic or explicit connection), OUR (multicast announcement, optional list in a file, retry, unreadable file) | When the nodes are started in any order with no list, they all end up connected with no intervention. A node with no list and no discovery joins when another node lists it. A packet without our tag is ignored. With `NODES_FILE` pointing to a file that does not exist, `Crdt.Replica.start_link/1` returns `:ignore` and the console names the file. | Configuration test, discovery tests, replica test, distributed tests, MAN4 |
| REQ15 | All communication between nodes must be sent to every connected node. | ASG | Edits, forwards and histories are sent to every connected node, also to nodes that are in no list, never to just one. | Distributed tests, code review, MAN1 |
| REQ16 | Local edits and remote messages that arrive at the same time must not corrupt the node's state. | ASG | Two nodes inserting in a loop at the same time end with the same text, with no errors. | Distributed test, design review, MAN8 |
| REQ17 | While the node runs, the user must be able to see the text, the node table, the state of discovery, the connected nodes and how each one was found, the clock, the buffer, the history and each character with its identifier. The console must report when an operation is applied, waits or is dropped, and when a node connects or disconnects. | OUR | `Crdt.status()`, `Crdt.history()` and `Crdt.debug()` show that information, and the notices appear in the console. | Replica tests, MAN7 |
| REQ18 | The history on disk must be readable with a text editor: one operation per line. | OUR | Each line of the file is a readable JSON object, and the round-trip conversion loses no information. | Format tests, MAN7 |
| REQ19 | A history line is complete if it ends in `"\n"` and is valid JSON. If the last line is not complete, the node must report it, remove it from the file and go on starting. If an earlier line is damaged, the replica must not start and must explain what to do, but the virtual machine and IEx must stay alive; meanwhile, the `Crdt` functions return `{:error, :no_replica}`. | OUR | A history whose last line is cut in half loads all the others; then a new operation is written and the history loads again with no errors. With a damaged line in the middle, `Crdt.Replica.start_link/1` returns `:ignore` and the console says which file to delete. | History loading tests |
| REQ20 | Inserting or deleting several characters at once must behave as a single local edit: the inserted text stays together even if remote edits arrive at the same time. | OUR | `Crdt.insert(i, "mundo")` leaves "mundo" together on every node, also during MAN2. | Replica test, MAN2 |
| REQ21 | The node must also run on a Raspberry Pi 4 with Nerves firmware, with no start script: when `wlan0` has an IPv4, it names itself `<hostname>@<IPv4>`, connects like any other node (discovery and the optional node list) and keeps its history on the writable partition. A change of IP is handled by restarting the Pi, as on the other platforms (REQ13). | ASG (Raspberry Pi), OUR (Nerves) | The Pi with Nerves and a computer started with its start script, with no node list, find each other and pass MAN1, MAN4 and MAN5 between them. Restarted on a new network, the Pi joins with its new name and the same text. | MAN14, MAN15 |
| REQ22 | Our node must edit one document together with another team's implementation that follows our operation protocol (`INTEGRATION.md`, L3), on the same local network, with no change on either side: with computers, with our Pi with Nerves, and Pi to Pi. Every node starts with `prevent_overlapping_partitions` off, so a dropped link does not cut the node's other links. | OUR (interoperation agreed with other teams of the course) | Our nodes and the other implementation find each other with no node list (or with `Node.connect/1` by hand on one computer), and after MAN1, MAN2, MAN3 and MAN4 between them every node shows the same text. On every one of our nodes, `:application.get_env(:kernel, :prevent_overlapping_partitions)` returns `{:ok, false}`. | MAN16, MAN17, MAN18 |
| REQ23 | A message that the replica receives from another node and that does not follow the format of `DESIGN.md` DES5.1, or that the replica does not know, must be dropped with a console notice and must change nothing: not the document, the clock, the buffer, the history nor the file. The replica never crashes because of a message. A discovery packet whose node name cannot be an atom is ignored, so it never stops discovery or the replica. | OUR | A replica that gets many malformed or unknown messages (casts, plain messages and calls; from the test process and from another node) keeps the same process, the same text, clock and history file, prints the notice, and still applies a valid operation that arrives after them. `Crdt.Discovery.parse/1` ignores a tagged name of 256 bytes or one that is not valid UTF-8. | Replica tests, discovery test, distributed test, MAN16 |

---

## Constraints

| ID | Constraint | Origin |
|---|---|---|
| CON1 | The code of `lib/` must compile and run with Elixir 1.18.3 and Erlang/OTP 27, the versions of Raspberry Pi OS (Debian trixie), even if it is developed with newer versions. Nothing from Elixir 1.19 or later or from OTP 28 or later is used in `lib/`. `lib/` and the root `mix.exs` have no external dependencies. Only the firmware project `firmware/` depends on Nerves; it is built with the Erlang/OTP of `nerves_system_rpi4` and an Elixir version that supports it. | OUR |
| CON2 | All nodes are written in Elixir and communicate with Erlang distribution. | OUR |
| CON3 | It must run on Windows and on macOS (several nodes on one computer), on Raspberry Pi OS and on a Raspberry Pi 4 with Nerves. On Windows, macOS and Raspberry Pi OS each starts a node with one start script that picks the Wi-Fi IPv4 by itself; on Nerves the firmware does the same when the Pi boots. | ASG (Raspberry Pi), OUR (Windows, macOS, start scripts, Nerves) |
| CON4 | The CRDT is Treedoc, operation-based, with a granularity of one character. | ASG (a CRDT), OUR (Treedoc, operation-based; one-character granularity, allowed by PAP2) |
| CON5 | The code must be simple and understandable by students. | OUR |
| CON6 | The interface is functions in IEx. | OUR |
| CON7 | No real SSID, Wi-Fi password or SSH key is written in the repository or its public copy. One exception: the SSID and password of the test hotspot are published in `deploy/README-nerves.md`, because the ready Nerves image only joins that network. | OUR |

---

## Out of scope

- *Flatten* and garbage collection of tombstones.
- Tree balancing (PAP4.1).
- A graphical interface or a full-screen editor.
- Discovery beyond the local network (multicast does not cross routers); a node on another network is added with the list.
- Security beyond the Erlang cookie.
- Editing together with an implementation that does not follow our operation protocol (another CRDT such as RGA or Logoot, another message format, another process name): it only reaches L1 and L2 of `INTEGRATION.md`. Implementations that follow it are in scope (REQ22); we test with the ones of the other teams that we can reach, and we do not change our protocol for them.
- Several documents, undo and redo.
- Nerves on other boards than the Raspberry Pi 4, and our own Nerves systems: the firmware uses the official `nerves_system_rpi4`.
- On Nerves, joining a new network without restarting: the node name is fixed at boot, and a new IP needs a restart, as on the other platforms (REQ13).
- On Nerves, the replica's notices in an SSH session: they appear on the Pi's console (HDMI screen); the queries (`Crdt.status()` and the others) do work over SSH.

---

## Manual tests

The exact commands are in `README.md` and, case by case, in `MANUAL-TESTS.md`. Locally three nodes are used, started with the start script: `crdt1`, `crdt2` and `crdt3`, with no node table.

| ID | Test | Requirements |
|---|---|---|
| MAN1 | Write on one node and check with `Crdt.text()` that the text appears the same on the other two. | REQ2, REQ5, REQ6, REQ15 |
| MAN2 | Write at the same time on two nodes, at the same place and at different places. The three end with the same text, no character is lost and each inserted word stays together. | REQ7, REQ8, REQ20 |
| MAN3 | Delete on one node and check that the delete appears on the others. | REQ3, REQ6 |
| MAN4 | Halt a node with `System.halt()` and keep writing on the others. Then start it again, with no node table: it connects by itself and catches up. | REQ1, REQ11, REQ12, REQ14 |
| MAN5 | Halt the three nodes. Start only one: it recovers its text. Write on it right away. Start the others: they receive those operations and none is dropped as a duplicate. | REQ13 |
| MAN6 | Repeat MAN1 to MAN5 between two Raspberry Pis, each started with `scripts/start.sh` and no node table. MAN2 with two nodes. MAN4: halt one Pi, write on the other, start it again and see that it catches up. Optional: a third node, a computer on the same network started with its start script (as in `NETWORK.md`). REQ1 does not change: it is tested locally with three nodes (MAN4). | CON3 |
| MAN7 | Check `Crdt.status()`, `Crdt.history()`, `Crdt.debug()`, the console notices and the `data/*.jsonl` file. | REQ17, REQ18 |
| MAN8 | On two nodes at the same time, run `for _ <- 1..100, do: Crdt.insert(0, "a")`. At the end, the text grew by 200 characters on each node, the three texts are equal and there were no errors. | REQ7, REQ16 |
| MAN9 | Two computers on the same Wi-Fi (for example Windows and macOS), each started with its start script and no node table, find each other by discovery; an edit on each appears on the other. | REQ5, REQ6, REQ14, CON3 |
| MAN10 | Between two computers: halt the node of one, edit on the other, start it again: it reconnects by itself, both resend their whole history, the copies are dropped and the texts are equal. | REQ10, REQ12 |
| MAN11 | A computer and a Raspberry Pi on a phone hotspot: the Pi edits alone, then the computer starts and catches up; a third computer joins later and gets everything. The same text on three machines and three operating systems. | REQ7, REQ12, CON3 |
| MAN12 | Between computers, two nodes insert a word at the same position at the same time: each word stays in one block and the order is the same on every node. | REQ8, REQ20 |
| MAN13 | Between computers, `Crdt.insert` with an index out of range returns `{:error, :invalid_index}` and changes nothing. | REQ4 |
| MAN14 | A Raspberry Pi 4 with Nerves and a Mac (started with `scripts/start.sh`), on the same network and with no node list, find each other. MAN1 between them. MAN4: power off the Pi, edit on the Mac, power the Pi on: it catches up. MAN5: halt both, start only the Pi: it recovers its text from `/data`; write N+1… on it at once, start the Mac: those new operations arrive on the Mac as "applied", not as "duplicate dropped" (as in Case 13 of `MANUAL-TESTS.md`); the duplicates of the resent history are normal. It also checks the assumptions of `DESIGN.md` DES15. | REQ21, REQ5, REQ6, REQ12, REQ13, REQ14, CON3 |
| MAN15 | Move the Pi with Nerves to a new network: from the HDMI console with a USB keyboard, `VintageNetWiFi.quick_configure/2` to another Wi-Fi (for example a home Wi-Fi), then restart the Pi (a new IP needs a restart, REQ13). It joins with its new name and its text is the same. Then `VintageNet.reset_to_defaults("wlan0")` and a restart go back to the networks of the build. | REQ21, REQ13 |
| MAN16 | Interoperation on one computer, or two if the other implementation does not build on one of them: our node (start script) and the node of another team's implementation, each named with the Wi-Fi IPv4 of its computer, with no node list. They find each other by discovery, or, if discovery does not link them (multicast blocked, or two discovery sockets on one machine, `DESIGN.md` DES6.1), with `Node.connect/1` by hand. MAN1, MAN2 (same place and different places, with a word of several characters on each side), MAN3 and MAN4 between them; accents and an emoji (as in Case 7 of `MANUAL-TESTS.md`); on our node, `:application.get_env(:kernel, :prevent_overlapping_partitions)`. Between two computers, MAN2 edits while one side is disconnected. From a third node on our node's computer, a few malformed casts to our `Crdt.Replica` (as in REQ23): our replica stays up and keeps its text. | REQ22, REQ23, REQ5, REQ6, REQ7, REQ8, REQ12, REQ14 |
| MAN17 | Interoperation with our Pi: the node of the other implementation on a computer, our Pi 4 with Nerves (the image built after REQ22 and REQ23) and our computer, on the same network, with no node list. Before it, once both Pis have the new image: stop every node and delete every node's history file at once, the other implementation's included (burning the card keeps the Pi's name and clears its history, `DESIGN.md` DES14; commands in `MANUAL-TESTS.md`); no card is burned again after that. MAN1 and MAN3 from each of the three; MAN4 powering the Pi off and on: it catches up from the other two. | REQ22, REQ21, REQ12 |
| MAN18 | Interoperation Pi to Pi: our Pi 4 with Nerves and the Pis of other teams, on the same network (a router or a phone hotspot; the lab router broadcasts the same network as the test hotspot, CON7, so our image joins it with no change), with no computer as a node (a computer may only open an SSH console). MAN1 and MAN3 from our Pi and from one Pi of another team; MAN4 powering our Pi off and on. Every Pi ends with the same text. | REQ22, REQ21, REQ12 |
