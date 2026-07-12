# Docker verification report

Status: **PASS**

Verified on 2026-07-12 (Asia/Seoul) with Docker Engine 29.6.1 and Docker Compose 5.2.0.

Command:

```powershell
.\scripts\verify-docker.ps1
```

Evidence summary:

| Check | Result |
|---|---|
| Docker daemon and Compose availability | PASS |
| Isolated Compose project and ports 18080/18081 | PASS |
| Compose config validation | PASS |
| Backend and frontend image build | PASS |
| PostgreSQL/backend/frontend startup | PASS |
| Backend `/health/ready` | PASS |
| Frontend HTTP response | PASS |
| Containerized Alembic current check | PASS |
| Seed first run and idempotent second run | PASS |
| Public resources API smoke | PASS (`resources count=12`) |
| Auth register smoke | PASS |
| Regular-user admin permission guard | PASS |
| Dependency-ordered restart and readiness recovery | PASS |
| Data persistence across restart | PASS (`resources 12 -> 12`) |
| Fatal log marker scan | PASS |
| Verification cleanup | PASS |

Final script result:

```text
RESULT: failed=False blocked=False
```

The verifier uses a unique Compose project name and a temporary override file, so it does not stop user-run containers. It only removes the containers, network, volume, and temporary override created for the verification run.

If Docker is missing or the daemon is unavailable, `scripts/verify-docker.ps1` exits with code 2 and prints `BLOCKED`. The parent `scripts/verify.ps1` treats that as BLOCKED, not PASS.
