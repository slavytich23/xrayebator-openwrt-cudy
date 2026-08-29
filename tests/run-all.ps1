[CmdletBinding()]
param([switch]$Integration)

$ErrorActionPreference = 'Stop'
$tests = @(
    'test-openwrt-scripts.ps1',
    'test-windows-failover-monitor.ps1',
    'test-secret-hygiene.ps1'
)

foreach ($test in $tests) {
    if ($test -eq 'test-openwrt-scripts.ps1') {
        & (Join-Path $PSScriptRoot $test) -Integration:$Integration
    } else {
        & (Join-Path $PSScriptRoot $test)
    }
}

'ALL_TESTS=true'
