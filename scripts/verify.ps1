$ErrorActionPreference = "Continue"
$failed = $false
$blocked = $false
$started = @()
$oldDatabase = $env:DATABASE_URL
$oldCors = $env:CORS_ORIGINS
$oldApi = $env:VITE_API_URL
$oldPw = $env:PLAYWRIGHT_BASE_URL
$oldAdminEmail = $env:ADMIN_EMAIL
$oldAdminPassword = $env:ADMIN_PASSWORD
function Gate([string]$Name, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -eq 0) { Write-Host "PASS: $Name" } else { Write-Host "FAIL: $Name"; $script:failed = $true }
}
function PortBusy([int]$Port) { return [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) }
function StopTree([int]$ProcessId) {
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue
    foreach ($child in $children) { StopTree ([int]$child.ProcessId) }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}
function WaitReady([string]$Url, [int]$TimeoutSeconds = 45) {
    $until = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try { Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2 | Out-Null; return $true } catch { Start-Sleep -Milliseconds 500 }
    } while ((Get-Date) -lt $until)
    return $false
}
try {
    $required = @(".\.venv\Scripts\ruff.exe", ".\.venv\Scripts\python.exe", "frontend\node_modules\.bin\vite.cmd", "frontend\node_modules\.bin\playwright.cmd")
    foreach ($path in $required) { if (-not (Test-Path -LiteralPath $path)) { Write-Host "FAIL: missing required command $path"; $failed = $true } }
    Write-Host "RESULT: failed=$failed blocked=$blocked"
if ($failed) { exit 1 }

    Gate "Ruff" { & .\.venv\Scripts\ruff.exe check backend }
    Gate "Pytest" { & .\.venv\Scripts\python.exe -m pytest backend\tests -q }
    Gate "ESLint" { npm run lint --prefix frontend }
    Gate "TypeScript" { npm run typecheck --prefix frontend }
    Gate "Vitest" { npm run test --prefix frontend }
    Gate "Vite production build" { npm run build --prefix frontend }

    $migrationDb = Join-Path $env:TEMP ("yonlearn-migration-" + [guid]::NewGuid().ToString("N") + ".db")
    $env:DATABASE_URL = "sqlite:///$migrationDb"
    Push-Location backend
    try { Gate "Empty DB Alembic migration" { & ..\.venv\Scripts\python.exe -m alembic -c alembic.ini upgrade head } } finally { Pop-Location }
    Push-Location backend
    try {
        Gate "Seed first run" { & ..\.venv\Scripts\python.exe -m app.seed }
        Gate "Seed idempotency" { & ..\.venv\Scripts\python.exe -m app.seed }
    } finally { Pop-Location }
    if (Test-Path -LiteralPath $migrationDb) { Remove-Item -LiteralPath $migrationDb -Force }

    $backendPort = 8000
    $frontendPort = 5173
    if (PortBusy $backendPort -or PortBusy $frontendPort) {
        Write-Host "INFO: default E2E port occupied; selecting isolated ports without stopping existing processes."
        $backendPort = 18000
        $frontendPort = 15173
        if (PortBusy $backendPort -or PortBusy $frontendPort) { Write-Host "BLOCKED: required E2E ports are occupied."; $blocked = $true; exit 2 }
    }
    $e2eDb = Join-Path $env:TEMP ("yonlearn-e2e-" + [guid]::NewGuid().ToString("N") + ".db")
    $env:DATABASE_URL = "sqlite:///$e2eDb"
    $env:JWT_SECRET = "verify-only-secret-at-least-thirty-two-characters"
    $env:CORS_ORIGINS = "http://127.0.0.1:$frontendPort"
    $env:ADMIN_EMAIL = "admin@example.com"
    $env:ADMIN_PASSWORD = "AdminPass1234"
    Push-Location backend
    try { & ..\.venv\Scripts\python.exe -m app.seed | Out-Host } finally { Pop-Location }
    $backendLog = Join-Path $env:TEMP "yonlearn-verify-backend.log"
    $backendErr = Join-Path $env:TEMP "yonlearn-verify-backend.err.log"
    $frontendLog = Join-Path $env:TEMP "yonlearn-verify-frontend.log"
    $frontendErr = Join-Path $env:TEMP "yonlearn-verify-frontend.err.log"
    $backend = Start-Process -FilePath (Resolve-Path .\.venv\Scripts\python.exe) -WorkingDirectory (Resolve-Path backend) -ArgumentList "-m","uvicorn","app.main:app","--host","127.0.0.1","--port",$backendPort -RedirectStandardOutput $backendLog -RedirectStandardError $backendErr -PassThru
    $started += $backend
    $env:VITE_API_URL = "http://127.0.0.1:$backendPort/api/v1"
    $env:PLAYWRIGHT_BASE_URL = "http://127.0.0.1:$frontendPort"
    $frontend = Start-Process -FilePath "npm.cmd" -WorkingDirectory (Resolve-Path frontend) -ArgumentList "run","dev","--","--host","127.0.0.1","--port",$frontendPort -RedirectStandardOutput $frontendLog -RedirectStandardError $frontendErr -PassThru
    $started += $frontend
    if (-not (WaitReady "http://127.0.0.1:$backendPort/health/ready") -or -not (WaitReady "http://127.0.0.1:$frontendPort")) { Write-Host "FAIL: E2E readiness timeout"; $failed = $true } else { Gate "Playwright E2E" { npm run e2e --prefix frontend } }

    $secretHits = rg -n --hidden -g '!frontend/node_modules/**' -g '!frontend/dist/**' -g '!frontend/e2e/**' -g '!backend/tests/**' -g '!backend/app/seed.py' -g '!README.md' -g '!scripts/verify.ps1' -g '!.git/**' '(BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|AdminPass1234|DemoUser!234)' .
    if ($LASTEXITCODE -eq 0) { Write-Host "FAIL: secret pattern detected"; $failed = $true } else { Write-Host "PASS: secret scan" }
    git status --short
    if (Get-Command docker -ErrorAction SilentlyContinue) { Gate "Docker integration" { & "$PSScriptRoot\verify-docker.ps1" } } else { Write-Host "BLOCKED: Docker integration (Docker CLI unavailable)"; $blocked = $true }
} finally {
    foreach ($process in $started) { if ($process -and -not $process.HasExited) { StopTree $process.Id } }
    $env:DATABASE_URL = $oldDatabase; $env:CORS_ORIGINS = $oldCors; $env:VITE_API_URL = $oldApi; $env:PLAYWRIGHT_BASE_URL = $oldPw
    $env:ADMIN_EMAIL = $oldAdminEmail; $env:ADMIN_PASSWORD = $oldAdminPassword
    if (Test-Path -LiteralPath $e2eDb) { Remove-Item -LiteralPath $e2eDb -Force -ErrorAction SilentlyContinue }
}
Write-Host "RESULT: failed=$failed blocked=$blocked"
if ($failed) { exit 1 }
if ($blocked) { exit 0 }
exit 0