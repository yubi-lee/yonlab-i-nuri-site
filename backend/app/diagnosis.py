"""Deterministic diagnosis, persona, and recommendation policy primitives.

The functions in this module deliberately operate on plain mappings and fixed-point
integers.  AI providers may suggest evidence, but they do not calculate scores,
levels, probabilities, or ranking decisions.
"""

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from decimal import ROUND_FLOOR, Decimal, localcontext
from enum import Enum
from typing import Any

SCALE = 1_000_000
SCORE_SCALE = 100_000_000
POLICY_VERSION = "diagnosis-scoring.v1"
DECISION_POLICY_VERSION = "diagnosis-decision.v1"
PERSONA_POLICY_VERSION = "persona-inference.v1"
RECOMMENDATION_POLICY_VERSION = "recommendation-ranking.v1"

_FIXED_SIX = re.compile(r"^(?:0|1)(?:\.\d{6})$")


class DecisionStatus(str, Enum):
    INVALID_EVIDENCE = "INVALID_EVIDENCE"
    INSUFFICIENT_EVIDENCE = "INSUFFICIENT_EVIDENCE"
    HUMAN_REVIEW_REQUIRED = "HUMAN_REVIEW_REQUIRED"
    ADDITIONAL_CONFIRMATION_REQUIRED = "ADDITIONAL_CONFIRMATION_REQUIRED"
    LEVEL_ASSIGNED = "LEVEL_ASSIGNED"


@dataclass(frozen=True)
class DimensionScore:
    status: str
    dimension_score_microunit: int | None
    overall_score_microunit: int | None
    confidence_microunit: int | None
    conflict_microunit: int
    selected_evidence_id: str | None = None


@dataclass(frozen=True)
class DiagnosisDecision:
    status: DecisionStatus
    level: str | None


@dataclass(frozen=True)
class PersonaInference:
    profile_probability_microunit: list[int]
    family_probability_microunit: list[int]
    classification: str
    top_profile_ids: list[str]
    policy_version: str = PERSONA_POLICY_VERSION


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def div_half_up(numerator: int, denominator: int) -> int:
    if not _is_int(numerator) or not _is_int(denominator) or numerator < 0 or denominator <= 0:
        raise ValueError("div_half_up requires non-negative integer numerator and positive denominator")
    return (2 * numerator + denominator) // (2 * denominator)


def _fixed_six(value: Any) -> int:
    if not isinstance(value, str) or not _FIXED_SIX.fullmatch(value):
        raise ValueError("value must be a fixed-six decimal string in [0,1]")
    parsed = int(value[0]) * SCALE + int(value[2:])
    if not 0 <= parsed <= SCALE:
        raise ValueError("value is outside [0,1]")
    return parsed


def _valid_evidence(item: Mapping[str, Any], anchor_count: int) -> tuple[int, int] | None:
    required = {
        "evidence_id",
        "turn_id",
        "turn_sequence",
        "indicator_id",
        "anchor",
        "anchor_count",
        "confidence_decimal",
        "span_start_codepoint",
        "span_end_codepoint",
        "quoted_span",
        "schema_version",
    }
    if not required.issubset(item):
        return None
    if not all(isinstance(item[key], str) for key in ("evidence_id", "turn_id", "indicator_id", "quoted_span")):
        return None
    if item["schema_version"] != "evidence.v1":
        return None
    if not all(
        _is_int(item[key])
        for key in ("turn_sequence", "anchor", "anchor_count", "span_start_codepoint", "span_end_codepoint")
    ):
        return None
    if item["anchor_count"] != anchor_count or not 2 <= anchor_count:
        return None
    if not 0 <= item["anchor"] < anchor_count:
        return None
    if item["span_start_codepoint"] < 0 or item["span_end_codepoint"] < item["span_start_codepoint"]:
        return None
    try:
        confidence = _fixed_six(item["confidence_decimal"])
    except ValueError:
        return None
    score = div_half_up(SCORE_SCALE * item["anchor"], anchor_count - 1)
    return score, confidence


def score_dimension(payload: Mapping[str, Any]) -> DimensionScore:
    """Score a dimension using immutable evidence and fixed-point arithmetic."""

    try:
        anchor_count = payload["anchor_count"]
        if not _is_int(anchor_count) or anchor_count < 2:
            raise ValueError
        dimension_weight = _fixed_six(payload.get("dimension_weight_decimal", "1.000000"))
        indicator_weight = _fixed_six(payload.get("indicator_weight_decimal", "1.000000"))
        evidence = payload.get("evidence", [])
        if not isinstance(evidence, list):
            raise ValueError
        if not evidence and any(key in payload for key in ('anchor', 'confidence_decimal')):
            raise ValueError
    except (KeyError, TypeError, ValueError):
        return DimensionScore("INVALID_EVIDENCE", None, None, None, 0)

    validated: list[tuple[Mapping[str, Any], int, int]] = []
    for item in evidence:
        if not isinstance(item, Mapping):
            return DimensionScore("INVALID_EVIDENCE", None, None, None, 0)
        result = _valid_evidence(item, anchor_count)
        if result is None:
            return DimensionScore("INVALID_EVIDENCE", None, None, None, 0)
        validated.append((item, *result))

    if not validated:
        return DimensionScore("INSUFFICIENT_EVIDENCE", 0, 0, 0, 0)

    # One candidate per indicator/turn is retained.  Higher confidence wins;
    # evidence ID is the stable bytewise tie-break.
    selected: dict[tuple[str, int], tuple[Mapping[str, Any], int, int]] = {}
    for item, score, confidence in validated:
        key = (item["indicator_id"], item["turn_sequence"])
        current = selected.get(key)
        if current is None or (confidence, item["evidence_id"]) > (
            current[2], current[0]["evidence_id"]
        ):
            selected[key] = (item, score, confidence)

    selected_values = list(selected.values())
    indicator_weighted_score = sum(indicator_weight * score for _, score, _ in selected_values)
    indicator_weighted_confidence = sum(
        indicator_weight * confidence for _, _, confidence in selected_values
    )
    dimension_score = div_half_up(indicator_weighted_score, indicator_weight * len(selected_values))
    confidence = div_half_up(
        indicator_weighted_confidence, indicator_weight * len(selected_values)
    )
    overall_score = div_half_up(dimension_weight * dimension_score, dimension_weight)

    conflict = 0
    by_indicator: dict[str, list[tuple[Mapping[str, Any], int]]] = {}
    for item, _score, item_confidence in selected_values:
        if item_confidence >= 600_000:
            by_indicator.setdefault(item["indicator_id"], []).append((item, item_confidence))
    for pairs in by_indicator.values():
        for index, (first, _) in enumerate(pairs):
            for second, _ in pairs[index + 1 :]:
                conflict = max(
                    conflict,
                    div_half_up(
                        SCALE * abs(first["anchor"] - second["anchor"]), anchor_count - 1
                    ),
                )

    selected_id = max(selected_values, key=lambda value: (value[2], value[0]["evidence_id"]))[0][
        "evidence_id"
    ]
    return DimensionScore("OK", dimension_score, overall_score, confidence, conflict, selected_id)


def decide_diagnosis(
    *,
    overall_score_microunit: Any,
    overall_confidence_microunit: Any,
    conflict_microunit: Any,
    required_indicators_satisfied: Any,
) -> DiagnosisDecision:
    """Apply the diagnosis decision precedence from ``diagnosis-decision.v1``."""

    if (
        not _is_int(overall_score_microunit)
        or not _is_int(overall_confidence_microunit)
        or not _is_int(conflict_microunit)
        or not isinstance(required_indicators_satisfied, bool)
        or not 0 <= overall_score_microunit <= SCORE_SCALE
        or not 0 <= overall_confidence_microunit <= SCALE
        or not 0 <= conflict_microunit <= SCALE
    ):
        return DiagnosisDecision(DecisionStatus.INVALID_EVIDENCE, None)
    if not required_indicators_satisfied:
        return DiagnosisDecision(DecisionStatus.INSUFFICIENT_EVIDENCE, None)
    if conflict_microunit >= 500_000:
        return DiagnosisDecision(DecisionStatus.HUMAN_REVIEW_REQUIRED, None)
    if overall_confidence_microunit < 600_000:
        return DiagnosisDecision(DecisionStatus.ADDITIONAL_CONFIRMATION_REQUIRED, None)
    if overall_score_microunit <= 24_999_999:
        level = "L1"
    elif overall_score_microunit <= 49_999_999:
        level = "L2"
    elif overall_score_microunit <= 74_999_999:
        level = "L3"
    else:
        level = "L4"
    return DiagnosisDecision(DecisionStatus.LEVEL_ASSIGNED, level)


def _largest_remainder(raw_values: Sequence[Decimal]) -> list[int]:
    floors = [int(value.to_integral_value(rounding=ROUND_FLOOR)) for value in raw_values]
    remaining = SCALE - sum(floors)
    order = sorted(
        range(len(raw_values)),
        key=lambda index: (raw_values[index] - floors[index], -index),
        reverse=True,
    )
    for index in order[:remaining]:
        floors[index] += 1
    return floors


def infer_persona(logits: Sequence[str], profile_order: Sequence[str]) -> PersonaInference:
    """Convert 12 fixed-order logits into exact profile/family probabilities."""

    if len(logits) != 12 or len(profile_order) != 12 or len(set(profile_order)) != 12:
        raise ValueError("persona inference requires twelve unique profiles and logits")
    with localcontext() as context:
        context.prec = 80
        values = [Decimal(value) for value in logits]
        maximum = max(values)
        exponentials = [(value - maximum).exp() for value in values]
        total = sum(exponentials)
        raw = [value / total * SCALE for value in exponentials]
    probabilities = _largest_remainder(raw)
    families: list[int] = []
    family_ids: list[str] = []
    for index in range(0, 12, 2):
        family_id = profile_order[index].split("-")[0] + "-" + profile_order[index].split("-")[1]
        if not profile_order[index + 1].startswith(family_id + "-"):
            raise ValueError("profiles must be ordered in family pairs")
        family_ids.append(family_id)
        families.append(probabilities[index] + probabilities[index + 1])
    top_profile_ids = [
        profile_order[index]
        for index in sorted(range(12), key=lambda i: (-probabilities[i], i))[:3]
    ]
    winner = max(range(6), key=lambda index: (families[index], -index))
    classification = "MIXED_OR_UNDETERMINED" if families[winner] < 450_000 else family_ids[winner]
    return PersonaInference(probabilities, families, classification, top_profile_ids)


def recommendation_score(feature_microunit: Sequence[int], maximum_jaccard_microunit: int | None = None) -> dict[str, int]:
    if len(feature_microunit) != 6 or any(
        not _is_int(value) or not 0 <= value <= SCALE for value in feature_microunit
    ):
        raise ValueError("recommendation features must contain six fixed-point values")
    base = div_half_up(
        400_000 * feature_microunit[0]
        + 200_000 * feature_microunit[1]
        + 150_000 * feature_microunit[2]
        + 100_000 * feature_microunit[3]
        + 100_000 * feature_microunit[4]
        + 50_000 * feature_microunit[5],
        SCALE,
    )
    if maximum_jaccard_microunit is None:
        novelty = SCALE
    else:
        if not _is_int(maximum_jaccard_microunit) or not 0 <= maximum_jaccard_microunit <= SCALE:
            raise ValueError("maximum Jaccard must be a fixed-point value")
        novelty = SCALE - maximum_jaccard_microunit
    selection_score = div_half_up(850_000 * base + 150_000 * novelty, SCALE)
    return {
        "base_microunit": base,
        "novelty_microunit": novelty,
        "selection_score_microunit": selection_score,
    }


def rank_recommendations(candidates: Sequence[Mapping[str, Any]]) -> list[Mapping[str, Any]]:
    """Apply the final deterministic recommendation tie-break order."""

    return sorted(
        candidates,
        key=lambda candidate: (
            -candidate["selection_score_microunit"],
            -candidate["base_microunit"],
            candidate["duration_minutes"],
            str(candidate["content_id"]).encode("utf-8"),
        ),
    )
