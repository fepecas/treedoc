# A Raspberry Pi 4 with Nerves

The Pi runs our node as Nerves firmware instead of Raspberry Pi OS:
there is no shell to set up and no start script. When the Wi-Fi has an
IPv4, the node starts by itself, names itself `nerves-XXXX@<IP>`, finds
the other nodes and keeps its history in `/data` (REQ21,
[DESIGN.md, section 15](../docs/DESIGN.md#15-raspberry-pi-with-nerves)).

Two paths:

- [Path A: ready image](#path-a-ready-image): burn the author's image.
  Nothing to install.
- [Path B: build your own](#path-b-build-your-own): your Wi-Fi, your SSH
  keys. Needs Elixir and the Nerves tools.

The first boot, troubleshooting and updates are the same for both.

## Path A: ready image

### What you get

A Pi that boots into a working node, ready to edit with a computer on
the same network.

### What you need

- A Raspberry Pi 4 Model B and a microSD card. Burning erases the card.
- A phone hotspot or router with exactly this SSID and password, on
  2.4 GHz (on an iPhone, turn on "Maximize Compatibility"):
  - SSID: `cpd2026`
  - Password: `1234567890`
- A computer on that network running our node
  ([NETWORK.md](../docs/NETWORK.md#3-start-the-node)).

### What is inside

- Wi-Fi: only the network above. To use another one, build your own
  image (Path B), or see [Another Wi-Fi network](#another-wi-fi-network).
- Cookie `cpd2026`, distribution ports 4218 to 4228, discovery on, no
  node table: the same as every other node.
- Node name `nerves-XXXX@<IP>`. `nerves-XXXX` is different on each Pi.
- SSH accepts only the author's key. You can use the node from your
  computer, but you cannot open a console on the Pi; for that, build
  your own image.

### What was tested

On a Raspberry Pi 4 Model B with this image, an iPhone hotspot with
"Maximize Compatibility" and a Mac (Elixir 1.20.5, Erlang/OTP 29),
November 2026, with no monitor (MAN14):

- The Pi and the Mac find each other with no node table, and edits on
  each appear on the other (MAN1).
- Pi off, edit on the Mac, Pi on: it reconnects and catches up (MAN4).
- Only the Pi on: it recovers its text from `/data`; an edit made there
  reaches the Mac when it starts, as "applied" (MAN5).
- 20 minutes after boot the Pi has not rebooted (the startup guard of
  DES15), and `Nerves.Runtime.poweroff()` turns it off cleanly.

Pending: another Wi-Fi network (MAN15).

### Get the image and check it

The image is not in any repository: it holds the Wi-Fi password and the
author's SSH key. Ask for it in an issue of this repository on GitHub,
or through the author's GitHub profile. It is shared through a Google
Drive link with restricted access.

- Built on `November 21, 2026` from the code of this repository; `lib/` and
  `firmware/` have not changed since.
- SHA-256: `ec65313755407288c27c1db340657099ceefea7a7dd961726eb669002163e7fa`

Check the file before burning it; the output must be that hash:

```sh
shasum -a 256 crdt_fw.img        # macOS
sha256sum crdt_fw.img            # Linux
```

```powershell
Get-FileHash -Algorithm SHA256 crdt_fw.img   # Windows
```

Every build gives a new hash, even from the same commit. A hash that
does not match is not this image.

### Burn the card

1. Open Raspberry Pi Imager. Device: Raspberry Pi 4. Operating system:
   "Use custom", then `crdt_fw.img`.
2. Storage: the microSD card. Check its size: the card is erased.
3. OS customisation: No (or greyed out). The settings come from the
   firmware.
4. Write, then put the card in the Pi and power it on.

## First boot

No monitor needed.

1. Wait about 3 minutes, with the computer on the same network.
2. Start the node on the computer
   ([NETWORK.md](../docs/NETWORK.md#3-start-the-node)). Within a few
   seconds it prints `connected nerves-XXXX@<IP>: resending history`.
   That is the Pi.
3. Edit on the computer; the Pi applies it. With SSH (your own image),
   `Crdt.text()` on the Pi shows the same text.

To find the Pi on the network without starting the node:

```sh
dns-sd -B _ssh._tcp local.       # macOS: lists nerves-XXXX; it never exits, Ctrl-C
avahi-browse -rt _ssh._tcp       # Linux, untested
ping nerves-XXXX.local           # Windows, untested; once you know the name
```

With your own image, open a console on the Pi:

```sh
ssh nerves-XXXX.local
```

Use the name of the Pi, never `nerves.local`, which every Nerves device
answers. If `.local` does not resolve, use `ssh <IP>`. The first time,
ssh asks to confirm the host key. The console is IEx:

```elixir
Crdt.status()      # node, history file /data/crdt/nerves-XXXX.jsonl, discovery, connected
Crdt.text()
```

`Crdt.status()`, `Crdt.history()` and `Crdt.debug()` print in the SSH
session; the replica's notices only on an HDMI screen. Type `exit` to
leave.

### Turn the Pi off

With SSH, in IEx on the Pi (tested):

```elixir
Nerves.Runtime.poweroff()
```

The SSH session drops; that is expected. Wait until the green LED stops
blinking (about 10 s), then unplug the power. The computer's node
prints `disconnected nerves-XXXX@<IP>`. Pulling the power without this
works in practice (the history is on disk after every edit), but
`poweroff` is the clean way. Without SSH (Path A), unplug it.

### If the computer does not see the Pi

From the most likely cause to the least:

1. Network. The SSID and password must match exactly, on 2.4 GHz. If
   `dns-sd` does not list the Pi after 5 minutes, the Pi is not on the
   network.
2. The node on the Pi (only with SSH). In the console,
   `:sys.get_state(CrdtFw)` returns `:started` (running), `:waiting`
   (no IPv4 on `wlan0` yet) or `:failed` (a step failed; the reason is
   on the HDMI screen).
3. Multicast. If the Pi is on the network and its node is `:started`,
   but the computer prints no `connected`, the network blocks
   multicast: put `nerves-XXXX@<IP>` in the computer's node table
   ([NETWORK.md](../docs/NETWORK.md#5-if-the-nodes-do-not-find-each-other)).
   One side is enough.
4. Last resort: an HDMI screen and a USB keyboard. The screen shows
   `waiting for an IPv4 on wlan0`, then `node: nerves-XXXX@<IP>
   (interface: wlan0)`, or `node not started: step ... failed (...)`.

## Another Wi-Fi network

On the Pi's console (HDMI and keyboard, or SSH while the Pi is still on
a known network):

```elixir
VintageNetWiFi.quick_configure("<SSID>", "<password>")
```

The Pi keeps that network across restarts. Then restart it (power it
off and on, or `Nerves.Runtime.reboot()`): the node name has the IP,
fixed when the node starts. It comes back with its new name and the
same text. That call may replace the networks of the image; to go back:

```elixir
VintageNet.reset_to_defaults("wlan0")
```

and restart the Pi. Over SSH, a wrong password leaves the Pi on no
network you can reach; then only an HDMI screen or burning the card
again helps. Not tested yet (MAN15).

## Update without burning

Burning the card again erases `/data`, the Pi's history: it is the same
as deleting the history of one node, so do not edit on it until its
text matches the others. To update the firmware and keep `/data`, with
your own build (Path B) and your key in the Pi:

```sh
cd firmware
mix firmware
mix upload nerves-XXXX.local
```

The Pi installs the new firmware and restarts.

## Path B: build your own

Tested on macOS. Linux and Windows (only through WSL2; Nerves does not
build on Windows itself) are untested.

### Tools (once)

The firmware uses `nerves_system_rpi4` 2.2, with Erlang/OTP 29.1.2. The
computer needs Erlang/OTP 29 (29.1.2 if possible) and Elixir 1.20 built
for OTP 29.

```sh
brew install fwup squashfs coreutils xz pkg-config     # macOS
mix local.hex --force
mix local.rebar --force
mix archive.install hex nerves_bootstrap --force
erl -noshell -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().'
elixir --version
```

`erl` prints `29`; `elixir --version` says `compiled with Erlang/OTP 29`.

### Wi-Fi and SSH keys

Read from environment variables when the firmware is built, never from
a file of the repository. They end up inside the firmware and the
image, so share those files only with people who may use those
networks.

- `CRDT_HOTSPOT_SSID`, `CRDT_HOTSPOT_PSK`: the network the Pi tries
  first. Required.
- `CRDT_LAB_SSID`, `CRDT_LAB_PSK`: a second network. Optional: both or
  neither; with only one of them, the second network is left out with
  no message.
- `CRDT_SSH_KEYS`: the path of a file outside the repository with the
  public keys allowed on the Pi, one OpenSSH key per line (for example
  `ssh-ed25519 AAAA... you@laptop`). Blank lines are skipped. Never a
  private key. Required.

In the terminal you build in (bash or zsh). Each Wi-Fi value is typed
when asked and not shown; never write it after `export ...=`, which
leaves it in the shell history.

```sh
ls ~/.ssh/*.pub                                  # if there is none: ssh-keygen -t ed25519
cat ~/.ssh/id_ed25519.pub > ~/crdt-ssh-keys.txt
# add other public keys as more lines of ~/crdt-ssh-keys.txt
export CRDT_SSH_KEYS=~/crdt-ssh-keys.txt
export MIX_TARGET=rpi4
```

Paste each `read` line below on its own and answer it before the next:
pasted together, the next line becomes the value.

```sh
printf 'Hotspot SSID: ' && read -rs CRDT_HOTSPOT_SSID && echo && export CRDT_HOTSPOT_SSID
```

```sh
printf 'Hotspot password: ' && read -rs CRDT_HOTSPOT_PSK && echo && export CRDT_HOTSPOT_PSK
```

Optional second network, both or neither, also one at a time:

```sh
printf 'Lab SSID: ' && read -rs CRDT_LAB_SSID && echo && export CRDT_LAB_SSID
```

```sh
printf 'Lab password: ' && read -rs CRDT_LAB_PSK && echo && export CRDT_LAB_PSK
```

Set them before `mix deps.get`: with `MIX_TARGET=rpi4`, Mix reads
`firmware/config/target.exs` for every task, and stops with a message
if the hotspot variables or the key file are missing. If `mix deps.get`
prints `MIX_TARGET: host`, the export was skipped.

### Build

From the project folder, in the same terminal:

```sh
mix test
cd firmware
mix deps.get
mix firmware
mix firmware.image crdt_fw.img
```

`mix test` runs at the root, as on any computer. The first
`mix deps.get` downloads the prebuilt system and toolchain (about
380 MB) into `~/.nerves`. If the download stalls, stop it with Ctrl-C,
delete the partial `.tmp` file in `~/.nerves/dl/` and run the command
again. `mix firmware` builds the `.fw` file under `firmware/_build/`;
`mix firmware.image` builds it again and writes `crdt_fw.img`. Git
ignores both.

To check that the Wi-Fi values are in the firmware, without printing
them (bash or zsh):

```sh
F=_build/rpi4_dev/rel/crdt_fw/releases/0.1.0/sys.config
[ -n "$CRDT_HOTSPOT_SSID" ] && grep -qF -- "$CRDT_HOTSPOT_SSID" "$F" && echo SSID-OK
[ -n "$CRDT_HOTSPOT_PSK" ] && grep -qF -- "$CRDT_HOTSPOT_PSK" "$F" && echo PSK-OK
```

A value with `"` or `\` is escaped in that file, so this check misses
it. Then burn `crdt_fw.img` as in [Burn the card](#burn-the-card) and
follow [First boot](#first-boot).
