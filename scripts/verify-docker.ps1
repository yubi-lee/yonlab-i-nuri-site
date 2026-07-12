$ErrorActionPreference = "Stop"

$failed = $false
$blocked = $false
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$project = "yonlearn_verify_$(([guid]::NewGuid().ToString('N')).Substring(0, 12))"
$overrideFile = Join-Path $env:TEMP ("yonlearn-docker-override-" + [guid]::NewGuid().ToString("N") + ".yml")
$backendUrl = "http://127.0.0.1:18080"
$frontendUrl = "http://127.0.0.1:18081"
$composeArgs = @()
$started = $false

function Pass([string]$Message) { Write-Host "PASS: $Message" }
function Fail([string]$Message) { Write-Host "FAIL: $Message"; $script:failed = $true }
function Blocked([string]$Message) { Write-Host "BLOCKED: $Message"; $script:blocked = $true }

function Compose([string[]]$CommandArgs) {
    & docker compose @script:composeArgs @CommandArgs
    return $global:LASTEXITCODE
}

function Run-Step([string]$Name, [scriptblock]$Command) {
    try {
        $global:LASTEXITCODE = 0
        & $Command
        $exitCode = $global:LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = if ($?) { 0 } else { 1 } }
        if ($exitCode -eq 0) { Pass $Name } else { Fail "$Name exited with code $exitCode" }
    } catch {
        Fail "$Name threw $($_.Exception.GetType().Name): $($_.Exception.Message)"
    }
}

function Wait-ContainerReady([string]$Service, [int]$TimeoutSeconds = 180) {
    $until = (Get-Date).AddSeconds($TimeoutSeconds)
    $idDeadline = (Get-Date).AddSeconds(30)
    do {
        $id = (& docker compose @script:composeArgs ps -q $Service) 2>$null
        if ($LASTEXITCODE -eq 0 -and $id) {
            $inspectRaw = (& docker inspect $id) 2>$null
            if ($LASTEXITCODE -eq 0 -and $inspectRaw) {
                $inspect = @($inspectRaw | ConvertFrom-Json)[0]
                $status = [string]$inspect.State.Status
                $health = $null
                if ($inspect.State.PSObject.Properties.Name -contains "Health" -and $inspect.State.Health) { $health = [string]$inspect.State.Health.Status }
                if ($health) {
                    if ($health -eq "healthy") { return $true }
                    if ($health -eq "unhealthy") { return $false }
                } elseif ($status -eq "running") { return $true }
                if ($status -eq "exited" -or $status -eq "dead") { return $false }
            }
        }
        if (-not $id -and (Get-Date) -ge $idDeadline) { return $false }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $until)
    return $false
}

function Wait-HttpReady([string]$Url, [int]$TimeoutSeconds = 120) {
    $until = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 3 | Out-Null
            return $true
        } catch {
            Start-Sleep -Seconds 2
        }
    } while ((Get-Date) -lt $until)
    return $false
}

function Invoke-JsonRequest([string]$Method, [string]$Uri, $Body = $null, [hashtable]$Headers = @{}) {
    $params = @{ Method = $Method; Uri = $Uri; TimeoutSec = 15; Headers = $Headers }
    if ($null -ne $Body) {
        $params.ContentType = "application/json"
        $params.Body = ($Body | ConvertTo-Json -Depth 8)
    }
    return Invoke-RestMethod @params
}

function Get-ResourceCount {
    $response = Invoke-JsonRequest -Method GET -Uri "$backendUrl/api/v1/resources"
    if ($null -ne $response.items) { return [int]$response.items.Count }
    if ($response -is [System.Array]) { return [int]$response.Count }
    if ($null -ne $response.total) { return [int]$response.total }
    return 0
}

function Test-AdminGuard([string]$Token) {
    try {
        Invoke-WebRequest -UseBasicParsing -Method GET -Uri "$backendUrl/api/v1/admin/dashboard" -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 15 | Out-Null
        Fail "admin guard allowed a regular user"
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($status -eq 403) { Pass "Docker admin permission guard smoke" } else { Fail "admin guard returned unexpected status $status" }
    }
}

try {
    Push-Location $repoRoot

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Blocked "Docker CLI is not installed or not on PATH."
        throw "__VERIFY_STOP__"
    }

    $versionOutput = (& docker version --format "{{.Server.Version}}") 2>&1
    if ($LASTEXITCODE -ne 0) {
        Blocked "Docker daemon is unavailable: $versionOutput"
        throw "__VERIFY_STOP__"
    }
    Pass "Docker daemon reachable ($versionOutput)"

    $composeVersion = (& docker compose version --short) 2>&1
    if ($LASTEXITCODE -ne 0) {
        Blocked "Docker Compose v2 is unavailable: $composeVersion"
        throw "__VERIFY_STOP__"
    }
    Pass "Docker Compose available ($composeVersion)"

    if ((Get-NetTCPConnection -LocalPort 18080 -State Listen -ErrorAction SilentlyContinue) -or (Get-NetTCPConnection -LocalPort 18081 -State Listen -ErrorAction SilentlyContinue)) {
        Blocked "Docker verification ports 18080/18081 are already in use; no existing process was stopped."
        throw "__VERIFY_STOP__"
    }
    Pass "Docker verification ports available"

    Set-Content -LiteralPath $overrideFile -Encoding UTF8 -Value @"
services:
  backend:
    ports:
      - "18080:8000"
    environment:
      JWT_SECRET: docker-verify-secret-at-least-thirty-two-characters
      CORS_ORIGINS: http://127.0.0.1:18081,http://localhost:18081
      ADMIN_EMAIL: admin@example.com
      ADMIN_PASSWORD: AdminPass1234
  frontend:
    ports:
      - "18081:80"
"@
    $script:composeArgs = @("-p", $project, "-f", "docker-compose.yml", "-f", $overrideFile)

    Run-Step "Docker Compose config" { [void](Compose @("config", "--quiet")) }
    if ($failed) { throw "__VERIFY_STOP__" }

    Run-Step "Docker Compose build" { [void](Compose @("build")) }
    if ($failed) { throw "__VERIFY_STOP__" }

    Run-Step "Docker Compose up" { [void](Compose @("up", "-d")) }
    if ($failed) { throw "__VERIFY_STOP__" }
    $started = $true

    foreach ($service in @("postgres", "backend")) {
        if (Wait-ContainerReady $service) { Pass "Docker container ready: $service" } else { Fail "Docker container not ready: $service" }
    }
    if ($failed) { throw "__VERIFY_STOP__" }

    if (Wait-HttpReady "$backendUrl/health/ready") { Pass "Docker backend readiness endpoint" } else { Fail "Docker backend readiness endpoint timed out" }
    if (Wait-HttpReady $frontendUrl) { Pass "Docker frontend HTTP endpoint" } else { Fail "Docker frontend HTTP endpoint timed out" }
    if ($failed) { throw "__VERIFY_STOP__" }

    Run-Step "Docker Alembic current" { [void](Compose @("exec", "-T", "backend", "python", "-m", "alembic", "-c", "alembic.ini", "current")) }
    Run-Step "Docker seed first run" { [void](Compose @("exec", "-T", "backend", "python", "-m", "app.seed")) }
    Run-Step "Docker seed idempotency" { [void](Compose @("exec", "-T", "backend", "python", "-m", "app.seed")) }
    if ($failed) { throw "__VERIFY_STOP__" }

    $beforeCount = Get-ResourceCount
    Pass "Docker public API smoke (resources count=$beforeCount)"

    $email = "docker-smoke-$(([guid]::NewGuid().ToString('N')).Substring(0, 12))@example.com"
    $token = Invoke-JsonRequest -Method POST -Uri "$backendUrl/api/v1/auth/register" -Body @{ email = $email; name = "Docker Smoke"; password = "DockerSmoke!234" }
    if (-not $token.access_token) { Fail "Docker auth smoke did not return an access token" } else { Pass "Docker auth/register smoke"; Test-AdminGuard $token.access_token }
    if ($failed) { throw "__VERIFY_STOP__" }

    Run-Step "Docker stop app services before database restart" { [void](Compose @("stop", "frontend", "backend")) }
    Run-Step "Docker restart PostgreSQL" { [void](Compose @("restart", "postgres")) }
    if ($failed) { throw "__VERIFY_STOP__" }
    if (Wait-ContainerReady "postgres") { Pass "Docker container ready after restart: postgres" } else { Fail "Docker container not ready after restart: postgres" }
    Run-Step "Docker start backend after database restart" { [void](Compose @("start", "backend")) }
    if ($failed) { throw "__VERIFY_STOP__" }
    if (Wait-ContainerReady "backend") { Pass "Docker container ready after restart: backend" } else { Fail "Docker container not ready after restart: backend" }
    if (Wait-HttpReady "$backendUrl/health/ready") { Pass "Docker backend readiness after restart" } else { Fail "Docker backend readiness after restart timed out" }
    Run-Step "Docker start frontend after backend restart" { [void](Compose @("start", "frontend")) }
    if ($failed) { throw "__VERIFY_STOP__" }
    if (Wait-HttpReady $frontendUrl) { Pass "Docker frontend HTTP after restart" } else { Fail "Docker frontend HTTP after restart timed out" }
    if ($failed) { throw "__VERIFY_STOP__" }

    $afterCount = Get-ResourceCount
    if ($afterCount -ge $beforeCount) { Pass "Docker data persisted across restart (resources $beforeCount -> $afterCount)" } else { Fail "Docker resource count decreased after restart ($beforeCount -> $afterCount)" }

    $logs = (& docker compose @composeArgs logs --no-color --tail 300) 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "Docker log collection failed with code $LASTEXITCODE"
    } elseif (($logs | Select-String -Pattern "Traceback|Unhandled|panic|FATAL|CRITICAL" -CaseSensitive:$false)) {
        Fail "Docker logs contain fatal error markers"
        $logs | Select-String -Pattern "Traceback|Unhandled|panic|FATAL|CRITICAL" -CaseSensitive:$false | ForEach-Object { Write-Host $_.Line }
    } else {
        Pass "Docker logs have no fatal error markers"
    }
} catch {
    if ($_.Exception.Message -ne "__VERIFY_STOP__") { Fail "Docker verification threw $($_.Exception.GetType().Name): $($_.Exception.Message)" }
} finally {
    try {
        if ($started) {
            & docker compose @composeArgs down -v --remove-orphans | Out-Host
            if ($LASTEXITCODE -eq 0) { Pass "Docker verification cleanup" } else { Fail "Docker cleanup exited with code $LASTEXITCODE" }
        }
    } catch {
        Fail "Docker cleanup threw $($_.Exception.GetType().Name): $($_.Exception.Message)"
    }
    if (Test-Path -LiteralPath $overrideFile) { Remove-Item -LiteralPath $overrideFile -Force -ErrorAction SilentlyContinue }
    Pop-Location
}

Write-Host "RESULT: failed=$failed blocked=$blocked"
if ($failed) { exit 1 }
if ($blocked) { exit 2 }
exit 0
