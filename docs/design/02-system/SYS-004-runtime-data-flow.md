# SYS-004 Runtime Data Flow

## 1. Authentication

1. The user submits credentials to the API.
2. The API validates the account and password hash.
3. The API issues a short-lived access token and a refresh token.
4. The refresh token is stored only as a digest in a refresh session record.
5. The client uses the access token for authenticated requests.

## 2. Refresh Rotation And Replay Handling

1. The client submits a refresh token to the refresh endpoint.
2. The API locates the matching active session by token digest.
3. The API revokes the used session and creates a replacement session atomically.
4. Reuse of a revoked token is treated as replay and triggers session revocation policy, audit logging, and security telemetry.

## 3. Password Reset

1. A reset request accepts an email address and returns a neutral response.
2. The API creates a single-use reset token digest for eligible accounts.
3. The email service sends a reset link containing the raw token.
4. Confirmation validates token digest, expiry, and unused state.
5. Successful reset changes the password hash and revokes refresh sessions.

## 4. CMS Mutation

1. Administrator submits a CMS mutation request.
2. API validates token, role, request body, entity state, and business constraints.
3. Database mutation and audit record occur in one transaction.
4. Related search indexes or cache entries are refreshed through asynchronous or transactional outbox design where needed.
5. Response includes normalized entity data and correlation ID.

## 5. File Upload

1. Administrator uploads a file for a resource.
2. API validates filename, extension, MIME type, signature, size, malware policy, and resource authorization.
3. File bytes are stored in object storage under generated object key.
4. File metadata is committed in PostgreSQL.
5. If metadata commit fails, stored bytes are removed or marked for cleanup.

## 6. Search

1. User submits query and filters.
2. API authorizes the visibility scope.
3. Search service queries the configured index or relational search path.
4. Results return ranked items with type, title, summary, highlights where supported, and pagination.

## 7. Observability

Every inbound request receives a correlation ID. Logs, audit records, metrics, and error responses include the correlation ID where safe.
