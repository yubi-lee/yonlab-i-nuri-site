# CDD-007 Audit Observability

## 1. Purpose

Provide accountability, diagnosis, monitoring, alerting, and incident evidence across the platform.

## 2. Scope

Includes audit logs, structured application logs, correlation IDs, metrics, alerts, dashboards, and evidence retention.

## 3. Responsibilities

- Record privileged and security-sensitive actions.
- Propagate correlation IDs.
- Emit structured logs and metrics.
- Trigger alerts for defined conditions.
- Preserve incident evidence without leaking secrets.

## 4. Non-Responsibilities

Observability does not replace business records, store raw secrets, or grant administrative privileges.

## 5. Components

| Component | Role |
|---|---|
| Correlation middleware | Creates and propagates request identifiers |
| Audit writer | Persists privileged action records |
| Structured logger | Emits machine-readable logs |
| Metrics emitter | Records counters, gauges, and histograms |
| Alert rules | Detect operational and security conditions |

## 6. Provided Interfaces

Provides audit-log query, log events, metric streams, alert events, and dashboard inputs.

## 7. Consumed Interfaces

Consumes request context, user identity, domain events, provider operation results, and security events.

## 8. Dependencies

Depends on database audit storage, log collector, metrics backend, alert manager, dashboard tool, and retention policy.

## 9. Data Structures

Audit event fields include actor, action, entity type, entity ID, details, timestamp, correlation ID, source IP category where allowed, and result.

## 10. Normal Processing

Each request receives a correlation ID. Domain services emit events. Privileged mutations write audit records inside transaction boundaries. Metrics and logs are emitted at decision points.

## 11. Error And Exception Handling

Logging failure must not expose secrets or crash non-critical user workflows. Audit persistence failure for privileged writes fails the write or uses a durable outbox according to policy.

## 12. State And Lifecycle

Audit logs follow retention and export policy. Metrics follow aggregation policy. Incident evidence follows legal and operational retention requirements.

## 13. Concurrency And Transactions

Audit records for database writes are committed with the write transaction where feasible. Outbox patterns preserve event durability across provider boundaries.

## 14. Security Controls

Controls include log redaction, personal-data minimization, immutable audit retention, access control for audit views, and alerting on suspicious events.

## 15. Configuration

Configuration includes log level, sinks, metric namespace, alert thresholds, retention, sampling, and redaction rules.

## 16. Performance

Observability uses non-blocking emission where safe and bounded payloads. High-volume events are sampled only when sampling does not compromise audit needs.

## 17. Scalability

Logs and metrics are shipped to external systems designed for aggregation. Audit tables are indexed and retained according to policy.

## 18. Observability

This component observes itself through exporter health, queue depth, dropped event counts, and alert delivery status.

## 19. Testability

Tests cover correlation propagation, audit emission, redaction, metric names, alert rule conditions, and audit query permissions.

## 20. Design Decisions

Audit and observability are designed together because security incidents need both durable action records and runtime context.
