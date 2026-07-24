# ICD-001 API Interface

## Contract Overview

| Item | Design |
|---|---|
| Base path | `/api/v1` |
| Format | JSON for structured bodies, multipart for uploads, streamed or signed URL for downloads |
| Authentication | Bearer access token unless endpoint is public |
| Correlation | `X-Request-ID` accepted and returned |
| Pagination | `page`, `page_size`, `total`, `items` |
| Time format | ISO 8601 UTC |

## Public And Member Endpoints

| Method | Path | Auth | Input | Output | Success |
|---|---|---|---|---|---|
| GET | `/health` | None | None | Health document | Process is alive |
| GET | `/health/live` | None | None | Health document | Process is alive |
| GET | `/ready` | None | None | Dependency readiness | Required dependencies are ready |
| GET | `/health/ready` | None | None | Dependency readiness | Required dependencies are ready |
| POST | `/auth/register` | None | email, name, password | Token session | User account created |
| POST | `/auth/login` | None | email, password | Token session | Valid credentials |
| POST | `/auth/refresh` | Refresh token | refresh token | Token session | Session rotated |
| POST | `/auth/logout` | Refresh token or access token | session identifier or refresh token | Empty | Session revoked |
| POST | `/auth/logout-all` | User | None | Empty | User sessions revoked |
| POST | `/auth/password-reset/request` | None | email | Neutral accepted response | Reset flow accepted |
| POST | `/auth/password-reset/confirm` | None | token, password | Empty | Password changed |
| GET | `/me` | User | None | User profile | Active account |
| PATCH | `/me` | User | allowed profile fields | User profile | Profile updated |
| GET | `/resources` | None | filters, pagination | Resource page | Visible resources returned |
| GET | `/resources/{id}` | None | resource id | Resource detail | Visible resource returned |
| GET | `/resources/{id}/attachments` | None | resource id | Attachment list | Visible attachments returned |
| GET | `/resources/{id}/attachments/{attachmentId}/download` | None or signed policy | identifiers | File stream or signed URL | Authorized file access |
| GET | `/content/{kind}` | None | kind, filters | Content page | Visible content returned |
| GET | `/search` | None | query, filters, pagination | Search page | Ranked results returned |
| POST | `/inquiries` | None or user | contact, subject, message, consent | Inquiry receipt | Inquiry accepted |
| GET | `/me/inquiries` | User | pagination | Inquiry page | User inquiries returned |
| GET | `/me/bookmarks` | User | pagination | Bookmark page | Bookmarks returned |
| POST | `/me/bookmarks/{resourceId}` | User | resource id | Bookmark | Bookmark created idempotently |
| DELETE | `/me/bookmarks/{resourceId}` | User | resource id | Empty | Bookmark removed idempotently |

## Diagnosis Score Contract

POST /api/v1/diagnosis/score is a public, strict Pydantic v2 JSON contract for deterministic
scoring. The request contains anchor_count, one to one hundred evidence.v1 records, and optional
fixed-six decimal dimension and indicator weights. Evidence records require UUID identifiers, a
positive turn sequence, an anchor within the requested anchor count, non-negative code-point
spans, and an end span no earlier than its start. Unknown fields and cross-record anchor-count
mismatches are rejected with 422.

The response contains the policy version, deterministic status and fixed-point score fields, the
selected evidence identifier, the preserved request_id, and persisted: false. It never returns
quoted_span or any other raw evidence field. Validation errors use the safe validation_error
envelope with the same request_id; the endpoint does not create or update a database record.
## Administrator Endpoints

| Method | Path | Auth | Input | Output | Success |
|---|---|---|---|---|---|
| GET | `/admin/dashboard` | Admin | date/filter options | Summary | Operational summary returned |
| GET | `/admin/{entity}` | Admin | filters, pagination | Entity page | Entity list returned |
| POST | `/admin/{entity}` | Admin | entity body | Entity | Entity created |
| GET | `/admin/{entity}/{id}` | Admin | entity id | Entity | Entity detail returned |
| PATCH | `/admin/{entity}/{id}` | Admin | partial body | Entity | Entity updated |
| DELETE | `/admin/{entity}/{id}` | Admin | entity id | Empty | Entity archived, disabled, or deleted by policy |
| POST | `/admin/resources/{id}/attachments` | Admin | multipart file | Attachment metadata | File accepted |
| DELETE | `/admin/resources/{id}/attachments/{attachmentId}` | Admin | identifiers | Empty | File detached or deleted by policy |
| GET | `/admin/audit-logs` | Admin | filters, pagination | Audit page | Audit records returned |

## Error Conditions

Errors follow `ICD-005`. Authentication errors use 401, authorization errors use 403, validation errors use 400 or 422, conflicts use 409, rate limits use 429, and provider failures use controlled 5xx responses.

## Timeout, Retry, And Idempotency

- Read requests have bounded API timeouts.
- Client retries are allowed for safe reads and idempotent deletes.
- Mutating requests support idempotency keys where duplicate submission is likely.
- Refresh rotation and file upload are not blindly retried without idempotency protection.

## Transaction Boundary

Each mutating endpoint defines a database transaction boundary. Cross-provider side effects use compensation or durable outbox behavior.

## Security And Observability

Every endpoint validates visibility and authorization. Logs and metrics include correlation ID, endpoint group, result class, and latency without raw secrets.

## AI Training Platform Extension

Organization-scoped operations require an active `OrganizationMembership` and server-side membership enforcement. The implemented platform slice adds organization/member/consent APIs, teacher profile, diagnosis sessions with SSE events, learning paths/enrollments/activities, document processing jobs, tenant-scoped citation-backed knowledge search, reports, and pilot metrics under `/api/v1`.

Diagnosis remains deterministic and fixed-point based. Diagnosis evidence is stored only as metadata and a hash of the quoted span; raw spans are not returned by session completion or SSE. Knowledge search returns citations tied to a document node and a `no_answer` flag when no grounded result matches.

The independent `services/ai-gateway` boundary contains no provider credentials or SDKs. Restricted and elevated-safeguarding requests are accepted only by the deterministic local route. The local document adapter supports text/Markdown/HTML and constrained native HWPX; PDF/OCR returns an explicit adapter-required job failure.