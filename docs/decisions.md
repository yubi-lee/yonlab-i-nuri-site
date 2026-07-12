# Decisions

1. Modular monolith for fewer deployment edges with replaceable search/storage boundaries.
2. Search-led center hero because finding applicable knowledge is the primary intent.
3. Independent navy/teal system to communicate trust without reproducing the reference.
4. PostgreSQL in Docker; SQLite only as local/test fallback.
5. Access tokens now; production refresh rotation is an explicit release gate.
6. Verification scripts must fail closed: missing tools, command exceptions, and child gate failures must produce FAIL or BLOCKED, never inherit stale `$LASTEXITCODE` state.
7. Docker verification uses isolated Compose project names and dependency-ordered restart checks so validation does not stop user processes and does not create restart-induced backend/database tracebacks.
