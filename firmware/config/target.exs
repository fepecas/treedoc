# Configuration on the Pi (MIX_TARGET=rpi4). DES15: Wi-Fi and SSH keys are read from
# environment variables when the firmware is built, never written in Git.
import Config

# Start nerves_runtime and nerves_pack first (shoehorn)
config :shoehorn, init: [:nerves_runtime, :nerves_pack]

# Validate new firmware once every application has started (nerves_runtime)
config :nerves_runtime, startup_guard_enabled: true

# Advance the system clock on devices without a real-time clock
config :nerves, :erlinit, update_clock: true

# A value from the environment, or nil if it is not set or empty
env = fn name ->
  value = System.get_env(name)
  if value in [nil, ""], do: nil, else: value
end

# DES15: the phone hotspot, required, with the higher priority
hotspot_ssid = env.("CRDT_HOTSPOT_SSID")
hotspot_psk = env.("CRDT_HOTSPOT_PSK")

if hotspot_ssid == nil or hotspot_psk == nil do
  Mix.raise("""
  Set CRDT_HOTSPOT_SSID and CRDT_HOTSPOT_PSK (the phone hotspot) before building
  the firmware. See deploy/README-pi.md, section "A Pi 4 with Nerves".
  """)
end

hotspot = %{key_mgmt: :wpa_psk, ssid: hotspot_ssid, psk: hotspot_psk, priority: 2}

# DES15: the lab network, optional
lab =
  case {env.("CRDT_LAB_SSID"), env.("CRDT_LAB_PSK")} do
    {nil, _} -> []
    {_, nil} -> []
    {ssid, psk} -> [%{key_mgmt: :wpa_psk, ssid: ssid, psk: psk, priority: 1}]
  end

# DES15: the public SSH keys, one per line, from the file named by CRDT_SSH_KEYS
keys =
  case env.("CRDT_SSH_KEYS") && File.read(env.("CRDT_SSH_KEYS")) do
    {:ok, text} ->
      for line <- String.split(text, "\n"), key = String.trim(line), key != "", do: key

    _ ->
      []
  end

if keys == [] do
  Mix.raise("""
  Set CRDT_SSH_KEYS to a file with the public SSH keys, one per line, before
  building the firmware. See deploy/README-pi.md, section "A Pi 4 with Nerves".
  """)
end

config :nerves_ssh, authorized_keys: keys

config :vintage_net,
  regulatory_domain: "00",
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}},
    {"wlan0",
     %{
       type: VintageNetWiFi,
       vintage_net_wifi: %{networks: [hotspot | lab]},
       ipv4: %{method: :dhcp}
     }}
  ]

# DES15: only nerves-XXXX.local, never nerves.local (shared by every Nerves device)
config :mdns_lite,
  hosts: [:hostname],
  ttl: 120,
  services: [
    %{protocol: "ssh", transport: "tcp", port: 22},
    %{protocol: "sftp-ssh", transport: "tcp", port: 22},
    %{protocol: "epmd", transport: "tcp", port: 4369}
  ]

# DES15: the node table, empty by default: discovery finds the nodes (DES6)
config :crdt_fw, nodes: []
