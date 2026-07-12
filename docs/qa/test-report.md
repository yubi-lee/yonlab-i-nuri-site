# RC1 completion test report

Verified on 2026-07-13 (Asia/Seoul).

| Gate | Result | Evidence |
|---|---|---|
| Ruff | PASS | `ruff check backend`: all checks passed |
| Backend tests | PASS | 13 passed, including YOnLab content pack v1 seed count/idempotency/clean-room regression |
| Empty database migration | PASS | Integrated verify creates an isolated DB and runs Alembic upgrade |
| Seed idempotency | PASS | First run seeds public education content pack v1; second run is idempotent |
| Frontend lint/typecheck | PASS | ESLint and TypeScript completed |
| Frontend unit tests | PASS | 4 passed |
| Production build | PASS | Vite build completed |
| Browser E2E | PASS | Playwright 14 passed across desktop/mobile/responsive projects |
| Secret scan | PASS | Repository secret scan passed |
| Docker runtime | PASS | `scripts/verify-docker.ps1` built isolated Compose services, verified health/readiness, Alembic current, seed idempotency, public/auth/admin-guard API smoke, dependency-ordered restart persistence, fatal-log scan, and cleanup |

Content pack v1 evidence: empty seed creates 10 categories, 45 tags, 100 resources, 18 notices, 28 articles, 45 FAQs, 15 inquiries, 4 users, and 0 real attachments. The pack is YOnLab-authored fictional sample content and does not use i-Nuri original text, images, attachments, resource names, unique wording, colors, layout, or file names.

The only remaining test warning is the external Starlette 1.3.1 TestClient/httpx compatibility warning documented in `docs/qa/testclient-warning.md`. Controllable warnings from FastAPI `on_event` and `datetime.utcnow()` are removed.
