import os

os.environ["DATABASE_URL"] = "sqlite:///./test-inquiry-binding.db"
os.environ["JWT_SECRET"] = "test-secret-at-least-thirty-two-characters"

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.database import Base, SessionLocal, engine
from app.main import app
from app.models import Category, Inquiry


def reset_db() -> None:
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        db.add(Category(name="AI Education", slug="ai-education"))
        db.commit()


def test_authenticated_inquiry_is_bound_to_current_member():
    reset_db()
    client = TestClient(app)
    registered = client.post(
        "/api/v1/auth/register",
        json={"email": "learner@example.com", "name": "Learner", "password": "StrongPass!123"},
    )
    assert registered.status_code == 201
    user = registered.json()

    created = client.post(
        "/api/v1/inquiries",
        headers={"Authorization": f"Bearer {user['access_token']}"},
        json={
            "email": "learner@example.com",
            "subject": "Bound inquiry",
            "message": "This inquiry must be linked to the authenticated member.",
            "privacy_agreed": True,
        },
    )

    assert created.status_code == 201
    with SessionLocal() as db:
        inquiry = db.scalar(select(Inquiry).where(Inquiry.id == created.json()["id"]))
        assert inquiry is not None
        assert inquiry.user_id == user["user"]["id"]
