# CDR-003 Risk Analysis

## Design Risks

| ID | Risk | Impact | Mitigation |
|---|---|---|---|
| R-001 | Object storage provider choice is not selected | File storage delivery could diverge by provider | Decide provider using OD-001 criteria and run storage contract tests |
| R-002 | Email provider choice is not selected | Password reset delivery could be delayed | Decide provider using OD-002 criteria and run email adapter tests |
| R-003 | RPO and RTO values are not numerically selected | Recovery design cannot be fully validated against business targets | Select values using OD-003 criteria and run recovery drills |
| R-004 | Search scale threshold is not selected | Search implementation may be overbuilt or underbuilt | Use OD-004 criteria and define migration trigger |
| R-005 | Hosting platform is not selected | Deployment and rollback details may vary | Use OD-005 criteria and update deployment runbook |
| R-006 | Generic CMS patterns may hide entity-specific rules | Domain rules could be underspecified | Keep entity policy tables and add per-entity acceptance tests |
| R-007 | File metadata and object bytes can drift | Downloads or retention may become inconsistent | Use compensation, reconciliation, and backup consistency checks |
| R-008 | Audit and privacy needs can conflict | Logs may overexpose data or omit evidence | Apply redaction policy and audit-specific retention |
| R-009 | CI/CD platform is not selected | Quality gate and deployment evidence design may remain incomplete | Use OD-006 criteria and update quality-gate and deployment documents |

## Risk Review Rule

Each design risk requires an owner, decision date, mitigation plan, verification method, and acceptance or closure record before production release approval.
