# Backup and restore

Use `pg_dump --format=custom`; verify `pg_restore --clean --if-exists` in an isolated database. Back up attachments separately with checksums. Set retention, encryption, RPO, RTO, and an accountable restore owner before launch.
