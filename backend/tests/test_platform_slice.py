import os
from uuid import uuid4

os.environ["DATABASE_URL"] = "sqlite:///./test-platform-slice.db"

from fastapi.testclient import TestClient

from app.database import Base, engine
from app.main import app


def setup_module():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)


def register_user(client: TestClient) -> tuple[dict, dict]:
    email = f"platform-{uuid4()}@example.com"
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "name": "Platform Teacher", "password": "StrongPass!123"},
    )
    assert response.status_code == 201
    body = response.json()
    return {"Authorization": f"Bearer {body['access_token']}"}, body


def test_platform_vertical_slice_persists_tenant_diagnosis_learning_and_knowledge():
    client = TestClient(app)
    headers, _ = register_user(client)

    organization = client.post(
        "/api/v1/organizations", headers=headers, json={"name": "YOnLab Pilot Center"}
    )
    assert organization.status_code == 201
    organization_id = organization.json()["id"]

    profile = client.put(
        "/api/v1/me/teacher-profile",
        headers=headers,
        json={"organization_id": organization_id, "years_experience": 5, "specialty": "유아 AI 놀이"},
    )
    assert profile.status_code == 200
    assert profile.json()["specialty"] == "유아 AI 놀이"

    session = client.post(
        "/api/v1/diagnosis/sessions",
        headers=headers,
        json={"organization_id": organization_id, "goal": "수업 설계 역량 진단"},
    )
    assert session.status_code == 201
    session_id = session.json()["id"]

    turn = client.post(
        f"/api/v1/diagnosis/sessions/{session_id}/turns",
        headers=headers,
        json={
            "content": "아이들의 질문을 바탕으로 AI 놀이 활동을 설계하고 싶습니다.",
            "evidence": [
                {
                    "indicator_id": "lesson-design",
                    "anchor": 3,
                    "anchor_count": 5,
                    "confidence_decimal": "0.800000",
                    "quoted_span": "AI 놀이 활동을 설계하고 싶습니다.",
                }
            ],
        },
    )
    assert turn.status_code == 201
    assert turn.json()["sequence"] == 1

    completed = client.post(f"/api/v1/diagnosis/sessions/{session_id}/complete", headers=headers)
    assert completed.status_code == 200
    result = completed.json()
    assert result["status"] == "completed"
    assert result["result"]["status"] == "OK"
    assert "quoted_span" not in completed.text

    paths = client.get("/api/v1/learning/paths", headers=headers)
    assert paths.status_code == 200
    path_id = paths.json()["items"][0]["id"]
    enrollment = client.post(
        "/api/v1/learning/enrollments",
        headers=headers,
        json={"organization_id": organization_id, "path_id": path_id},
    )
    assert enrollment.status_code == 201
    activity = client.post(
        f"/api/v1/learning/enrollments/{enrollment.json()['id']}/activities",
        headers=headers,
        json={"content_id": "content-intro-ai", "activity_type": "lesson", "status": "completed"},
    )
    assert activity.status_code == 201

    document = client.post(
        "/api/v1/documents",
        headers=headers,
        json={
            "organization_id": organization_id,
            "title": "AI 놀이 수업 운영안",
            "mime_type": "text/plain",
            "content": "AI 놀이 수업은 아이의 질문을 존중하고 교사는 안전한 탐색을 돕는다.",
        },
    )
    assert document.status_code == 201
    document_id = document.json()["id"]
    processed = client.post(f"/api/v1/documents/{document_id}/process", headers=headers)
    assert processed.status_code == 200
    assert processed.json()["status"] == "completed"

    search = client.get(
        "/api/v1/knowledge/search",
        headers=headers,
        params={"organization_id": organization_id, "q": "아이의 질문"},
    )
    assert search.status_code == 200
    assert search.json()["items"][0]["citations"][0]["document_id"] == document_id

    report = client.post(
        "/api/v1/reports",
        headers=headers,
        json={"organization_id": organization_id, "report_type": "diagnosis", "session_id": session_id},
    )
    assert report.status_code == 201
    assert report.json()["status"] == "ready"
