[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RemoteHost
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$bootstrap = Get-Content -LiteralPath (Join-Path $repoRoot 'deploy/server-bootstrap.sh') -Raw

function Get-TextBetween {
    param([string]$Name, [string]$Content, [string]$Start, [string]$End)

    $startIndex = $Content.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { throw "Unable to locate start of $Name" }
    $endIndex = $Content.IndexOf($End, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "Unable to locate end of $Name" }
    return $Content.Substring($startIndex, $endIndex - $startIndex)
}

# The fixture intentionally transcribes the fixed production assignment to a
# temporary path, then extracts the production lock and backup code. It only
# creates a fresh /tmp directory on the target and never invokes the full
# bootstrap, changes services, touches credentials, or loads firewall rules.
$productionLockAssignment = Get-TextBetween -Name 'fixed production lock assignment' -Content $bootstrap `
    -Start 'LOCK_FILE="' -End "`nBACKUP_PARENT_DIR="
if ($productionLockAssignment -cne 'LOCK_FILE="/var/lock/proxy-stack-bootstrap.lock"') {
    throw 'The deployment lock fixture requires a fixed, non-overridable production lock path.'
}
$fixtureLockAssignment = $productionLockAssignment.Replace('/var/lock/proxy-stack-bootstrap.lock', '${LOCK_FILE_FIXTURE_PATH}')
$lockSnippet = Get-TextBetween -Name 'deployment lock fixture' -Content $bootstrap `
    -Start 'if ! command -v flock >/dev/null 2>&1; then' -End "`n`n# mktemp adds an unpredictable suffix"
$backupSnippet = Get-TextBetween -Name 'backup directory fixture' -Content $bootstrap `
    -Start 'backup_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"' -End "`nmkdir -p `"`${STACK_DIR}`""

$remoteFixture = @'
set -Eeuo pipefail
temp_root="$(mktemp -d)"
lock_file="${temp_root}/proxy-stack-bootstrap.lock"
ready_file="${temp_root}/lock-holder-ready"
trap 'rm -rf -- "${temp_root}"' EXIT

set +e
missing_flock_output="$(
  (
    PATH=/nonexistent
    LOCK_FILE="/tmp/external-lock-must-not-apply"
    LOCK_FILE_FIXTURE_PATH="${lock_file}"
'@ + "`n" + $fixtureLockAssignment + "`n" + $lockSnippet + "`n" + @'
  ) 2>&1
)"
missing_flock_status=$?
set -e
[[ ${missing_flock_status} -ne 0 ]]
[[ "${missing_flock_output}" == *'flock is required to prevent concurrent proxy-stack deployments; exiting safely.'* ]]

(
  LOCK_FILE="/tmp/external-lock-holder-must-not-apply"
  LOCK_FILE_FIXTURE_PATH="${lock_file}"
'@ + "`n" + $fixtureLockAssignment + "`n" + $lockSnippet + "`n" + @'
  touch "${ready_file}"
  sleep 3
) &
holder_pid=$!

for _ in $(seq 1 100); do
  [[ -f "${ready_file}" ]] && break
  sleep 0.05
done
[[ -f "${ready_file}" ]]

set +e
contender_output="$(
  (
    LOCK_FILE="/tmp/external-lock-contender-must-not-apply"
    LOCK_FILE_FIXTURE_PATH="${lock_file}"
'@ + "`n" + $fixtureLockAssignment + "`n" + $lockSnippet + "`n" + @'
  ) 2>&1
)"
contender_status=$?
set -e
[[ ${contender_status} -ne 0 ]]
[[ "${contender_output}" == *'Another proxy-stack deployment is already running; exiting without changes.'* ]]

wait "${holder_pid}"
(
  LOCK_FILE="/tmp/external-lock-retry-must-not-apply"
  LOCK_FILE_FIXTURE_PATH="${lock_file}"
'@ + "`n" + $fixtureLockAssignment + "`n" + $lockSnippet + "`n" + @'
)

backup_one="$(
  (
    BACKUP_PARENT_DIR="${temp_root}"
'@ + "`n" + $backupSnippet + "`n" + @'
    printf '%s\n' "${BACKUP_DIR}"
  )
)"
backup_two="$(
  (
    BACKUP_PARENT_DIR="${temp_root}"
'@ + "`n" + $backupSnippet + "`n" + @'
    printf '%s\n' "${BACKUP_DIR}"
  )
)"
[[ -d "${backup_one}" && -d "${backup_two}" && "${backup_one}" != "${backup_two}" ]]
[[ "${backup_one}" =~ proxy-stack-backup-[0-9]{8}T[0-9]{6}Z-[A-Za-z0-9]+$ ]]
[[ "${backup_two}" =~ proxy-stack-backup-[0-9]{8}T[0-9]{6}Z-[A-Za-z0-9]+$ ]]
printf 'Deployment lock fixture passed: external LOCK_FILE ignored, concurrent rejection, automatic release, and unique UTC/random backups.\n'
'@

$encodedFixture = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteFixture))
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$output = ($encodedFixture | & ssh $RemoteHost 'base64 --ignore-garbage --decode | bash' 2>&1 | Out-String)
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0 -or $output -notmatch 'Deployment lock fixture passed') {
    throw "Deployment lock fixture failed on $RemoteHost (exit $exitCode): $output"
}

Write-Output $output.Trim()
