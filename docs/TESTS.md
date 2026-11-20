# Tests

87 automated tests. 81 run without network; 6 start real nodes on this
computer. Each test is tagged with the requirements it proves. The words
used here (op, PosID, tombstone, vector clock) are in the
[glossary](MANUAL-TESTS.md#glossary). Three more:

- `:peer`: the OTP module that starts another Erlang node on this
  computer, from a test.
- nodeup: the message `{:nodeup, node}` that a node receives when
  another node connects to it.
- hello: the message `{:hello, node}` that a replica sends when it
  starts, so the others send it their history again.

## What each file covers

| File | Covers | Main tags |
|---|---|---|
| `test/crdt/treedoc_test.exs` | `Crdt.Treedoc`: order of positions, insert and delete, the paper scenario, convergence in any order | req3, req7, req8 |
| `test/crdt/causal_test.exs` | `Crdt.Causal`: apply, wait or drop; duplicates; three simulated replicas, 100 seeds | req9, req10, req11 |
| `test/crdt/log_format_test.exs` | `Crdt.LogFormat`: the JSON line format and its round trip | req18 |
| `test/crdt/config_test.exs` | `Crdt.Config`: reading the node table, CRLF included | req14 |
| `test/crdt_test.exs` | `Crdt` and `Crdt.Replica` without network: edits, invalid input, remote operations, `status`, `history`, the node table | req3, req4, req17 |
| `test/crdt_history_test.exs` | The history file: reload, incomplete last line, damaged line, one sync per call | req13, req19, req20 |
| `test/crdt_distributed_test.exs` | Real nodes with `:peer`: forwarding, table filter, resending the history, an unreachable node | req12, req15, req16 |

## How to run them

```sh
mix test                          # the 81 tests without network
mix test --only req7              # only the tests of one requirement
mix test --include distributed    # all 87, with real nodes
```

- `--only reqN` also runs the distributed tests tagged `reqN`.
- The distributed tests need `epmd`, the Erlang port mapper. They start
  it themselves if it is not running.
- On Windows, the firewall may ask about `erl.exe` or `epmd.exe` the
  first time. Allow it.
- The tests write their history files in temporary folders, never in
  `data/`.

## How to read one test

Take the scenario of the paper, in `test/crdt/treedoc_test.exs`,
describe "scenario of paper figures 3 and 4 (DESIGN.md DES3.6)".

- The `@tag :req8` line above the test says which requirement it proves.
- The describe and test names say the expected behaviour, and cite the
  design section.
- The body types "abcdef", then builds two concurrent inserts, W and Y,
  with `prepare/3`. Two replicas apply them with `effect/2` in opposite
  orders; both read "abcWYdef". After X is inserted between them, both
  read "abcWXYdef" (`value/1`).
- Tests of `Crdt.Replica` start a replica with `start_supervised` and
  capture its console notices with `StringIO`.
- Distributed tests register a fake `Crdt.Replica` on a peer node and
  count the messages it receives.

## Traceability matrix

Each requirement (`REQUIREMENTS.md`), its design section (`DESIGN.md`),
its automated tests and its manual tests (`MANUAL-TESTS.md`). The numbers
are the tests that `mix test --only reqN` runs. Rows marked "(dist)"
include distributed tests.

| REQ | Design | Tests (`mix test --only reqN`) | Manual |
|---|---|---|---|
| REQ1 No node with a special role | DES6 | manual (0 tests) | MAN4 |
| REQ2 Every node keeps the whole document | DES3 | 1: `test/crdt/treedoc_test.exs` "new/0, effect/2 and value/1" | MAN1 |
| REQ3 A valid edit is applied at once at the index | DES3.4, DES3.5, DES9 | 17: `test/crdt/treedoc_test.exs` (prepare/3 for insert, prepare/3 for delete, edge cases, convergence, random checks: list model and total order); `test/crdt_test.exs` "replica without network" (4) | MAN3 |
| REQ4 An invalid index changes nothing | DES4.1, DES9 | 12: `test/crdt/treedoc_test.exs` (invalid indices, edge cases); `test/crdt/causal_test.exs` "next_local/2"; `test/crdt_test.exs` "replica without network" (5); `test/crdt_history_test.exs` "an invalid index, an empty text or count 0 do not change the file" | - |
| REQ5 A local edit is sent to every connected node | DES4, DES5 | manual (0 tests) | MAN1 |
| REQ6 A remote edit is applied | DES3.5, DES5 | 3: `test/crdt/treedoc_test.exs` "new/0, effect/2 and value/1"; `test/crdt_test.exs` "replica without network" (2) | MAN1, MAN3 |
| REQ7 Same ops, same text, in any order | DES3.3, DES4.2 | 11: `test/crdt/treedoc_test.exs` (compare/2, convergence without network, random checks: list model and total order); `test/crdt/causal_test.exs` "simulation with Treedoc" (2) | MAN2, MAN8 |
| REQ8 Concurrent inserts at one place: all kept, same order | DES3.4, DES3.6 | 6: `test/crdt/treedoc_test.exs` (compare/2, prepare/3 for insert, scenario of paper figures 3 and 4, edge cases) | MAN2 |
| REQ9 An op waits for the ops it depends on | DES4.2 | 10: `test/crdt/causal_test.exs` (duplicate?/2 and deliverable?/2, receive_message/3, simulation); `test/crdt_test.exs`; `test/crdt_history_test.exs` | - |
| REQ10 A duplicate is dropped | DES4.2 | 10: `test/crdt/causal_test.exs` (duplicates, duplicate?/2 and deliverable?/2, simulation); `test/crdt/treedoc_test.exs`; `test/crdt_test.exs` (2); `test/crdt_history_test.exs` | - |
| REQ11 An op reaches everyone even if its origin is gone (dist) | DES4.3 | 4: `test/crdt/causal_test.exs` "simulation with Treedoc" (2); `test/crdt_test.exs` "an echo of an own op..."; `test/crdt_distributed_test.exs` (a) | MAN4 |
| REQ12 A (re)connecting node gets what it misses (dist) | DES4.4, DES6 | 3: `test/crdt_test.exs` "nodeup, nodedown and hello count only for nodes in the table"; `test/crdt_distributed_test.exs` (c), (e) | MAN4 |
| REQ13 A restarted node recovers from disk, no repeated ids (dist) | DES4.5, DES4.6 | 17: `test/crdt_history_test.exs` (13); `test/crdt/causal_test.exs` "next_local/2" (2); `test/crdt_distributed_test.exs` (e), (f) | MAN5 |
| REQ14 Each node connects to the table by itself; bad table file (dist) | DES6 | 7: `test/crdt/config_test.exs` (4); `test/crdt_test.exs` "node table from NODES_FILE" (2); `test/crdt_distributed_test.exs` (d) | MAN4 |
| REQ15 Every message goes to every connected table node (dist) | DES6 | 4: `test/crdt_distributed_test.exs` (a), (b), (c), (e) | MAN1 |
| REQ16 Local and remote edits at once do not corrupt state (dist) | DES7, DES7.1 | 1: `test/crdt_distributed_test.exs` (d) | MAN8 |
| REQ17 The user can see text, table, clock, buffer, history, notices | DES9 | 10: `test/crdt_test.exs` (8); `test/crdt/treedoc_test.exs` "debug_rows/1"; `test/crdt/causal_test.exs` "waiting reports the last seq missing from each node" | MAN7 |
| REQ18 The history file is readable, one op per line | DES5.2 | 5: `test/crdt/log_format_test.exs` (4); `test/crdt_history_test.exs` "reload: same text, clock and history..." | MAN7 |
| REQ19 Incomplete last line is cut; damaged line stops the replica | DES4.5, DES9 | 9: `test/crdt_history_test.exs` (6); `test/crdt/log_format_test.exs` (1); `test/crdt_test.exs` (2) | - |
| REQ20 A multi-character edit stays together (dist) | DES4.5, DES7 | 5: `test/crdt_test.exs` (2); `test/crdt_history_test.exs` (2); `test/crdt_distributed_test.exs` (f) | MAN2 |

The distributed tests, by letter: (a) b2 waits, b1 arrives: both are
forwarded to the table node; (b) a connected node outside the table
receives nothing; (c) the history is resent on nodeup and on hello; (d)
an unreachable node in the table does not block `Crdt.insert`; (e) the
history loaded from the file is sent once to a connected table node;
(f) local call: one sync, then the sends; remote op: sync, notice,
forward.
