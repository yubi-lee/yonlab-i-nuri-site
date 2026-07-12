# DOC-004 Design Decisions

## Accepted Decisions

| ID | Decision | Rationale | Impact |
|---|---|---|---|
| DD-001 | Use React for the web application | Supports rich public, member, and CMS workflows in one client architecture | Frontend verification includes component, accessibility, and E2E coverage |
| DD-002 | Serve production web assets through Nginx or an equivalent web service layer | Provides static asset delivery, caching, security headers, and reverse proxy options | Deployment design includes a web tier before the API |
| DD-003 | Use FastAPI for the application API | Provides typed request validation, OpenAPI contracts, and async-compatible service boundaries | API contracts are versioned under `/api/v1` |
| DD-004 | Use PostgreSQL as the system of record | Supports relational integrity, indexing, transactions, and mature backup tooling | Database design centers on PostgreSQL features and migrations |
| DD-005 | Use object storage for file bytes | Decouples file durability and scale from application nodes | File metadata remains in PostgreSQL and bytes reside in storage |
| DD-006 | Use provider-backed email delivery | Password reset and operational notifications require reliable delivery and auditability | Email delivery has a defined adapter and tracking model |
| DD-007 | Use rotating refresh sessions with replay detection | Reduces account risk from stolen refresh tokens | Refresh token reuse revokes related sessions and raises security telemetry |
| DD-008 | Use structured logs, metrics, and alerts | Operations require observable behavior and incident evidence | Correlation IDs, audit logs, metrics, and alerts are required |
| DD-009 | Use Docker Compose for reproducible development and verification | Local services must be started with consistent dependency wiring | Development system includes database, API, frontend, storage-compatible service, and mail capture where practical |
| DD-010 | Use CI/CD quality gates before deployment | Repeatable review needs automated checks beyond local execution | Verification design includes unit, integration, E2E, security, deployment, and recovery checks |

## Open Design Decisions

| ID | Decision Needed | Options | Decision Criteria |
|---|---|---|---|
| OD-001 | Production object storage provider | Managed S3, compatible object storage, cloud-specific blob storage | Security controls, lifecycle policy, cost, region, backup support |
| OD-002 | Production email provider | SMTP relay, transactional email API, cloud email service | Deliverability, audit logs, bounce handling, secret management |
| OD-003 | Numeric RPO and RTO | Product-tier-specific targets | Business impact, cost, data-loss tolerance, recovery testing capacity |
| OD-004 | Search engine upgrade threshold | PostgreSQL full-text, OpenSearch-compatible service | Content volume, ranking needs, operations cost |
| OD-005 | Hosting platform | Managed container platform, VM-based deployment, orchestrated containers | Operations maturity, rollback needs, cost, security controls |
| OD-006 | CI/CD platform | GitHub Actions, GitLab CI, Azure DevOps, managed deployment pipeline | Quality gates, approvals, artifact provenance, rollback automation |
