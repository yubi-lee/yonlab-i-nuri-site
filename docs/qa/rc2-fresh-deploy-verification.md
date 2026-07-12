# RC2 fresh deploy verification

This procedure describes how to reproduce a fresh `v0.1.0-rc2` verification from a clean directory under `D:\Deploy` without moving or overwriting the existing development checkout.

## Preconditions

- Windows PowerShell.
- Git installed.
- Docker Desktop installed and running.
- Network access to package and container registries when rebuilding images.
- Access to the YOnLearn Hub repository remote.

## Procedure

1. Prepare a clean deploy directory:

```powershell
New-Item -ItemType Directory -Force -Path D:\Deploy | Out-Null
Set-Location D:\Deploy
```

2. Clone the repository into a fresh folder:

```powershell
git clone <repository-url> yonlab-i-nuri-site-rc2
Set-Location D:\Deploy\yonlab-i-nuri-site-rc2
```

3. Fetch tags and check out the RC2 tag:

```powershell
git fetch --tags
git checkout v0.1.0-rc2
```

4. Confirm tag and commit state:

```powershell
git status --short
git log --oneline --decorate -5
git tag --list "v0.1.0-rc*"
git show --no-patch --decorate v0.1.0-rc2
```

5. Install or restore local dependencies as required by the repository setup. If the existing project-provisioned `.venv` and `frontend/node_modules` are not present in the fresh clone, create them before running the local gate.

6. Run the full local quality gate:

```powershell
.\scripts\verify.ps1
```

Expected final line:

```text
RESULT: failed=False blocked=False
```

7. Run the Docker verification gate:

```powershell
.\scripts\verify-docker.ps1
```

Expected final line:

```text
RESULT: failed=False blocked=False
```

8. Optional manual Docker smoke:

```powershell
$env:JWT_SECRET = "replace-with-a-strong-local-secret"
$env:ADMIN_EMAIL = "admin@example.com"
$env:ADMIN_PASSWORD = "replace-with-a-local-admin-password"
docker compose up -d --build
Invoke-WebRequest -UseBasicParsing -Uri http://localhost:8080 -TimeoutSec 10
```

The frontend should respond with HTTP 200 at `http://localhost:8080`.

9. Clean up the manual Compose stack if started:

```powershell
docker compose down -v --remove-orphans
```

## Evidence to record

- `git show --no-patch --decorate v0.1.0-rc2` output.
- Final `RESULT` line from `scripts/verify.ps1`.
- Final `RESULT` line from `scripts/verify-docker.ps1`.
- `http://localhost:8080` HTTP status if manual Compose smoke is performed.
- Final `git status --short` output.

## Notes

- Do not move or overwrite `v0.1.0-rc1`.
- Do not push from this verification procedure unless release owners explicitly approve it.
- The seed content is fictional YOnLab sample data and must be replaced or reviewed before production use.
