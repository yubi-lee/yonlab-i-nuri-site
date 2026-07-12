# CDD-003 Authentication

## 1. Purpose

Protect member and administrator workflows through account identity, password security, token issuance, session rotation, password reset, and RBAC.

## 2. Scope

Includes registration, login, access tokens, refresh sessions, replay detection, logout, password reset, account activity checks, and role checks.

## 3. Responsibilities

- Hash passwords with a strong adaptive algorithm.
- Issue signed access tokens with expiry.
- Maintain refresh sessions as server-side records.
- Rotate refresh tokens and detect replay.
- Enforce active account and role policy.
- Reset passwords through expiring single-use tokens.

## 4. Non-Responsibilities

Authentication does not decide CMS business rules, store raw tokens, or expose account existence through recovery flows.

## 5. Components

| Component | Role |
|---|---|
| Credential service | Password hashing and verification |
| Token service | Access token issuance and validation |
| Session service | Refresh session lifecycle and replay handling |
| Reset service | Password reset token lifecycle and email request |
| RBAC service | Role and permission evaluation |

## 6. Provided Interfaces

Provides login, refresh, logout, logout-all, reset request, reset confirm, profile, and authorization dependencies.

## 7. Consumed Interfaces

Consumes user, refresh session, reset token, audit log, email delivery, and observability interfaces.

## 8. Dependencies

Password hashing library, JWT signing and verification, secure random generator, PostgreSQL transactions, email adapter, and structured logging.

## 9. Data Structures

Key data includes User, Role, RefreshSession, PasswordResetToken, token claims, password policy result, and security event.

## 10. Normal Processing

Login validates credentials and account state, then issues tokens. Refresh validates the session digest, rotates the session, and returns new tokens. Reset request creates a single-use token and sends an email. Reset confirmation changes password and revokes sessions.

## 11. Error And Exception Handling

Invalid credentials return a generic authentication error. Expired, revoked, or malformed tokens are rejected. Reset request responses are neutral. Replay events trigger revocation policy and telemetry.

## 12. State And Lifecycle

Refresh sessions move through active, revoked, expired, and replay-handled states. Reset tokens move through active, used, and expired states.

## 13. Concurrency And Transactions

Refresh rotation and replay detection are transactional and protected by uniqueness and state checks. Password reset updates password state and session revocation in one boundary or compensating sequence.

## 14. Security Controls

Controls include adaptive password hashing, token expiry, signed claims, hashed token storage, replay detection, account activity checks, RBAC, least privilege, neutral reset responses, CSRF policy for cookie flows, and safe logs.

## 15. Configuration

Configurable values include token lifetimes, password policy, signing secret source, allowed algorithms, reset token lifetime, and session revocation policy.

### Token Policy Reference

| Policy | Recommended default | Configurable range | Configuration key | Notes |
|---|---|---|---|---|
| Access token lifetime | 15 minutes | 5 to 30 minutes | `ACCESS_TOKEN_MINUTES` | Short enough to reduce bearer-token risk |
| Refresh session lifetime | 7 days | 1 to 30 days | `REFRESH_TOKEN_DAYS` | Longer values require explicit risk acceptance |
| Password reset token lifetime | 30 minutes | 10 to 60 minutes | `PASSWORD_RESET_TOKEN_MINUTES` | Single-use and revoked after confirmation |
| Session retention | Policy-defined | Security and privacy review | `SESSION_RETENTION_DAYS` | Retains security evidence without indefinite personal data |

Client storage policy prefers in-memory access tokens and an HttpOnly, Secure, SameSite refresh-token transport when browser cookies are used. Any alternate browser storage requires threat-model approval and compensating controls.


## 16. Performance

Password hashing cost is tuned for security and acceptable login latency. Token lookup uses indexed digests.

## 17. Scalability

Session state is stored centrally so multiple API nodes can validate and revoke tokens consistently.

## 18. Observability

Authentication emits metrics and logs for login outcomes, token refresh, replay detection, reset requests, and role denial without logging raw credentials or tokens.

## 19. Testability

Tests cover password policy, login, token expiry, refresh rotation, replay detection, reset flow, role checks, inactive users, and last-administrator policy.

## 20. Design Decisions

Refresh sessions are server-side and rotating because revocation and replay detection are product security requirements.
