# YOnLearn Hub development instructions

## Architecture
- Keep the React client, FastAPI API, and PostgreSQL persistence independently testable.
- Public APIs live below `/api/v1`; health checks remain at `/health/*`.
- Storage and search must stay behind replaceable service boundaries before S3 or OpenSearch adoption.

## Coding and quality
- Python 3.12+, SQLAlchemy 2 typed mappings, Pydantic v2, Ruff.
- Strict TypeScript, semantic HTML, keyboard-visible focus, WCAG 2.1 AA target.
- Write a failing test before changing behavior; preserve request IDs and safe error responses.
- Required gate: `scripts/verify.ps1`. Do not claim Docker or E2E success without executing them.

## Security and copyright
- Never commit secrets, real user data, administrator passwords, source-site assets, or raw reference captures.
- i-?? is reference-only. Do not copy its copy, code, layout, logo, images, icons, or content.
- Keep `reference/inuri-public/raw/` and screenshots ignored. Product code may not reference them.

## Design documentation maintenance
- API changes require review of `docs/design/04-interfaces/ICD-001-api-interface.md` and `docs/design/01-requirements/REQ-003-requirements-traceability.md`.
- Database changes require review of `docs/design/03-components/CDD-008-database.md`, `docs/design/04-interfaces/ICD-002-database-interface.md`, and the ERD in `ICD-002`.
- Authentication changes require review of `docs/design/03-components/CDD-003-authentication.md`, `docs/design/05-security/`, and `docs/design/07-verification/`.
- File-handling changes require review of `docs/design/03-components/CDD-006-storage.md`, `docs/design/04-interfaces/ICD-003-file-storage-interface.md`, and `docs/design/05-security/`.
- Deployment changes require review of `docs/design/02-system/SYS-005-deployment-architecture.md` and `docs/design/06-operations/`.
- Requirement changes require review of `docs/design/01-requirements/REQ-001-system-requirements.md`, `docs/design/01-requirements/REQ-002-non-functional-requirements.md`, and `docs/design/01-requirements/REQ-003-requirements-traceability.md`.
- Run `scripts/verify-design-docs.ps1` after every design documentation change.
- If implementation and design diverge, do not quietly distort the design; record the design decision and update affected documents intentionally.
