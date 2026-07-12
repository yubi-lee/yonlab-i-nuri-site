# SYS-003 Logical Architecture

## Layered View

```mermaid
flowchart TB
  UI["React Web Application"] --> Client["API Client"]
  Client --> API["FastAPI API Layer"]
  API --> Auth["Authentication and RBAC"]
  API --> Domain["Domain Services"]
  Domain --> Search["Search Service Boundary"]
  Domain --> Storage["Storage Service Boundary"]
  Domain --> Email["Email Service Boundary"]
  Domain --> Audit["Audit and Observability"]
  Domain --> Data["Repository and Transaction Layer"]
  Data --> Postgres["PostgreSQL"]
  Storage --> ObjectStore["Object Storage"]
  Email --> Provider["Email Provider"]
```

## Logical Responsibilities

| Layer | Responsibility |
|---|---|
| Presentation | Route users through public, member, and administrator workflows |
| API | Validate requests, enforce authentication and authorization, expose versioned contracts |
| Domain services | Apply business rules for content, inquiries, accounts, files, and search |
| Integration services | Encapsulate object storage, email, and observability providers |
| Data layer | Manage transactions, constraints, migrations, and query consistency |

## Cross-Cutting Concerns

Cross-cutting concerns include correlation ID propagation, structured logging, audit logging, metrics, error normalization, UTC timestamps, secret management, privacy limits, and authorization checks.

## Dependency Rule

Higher layers call lower-level service interfaces. Provider-specific code remains behind adapters. Database models do not contain browser or provider concerns.
