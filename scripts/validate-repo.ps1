[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
# Git ignore rules apply only to untracked files: tracked credentials must
# remain visible even if a later ignore rule matches them. NUL separators
# preserve whitespace and non-ASCII filenames without Git path quoting.
$gitFiles = & git -C $repoRoot ls-files --cached --others --exclude-standard -z
if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate repository files with Git.' }
$files = (($gitFiles -join "`n") -split "`0") |
    Where-Object { $_.Length -gt 0 } | Sort-Object -Unique -CaseSensitive |
    ForEach-Object {
        $path = Join-Path $repoRoot $_
        if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Item -LiteralPath $path -Force }
    }

$rules = [ordered]@{
    'Private key block' = '-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----'
    'Literal 64-char subscription URL token' = 'https?://[^\s/]+/[A-Fa-f0-9]{64}/(?:clash\.yaml|v2ray\.txt|subscription)(?:[?#][^\s]*)?'
    'Literal secret assignment' = '(?i)(?:password|token|private[_-]?key|secret)\s*[:=]\s*["'']?[A-Za-z0-9_+/-]{20,}["'']?\s*$'
}

$findings = @()
foreach ($file in $files) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue) {
        $lineNumber++
        foreach ($rule in $rules.GetEnumerator()) {
            if ($line -match $rule.Value) {
                $findings += [PSCustomObject]@{
                    Rule = $rule.Key
                    File = $file.FullName.Substring($repoRoot.Length + 1)
                    Line = $lineNumber
                }
            }
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | Format-Table -AutoSize
    throw 'Potential secrets found. Values were intentionally not printed.'
}

$pwshExe = (Get-Command pwsh -ErrorAction Stop).Source
& $pwshExe -NoProfile -File (Join-Path $repoRoot 'scripts/test-repository-scan.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Repository scan file-selection tests failed.' }

$gitExe = (Get-Command git -ErrorAction Stop).Source
$gitRoot = Split-Path -Parent (Split-Path -Parent $gitExe)
$gitBash = Join-Path $gitRoot 'bin/bash.exe'
$bashExe = if (Test-Path -LiteralPath $gitBash) {
    $gitBash
} else {
    (Get-Command bash -ErrorAction Stop).Source
}

& $bashExe -n (Join-Path $repoRoot 'deploy/server-bootstrap.sh')
if ($LASTEXITCODE -ne 0) { throw 'server-bootstrap.sh failed bash syntax validation.' }

& $pwshExe -NoProfile -File (Join-Path $repoRoot 'scripts/test-deployment-static.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Deployment static invariant validation failed.' }

& node --check (Join-Path $repoRoot 'cloudflare-worker/src/index.js')
if ($LASTEXITCODE -ne 0) { throw 'Cloudflare Worker failed JavaScript syntax validation.' }

& node --test (Join-Path $repoRoot 'cloudflare-worker/test/index.test.js')
if ($LASTEXITCODE -ne 0) { throw 'Cloudflare Worker unit tests failed.' }

Write-Output 'Repository validation passed: no secret patterns found; Bash, PowerShell static invariants, and Cloudflare Worker checks are valid.'
