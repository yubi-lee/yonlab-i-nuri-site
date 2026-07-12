# OPS-005 Operations Runbook

## Routine Checks

| Check | Action |
|---|---|
| Service health | Verify liveness and readiness |
| Deployment state | Confirm artifact, migration, and release identifiers |
| Backup state | Confirm last successful database and storage backup |
| Alert state | Review active critical and warning alerts |
| Audit state | Review privileged-action anomalies |
| Provider state | Check database, storage, email, and observability provider health |

## Incident Response

1. Triage alert and capture correlation IDs.
2. Identify affected service, endpoint, provider, or data domain.
3. Apply containment, such as disabling a provider integration or pausing deployment.
4. Preserve logs, audit records, provider events, and deployment evidence.
5. Restore service using documented recovery or rollback procedure.
6. Record root cause, impact, remediation, and prevention actions.

## Common Scenarios

| Scenario | Runbook focus |
|---|---|
| Authentication failures | Token signing, database session records, rate limits, replay alerts |
| CMS write failures | Database constraints, audit persistence, authorization, validation errors |
| File upload failures | Policy rejection, object storage, malware scan, metadata consistency |
| Email delivery failures | Provider status, retry queue, template validity, bounce handling |
| Search degradation | Index lag, provider timeout, query latency, fallback behavior |
| Database outage | Readiness, failover, backup, restore, connection pools |
| Bad deployment | Rollback, migration compatibility, smoke checks, artifact provenance |

## Operational Review

Operations review confirms runbooks are executable, alerts are actionable, backups are restorable, secrets are rotatable, deployment is reversible, and incident evidence is retained.
