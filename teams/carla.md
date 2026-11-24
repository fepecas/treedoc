# carla

Implementation: [distribution-project-](https://github.com/Carlixgonzam/distribution-project-),
folder [`documento/`](https://github.com/Carlixgonzam/distribution-project-/tree/ad9d665352b0e60763ebc78743d180b30b617f2e/documento),
commit `ad9d665`, by GitHub user [Carlixgonzam](https://github.com/Carlixgonzam).
Everything below was checked against that commit. Links to her code are
pinned to it; ours are cited by file and function.

Her contract file: [`PROTOCOL.md` at `ad9d665`](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/PROTOCOL.md)
([current version on `main`](https://github.com/Carlixgonzam/distribution-project-/blob/main/PROTOCOL.md),
may differ). It restates our [INTEGRATION.md](../docs/INTEGRATION.md)
and adds a few rules.

## What her PROTOCOL.md asks beyond INTEGRATION.md

In our words, and whether our code meets each one.

| Her rule | Our code |
|---|---|
| Every node starts with `-kernel prevent_overlapping_partitions false` | Yes: `scripts/start.ps1`, `scripts/start.sh` (`ERL_AFLAGS`), `firmware/rel/vm.args.eex` (REQ22, `DESIGN.md` DES6). Now also in INTEGRATION.md, L1 |
| `net_ticktime` stays at the OTP default, 60 s | Yes: nothing of ours sets it |
| Distribution ports 4218 to 4228 | Yes: the start scripts and `CrdtFw` |
| A Pi's name carries an epoch, so a burned card never reuses a `seq` | No, and not needed: our Pi is `<hostname>@<IPv4>`. Before a test after a burn, every history is deleted at once (`MANUAL-TESTS.md`, MAN17; `DESIGN.md` DES14) |
| A malformed message is ignored and never crashes the replica | Yes: `lib/crdt/replica.ex`, `handle_cast/2`, `handle_call/3`, `handle_info/2`, `drop/2` (REQ23, `DESIGN.md` DES5.1). We also print a notice |

## Her side, layer by layer

| Layer | What her code does | Her code | Same as ours? |
|---|---|---|---|
| L1 cookie and name | Cookie `cpd2026`; laptops any `<name>@<IPv4>`; Pis `<hostname>-<epoch>@<IPv4>` | [`red.ex` L48-L63](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib_target/red.ex#L48-L63), [`mix.exs` L89](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/mix.exs#L89) | Same, except the epoch |
| L1 ports and partitions | Ports 4218 to 4228 and the partitions flag in the release | [`rel/vm.args.eex` L49-L50](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/rel/vm.args.eex#L49-L50) | Same |
| L2 packet | `crdt-treedoc-1 <name>` to 233.252.1.32:45892, TTL 1, every 2 s | [`descubrimiento.ex` L4-L7](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/descubrimiento.ex#L4-L7), [L61-L70](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/descubrimiento.ex#L61-L70) | Same |
| L2 parsing | The name must match `[A-Za-z0-9_\-.]{1,64}@<IPv4>`; at most 256 names; 30 s between tries to one node | [L10-L11](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/descubrimiento.ex#L10-L11), [L28-L37](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/descubrimiento.ex#L28-L37), [L113-L136](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/descubrimiento.ex#L113-L136) | Differs, stricter; our names match her pattern |
| L2 socket | `reuseaddr`; no socket when the node's host is `127.0.0.1` | [L158-L172](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/descubrimiento.ex#L158-L172), [L228-L240](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/descubrimiento.ex#L228-L240) | Differs: on `127.0.0.1` her node must be connected by hand |
| L3 process and casts | `Crdt.Replica`; `{:remote, op}` and `{:hello, node}` with an atom; unknown calls answer an error, other casts and messages are ignored | [`mensaje.ex` L2](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/mensaje.ex#L2), [`replica.ex` L77-L104](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L77-L104) | Same |
| L3 format check | `from`, `vc` (at most 10 000 keys), `vc[from] >= 1`, steps, one grapheme; only the known keys are kept | [`mensaje.ex` L9-L72](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/mensaje.ex#L9-L72) | Same, except a step node `nil`, `true` or `false` (below) |
| L3 order | In-order traversal; steps compared as `{bit, seq, node}` tuples | [`treedoc.ex` L6-L24](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/treedoc.ex#L6-L24) | Same as `lib/crdt/treedoc.ex`, `compare/2` |
| L3 tombstones | A delete marks the PosID; the char stays | [L78-L80](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/treedoc.ex#L78-L80) | Same |
| L3 one PosID, two chars | Keeps the smaller char | [L74-L76](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/treedoc.ex#L74-L76) | Differs: ours keeps the last applied. Only a node that reuses a `seq` causes it |
| L3 causal delivery | Duplicate, apply or wait by the vector clock; the buffer is checked again after each op | [`causal.ex` L7-L21](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/causal.ex#L7-L21), [L57-L76](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/causal.ex#L57-L76) | Same as `lib/crdt/causal.ex`, `receive_message/3` |
| L3 buffer | At most 50 000 waiting ops; the oldest are dropped | [`replica.ex` L9](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L9), [L311-L317](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L311-L317) | Differs: ours has no limit (`DESIGN.md` DES14) |
| L3 forwarding | Every op applied from the network is written, then forwarded once | [L323-L336](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L323-L336) | Same |
| L3 history resend | On `:nodeup`, on `hello`, and at start if nodes are connected | [L88-L100](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L88-L100), [L126-L129](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L126-L129), [L346-L352](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L346-L352) | Same |
| L3 sync before send | Local ops are written and synced before they leave | [`historial.ex` L19-L29](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/historial.ex#L19-L29), [`replica.ex` L275-L289](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L275-L289) | Same |

## The user API

Both run in IEx. Each local edit becomes one `{:remote, op}` per
character, sent to every node of `Node.list()`.

| Ours (`lib/crdt.ex`) | Hers ([`cpd_doc.ex`](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc.ex)) | Where the edit becomes `{:remote, op}` |
|---|---|---|
| `Crdt.insert(i, text)` | `CpdDoc.insertar(i, texto)` ([L4-L6](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc.ex#L4-L6)) | Ours: `lib/crdt/replica.ex`, `handle_call/3`, `local_edit/2`, `broadcast/1`. Hers: [`replica.ex` L30-L36](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L30-L36), [L263-L289](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L263-L289), [L354-L360](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L354-L360) |
| `Crdt.delete(i, n)` | `CpdDoc.borrar(i, n)` ([L8-L14](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc.ex#L8-L14)) | Ours: the same path. Hers: [`replica.ex` L38-L43](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L38-L43), then the same path |
| `Crdt.text()` | `CpdDoc.texto()` ([L16-L18](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc.ex#L16-L18)) | No op |
| `Crdt.status()` | `CpdDoc.estado()` ([L20-L22](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc.ex#L20-L22)) | No op |
| `Crdt.history()` | `CpdDoc.historial()` ([L24-L26](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc.ex#L24-L26)) | No op |
| `Node.connect/1` | `CpdDoc.conectar/1` ([L28-L38](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc.ex#L28-L38)) | No op |
| `Crdt.debug()` | None | No op |

## Only hers

- Pi-name epoch: 6 random hex characters in `/data`, removed when the
  history is damaged, so a Pi never reuses a `seq`
  ([`red.ex` L48-L97](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib_target/red.ex#L48-L97),
  [`replica.ex` L162-L167](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/replica.ex#L162-L167)).
  Interop: none; her names are plain atoms to us.
- Balanced multi-character inserts: the middle character goes first
  between its neighbours, and the halves become its subtrees
  ([`treedoc.ex` L50-L62](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/treedoc.ex#L50-L62),
  [L82-L106](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/treedoc.ex#L82-L106)).
  So an op can go through a step of an op not applied yet. Interop:
  none; ours places it right (test "an insert of the other
  implementation's shape lands in the right place", REQ22).
- epmd sweep: her Pis ask epmd at every address of their /24 every
  10 s, and connect to the names that match her pattern
  ([`descubrimiento.ex` L83-L92](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/descubrimiento.ex#L83-L92),
  [L181-L227](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/lib/cpd_doc/descubrimiento.ex#L181-L227)).
  Off on laptops unless `CPD_DOC_BARRIDO=on`
  ([`config/host.exs` L23-L26](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/config/host.exs#L23-L26)).
  Interop: it helps; her Pis find our nodes even without multicast.

## Only ours

- The optional node table (`NODES_FILE`; `lib/crdt/config.ex`,
  `nodes/0`; `lib/crdt/replica.ex`, `handle_info/2` with `:connect`).
  Interop: none; it only adds connections.
- The step node rule: we drop an op whose PosID has a step with node
  `nil`, `true` or `false`; she accepts it (`lib/crdt/treedoc.ex`,
  `valid_op?/1`, `steps?/1`; `DESIGN.md` DES5.1). Our history file
  could not load those atoms back. Interop: none in practice; no
  correct node sends them. If one did, its later ops would wait on our
  nodes.
- `Crdt.debug()`: each character with its PosID. Interop: none.

## Running her node

Her project does not build on Windows: `mix deps.get` fetches every
Nerves system her `mix.exs` lists
([L62-L79](https://github.com/Carlixgonzam/distribution-project-/blob/ad9d665352b0e60763ebc78743d180b30b617f2e/documento/mix.exs#L62-L79)),
also with `MIX_TARGET=host`, and one of them cannot be unpacked there:

```
* Updating nerves_system_trellis (Hex package)
** (Mix) Unpacking tarball failed: inner tarball error, not owner
```

Run it on macOS or Linux. It needs the Mix archive `nerves_bootstrap`
(`mix archive.install hex nerves_bootstrap`). On a Mac, from this
repository:

```sh
cd <project folder>
git clone https://github.com/Carlixgonzam/distribution-project- teams/carla
cd teams/carla
git checkout ad9d665
cd documento
MIX_TARGET=host mix deps.get
MIX_TARGET=host mix test
```

Her node, named with the IPv4 that `scripts/start.sh` would pick:

```sh
cd <project folder>/teams/carla/documento
MIX_TARGET=host iex --name carla-mac@$(ipconfig getifaddr $(route -n get default | awk '/interface:/ {print $2}')) --cookie cpd2026 --erl "-kernel inet_dist_listen_min 4218 inet_dist_listen_max 4228 prevent_overlapping_partitions false" -S mix
```

Her history is `datos/carla-mac.log` in `documento/`.

## Reproduce MAN16

1. Her node on a Mac, as above.
2. Our node on Windows, in PowerShell (`-Ip <IPv4>` is optional; the
   script finds the Wi-Fi IPv4):

   ```powershell
   cd <project folder>
   .\scripts\start.ps1 -Name win-a
   ```

3. On win-a, `Node.list()` shows `carla-mac@...` after a few seconds.
   If not (multicast blocked): `Node.connect(:"carla-mac@<Mac IPv4>")`
   on win-a, or `CpdDoc.conectar("win-a@<Windows IPv4>")` on hers.
4. The steps of MAN16 in `MANUAL-TESTS.md`, "Interoperation (MAN16 to
   MAN18)": win-a uses `Crdt`, hers uses `CpdDoc`. Between two
   computers, MAN2 edits while one side is disconnected.

## Results

| Test | Status | Setup |
|---|---|---|
| MAN16 | Passed, Case 7 and MAN4 not run (November 2026) | win-a on Windows (Elixir 1.20.4, OTP 29), carla-mac on macOS, iPhone hotspot |
| MAN17 | Passed, MAN4 not run (November 2026) | our Pi nerves-35f1 (Nerves) and carla-mac on macOS, iPhone hotspot |
| MAN18 | Pending | |

MAN16 (step numbers of `MANUAL-TESTS.md`, MAN16):

- The two nodes found each other by discovery, with no
  `Node.connect/1`.
- Step 1: on win-a,
  `:application.get_env(:kernel, :prevent_overlapping_partitions)`
  returned `{:ok, false}`.
- Step 2 (MAN1) passed: `Crdt.text()` on win-a and `CpdDoc.texto()` on
  carla-mac both returned `"hola mundo"`.
- Step 3 (MAN2) passed: edits made while the Mac was disconnected, at
  the same place and at different places, gave the same text on both.
- Step 4 (MAN3) passed: the same text on both after a delete.
- Steps 5 (Case 7) and 6 (MAN4): not run.
- Step 7 (the probe): not run. REQ23 is covered by the automated tests,
  among them a distributed test where another node casts malformed
  terms to our replica (`TESTS.md`, REQ23).

MAN17:

- The image was built from the same code; `vm.args` in the release
  has `-kernel prevent_overlapping_partitions false`.
- First, every node's history was deleted (the reset above).
- carla-mac found the Pi by discovery, with no `Node.connect/1`.
- On the Pi, `:application.get_env(:kernel, :prevent_overlapping_partitions)`
  returned `{:ok, false}`.
- MAN1 passed: `"hola pi"` on both.
- MAN3 passed: `"la pi"` on both.
- MAN4: not run.
- Our computer was not a node in this run; the test counts with the Pi
  and the other implementation only.
