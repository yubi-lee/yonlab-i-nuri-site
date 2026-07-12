# CDD-005 Search

## 1. Purpose

Provide integrated discovery across resources and support content.

## 2. Scope

Includes query parsing, filters, visibility rules, ranking, pagination, result shaping, and indexing boundaries.

## 3. Responsibilities

- Search resources, notices, articles, and FAQs according to visibility rules.
- Support filters for category, tag, audience, content type, and publication state where authorized.
- Return ranked, paginated results.
- Encapsulate search provider details.

## 4. Non-Responsibilities

Search does not grant access to hidden content, own source-of-record data, or replace CMS validation.

## 5. Components

| Component | Role |
|---|---|
| Query service | Normalizes query and filters |
| Index adapter | Executes provider-specific search |
| Visibility filter | Applies public, member, and administrator scopes |
| Result mapper | Produces stable API response items |

## 6. Provided Interfaces

Provides search API and internal indexing commands for content changes.

## 7. Consumed Interfaces

Consumes content records, classification metadata, permissions, search index, and observability services.

## 8. Dependencies

Depends on PostgreSQL full-text search or a search engine provider, database source records, and indexing workers or triggers.

## 9. Data Structures

Search documents include id, type, title, summary, body text, category, tags, audience, publication state, timestamps, ranking fields, and permissions scope.

## 10. Normal Processing

Search validates input, applies visibility, executes provider query, maps results, adds highlights where supported, and returns pagination metadata.

## 11. Error And Exception Handling

Invalid filters return validation errors. Provider timeout returns a controlled service error. Empty result sets return a successful response with no items.

## 12. State And Lifecycle

Search index entries are created, updated, hidden, or removed when source content lifecycle changes.

## 13. Concurrency And Transactions

Content writes update search through transactional outbox, synchronous index update, or reliable retry process. Stale index entries must not expose hidden content.

## 14. Security Controls

Controls include query parameter binding, visibility filtering, output encoding, rate limiting, and avoidance of sensitive field indexing.

## 15. Configuration

Configuration includes provider type, index name, query timeout, page-size limits, highlighting, and ranking weights.

## 16. Performance

Search uses indexes, bounded page sizes, timeouts, and result caching where appropriate.

## 17. Scalability

The search boundary supports migration from relational search to dedicated search infrastructure as content volume and ranking needs grow.

## 18. Observability

Metrics include query latency, zero-result rate, provider errors, timeout rate, and indexing lag.

## 19. Testability

Tests cover query parsing, filters, permission scope, ranking expectations, provider contract, timeout behavior, and indexing lifecycle.

## 20. Design Decisions

Search is a service boundary rather than inline query logic so ranking and provider choices can evolve.
