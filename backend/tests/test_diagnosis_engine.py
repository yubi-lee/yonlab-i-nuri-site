import json
from pathlib import Path

import pytest

from app.diagnosis import (
    DecisionStatus,
    decide_diagnosis,
    infer_persona,
    rank_recommendations,
    score_dimension,
)

GOLDEN_PATH = (
    Path(__file__).parents[2]
    / "docs"
    / "planning"
    / "ai-training-platform-v1"
    / "diagnosis-scoring-golden-vectors.json"
)


def golden() -> dict:
    return json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))


def test_dimension_scoring_reproduces_normative_golden_vectors():
    vectors = {vector["id"]: vector for vector in golden()["vectors"]}

    score = score_dimension(vectors["GV-SCORE-001"]["input"])
    assert score.status == "OK"
    assert score.dimension_score_microunit == 75_000_000
    assert score.overall_score_microunit == 75_000_000
    assert score.confidence_microunit == 800_000

    deduped = score_dimension(vectors["GV-SCORE-DEDUP-001"]["input"])
    assert deduped.selected_evidence_id == vectors["GV-SCORE-DEDUP-001"]["expected"]["selected_evidence_id"]
    assert deduped.dimension_score_microunit == 75_000_000


def test_invalid_evidence_is_fail_closed_without_numeric_score():
    result = score_dimension({"anchor_count": 4, "anchor": 4, "confidence_decimal": "0.800000"})

    assert result.status == "INVALID_EVIDENCE"
    assert result.dimension_score_microunit is None
    assert result.overall_score_microunit is None


@pytest.mark.parametrize(
    ("score", "confidence", "conflict", "required", "status", "level"),
    [
        (0, 600_000, 0, True, DecisionStatus.LEVEL_ASSIGNED, "L1"),
        (24_999_999, 600_000, 0, True, DecisionStatus.LEVEL_ASSIGNED, "L1"),
        (25_000_000, 600_000, 0, True, DecisionStatus.LEVEL_ASSIGNED, "L2"),
        (50_000_000, 600_000, 0, True, DecisionStatus.LEVEL_ASSIGNED, "L3"),
        (75_000_000, 600_000, 0, True, DecisionStatus.LEVEL_ASSIGNED, "L4"),
        (75_000_000, 599_999, 0, True, DecisionStatus.ADDITIONAL_CONFIRMATION_REQUIRED, None),
        (50_000_000, 900_000, 500_000, True, DecisionStatus.HUMAN_REVIEW_REQUIRED, None),
        (75_000_000, 900_000, 0, False, DecisionStatus.INSUFFICIENT_EVIDENCE, None),
        (-1, 599_999, 500_000, False, DecisionStatus.INVALID_EVIDENCE, None),
    ],
)
def test_diagnosis_decision_uses_normative_precedence(
    score: int,
    confidence: int,
    conflict: int,
    required: bool,
    status: DecisionStatus,
    level: str | None,
):
    result = decide_diagnosis(
        overall_score_microunit=score,
        overall_confidence_microunit=confidence,
        conflict_microunit=conflict,
        required_indicators_satisfied=required,
    )

    assert result.status is status
    assert result.level == level


def test_persona_inference_is_fixed_order_and_exactly_normalized():
    profile_order = [
        "P-01-A",
        "P-01-B",
        "P-02-A",
        "P-02-B",
        "P-03-A",
        "P-03-B",
        "P-04-A",
        "P-04-B",
        "P-05-A",
        "P-05-B",
        "P-06-A",
        "P-06-B",
    ]

    result = infer_persona(["0.000000000000"] * 12, profile_order)

    assert result.profile_probability_microunit == [
        83_334,
        83_334,
        83_334,
        83_334,
        83_333,
        83_333,
        83_333,
        83_333,
        83_333,
        83_333,
        83_333,
        83_333,
    ]
    assert result.family_probability_microunit == [166_668, 166_668, 166_666, 166_666, 166_666, 166_666]
    assert sum(result.profile_probability_microunit) == 1_000_000
    assert result.classification == "MIXED_OR_UNDETERMINED"


def test_recommendation_ranking_uses_fixed_point_features_and_uuid_tie_break():
    result = rank_recommendations(
        [
            {
                "content_id": "00000000-0000-4000-8000-000000000002",
                "selection_score_microunit": 500_000,
                "base_microunit": 500_000,
                "duration_minutes": 30,
            },
            {
                "content_id": "00000000-0000-4000-8000-000000000001",
                "selection_score_microunit": 500_000,
                "base_microunit": 500_000,
                "duration_minutes": 30,
            },
        ]
    )

    assert [candidate["content_id"] for candidate in result] == [
        "00000000-0000-4000-8000-000000000001",
        "00000000-0000-4000-8000-000000000002",
    ]
