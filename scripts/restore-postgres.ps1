param(
    [Parameter(Mandatory = $true)]
    [string]$BackupFile,
    [switch]$Force,
    [string]$ProjectName = '',
    [string]$Service = 'postgres',
    [string]$Database = 'yonlearn',
    [string]$Username = 'yonlearn'
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Host "FAIL: $Message"
    exit 1
}

function Assert-SafeIdentifier([string]$Name, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9_.-]+$') {
        Fail "$Name contains unsupported characters. Use letters, numbers, dot, underscore, or dash only."
    }
}

function ComposeArgs() {
    $args = @()
    if (-not [string]::IsNullOrWhiteSpace($ProjectName)) { $args += @('-p', $ProjectName) }
    return $args
}

function Run-Docker([string[]]$DockerArgs, [string]$Step) {
    & docker @DockerArgs
    if ($LASTEXITCODE -ne 0) { Fail "$Step failed with exit code $LASTEXITCODE" }
}

Assert-SafeIdentifier 'Service' $Service
Assert-SafeIdentifier 'Database' $Database
Assert-SafeIdentifier 'Username' $Username
if ($ProjectName) { Assert-SafeIdentifier 'ProjectName' $ProjectName }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Fail 'Docker CLI is not installed or not on PATH.' }
if (-not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) { Fail "Backup file does not exist: $BackupFile" }

$resolvedBackup = (Resolve-Path -LiteralPath $BackupFile).Path
$backupItem = Get-Item -LiteralPath $resolvedBackup
if ($backupItem.Length -le 0) { Fail "Backup file is empty: $resolvedBackup" }
if ($backupItem.Extension -ne '.dump') { Fail "Backup file must be a .dump file created by scripts/backup-postgres.ps1: $resolvedBackup" }

if (-not $Force) {
    Write-Host 'WARNING: PostgreSQL restore is destructive and may drop/recreate database objects.'
    Write-Host "Target service: $Service"
    Write-Host "Target database: $Database"
    Write-Host "Backup file: $resolvedBackup"
    $confirmation = Read-Host 'Type RESTORE to continue'
    if ($confirmation -ne 'RESTORE') { Fail 'Restore confirmation was not provided.' }
}

$compose = ComposeArgs
$containerIds = @(& docker compose @compose ps -q $Service 2>$null | Where-Object { $_ })
if ($LASTEXITCODE -ne 0) { Fail "docker compose ps failed for service '$Service'." }
if ($containerIds.Count -ne 1) { Fail "Expected exactly one '$Service' container, found $($containerIds.Count). Is the Compose project running?" }
$containerId = $containerIds[0]

$running = (& docker inspect --format '{{.State.Running}}' $containerId 2>$null)
if ($LASTEXITCODE -ne 0 -or $running -ne 'true') { Fail "PostgreSQL container '$containerId' is not running." }

Run-Docker -DockerArgs @('exec', $containerId, 'pg_isready', '-U', $Username, '-d', $Database) -Step 'PostgreSQL readiness check'

$remotePath = "/tmp/restore-$([guid]::NewGuid().ToString('N')).dump"

try {
    Run-Docker -DockerArgs @('cp', $resolvedBackup, "$containerId`:$remotePath") -Step 'docker cp restore artifact'
    Run-Docker -DockerArgs @('exec', $containerId, 'pg_restore', '--list', $remotePath) -Step 'backup format validation'
    Run-Docker -DockerArgs @('exec', $containerId, 'pg_restore', '--clean', '--if-exists', '--no-owner', '--no-acl', '--exit-on-error', '--single-transaction', '-U', $Username, '-d', $Database, $remotePath) -Step 'pg_restore'
    Write-Host "PASS: PostgreSQL restore completed from: $resolvedBackup"
} catch {
    Fail "PostgreSQL restore failed: $($_.Exception.Message)"
} finally {
    & docker exec $containerId sh -c "rm -f '$remotePath'" | Out-Null
}
