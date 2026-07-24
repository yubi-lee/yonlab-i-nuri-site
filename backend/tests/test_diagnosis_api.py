from copy import deepcopy

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

VALID_REQUEST = {
    "anchor_count": 5,
    "evidence": [
        {
            "evidence_id": "00000000-0000-4000-8000-000000000001",
            "turn_id": "00000000-0000-4000-8000-000000000011",
            "turn_sequence": 1,
            "indicator_id": "indicator-1",
            "anchor": 3,
            "anchor_count": 5,
            "confidence_decimal": "0.800000",
            "span_start_codepoint": 0,
            "span_end_codepoint": 2,
            "quoted_span": "원문 증거는 응답에 포함되지 않아야 합니다.",
            "schema_version": "evidence.v1",
        }
    ],
}


def test_score_endpoint_returns_deterministic_result_without_echoing_raw_evidence():
    request_id = "api-diagnosis-0001"

    response = client.post(
        "/api/v1/diagnosis/score", headers={"X-Request-ID": request_id}, json=VALID_REQUEST
    )

    assert response.status_code == 200
    assert response.headers["X-Request-ID"] == request_id
    body = response.json()
    assert body == {
        "policy_version": "diagnosis-scoring.v1",
        "status": "OK",
        "dimension_score_microunit": 75_000_000,
        "overall_score_microunit": 75_000_000,
        "confidence_microunit": 800_000,
        "conflict_microunit": 0,
        "selected_evidence_id": "00000000-0000-4000-8000-000000000001",
        "request_id": request_id,
        "persisted": False,
    }
    assert "quoted_span" not in response.text
    assert "원문 증거는 응답에 포함되지 않아야 합니다." not in response.text


def test_score_endpoint_rejects_unknown_fields_with_safe_request_id_error():
    payload = deepcopy(VALID_REQUEST)
    payload["unexpected"] = "do-not-echo"
    request_id = "api-diagnosis-0002"

    response = client.post(
        "/api/v1/diagnosis/score", headers={"X-Request-ID": request_id}, json=payload
    )

    assert response.status_code == 422
    assert response.headers["X-Request-ID"] == request_id
    assert response.json() == {
        "error": {
            "code": "validation_error",
            "message": "요청 형식이 올바르지 않습니다.",
            "request_id": request_id,
        }
    }
    assert "do-not-echo" not in response.text
    assert "원문 증거는 응답에 포함되지 않아야 합니다." not in response.text


def test_score_endpoint_rejects_evidence_anchor_count_mismatch():
    payload = deepcopy(VALID_REQUEST)
    payload["evidence"][0]["anchor_count"] = 4

    response = client.post("/api/v1/diagnosis/score", json=payload)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
