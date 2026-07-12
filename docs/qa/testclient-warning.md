# TestClient deprecation warning diagnosis

Observed environment:

- Python 3.14.4
- FastAPI 0.139.0
- Starlette 1.3.1
- httpx 0.28.1
- Dependency declaration: `fastapi>=0.115,<1` and `httpx>=0.28,<1` in `backend/pyproject.toml`; no lock file exists.
- Import path: `fastapi.testclient` re-exports Starlette's `TestClient`; warning originates at `starlette/testclient.py` importing its HTTPX-backed client.

The warning is emitted by the installed Starlette/TestClient compatibility layer:
`Using httpx with starlette.testclient is deprecated; install httpx2 instead.`

FastAPI's official testing documentation still documents `fastapi.testclient.TestClient` and says it is the Starlette TestClient, with HTTPX required. Therefore this repository does not install an unlisted `httpx2` package or suppress the warning. The current application code does not call deprecated FastAPI startup events anymore, and all `datetime.utcnow()` calls are removed. The remaining warning is external test-library guidance and is tracked until the FastAPI/Starlette-supported migration path is published.

Reference: https://fastapi.tiangolo.com/tutorial/testing/