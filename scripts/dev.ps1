$ErrorActionPreference = "Stop"
$backend = Start-Process -FilePath ".\.venv\Scripts\python.exe" -ArgumentList "-m","uvicorn","app.main:app","--reload","--app-dir","backend" -PassThru -WindowStyle Hidden
$frontend = Start-Process -FilePath "npm.cmd" -ArgumentList "run","dev","--prefix","frontend" -PassThru -WindowStyle Hidden
Write-Host "Backend PID $($backend.Id), frontend PID $($frontend.Id). Press Ctrl+C to stop."
try { Wait-Process -Id $backend.Id,$frontend.Id } finally { Stop-Process -Id $backend.Id,$frontend.Id -Force -ErrorAction SilentlyContinue }
