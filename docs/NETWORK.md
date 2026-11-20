# Several computers on the same network

**Not yet validated between computers.** On one Windows computer the
start scripts, discovery and three nodes were run for real; multicast
was checked between a Windows computer and a Raspberry Pi on a phone
hotspot. A run between real computers may need fixes.

One node per computer (Windows, macOS or a Raspberry Pi), on the same
Wi-Fi. Each node finds the others by itself: no node table to edit.
Node names are `<hostname>@<IPv4>`, for example `pi-pe@172.20.10.4`
(`DESIGN.md` DES6).

- [1. Get the code](#1-get-the-code)
- [2. Once per computer: firewall](#2-once-per-computer-firewall)
- [3. Start the node](#3-start-the-node)
- [4. Check](#4-check)
- [5. If the nodes do not find each other](#5-if-the-nodes-do-not-find-each-other)
- [6. More](#6-more)

## 1. Get the code

On each computer, in a terminal:

```sh
git clone <repository URL> crdt
cd crdt
mix compile
mix test
```

Every computer needs its own hostname. Two Raspberry Pis left as
`raspberrypi` would use the same node name part and the same clock
entries; rename one (Raspberry Pi Imager, or `sudo hostnamectl
set-hostname crdt-pi2` and a reboot).

## 2. Once per computer: firewall

**Windows.** In a PowerShell run as administrator. First, the network
must be private (Settings > Network & internet > Wi-Fi > the network >
Network profile type: Private), or:

```powershell
Get-NetConnectionProfile
Set-NetConnectionProfile -InterfaceAlias "Wi-Fi" -NetworkCategory Private
```

Then three rules, for the fixed ports of the start script: EPMD (TCP
4369), the Erlang distribution (TCP 4218 to 4228) and discovery (UDP
45892):

```powershell
New-NetFirewallRule -DisplayName "crdt epmd" -Direction Inbound -Protocol TCP -LocalPort 4369 -Profile Private -Action Allow
New-NetFirewallRule -DisplayName "crdt distribution" -Direction Inbound -Protocol TCP -LocalPort 4218-4228 -Profile Private -Action Allow
New-NetFirewallRule -DisplayName "crdt discovery" -Direction Inbound -Protocol UDP -LocalPort 45892 -Profile Private -Action Allow
```

Last, as your normal user (not administrator), allow local scripts to
run, once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

If Windows still refuses to run the script, start it with
`powershell -ExecutionPolicy Bypass -File scripts\start.ps1` instead.
If Windows asks about `erl.exe` or `epmd.exe`, allow them on private
networks.

**macOS.** If the firewall is on (System Settings > Network >
Firewall), the first start asks whether `beam.smp` may accept incoming
connections: Allow.

**Raspberry Pi OS.** No firewall by default: nothing to do.

## 3. Start the node

Windows (PowerShell):

```powershell
.\scripts\start.ps1
```

macOS and Linux (also the Pi):

```sh
./scripts/start.sh
```

The script prints the node name, the IP and the interface it picked,
for example:

```text
node: pi-pe@172.20.10.4 (interface: wlan0)
```

then compiles and starts IEx with that name, the cookie `cpd2026` and
the fixed ports. It picks the Wi-Fi IPv4: on Windows it skips Hyper-V
(`vEthernet`) and VPN adapters; on macOS it takes the interface of the
default route; on Linux the `wl*` device (`DESIGN.md` DES11).

If it cannot decide, it lists what it found and stops. Then give the IP
yourself: `.\scripts\start.ps1 -Ip 172.20.10.3` or
`./scripts/start.sh --ip 172.20.10.4`. To see the IPv4: `ipconfig` on
Windows (line "IPv4 Address" of the Wi-Fi adapter),
`ipconfig getifaddr en0` on macOS, `hostname -I` on Linux. The
variable `CRDT_IP` does the same.

## 4. Check

Within a few seconds of starting the second node, on each node:

```elixir
Node.self()
Node.list()
Crdt.status()
```

`Node.list()` shows the other nodes. In `Crdt.status()`:

```text
discovery: listening on 45892
connected: crdt-pi1@172.20.10.4 (announced), co-mac@172.20.10.5 (announced)
```

`(announced)`: this node heard its announcement. `(other)`: another
node connected it (Erlang connects everyone each node already knows).
`(table)`: it is in this node's table (section 5).

Then MAN1: `Crdt.insert(0, "hola")` on one node, and `Crdt.text()`
returns `"hola"` on the others. The other cases are in
[MANUAL-TESTS.md](MANUAL-TESTS.md), "With network".

## 5. If the nodes do not find each other

1. Check the firewall (section 2) and that all are on the same Wi-Fi.
2. Check whether the network carries multicast. Halt the nodes, then
   run at the same time on two computers, each with its own IP:

   ```sh
   elixir scripts/multicast_check.exs <this computer's IPv4>
   ```

   For 30 seconds each one prints what arrives from the other:
   `received from 172.20.10.4: pi-pe|multicast|3`. If nothing arrives,
   discovery cannot work on this network (some lab and guest networks
   block it).
3. Use a node table on **one** computer: a text file with the node name
   of another computer, as its script printed it. Then start with
   `NODES_FILE`:

   Windows (PowerShell):

   ```powershell
   Set-Content $env:TEMP\nodes.txt "pi-pe@172.20.10.4"
   $env:NODES_FILE="$env:TEMP\nodes.txt"; .\scripts\start.ps1
   ```

   macOS and Linux:

   ```sh
   printf 'pi-pe@172.20.10.4\n' > /tmp/nodes.txt
   NODES_FILE=/tmp/nodes.txt ./scripts/start.sh
   ```

   One line is enough: when two nodes connect, Erlang connects the
   others they know. A node that another node lists takes part with no
   change on its side. `nodes.example.txt` shows the format.
4. Erlang connection test, without our code (two computers). First
   `ping <OTHER_IP>`; Windows blocks incoming ping by default, so a ping
   towards Windows may fail without being an error. Then, on both, an
   Erlang node with the same fixed ports as the script:

   Windows (PowerShell):

   ```powershell
   $env:ERL_AFLAGS="-kernel inet_dist_listen_min 4218 inet_dist_listen_max 4228"; iex.bat --name test@<MY_IP> --cookie cpd2026
   ```

   macOS and Linux:

   ```sh
   ERL_AFLAGS="-kernel inet_dist_listen_min 4218 inet_dist_listen_max 4228" iex --name test@<MY_IP> --cookie cpd2026
   ```

   On one of them, `Node.connect(:"test@<OTHER_IP>")` returns `true`
   and `Node.list()` shows the other. Leave both with `System.halt()`.

## 6. More

- Several nodes on one computer: `.\scripts\start.ps1 -Node 1`,
  `-Node 2` (`--node 1` with `start.sh`) gives `pc-1@IP`, `pc-2@IP`.
  Only one of them listens for announcements (`discovery: announce
  only` on the others); that is normal.
- Without discovery (for example, on a network where it must not be
  used): `DISCOVERY=off`, and a node table.
- A node off does not block the others. With one node halted, on
  another:

  ```elixir
  :timer.tc(fn -> Crdt.insert(0, "x") end)   # {micros, :ok}, micros well under 1_000_000
  ```

  Start the halted node again: it catches up (`DESIGN.md` DES7.1).
- A new network gives a new IP and so a new node name; the history file
  is named by the hostname only (`data/pi-pe.jsonl`), so the text comes
  back (`DESIGN.md` DES4.5).
- A remote console on a running node, from the same computer:
  `iex --name console@127.0.0.1 --cookie cpd2026 --hidden --remsh <node name>`.
  `--hidden` keeps the console out of the cluster.
- Clean up: halt the nodes and delete `data/<hostname>.jsonl` on each
  computer.
