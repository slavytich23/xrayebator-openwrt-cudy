[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$textExtensions = @('.md', '.txt', '.ps1', '.sh', '.json', '.example', '')
$findings = [Collections.Generic.List[string]]::new()

$patterns = [ordered]@{
    'VLESS URL' = '(?i)vless://'
    'Private key block' = '-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----'
    'UUID-like credential' = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
    'Subscription token path' = '(?i)/sub/[0-9a-f]{24,}'
    'Developer machine path' = '(?i)[A-Z]:\\(?:Users|Codex)\\'
    'SSH host target' = '(?i)\broot@[a-z0-9.-]+'
    'Secret assignment' = '(?i)(?:password|passwd|token|secret|private_key)\s*[=:]\s*["''][^"''\r\n]{8,}["'']'
}

Get-ChildItem -LiteralPath $root -Recurse -File |
    Where-Object {
        $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar).git$([IO.Path]::DirectorySeparatorChar)*" -and
        $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar)tests$([IO.Path]::DirectorySeparatorChar)*"
    } |
    ForEach-Object {
        $extension = $_.Extension.ToLowerInvariant()
        if ($textExtensions -notcontains $extension) { return }
        $text = Get-Content -LiteralPath $_.FullName -Raw
        foreach ($entry in $patterns.GetEnumerator()) {
            if ($text -match $entry.Value) {
                $relative = $_.FullName.Substring($root.Length).TrimStart('\')
                $findings.Add("$($entry.Key): $relative")
            }
        }
    }

if ($findings.Count -gt 0) {
    $findings | ForEach-Object { Write-Error $_ }
    throw "secret hygiene failed with $($findings.Count) finding(s)"
}

'SECRET_HYGIENE_TESTS=true'
