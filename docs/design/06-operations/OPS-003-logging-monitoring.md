# OPS-003 Logging Monitoring

## Logging

Structured logs include timestamp, service, environment, severity, correlation ID, endpoint group, user category where safe, result, latency, and error code. Logs exclude raw passwords, tokens, reset links, secret values, and unnecessary personal data.

## Metrics

| Metric group | Examples |
|---|---|
| API | request count, latency, error rate, readiness failures |
| Authentication | login result, refresh rotation, replay detection, reset requests |
| CMS | mutation count, validation failure, audit write failure |
| Search | query latency, zero-result rate, indexing lag |
| Storage | upload count, rejection reason, provider latency, scan outcome |
| Email | accepted, retry, bounce, complaint, provider latency |
| Database | connection pool, query latency, lock wait, migration state |
| Backup | last success, duration, restore drill status |

## Alerts

Alerts map to runbook entries. Critical alerts include readiness failure, elevated 5xx rate, refresh replay event, audit write failure, backup failure, provider outage, migration failure, and storage consistency error.

## Dashboards

Dashboards cover service health, user journey health, authentication security, CMS operations, search quality, storage/email providers, database health, and backup status.

## Retention

Audit logs, application logs, metrics, traces, provider events, and incident records have retention classes based on operational, security, privacy, and legal needs.
