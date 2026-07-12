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
