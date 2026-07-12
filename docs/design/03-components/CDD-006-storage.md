# CDD-006 Storage

## 1. Purpose

Manage uploaded resource files through validated metadata, durable object storage, and safe download behavior.

## 2. Scope

Includes upload validation, object key generation, metadata persistence, object storage operations, download authorization, deletion, retention, and consistency repair.

## 3. Responsibilities

- Validate uploaded file name, extension, MIME type, signature, size, malware policy, and authorization.
- Store bytes in object storage.
- Store metadata in PostgreSQL.
- Provide authorized downloads.
- Compensate for partial failures.

## 4. Non-Responsibilities

Storage does not decide content publication policy, parse document content for product meaning, or expose provider credentials to browsers.

## 5. Components

| Component | Role |
|---|---|
| Upload validator | Checks file safety and policy |
| Object storage adapter | Saves, reads, deletes, and signs object access |
| Metadata service | Maintains ResourceAttachment and FileObject records |
| Consistency reconciler | Finds orphaned metadata or objects |
| Malware scanner | Scans files where policy requires it |

## 6. Provided Interfaces

Provides upload, list, download, delete, signed URL, and reconciliation interfaces.

## 7. Consumed Interfaces

Consumes authentication, CMS resource state, PostgreSQL, object storage, malware scanning, audit, and observability services.

## 8. Dependencies

Depends on S3-compatible object storage or equivalent, database transactions, configured buckets, encryption policy, lifecycle rules, and provider timeout settings.

## 9. Data Structures

Data includes FileObject, ResourceAttachment, object key, original filename, MIME type, size, checksum, scan status, retention state, and audit target.

## 10. Normal Processing

Upload validates file policy, stores bytes, records metadata, emits audit and metrics, and returns attachment metadata. Download validates resource visibility and returns bytes or signed access.

## 11. Error And Exception Handling

Rejected uploads return policy-specific errors. Provider failures return controlled service errors. Metadata failure after object write triggers delete compensation or reconciliation marker.

## 12. State And Lifecycle

Files move through pending, stored, scan-pending, available, quarantined, deleted, and retention-expired states according to policy.

## 13. Concurrency And Transactions

Database metadata writes are transactional. Object writes are coordinated with compensation because object storage is outside the database transaction boundary.

## 14. Security Controls

Controls include MIME and signature checks, path traversal prevention, generated object keys, private buckets, encryption, least-privilege credentials, malware scanning, and signed download policy.

## 15. Configuration

Configuration includes bucket, region, endpoint, credential source, size limit, type allowlist, scan policy, timeout, retry, retention, and lifecycle rules.

## 16. Performance

Large downloads stream through provider-native paths where safe. Upload size is bounded. Metadata lists are paginated.

## 17. Scalability

Object storage scales independently of API nodes. Reconciliation and scanning can run in workers.

## 18. Observability

Metrics include upload count, rejection reason, storage latency, download errors, scan outcomes, and reconciliation findings.

## 19. Testability

Tests cover adapter contract, upload policy, compensation, signed access, deletion, retention, and provider timeout behavior.

## 20. Design Decisions

Object storage is the target file-byte store; PostgreSQL stores metadata and lifecycle state.
