# RC1 completion test report

Verified on 2026-07-12 (Asia/Seoul).

| Gate | Result | Evidence |
|---|---|---|
| Ruff | PASS | `ruff check backend`: all checks passed |
| Backend tests | PASS | 12 passed |
| Empty database migration | PASS | Integrated verify creates an isolated DB and runs Alembic upgrade |
| Seed idempotency | PASS | First run seeds; second run is idempotent |
| Frontend lint/typecheck | PASS | ESLint and TypeScript completed |
| Frontend unit tests | PASS | 4 passed |
| Production build | PASS | Vite build completed |
| Browser E2E | PASS | Playwright 14 passed across desktop/mobile/responsive projects |
| Secret scan | PASS | `scripts/verify.ps1 -SecretScanOnly` passed with `rg`; the same gate passed with `rg` removed from PATH via the PowerShell fallback |
| Docker runtime | PASS | `scripts/verify-docker.ps1` built isolated Compose services, verified health/readiness, Alembic current, seed idempotency, public/auth/admin-guard API smoke, dependency-ordered restart persistence, fatal-log scan, and cleanup |

False-positive fix: the secret scan no longer relies on `rg` being present. If `rg` is missing, `scripts/verify.ps1` performs a pruned PowerShell scan over source-controlled candidates and still emits a real PASS/FAIL result. Command-not-found and script exceptions are treated as FAIL instead of inheriting a stale `$LASTEXITCODE`.

The only remaining test warning is the external Starlette 1.3.1 TestClient/httpx compatibility warning documented in `docs/qa/testclient-warning.md`. Controllable warnings from FastAPI `on_event` and `datetime.utcnow()` are removed.
