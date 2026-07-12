# Backup and restore

This runbook covers PostgreSQL logical backups for the Docker Compose deployment shape. It does not replace off-host storage, encryption, retention automation, or restore drills required before production launch.

## Backup

Create a backup from the running Compose `postgres` service:

```powershell
.\scripts\backup-postgres.ps1
```

Defaults:

- service: `postgres`
- database: `yonlearn`
- user: `yonlearn`
- output directory: `backups/`
- filename: `yonlearn-postgres-<UTC timestamp>.dump`

The script runs `pg_dump --format=custom --no-owner --no-acl` inside the PostgreSQL container, copies the dump to the host, verifies the copied file is non-empty, and fails closed on any error. Partial backup files are removed on failure. `backups/` is intentionally ignored by Git.

For an isolated Compose project, pass the project name explicitly:

```powershell
.\scripts\backup-postgres.ps1 -ProjectName yonlearn_restore_drill
```

## Restore

Restore is destructive. Run it only against the intended environment, and prefer a fresh or isolated database when verifying a backup.

```powershell
.\scripts\restore-postgres.ps1 -BackupFile .\backups\yonlearn-postgres-20260713T120000Z.dump
```

Without `-Force`, the script requires an interactive `RESTORE` confirmation. Automation and isolated drills may use `-Force`:

```powershell
.\scripts\restore-postgres.ps1 -BackupFile .\backups\yonlearn-postgres-20260713T120000Z.dump -ProjectName yonlearn_restore_drill -Force
```

The restore script validates that the file exists, is non-empty, uses the `.dump` extension, targets exactly one running Compose `postgres` container, passes `pg_restore --list`, and then runs `pg_restore --clean --if-exists --no-owner --no-acl --exit-on-error --single-transaction`.

## Restore drill checklist

- Start an isolated Compose project or fresh deploy environment.
- Load or create non-production probe data.
- Run `scripts/backup-postgres.ps1`.
- Mutate or clear the probe data.
- Run `scripts/restore-postgres.ps1` with the backup file and `-Force` only in the isolated project.
- Verify application readiness, admin login, resource search, inquiry list, and database probe data after restore.
- Record backup file timestamp, restore duration, operator, and result.

## Production requirements still required

- Store production backups off-host in object storage or a cloud backup vault.
- Encrypt backups at rest and in transit.
- Define retention and deletion policy.
- Assign an accountable restore owner.
- Back up future uploaded attachments separately with checksums until object storage is adopted.
- Record first restore drill evidence before opening external production access.
## Pending production decisions

Local logical backup and isolated restore are executable now. The following remain pending external operations decisions before external production access:

- off-host backup storage provider or vault;
- encryption key ownership and rotation;
- retention automation and deletion approval;
- backup age monitoring and alert routing;
- restore drill owner and quarterly cadence.

Backup age monitoring should alert when the newest approved production backup is older than the RPO threshold. The current pilot proposal is daily backup with an alert when backup age exceeds 30 hours.
