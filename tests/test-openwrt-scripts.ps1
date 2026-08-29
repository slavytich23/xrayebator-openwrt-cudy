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
    'usr\libexec\xrayebator-safe\xray-supervisor'
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

Assert-Match $service 'run -test -c "\$CONFIG"' 'config is validated before start'
Assert-Match $service 'procd_set_param command "\$SUPERVISOR"' 'procd starts supervisor'
Assert-Match $activate 'COMMIT_REQUIRED=true' 'activation requires explicit commit'
Assert-Match $activate 'automatic rollback restored direct internet' 'activation has timed rollback'
Assert-Match $commit 'POLICY_INSTALLED=true' 'commit requires routing policy'
Assert-Match $commit 'TUN_ROUTE_ACTIVE=true' 'commit requires active TUN route'

Assert-Match $guard 'prohibit default' 'guard fails closed without TUN'
Assert-Match $guard 'iifname "\$LAN_DEVICE" oifname "\$WAN_DEVICE" reject' 'guard blocks direct LAN to WAN forwarding'
Assert-Match $guard 'XRAYEBATOR_DNS_CAPTURE_ADDRESS' 'DNS capture address is configurable'
Assert-Match $guard 'th dport 53 reject' 'router plaintext DNS is blocked on WAN'

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
