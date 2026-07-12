# RC1 completion test report

Verified on 2026-07-12 (Asia/Seoul).

| Gate | Result | Evidence |
|---|---|---|
| Ruff | PASS | `ruff check backend`: all checks passed |
| Backend tests | PASS | 12 passed |
| Empty database migration | PASS | Integrated verify created an isolated DB and ran Alembic upgrade |
| Seed idempotency | PASS | First run seeded; second run reported existing data |
| Frontend lint/typecheck | PASS | ESLint and TypeScript completed |
| Frontend unit tests | PASS | 4 passed |
| Production build | PASS | Vite build completed |
| Browser E2E | PASS | Playwright 14 passed across desktop/mobile/responsive projects |
| Secret scan | PASS | No private-key/API-key patterns; known test fixtures excluded and documented |
| Docker runtime | BLOCKED | Docker CLI unavailable on this host |

The only remaining test warning is the external Starlette 1.3.1 TestClient/httpx compatibility warning documented in `docs/qa/testclient-warning.md`. Controllable warnings from FastAPI `on_event` and `datetime.utcnow()` are removed.