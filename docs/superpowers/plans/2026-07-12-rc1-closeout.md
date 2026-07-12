# RC1 Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (not used; inline execution in this session).

**Goal:** Remove controllable deprecation warnings, make `verify.ps1` the complete local gate, strengthen CMS evidence, and prepare a reviewable first commit without committing.

**Architecture:** Keep existing FastAPI/SQLAlchemy/React architecture. Replace startup event registration with one lifespan context, standardize UTC at service boundaries, and make verification orchestration own only the processes it starts.

**Tech Stack:** FastAPI, SQLAlchemy, Alembic, Pydantic, Ruff, pytest, Vitest, Vite, Playwright, PowerShell.

## Global Constraints

- Do not add new product scope.
- Do not install packages until compatibility is checked.
- Docker absence remains BLOCKED, not PASS or FAIL.
- Do not commit or tag automatically.

### Task 1: Warning inventory and tests

**Files:** `backend/tests/test_lifespan.py`, `backend/tests/test_datetime_policy.py`, `backend/pyproject.toml`.

- Add failing lifespan test proving startup runs once through TestClient.
- Add failing UTC test proving issued expiry and persisted session timestamps are aware UTC.
- Record installed Python/FastAPI/Starlette/httpx versions and warning import path.
- Run targeted tests and capture RED output.

### Task 2: Runtime warning fixes

**Files:** `backend/app/main.py`, all files returned by `rg "datetime\\.utcnow" backend`, `backend/pyproject.toml`.

- Move startup body into `@asynccontextmanager` lifespan without changing order.
- Replace naive UTC generation with `datetime.now(UTC)` and preserve DB/API serialization compatibility.
- Move Ruff top-level `ignore` to `lint.ignore` with identical values.
- Run targeted GREEN tests, then backend tests.

### Task 3: Integrated verification

**Files:** `scripts/verify.ps1`, `scripts/verify-docker.ps1`, `docs/qa/verify-run.md`.

- Check commands and ports before mutations.
- Run Ruff, pytest, frontend lint/typecheck/test/build, isolated migration, seed twice, owned E2E servers/readiness/Playwright, cleanup in `finally`, secret/ignored-file scan, git status, and optional Docker.
- Distinguish PASS/FAIL/BLOCKED and preserve existing processes.
- Add regression test or script smoke evidence for cleanup and readiness behavior.

### Task 4: CMS evidence and first-commit review

**Files:** `docs/qa/admin-cms-matrix.md`, `.gitignore`, `docs/qa/test-report.md`.

- Build an eight-entity matrix covering list/search/create/update/delete-or-deactivate/authorization/audit/backend/frontend/E2E evidence.
- Add representative E2E references for resource, notice/article, category/tag, inquiry, and user authorization.
- Extend ignore rules for secrets, DBs, volumes, node modules, build/test artifacts, caches, reference originals, logs, and PIDs.
- Run `git status --short`, secret scan, and review only; do not commit.