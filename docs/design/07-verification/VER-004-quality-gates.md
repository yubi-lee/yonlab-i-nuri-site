# VER-004 Quality Gates

## Gate Categories

| Gate | Purpose |
|---|---|
| Static analysis | Detect code quality, type, lint, dependency, and formatting defects |
| Unit and component tests | Validate isolated behavior and component contracts |
| API integration tests | Validate endpoint contracts, permissions, errors, and transactions |
| Migration tests | Validate schema evolution and empty-database setup |
| Provider contract tests | Validate storage, email, search, and observability adapters |
| Browser E2E tests | Validate public, member, and administrator journeys |
| Accessibility tests | Validate WCAG-oriented behavior |
| Performance tests | Validate latency and asset budgets |
| Security tests | Validate threat controls and dependency posture |
| Backup and restore tests | Validate recoverability and consistency |
| Deployment tests | Validate rollout, readiness, smoke checks, and rollback |
| Document tests | Validate design package integrity and traceability |

## Required Document Gate

`scripts/verify-design-docs.ps1` checks the design package for required files, duplicate IDs, traceability, prohibited implementation-status language, local absolute paths, broken relative links, Mermaid fence closure, placeholder markers, root README access, AGENTS maintenance rules, CDR condition IDs, and document-index coverage.

## CI/CD Gate Model

CI/CD should fail closed on security-critical, migration, contract, deployment, and acceptance failures. Non-blocking exploratory checks may report warnings only when documented by policy and approved by reviewers.

## Evidence Model

Each gate records command, environment class, artifact version, result, timestamp, and safe logs. Evidence excludes secrets and raw personal data.
