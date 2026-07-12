# ICD-004 Email Interface

## Interface Summary

The email interface sends transactional messages and tracks delivery state for password reset and operational notifications.

## Operations

| Operation | Input | Output | Success condition |
|---|---|---|---|
| Queue email | template, recipient, locale, variables, correlation ID | EmailDelivery record | Message accepted for delivery |
| Send email | EmailDelivery record | provider response | Provider accepts message |
| Retry email | failed delivery record | updated status | Retry policy applied |
| Handle event | provider event | delivery update | Bounce, delivery, or complaint recorded |

## Data Format

Requests are internal service calls. Provider communication may use SMTP or HTTPS API. Templates render text and HTML variants.

## Required Fields

Required delivery fields include recipient, template key, subject, body variables, status, attempt count, correlation ID, created time, and last attempt time.

## Optional Fields

Optional fields include provider message ID, bounce reason, locale, scheduled send time, and related entity ID.

## Authentication And Authorization

Only backend services may call the email adapter. Provider credentials come from secrets management. User-facing APIs cannot specify arbitrary templates.

## Error Conditions

Errors include template missing, invalid recipient, provider timeout, provider rejection, bounce, complaint, exhausted retries, and disabled delivery configuration.

## Timeout, Retry, And Idempotency

Provider calls have short timeouts. Retry policy uses exponential backoff with maximum attempts. Idempotency uses delivery record ID and provider message ID.

## Transaction Boundary

Domain operations create delivery records inside the relevant transaction or outbox. Sending occurs after commit to avoid emailing rolled-back events.

## Security Considerations

Emails must not contain raw passwords or sensitive tokens beyond single-use reset links. Logs store delivery metadata, not full secret URLs.

## Observability

Metrics include send attempts, accepted count, retry count, bounce count, complaint count, latency, and provider errors.
