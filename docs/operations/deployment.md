# Deployment

For production, inject secrets from a protected secret manager or server environment file, terminate TLS at the selected reverse proxy or load balancer, use PostgreSQL, set an exact CORS allowlist, run Alembic before traffic, and serve immutable frontend assets through the web image or a future CDN. Compose credentials are development defaults unless replaced by protected production values.

## Environment files

Use `.env.example` for local development and `.env.production.example` as the production checklist template. The production template contains placeholders only; never commit a filled production `.env` file.

Minimum production values to provide before external access:

- `DATABASE_URL`: PostgreSQL URL for the intended production database.
- `JWT_SECRET`: high-entropy signing secret, at least 32 random characters.
- `CORS_ORIGINS`: exact HTTPS frontend origin.
- `PRODUCTION_ADMIN_EMAIL`, `PRODUCTION_ADMIN_INITIAL_PASSWORD`, `PRODUCTION_ADMIN_NAME`: one-time administrator bootstrap values.
- `VITE_API_URL`: public API base URL used by the frontend build/runtime.
- `BACKUP_DESTINATION`, `BACKUP_RETENTION_DAYS`, `BACKUP_ENCRYPTION_REQUIRED`: backup policy placeholders until off-host storage is selected.
- `EMAIL_PROVIDER`, `EMAIL_FROM_ADDRESS`, `EMAIL_PROVIDER_API_KEY`: keep pending/blank until real email flows are enabled.

Validate the template or a server env file without printing secret values:

```powershell
.\scripts\verify-production-readiness.ps1 -TemplateMode -SkipHttp
.\scripts\verify-production-readiness.ps1 -EnvFile .env -BackendUrl http://localhost:8000 -FrontendUrl http://localhost:8080
```

## Cloud VM + Docker Compose handoff

A first production candidate can run on a Cloud VM with Docker Compose after the hosting decision is approved.

1. Clone the repository and check out `feat/production-readiness` or the approved release tag/commit.
2. Copy `.env.production.example` to the server's protected `.env` location and replace placeholders outside Git.
3. Confirm the production env file with `scripts/verify-production-readiness.ps1`.
4. Build images:

   ```powershell
   docker compose build
   ```

5. Start PostgreSQL first if performing manual migration/bootstrap checks:

   ```powershell
   docker compose up -d postgres
   docker compose run --rm backend python -m alembic -c alembic.ini upgrade head
   ```

6. For demo environments only, run `python -m app.seed`. For production, do not rely on demo seed admin; use the production bootstrap below.
7. Start or restart the application services:

   ```powershell
   docker compose up -d
   ```

8. Verify runtime health:

   ```powershell
   Invoke-WebRequest http://localhost:8000/health
   Invoke-WebRequest http://localhost:8000/ready
   Invoke-WebRequest http://localhost:8080
   ```

9. Bootstrap or rotate the first real administrator:

   ```powershell
   .\scripts\bootstrap-admin.ps1
   ```

10. Create a database backup and copy it to the approved off-host destination:

    ```powershell
    .\scripts\backup-postgres.ps1
    ```

11. Record the deployment commit, migration revision, env source, administrator bootstrap result, backup file timestamp, and health-check results in the operations log.

## Seed data

Run the seed command only in the intended demo or verification environment:

```powershell
Push-Location backend
..\.venv\Scripts\python.exe -m app.seed
Pop-Location
```

The RC2 seed creates YOnLab public education content pack v1 when the database is empty. It is fictional sample data for demonstration and verification, not operating content. It creates 10 categories, 45 tags, 100 resources, 18 notices, 28 articles, 45 FAQs, 15 inquiries, 4 users, and no real attachments.

The seed is intentionally idempotent under the current project policy: if categories already exist, it prints `Seed data already exists.` and does not create duplicates. For production, replace this seed pack with reviewed operating content and remove, disable, or isolate all sample accounts before opening access.

## Production administrator bootstrap

Use [Production administrator bootstrap](admin-bootstrap.md) to create or rotate the first real operator account. The `ADMIN_EMAIL` and `ADMIN_PASSWORD` settings are for demo seed data only; production bootstrap uses `PRODUCTION_ADMIN_EMAIL`, `PRODUCTION_ADMIN_INITIAL_PASSWORD`, and `PRODUCTION_ADMIN_NAME`.

## PostgreSQL backup and restore

Use [Backup and restore](backup-restore.md) for the Docker Compose PostgreSQL runbook.

```powershell
.\scripts\backup-postgres.ps1
.\scripts\restore-postgres.ps1 -BackupFile .\backups\<backup-file>.dump
```

Restore is destructive and requires either the interactive `RESTORE` confirmation or an explicit `-Force` flag. Run restore verification in an isolated Compose project or fresh deploy environment, not against an operator's active local project.

## Local Docker verification

Run the containerized deployment gate before release handoff:

```powershell
.\scripts\verify-docker.ps1
```

The script builds backend/frontend images in an isolated Compose project, starts PostgreSQL/backend/frontend on verification ports 18080/18081, checks backend and frontend readiness, verifies Alembic/seed/API smoke behavior, restarts services in dependency order, confirms data persists across restart, scans container logs for fatal markers, and removes only the resources it created.

Docker unavailable is reported as `BLOCKED` with exit code 2. A runtime, build, readiness, smoke, persistence, log, or cleanup failure is reported as `FAIL` with exit code 1.

## Rollback

Use the last known-good commit or tag, restore the previous protected env file if configuration changed, and verify `/health`, `/ready`, login, resource search, resource detail, admin dashboard, inquiry flow, and backup age after rollback. Database restore is the highest-risk rollback level and must follow [Backup and restore](backup-restore.md).