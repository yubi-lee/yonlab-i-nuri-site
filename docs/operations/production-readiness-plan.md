# Production readiness plan

Date: 2026-07-13

Scope: post-RC2 operating decision record and deployment readiness baseline for YOnLearn Hub. This document is intentionally limited to operations planning. It does not change application behavior, seed data, Docker configuration, or release tags.

Related review record: [CDR-004 Review Record](../design/08-review/CDR-004-review-record.md)

## 1. Deployment environment candidates

| Candidate | Strengths | Risks / costs | Fit for first production |
|---|---|---|---|
| Single VPS + Docker Compose | Lowest complexity, close to current Docker verification, fast setup, easy operator mental model | Single-machine failure domain, manual hardening burden, backup discipline required | Acceptable only for a small pilot or internal demo with clear backup/restore drills |
| Cloud VM + Docker Compose | Keeps current Compose packaging while adding cloud disks, snapshots, firewall/IAM, monitoring, managed DNS/LB options | Still mostly self-operated; scaling and zero-downtime deploys are limited | Recommended first production baseline |
| Managed PaaS | Managed deploys, health checks, logs, TLS, rollback, and often managed Postgres integrations | Requires platform-specific adaptation, potential vendor lock-in, less direct parity with current Compose | Strong later option after traffic, support, and CI/CD requirements are clearer |

## 2. Recommended option

Recommended baseline: **Cloud VM + Docker Compose** for the first production candidate.

Reasons:

- It preserves the verified Docker Compose deployment shape from RC2.
- It is a smaller operational step than a PaaS migration.
- It can use cloud firewall rules, volume snapshots, managed DNS, and external backup storage.
- It keeps rollback understandable: redeploy a known image/tag, restore a known database backup, and verify health endpoints.
- It gives enough production discipline while the team validates actual traffic, content governance, inquiry volume, and administrator workflows.

Single VPS remains acceptable for a time-boxed internal pilot, not for external production without documented backup and restore proof. Managed PaaS should be revisited when CI/CD, preview environments, autoscaling, and operational staffing needs are clearer.

## 3. Domain and HTTPS strategy

- Use a dedicated production domain, for example `learn.yonlab.example`, with `www` redirect policy decided before launch.
- Terminate HTTPS at a reverse proxy or cloud load balancer.
- Use Let's Encrypt or cloud-managed certificates with automatic renewal.
- Enforce HTTP to HTTPS redirect.
- Set production CORS to the exact frontend origin only.
- Keep `/health/live` and `/health/ready` available for platform health checks, but do not expose internal diagnostics.

Definition of done:

- DNS record points to the selected platform.
- Certificate auto-renewal is configured and tested.
- HTTP redirect and HTTPS response are verified.
- Production `CORS_ORIGINS` is exact and documented.

## 4. PostgreSQL backup and recovery policy

Initial production objective proposal:

- RPO: 24 hours for pilot production; tighten to 4 hours when real external users are onboarded.
- RTO: 4 hours for pilot production; tighten to 1 hour when contractual or institutional commitments exist.
- Backup frequency: daily logical dump plus platform snapshot if available.
- Backup retention: 7 daily, 4 weekly, 3 monthly copies for production.
- Backup storage: off-host object storage or cloud backup vault; never only on the application VM.
- Recovery drills: at least once before launch and then quarterly.
- Current automation: `scripts/backup-postgres.ps1` creates timestamped custom-format dumps from the Docker Compose `postgres` service; `scripts/restore-postgres.ps1` restores an explicitly named dump only after an interactive confirmation or `-Force`.
- Runbook: [Backup and restore](backup-restore.md).

Definition of done:

- A restore drill creates a fresh database from backup.
- Application starts against the restored database.
- Admin login, resource search, inquiry list, and health endpoints are verified after restore.
- Drill result is recorded in operations notes.
- Backup artifacts are excluded from Git and copied to off-host storage before production use.

## 5. `.env` and secrets policy

- Do not commit `.env` files or secrets.
- Store production secrets in a cloud secret manager, platform environment settings, or an encrypted operations vault.
- Required secrets include `JWT_SECRET`, admin bootstrap credentials, database URL/password, email provider credentials, and object storage credentials when enabled.
- `JWT_SECRET` must be generated with high entropy and rotated through a documented maintenance window.
- Local development may use `.env`, but production values must not be copied into development machines or screenshots.
- Verification scripts may use dummy values only.

Definition of done:

- Production secret inventory exists.
- Secret owner and rotation cadence are assigned.
- No production secret appears in Git, logs, reports, screenshots, or seed data.

## 6. Initial administrator account policy

- Bootstrap one administrator through environment-controlled seed or a one-time admin creation runbook.
- Force password rotation immediately after first login where the product flow supports it; until then, rotate through operations procedure.
- Use a unique email alias controlled by the operating organization.
- Disable or remove sample users and sample inquiries before external production.
- Record all administrator changes through audit logs.

Definition of done:

- Initial admin creation procedure is documented.
- Sample accounts are removed, disabled, or isolated from production.
- At least two authorized operators can recover admin access without sharing a password.

## 7. Object Storage transition criteria

Current RC2 storage is suitable for local verification, not long-term production file operations.

Transition to object storage when any of the following are true:

- Production attachments are enabled for real users.
- File retention exceeds the lifecycle of one VM disk.
- Required backup/recovery scope includes uploaded files.
- Antivirus/quarantine workflow is required.
- File serving requires signed URLs, CDN, or access logging.

Preferred requirement: S3-compatible object storage adapter with bucket lifecycle policy, server-side encryption, private bucket defaults, checksum recording, and storage contract tests.

Definition of done:

- Provider or mandatory adapter requirements are approved.
- Upload/download/delete contract tests pass.
- Backup/retention policy includes file objects.
- Security review covers signed URL and quarantine behavior.

## 8. Email provider transition criteria

A real provider is required before password reset, notifications, or operational email are enabled for real users.

Provider selection criteria:

- Verified domain sender identity.
- SPF/DKIM/DMARC configured.
- API credentials stored as secrets.
- Sandbox and production sending modes separated.
- Bounce/complaint handling documented.
- Email templates reviewed for privacy and support wording.

Definition of done:

- Provider is selected or provider-agnostic criteria are formally approved.
- Password reset and notification flows have contract tests.
- Delivery and failure events are observable.

## 9. Logs and monitoring baseline

Minimum production signals:

- Uptime and readiness for frontend and backend.
- PostgreSQL disk, CPU, memory, connection count, and backup age.
- HTTP 5xx rate and latency trend.
- Authentication failure rate and administrator actions.
- Error logs with request ID, without secrets or personal data.
- Disk usage for Docker volumes and logs.
- Alert channel with owner and escalation path.

Initial alert thresholds:

- `/health/ready` fails for 3 consecutive checks.
- HTTP 5xx rate exceeds 2% for 10 minutes.
- Database disk usage exceeds 75% warning and 85% critical.
- Backup age exceeds 30 hours for daily backup policy.
- Repeated admin login failures exceed agreed threshold.

Definition of done:

- Dashboard exists for the signals above.
- Alerts have named responders.
- A test alert is sent and acknowledged.

## 10. Incident response and rollback

Rollback levels:

1. Application rollback: redeploy previous known-good Git tag or image.
2. Configuration rollback: restore previous environment/secrets configuration.
3. Database recovery: restore from the latest verified backup when data corruption is confirmed.
4. Content rollback: archive or remove problematic content through admin CMS where possible.

Incident procedure:

- Declare incident owner.
- Freeze non-essential changes.
- Capture current tag, container status, logs, database backup age, and user-visible impact.
- Choose rollback level.
- Verify `/health/ready`, login, search, resource detail, admin dashboard, and inquiry flow after rollback.
- Record post-incident review and prevention action.

Definition of done:

- Previous tag rollback is rehearsed.
- Database restore drill is rehearsed.
- Incident note template exists.

## 11. CDR condition linkage

| Condition | Production readiness plan impact | Status after this document | Remaining action |
|---|---|---|---|
| PC-001 Object Storage provider / adapter | Defines transition criteria and mandatory adapter requirements | Partially addressed | Approve provider or adapter requirement record; add contract tests and update storage/security design docs |
| PC-002 Email Provider / selection criteria | Defines provider selection criteria and operational controls | Partially addressed | Select provider or approve provider-agnostic criteria; add email contract tests and update auth/privacy docs |
| PC-003 RPO/RTO objectives | Proposes numeric RPO/RTO and drill cadence | Addressable by approval | Product/operations must approve objectives and record first restore drill |
| PC-004 Search expansion criteria | Defines an operational review trigger for search expansion below | Partially addressed | Approve thresholds and update search/API verification docs |
| PC-005 Hosting platform | Recommends Cloud VM + Docker Compose for first production | Addressable by approval | Operations/security must approve platform and update deployment architecture/runbook |
| PC-006 CI/CD platform | Defines CI/CD as P1 backlog with gates and rollback evidence | Not resolved | Choose CI/CD platform and map pipeline gates to quality gates |
| PC-007 Affected design doc updates | Lists affected documents to update after approvals | Not resolved | Update DOC/CDD/ICD/SEC/OPS/VER docs after PC-001 through PC-006 approvals |
| PC-008 Design-document verification | This work will run design-doc verification | Verification evidence only | Re-run after all affected design docs are updated |
| PC-009 Internal CDR review record | Provides input evidence for review | Not resolved | Internal reviewers must record final disposition |

Search expansion trigger for PC-004:

- More than 5,000 published resources, or
- Search p95 latency above 500 ms for common terms, or
- Relevance complaints become a recurring support category, or
- Weighted ranking, typo tolerance, synonyms, or faceting become launch requirements.

## 12. Remaining CDR items after this plan

Items that still require formal decision or implementation:

- PC-001 provider approval and storage contract tests.
- PC-002 provider approval and email contract tests.
- PC-003 formal RPO/RTO owner approval and first restore drill record.
- PC-004 formal search threshold approval and verification update.
- PC-005 formal hosting platform approval and deployment design update.
- PC-006 CI/CD platform decision.
- PC-007 updates to affected design documents.
- PC-009 final internal CDR disposition.

## 13. P0/P1/P2 backlog

### P0 before external production

| Item | Definition of done |
|---|---|
| Approve hosting baseline | Cloud VM + Docker Compose, single VPS exception, or PaaS choice is approved by operations and security; deployment architecture docs updated |
| Approve RPO/RTO | Numeric RPO/RTO recorded; `scripts/backup-postgres.ps1` or equivalent backup schedule configured; first isolated restore drill using `scripts/restore-postgres.ps1` passes |
| Establish production secrets process | Secret inventory, owners, storage location, and rotation procedure are documented; no secrets in Git/logs |
| Initial admin runbook | Admin bootstrap, rotation, recovery, and sample-account removal procedure is documented and tested |
| Production domain and HTTPS | DNS, TLS, redirect, and exact CORS are configured and verified |
| Monitoring minimum viable dashboard | Readiness, 5xx, latency, database disk, backup age, and alert route are visible and tested |
| Rollback rehearsal | Previous tag redeploy and health smoke pass in a rehearsal environment |

### P1 before broader rollout

| Item | Definition of done |
|---|---|
| CI/CD platform decision | Pipeline runs lint, tests, build, design-doc verification, Docker verification, artifact retention, and approval gates |
| Object storage provider or adapter decision | Provider or adapter requirements approved; contract tests pass; backup/security docs updated |
| Email provider decision | Provider or criteria approved; SPF/DKIM/DMARC planned; email contract tests scoped |
| Search expansion decision | Thresholds approved; monitoring captures search latency and zero-result terms |
| Backup automation hardening | Off-host backup automation, retention, encryption, and restore evidence are recorded |
| Incident runbook | Incident roles, severity levels, comms, rollback, and postmortem template are approved |

### P2 after production stabilization

| Item | Definition of done |
|---|---|
| PaaS reevaluation | Platform economics, operational burden, preview environments, and rollback maturity are compared against VM baseline |
| CDN/static asset optimization | Cache policy, invalidation, and asset fingerprinting are documented and tested |
| Advanced observability | Structured metrics, traces, audit dashboards, and synthetic checks are expanded beyond MVP |
| Content governance workflow | Review/approval lifecycle for real content replaces sample-content assumptions |
| Disaster recovery game day | Full restore and application recovery are rehearsed with timed RPO/RTO evidence |

## 14. Operating checklist before launch

- [ ] Hosting platform approved.
- [ ] Domain and HTTPS verified.
- [ ] Production secrets stored outside Git.
- [ ] Sample accounts and sample inquiries removed or isolated.
- [ ] PostgreSQL backup automation configured.
- [ ] Restore drill completed.
- [ ] Monitoring dashboard and alerts tested.
- [ ] Rollback runbook rehearsed.
- [ ] Object storage decision recorded if real attachments are enabled.
- [ ] Email provider decision recorded if reset/notification email is enabled.
- [ ] CDR conditions updated with evidence and reviewed.
