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
    [string]$TaskName = 'Xrayebator OpenWrt Cudy Failover'
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this installer from an elevated PowerShell window.'
}

$sourceMonitor = Join-Path $PSScriptRoot 'cudy-primary-failover-monitor.ps1'
if (-not (Test-Path -LiteralPath $sourceMonitor -PathType Leaf)) {
    throw 'Monitor script is missing next to the installer.'
}

$installDirectory = Join-Path $env:ProgramData 'XrayebatorOpenWrtCudy'
$installedMonitor = Join-Path $installDirectory 'cudy-primary-failover-monitor.ps1'
$configPath = Join-Path $installDirectory 'config.json'
New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourceMonitor -Destination $installedMonitor -Force

$config = [ordered]@{
    PrimaryInterfaceAlias = $PrimaryInterfaceAlias
    BackupInterfaceAlias = $BackupInterfaceAlias
    BackupWifiProfile = $BackupWifiProfile
    PrimaryGateway = $PrimaryGateway
    BackupGateway = $BackupGateway
    PrimaryMetric = $PrimaryMetric
    StandbyMetric = $StandbyMetric
    IntervalSeconds = $IntervalSeconds
    FailureThreshold = $FailureThreshold
    RecoveryThreshold = $RecoveryThreshold
    WifiReconnectCooldownSeconds = 60
    StateDirectory = $installDirectory
}
$config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8

$argument = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installedMonitor`" -ConfigPath `"$configPath`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

[pscustomobject]@{
    Installed = $true
    TaskName = $TaskName
    MonitorPath = $installedMonitor
    ConfigPath = $configPath
}
