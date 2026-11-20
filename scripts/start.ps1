# Starts a node named <hostname>@<Wi-Fi IPv4> (docs/DESIGN.md, sections 6 and 11).
# Usage: .\scripts\start.ps1 [-Ip <IPv4>] [-Name <name>] [-Node <n>]
#   -Ip    the IPv4 to use (or $env:CRDT_IP); without it, the Wi-Fi one
#   -Name  the name before "@" (or $env:CRDT_NAME); without it, the hostname
#   -Node  a suffix for several nodes on one machine: pc-1, pc-2, ...
# NODES_FILE (optional node table) and DISCOVERY=off reach the node as they are.
param(
    [string]$Ip = $env:CRDT_IP,
    [string]$Name = $env:CRDT_NAME,
    [string]$Node = ""
)

function Get-SafeName([string]$text) {
    # lowercase; anything other than a-z, 0-9, _ and - becomes _
    $safe = $text.ToLower() -replace '[^a-z0-9_-]', '_'
    if ($safe -eq "") { "crdt" } else { $safe }
}

function Stop-Choosing([string]$found) {
    Write-Host "Cannot pick the network adapter. $found"
    Write-Host "Run again with the IP, for example: .\scripts\start.ps1 -Ip <IPv4>"
    exit 1
}

function Get-WifiAddress {
    # default IPv4 routes on physical adapters that are up: skips Hyper-V vEthernet and VPNs
    $physical = @(Get-NetAdapter -Physical | Where-Object Status -eq "Up")
    $routes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Where-Object { $physical.ifIndex -contains $_.ifIndex })
    $found = @(foreach ($index in ($routes.ifIndex | Sort-Object -Unique)) {
        $adapter = $physical | Where-Object ifIndex -eq $index
        $address = Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1
        if ($address) {
            [pscustomobject]@{ Ip = $address.IPAddress; Alias = $adapter.Name; WiFi = $adapter.PhysicalMediaType -like "*802.11*" }
        }
    })
    $wifi = @($found | Where-Object WiFi)
    if ($wifi.Count -eq 1) { return $wifi[0] }
    if ($wifi.Count -eq 0 -and $found.Count -eq 1) { return $found[0] }
    if ($found.Count -eq 0) { Stop-Choosing "No physical adapter with a default gateway: connect to the Wi-Fi." }
    Stop-Choosing ("Found: " + (($found | ForEach-Object { "$($_.Alias) $($_.Ip)" }) -join ", ") + ".")
}

if (-not $Name) { $Name = $env:COMPUTERNAME }
$Name = Get-SafeName $Name
if ($Node) { $Name = "$Name-$Node" }

if ($Ip) {
    $interface = "given"
} else {
    $picked = Get-WifiAddress
    $Ip = $picked.Ip
    $interface = $picked.Alias
}

if ($Ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
    Write-Host "Not an IPv4 address: $Ip"
    exit 1
}

Write-Host "node: $Name@$Ip (interface: $interface)"

# Fixed distribution ports, so the firewall needs fixed rules (DES6)
$oldFlags = $env:ERL_AFLAGS
$env:ERL_AFLAGS = "-kernel inet_dist_listen_min 4218 inet_dist_listen_max 4228"
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    mix compile
    if ($LASTEXITCODE -eq 0) {
        iex.bat --name "$Name@$Ip" --cookie cpd2026 -S mix
    }
} finally {
    Pop-Location
    $env:ERL_AFLAGS = $oldFlags
}
