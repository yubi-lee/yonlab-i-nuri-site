# SEC-001 Security Architecture

## Security Objectives

- Protect accounts, sessions, administrator privileges, files, inquiries, audit records, and secrets.
- Enforce authorization at the API boundary.
- Prevent common web, API, upload, and provider-integration attacks.
- Preserve actionable audit and incident evidence without leaking sensitive data.

## Trust Boundaries

| Boundary | Control |
|---|---|
| Browser to web layer | TLS, security headers, CORS, content security policy |
| Web layer to API | Reverse proxy policy, request size limits, correlation ID |
| API to PostgreSQL | Least-privilege database user, encrypted transport, parameterized queries |
| API to object storage | Private bucket, least-privilege credentials, signed access policy |
| API to email provider | Secret-managed credentials, template allowlist |
| API to observability | Redaction, access control, retention policy |

## Authentication

Users authenticate with email and password. Passwords are stored only as adaptive hashes. Access tokens are short-lived and signed. Refresh tokens are random, stored only as digests, rotated on use, and revoked on replay.

## Authorization

RBAC defines user and administrator permissions. Privileged operations require administrator role checks at the API. Least privilege applies to users, operators, runtime identities, database credentials, storage credentials, and CI/CD identities.

## Session And Token Controls

- Access token expiry is short.
- Refresh sessions are server-side and revocable.
- Refresh replay triggers revocation policy and security telemetry.
- Password reset tokens are single-use, expiring, and stored as digests.
- Logout invalidates the relevant session scope.

## Web Controls

Controls include CSRF strategy for cookie-based flows, exact CORS allowlist, XSS-safe rendering, content security policy, secure headers, no secret-bearing client bundles, and safe redirect handling.

## API And Data Controls

SQL injection is prevented through parameterized queries and ORM-bound expressions. IDOR is prevented through authorization and visibility checks on every entity access. Validation rejects unsafe field shapes and lifecycle transitions.

## File Controls

Uploads are checked for filename safety, extension allowlist, MIME type, signature, size, malware policy, and resource authorization. Object storage uses private access, encryption, generated keys, and least-privilege credentials.

## Container And Dependency Controls

Images use minimal bases, pinned dependencies where practical, vulnerability scanning, non-root runtime where supported, explicit health checks, and separated build/runtime secrets.

## Secrets

Secrets are provided by a secret manager or protected deployment facility. Secrets are never committed, logged, embedded in frontend assets, or copied into design examples.

## Backup And Incident Evidence

Backups are encrypted and access-controlled. Audit records, logs, provider events, and deployment records are retained according to incident and compliance needs.
