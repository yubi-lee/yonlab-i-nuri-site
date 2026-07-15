#!/usr/bin/env python3
"""Verify the single canonical AI-gateway safeguarding vocabulary."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


CANONICAL_DECISIONS = [
    "STANDARD",
    "CHILD_SAFEGUARDING",
    "IMMINENT_DANGER",
    "SECURITY_EXFILTRATION",
    "POLICY_BLOCK",
]


def load(path: Path, failures: list[str]) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        failures.append(f"cannot load {path.name}: {exc}")
        return {}


def verify(package_root: Path) -> int:
    failures: list[str] = []
    schema = load(package_root / "ai-gateway-request.schema.json", failures)
    valid = load(package_root / "fixtures" / "ai-gateway-request.valid.json", failures)
    vectors = load(package_root / "fixtures" / "ai-gateway-safeguarding-decision-vectors.json", failures)
    try:
        actual_enum = schema["$defs"]["dataUsePayload"]["properties"]["safeguarding_decision"]["enum"]
    except (KeyError, TypeError):
        actual_enum = None
    if actual_enum != CANONICAL_DECISIONS:
        failures.append("schema safeguarding_decision enum is not the exact ordered canonical vocabulary")

    if not isinstance(vectors, dict) or set(vectors) != {"schema_version", "canonical_decisions", "positive_cases", "negative_cases"}:
        failures.append("safeguarding vector key contract drift")
        vectors = {}
    if vectors.get("schema_version") != "ai-gateway-safeguarding-decision-v1":
        failures.append("safeguarding vector schema_version drift")
    if vectors.get("canonical_decisions") != CANONICAL_DECISIONS:
        failures.append("safeguarding vector vocabulary drift")

    positives = vectors.get("positive_cases", [])
    negatives = vectors.get("negative_cases", [])
    if not isinstance(positives, list) or [row.get("decision") for row in positives if isinstance(row, dict)] != CANONICAL_DECISIONS:
        failures.append("each canonical safeguarding decision needs one ordered positive case")
    if not isinstance(negatives, list) or len(negatives) != 1:
        failures.append("exactly one unknown-state negative vector is required")
    else:
        negative = negatives[0]
        if not isinstance(negative, dict) or negative.get("decision") != "UNKNOWN" or negative.get("expected_schema_valid") is not False or negative.get("expected_fail_closed_decision") != "POLICY_BLOCK":
            failures.append("unknown safeguarding state must be schema-invalid and fail closed to POLICY_BLOCK")

    expected_actions = {
        "STANDARD": "MODEL_ROUTE_POLICY_EVALUATION",
        "CHILD_SAFEGUARDING": "SAFEGUARDING_QUEUE_NO_EXTERNAL_AI",
        "IMMINENT_DANGER": "SAFEGUARDING_QUEUE_NO_EXTERNAL_AI",
        "SECURITY_EXFILTRATION": "SECURITY_EVENT_BLOCK_TOOL_AND_EGRESS",
        "POLICY_BLOCK": "BLOCK_MODEL_AND_TOOL_ROUTE",
    }
    seen_case_ids: set[str] = set()
    for row in positives if isinstance(positives, list) else []:
        if not isinstance(row, dict):
            failures.append("positive safeguarding vector must be an object")
            continue
        if set(row) != {"case_id", "decision", "expected_schema_valid", "expected_route_action"}:
            failures.append(f"{row.get('case_id')} positive vector key contract drift")
        case_id = row.get("case_id")
        decision = row.get("decision")
        if not isinstance(case_id, str) or not re.fullmatch(r"SAFEGUARD-[A-Z-]+", case_id) or case_id in seen_case_ids:
            failures.append(f"invalid or duplicate safeguarding case ID: {case_id}")
        if isinstance(case_id, str):
            seen_case_ids.add(case_id)
        if decision not in (actual_enum or []) or row.get("expected_schema_valid") is not True:
            failures.append(f"{case_id} does not positively cover a schema-accepted decision")
        if row.get("expected_route_action") != expected_actions.get(decision):
            failures.append(f"{case_id} route action is not canonical")

    try:
        valid_decision = valid["body"]["data_use_context"]["payload"]["safeguarding_decision"]
    except (KeyError, TypeError):
        valid_decision = None
    if valid_decision != "STANDARD" or valid_decision not in (actual_enum or []):
        failures.append("canonical valid gateway fixture must use accepted STANDARD decision")

    for document_name in ("06-ai-gateway-model-selection.md", "15-normative-policy-and-interface-contracts.md"):
        try:
            text = (package_root / document_name).read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            failures.append(f"cannot read {document_name}: {exc}")
            continue
        for decision in CANONICAL_DECISIONS:
            if f"`{decision}`" not in text:
                failures.append(f"{document_name} omits canonical safeguarding decision {decision}")

    if failures:
        for failure in failures:
            print(f"FAIL [AI_GATEWAY_SAFEGUARDING]: {failure}")
        print("RESULT: FAIL")
        return 1
    print("PASS [AI_GATEWAY_SAFEGUARDING]: five canonical decisions accepted and UNKNOWN rejected fail-closed")
    print("RESULT: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-root", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    return verify(args.package_root.resolve())


if __name__ == "__main__":
    sys.exit(main())
