import os

os.environ["DATABASE_URL"] = "sqlite:///./test-rc1.db"
os.environ["JWT_SECRET"] = "test-secret-at-least-thirty-two-characters"

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.database import Base, SessionLocal, engine
from app.main import app
from app.models import Category, Role, User
from app.security import hash_password


def reset_db() -> None:
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        db.add(Category(name="AI Education", slug="ai-education"))
        db.add(
            User(
                email="admin@example.com",
                name="Admin",
                password_hash=hash_password("AdminPass!123"),
                role=Role.admin,
            )
        )
        db.commit()


def login(client: TestClient, email: str, password: str) -> dict:
    response = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200
    return response.json()


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_refresh_rotation_rejects_reuse_and_logout_revokes_session():
    reset_db()
    client = TestClient(app)
    registered = client.post(
        "/api/v1/auth/register",
        json={"email": "user@example.com", "name": "User", "password": "StrongPass!123"},
    )
    assert registered.status_code == 201
    first_refresh = registered.json()["refresh_token"]

    rotated = client.post("/api/v1/auth/refresh", json={"refresh_token": first_refresh})
    assert rotated.status_code == 200
    second_refresh = rotated.json()["refresh_token"]
    assert second_refresh != first_refresh

    reused = client.post("/api/v1/auth/refresh", json={"refresh_token": first_refresh})
    assert reused.status_code == 401

    logged_out = client.post("/api/v1/auth/logout", json={"refresh_token": second_refresh})
    assert logged_out.status_code == 204
    assert (
        client.post("/api/v1/auth/refresh", json={"refresh_token": second_refresh}).status_code
        == 401
    )


def test_logout_all_revokes_every_refresh_session():
    reset_db()
    client = TestClient(app)
    first = login(client, "admin@example.com", "AdminPass!123")
    second = login(client, "admin@example.com", "AdminPass!123")
    result = client.post("/api/v1/auth/logout-all", headers=auth(first["access_token"]))
    assert result.status_code == 204
    assert (
        client.post(
            "/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]}
        ).status_code
        == 401
    )
    assert (
        client.post(
            "/api/v1/auth/refresh", json={"refresh_token": second["refresh_token"]}
        ).status_code
        == 401
    )


def test_regular_user_cannot_access_admin_and_last_admin_cannot_demote_self():
    reset_db()
    client = TestClient(app)
    user = client.post(
        "/api/v1/auth/register",
        json={"email": "user@example.com", "name": "User", "password": "StrongPass!123"},
    ).json()
    assert client.get("/api/v1/admin/users", headers=auth(user["access_token"])).status_code == 403

    admin = login(client, "admin@example.com", "AdminPass!123")
    me = client.get("/api/v1/me", headers=auth(admin["access_token"])).json()
    response = client.patch(
        f"/api/v1/admin/users/{me['id']}",
        headers=auth(admin["access_token"]),
        json={"role": "user"},
    )
    assert response.status_code == 409


def test_admin_category_crud_and_audit_log():
    reset_db()
    client = TestClient(app)
    admin = login(client, "admin@example.com", "AdminPass!123")
    headers = auth(admin["access_token"])

    created = client.post(
        "/api/v1/admin/categories", headers=headers, json={"name": "Safety", "slug": "safety"}
    )
    assert created.status_code == 201
    category_id = created.json()["id"]
    listed = client.get("/api/v1/admin/categories?q=Safe&page=1&page_size=10", headers=headers)
    assert listed.status_code == 200
    assert listed.json()["total"] == 1
    updated = client.patch(
        f"/api/v1/admin/categories/{category_id}",
        headers=headers,
        json={"name": "AI Safety", "slug": "ai-safety"},
    )
    assert updated.status_code == 200
    deleted = client.delete(f"/api/v1/admin/categories/{category_id}", headers=headers)
    assert deleted.status_code == 204
    audit = client.get("/api/v1/admin/audit-logs", headers=headers)
    assert audit.status_code == 200
    assert {row["action"] for row in audit.json()["items"]} >= {
        "category.create",
        "category.update",
        "category.delete",
    }


def test_file_upload_accepts_pdf_and_rejects_security_cases(tmp_path):
    reset_db()
    client = TestClient(app)
    admin = login(client, "admin@example.com", "AdminPass!123")
    headers = auth(admin["access_token"])
    with SessionLocal() as db:
        category = db.scalar(select(Category))
        category_id = category.id
    resource = client.post(
        "/api/v1/admin/resources",
        headers=headers,
        json={
            "title": "Files",
            "summary": "Attachment test",
            "body": "Body",
            "audience": "teachers",
            "resource_type": "guide",
            "category_id": category_id,
            "status": "published",
            "tag_ids": [],
        },
    )
    assert resource.status_code == 201
    resource_id = resource.json()["id"]

    ok = client.post(
        f"/api/v1/admin/resources/{resource_id}/attachments",
        headers=headers,
        files={"file": ("guide.pdf", b"%PDF-1.7 test", "application/pdf")},
    )
    assert ok.status_code == 201
    assert ok.json()["original_name"] == "guide.pdf"

    forbidden = client.post(
        f"/api/v1/admin/resources/{resource_id}/attachments",
        headers=headers,
        files={"file": ("malware.exe", b"MZ", "application/octet-stream")},
    )
    assert forbidden.status_code == 415
    spoofed = client.post(
        f"/api/v1/admin/resources/{resource_id}/attachments",
        headers=headers,
        files={"file": ("fake.pdf", b"MZ executable", "application/pdf")},
    )
    assert spoofed.status_code == 415
    traversal = client.post(
        f"/api/v1/admin/resources/{resource_id}/attachments",
        headers=headers,
        files={"file": ("../escape.pdf", b"%PDF-1.7", "application/pdf")},
    )
    assert traversal.status_code == 400
