# OPS-004 Backup Recovery

## Backup Domains

| Domain | Backup design |
|---|---|
| PostgreSQL | Scheduled encrypted backups with point-in-time recovery where supported |
| Object storage | Versioning or lifecycle-aware backup for file bytes |
| Configuration | Versioned non-secret configuration and protected secret references |
| Email delivery | Provider event retention and EmailDelivery records |
| Audit records | Retention and export policy for accountability |

## RPO And RTO Decision Criteria

Numeric RPO and RTO values are set by YOnLab based on user impact, data-loss tolerance, inquiry response obligations, regulatory needs, cost, and operational staffing. The selected values must be recorded as a design decision and exercised through recovery drills.

## Recovery Procedure

1. Identify incident scope and last known good point.
2. Restore PostgreSQL to selected recovery point.
3. Restore or reconcile object storage to match metadata.
4. Restore configuration and rotate compromised secrets if needed.
5. Apply migrations to the expected revision.
6. Start services and validate readiness.
7. Run smoke checks, data consistency checks, and audit review.
8. Record recovery evidence and follow-up actions.

## Consistency Checks

Recovery validates user/session integrity, content visibility, file metadata versus object storage, search index consistency, email delivery state, audit-log continuity, and backup encryption status.

## Disaster Recovery

Disaster recovery covers regional outage, database loss, object storage loss, provider credential compromise, deployment rollback, and administrative lockout.
