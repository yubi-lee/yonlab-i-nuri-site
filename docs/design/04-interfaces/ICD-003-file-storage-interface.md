# ICD-003 File Storage Interface

## Interface Summary

The storage interface separates file bytes from application metadata and supports S3-compatible object storage or an equivalent provider.

| Operation | Input | Output | Success condition |
|---|---|---|---|
| Validate upload | filename, MIME, bytes, resource, user | validation result | File satisfies policy |
| Save object | object key, bytes, metadata | provider object reference | Object durably stored |
| Read object | object key or signed policy | bytes or signed URL | Authorized object available |
| Delete object | object key | deletion result | Object removed or delete marker recorded |
| Reconcile | metadata and provider listing | reconciliation report | Orphans identified or repaired |

## Data Format

Upload requests use multipart form data. Metadata responses use JSON. Downloads use streamed bytes or provider signed URLs according to deployment policy.

## Required Fields

Attachment metadata requires resource ID, file object ID, original display name, generated object key, MIME type, size, checksum, scan state, created time, and retention state.

## Optional Fields

Optional fields include display order, description, language, provider version ID, scan vendor result, and expiration policy.

## Authentication And Authorization

Only administrators upload or delete resource attachments. Public download is allowed only for visible resources and non-quarantined files. Provider credentials are never exposed to browsers.

## Error Conditions

Errors include unsafe filename, unsupported type, MIME mismatch, signature mismatch, size exceeded, malware rejection, provider timeout, object missing, metadata conflict, and unauthorized access.

## Timeout, Retry, And Idempotency

Object operations have bounded timeouts and provider retry policy. Upload idempotency uses request key and checksum where clients may retry. Delete operations are idempotent.

## Transaction Boundary

Object storage is outside the database transaction. Save-then-metadata and metadata-then-save flows must define compensation. Reconciliation repairs rare split-state failures.

## Security Considerations

Use private buckets, least-privilege credentials, encryption, generated keys, no path-derived object names, content scanning, and signed access policies.

## Observability

Metrics include upload size, rejection reason, provider latency, provider error rate, delete failures, reconciliation count, and scan outcomes.
