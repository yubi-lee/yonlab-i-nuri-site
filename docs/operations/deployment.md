# Deployment

For production inject secrets from a secret manager, terminate TLS, use managed PostgreSQL, set an exact CORS allowlist, run Alembic before traffic, and serve immutable frontend assets through a CDN. Compose credentials are development-only.

## Seed data

Run the seed command only in the intended environment:

```powershell
Push-Location backend
..\.venv\Scripts\python.exe -m app.seed
Pop-Location
```

The RC1 seed creates YOnLab public education content pack v1 when the database is empty. It is fictional sample data for demonstration and verification, not operating content. It creates 10 categories, 45 tags, 100 resources, 18 notices, 28 articles, 45 FAQs, 15 inquiries, 4 users, and no real attachments.

The seed is intentionally idempotent under the current project policy: if categories already exist, it prints `Seed data already exists.` and does not create duplicates. For production, replace this seed pack with reviewed operating content and remove or rotate all sample accounts before opening access.

## Local Docker verification

Run the containerized deployment gate before release handoff:

```powershell
.\scripts\verify-docker.ps1
```

The script builds backend/frontend images in an isolated Compose project, starts PostgreSQL/backend/frontend on verification ports 18080/18081, checks backend and frontend readiness, verifies Alembic/seed/API smoke behavior, restarts services in dependency order, confirms data persists across restart, scans container logs for fatal markers, and removes only the resources it created.

Docker unavailable is reported as `BLOCKED` with exit code 2. A runtime, build, readiness, smoke, persistence, log, or cleanup failure is reported as `FAIL` with exit code 1.
