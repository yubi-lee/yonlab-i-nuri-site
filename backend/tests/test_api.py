import os

os.environ["DATABASE_URL"] = "sqlite:///./test.db"

from fastapi.testclient import TestClient

from app.database import Base, engine
from app.main import app


def setup_module():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)


def test_health():
    client = TestClient(app)
    assert client.get("/health/live").json() == {"status": "ok"}
    assert client.get("/health/ready").status_code == 200


def test_register_login_and_duplicate():
    client = TestClient(app)
    payload = {"email": "person@example.com", "name": "Test User", "password": "StrongPass!123"}
    response = client.post("/api/v1/auth/register", json=payload)
    assert response.status_code == 201
    assert response.json()["user"]["email"] == payload["email"]
    assert client.post("/api/v1/auth/register", json=payload).status_code == 409
    assert (
        client.post(
            "/api/v1/auth/login", json={"email": payload["email"], "password": "bad"}
        ).status_code
        == 401
    )


def test_inquiry_requires_privacy_consent():
    client = TestClient(app)
    payload = {
        "email": "person@example.com",
        "subject": "Test inquiry",
        "message": "This is a sufficiently long inquiry message.",
        "privacy_agreed": False,
    }
    assert client.post("/api/v1/inquiries", json=payload).status_code == 422
    payload["privacy_agreed"] = True
    assert client.post("/api/v1/inquiries", json=payload).status_code == 201
