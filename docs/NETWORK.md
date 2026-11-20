# Two computers on the same network

**Not yet validated on two computers.** These steps were rehearsed with
two nodes on one Windows computer, using its network address. A run
between two real computers may need fixes.

One node on a Mac and one on a Windows computer, on the same network.
Node names use the IP address (`name@IP`), not `.local`.

1. Code. On both computers, clone or copy the repository, open a
   terminal in its folder and run `mix compile` and `mix test` (see
   [README.md](../README.md)).
2. IP addresses. On Windows: `ipconfig` (line "IPv4 Address" of the
   Wi-Fi or Ethernet adapter). On the Mac:
   `ipconfig getifaddr en0` (Wi-Fi; `en1` on some Macs). Below,
   `<WIN_IP>` and `<MAC_IP>`.
3. Windows: the network should be private. If it is public, the firewall
   may block the connection. Settings > Network & internet > Wi-Fi (or
   Ethernet) > the network > Network profile type: Private. Or, in a
   PowerShell run as administrator:

   ```powershell
   Get-NetConnectionProfile
   Set-NetConnectionProfile -InterfaceAlias "Wi-Fi" -NetworkCategory Private
   ```

   When the firewall asks about `erl.exe` or `epmd.exe`, allow them on
   private networks.

   If you cannot mark the network as private (for example, a corporate
   computer without administrator rights), go on anyway: the Erlang
   connection is opened by Windows towards the Mac (step 5.2), so it is
   outgoing. If `Node.connect` returns `true` there, the rest works, and
   in step 8 Windows reconnects by itself.

   On the Mac, if the firewall asks whether `beam.smp` may accept
   incoming connections, allow it.
4. A temporary node table, outside the project folder, with the same two
   lines on both computers:

   ```
   crdt@<WIN_IP>
   crdt@<MAC_IP>
   ```

   Windows (PowerShell): `notepad $env:TEMP\nodes.pair.txt`. Mac:
   `nano /tmp/nodes.pair.txt`.
5. Connection test in three steps, before our code:
   1. Network: on Windows `ping <MAC_IP>`; on the Mac `ping -c 3 <WIN_IP>`.
      Windows blocks incoming ping by default, so the ping from the Mac
      to Windows may fail without it being an error; what counts is the
      ping from Windows to the Mac.
   2. Erlang distribution. On the Mac: `iex --name crdt@<MAC_IP> --cookie cpd2026`.
      On Windows: `iex.bat --name crdt@<WIN_IP> --cookie cpd2026`, then
      `Node.connect(:"crdt@<MAC_IP>")` returns `true`.
   3. On Windows, `Node.list()` returns `[:"crdt@<MAC_IP>"]`.

   Leave both with `System.halt()`. If step 2 returns `false`, check the
   cookie, that Windows is on a private network, and the firewall.
6. Start the nodes with the temporary table:

   ```powershell
   $env:NODES_FILE="$env:TEMP\nodes.pair.txt"; iex.bat --name crdt@<WIN_IP> --cookie cpd2026 -S mix
   ```

   ```sh
   NODES_FILE=/tmp/nodes.pair.txt iex --name crdt@<MAC_IP> --cookie cpd2026 -S mix
   ```

   Each prints `history loaded: 0 ops`. Within a few seconds,
   `Crdt.status()` lists the other node in `connected:` (a `connected`
   or `hello from` notice may or may not appear, depending on which
   node started first).
7. MAN1. On Windows: `Crdt.insert(0, "hola")`. On the Mac,
   `Crdt.text()` returns `"hola"` and the console shows
   `applied op 1 from crdt@<WIN_IP>: ins "h"` up to `op 4`. Then the
   other way: on the Mac `Crdt.insert(4, " mac")`; on Windows
   `Crdt.text()` returns `"hola mac"`.
8. A node off does not block the other. On the Mac: `System.halt()` (or
   turn off its Wi-Fi). On Windows:

   ```elixir
   :timer.tc(fn -> Crdt.insert(0, "x") end)   # {micros, :ok}, micros well under 1_000_000
   ```

   `Crdt.insert` answers at once while the node keeps trying to
   reconnect (`DESIGN.md` DES7.1). Start the Mac node again: it catches up.
9. Clean up: halt both nodes and delete the files of this test,
   `data/crdt_<WIN_IP with _>.jsonl` and `data/crdt_<MAC_IP with _>.jsonl`
   (for example `data/crdt_192_168_1_20.jsonl`), and the temporary table.
