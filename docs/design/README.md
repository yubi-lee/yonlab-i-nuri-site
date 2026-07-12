# YOnLearn Hub Production Target Design

## Metadata

| Field | Value |
|---|---|
| Version | 1.0-draft |
| Status | Draft for Internal Design Review |
| Baseline | YOnLearn Hub Production-Ready Target Design |
| Owner | YOnLab Engineering |
| Reviewer | YOnLab Internal Design Review |

## Purpose

This package defines the target system design for YOnLearn Hub. It is the reference for product design review, implementation planning, security review, operations planning, and verification planning.

The documents describe the completed system as it must operate in production. Repository source and prior analysis are evidence for domain language, selected technology, and architectural constraints, but they do not limit the design baseline.

## Document Set

| Area | Documents |
|---|---|
| Governance | Document control, terminology, design principles, design decisions |
| Requirements | System requirements, non-functional requirements, requirements traceability |
| System | System design, context, logical architecture, runtime flows, deployment, development system |
| Components | Frontend, backend API, authentication, CMS, search, storage, audit and observability, database |
| Interfaces | API, database, file storage, email, error catalog |
| Security | Security architecture, threat model, privacy design |
| Operations | Configuration, deployment, logging and monitoring, backup and recovery, runbook |
| Verification | Verification strategy, test design, acceptance criteria, quality gates |
| Review | Critical design review package, checklist, risk analysis, review record |

## Document Index

- [DOC-001 Document Control](00-governance/DOC-001-document-control.md)
- [DOC-002 Terminology](00-governance/DOC-002-terminology.md)
- [DOC-003 Design Principles](00-governance/DOC-003-design-principles.md)
- [DOC-004 Design Decisions](00-governance/DOC-004-design-decisions.md)
- [REQ-001 System Requirements](01-requirements/REQ-001-system-requirements.md)
- [REQ-002 Non-Functional Requirements](01-requirements/REQ-002-non-functional-requirements.md)
- [REQ-003 Requirements Traceability](01-requirements/REQ-003-requirements-traceability.md)
- [SYS-001 System Design Description](02-system/SYS-001-system-design-description.md)
- [SYS-002 System Context](02-system/SYS-002-system-context.md)
- [SYS-003 Logical Architecture](02-system/SYS-003-logical-architecture.md)
- [SYS-004 Runtime Data Flow](02-system/SYS-004-runtime-data-flow.md)
- [SYS-005 Deployment Architecture](02-system/SYS-005-deployment-architecture.md)
- [SYS-006 Development System](02-system/SYS-006-development-system.md)
- [CDD-001 Frontend](03-components/CDD-001-frontend.md)
- [CDD-002 Backend API](03-components/CDD-002-backend-api.md)
- [CDD-003 Authentication](03-components/CDD-003-authentication.md)
- [CDD-004 CMS](03-components/CDD-004-cms.md)
- [CDD-005 Search](03-components/CDD-005-search.md)
- [CDD-006 Storage](03-components/CDD-006-storage.md)
- [CDD-007 Audit Observability](03-components/CDD-007-audit-observability.md)
- [CDD-008 Database](03-components/CDD-008-database.md)
- [ICD-001 API Interface](04-interfaces/ICD-001-api-interface.md)
- [ICD-002 Database Interface](04-interfaces/ICD-002-database-interface.md)
- [ICD-003 File Storage Interface](04-interfaces/ICD-003-file-storage-interface.md)
- [ICD-004 Email Interface](04-interfaces/ICD-004-email-interface.md)
- [ICD-005 Error Catalog](04-interfaces/ICD-005-error-catalog.md)
- [SEC-001 Security Architecture](05-security/SEC-001-security-architecture.md)
- [SEC-002 Threat Model](05-security/SEC-002-threat-model.md)
- [SEC-003 Privacy Design](05-security/SEC-003-privacy-design.md)
- [OPS-001 Configuration](06-operations/OPS-001-configuration.md)
- [OPS-002 Deployment](06-operations/OPS-002-deployment.md)
- [OPS-003 Logging Monitoring](06-operations/OPS-003-logging-monitoring.md)
- [OPS-004 Backup Recovery](06-operations/OPS-004-backup-recovery.md)
- [OPS-005 Operations Runbook](06-operations/OPS-005-operations-runbook.md)
- [VER-001 Verification Strategy](07-verification/VER-001-verification-strategy.md)
- [VER-002 Test Design](07-verification/VER-002-test-design.md)
- [VER-003 Acceptance Criteria](07-verification/VER-003-acceptance-criteria.md)
- [VER-004 Quality Gates](07-verification/VER-004-quality-gates.md)
- [CDR-001 Review Package](08-review/CDR-001-review-package.md)
- [CDR-002 Checklist](08-review/CDR-002-checklist.md)
- [CDR-003 Risk Analysis](08-review/CDR-003-risk-analysis.md)
- [CDR-004 Review Record](08-review/CDR-004-review-record.md)
## Target System Scope

YOnLearn Hub includes a public learning portal, member services, administrator CMS, authentication and session management, password reset, integrated search, content management, bookmark and inquiry workflows, file upload and download, email delivery, audit logging, structured logs, metrics, alerts, backup and recovery, and reproducible deployment.

## Verification

Run the design-document gate before review:

```powershell
.\scripts\verify-design-docs.ps1
```

The gate checks required documents, requirement identifiers, traceability, prohibited implementation-status language, local absolute paths, relative links, Mermaid fences, and placeholder markers.
