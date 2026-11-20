# Collaborative text editor with Treedoc

Written for the course ISIS-4218 (Universidad de los Andes).

A collaborative text editor with no central server, written in Elixir.
Every node keeps the whole document and sends its edits to the others.
All nodes end with the same text, even when two people type at the same
place at the same time. It uses Treedoc, an operation-based CRDT, and
causal delivery. The words used here are in the
[glossary](docs/MANUAL-TESTS.md#glossary).

## Adopt it step by step

Go as far as it is useful to you. Stopping at any step is fine: each
step works by itself.

| Step | You need | You will see | Guide |
|---|---|---|---|
| 1. One node alone on one computer | Elixir | You insert text, halt the node, start it again and the text is back | [Quick start, "One node"](#one-node) |
| 2. Three nodes on one computer | Three terminals | What you type in one node appears in the other two | [Quick start, "Three nodes"](#three-nodes), then [MANUAL-TESTS.md, "Short path"](docs/MANUAL-TESTS.md#short-path) |
| 3. Two or more computers on the same network | Two computers, for example Windows and macOS, each with a clone of this repository. One start command per computer: the nodes find each other, with no table to edit | Edits on one computer appear on the other | [NETWORK.md](docs/NETWORK.md) (not yet validated) |
| 4. One computer and one Raspberry Pi | A computer and a Pi on the same network, both with a clone, each started with its start script | Edits on the computer appear on the Pi, and back | [NETWORK.md](docs/NETWORK.md), with `scripts/start.sh` on the Pi (Raspberry Pi OS is Linux). Raspberry Pi setup guide (system and Elixir): coming |
| 5. Two Raspberry Pis | Two Pis with a clone, each with its own hostname, and no computer as a node. You reach them over SSH from any device | Edits on one Pi appear on the other | [NETWORK.md](docs/NETWORK.md), as in step 4. Raspberry Pi setup guide (system and Elixir): coming |
| 6. Your own implementation | Your node, on a Pi or a computer, that speaks our contract | Your node and ours exchange operations | [INTEGRATION.md](docs/INTEGRATION.md). Tested on one computer. Optional: a team that stops at step 5 has a complete system |

Each step adds one thing to the one before: a second process, a second
machine, a small device, a device without a screen, another
implementation.

## Reference

- [TESTS.md](docs/TESTS.md): 84 automated tests, plus 10 with real nodes
  (11 on macOS and Linux), runnable per requirement.
- [REQUIREMENTS.md](docs/REQUIREMENTS.md): what the system must do, and how
  each requirement is checked.
- [DESIGN.md](docs/DESIGN.md): how it works, and where each decision comes
  from.
- [CODE-MAP.md](docs/CODE-MAP.md): a path to study the code, module by
  module.

Known limitations (short texts, tombstones kept forever, discovery only
on the local network and more; a tombstone is a deleted character that is kept, hidden, with
its position):
[DESIGN.md, section 14](docs/DESIGN.md#14-known-limitations).

## Quick start

You need Elixir 1.18 or later with Erlang/OTP 27 or later. There are no
dependencies. Once, in the project folder (the same on Windows, macOS and
Linux):

```sh
mix compile
mix test
```

Each node starts with a start script: `scripts/start.ps1` on Windows,
`scripts/start.sh` on macOS and Linux. It names the node, compiles and
starts IEx. Here the name and the IP are given, for nodes on one
computer; on a network the script picks them by itself
([NETWORK.md](docs/NETWORK.md)). If PowerShell refuses to run the
script, once: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

### One node

Start one node, in the project folder.

Windows (PowerShell):

```powershell
.\scripts\start.ps1 -Name crdt1 -Ip 127.0.0.1
```

macOS and Linux:

```sh
./scripts/start.sh --name crdt1 --ip 127.0.0.1
```

It prints `node: crdt1@127.0.0.1 (interface: given)`, then
`history loaded: 0 ops`. It announces itself every 2 seconds, so the
other nodes of this computer find it.

Insert text and halt the node:

```elixir
Crdt.insert(0, "hola")
System.halt()
```

Start it again with the same command. It prints `history loaded: 4 ops`,
and `Crdt.text()` returns `"hola"`. The node keeps its history in
`data/crdt1.jsonl` and reloads it when it starts.

### Three nodes

One terminal per node, in the project folder. If crdt1 is still running
from the part above, leave it.

Windows (PowerShell):

```powershell
.\scripts\start.ps1 -Name crdt1 -Ip 127.0.0.1
.\scripts\start.ps1 -Name crdt2 -Ip 127.0.0.1
.\scripts\start.ps1 -Name crdt3 -Ip 127.0.0.1
```

macOS and Linux:

```sh
./scripts/start.sh --name crdt1 --ip 127.0.0.1
./scripts/start.sh --name crdt2 --ip 127.0.0.1
./scripts/start.sh --name crdt3 --ip 127.0.0.1
```

Within a few seconds they find each other: `Crdt.status()` lists the
other two in `connected:`.

Try it. On crdt2, `Crdt.text()` returns `"hola"`, received from crdt1
(`""` if you skipped the one-node part). Then, on crdt2,
`Crdt.insert(0, "hey ")`. On crdt1 and crdt3, `Crdt.text()` returns
`"hey hola"` (`"hey "` if you skipped it).

```elixir
Crdt.insert(index, "text")   # insert each character starting at index
Crdt.delete(index, count)    # delete count characters (count defaults to 1)
Crdt.text()                  # visible text
Crdt.status()                # node, table, discovery, connected nodes, clock, history, buffer
Crdt.history()               # last 10 applied operations; Crdt.history(:all) for all
Crdt.debug()                 # each character with its position identifier
```

Each node keeps its history in `data/<name>.jsonl` (the name before
`@`) and reloads it on restart. To start from scratch, halt every node (`System.halt()`) and
delete `data/*.jsonl`.

## How to read this project

The documents and the code use short codes. Every REQ, CON, CLS,
implemented PAP section and `DESIGN.md` DES3 to DES9 also appears in a comment
or a `@doc` in `lib/` (or `mix.exs`), where it is implemented.

| Code | What it is | Example | Where it lives |
|---|---|---|---|
| REQ | Requirement | REQ7 (same operations, same text) | [REQUIREMENTS.md](docs/REQUIREMENTS.md) |
| CON | Constraint | CON1 (Elixir 1.18.3, OTP 27) | [REQUIREMENTS.md](docs/REQUIREMENTS.md) |
| MAN | Manual test | MAN4 (halt a node, catch up) | [REQUIREMENTS.md](docs/REQUIREMENTS.md), [MANUAL-TESTS.md](docs/MANUAL-TESTS.md) |
| DES | Section of DESIGN.md, DES4.2 = section 4.2 | DES4.2 (apply, wait or drop) | [DESIGN.md](docs/DESIGN.md) |
| ASG | Origin: the course assignment | Explicit connection between nodes | Course material, not included; [REQUIREMENTS.md](docs/REQUIREMENTS.md), "Origin" |
| PAP | Origin: the Treedoc paper; PAP3.1 = section 3.1 of the paper | PAP3.1 (in-order traversal) | [Paper](#paper) |
| CLS | Origin: the course slides on causality | Causal delivery with vector clocks | Course material, not included; [REQUIREMENTS.md](docs/REQUIREMENTS.md), "Origin" |
| OUR | Origin: a decision of this project | One disk sync per local call | [DESIGN.md](docs/DESIGN.md) DES2 |
| `@tag :reqN` | Test tag of requirement REQN | `mix test --only req7` | `test/`, [TESTS.md](docs/TESTS.md) |
| `@tag :distributed` | Tests with real nodes, excluded by default | `mix test --include distributed` | `test/crdt_distributed_test.exs` |

## Paper

Nuno Preguiça, Joan Manuel Marquès, Marc Shapiro, Mihai Leția.
*A commutative replicated data type for cooperative editing.*
ICDCS 2009. <https://doi.org/10.1109/ICDCS.2009.20>

## License

MIT. See [LICENSE](LICENSE).
