# Docker verification status

Status: **ENVIRONMENT BLOCKED**

The repository contains a statically reviewed backend image, Compose health checks, migration-on-start, and `scripts/verify-docker.ps1`. Docker is not installed on this host, so image build, Compose startup, container health, and containerized migration execution are not claimed as passed.

Run on a Docker-capable host:

```powershell
.\scripts\verify-docker.ps1
```

Exit 0 is PASS; exit 2 is BLOCKED because Docker is unavailable.