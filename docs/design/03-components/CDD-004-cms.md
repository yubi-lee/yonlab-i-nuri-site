# CDD-004 CMS

## 1. Purpose

Provide administrator workflows for managing product content, classification, inquiries, users, and operational records.

## 2. Scope

Includes CMS operations for Resource, Notice, Article, FAQ, Category, Tag, Inquiry, User, attachments, and audit review.

## 3. Responsibilities

- Enforce administrator authorization.
- Provide list, search, create, update, archive, delete, or disable workflows according to entity rules.
- Validate entity-specific fields and lifecycle transitions.
- Record audit logs for privileged mutations.
- Preserve referential integrity and publication rules.

## 4. Non-Responsibilities

The CMS does not bypass API authorization, directly manipulate object storage without metadata, or expose draft content to public users.

## 5. Components

| Component | Role |
|---|---|
| CMS API service | Entity validation and transaction orchestration |
| CMS frontend | Administrator forms, tables, filters, and status controls |
| Workflow policy | Entity lifecycle and allowed transitions |
| Audit writer | Privileged operation records |
| Attachment manager | Resource file association |

## 6. Provided Interfaces

Provides administrator APIs for entity lists, detail where applicable, create, update, lifecycle changes, attachment management, and audit review.

## 7. Consumed Interfaces

Consumes authentication, RBAC, database, storage, search indexing, audit, and observability interfaces.

## 8. Dependencies

Depends on user and role records, domain entities, database constraints, object storage, structured logs, and email service where inquiry notifications are configured.

## 9. Data Structures

Data includes Resource, Notice, Article, FAQ, Category, Tag, Inquiry, User, ResourceAttachment, AuditLog, pagination envelope, and validation error envelope.

## 10. Normal Processing

Administrators list and filter records, submit validated mutations, receive normalized responses, and see updated entity state. Publication changes update visibility and search behavior.

## 11. Error And Exception Handling

Entity not found, invalid transition, duplicate slug, unsafe deletion, unauthorized access, and stale update conflicts return explicit errors. Errors include correlation ID.

## 12. State And Lifecycle

Content supports draft, published, and archived states. Inquiries support received, in-progress, resolved, and closed states. Users support active and disabled states with role policy.

## 13. Concurrency And Transactions

CMS writes are transactional with audit records. Conflicting updates use database constraints, version fields, or last-write policy with audit visibility.

## 14. Security Controls

Controls include RBAC, least privilege, last-privileged-admin protection, field-level validation, IDOR prevention, audit logging, and personal-data minimization in lists.

## 15. Configuration

Configurable values include page sizes, file limits, allowed content statuses, inquiry status vocabulary, and notification rules.

## 16. Performance

Lists use pagination, indexes, and bounded filters. CMS file operations stream bytes and avoid loading large lists without pagination.

## 17. Scalability

CMS services scale with shared database, object storage, and search indexing. Long-running side effects use asynchronous workers or outbox patterns.

## 18. Observability

CMS writes emit audit logs, structured application logs, metrics for success/failure, and alerts for unusual privilege or replay events.

## 19. Testability

Tests cover per-entity lifecycle, authorization denial, audit records, validation errors, search/filter behavior, file association, and representative administrator journeys.

## 20. Design Decisions

Eight CMS entity types are managed through shared patterns with entity-specific lifecycle policy to avoid duplicated behavior while preserving domain constraints.
