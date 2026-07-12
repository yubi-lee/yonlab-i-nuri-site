$ErrorActionPreference = "Stop"
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "Node.js 22+ is required." }
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw "Python 3.12+ is required." }
if (-not (Test-Path ".env")) { Write-Host "Copy .env.example to .env and set JWT_SECRET and optional ADMIN credentials." }
Push-Location frontend; npm install; Pop-Location
python -m venv .venv
& .\.venv\Scripts\python.exe -m pip install -e ".\backend[dev]"
Write-Host "Setup complete."
