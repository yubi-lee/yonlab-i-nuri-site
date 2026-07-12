# SYS-006 Development System

## Purpose

The development system gives engineers a reproducible environment for product work, integration checks, and design verification without depending on production services.

## Development Services

| Service | Purpose |
|---|---|
| Web application | Frontend development server or built static assets |
| API application | FastAPI runtime with development configuration |
| PostgreSQL | Relational database matching production behavior |
| Object-storage-compatible service | Local validation of storage contracts |
| Mail capture service | Local validation of email formatting and delivery requests |
| Observability sink | Local structured log and metric inspection |

## Docker Compose Design

Docker Compose defines service wiring, health checks, dependency order, environment variables, volumes, and ports for local and verification environments. Compose files must avoid real secrets and should use explicit health checks instead of fixed waits.

## Developer Workflow

1. Install dependencies through documented scripts.
2. Start service dependencies through Compose or documented local substitutes.
3. Apply migrations.
4. Seed non-sensitive development data.
5. Run quality gates before review.

## CI/CD Integration Points

The same verification logic is used by CI/CD where practical: lint, typecheck, unit tests, integration tests, migration checks, storage contract checks, email contract checks, E2E tests, accessibility checks, dependency scanning, and deployment smoke checks.
