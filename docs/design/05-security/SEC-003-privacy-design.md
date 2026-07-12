# SEC-003 Privacy Design

## Personal Data Inventory

| Data | Purpose | Access |
|---|---|---|
| Email address | Login, contact, password reset, inquiry response | User, administrator by role, system email service |
| Name | Account display and administrator identification | User and administrator by role |
| Inquiry message | Support handling | Submitter and authorized administrators |
| Bookmark | Member curation | Member and authorized service logic |
| Audit actor | Accountability | Authorized administrators and operators |
| Email delivery metadata | Delivery and troubleshooting | Operators and authorized administrators |

## Privacy Principles

- Collect only data needed for product and operations.
- Require consent for inquiry submission.
- Avoid exposing account existence in reset flows.
- Restrict administrative views to necessary fields.
- Redact secrets and sensitive content from logs.
- Define retention and deletion or anonymization procedures.

## Data Subject Workflows

The design supports account review, correction of profile data, inquiry history access, and privacy-driven deletion or anonymization where policy allows.

## Retention

Retention periods are defined by business, legal, support, and security needs. Inquiry content, audit records, email delivery metadata, backups, and deleted accounts can have different retention policies.

## Cross-System Privacy

Email provider, object storage, observability platform, backup storage, and CI/CD systems process operational metadata. Each provider must have access controls, data processing terms, and retention settings aligned with YOnLab policy.

## Clean-Room Compliance

Product assets, copy, layout, source, and documentation are independently authored or properly licensed. Reference analysis artifacts are segregated from product deliverables.
