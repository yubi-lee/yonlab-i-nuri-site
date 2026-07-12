# SEC-002 Threat Model

## Assets

| Asset | Protection need |
|---|---|
| User account | Authentication, privacy, and recovery |
| Administrator account | Privileged access and auditability |
| Refresh session | Replay prevention and revocation |
| Reset token | Single-use recovery and secrecy |
| CMS content | Integrity and publication control |
| Uploaded file | Safe handling and authorized access |
| Inquiry data | Personal-data protection |
| Audit log | Accountability and tamper resistance |
| Secrets | Runtime confidentiality |
| Backups | Confidentiality and recoverability |

## Threats And Mitigations

| Threat | Mitigation |
|---|---|
| Credential stuffing | Rate limiting, adaptive hashing, monitoring, account protection workflow |
| Stolen refresh token | Rotation, digest storage, replay detection, session revocation |
| Password reset abuse | Neutral responses, expiring single-use tokens, email delivery controls, rate limits |
| Privilege escalation | RBAC, least privilege, last-privileged-admin safety, audit logs |
| IDOR | Per-request ownership and visibility checks |
| SQL injection | Parameterized queries and validation |
| XSS | Output escaping, no unsafe HTML rendering, content security policy |
| CSRF | SameSite strategy and CSRF tokens where cookies authorize state changes |
| CORS abuse | Exact origin allowlist |
| MIME spoofing | Extension, MIME, signature, scan, and quarantine policy |
| Path traversal | Generated object keys and basename validation |
| Object storage exposure | Private buckets, signed URLs, least-privilege credentials |
| Secret leakage | Secret manager, redaction, repository scanning, deployment controls |
| Log privacy leakage | Redaction and structured safe fields |
| Container compromise | Minimal images, dependency scanning, non-root runtime, network policy |
| Backup compromise | Encryption, access controls, restore audit |

## Abuse Cases

1. Attacker reuses a rotated refresh token.
2. Attacker enumerates accounts through reset requests.
3. Non-admin user attempts CMS mutation.
4. User tries to access another user's inquiry or bookmark.
5. Administrator uploads a disguised executable.
6. Provider outage interrupts email or storage operations.

## Residual Risk Management

Residual risks are reviewed during CDR and release readiness. Risks require owner, mitigation, verification method, and acceptance decision.
