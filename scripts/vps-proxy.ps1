[CmdletBinding()]
param(
    [ValidateSet('preflight', 'check', 'deploy', 'rotate', 'status', 'logs', 'restart')]
    [string]$Action = 'check',
    [string]$SshHost,
    [string]$Domain,
    [string]$SubDomain,
    [int]$XrayPort,
    [string]$AdminUser,
    [switch]$AdminSshVerified,
    [switch]$HostChangesApproved,
    [switch]$AcmeTosAccepted,
    [switch]$DisableGoogleOpsAgent,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $name, $value = $line -split '=', 2
        $name = $name.Trim()
        $value = $value.Trim().Trim('"').Trim("'")
        if ($name -match '^[A-Z][A-Z0-9_]*$' -and -not [Environment]::GetEnvironmentVariable($name, 'Process')) {
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }
}

function Invoke-Ssh {
    param([string]$Command)
    & ssh -- $script:SshHost $Command
    if ($LASTEXITCODE -ne 0) { throw "SSH command failed with exit code $LASTEXITCODE." }
}

Import-DotEnv (Join-Path $repoRoot '.env')

if ([string]::IsNullOrWhiteSpace($SshHost)) { $SshHost = $env:VPS_SSH_HOST }
if ([string]::IsNullOrWhiteSpace($Domain)) { $Domain = $env:VPS_DOMAIN }
if ([string]::IsNullOrWhiteSpace($SubDomain)) { $SubDomain = $env:VPS_SUB_DOMAIN }
if ($XrayPort -eq 0 -and $env:VPS_XRAY_PORT) { $XrayPort = [int]$env:VPS_XRAY_PORT }
if ([string]::IsNullOrWhiteSpace($AdminUser)) { $AdminUser = $env:VPS_ADMIN_USER }

if ([string]::IsNullOrWhiteSpace($SshHost)) { throw 'SshHost is required. Configure your own SSH alias in .env or -SshHost.' }
if ([string]::IsNullOrWhiteSpace($Domain)) { throw 'Domain is required. Configure your own domain in .env or -Domain.' }
if ([string]::IsNullOrWhiteSpace($SubDomain)) { $SubDomain = $Domain }
if ($XrayPort -eq 0) { $XrayPort = 2053 }

if ($SshHost -notmatch '^[A-Za-z0-9_.@-]+$') { throw 'SshHost contains unsupported characters.' }
if ($Domain -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$') { throw 'Domain is not a valid DNS name.' }
if ($SubDomain -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$') { throw 'SubDomain is not a valid DNS name.' }
if ($XrayPort -lt 1 -or $XrayPort -gt 65535) { throw 'XrayPort must be between 1 and 65535.' }
if ($XrayPort -in @(22, 80, 443, 8080, 8443, 10443)) { throw "XrayPort $XrayPort conflicts with a reserved TCP port (22, 80, 443 closed, 8080, 8443, Trojan 10443)." }

switch ($Action) {
    'check' {
        Invoke-Ssh "set -eu; systemctl is-active ssh xray hysteria-server nginx proxy-firewall vnstat; uptime; free -h; printf 'trojan_tcp10443_connections='; ss -Htan state established '( sport = :10443 )' | wc -l; printf 'reality_tcp${XrayPort}_connections='; ss -Htan state established '( sport = :$XrayPort )' | wc -l"

        $reality = Test-NetConnection -ComputerName $Domain -Port $XrayPort -InformationLevel Quiet
        $trojan10443 = Test-NetConnection -ComputerName $Domain -Port 10443 -InformationLevel Quiet
        [PSCustomObject]@{
            Host              = $Domain
            RealityTcpPort    = $XrayPort
            RealityReachable  = $reality
            TrojanTcpPort     = 10443
            TrojanReachable   = $trojan10443
        } | Format-List
    }
    'status' {
        Invoke-Ssh "systemctl --no-pager --full status xray hysteria-server nginx proxy-firewall vnstat; echo LOAD; uptime; echo MEMORY; free -h; echo SOCKETS; ss -s; echo LISTENERS; ss -lntup | grep -E ':(22|80|443|8443|10443|$XrayPort)\\b' || true"
    }
    'logs' {
        Invoke-Ssh "sudo journalctl --no-pager -n 200 -u xray -u hysteria-server -u nginx -u proxy-firewall"
    }
    'restart' {
        Invoke-Ssh 'sudo systemctl restart xray hysteria-server && systemctl is-active xray hysteria-server'
    }
    { $_ -in @('preflight', 'deploy', 'rotate') } {
        if ($AdminUser -notmatch '^[a-z_][a-z0-9_-]{0,31}$' -or $AdminUser -eq 'root' -or -not $AdminSshVerified) {
            throw 'AdminUser and -AdminSshVerified are required after a NEW non-root key-only SSH session and sudo test.'
        }
        if (-not $HostChangesApproved -or -not $AcmeTosAccepted) {
            throw 'Review the skill change manifest, then pass -HostChangesApproved and -AcmeTosAccepted with user authorization.'
        }
        $rotate = if ($Action -eq 'rotate') { 1 } else { 0 }
        $preflightOnly = if ($Action -eq 'preflight') { 1 } else { 0 }
        $disableOps = if ($DisableGoogleOpsAgent) { 1 } else { 0 }
        if ($rotate -eq 1 -and -not $Force) {
            $answer = Read-Host 'This invalidates all current node and subscription credentials. Type ROTATE to continue'
            if ($answer -cne 'ROTATE') { throw 'Credential rotation cancelled.' }
        }

        $localScript = Join-Path $repoRoot 'deploy/server-bootstrap.sh'
        $localPreflight = Join-Path $repoRoot 'deploy/preflight.py'
        if (-not (Test-Path -LiteralPath $localScript)) { throw "Missing deployment script: $localScript" }
        if (-not (Test-Path -LiteralPath $localPreflight)) { throw "Missing readiness gate: $localPreflight" }
        $remoteDir = (& ssh -- $SshHost 'mktemp -d /tmp/vps-proxy-build.XXXXXXXXXX' | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $remoteDir -notmatch '^/tmp/vps-proxy-build\.[A-Za-z0-9]{10}$') {
            throw 'Unable to create a validated remote upload directory.'
        }

        try {
            & scp -- $localScript $localPreflight "${SshHost}:$remoteDir/"
            if ($LASTEXITCODE -ne 0) { throw "SCP failed with exit code $LASTEXITCODE." }
            Invoke-Ssh "sudo env DOMAIN='$Domain' SUB_DOMAIN='$SubDomain' XRAY_PORT='$XrayPort' ADMIN_USER='$AdminUser' ADMIN_SSH_VERIFIED=1 HOST_CHANGES_APPROVED=1 ACME_TOS_ACCEPTED=1 DISABLE_GOOGLE_OPS_AGENT='$disableOps' PREFLIGHT_ONLY='$preflightOnly' ROTATE_SECRETS='$rotate' bash '$remoteDir/server-bootstrap.sh'"
        }
        finally {
            & ssh -- $SshHost "rm -f -- '$remoteDir/server-bootstrap.sh' '$remoteDir/preflight.py' && rmdir -- '$remoteDir'" | Out-Null
        }
    }
}
