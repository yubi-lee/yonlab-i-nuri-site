# YOnLearn Hub

YOnLab? ???AI ??? ???? ???? ??? ? ?? ??? ??? ??? ?? 1? ?????. React/TypeScript ?????? FastAPI/PostgreSQL ???, ??? ?? ??? ?????.

## ?? ?? (PowerShell)

```powershell
Copy-Item .env.example .env
.\scripts\setup.ps1
.\scripts\seed.ps1
.\scripts\dev.ps1
```

? http://localhost:5173 ? API http://localhost:8000 ? Swagger http://localhost:8000/docs

?? ?? ???: `learner@example.test` / `DemoUser!234`. ???? `.env`? `ADMIN_EMAIL`, `ADMIN_PASSWORD`? ?? ?? ?? ?????.

## Docker

```powershell
docker compose up --build
docker compose exec backend python -m app.seed
```

?? http://localhost:8080 ?? ????.

## ??

```powershell
.\scripts\test.ps1
.\scripts\verify.ps1
```

E2E? ? ?? ?? ? `npm run e2e --prefix frontend`? ?????. ??? ??? `docs/qa/test-report.md`? ?????.

## Production Target Design

The production-ready target system design starts at [docs/design/README.md](docs/design/README.md). It defines the intended architecture, requirements, CDD/ICD set, data model, security, operations, verification strategy, and CDR package.

Validate the design documentation with:

```powershell
.\scripts\verify-design-docs.ps1
```
## Health endpoints

The backend exposes liveness and readiness aliases for local and Docker checks:

```powershell
Invoke-WebRequest http://localhost:8000/health
Invoke-WebRequest http://localhost:8000/ready
Invoke-WebRequest http://localhost:8000/health/live
Invoke-WebRequest http://localhost:8000/health/ready
```

Use `docs/operations/deployment.md` and `.env.production.example` for the production-readiness handoff. Filled production `.env` files and real secrets must stay outside Git.
