# Authentication and threat model

## Token strategy

Access tokens are HS256 JWTs with a 15-minute default lifetime and contain only user id, role, issue time and expiry. Refresh tokens are 384-bit random opaque values. The database stores only SHA-256 digests, expiry and revocation state. Every refresh rotates the token: the presented session is revoked and a new session is created.

A revoked refresh token presented again is treated as probable theft. All active sessions for that user are revoked. Logout revokes one session; logout-all revokes every active session. Password reset also revokes every session. Protected API calls always reload the active user so disabled accounts and current roles take effect.

The browser stores the current session in one versioned local record for this RC1 client and sends credentials on API calls. Production deployment should prefer an HttpOnly Secure refresh cookie plus CSRF token; the response body refresh token remains for non-browser clients and deterministic integration testing. Never log either token.

## Password reset

Reset tokens are one-time 256-bit random values, expire after 30 minutes and are stored only as SHA-256 digests. The request endpoint always returns the same generic response to prevent account enumeration. In development only, the adapter returns the raw token in the response. Production must replace this development delivery with a provider implementing the same send-reset-link boundary. Confirmation marks the token used, changes the Argon2 hash and revokes all sessions.

## Threats and controls

- Stolen access token: short expiry and active-user lookup limit impact.
- Stolen refresh token: rotation and reuse detection revoke the session family.
- Database disclosure: raw refresh and reset tokens are absent.
- Privilege escalation: server-side role dependency guards every admin endpoint.
- Last-admin lockout: demotion is rejected when only one active administrator remains.
- XSS: local session storage increases impact; strict CSP and HttpOnly refresh migration are production gates.
- CSRF: bearer access tokens are not ambient credentials; cookie refresh deployment requires explicit CSRF protection.
