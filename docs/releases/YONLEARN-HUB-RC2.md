# YOnLearn Hub v0.1.0-rc2

Release candidate: **YOnLearn Hub v0.1.0-rc2**

Application/content baseline commit: `ccb3788 feat: add YOnLab public education content pack v1`

Release package date: 2026-07-13 (Asia/Seoul)

## RC1 to RC2 changes

Compared with `v0.1.0-rc1` (`c99a5ed`), RC2 adds the YOnLab public education content pack v1 and closes the release package around the content-rich RC1 candidate.

Primary differences:

- Added YOnLab-authored public education portal sample content pack v1.
- Expanded seed content density for resources, notices, articles, FAQs, inquiries, categories, tags, and demo users.
- Added seed count/idempotency/clean-room regression coverage.
- Stabilized verification gates for occupied local ports and isolated Docker verification ports.
- Documented content-pack clean-room status, seed operation notes, and release/demo verification procedures.

## Included feature summary

- Public search-led education portal flow.
- Resource listing and detail pages.
- Category/tag/audience/resource-type metadata for discovery.
- Notices, insight articles, and FAQs.
- Member login, bookmark, inquiry submission, and inquiry history flows.
- Admin CMS list/search/create/update/delete or safe-status flows for RC1 entities.
- Audit logging for admin operations.
- Local SQLite test flow and PostgreSQL Docker deployment flow.
- Integrated verification through `scripts/verify.ps1` and isolated Docker verification through `scripts/verify-docker.ps1`.

## Content pack v1 counts

| Entity | Count |
|---|---:|
| Categories | 10 |
| Tags | 45 |
| Resources | 100 |
| Notices | 18 |
| Articles / insights | 28 |
| FAQs | 45 |
| Inquiries | 15 |
| Users | 4 |
| Real attachments | 0 |

## Clean-room statement

The content pack is fictional sample data written by YOnLab for demonstration and verification. It does not use i-Nuri original text, images, attachments, resource names, unique wording, colors, layout, file names, or source assets. It does not include real institution names, real textbook names, real child/family/staff data, or real copyrighted teaching materials.

References to activity sheets, checklists, or observation templates are fictional metadata only. The seed creates no actual attachment binaries.

## Verification result

Fresh verification commands for this release package:

```powershell
.\scripts\verify.ps1
.\scripts\verify-docker.ps1
```

Expected RC2 pass condition:

- Design documentation gate: PASS
- Ruff: PASS
- Pytest: PASS, including content pack seed regression
- ESLint: PASS
- TypeScript: PASS
- Vitest: PASS
- Vite production build: PASS
- Empty DB Alembic migration: PASS
- Seed idempotency: PASS
- Playwright E2E: PASS
- Secret scan: PASS
- Docker build/up/readiness/migration/seed/API smoke/restart/log scan/cleanup: PASS

The known external Starlette TestClient/httpx deprecation warning remains documented in `docs/qa/testclient-warning.md`.

## Docker execution

Run the isolated Docker verification gate:

```powershell
.\scripts\verify-docker.ps1
```

For manual Compose review, use the project Compose file with secrets supplied through environment or `.env`:

```powershell
$env:JWT_SECRET = "<set-locally>"
$env:ADMIN_EMAIL = "admin@example.com"
$env:ADMIN_PASSWORD = "<set-locally>"
docker compose up -d --build
```

Then open:

```text
http://localhost:8080
```

## Fresh deploy verification

See `docs/qa/rc2-fresh-deploy-verification.md` for a D:\Deploy-oriented clean checkout verification procedure.

## Operational checks before production

- Replace sample seed data with reviewed operating content.
- Remove, rotate, or disable sample accounts and sample inquiries.
- Complete copyright/license review.
- Complete privacy review and avoid real child/family/staff data in non-production environments.
- Complete accessibility and mobile QA.
- Complete education/safety/legal appropriateness review.
- Confirm production secret management and backup/restore procedures.
- Confirm production domain, TLS, CORS, logging, and monitoring configuration.

## Known limitations

- Content pack v1 is demonstration data, not approved operating content.
- No real downloadable source attachments are included in the seed.
- Search is database-backed and suitable for RC verification, not a dedicated search engine.
- The Docker frontend container may not expose a native Docker healthcheck in some manual Compose states; HTTP readiness remains the release verification criterion.
- Push is not performed as part of this local release package.
