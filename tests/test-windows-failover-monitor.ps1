[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$monitorPath = Join-Path $root 'windows\cudy-primary-failover-monitor.ps1'
$installerPath = Join-Path $root 'windows\install-cudy-failover-monitor.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "assertion failed: $Name" }
}

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Name)
    Assert-True ($Text -match $Pattern) $Name
}

foreach ($path in @($monitorPath, $installerPath)) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "PowerShell syntax for $([IO.Path]::GetFileName($path))"
}

$monitor = Get-Content -LiteralPath $monitorPath -Raw
$installer = Get-Content -LiteralPath $installerPath -Raw

Assert-Match $monitor '\[switch\]\$NoChange' 'diagnostic no-change mode exists'
Assert-Match $monitor '--interface'', \$Address' 'HTTPS probes bind to a specific source address'
Assert-Match $monitor '--resolve ''one\.one\.one\.one:443:1\.1\.1\.1''' 'fixed probe does not depend on DNS'
Assert-Match $monitor 'https://example\.com/' 'named probe checks DNS and HTTPS'
Assert-Match $monitor '\$failures -ge \$FailureThreshold -and \$backup\.Healthy' 'failover requires a healthy backup'
Assert-Match $monitor '\$successes -ge \$RecoveryThreshold' 'recovery requires consecutive successes'
Assert-Match $monitor 'Set-NetIPInterface' 'monitor changes only route preference when enabled'
Assert-Match $installer 'WindowsBuiltInRole\]::Administrator' 'installer requires elevation'
Assert-Match $installer 'New-ScheduledTaskAction' 'installer creates a scheduled task'

Assert-True ($monitor -notmatch '(?i)[A-Z]:\\(?:Users|Codex)\\') 'monitor has no developer machine path'
Assert-True ($installer -notmatch '(?i)[A-Z]:\\(?:Users|Codex)\\') 'installer has no developer machine path'

'WINDOWS_FAILOVER_TESTS=true'
