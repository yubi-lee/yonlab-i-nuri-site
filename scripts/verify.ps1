param([switch]$SecretScanOnly)

$ErrorActionPreference = "Stop"
$failed = $false
$blocked = $false
$started = @()
$oldDatabase = $env:DATABASE_URL
$oldCors = $env:CORS_ORIGINS
$oldApi = $env:VITE_API_URL
$oldPw = $env:PLAYWRIGHT_BASE_URL
$oldAdminEmail = $env:ADMIN_EMAIL
$oldAdminPassword = $env:ADMIN_PASSWORD
$oldJwt = $env:JWT_SECRET

function Set-Failed([string]$Message) {
    Write-Host "FAIL: $Message"
    $script:failed = $true
}

function Set-Blocked([string]$Message) {
    Write-Host "BLOCKED: $Message"
    $script:blocked = $true
}

function Gate([string]$Name, [scriptblock]$Command) {
    try {
        $global:LASTEXITCODE = 0
        & $Command
        $exitCode = $global:LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = if ($?) { 0 } else { 1 } }
        if ($exitCode -eq 0) { Write-Host "PASS: $Name" } else { Set-Failed "$Name exited with code $exitCode" }
    } catch {
        Set-Failed "$Name threw $($_.Exception.GetType().Name): $($_.Exception.Message)"
    }
}

function PortBusy([int]$Port) { return [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) }
function StopTree([int]$ProcessId) {
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue
    foreach ($child in $children) { StopTree ([int]$child.ProcessId) }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}
function WaitReady([string]$Url, [int]$TimeoutSeconds = 45) {
    $until = (Get-Date).AddSeconds($TimeoutSeconds)
    do { try { Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2 | Out-Null; return $true } catch { Start-Sleep -Milliseconds 500 } } while ((Get-Date) -lt $until)
    return $false
}
function Mask-SecretLine([string]$Line) {
    $masked = $Line -replace '(BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)', '[REDACTED-PRIVATE-KEY]'
    $masked = $masked -replace 'AKIA[0-9A-Z]{16}', '[REDACTED-AWS-KEY]'
    $masked = $masked -replace 'sk-[A-Za-z0-9]{20,}', '[REDACTED-API-KEY]'
    $masked = $masked -replace '(?i)((access|refresh|reset)[_-]?token\s*[=:]\s*[''"]?)[A-Za-z0-9._\-]{24,}', '$1[REDACTED-TOKEN]'
    $masked = $masked -replace '(?i)((password|secret|api[_-]?key)\s*[=:]\s*[''"]?)[^''"\s]{12,}', '$1[REDACTED-SECRET]'
    return $masked
}
function Is-SkippedSecretPath([string]$RelativePath) {
    $normalized = $RelativePath -replace '\\', '/'
    $skipPrefixes = @('.git/', '.venv/', 'venv/', 'backend/.venv/', 'backend/venv/', 'frontend/node_modules/', 'frontend/dist/', 'playwright-report/', 'test-results/', 'storage/', 'backend/storage/', 'reference/inuri-public/raw/', '.pytest_cache/', '.ruff_cache/', '__pycache__/')
    foreach ($prefix in $skipPrefixes) { if ($normalized.StartsWith($prefix)) { return $true } }
    if ($normalized -match '(^|/)package-lock\.json$') { return $true }
    if ($normalized -match '(^|/)\.env$') { return $true }
    if ($normalized -match '\.(db|sqlite|sqlite3|png|jpg|jpeg|gif|webp|ico|pdf|zip|gz|woff|woff2|ttf|eot|exe|dll|pyc|pyd)$') { return $true }
    return $false
}
function Get-SecretPatterns {
    return @(
        'BEGIN (RSA|OPENSSH|EC) PRIVATE KEY',
        'AKIA[0-9A-Z]{16}',
        'sk-[A-Za-z0-9]{20,}',
        'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}',
        '(?i)(access|refresh|reset)[_-]?token\s*[=:]\s*[''"]?[A-Za-z0-9._\-]{32,}',
        '(?i)(jwt[_-]?secret|secret[_-]?key|api[_-]?key|password)\s*[=:]\s*[''"][^''"]{32,}[''"]'
    )
}
function Is-AllowedSecretScanLine([string]$Line) {
    $allowed = @(
        'verify-only-secret-at-least-thirty-two-characters',
        'docker-verify-secret-at-least-thirty-two-characters',
        'Set JWT_SECRET in .env',
        'DockerSmoke!234',
        'AdminPass1234',
        'AdminPass!123',
        'os.getenv("ADMIN_PASSWORD")',
        '$oldAdminPassword'
    )
    foreach ($item in $allowed) { if ($Line.Contains($item)) { return $true } }
    return $false
}
function Get-SecretScanFiles([string]$Root) {
    foreach ($child in Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop) {
        $relative = Resolve-Path -LiteralPath $child.FullName -Relative
        $relative = $relative.TrimStart('.', '\', '/')
        if ($child.PSIsContainer) {
            if (Is-SkippedSecretPath ($relative + '/')) { continue }
            Get-SecretScanFiles $child.FullName
        } else {
            if (Is-SkippedSecretPath $relative) { continue }
            $child
        }
    }
}
function Invoke-SecretScanWithPowerShell {
    $patterns = Get-SecretPatterns
    $hits = @()
    $files = Get-SecretScanFiles (Resolve-Path .)
    foreach ($file in $files) {
        $relative = Resolve-Path -LiteralPath $file.FullName -Relative
        $relative = $relative.TrimStart('.', '\', '/')
        if (Is-SkippedSecretPath $relative) { continue }
        try {
            $stream = [System.IO.File]::OpenRead($file.FullName)
            try {
                $buffer = New-Object byte[] ([Math]::Min(4096, [int]$stream.Length))
                [void]$stream.Read($buffer, 0, $buffer.Length)
                if ($buffer -contains 0) { continue }
            } finally { $stream.Dispose() }
            $lineNumber = 0
            foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
                $lineNumber++
                foreach ($pattern in $patterns) {
                    if ($line -match $pattern -and -not (Is-AllowedSecretScanLine $line)) { $hits += [pscustomobject]@{ Path = $relative; Line = $lineNumber; Text = (Mask-SecretLine $line) }; break }
                }
            }
        } catch { throw "secret scan could not read ${relative}: $($_.Exception.Message)" }
    }
    return $hits
}
function Invoke-SecretScan {
    try {
        $rg = Get-Command rg -ErrorAction SilentlyContinue
        if ($rg) {
            $pattern = (Get-SecretPatterns) -join '|'
            $args = @('-n', '--hidden', '--glob', '!frontend/node_modules/**', '--glob', '!frontend/dist/**', '--glob', '!venv/**', '--glob', '!.venv/**', '--glob', '!playwright-report/**', '--glob', '!test-results/**', '--glob', '!storage/**', '--glob', '!backend/storage/**', '--glob', '!reference/inuri-public/raw/**', '--glob', '!package-lock.json', '--glob', '!.env', '--glob', '!.git/**', $pattern, '.')
            $output = & $rg.Source @args 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0) { $findings = @($output | Where-Object { -not (Is-AllowedSecretScanLine ([string]$_)) }); if ($findings.Count -eq 0) { Write-Host "PASS: secret scan"; return }; Write-Host "FAIL: secret pattern detected"; foreach ($line in $findings) { Write-Host (Mask-SecretLine ([string]$line)) }; $script:failed = $true; return }
            if ($exitCode -eq 1) { Write-Host "PASS: secret scan"; return }
            Set-Failed "secret scan tool rg exited with code $exitCode"; foreach ($line in $output) { Write-Host $line }; return
        }
        Write-Host "INFO: rg not found; using PowerShell secret scan fallback."
        $hits = Invoke-SecretScanWithPowerShell
        if ($hits.Count -gt 0) { Write-Host "FAIL: secret pattern detected"; foreach ($hit in $hits) { Write-Host "$($hit.Path):$($hit.Line):$($hit.Text)" }; $script:failed = $true } else { Write-Host "PASS: secret scan" }
    } catch { Set-Failed "secret scan failed: $($_.Exception.Message)" }
}

if ($SecretScanOnly) {
    Invoke-SecretScan
    Write-Host "RESULT: failed=$failed blocked=$blocked"
    if ($failed) { exit 1 }
    exit 0
}

try {
    $required = @(".\.venv\Scripts\ruff.exe", ".\.venv\Scripts\python.exe", "frontend\node_modules\.bin\vite.cmd", "frontend\node_modules\.bin\playwright.cmd", ".\scripts\verify-design-docs.ps1")
    foreach ($path in $required) { if (-not (Test-Path -LiteralPath $path)) { Set-Failed "missing required command $path" } }
    if ($failed) { throw "required command check failed" }
    Gate "production target design documentation" { & .\scripts\verify-design-docs.ps1 }
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
    try { Gate "Seed first run" { & ..\.venv\Scripts\python.exe -m app.seed }; Gate "Seed idempotency" { & ..\.venv\Scripts\python.exe -m app.seed } } finally { Pop-Location }
    if (Test-Path -LiteralPath $migrationDb) { Remove-Item -LiteralPath $migrationDb -Force }
    $backendPort = 8000; $frontendPort = 5173
    if (PortBusy $backendPort -or PortBusy $frontendPort) { Write-Host "INFO: default E2E port occupied; selecting isolated ports without stopping existing processes."; $backendPort = 18000; $frontendPort = 15173; if (PortBusy $backendPort -or PortBusy $frontendPort) { Set-Blocked "required E2E ports are occupied"; throw "E2E ports blocked" } }
    $e2eDb = Join-Path $env:TEMP ("yonlearn-e2e-" + [guid]::NewGuid().ToString("N") + ".db")
    $env:DATABASE_URL = "sqlite:///$e2eDb"; $env:JWT_SECRET = "verify-only-secret-at-least-thirty-two-characters"; $env:CORS_ORIGINS = "http://127.0.0.1:$frontendPort"; $env:ADMIN_EMAIL = "admin@example.com"; $env:ADMIN_PASSWORD = "AdminPass1234"
    Push-Location backend
    try { & ..\.venv\Scripts\python.exe -m app.seed | Out-Host } finally { Pop-Location }
    $backendLog = Join-Path $env:TEMP "yonlearn-verify-backend.log"; $backendErr = Join-Path $env:TEMP "yonlearn-verify-backend.err.log"; $frontendLog = Join-Path $env:TEMP "yonlearn-verify-frontend.log"; $frontendErr = Join-Path $env:TEMP "yonlearn-verify-frontend.err.log"
    $backend = Start-Process -FilePath (Resolve-Path .\.venv\Scripts\python.exe) -WorkingDirectory (Resolve-Path backend) -ArgumentList "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", $backendPort -RedirectStandardOutput $backendLog -RedirectStandardError $backendErr -PassThru
    $started += $backend
    $env:VITE_API_URL = "http://127.0.0.1:$backendPort/api/v1"; $env:PLAYWRIGHT_BASE_URL = "http://127.0.0.1:$frontendPort"
    $frontend = Start-Process -FilePath "npm.cmd" -WorkingDirectory (Resolve-Path frontend) -ArgumentList "run", "dev", "--", "--host", "127.0.0.1", "--port", $frontendPort -RedirectStandardOutput $frontendLog -RedirectStandardError $frontendErr -PassThru
    $started += $frontend
    if (-not (WaitReady "http://127.0.0.1:$backendPort/health/ready") -or -not (WaitReady "http://127.0.0.1:$frontendPort")) { Set-Failed "E2E readiness timeout" } else { Gate "Playwright E2E" { npm run e2e --prefix frontend } }
    Invoke-SecretScan
    git status --short
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        try {
            $global:LASTEXITCODE = 0
            & "$PSScriptRoot\verify-docker.ps1"
            $dockerExit = $global:LASTEXITCODE
            if ($dockerExit -eq 0) {
                Write-Host "PASS: Docker integration"
            } elseif ($dockerExit -eq 2) {
                Set-Blocked "Docker integration reported BLOCKED"
            } else {
                Set-Failed "Docker integration exited with code $dockerExit"
            }
        } catch {
            Set-Failed "Docker integration threw $($_.Exception.GetType().Name): $($_.Exception.Message)"
        }
    } else { Set-Blocked "Docker integration (Docker CLI unavailable)" }
} catch { if (-not $failed -and -not $blocked) { Set-Failed $_.Exception.Message } } finally {
    foreach ($process in $started) { if ($process -and -not $process.HasExited) { StopTree $process.Id } }
    $env:DATABASE_URL = $oldDatabase; $env:CORS_ORIGINS = $oldCors; $env:VITE_API_URL = $oldApi; $env:PLAYWRIGHT_BASE_URL = $oldPw; $env:ADMIN_EMAIL = $oldAdminEmail; $env:ADMIN_PASSWORD = $oldAdminPassword; $env:JWT_SECRET = $oldJwt
    if ($e2eDb -and (Test-Path -LiteralPath $e2eDb)) { Remove-Item -LiteralPath $e2eDb -Force -ErrorAction SilentlyContinue }
    if ($migrationDb -and (Test-Path -LiteralPath $migrationDb)) { Remove-Item -LiteralPath $migrationDb -Force -ErrorAction SilentlyContinue }
}
Write-Host "RESULT: failed=$failed blocked=$blocked"
if ($failed) { exit 1 }
exit 0
