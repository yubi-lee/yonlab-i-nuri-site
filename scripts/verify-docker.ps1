$ErrorActionPreference = "Stop"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "BLOCKED: Docker CLI is not installed or not on PATH."
    exit 2
}
docker compose config --quiet
docker compose build
docker compose up -d --wait
try {
    Invoke-RestMethod http://localhost:8000/health/ready | Out-Null
    Invoke-WebRequest http://localhost:8080 -UseBasicParsing | Out-Null
    Write-Host "PASS: Docker build, migrations, health checks, and web response succeeded."
} finally {
    docker compose down
}