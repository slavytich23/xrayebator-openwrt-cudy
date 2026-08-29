[CmdletBinding()]
param(
    [string]$PrimaryInterfaceAlias = 'Ethernet',
    [string]$BackupInterfaceAlias = 'Wi-Fi',
    [string]$BackupWifiProfile = '',
    [string]$PrimaryGateway = '192.168.10.1',
    [string]$BackupGateway = '192.168.0.1',
    [int]$PrimaryMetric = 20,
    [int]$StandbyMetric = 500,
    [int]$IntervalSeconds = 15,
    [int]$FailureThreshold = 3,
    [int]$RecoveryThreshold = 2,
    [int]$WifiReconnectCooldownSeconds = 60,
    [int]$MaxCycles = 0,
    [string]$StateDirectory = (Join-Path $env:ProgramData 'XrayebatorOpenWrtCudy'),
    [string]$ConfigPath = '',
    [switch]$NoChange,
    [switch]$SelfTestFailover
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $false
}

if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $allowed = @(
        'PrimaryInterfaceAlias', 'BackupInterfaceAlias', 'BackupWifiProfile',
        'PrimaryGateway', 'BackupGateway', 'PrimaryMetric', 'StandbyMetric',
        'IntervalSeconds', 'FailureThreshold', 'RecoveryThreshold',
        'WifiReconnectCooldownSeconds', 'StateDirectory'
    )
    foreach ($name in $allowed) {
        if ($null -ne $config.PSObject.Properties[$name]) {
            Set-Variable -Name $name -Value $config.$name -Scope Script
        }
    }
}

if ($FailureThreshold -lt 1 -or $RecoveryThreshold -lt 1 -or $IntervalSeconds -lt 1) {
    throw 'Thresholds and interval must be positive integers.'
}

$statusPath = Join-Path $StateDirectory 'status.json'
$logPath = Join-Path $StateDirectory 'monitor.log'
$lastWifiReconnectAttempt = [datetime]::MinValue
New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null

$mutex = [Threading.Mutex]::new($false, 'Global\XrayebatorOpenWrtCudyFailover')
$hasMutex = $false

function Write-MonitorLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = '{0:o} {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Get-InterfaceState {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [string]$ExpectedGateway = ''
    )

    $adapter = Get-NetAdapter -Name $Alias -ErrorAction SilentlyContinue
    $ipConfig = Get-NetIPConfiguration -InterfaceAlias $Alias -ErrorAction SilentlyContinue
    $address = @(
        $ipConfig.IPv4Address.IPAddress |
            Where-Object { $_ -and $_ -notlike '169.254.*' } |
            Select-Object -First 1
    )
    $gateways = @($ipConfig.IPv4DefaultGateway.NextHop | Where-Object { $_ })
    $gatewayReady = if ([string]::IsNullOrWhiteSpace($ExpectedGateway)) {
        $gateways.Count -gt 0
    } else {
        $gateways -contains $ExpectedGateway
    }
    $defaultRoutes = @(
        Get-NetRoute -InterfaceAlias $Alias -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Alive' }
    )

    [pscustomobject]@{
        AdapterState = if ($null -eq $adapter) { 'Missing' } else { [string]$adapter.Status }
        Address = if ($address.Count -gt 0) { [string]$address[0] } else { $null }
        RouteReady = $null -ne $adapter -and $adapter.Status -eq 'Up' -and $gatewayReady -and $defaultRoutes.Count -gt 0
    }
}

function Test-BoundHttps {
    param([Parameter(Mandatory)][string]$Address)

    $common = @(
        '--silent', '--show-error', '--fail',
        '--connect-timeout', '4', '--max-time', '8',
        '--noproxy', '*', '--interface', $Address,
        '--output', 'NUL'
    )

    & curl.exe @common --resolve 'one.one.one.one:443:1.1.1.1' 'https://one.one.one.one/cdn-cgi/trace' 2>$null
    $fixedOk = $LASTEXITCODE -eq 0
    & curl.exe @common 'https://example.com/' 2>$null
    $namedOk = $LASTEXITCODE -eq 0
    return $fixedOk -and $namedOk
}

function Ensure-BackupConnected {
    $state = Get-InterfaceState -Alias $BackupInterfaceAlias -ExpectedGateway $BackupGateway
    if ($state.RouteReady -or $NoChange -or [string]::IsNullOrWhiteSpace($BackupWifiProfile)) {
        return $state
    }

    $now = Get-Date
    if (($now - $script:lastWifiReconnectAttempt).TotalSeconds -lt $WifiReconnectCooldownSeconds) {
        return $state
    }

    $script:lastWifiReconnectAttempt = $now
    Write-MonitorLog 'Backup Wi-Fi is unavailable; requesting profile reconnect.'
    & netsh.exe wlan connect name="$BackupWifiProfile" interface="$BackupInterfaceAlias" *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-MonitorLog "Backup Wi-Fi reconnect failed with exit code $LASTEXITCODE."
        return $state
    }

    Start-Sleep -Seconds 5
    return Get-InterfaceState -Alias $BackupInterfaceAlias -ExpectedGateway $BackupGateway
}

function Test-InterfaceInternet {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$ExpectedGateway,
        [switch]$ReconnectBackup
    )

    try {
        $state = if ($ReconnectBackup) {
            Ensure-BackupConnected
        } else {
            Get-InterfaceState -Alias $Alias -ExpectedGateway $ExpectedGateway
        }
        if (-not $state.RouteReady -or [string]::IsNullOrWhiteSpace($state.Address)) {
            return [pscustomobject]@{ Healthy = $false; State = $state }
        }
        $healthy = Test-BoundHttps -Address $state.Address
        return [pscustomobject]@{ Healthy = $healthy; State = $state }
    } catch {
        Write-MonitorLog ("Probe for '$Alias' failed: " + $_.Exception.Message)
        return [pscustomobject]@{
            Healthy = $false
            State = [pscustomobject]@{ AdapterState = 'Error'; Address = $null; RouteReady = $false }
        }
    }
}

function Get-PrimaryMetric {
    $iface = Get-NetIPInterface -InterfaceAlias $PrimaryInterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($null -eq $iface) { return $null }
    return [int]$iface.InterfaceMetric
}

function Set-PrimaryMetricSafe {
    param([Parameter(Mandatory)][int]$Metric, [Parameter(Mandatory)][string]$Reason)
    if ($NoChange) { return }
    $before = Get-PrimaryMetric
    if ($before -eq $Metric) { return }
    Set-NetIPInterface -InterfaceAlias $PrimaryInterfaceAlias -AddressFamily IPv4 -AutomaticMetric Disabled -InterfaceMetric $Metric
    Write-MonitorLog "Primary metric $before -> $Metric; $Reason"
}

try {
    $hasMutex = $mutex.WaitOne(0)
    if (-not $hasMutex) { exit 0 }

    Write-MonitorLog 'Monitor started.'
    $failures = 0
    $successes = 0
    $cycle = 0

    while ($true) {
        $cycle++
        $primary = if ($SelfTestFailover) {
            $simulatedHealthy = $cycle -gt $FailureThreshold
            [pscustomobject]@{
                Healthy = $simulatedHealthy
                State = [pscustomobject]@{ AdapterState = 'SelfTest'; Address = $null; RouteReady = $true }
            }
        } else {
            Test-InterfaceInternet -Alias $PrimaryInterfaceAlias -ExpectedGateway $PrimaryGateway
        }
        $backup = Test-InterfaceInternet -Alias $BackupInterfaceAlias -ExpectedGateway $BackupGateway -ReconnectBackup

        if ($primary.Healthy) {
            $successes++
            $failures = 0
            if ($successes -ge $RecoveryThreshold -and $primary.State.RouteReady) {
                Set-PrimaryMetricSafe -Metric $PrimaryMetric -Reason 'primary passed consecutive bound HTTPS checks'
            }
        } else {
            $failures++
            $successes = 0
            if ($failures -ge $FailureThreshold -and $backup.Healthy) {
                Set-PrimaryMetricSafe -Metric $StandbyMetric -Reason 'primary failed consecutive checks and backup is healthy'
            }
        }

        $metric = Get-PrimaryMetric
        $status = [ordered]@{
            Timestamp = (Get-Date).ToString('o')
            Cycle = $cycle
            PrimaryHealthy = [bool]$primary.Healthy
            BackupHealthy = [bool]$backup.Healthy
            PrimaryAdapterState = $primary.State.AdapterState
            BackupAdapterState = $backup.State.AdapterState
            ConsecutiveFailures = $failures
            ConsecutiveSuccesses = $successes
            PrimaryInterfaceMetric = $metric
            PrimarySelected = $metric -eq $PrimaryMetric
            NoChange = [bool]$NoChange
            SelfTest = [bool]$SelfTestFailover
        }
        $status | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8

        if ($MaxCycles -gt 0 -and $cycle -ge $MaxCycles) { break }
        Start-Sleep -Seconds $IntervalSeconds
    }
} catch {
    Write-MonitorLog ('Monitor error: ' + $_.Exception.Message)
    throw
} finally {
    if ($hasMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
