# Configuration on the computer (MIX_TARGET not set); the node itself only runs on the Pi (DES15).
import Config

# Nerves.Runtime on the computer reads this store instead of the Pi's U-Boot environment
config :nerves_runtime,
  kv_backend:
    {Nerves.Runtime.KVBackend.InMemory,
     contents: %{
       "nerves_fw_active" => "a",
       "a.nerves_fw_architecture" => "generic",
       "a.nerves_fw_description" => "N/A",
       "a.nerves_fw_platform" => "host",
       "a.nerves_fw_version" => "0.0.0"
     }}
