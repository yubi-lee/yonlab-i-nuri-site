# REQ-003 Requirements Traceability

## Traceability Matrix

| Requirement | System Design | Component | Interface | Security/Operations | Verification |
|---|---|---|---|---|---|
| REQ-F-001 | SYS-003 | CDD-001 | ICD-001 | SEC-003 | VER-002 |
| REQ-F-002 | SYS-004 | CDD-003 | ICD-001 | SEC-001 | VER-002 |
| REQ-F-003 | SYS-004 | CDD-003 | ICD-001 | SEC-001 | VER-002 |
| REQ-F-004 | SYS-004 | CDD-003, CDD-007 | ICD-001 | SEC-001, OPS-003 | VER-002 |
| REQ-F-005 | SYS-004 | CDD-003 | ICD-004 | SEC-001, SEC-003 | VER-002 |
| REQ-F-006 | SYS-003 | CDD-004, CDD-006 | ICD-001, ICD-003 | SEC-001 | VER-002 |
| REQ-F-007 | SYS-003 | CDD-004 | ICD-001 | SEC-001 | VER-002 |
| REQ-F-008 | SYS-003 | CDD-004, CDD-008 | ICD-002 | OPS-004 | VER-002 |
| REQ-F-009 | SYS-004 | CDD-005 | ICD-001 | OPS-003 | VER-002 |
| REQ-F-010 | SYS-004 | CDD-001, CDD-008 | ICD-001, ICD-002 | SEC-003 | VER-002 |
| REQ-F-011 | SYS-004 | CDD-004 | ICD-001 | SEC-003 | VER-002 |
| REQ-F-012 | SYS-004 | CDD-004, CDD-007 | ICD-001 | SEC-001, OPS-003 | VER-002 |
| REQ-F-013 | SYS-004 | CDD-003, CDD-004 | ICD-001 | SEC-001 | VER-002 |
| REQ-F-014 | SYS-004 | CDD-006 | ICD-003 | SEC-001, OPS-004 | VER-002 |
| REQ-F-015 | SYS-004 | CDD-003 | ICD-004 | SEC-003, OPS-003 | VER-002 |
| REQ-F-016 | SYS-004 | CDD-007, CDD-008 | ICD-002 | SEC-001, OPS-003 | VER-002 |
| REQ-F-017 | SYS-005 | CDD-002 | ICD-001 | OPS-002, OPS-003 | VER-002 |
| REQ-F-018 | SYS-005, SYS-006 | CDD-007, CDD-008 | ICD-002, ICD-003 | OPS-001, OPS-002, OPS-004, OPS-005 | VER-002, VER-004 |
| REQ-NF-001 | SYS-002 | CDD-003, CDD-006 | ICD-001, ICD-003 | SEC-001, SEC-002 | VER-002 |
| REQ-NF-002 | SYS-002 | CDD-004, CDD-007 | ICD-001, ICD-002 | SEC-003, OPS-004 | VER-002 |
| REQ-NF-003 | SYS-003 | CDD-001 | ICD-001 | SEC-003 | VER-002 |
| REQ-NF-004 | SYS-003 | CDD-001 | ICD-001 | OPS-005 | VER-002 |
| REQ-NF-005 | SYS-003 | CDD-005, CDD-008 | ICD-001, ICD-002 | OPS-003 | VER-002 |
| REQ-NF-006 | SYS-005 | CDD-005, CDD-006, CDD-008 | ICD-003 | OPS-002, OPS-004 | VER-002 |
| REQ-NF-007 | SYS-005 | CDD-002, CDD-007 | ICD-001 | OPS-002, OPS-004, OPS-005 | VER-004 |
| REQ-NF-008 | SYS-004 | CDD-006, CDD-008 | ICD-003, ICD-004 | OPS-004 | VER-002 |
| REQ-NF-009 | SYS-004 | CDD-007 | ICD-005 | OPS-003 | VER-002 |
| REQ-NF-010 | SYS-005 | CDD-006, CDD-008 | ICD-002, ICD-003 | OPS-004 | VER-002 |
| REQ-NF-011 | SYS-003 | CDD-002, CDD-006 | ICD-001, ICD-003, ICD-004 | VER-004 | VER-004 |
| REQ-NF-012 | SYS-006 | CDD-002 | ICD-001 | OPS-001, OPS-002 | VER-004 |
| REQ-NF-013 | SYS-005, SYS-006 | CDD-007 | ICD-001 | OPS-002, VER-004 | VER-004 |
| REQ-NF-014 | SYS-002 | CDD-001 | ICD-001 | DOC-003, SEC-003 | VER-003 |
| REQ-NF-015 | SYS-006 | CDD-002, CDD-007 | ICD-001, ICD-005 | VER-004, OPS-005 | VER-001, VER-002, VER-004 |

## Traceability Rule

Every requirement is linked to at least one system design document, component or interface design, security or operations design, and verification document. The traceability purpose is design completeness and verifiability.
The diagnosis score API is a contract-level implementation of the existing minimization,
correlation, interface-versioning, and deterministic-verification requirements
(REQ-NF-002, REQ-NF-009, REQ-NF-011, and REQ-NF-015). Its endpoint contract is defined in
ICD-001, and its API validation, safe-error, request-ID, and no-persistence scenarios are
verified through VER-002; no new requirement identifier is introduced by this implementation.

## AI Training Platform Traceability Extension

| Requirement | Evidence | Verification |
|---|---|---|
| Tenant access is server-enforced | `backend/app/platform.py::require_membership` | `backend/tests/test_platform_slice.py` |
| Diagnosis evidence is deterministic and privacy-safe | `backend/app/diagnosis.py`, `DiagnosisEvidenceRecord.quoted_span_hash` | Golden vectors and platform slice test |
| Learning state and document grounding are durable | `LearningEnrollment`, `SourceDocument`, `DocumentNode`, `ProcessingJob` | Platform slice and migration tests |
| Knowledge results provide citations or no-answer | `/api/v1/knowledge/search` | Platform slice test |
| AI provider policy is isolated | `services/ai-gateway/app/main.py` | Gateway policy tests and service health |