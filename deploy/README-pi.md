# Running the editor on Raspberry Pi

Step by step guide for two (or more) Raspberry Pis with Raspberry Pi OS,
checked on a real Pi. Design: `DESIGN.md` DES13.

Names used below: `crdt-pi1` and `crdt-pi2` (hostnames), user `pi`,
cookie `cpd2026`. Change `pi` for the user you choose. Each node is
named `<hostname>@<IP>` by the start script, for example
`crdt-pi1@172.20.10.4`; the IP depends on the network.

## 1. Flash the microSD card

1. On a computer, install and open Raspberry Pi Imager.
2. Device: your Raspberry Pi model. OS: Raspberry Pi OS (64-bit), Lite
   or with desktop. Storage: the microSD card.
3. When it asks about OS customisation, choose "Edit settings":
   - Hostname: `crdt-pi1` (the second card: `crdt-pi2`). Every Pi needs
     its own hostname: two Pis left as `raspberrypi` would get the same
     node name part and collide.
   - Username and password: for example `pi` and a password of your
     choice.
   - Wireless LAN: the network name and password of the network for the
     test, and your country.
   - Services: enable SSH with password authentication.
4. Write the card, put it in the Pi and power it on. The first boot
   takes a minute or two.

To rename a Pi that is already installed:
`sudo hostnamectl set-hostname crdt-pi2`, then `sudo reboot`.

## 2. Log in and install Elixir

From the computer, on the same network:

```powershell
ssh pi@crdt-pi1.local
```

If `crdt-pi1.local` does not resolve, find the Pi's IP address in the
router (or the phone hotspot) and use `ssh pi@<IP>`. The `.local` name
is only for SSH: node names always use the IP.

On the Pi:

```sh
cat /etc/os-release        # VERSION_CODENAME=trixie (Debian 13)
sudo apt update
sudo apt install -y elixir git
elixir --version           # Elixir 1.18.3 (compiled with Erlang/OTP 27)
```

The code is written for Elixir 1.18.3 and Erlang/OTP 27 (CON1). If the
Pi shows another Debian version or another Elixir version, the code
has not been tested there.

## 3. Get the code

On the Pi:

```sh
git clone <repository URL> ~/crdt
cd ~/crdt
mix compile
mix test
```

`mix test` must end with `0 failures` (the distributed tests are
excluded by default). The message `Node has no name: Crdt.Replica not
started` at the top is expected: tests run without `--name`.

Without network access to the repository, copy the versioned files
from the computer instead, with no `_build/`: what was compiled on
Windows does not work on the Pi. For example, from a clone:
`git archive --format=tar -o crdt.tar HEAD`, then
`scp crdt.tar pi@crdt-pi1.local:` and, on the Pi,
`mkdir ~/crdt && tar -xf crdt.tar -C ~/crdt`.

## 4. No node table

The nodes find each other on the local network by themselves
(`DESIGN.md` DES6.1): there is no table to edit. Raspberry Pi OS has no
firewall by default, so nothing else is needed.

If the network blocks multicast (section 5 tells), use a node table on
one Pi: [NETWORK.md](../docs/NETWORK.md), section 5.

## 5. Connection test (before our code)

Agreed with the other teams. Run it on `crdt-pi1`, with `crdt-pi2`
powered on. Below, `<PI1_IP>` and `<PI2_IP>` are the IPs that
`hostname -I` shows on each Pi (the first address).

1. Network:

   ```sh
   ping -c 3 <PI2_IP>
   ```

2. Erlang distribution. On `crdt-pi2`, start a plain node and leave it
   open:

   ```sh
   iex --name test@<PI2_IP> --cookie cpd2026
   ```

   On `crdt-pi1`:

   ```sh
   iex --name test@<PI1_IP> --cookie cpd2026
   ```

   ```elixir
   Node.connect(:"test@<PI2_IP>")   # true
   Node.list()                      # [:"test@<PI2_IP>"]
   ```

   Leave both with `System.halt()`.
3. Discovery. Run at the same time on both Pis:

   ```sh
   elixir scripts/multicast_check.exs <this Pi's IP>
   ```

   Each prints `received from <other IP>: ...` lines. If nothing
   arrives, the network blocks multicast: use a node table (section 4).

If step 1 fails, it is the network. If step 2 returns `false`, check
that both use the same cookie and are on the same network.

### A Pi with Nerves

A Raspberry Pi 4 can also run our node with Nerves firmware instead of
Raspberry Pi OS (`DESIGN.md` DES15); its guide is
`deploy/README-nerves.md`. Its node name is `nerves-XXXX@<IP>`,
where `nerves-XXXX` is the Pi's Nerves hostname. The three-step test is
the same: that name goes in `Node.connect/1` in step 2, with the cookie
`cpd2026`. A Nerves Pi of another team also does only steps 1 and 2,
with its own node name.

## 6. Run the node in the foreground (demo)

For the demo each Pi runs its node in the foreground in an SSH session,
so the commands and the notices are visible (`DESIGN.md` DES13).

If a systemd service runs the node, stop it first,
because two nodes cannot have the same name:

```sh
sudo systemctl stop crdt
```

Then, on each Pi, in `~/crdt`:

```sh
./scripts/start.sh
```

It prints the node name it picked, for example
`node: crdt-pi1@172.20.10.4 (interface: wlan0)`, and `history loaded:
N ops`. Within a few seconds of starting the other Pi:
`connected crdt-pi2@172.20.10.5: resending history (N ops)`. Check with
`Node.list()` and `Crdt.status()` (`connected:` lists the other Pi).

If the script cannot pick the interface, give the IP:
`./scripts/start.sh --ip <this Pi's IP>`.

## 7. MAN1 between Pis

On `crdt-pi1`:

```elixir
Crdt.insert(0, "hola")    # :ok
```

On `crdt-pi2`, `Crdt.text()` returns `"hola"` and the console shows
`applied op 1 from crdt-pi1@<PI1_IP>: ins "h"` up to `op 4`.

The other manual tests (MAN2 to MAN5, MAN7, MAN8) are in
[MANUAL-TESTS.md](../docs/MANUAL-TESTS.md); MAN6 repeats them between
Pis.

## 8. `Crdt.insert` answers at once with the other Pi off

1. On `crdt-pi2`: `System.halt()` (or unplug it).
2. On `crdt-pi1`:

   ```elixir
   :timer.tc(fn -> Crdt.insert(0, "x") end)   # {micros, :ok}, micros well under 1_000_000
   ```

`Node.connect/1` runs in a separate process, so the replica is never
blocked (`DESIGN.md` DES7.1). Start `crdt-pi2` again: it is found by
discovery and catches up.

## 9. Usage rules on the Pis

The same rules as on a computer, with the paths of the Pis:

- The history is in `~/crdt/data/<hostname>.jsonl`, for example
  `data/crdt-pi1.jsonl`. It does not depend on the IP: on a new network
  the node gets a new name, finds the same file and its text is back.
- To start from scratch: halt the node on every Pi and run, on every
  Pi, `rm ~/crdt/data/*.jsonl` (keep `data/.gitkeep`).
- If you delete the history of only one Pi, do not edit on it until its
  `Crdt.text()` matches the other Pi.
- If the replica does not start, every `Crdt` function returns
  `{:error, :no_replica}`; read the message at the top of the console.
  With `history corrupted at line N of data/...`: halt the node, delete
  that file, start again and do not edit until the texts match.
- After a power cut, `history: last line was incomplete; removed from
  file` is normal: the node starts.
- On reconnection hundreds of `duplicate dropped` notices may appear.
  It is not an error.

## 10. Test network

To be confirmed (`DESIGN.md` DES13). In order:

- A university network lab, if it allows it. Lab networks may block
  multicast: then a node table (section 4).
  - Bring an Ethernet cable for each Pi if possible.
  - If not, add the lab's Wi-Fi to each Pi by SSH (from a network where
    you can still reach the Pi):

    ```sh
    sudo nmcli device wifi connect "<network>" password "<password>"
    nmcli connection show          # the new network is listed
    ```

- If not, an iPhone hotspot ("Allow others to join" on, and "Maximize
  Compatibility" on so the Pis see a 2.4 GHz network). Multicast works
  there (checked with a Pi and a Windows computer).
- If not, our own router.

On every network, run the connection test (section 5) before MAN1.
