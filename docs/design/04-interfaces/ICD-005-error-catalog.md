# ICD-005 Error Catalog

## Error Envelope

```json
{
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "Resource was not found.",
    "details": {},
    "request_id": "correlation-id"
  }
}
```

## Catalog

| HTTP status | Code family | Meaning |
|---|---|---|
| 400 | INVALID_REQUEST | Request is syntactically valid but violates domain rules |
| 401 | AUTHENTICATION_REQUIRED | Credential is missing, invalid, expired, or revoked |
| 403 | AUTHORIZATION_DENIED | Authenticated identity lacks required permission |
| 404 | NOT_FOUND | Entity is missing or not visible to the caller |
| 409 | CONFLICT | Unique constraint, stale state, unsafe lifecycle transition, or privilege safety rule |
| 413 | PAYLOAD_TOO_LARGE | Upload exceeds configured size |
| 415 | UNSUPPORTED_MEDIA_TYPE | Upload type or signature is rejected |
| 422 | VALIDATION_ERROR | Request fields fail schema validation |
| 429 | RATE_LIMITED | Caller exceeded policy |
| 500 | INTERNAL_ERROR | Unexpected server fault with safe response |
| 502 | PROVIDER_ERROR | Upstream provider returned unusable response |
| 503 | SERVICE_UNAVAILABLE | Required dependency is unavailable |
| 504 | PROVIDER_TIMEOUT | Upstream provider timed out |

## Field Rules

`message` is safe for users. `details` contains field errors or non-sensitive domain context. `request_id` is always safe to share with support.

## Timeout, Retry, And Idempotency

Clients may retry 503 and 504 responses only when the operation is idempotent or an idempotency key is supplied. Clients must not retry authentication failures without user action.

## Security Considerations

Errors do not reveal whether a reset email exists, whether a hidden resource exists, raw provider responses, stack traces, secrets, tokens, or password-policy internals beyond accepted user guidance.

## Observability

Each error is logged with code, status, endpoint group, correlation ID, and safe diagnostic fields.
