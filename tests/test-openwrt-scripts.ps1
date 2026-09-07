[CmdletBinding()]
param([switch]$Integration)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$filesRoot = Join-Path $root 'openwrt\files'

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "assertion failed: $Name" }
}

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Name)
    Assert-True ($Text -match $Pattern) $Name
}

$shellFiles = @(
    'etc\init.d\xrayebator-safe',
    'usr\bin\xrayebator-safe-activate',
    'usr\bin\xrayebator-safe-commit',
    'usr\bin\xrayebator-safe-rollback',
    'usr\libexec\xrayebator-safe\route-guard',
    'usr\libexec\xrayebator-safe\xray-supervisor',
    '..\tools\configure-dual-network.sh',
    '..\tools\finalize-dual-network.sh',
    '..\tools\rollback-dual-network.sh',
    '..\tools\verify-dual-network.sh'
)

foreach ($relativePath in $shellFiles) {
    $path = Join-Path $filesRoot $relativePath
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "$relativePath exists"
}

$service = Get-Content -LiteralPath (Join-Path $filesRoot 'etc\init.d\xrayebator-safe') -Raw
$activate = Get-Content -LiteralPath (Join-Path $filesRoot 'usr\bin\xrayebator-safe-activate') -Raw
$commit = Get-Content -LiteralPath (Join-Path $filesRoot 'usr\bin\xrayebator-safe-commit') -Raw
$guard = Get-Content -LiteralPath (Join-Path $filesRoot 'usr\libexec\xrayebator-safe\route-guard') -Raw
$supervisor = Get-Content -LiteralPath (Join-Path $filesRoot 'usr\libexec\xrayebator-safe\xray-supervisor') -Raw
$settings = Get-Content -LiteralPath (Join-Path $filesRoot 'etc\config\xrayebator_safe') -Raw
$configureDual = Get-Content -LiteralPath (Join-Path $root 'openwrt\tools\configure-dual-network.sh') -Raw
$finalizeDual = Get-Content -LiteralPath (Join-Path $root 'openwrt\tools\finalize-dual-network.sh') -Raw
$rollbackDual = Get-Content -LiteralPath (Join-Path $root 'openwrt\tools\rollback-dual-network.sh') -Raw
$verifyDual = Get-Content -LiteralPath (Join-Path $root 'openwrt\tools\verify-dual-network.sh') -Raw

Assert-Match $service 'run -test -c "\$CONFIG"' 'config is validated before start'
Assert-Match $service 'procd_set_param command "\$SUPERVISOR"' 'procd starts supervisor'
Assert-Match $activate 'COMMIT_REQUIRED=true' 'activation requires explicit commit'
Assert-Match $activate 'automatic rollback restored direct internet' 'activation has timed rollback'
Assert-Match $activate 'setsid sh -c' 'activation uses BusyBox setsid for detached rollback'
Assert-True ($activate -notmatch '\bnohup\b') 'activation does not require optional nohup'
Assert-Match $commit 'POLICY_INSTALLED=true' 'commit requires routing policy'
Assert-Match $commit 'TUN_ROUTE_ACTIVE=true' 'commit requires active TUN route'

Assert-Match $guard 'prohibit default' 'guard fails closed without TUN'
Assert-Match $guard 'iifname "\$LAN_DEVICE" oifname "\$WAN_DEVICE" reject' 'guard blocks direct LAN to WAN forwarding'
Assert-Match $guard 'XRAYEBATOR_DNS_CAPTURE_ADDRESS' 'DNS capture address is configurable'
Assert-Match $guard 'XRAYEBATOR_LAN_NETWORK' 'client network is configurable'
Assert-True ($guard -notmatch 'chain output_guard') 'guard does not block DNS for unrelated direct networks'

Assert-Match $service 'config_load xrayebator_safe' 'service loads persistent OpenWrt settings'
Assert-Match $service 'XRAYEBATOR_LAN_NETWORK=\$CLIENT_NETWORK' 'service scopes guard to configured client network'
Assert-Match $settings "option client_network 'lan'" 'default settings preserve single-LAN compatibility'

Assert-Match $configureDual 'APPLY_CHANGES' 'dual-network setup requires an explicit apply flag'
Assert-Match $configureDual 'XRAYEBATOR_SAFE_MUST_BE_STOPPED=true' 'dual-network setup refuses to rewire a running Xray service'
Assert-Match $configureDual 'pre-dual-network-' 'dual-network setup creates a timestamped backup'
Assert-Match $configureDual 'AUTOMATIC_ROLLBACK_APPLIED=true' 'dual-network setup restores its backup after an apply failure'
Assert-Match $configureDual 'del_list.*ports=' 'dual-network setup moves only the selected LAN port'
Assert-Match $configureDual 'wireless\.\$direct_section\.ssid=\$DIRECT_SSID' 'both direct radios share one SSID'
Assert-Match $configureDual 'wireless\.\$vpn_section\.ssid=\$VPN_SSID' 'both VPN radios share one SSID'
Assert-Match $finalizeDual 'LEGACY_SECTIONS=.*default_radio0 default_radio1' 'finalizer targets both default legacy SSIDs'
Assert-Match $finalizeDual 'wireless\.\$section\.disabled=1' 'finalizer disables only selected legacy sections'
Assert-Match $finalizeDual 'AUTOMATIC_ROLLBACK_APPLIED=true' 'finalizer restores wireless after an apply failure'
Assert-Match $rollbackDual 'for name in network wireless dhcp firewall xrayebator_safe' 'rollback covers every changed UCI package'
Assert-Match $rollbackDual 'cp "\$BACKUP_DIR/\$name" "/etc/config/\$name"' 'rollback restores configuration files'
Assert-Match $rollbackDual 'readlink -f' 'rollback rejects redirected backup paths'
Assert-Match $verifyDual 'ip netns exec' 'verification uses an isolated tunnel client'
Assert-True ($configureDual -notmatch '(?i)(?:password|passwd|token|secret)\s*[=:]\s*["''][^"''\r\n]{8,}["'']') 'dual-network tool contains no embedded credential'

Assert-Match $supervisor 'GOMEMLIMIT=' 'Go memory limit is set'
Assert-Match $supervisor 'VmRSS:' 'Xray RSS is monitored'
Assert-Match $supervisor 'MemAvailable:' 'router memory is monitored'
Assert-Match $supervisor 'probe_direct_wan_health' 'WAN is checked before Xray restart'
Assert-Match $supervisor 'upstream connectivity unavailable; deferring xray restart' 'WAN outage defers Xray restart'
Assert-Match $supervisor 'HEALTH_RESTART_COOLDOWN' 'health restart cooldown exists'
Assert-Match $supervisor 'post-upstream recovery retry' 'one recovery retry exists'
Assert-Match $supervisor '--resolve "\$HEALTH_FIXED_RESOLVE"' 'fixed HTTPS probe preserves certificate validation'
Assert-True ($supervisor -notmatch '(?m)(?:^|\s)-k(?:\s|$)') 'health probes do not disable TLS verification'

$privateConfig = Join-Path $filesRoot 'etc\xrayebator-safe\client.json'
Assert-True (-not (Test-Path -LiteralPath $privateConfig)) 'repository does not contain a live client.json'

if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    foreach ($relativePath in $shellFiles) {
        $path = Join-Path $filesRoot $relativePath
        $wslPath = (& wsl.exe wslpath -a ($path -replace '\\', '/') 2>$null).Trim()
        if ($LASTEXITCODE -eq 0 -and $wslPath) {
            & wsl.exe sh -n $wslPath
            Assert-True ($LASTEXITCODE -eq 0) "$relativePath shell syntax"
        }
    }
}

if ($Integration) {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'integration test requested but WSL is unavailable'
    }
    $integrationPath = Join-Path $root 'tests\test-route-guard.sh'
    $wslIntegrationPath = (& wsl.exe wslpath -a ($integrationPath -replace '\\', '/') 2>$null).Trim()
    Assert-True ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($wslIntegrationPath)) 'route-guard integration path'
    & wsl.exe -u root bash $wslIntegrationPath
    Assert-True ($LASTEXITCODE -eq 0) 'route-guard namespace integration'
}

'OPENWRT_SCRIPT_TESTS=true'
