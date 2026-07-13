# YOnLearn Hub Production Readiness RC

Date: 2026-07-13

## Baseline

- Base release tag: `v0.1.0-rc2`
- Branch: `feat/production-readiness`
- Remote: `origin https://github.com/yubi-lee/yonlab-i-nuri-site.git`
- Purpose: prepare the RC2 application for a Cloud VM + Docker Compose production-readiness handoff without performing an external production deployment.

## Included branch commits

| Commit | Summary |
|---|---|
| `b79cdd2` | Add production readiness plan |
| `e87b009` | Add PostgreSQL backup and restore scripts |
| `31d8776` | Add production admin bootstrap procedure |
| current change set | Add production env template, health aliases, readiness checker, and handoff docs |

## Operational readiness completed

- Production-readiness plan documents recommended first production baseline: Cloud VM + Docker Compose.
- PostgreSQL backup and restore scripts exist and have an isolated restore-drill runbook.
- Production administrator bootstrap is separated from demo seed administrator accounts.
- `.env.production.example` provides a production operator template with placeholders only.
- `scripts/verify-production-readiness.ps1` checks required env keys, placeholder status, Compose config, operations artifacts, backup ignore behavior, and optional runtime endpoints without printing secret values.
- Backend health aliases provide `/health`, `/health/live`, `/ready`, and `/health/ready`.
- Deployment handoff documents clone, env preparation, build/up, migration, demo seed separation, admin bootstrap, backup, rollback, and runtime checks.

## Pending external decisions

| Decision | Status | Notes |
|---|---|---|
| PC-001 Object Storage provider / adapter | Pending decision | Required before real production attachments or long-term file retention |
| PC-002 Email provider | Pending decision | Required before real password reset or notification email |
| PC-003 Final RPO/RTO approval | Pending decision | Pilot proposal exists; business owner approval and first recorded restore drill remain |
| PC-004 Search expansion thresholds | Pending decision | Criteria proposed; approve when content/latency needs are clearer |
| PC-005 Hosting platform | Partially addressed / pending decision | Cloud VM + Docker Compose runbook exists; final server, DNS, and TLS details remain |
| PC-006 CI/CD platform | Pending decision | Local gates exist; managed CI/CD platform not selected |
| PC-007 Affected design updates | In progress | This branch updates relevant operations/API design docs; future provider decisions will require more updates |
| PC-008 Design-doc verification | Requires final evidence | Run before PR handoff |
| PC-009 Internal CDR disposition | Pending decision | Internal reviewers must record final disposition |

## Verification results

Latest local evidence for this branch:

| Check | Result | Evidence summary |
|---|---|---|
| `scripts/verify-design-docs.ps1` | PASS | Design document count, IDs, links, traceability, CDR fields all passed |
| `scripts/verify-production-readiness.ps1 -TemplateMode -SkipHttp` | PASS | Production env template keys, Compose config, operations artifacts, backup ignore behavior passed without printing secrets |
| Targeted backend tests | PASS | Health aliases and admin bootstrap tests passed; backend suite reached 17 tests in full gate |
| `scripts/verify.ps1` | PASS | Ruff, Pytest, ESLint, TypeScript, Vitest, Vite build, Alembic, seed idempotency, Playwright 14 tests, secret scan, Docker integration all passed |
| `scripts/verify-docker.ps1` | PASS | Isolated Docker build/up, readiness, `/health` alias, `/ready` alias, seed, API smoke, auth, admin guard, restart persistence, log scan, cleanup all passed |
| Admin bootstrap temporary DB check | PASS | First run created production admin; second run detected existing active admin and did not create a duplicate |
| Backup artifact tracking | PASS | `backups/probe.dump` is ignored by Git |
| `git diff --check` | PASS | No whitespace errors detected |
| Default `localhost:8080` check | PASS | Existing RC1 frontend container responded on port 8080 |
| Default `localhost:8000/health` check | Not used as final evidence | Port 8000 is occupied by existing `yonlab-i-nuri-site-rc1-backend-1`, an older running image that returns 404 for the new aliases; the current code is verified through TestClient and isolated Docker images without stopping the user's existing container |

Known verification warning: Pytest still reports the pre-existing FastAPI/Starlette TestClient deprecation warning from the installed dependency stack. It is not introduced by this change set.

## Deployment preflight checklist

- [ ] Use the approved commit/tag and do not move `v0.1.0-rc1` or `v0.1.0-rc2`.
- [ ] Copy `.env.production.example` to a protected server env file and replace placeholders outside Git.
- [ ] Run `scripts/verify-production-readiness.ps1` without printing secrets.
- [ ] Build Compose images and apply Alembic migrations before traffic.
- [ ] Confirm `/health`, `/ready`, and frontend HTTP responses.
- [ ] Bootstrap production admin through `scripts/bootstrap-admin.ps1`; do not rely on demo seed admin.
- [ ] Create a PostgreSQL backup and copy it to the approved off-host destination.
- [ ] Record deployment commit, env source, health checks, bootstrap result, and backup evidence.
- [ ] Keep demo seed accounts disabled, removed, or isolated before external launch.

## Draft PR body

```markdown
## Summary

This PR prepares `feat/production-readiness` as the post-RC2 production-readiness handoff branch for a Cloud VM + Docker Compose operating model. It does not deploy externally and does not move RC tags.

## Included

- Production readiness plan and CDR pending-decision mapping
- PostgreSQL backup/restore scripts and runbook
- Production admin bootstrap separated from demo seed admin
- Production env template and readiness preflight script
- Backend `/health` and `/ready` compatibility aliases
- Deployment, backup, admin, and release handoff documentation

## Verification

- `.\scripts\verify-design-docs.ps1`: see release document evidence
- `.\scripts\verify.ps1`: see release document evidence
- `.\scripts\verify-docker.ps1`: see release document evidence
- Admin bootstrap temporary DB check: see release document evidence
- Backup artifacts ignored by Git: see release document evidence

## Pending decisions

Object storage provider, email provider, formal RPO/RTO approval, final hosting/DNS/TLS details, CI/CD platform, and final CDR disposition remain outside this PR scope.
```
