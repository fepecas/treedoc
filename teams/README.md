# Teams

Other teams' implementations that edit the same document as ours
(REQ22), and how each one was checked.

- `teams/<name>.md`: one file per team. What its code does at each
  layer of [INTEGRATION.md](../docs/INTEGRATION.md), where it differs
  from ours, and the interoperation tests (MAN16 to MAN18).
- `teams/<name>/`: a local clone of that team's repository, used to
  read and run its code. Clones are not part of this repository.

The contract is ours: [INTEGRATION.md](../docs/INTEGRATION.md) (L1,
L2, L3 and its rules 1 to 5) and `DESIGN.md` DES3 to DES6. A team
follows it; we do not change it for a team.

## Where our code meets each rule

Our side of the contract, by file and function.

| Rule of INTEGRATION.md | Our code |
|---|---|
| L1: cookie, long name with the IPv4 | `scripts/start.ps1`, `scripts/start.sh`; on Nerves `firmware/lib/crdt_fw.ex`, `CrdtFw.start_node/1` |
| L1: ports 4218 to 4228 | `scripts/start.ps1`, `scripts/start.sh` (`ERL_AFLAGS`); on Nerves `CrdtFw` (`Application.put_env/3` before `Node.start/1`) |
| L1: `prevent_overlapping_partitions false`, `net_ticktime` at the default | `scripts/start.ps1`, `scripts/start.sh` (`ERL_AFLAGS`); `firmware/rel/vm.args.eex`; nothing sets `net_ticktime` |
| L2: the discovery packet | `lib/crdt/discovery.ex`: `packet/1`, `parse/1`, `handle_info/2` |
| L3: the process `Crdt.Replica` and its two casts | `lib/crdt/replica.ex`: `start_link/1`, `handle_cast/2` |
| L3: history sent on connection and on `hello` | `lib/crdt/replica.ex`: `handle_info/2` (`:nodeup`), `handle_cast/2` (`:hello`), `resend_history/2`, `send_history/1`, `start/6` |
| L3: every applied op forwarded once | `lib/crdt/replica.ex`: `handle_event/2`, `broadcast/1` |
| Rule 1: `vc[from]` counts 1, 2, 3 | `lib/crdt/causal.ex`: `next_local/2`, `duplicate?/2`, `deliverable?/2`, `receive_message/3`; `lib/crdt/replica.ex`: `start/6` (the clock rebuilt from the file) |
| Rule 2: `vc[k]` at most what `k` sent | `lib/crdt/causal.ex`: `deliverable?/2`, `missing/2` |
| Rule 3: `ch` is one grapheme | `lib/crdt/replica.ex`: `handle_call/3` (`String.graphemes/1`); `lib/crdt/treedoc.ex`: `valid_op?/1` |
| Rule 4: `pos` new, unique, in the right place | `lib/crdt/treedoc.ex`: `prepare/3`, `new_pos/4`, `compare/2` |
| Rule 5: the exact format | `lib/crdt/treedoc.ex`: `valid_op?/1`; `lib/crdt/causal.ex`: `valid_clock?/1`; `lib/crdt/replica.ex`: `handle_cast/2`, `format_keys/1`, `drop/2` |

## Teams

| Team | Repository | Commit checked | MAN16 | MAN17 | MAN18 |
|---|---|---|---|---|---|
| [carla](carla.md) | [Carlixgonzam/distribution-project-](https://github.com/Carlixgonzam/distribution-project-) | `ad9d665` | Passed (Case 7 and MAN4 not run) | Passed (MAN4 not run) | Pending |

MAN16: our node and theirs on computers. MAN17: with our Pi with
Nerves. MAN18: Pi to Pi. Steps: `MANUAL-TESTS.md`, "Interoperation
(MAN16 to MAN18)".

## Add a team

1. Clone its repository into `teams/<name>/` and check out the commit
   to test. Note that commit: the tests are valid for it only.
2. Read its code against [INTEGRATION.md](../docs/INTEGRATION.md),
   layer by layer and rule by rule. Its code wins over its own
   documents when they disagree.
3. Write `teams/<name>.md` as [carla.md](carla.md) is written: credit,
   its side of each layer with links pinned to the commit, what only
   it has and what only we have, how to run it, and the results.
4. Add a row to the table above, and the file to
   `publish/manifest.txt`.
5. Run MAN16 to MAN18 with it and write the results in its file.
