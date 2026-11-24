#!/bin/sh
# Starts a node named <hostname>@<Wi-Fi IPv4> (docs/DESIGN.md, sections 6 and 11).
# Usage: ./scripts/start.sh [--ip <IPv4>] [--name <name>] [--node <n>]
#   --ip    the IPv4 to use (or CRDT_IP); without it, the Wi-Fi one
#   --name  the name before "@" (or CRDT_NAME); without it, the hostname
#   --node  a suffix for several nodes on one machine: pi-pe-1, pi-pe-2, ...
# NODES_FILE (optional node table) and DISCOVERY=off reach the node as they are.

ip="${CRDT_IP:-}"
name="${CRDT_NAME:-}"
node=""
interface="given"

while [ $# -gt 0 ]; do
  case "$1" in
    --ip) ip="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --node) node="$2"; shift 2 ;;
    *) echo "Unknown option: $1"
       echo "Usage: ./scripts/start.sh [--ip <IPv4>] [--name <name>] [--node <n>]"
       exit 1 ;;
  esac
done

stop_choosing() {
  echo "Cannot pick the network interface. $1"
  echo "Run again with the IP, for example: ./scripts/start.sh --ip <IPv4>"
  exit 1
}

count_lines() { printf '%s\n' "$1" | grep -c .; }

# macOS: the interface of the default route, unless it is a VPN tunnel
pick_macos() {
  interface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
  [ -n "$interface" ] || stop_choosing "No default route: connect to the Wi-Fi."
  case "$interface" in
    utun*|ppp*|ipsec*) stop_choosing "The default route goes through a VPN ($interface)." ;;
  esac
  ip=$(ipconfig getifaddr "$interface")
  [ -n "$ip" ] || stop_choosing "No IPv4 on $interface."
}

# Linux and Pi: the Wi-Fi device (wl*) of the default routes, or else the only one
pick_linux() {
  devices=$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1)}' | sort -u)
  [ -n "$devices" ] || stop_choosing "No default route: connect to the Wi-Fi."
  wifi=$(printf '%s\n' "$devices" | grep '^wl')
  if [ "$(count_lines "$wifi")" = 1 ]; then
    interface=$wifi
  elif [ -z "$wifi" ] && [ "$(count_lines "$devices")" = 1 ]; then
    interface=$devices
  else
    stop_choosing "Found: $(echo $devices)."
  fi
  ip=$(ip -4 -o addr show dev "$interface" scope global | awk '{print $4}' | cut -d/ -f1 | head -n 1)
  [ -n "$ip" ] || stop_choosing "No IPv4 on $interface."
}

if [ -z "$name" ]; then
  name=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
fi
# lowercase; anything other than a-z, 0-9, _ and - becomes _
name=$(printf '%s' "$name" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9_-]/_/g')
[ -n "$name" ] || name=crdt
[ -z "$node" ] || name="$name-$node"

if [ -z "$ip" ]; then
  if [ "$(uname)" = Darwin ]; then pick_macos; else pick_linux; fi
fi

if ! printf '%s' "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
  echo "Not an IPv4 address: $ip"
  exit 1
fi

echo "node: $name@$ip (interface: $interface)"

# Fixed distribution ports, so the firewall needs fixed rules (DES6)
# REQ22, DES6: a dropped link must not cut the other links (partitions flag off)
export ERL_AFLAGS="-kernel inet_dist_listen_min 4218 inet_dist_listen_max 4228 prevent_overlapping_partitions false"
cd "$(dirname "$0")/.." || exit 1
mix compile || exit 1
exec iex --name "$name@$ip" --cookie cpd2026 -S mix
