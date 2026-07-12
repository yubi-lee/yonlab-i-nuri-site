param(
    [string]$OutputDir = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')) 'backups'),
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

$compose = ComposeArgs
$containerIds = @(& docker compose @compose ps -q $Service 2>$null | Where-Object { $_ })
if ($LASTEXITCODE -ne 0) { Fail "docker compose ps failed for service '$Service'." }
if ($containerIds.Count -ne 1) { Fail "Expected exactly one '$Service' container, found $($containerIds.Count). Is the Compose project running?" }
$containerId = $containerIds[0]

$running = (& docker inspect --format '{{.State.Running}}' $containerId 2>$null)
if ($LASTEXITCODE -ne 0 -or $running -ne 'true') { Fail "PostgreSQL container '$containerId' is not running." }

Run-Docker -DockerArgs @('exec', $containerId, 'pg_isready', '-U', $Username, '-d', $Database) -Step 'PostgreSQL readiness check'

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$fileName = "yonlearn-postgres-$timestamp.dump"
$null = New-Item -ItemType Directory -Force -Path $OutputDir
$outputRoot = (Resolve-Path -LiteralPath $OutputDir).Path
$outputPath = Join-Path $outputRoot $fileName
$partialPath = "$outputPath.partial"
$remotePath = "/tmp/$fileName"

if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Force }
if (Test-Path -LiteralPath $outputPath) { Fail "Backup output already exists: $outputPath" }

try {
    Run-Docker -DockerArgs @('exec', $containerId, 'sh', '-c', "rm -f '$remotePath' && pg_dump -U '$Username' -d '$Database' --format=custom --no-owner --no-acl --file '$remotePath' && test -s '$remotePath'") -Step 'pg_dump'
    Run-Docker -DockerArgs @('cp', "$containerId`:$remotePath", $partialPath) -Step 'docker cp backup artifact'
    if (-not (Test-Path -LiteralPath $partialPath)) { Fail 'Backup artifact was not copied to the host.' }
    if ((Get-Item -LiteralPath $partialPath).Length -le 0) { Fail 'Backup artifact is empty.' }
    Move-Item -LiteralPath $partialPath -Destination $outputPath -Force
    Write-Host "PASS: PostgreSQL backup created: $outputPath"
} catch {
    if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue }
    Fail "PostgreSQL backup failed: $($_.Exception.Message)"
} finally {
    & docker exec $containerId sh -c "rm -f '$remotePath'" | Out-Null
}
