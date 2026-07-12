# CDD-008 Database

## 1. Purpose

Persist the authoritative relational state for accounts, sessions, content, inquiries, bookmarks, file metadata, email delivery tracking, and audit records.

## 2. Scope

Includes schema design, relationships, constraints, indexes, migrations, transactions, UTC timestamps, retention, and backup compatibility.

## 3. Responsibilities

- Enforce relational integrity and uniqueness.
- Store system-of-record data.
- Support transactional domain operations.
- Provide indexed query paths.
- Maintain migration history.

## 4. Non-Responsibilities

The database does not store raw file bytes, raw refresh tokens, raw reset tokens, or secrets.

## 5. Components

| Component | Role |
|---|---|
| Schema | Tables, columns, relationships, constraints |
| Migration system | Versioned database changes |
| Repository layer | Query and transaction abstractions |
| Backup process | Snapshot and restore support |
| Retention process | Data lifecycle enforcement |

## 6. Provided Interfaces

Provides relational transactions, constraints, indexes, migrations, backup artifacts, and queryable records.

## 7. Consumed Interfaces

Consumes application transactions and migration commands. Supports API, CMS, authentication, storage metadata, email tracking, audit, and reporting.

## 8. Dependencies

Depends on PostgreSQL, migration tooling, connection pooling, backup storage, monitoring, and secrets for database credentials.

## 9. Data Structures

Core entities are User, RolePolicy, RefreshSession, PasswordResetToken, Category, Tag, Resource, ResourceAttachment, Notice, Article, FAQ, Inquiry, Bookmark, AuditLog, FileObject, and EmailDelivery.

## 10. Normal Processing

Application services open transactions, read or mutate records, rely on constraints for integrity, write audit records where needed, and commit or roll back atomically.

## 11. Error And Exception Handling

Constraint violations map to explicit API errors. Deadlocks and transient connection failures are retried where safe. Migration failures stop deployment.

## 12. State And Lifecycle

Records follow defined lifecycle states, UTC timestamps, retention rules, and privacy policy. Soft delete is used where auditability or references require retention.

## 13. Concurrency And Transactions

Database transactions protect CMS writes, refresh rotation, password reset, bookmark uniqueness, and audit consistency. Isolation strategy prevents double-use of security tokens.

## 14. Security Controls

Controls include least-privilege credentials, encrypted transport, backup encryption, row exposure through API only, hashed token storage, and audit access restrictions.

## 15. Configuration

Configuration includes connection URL, pool size, timeout, migration command, backup schedule, retention, and read replica policy where used.

## 16. Performance

Indexes support login, session lookup, content lists, search filters, audit queries, and CMS lists. Long-running reporting avoids blocking transactional workloads.

## 17. Scalability

The schema supports read replicas, partitioning for audit or event tables, and external search indexing when query needs outgrow relational search.

## 18. Observability

Database metrics include connection pool health, query latency, lock waits, migration status, backup status, and replication lag where applicable.

## 19. Testability

Tests cover migrations, constraints, transaction behavior, UTC policy, retention queries, and backup/restore drills.

## 20. Design Decisions

PostgreSQL is the target relational database because the platform needs transactions, constraints, indexing, and mature backup tooling.
