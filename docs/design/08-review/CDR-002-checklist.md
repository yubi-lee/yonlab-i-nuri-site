# CDR-002 Checklist

## Requirements

| Check | Expected evidence |
|---|---|
| Functional scope complete | `REQ-001` covers product workflows and operations |
| Non-functional scope complete | `REQ-002` covers quality attributes |
| Traceability complete | `REQ-003` links every requirement to design and verification |

## Architecture

| Check | Expected evidence |
|---|---|
| System context clear | `SYS-002` identifies actors, external systems, and trust boundaries |
| Runtime flows clear | `SYS-004` defines authentication, CMS, files, search, and observability flows |
| Deployment model clear | `SYS-005` defines environments, topology, rollout, readiness, and secrets |

## Components And Interfaces

| Check | Expected evidence |
|---|---|
| CDD common sections present | Each CDD includes purpose through design decisions |
| API contract complete | `ICD-001` defines public, member, and administrator contracts |
| Data model complete | `ICD-002` defines entities, relationships, constraints, indexes, lifecycle, privacy, audit, and transaction boundaries |
| Provider contracts complete | `ICD-003` and `ICD-004` define storage and email behavior |

## Security And Operations

| Check | Expected evidence |
|---|---|
| Threats mitigated | `SEC-002` maps threats to controls |
| Privacy designed | `SEC-003` defines personal data, access, consent, and retention |
| Operations designed | `OPS-001` through `OPS-005` define configuration, deployment, monitoring, recovery, and runbooks |

## Verification

| Check | Expected evidence |
|---|---|
| Verification layers complete | `VER-001` and `VER-002` cover required test layers |
| Acceptance clear | `VER-003` defines design, product, and clean-room acceptance |
| Quality gates defined | `VER-004` defines gate categories and evidence |
