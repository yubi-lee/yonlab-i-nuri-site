# OPS-001 Configuration

## Environment Classes

| Environment | Configuration goal |
|---|---|
| Development | Fast setup with safe local values and service substitutes |
| Verification | Reproducible gates with deterministic dependencies |
| Staging | Production-like validation with protected secrets and managed services |
| Production | Hardened runtime with managed secrets, monitoring, backups, and controlled access |

## Configuration Categories

| Category | Examples | Source |
|---|---|---|
| Application | app name, environment, public URL | Environment or config service |
| Database | PostgreSQL URL, pool size, timeout | Secret manager and deployment config |
| Authentication | JWT signing key, token lifetimes, password policy | Secret manager and protected config |
| CORS and web | allowed origins, security headers | Deployment config |
| Storage | bucket, region, endpoint, size limits, type allowlist | Protected config and secret manager |
| Email | provider, sender, template namespace, retry policy | Protected config and secret manager |
| Observability | log level, metrics endpoint, alert namespace | Protected config |
| Backup | schedule, retention, encryption key reference | Operations config |

## Configuration Keys

| Key | Environment alignment | Purpose | Secret |
|---|---|---|---|
| `APP_NAME` | existing key | Application display and service name | No |
| `ENVIRONMENT` | existing key | Runtime environment class | No |
| `DATABASE_URL` | existing key | PostgreSQL connection URL | Yes |
| `JWT_SECRET` | existing key | Access token signing secret | Yes |
| `ACCESS_TOKEN_MINUTES` | existing key | Access token lifetime | No |
| `REFRESH_TOKEN_DAYS` | existing key | Refresh session lifetime | No |
| `CORS_ORIGINS` | existing key | Exact browser origin allowlist | No |
| `ADMIN_EMAIL` | existing key | Demo seed administrator email for local verification and sample CMS workflows | May be personal data |
| `ADMIN_PASSWORD` | existing key | Demo seed administrator password for local verification only | Yes |
| `PRODUCTION_ADMIN_EMAIL` | existing key | One-time production administrator bootstrap email | May be personal data |
| `PRODUCTION_ADMIN_INITIAL_PASSWORD` | existing key | One-time production administrator initial password supplied from protected channel | Yes |
| `PRODUCTION_ADMIN_NAME` | existing key | Production administrator display name for bootstrap | No |
| `UPLOAD_DIR` | existing key | Local development storage root | No |
| `VITE_API_URL` | existing key | Frontend API base URL | No |
| `OBJECT_STORAGE_ENDPOINT` | target key | Object storage endpoint | No |
| `OBJECT_STORAGE_BUCKET` | target key | Object storage bucket | No |
| `OBJECT_STORAGE_REGION` | target key | Object storage region | No |
| `OBJECT_STORAGE_ACCESS_KEY_ID` | target key | Object storage access key | Yes |
| `OBJECT_STORAGE_SECRET_ACCESS_KEY` | target key | Object storage secret key | Yes |
| `EMAIL_PROVIDER` | target key | Email provider selector | No |
| `EMAIL_FROM_ADDRESS` | target key | Approved sender identity | No |
| `EMAIL_PROVIDER_API_KEY` | target key | Email provider credential | Yes |
| `OBSERVABILITY_ENDPOINT` | target key | Log, metric, or trace collector endpoint | May be secret |
| `BACKUP_DESTINATION` | target key | Backup storage destination reference | May be secret |
| `PASSWORD_RESET_TOKEN_MINUTES` | target key | Reset token lifetime | No |
| `SESSION_RETENTION_DAYS` | target key | Refresh-session evidence retention | No |

Target keys extend the environment model for the production-ready design. They are documented here as design inputs and do not require application configuration changes in this documentation task.
## Secrets

Secrets include database credentials, JWT signing keys, storage credentials, email credentials, encryption keys, and CI/CD deployment tokens. They are supplied through protected mechanisms and never appear in source, frontend bundles, logs, or documentation examples.

## Validation

Application startup validates required configuration, safe value shapes, timeout bounds, and provider endpoint presence. Production startup fails closed when required secrets or dependencies are absent.
