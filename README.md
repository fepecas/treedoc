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
| 2. Three nodes on one computer | Three terminals | What you type in one node appears in the other two | [Quick start, "Three nodes"](#three-nodes) |
| 3. Two or more computers on the same network | Two computers, for example Windows and macOS, each with a clone of this repository. One start command per computer: the nodes find each other, with no table to edit | Edits on one computer appear on the other | [NETWORK.md](docs/NETWORK.md) |
| 4. A computer and a Pi with Raspberry Pi OS | A computer and a Pi on the same network, both with a clone, each started with its start script | Edits on the computer appear on the Pi, and back | [README-pi.md](deploy/README-pi.md); [INTEGRATION.md, "Add another Raspberry Pi"](docs/INTEGRATION.md#add-another-raspberry-pi) |
| 5a. A computer and a Pi 4 with Nerves: ready image | A Pi 4, a microSD card, the test hotspot, and a computer as in step 3 | The Pi boots into a node and joins by itself | [README-nerves.md, Path A](deploy/README-nerves.md#path-a-ready-image) |
| 5b. A computer and a Pi 4 with Nerves: build your own | As in 5a, plus Elixir and the Nerves tools; your Wi-Fi and SSH keys | As in 5a, and an SSH console on the Pi | [README-nerves.md, Path B](deploy/README-nerves.md#path-b-build-your-own) |
| 6. Two Raspberry Pis | Two Pis, any combination of steps 4 and 5, and no computer as a node | Edits on one Pi appear on the other | [README-pi.md](deploy/README-pi.md), [NETWORK.md](docs/NETWORK.md) |
| 7. Your own implementation | Your node, on a Pi or a computer, that speaks our contract (`prevent_overlapping_partitions false` included) | Your node and ours edit the same document; a malformed message of yours is dropped with a notice | [INTEGRATION.md](docs/INTEGRATION.md); [teams/](teams/README.md); [MANUAL-TESTS.md, MAN16 to MAN18](docs/MANUAL-TESTS.md#interoperation-man16-to-man18). Optional: a team that stops at step 6 has a complete system |

Each step adds one thing to the one before: a second process, a second
machine, a small device, a device with nothing to install, no computer
at all, another implementation.

Where each step stands:

| Step | Status | Date | Platforms and versions |
|---|---|---|---|
| 1. One node | Done | November 2026 | Windows, Elixir 1.20.4, OTP 29 |
| 2. Three nodes on one computer | Done | November 2026 | Windows, Elixir 1.20.4, OTP 29 |
| 3. Two computers | Done | November 2026 | Windows (Elixir 1.20.4, OTP 29) and macOS (Elixir 1.20.5, OTP 29), home Wi-Fi |
| 4. A computer and a Pi | Done | November 2026 | Windows and Raspberry Pi 4, Raspberry Pi OS 64-bit (Elixir 1.18.3, OTP 27), phone hotspot; a Mac joined as a third machine |
| 5a. A Pi 4 with Nerves, ready image | Done | November 2026 | Raspberry Pi 4, iPhone hotspot, and macOS (Elixir 1.20.5, OTP 29): MAN14 passes (discovery, MAN1, MAN4, MAN5). Two Pis with the image on another router with the test hotspot's SSID and password: both worked, each seen on its own monitor. MAN15 (another Wi-Fi network) not run |
| 5b. A Pi 4 with Nerves, own build | Done | November 2026 | Built on macOS twice (OTP 29.1.2, `nerves_system_rpi4` 2.2.2), the images of 5a. Also built from this repository on Linux for a Raspberry Pi 3, and it ran there. WSL2 untested |
| 6. Two Pis | Done | November 2026 | Two Raspberry Pi 4 with the ready Nerves image, on a router with no Internet that broadcasts the test hotspot's network, no computer as a node; each Pi joined under a new name and kept its history |
| 7. Your own implementation | Done | November 2026 | Carlixgonzam's implementation ([teams/carla.md](teams/carla.md)): our node on Windows, hers on macOS (it does not build on Windows), iPhone hotspot; MAN16 passed (discovery, MAN1, MAN2, MAN3); MAN17 with our Pi with Nerves passed (discovery, MAN1, MAN3); MAN18 (Pi to Pi) pending |

The results of steps 3 and 4:
[MANUAL-TESTS.md, MAN9 to MAN13](docs/MANUAL-TESTS.md#between-computers-tests-run-man9-to-man13).

## Reference

- [TESTS.md](docs/TESTS.md): 84 automated tests, plus 10 with real nodes
  (11 on macOS and Linux), runnable per requirement.
- [REQUIREMENTS.md](docs/REQUIREMENTS.md): what the system must do, and how
  each requirement is checked.
- [DESIGN.md](docs/DESIGN.md): how it works, and where each decision comes
  from.
- [CODE-MAP.md](docs/CODE-MAP.md): a path to study the code, module by
  module.

Known limitations: see [below](#known-limitations), and the full list
in [DESIGN.md, section 14](docs/DESIGN.md#14-known-limitations).

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

### On a network: one node per computer

Once per computer: clone, compile and test, as above. Then start the
node with no name and no IP: the script uses the hostname and picks the
Wi-Fi IPv4 by itself, and the nodes find each other.

Windows (PowerShell; the network profile must be Private, see
[NETWORK.md](docs/NETWORK.md), section 2):

```powershell
.\scripts\start.ps1
```

macOS:

```sh
./scripts/start.sh
```

Raspberry Pi (Raspberry Pi OS 64-bit):

```sh
sudo apt install -y elixir git
git clone <repository URL> ~/crdt
cd ~/crdt
mix compile
mix test
./scripts/start.sh
```

Type the `./` or `.\` in front of the script. Check on each node with
`Node.list()` and `Crdt.status()`. To use a neutral node name instead
of the hostname: `-Name <name>` (Windows) or `--name <name>`.

## Network requirements

- All the nodes on the same Wi-Fi or phone hotspot; discovery does not
  cross routers. Some networks (labs, guest Wi-Fi) block multicast:
  then use a node table ([NETWORK.md](docs/NETWORK.md), section 5).
- Ports: TCP 4369 (EPMD), TCP 4218 to 4228 (Erlang distribution, fixed
  by the start scripts), UDP 45892 (discovery). On Windows, the network
  profile Private and three firewall rules; on macOS, allow `beam.smp`
  when asked.
- Every computer with its own hostname.
- The cookie `cpd2026` is shared by the whole course: anyone with it
  can run code on your node. Use trusted networks only
  ([INTEGRATION.md](docs/INTEGRATION.md#security-first)).

## Known limitations

- The history grows fast when typing in a row: each position identifier
  is one step longer per character and repeats the full node name
  (observed: 14 characters gave a history of about 6 KB). The whole
  history is resent on every connection. Keep texts short.
- The node name includes the IP, so one computer used on two networks
  shows as two authors. It does not affect convergence.
- One console line per dropped duplicate: a reconnection prints many
  `duplicate dropped` lines. It is not an error.
- Reconnection may be slow: once, on a home Wi-Fi, a restarted node
  reconnected after about 30 s (observed, not measured); on a phone
  hotspot it was immediate.
- Node names are sent to every node and stored in every operation: on a
  work computer, start with a neutral name (`-Name` / `--name`).
- On a Pi with Nerves, a new IP needs a restart, burning the card again
  deletes the history in `/data`, and the notices show on an HDMI
  screen, not over SSH
  ([README-nerves.md](deploy/README-nerves.md#update-without-burning)).
- Tombstones (deleted characters, kept hidden with their position) stay
  forever; discovery only reaches the local network. More in
  [DESIGN.md, section 14](docs/DESIGN.md#14-known-limitations).

## How to read this project

The documents and the code use short codes. Every REQ, CON, CLS,
implemented PAP section and `DESIGN.md` DES3 to DES9 also appears in a comment
or a `@doc` in `lib/` (or `mix.exs`), where it is implemented. The
folder `firmware/` is the firmware for a Raspberry Pi 4 with Nerves
(`DESIGN.md` DES15): it starts the same node of `lib/` with no start
script; REQ21 and DES15 are cited there.

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
