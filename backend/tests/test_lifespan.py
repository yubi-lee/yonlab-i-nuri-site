from fastapi.testclient import TestClient

from app.main import app


def test_lifespan_initializes_once_for_testclient_context():
    before = getattr(app.state, "startup_runs", 0)
    with TestClient(app) as client:
        assert client.get("/health/live").status_code == 200
        assert app.state.startup_runs == before + 1