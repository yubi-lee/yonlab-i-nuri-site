param(
    [string]$EnvFile = ".env.production.example",
    [string]$BackendUrl = "http://localhost:8000",
    [string]$FrontendUrl = "http://localhost:8080",
    [switch]$TemplateMode,
    [switch]$SkipHttp
)

$ErrorActionPreference = "Stop"
$failed = $false
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Pass([string]$Message) { Write-Host "PASS: $Message" }
function Fail([string]$Message) { Write-Host "FAIL: $Message"; $script:failed = $true }
function Info([string]$Message) { Write-Host "INFO: $Message" }

function Read-EnvFile([string]$Path) {
    $values = @{}
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $index = $trimmed.IndexOf("=")
        if ($index -le 0) { continue }
        $key = $trimmed.Substring(0, $index).Trim()
        $value = $trimmed.Substring($index + 1).Trim()
        $values[$key] = $value
    }
    return $values
}

function Is-Placeholder([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    return $Value -match '<[^>]+>|replace-with|CHANGE_ME|__PENDING_|example\.test|localhost'
}

function Check-Http([string]$Name, [string]$Url) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5 | Out-Null
        Pass "$Name endpoint reachable"
    } catch {
        Fail "$Name endpoint is not reachable"
    }
}

Push-Location $repoRoot
try {
    $envPath = Join-Path $repoRoot $EnvFile
    if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
        Fail "environment file is missing: $EnvFile"
    } else {
        Pass "environment file exists"
        $envValues = Read-EnvFile $envPath
        $required = @(
            "APP_NAME",
            "ENVIRONMENT",
            "DATABASE_URL",
            "JWT_SECRET",
            "CORS_ORIGINS",
            "PRODUCTION_ADMIN_EMAIL",
            "PRODUCTION_ADMIN_INITIAL_PASSWORD",
            "PRODUCTION_ADMIN_NAME",
            "UPLOAD_DIR",
            "VITE_API_URL"
        )
        foreach ($key in $required) {
            if (-not $envValues.ContainsKey($key)) { Fail "required env key missing: $key" } else { Pass "required env key present: $key" }
        }

        if ($envValues.ContainsKey("ADMIN_PASSWORD") -and -not [string]::IsNullOrWhiteSpace($envValues["ADMIN_PASSWORD"])) {
            Fail "demo ADMIN_PASSWORD should stay blank outside controlled demo seed runs"
        }

        if (-not $TemplateMode) {
            foreach ($key in @("DATABASE_URL", "JWT_SECRET", "CORS_ORIGINS", "PRODUCTION_ADMIN_EMAIL", "PRODUCTION_ADMIN_INITIAL_PASSWORD", "VITE_API_URL")) {
                if ($envValues.ContainsKey($key) -and (Is-Placeholder $envValues[$key])) {
                    Fail "production env key still contains a placeholder or unsafe local value: $key"
                }
            }
        } else {
            Info "TemplateMode enabled; placeholder values are allowed for template validation."
        }

        $oldJwt = $env:JWT_SECRET
        $oldAdminEmail = $env:ADMIN_EMAIL
        $oldAdminPassword = $env:ADMIN_PASSWORD
        try {
            $env:JWT_SECRET = if ($envValues.ContainsKey("JWT_SECRET") -and $envValues["JWT_SECRET"]) { $envValues["JWT_SECRET"] } else { "template-only-secret-at-least-thirty-two-characters" }
            $env:ADMIN_EMAIL = if ($envValues.ContainsKey("ADMIN_EMAIL")) { $envValues["ADMIN_EMAIL"] } else { "" }
            $env:ADMIN_PASSWORD = if ($envValues.ContainsKey("ADMIN_PASSWORD")) { $envValues["ADMIN_PASSWORD"] } else { "" }
            & docker compose config --quiet
            if ($LASTEXITCODE -eq 0) { Pass "Docker Compose config" } else { Fail "Docker Compose config exited with code $LASTEXITCODE" }
        } finally {
            $env:JWT_SECRET = $oldJwt
            $env:ADMIN_EMAIL = $oldAdminEmail
            $env:ADMIN_PASSWORD = $oldAdminPassword
        }
    }

    foreach ($path in @("scripts/backup-postgres.ps1", "scripts/restore-postgres.ps1", "scripts/bootstrap-admin.ps1", "docs/operations/backup-restore.md", "docs/operations/admin-bootstrap.md")) {
        if (Test-Path -LiteralPath $path) { Pass "required operations artifact exists: $path" } else { Fail "required operations artifact missing: $path" }
    }

    & git check-ignore backups/probe.dump | Out-Null
    if ($LASTEXITCODE -eq 0) { Pass "backup artifacts are ignored by Git" } else { Fail "backup artifacts are not ignored by Git" }

    if ($SkipHttp) {
        Info "SkipHttp enabled; runtime endpoint checks were skipped."
    } else {
        Check-Http "backend /health" "$BackendUrl/health"
        Check-Http "backend /ready" "$BackendUrl/ready"
        Check-Http "frontend" $FrontendUrl
    }
} finally {
    Pop-Location
}

Write-Host "RESULT: failed=$failed"
if ($failed) { exit 1 }
exit 0