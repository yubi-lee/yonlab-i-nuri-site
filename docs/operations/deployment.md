# Deployment

For production inject secrets from a secret manager, terminate TLS, use managed PostgreSQL, set an exact CORS allowlist, run Alembic before traffic, and serve immutable frontend assets through a CDN. Compose credentials are development-only.

## Local Docker verification

Run the containerized deployment gate before release handoff:

```powershell
.\scripts\verify-docker.ps1
```

The script builds backend/frontend images in an isolated Compose project, starts PostgreSQL/backend/frontend on verification ports 18080/18081, checks backend and frontend readiness, verifies Alembic/seed/API smoke behavior, restarts services in dependency order, confirms data persists across restart, scans container logs for fatal markers, and removes only the resources it created.

Docker unavailable is reported as `BLOCKED` with exit code 2. A runtime, build, readiness, smoke, persistence, log, or cleanup failure is reported as `FAIL` with exit code 1.
