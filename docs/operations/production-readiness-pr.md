# Production readiness PR draft

Use this text when opening a GitHub PR from `feat/production-readiness` to `main`.

## Summary

This PR prepares YOnLearn Hub RC2 for a production-readiness handoff on a Cloud VM + Docker Compose operating model. It does not perform an external deployment, does not commit real secrets, and does not move existing RC tags.

## What changed

- Added production readiness plan and pending-decision mapping.
- Added PostgreSQL backup/restore scripts and runbook.
- Added production administrator bootstrap separated from demo seed accounts.
- Added production env template and readiness preflight checks.
- Added backend `/health` and `/ready` compatibility aliases.
- Expanded deployment, backup/restore, admin bootstrap, and release handoff docs.

## Verification

See `docs/releases/PRODUCTION-READINESS-RC.md` for final command output summary.

## Pending decisions

Object storage provider, email provider, final RPO/RTO approval, final hosting/DNS/TLS details, CI/CD platform, off-host backup storage provider, and final CDR disposition remain pending external decisions.

## Operator notes

Before external production, replace all production env placeholders outside Git, bootstrap a real administrator, disable/remove/isolate demo accounts, verify `/health` and `/ready`, complete an off-host backup decision, and record a restore drill.