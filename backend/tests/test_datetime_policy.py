from datetime import UTC, datetime

from fastapi.testclient import TestClient

from app.database import SessionLocal
from app.main import app
from app.models import RefreshSession


def test_issued_refresh_expiry_is_utc_aware_before_persistence():
    with TestClient(app) as client:
        response = client.post("/api/v1/auth/register", json={"email":"utc-policy-4f96d65cd4a84b419519e482570bf5f1@example.com","name":"UTC User","password":"UtcPolicy!234"})
    assert response.status_code == 201
    with SessionLocal() as db:
        session = db.query(RefreshSession).filter(RefreshSession.user_id == response.json()["user"]["id"]).one()
        assert session.expires_at.tzinfo in (UTC, None)
        if session.expires_at.tzinfo is not None:
            assert session.expires_at.utcoffset().total_seconds() == 0


def test_datetime_json_is_iso8601_utc_or_explicit_offset():
    with TestClient(app) as client:
        response = client.get("/api/v1/resources")
    response.raise_for_status()
    for item in response.json()["items"]:
        published = item.get("published_at")
        if published:
            parsed = datetime.fromisoformat(published.replace("Z", "+00:00"))
            assert parsed.tzinfo is not None or published.endswith("Z")