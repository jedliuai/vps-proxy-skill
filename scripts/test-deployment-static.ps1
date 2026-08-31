[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$bootstrapPath = Join-Path $repoRoot 'deploy/server-bootstrap.sh'
$proxyScriptPath = Join-Path $repoRoot 'scripts/vps-proxy.ps1'
$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw

function Require-Text {
    param([string]$Name, [string]$Text, [string]$Content)

    if ($Content.IndexOf($Text, [System.StringComparison]::Ordinal) -lt 0) {
        throw "Static deployment invariant failed: $Name"
    }
}

function Require-NoMatch {
    param([string]$Name, [string]$Pattern, [string]$Content)

    if ([regex]::IsMatch($Content, $Pattern)) {
        throw "Static deployment invariant failed: $Name"
    }
}

function Get-HeredocBody {
    param([string]$Start)

    $pattern = [regex]::Escape($Start) + "\r?\n(?<body>[\s\S]*?)\r?\nEOF"
    $match = [regex]::Match($bootstrap, $pattern)
    if (-not $match.Success) { throw "Unable to locate heredoc: $Start" }
    return $match.Groups['body'].Value
}

function Get-TextBetween {
    param([string]$Name, [string]$Content, [string]$Start, [string]$End)

    $startIndex = $Content.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { throw "Unable to locate start of $Name" }
    $endIndex = $Content.IndexOf($End, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "Unable to locate end of $Name" }
    return $Content.Substring($startIndex, $endIndex - $startIndex)
}

function Require-OrderedText {
    param([string]$Name, [string]$Content, [string[]]$Values)

    $previous = -1
    foreach ($value in $Values) {
        $position = $Content.IndexOf($value, [System.StringComparison]::Ordinal)
        if ($position -lt 0 -or $position -le $previous) {
            throw "Static deployment ordering invariant failed: $Name ($($Values -join ' -> '))"
        }
        $previous = $position
    }
}

# A non-blocking advisory lock must be acquired before every persistent
# deployment action. Its file remains after exit; closing fd 9 releases it.
Require-Text -Name 'deployment lock has a fixed production path' -Text 'LOCK_FILE="/var/lock/proxy-stack-bootstrap.lock"' -Content $bootstrap
Require-NoMatch -Name 'deployment lock path cannot be overridden from the environment' -Pattern '(?m)^LOCK_FILE=.*\$\{LOCK_FILE' -Content $bootstrap
Require-Text -Name 'deployment lock rejects missing flock' -Text 'flock is required to prevent concurrent proxy-stack deployments; exiting safely.' -Content $bootstrap
Require-Text -Name 'deployment lock opens a dedicated descriptor' -Text 'exec 9>"${LOCK_FILE}"' -Content $bootstrap
Require-Text -Name 'deployment lock is non-blocking' -Text 'flock -n 9' -Content $bootstrap
Require-Text -Name 'deployment lock rejects a concurrent run' -Text 'Another proxy-stack deployment is already running; exiting without changes.' -Content $bootstrap
Require-NoMatch -Name 'deployment lock file is never removed' -Pattern '(?m)^\s*rm\s+.*\$\{?LOCK_FILE\}?' -Content $bootstrap
Require-OrderedText -Name 'deployment lock precedes persistent actions' -Content $bootstrap -Values @(
    'flock -n 9',
    'backup_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"',
    'BACKUP_DIR="$(mktemp -d "${BACKUP_PARENT_DIR}/proxy-stack-backup-${backup_timestamp}-XXXXXX")"',
    'mkdir -p "${STACK_DIR}"',
    'apt-get update',
    'systemctl disable --now google-cloud-ops-agent.service',
    'install -m 0755 "${tmp_dir}/xray/xray" /usr/local/bin/xray'
)

# A host-only rollback must preserve the exact input firewall, both generated
# subscription files, and the currently working proxy binaries. --parents
# keeps these sources in distinct restore paths even when their basenames vary.
$backupCreation = Get-TextBetween -Name 'unique backup directory' -Content $bootstrap `
    -Start 'backup_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"' -End "`nmkdir -p `"`${STACK_DIR}`""
Require-OrderedText -Name 'unique backup directory' -Content $backupCreation -Values @(
    'backup_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"',
    'mktemp -d',
    'proxy-stack-backup-${backup_timestamp}-XXXXXX'
)
$backupSection = Get-TextBetween -Name 'host backup inputs' -Content $bootstrap `
    -Start 'mkdir -p "${STACK_DIR}"' -End "`nexport DEBIAN_FRONTEND"
Require-OrderedText -Name 'host backup inputs' -Content $backupSection -Values @(
    '/usr/local/sbin/proxy-firewall',
    '"${STACK_DIR}/firewall.nft"',
    '/var/lib/proxy-subscription',
    '/usr/local/bin/xray',
    '/usr/local/bin/hysteria',
    'cp -a --parents "${path}" "${BACKUP_DIR}/"'
)

# The firewall must be ordered before both proxies, and both proxy units must
# require it. This keeps boot and manual restarts fail-closed even if the
# deployment activation sequence is bypassed.
$xrayUnit = Get-HeredocBody -Start "cat >/etc/systemd/system/xray.service <<'EOF'"
$hysteriaUnit = Get-HeredocBody -Start "cat >/etc/systemd/system/hysteria-server.service <<'EOF'"
$firewallUnit = Get-HeredocBody -Start "cat >/etc/systemd/system/proxy-firewall.service <<'EOF'"

foreach ($proxyUnit in @(
    @{ Name = 'xray service unit'; Content = $xrayUnit },
    @{ Name = 'hysteria service unit'; Content = $hysteriaUnit }
)) {
    Require-Text -Name "$($proxyUnit.Name) requires firewall" -Text 'Requires=proxy-firewall.service' -Content $proxyUnit.Content
    Require-Text -Name "$($proxyUnit.Name) starts after firewall" -Text 'After=network-online.target' -Content $proxyUnit.Content
    Require-Text -Name "$($proxyUnit.Name) orders after firewall" -Text 'proxy-firewall.service' -Content $proxyUnit.Content
}
Require-OrderedText -Name 'xray unit firewall ordering' -Content $xrayUnit -Values @('Requires=proxy-firewall.service', 'After=network-online.target nss-lookup.target proxy-firewall.service')
Require-OrderedText -Name 'hysteria unit firewall ordering' -Content $hysteriaUnit -Values @('Requires=proxy-firewall.service', 'After=network-online.target nginx.service proxy-firewall.service')
Require-Text -Name 'firewall unit starts before xray and hysteria' -Text 'Before=xray.service hysteria-server.service' -Content $firewallUnit
Require-NoMatch -Name 'firewall dependency cycle' -Pattern '(?m)^(?:Requires|Wants|After)=.*(?:xray|hysteria-server)\.service' -Content $firewallUnit

# A legacy secrets.env migration may append the one new value, but must never
# delete or rewrite the existing secret file outside an explicit rotation.
$migration = Get-TextBetween -Name 'legacy secrets migration' -Content $bootstrap `
    -Start '# Existing installations predate Trojan.' -End "`nset -a"
Require-Text -Name 'legacy migration checks the Trojan key' -Text "if ! grep -q '^TROJAN_PASSWORD=' `"`${SECRETS_FILE}`"; then" -Content $migration
Require-Text -Name 'legacy migration creates an independent random password' -Text 'trojan_password="$(openssl rand -hex 32)"' -Content $migration
Require-Text -Name 'legacy migration appends rather than replaces secrets' -Text "printf '\nTROJAN_PASSWORD=%s\n' `"`${trojan_password}`" >>`"`${SECRETS_FILE}`"" -Content $migration
Require-NoMatch -Name 'legacy migration must not delete existing secrets' -Pattern '(?m)^\s*(rm|mv|cp|install)\b|(?<!>)>(?!>)' -Content $migration

# Run only the real validation sections, never the deployment or SSH actions.
# Both entrypoints must reject occupied ports and the deliberately closed TCP
# 443, while preserving the default Reality port and other free TCP ports.
$gitRoot = Split-Path -Parent (Split-Path -Parent (Get-Command git -ErrorAction Stop).Source)
$gitBash = Join-Path $gitRoot 'bin/bash.exe'
$bashExe = if (Test-Path -LiteralPath $gitBash) { $gitBash } else { (Get-Command bash -ErrorAction Stop).Source }
function Invoke-BashFixture {
    param([string]$Script)

    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $bashExe
    $info.Arguments = '--noprofile --norc -s'
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $process.StandardInput.Write($Script.Replace("`r`n", "`n") + "`n")
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return @{ ExitCode = $process.ExitCode; Output = $stdout.GetAwaiter().GetResult(); Error = $stderr.GetAwaiter().GetResult() }
    }
    finally { $process.Dispose() }
}
$bashPortValidation = Get-TextBetween -Name 'Bash port validation' -Content $bootstrap `
    -Start 'if [[ ! "${XRAY_PORT}" =~' -End 'if [[ "${ROTATE_SECRETS}"'
$proxyScript = Get-Content -LiteralPath $proxyScriptPath -Raw
$psPortValidation = Get-TextBetween -Name 'PowerShell port validation' -Content $proxyScript `
    -Start 'if ($XrayPort -lt 1' -End 'switch ($Action)'
foreach ($port in @(22, 80, 443, 8080, 8443, 10443, 2053, 2443)) {
    $wantRejected = $port -in @(22, 80, 443, 8080, 8443, 10443)
    $bashResult = Invoke-BashFixture -Script ("XRAY_PORT=$port`n" + $bashPortValidation)
    $psRejected = $false
    try { & ([scriptblock]::Create('param($XrayPort)' + "`n" + $psPortValidation)) $port }
    catch { $psRejected = $true }
    if (($bashResult.ExitCode -ne 0) -ne $wantRejected -or $psRejected -ne $wantRejected) {
        throw "Port validation failed for $port (expected rejected=$wantRejected; Bash=$($bashResult.ExitCode); PowerShell=$psRejected)."
    }
}

# Verify the exact Trojan inbound section rather than matching similarly named
# text elsewhere in the script. Its only fallback target is local Nginx.
$xrayConfig = Get-HeredocBody -Start 'cat >/etc/xray/config.json <<EOF'
$trojanInbound = Get-TextBetween -Name 'Trojan inbound' -Content $xrayConfig `
    -Start '      "tag": "trojan-tls-in"' -End '      "tag": "vless-reality-in"'
Require-OrderedText -Name 'Trojan TLS inbound fields' -Content $trojanInbound -Values @('"port": 10443', '"protocol": "trojan"', '"fallbacks": [', '"security": "tls"')
$fallbacks = [regex]::Matches($trojanInbound, '"dest":\s*"([^"]+)"')
if ($fallbacks.Count -ne 1 -or $fallbacks[0].Groups[1].Value -cne '127.0.0.1:8080') {
    throw 'Static deployment invariant failed: Trojan has exactly one local fallback target.'
}
Require-Text -Name 'Xray certificate directory ownership' -Text 'chown root:xray /etc/xray/certs' -Content $bootstrap
Require-Text -Name 'Xray certificate directory mode' -Text 'chmod 0750 /etc/xray/certs' -Content $bootstrap

# Render the actual Xray JSON with non-secret fixtures. Port changes must not
# disturb the Reality inbound or its local TLS target.
$renderedXray = Invoke-BashFixture -Script ('XRAY_PORT=2053' + "`n" + 'cat <<EOF' + "`n" + $xrayConfig + "`nEOF")
if ($renderedXray.ExitCode -ne 0) { throw 'Unable to render the Xray fixture.' }
$inbounds = ($renderedXray.Output | ConvertFrom-Json).inbounds
$renderedTrojan = @($inbounds | Where-Object tag -eq 'trojan-tls-in')
$renderedReality = @($inbounds | Where-Object tag -eq 'vless-reality-in')
if ($inbounds.Count -ne 2 -or $renderedTrojan.Count -ne 1 -or $renderedTrojan[0].port -ne 10443 -or
    $renderedTrojan[0].protocol -ne 'trojan' -or $renderedTrojan[0].streamSettings.network -ne 'tcp' -or
    $renderedReality.Count -ne 1 -or $renderedReality[0].port -ne 2053 -or $renderedReality[0].protocol -ne 'vless' -or
    $renderedReality[0].streamSettings.realitySettings.target -ne '127.0.0.1:8443') {
    throw 'Rendered Xray configuration does not preserve Trojan TCP 10443 and Reality TCP 2053.'
}
Require-Text -Name 'Bash default Reality port is unchanged' -Text 'XRAY_PORT="${XRAY_PORT:-2053}"' -Content $bootstrap
Require-Text -Name 'PowerShell default Reality port is unchanged' -Text 'if ($XrayPort -eq 0) { $XrayPort = 2053 }' -Content $proxyScript
$hysteriaConfig = Get-HeredocBody -Start 'cat >/etc/hysteria/config.yaml <<EOF'
Require-Text -Name 'Hysteria UDP listener is unchanged' -Text 'listen: 0.0.0.0:443' -Content $hysteriaConfig

# Renewal operations are extracted from their dedicated heredoc, so commands
# outside the hook cannot satisfy this test accidentally.
$renewalHook = Get-HeredocBody -Start 'cat >/etc/letsencrypt/renewal-hooks/deploy/proxy-stack <<EOF'
Require-OrderedText -Name 'certificate renewal hook' -Content $renewalHook -Values @(
    '#!/bin/sh',
    'set -eu',
    'install -o root -g hysteria -m 0640 /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/hysteria/certs/fullchain.pem',
    'install -o root -g hysteria -m 0640 /etc/letsencrypt/live/${DOMAIN}/privkey.pem /etc/hysteria/certs/privkey.pem',
    'install -o root -g xray -m 0640 /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/xray/certs/fullchain.pem',
    'install -o root -g xray -m 0640 /etc/letsencrypt/live/${DOMAIN}/privkey.pem /etc/xray/certs/privkey.pem',
    'systemctl restart xray',
    'systemctl restart hysteria-server',
    'systemctl reload nginx'
)
$hookServiceCommands = [regex]::Matches($renewalHook, '(?m)^systemctl .+$') | ForEach-Object Value
if (@($hookServiceCommands).Count -ne 3 -or (@($hookServiceCommands) -join "`n") -cne "systemctl restart xray`nsystemctl restart hysteria-server`nsystemctl reload nginx") {
    throw 'Static deployment invariant failed: renewal hook service commands are incomplete or out of order.'
}

# Validate the emitted YAML sections in isolation. ChatGPT must have exactly
# one selectable route, US-Auto, while the fallback order remains fixed.
$clashConfig = Get-HeredocBody -Start 'cat >/var/lib/proxy-subscription/clash.yaml <<EOF'
$clashTrojan = Get-TextBetween -Name 'Clash Trojan node' -Content $clashConfig -Start '  - name: US-Trojan' -End '  - name: US-Reality'
$clashHysteria = Get-TextBetween -Name 'Clash Hysteria node' -Content $clashConfig -Start '  - name: US-Hysteria2' -End '  - name: US-Trojan'
$clashReality = Get-TextBetween -Name 'Clash Reality node' -Content $clashConfig -Start '  - name: US-Reality' -End 'proxy-groups:'
Require-Text -Name 'Clash Trojan uses TCP 10443' -Text '    port: 10443' -Content $clashTrojan
Require-Text -Name 'Clash Hysteria retains UDP 443' -Text '    port: 443' -Content $clashHysteria
Require-Text -Name 'Clash Reality retains the configured port' -Text '    port: ${XRAY_PORT}' -Content $clashReality
$usAutoGroup = Get-TextBetween -Name 'US-Auto group' -Content $clashConfig -Start '  - name: US-Auto' -End "`n`n  - name: Proxy-Select"
$autoProxies = [regex]::Matches($usAutoGroup, '(?m)^\s*- (US-[A-Za-z0-9]+)$') | ForEach-Object { $_.Groups[1].Value }
if (@($autoProxies).Count -ne 3 -or (@($autoProxies) -join ',') -cne 'US-Hysteria2,US-Trojan,US-Reality') {
    throw 'Static deployment invariant failed: US-Auto ordering is not Hysteria2 -> Trojan -> Reality.'
}
$chatGptGroup = Get-TextBetween -Name 'ChatGPT group' -Content $clashConfig -Start '  - name: ChatGPT' -End "`n`nrules:"
Require-Text -Name 'ChatGPT group uses select' -Text '    type: select' -Content $chatGptGroup
$chatGptProxies = [regex]::Matches($chatGptGroup, '(?m)^ {6}- (.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() }
if (@($chatGptProxies).Count -ne 1 -or @($chatGptProxies)[0] -cne 'US-Auto') {
    throw 'Static deployment invariant failed: ChatGPT must contain only US-Auto.'
}

# Test the URI encoding contract with non-secret fixture values, then bind the
# same three URI templates and GNU no-wrap mode to the deployment writer.
$testDomain = 'unit.example'
$uriLines = @(
    "hysteria2://hy-test@$testDomain`:443/?sni=$testDomain&alpn=h3#US-Hysteria2",
    "trojan://tr-test@$testDomain`:10443?security=tls&sni=$testDomain&type=tcp#US-Trojan",
    "vless://uuid-test@$testDomain`:2053?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$testDomain&fp=chrome&pbk=public-test&sid=short-test&type=tcp#US-Reality"
)
$base64Subscription = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($uriLines -join "`n")))
if ($base64Subscription -match "\r|\n") { throw 'Base64 fixture unexpectedly contains a line fold.' }
$decodedUris = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64Subscription)) -split "`n"
if (@($decodedUris).Count -ne 3 -or
    $decodedUris[0] -notmatch '^hysteria2://.+:443/\?sni=unit\.example&alpn=h3#US-Hysteria2$' -or
    $decodedUris[1] -notmatch '^trojan://.+:10443\?security=tls&sni=unit\.example&type=tcp#US-Trojan$' -or
    $decodedUris[2] -notmatch '^vless://.+:2053\?encryption=none&flow=xtls-rprx-vision&security=reality&sni=unit\.example&fp=chrome&pbk=public-test&sid=short-test&type=tcp#US-Reality$') {
    throw 'Base64 fixture does not decode to exactly the three required URI forms.'
}
$subscriptionWriter = Get-TextBetween -Name 'URI subscription writer' -Content $bootstrap `
    -Start "{`n  printf 'hysteria2://" -End 'chown root:www-data /var/lib/proxy-subscription/v2ray.txt'
Require-OrderedText -Name 'URI subscription writer' -Content $subscriptionWriter -Values @(
    "printf 'hysteria2://%s@%s:443/?sni=%s&alpn=h3#US-Hysteria2\n'",
    "printf 'trojan://%s@%s:10443?security=tls&sni=%s&type=tcp#US-Trojan\n'",
    "printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#US-Reality\n'",
    '} | base64 -w 0 >/var/lib/proxy-subscription/v2ray.txt'
)

$nginxMarker = 'cat >/etc/nginx/sites-available/proxy-stack <<EOF'
$nginxMatches = [regex]::Matches($bootstrap, [regex]::Escape($nginxMarker) + "\r?\n(?<body>[\s\S]*?)\r?\nEOF")
if ($nginxMatches.Count -ne 2) { throw 'Expected separate ACME and subscription Nginx configuration heredocs.' }
$nginxConfig = $nginxMatches[1].Groups['body'].Value
Require-Text -Name 'backup Clash route' -Text 'location = /${BACKUP_SUBSCRIPTION_TOKEN}/clash.yaml' -Content $nginxConfig
Require-Text -Name 'backup V2Ray route' -Text 'location = /${BACKUP_SUBSCRIPTION_TOKEN}/v2ray.txt' -Content $nginxConfig
$backupLocations = @()
$backupLocations += Get-TextBetween -Name 'backup Clash location' -Content $nginxConfig `
    -Start 'location = /${BACKUP_SUBSCRIPTION_TOKEN}/clash.yaml {' -End "`n    }"
$backupLocations += Get-TextBetween -Name 'backup V2Ray location' -Content $nginxConfig `
    -Start 'location = /${BACKUP_SUBSCRIPTION_TOKEN}/v2ray.txt {' -End "`n    }"
foreach ($backupLocation in $backupLocations) {
    Require-OrderedText -Name 'backup subscription location security' -Content $backupLocation -Values @(
        'access_log off;',
        "add_header Cache-Control 'no-store, no-cache, must-revalidate, max-age=0' always;",
        "add_header X-Content-Type-Options 'nosniff' always;",
        "add_header X-Frame-Options 'DENY' always;",
        "add_header Referrer-Policy 'no-referrer' always;"
    )
}
$subscriptionUrls = Get-TextBetween -Name 'subscription URL manifest' -Content $bootstrap `
    -Start 'cat >"${STACK_DIR}/subscription-urls.txt" <<EOF' -End "`nEOF"
Require-OrderedText -Name 'subscription URL manifest' -Content $subscriptionUrls -Values @('PRIMARY_SUBSCRIPTION=', 'PRIMARY_CLASH=', 'PRIMARY_V2RAY=', 'BACKUP_CLASH=', 'BACKUP_V2RAY=')

# Only Trojan TCP 10443 receives the migrated limit/accept rule. TCP 443 is
# closed to new connections by the default-drop policy; UDP 443 is unchanged.
$firewall = Get-HeredocBody -Start 'cat >"${STACK_DIR}/firewall.nft" <<EOF'
$limit10443 = 'tcp dport 10443 ct state new limit rate 60/second burst 120 packets accept'
$drop10443 = 'tcp dport 10443 drop'
if ([regex]::Matches($firewall, [regex]::Escape($limit10443)).Count -ne 1 -or
    [regex]::Matches($firewall, [regex]::Escape($drop10443)).Count -ne 1 -or
    $firewall.IndexOf($limit10443, [System.StringComparison]::Ordinal) -ge $firewall.IndexOf($drop10443, [System.StringComparison]::Ordinal)) {
    throw 'Static deployment invariant failed: TCP 10443 limit accept must occur exactly once before its explicit drop.'
}
Require-Text -Name 'firewall remains default drop' -Text 'type filter hook input priority -10; policy drop;' -Content $firewall
Require-NoMatch -Name 'TCP 443 is not accepted, including in a port set' -Pattern '(?m)^\s*tcp dport [^\r\n]*\b443\b[^\r\n]*accept' -Content $firewall
Require-Text -Name 'firewall keeps Hysteria UDP 443 open' -Text 'udp dport 443 accept' -Content $firewall
Require-Text -Name 'firewall keeps Reality rate protection' -Text 'tcp dport ${XRAY_PORT} ct state new limit rate 60/second burst 120 packets accept' -Content $firewall
Require-Text -Name 'firewall keeps Nginx ACME and subscription ports' -Text 'tcp dport { 80, 8443 } accept' -Content $firewall

# Existing active services need a restart after the config test and after the
# firewall is active. New proxy processes must never start before the firewall
# has been loaded, while non-proxy timers may start independently.
$activation = Get-TextBetween -Name 'service activation' -Content $bootstrap `
    -Start '/usr/local/bin/xray run -test -c /etc/xray/config.json' -End 'cat >"${STACK_DIR}/subscription-urls.txt" <<EOF'
Require-OrderedText -Name 'safe service activation sequence' -Content $activation -Values @(
    '/usr/local/bin/xray run -test -c /etc/xray/config.json',
    'systemctl daemon-reload',
    'systemctl enable xray hysteria-server',
    'systemctl enable --now vnstat certbot.timer',
    'systemctl enable --now proxy-firewall',
    'systemctl reload proxy-firewall',
    'systemctl restart xray hysteria-server'
)
$firewallReadyIndex = $activation.IndexOf('systemctl reload proxy-firewall', [System.StringComparison]::Ordinal)
if ($firewallReadyIndex -lt 0) { throw 'Static deployment invariant failed: firewall reload is missing.' }
$beforeFirewall = $activation.Substring(0, $firewallReadyIndex)
if ([regex]::IsMatch($beforeFirewall, '(?m)^systemctl\s+(?:enable\s+--now|start|restart)\s+.*\b(?:xray|hysteria-server)\b')) {
    throw 'Static deployment invariant failed: proxy services can start before the firewall is active.'
}

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($proxyScriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    throw "vps-proxy.ps1 PowerShell syntax validation failed: $($parseErrors[0].Message)"
}
$proxyScript = Get-Content -LiteralPath $proxyScriptPath -Raw
Require-Text -Name 'check reports Trojan TCP 10443 connection count' -Text "printf 'trojan_tcp10443_connections='" -Content $proxyScript
Require-Text -Name 'check counts Trojan TCP 10443 connections' -Text "ss -Htan state established '( sport = :10443 )'" -Content $proxyScript
Require-Text -Name 'status labels TCP 10443 as Trojan' -Text 'TrojanTcpPort     = 10443' -Content $proxyScript
Require-Text -Name 'check probes Trojan TCP 10443' -Text 'Test-NetConnection -ComputerName $Domain -Port 10443' -Content $proxyScript

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$port10443Output = & $pwsh -NoProfile -File $proxyScriptPath -Action check -SshHost fixture-host -Domain node.customer.net -XrayPort 10443 2>&1 | Out-String
$port10443ExitCode = $LASTEXITCODE
if ($port10443ExitCode -eq 0 -or $port10443Output -notmatch 'XrayPort 10443 conflicts with a reserved TCP port') {
    throw 'vps-proxy.ps1 did not reject XRAY_PORT=10443 before a check action.'
}

Write-Output 'Static deployment invariants passed: deployment locking, unique backups, migration preservation, host backup coverage, port conflict rejection, renewal hook, URI Base64, subscription headers, firewall ordering, and service activation are consistent.'
