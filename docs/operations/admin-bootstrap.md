# Production administrator bootstrap

This runbook separates demonstration seed accounts from the first production administrator account.

## Account types

| Account type | Source | Purpose | Production use |
|---|---|---|---|
| Demo seed administrator | `app.seed` using `ADMIN_EMAIL` / `ADMIN_PASSWORD` or demo defaults | Local verification, E2E, sample CMS workflows | Do not rely on it for production access |
| Production administrator | `scripts/bootstrap-admin.ps1` / `python -m app.admin_bootstrap` using `PRODUCTION_ADMIN_*` | One-time controlled creation or credential rotation | Use for the first real operator account |

The content seed remains demo-oriented and idempotent for verification. Production environments should create or rotate the real administrator through the bootstrap procedure after migrations and before external access.

## Required inputs

- `PRODUCTION_ADMIN_EMAIL`: email address for the operating administrator.
- `PRODUCTION_ADMIN_INITIAL_PASSWORD`: one-time initial password supplied from a secret manager, shell environment, or hidden prompt.
- `PRODUCTION_ADMIN_NAME`: display name; defaults to `Production Administrator`.
- `DATABASE_URL`: target database connection string.

Never commit real administrator passwords, shell history containing passwords, screenshots of secrets, or production `.env` files.

## Password policy

The bootstrap command rejects weak passwords. The initial password must:

- be 14 to 128 characters long;
- include lowercase, uppercase, digit, and symbol characters;
- avoid common product or role words such as password, admin, yonlearn, or yonlab.

Operators should rotate the initial password after first login where the product flow supports it. Until then, rotate by re-running the bootstrap procedure for the same active administrator email or through an approved database/account runbook.

## Procedure with PowerShell wrapper

Run Alembic first so the target database schema exists. Then set the production email and database URL, and enter the password through the hidden prompt when possible:

```powershell
$env:DATABASE_URL = "postgresql+psycopg://<user>:<password>@<host>:5432/<database>"
$env:PRODUCTION_ADMIN_EMAIL = "operator@example.test"
$env:PRODUCTION_ADMIN_NAME = "Production Administrator"
.\scripts\bootstrap-admin.ps1
```

For non-interactive automation, inject `PRODUCTION_ADMIN_INITIAL_PASSWORD` from a protected secret store into the process environment and clear it after the command completes.

## Procedure with backend module

```powershell
Push-Location backend
..\.venv\Scripts\python.exe -m app.admin_bootstrap
Pop-Location
```

The module reads the same `PRODUCTION_ADMIN_*` environment variables. It prints only status, reason, and non-secret email metadata. It never prints the password.

## Idempotency and duplicate prevention

- If no active administrator exists, the command creates the requested administrator.
- If the requested email belongs to an existing user and no active administrator exists, the command promotes that user and rotates the password.
- If an active administrator with the same email exists, the command rotates that administrator's password and updates the display name.
- If an active administrator with another email already exists, the command exits successfully without creating a duplicate administrator.

Record each production bootstrap or rotation in the operations log because this out-of-band command does not have an authenticated CMS actor for audit-log attribution.

## Production checklist

- [ ] Production database migrations are current.
- [ ] `DATABASE_URL` targets the intended production database.
- [ ] Real password is supplied from a protected channel, not committed files.
- [ ] Command output is archived without secrets.
- [ ] At least one real active administrator can log in.
- [ ] Demo seed accounts are removed, disabled, or isolated before external launch.
