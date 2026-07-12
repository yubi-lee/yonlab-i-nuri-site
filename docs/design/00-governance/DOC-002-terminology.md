# DOC-002 Terminology

## Product Terms

| Term | Definition |
|---|---|
| YOnLearn Hub | YOnLab learning platform for public learning resources, member services, and administrator operations |
| Public portal | Unauthenticated web experience for discovery, search, content browsing, and inquiry submission |
| Member | Authenticated user with account, bookmarks, and inquiry history |
| Administrator | Privileged user who manages content, users, inquiries, and operational records |
| CMS | Content management system for resources, notices, articles, FAQs, categories, tags, inquiries, and users |
| Resource | Primary learning material with metadata, publication state, classification, and attachments |
| Notice | Operational announcement content |
| Article | Editorial or guide content |
| FAQ | Question-and-answer support content |
| Inquiry | Contact or support request submitted by a visitor or member |
| Audit log | Tamper-resistant operational record of privileged actions |

## Technical Terms

| Term | Definition |
|---|---|
| Access token | Short-lived signed bearer token used for API access |
| Refresh session | Server-side session record for rotating refresh tokens |
| Token replay | Reuse of a refresh token after it has been rotated or revoked |
| RBAC | Role-based access control |
| Object storage | S3-compatible or equivalent storage service for uploaded files |
| Correlation ID | Request-scoped identifier propagated through logs and responses |
| Readiness | Runtime signal that dependencies required for traffic are available |
| Idempotency | Property that repeated identical requests produce one durable effect |

## Data Terms

| Term | Definition |
|---|---|
| Personal data | Data that identifies or contacts a person, including email and inquiry content |
| Retention | Period and policy for preserving or deleting data |
| Soft delete | State-based removal from user workflows while retaining record history |
| UTC policy | All persisted operational timestamps are stored and exchanged in timezone-aware UTC |
