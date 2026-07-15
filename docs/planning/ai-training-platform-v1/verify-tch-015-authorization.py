#!/usr/bin/env python3
"""Verify operation-specific authorization for the shared TCH-015 screen."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


OPERATION_AGGREGATE_SHA256 = "cc9be193778d07e64c64786526506b2efa0900f845aecbe7b0e2b673811e47ff"
OPERATIONS = {
    "GET /api/v1/drafts/{id}": "AUTHZ-TCH-015-DRAFT-READ-V1",
    "PATCH /api/v1/drafts/{id}": "AUTHZ-TCH-015-DRAFT-EDIT-V1",
    "POST /api/v1/drafts/{id}/review": "AUTHZ-TCH-015-DRAFT-REVIEW-V1",
    "POST /api/v1/drafts/{id}/export": "AUTHZ-TCH-015-DRAFT-EXPORT-V1",
}
CASE_IDS = [
    "AUTHZ-TCH015-ALLOW-TEACHER-READ",
    "AUTHZ-TCH015-ALLOW-TEACHER-EDIT",
    "AUTHZ-TCH015-ALLOW-TEACHER-SUBMIT",
    "AUTHZ-TCH015-ALLOW-TEACHER-EXPORT",
    "AUTHZ-TCH015-ALLOW-REVIEWER-READ",
    "AUTHZ-TCH015-ALLOW-REVIEWER-DECISION",
    "AUTHZ-TCH015-DENY-TEACHER-APPROVE",
    "AUTHZ-TCH015-DENY-REVIEWER-EDIT",
    "AUTHZ-TCH015-DENY-REVIEWER-EXPORT",
    "AUTHZ-TCH015-DENY-OTHER-TENANT",
    "AUTHZ-TCH015-DENY-TEACHER-NOT-OWNER-READ",
    "AUTHZ-TCH015-DENY-REVIEWER-UNASSIGNED-READ",
    "AUTHZ-TCH015-DENY-REVIEWER-UNASSIGNED-DECISION",
    "AUTHZ-TCH015-DENY-TEACHER-WRONG-STATE-EDIT",
    "AUTHZ-TCH015-DENY-TEACHER-WRONG-STATE-SUBMIT",
    "AUTHZ-TCH015-DENY-TEACHER-WRONG-STATE-EXPORT",
    "AUTHZ-TCH015-DENY-REVIEWER-WRONG-STATE-DECISION",
]
EXPECTED_OPERATION_CONTRACTS = [
    {
        "contract_id": "AUTHZ-TCH-015-DRAFT-READ-V1",
        "operation_id": "GET /api/v1/drafts/{id}",
        "allowed_roles": ["TEACHER", "CONTENT_REVIEWER"],
        "authorization_formula": "same_tenant AND ((role == TEACHER AND subject_id == draft.owner_id) OR (role == CONTENT_REVIEWER AND subject_id == draft.assigned_reviewer_id AND draft.state IN {REVIEW_REQUESTED, IN_REVIEW, CHANGES_REQUESTED, APPROVED}))",
        "allowed_actions": ["READ"],
    },
    {
        "contract_id": "AUTHZ-TCH-015-DRAFT-EDIT-V1",
        "operation_id": "PATCH /api/v1/drafts/{id}",
        "allowed_roles": ["TEACHER"],
        "authorization_formula": "same_tenant AND role == TEACHER AND subject_id == draft.owner_id AND draft.state IN {DRAFT, CHANGES_REQUESTED}",
        "allowed_actions": ["EDIT"],
    },
    {
        "contract_id": "AUTHZ-TCH-015-DRAFT-REVIEW-V1",
        "operation_id": "POST /api/v1/drafts/{id}/review",
        "allowed_roles": ["TEACHER", "CONTENT_REVIEWER"],
        "authorization_formula": "same_tenant AND ((role == TEACHER AND subject_id == draft.owner_id AND action == SUBMIT_REVIEW AND draft.state IN {DRAFT, CHANGES_REQUESTED}) OR (role == CONTENT_REVIEWER AND subject_id == draft.assigned_reviewer_id AND action IN {APPROVE, REQUEST_CHANGES} AND draft.state IN {REVIEW_REQUESTED, IN_REVIEW}))",
        "allowed_actions": ["SUBMIT_REVIEW", "APPROVE", "REQUEST_CHANGES"],
    },
    {
        "contract_id": "AUTHZ-TCH-015-DRAFT-EXPORT-V1",
        "operation_id": "POST /api/v1/drafts/{id}/export",
        "allowed_roles": ["TEACHER"],
        "authorization_formula": "same_tenant AND role == TEACHER AND subject_id == draft.owner_id AND draft.state IN {DRAFT, CHANGES_REQUESTED, APPROVED}",
        "allowed_actions": ["EXPORT"],
    },
]


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def load(path: Path, failures: list[str]) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        failures.append(f"cannot load {path.name}: {exc}")
        return {}


def evaluate(case: dict[str, Any]) -> str:
    if case.get("tenant_relation") != "SAME_TENANT":
        return "DENY"
    operation = case.get("operation_id")
    role = case.get("role")
    relation = case.get("resource_relation")
    state = case.get("state")
    action = case.get("action")
    if operation == "GET /api/v1/drafts/{id}" and action == "READ":
        if role == "TEACHER" and relation == "OWNER":
            return "ALLOW"
        if role == "CONTENT_REVIEWER" and relation == "ASSIGNED_REVIEWER" and state in {"REVIEW_REQUESTED", "IN_REVIEW", "CHANGES_REQUESTED", "APPROVED"}:
            return "ALLOW"
    if operation == "PATCH /api/v1/drafts/{id}" and role == "TEACHER" and relation == "OWNER" and action == "EDIT" and state in {"DRAFT", "CHANGES_REQUESTED"}:
        return "ALLOW"
    if operation == "POST /api/v1/drafts/{id}/review":
        if role == "TEACHER" and relation == "OWNER" and action == "SUBMIT_REVIEW" and state in {"DRAFT", "CHANGES_REQUESTED"}:
            return "ALLOW"
        if role == "CONTENT_REVIEWER" and relation == "ASSIGNED_REVIEWER" and action in {"APPROVE", "REQUEST_CHANGES"} and state in {"REVIEW_REQUESTED", "IN_REVIEW"}:
            return "ALLOW"
    if operation == "POST /api/v1/drafts/{id}/export" and role == "TEACHER" and relation == "OWNER" and action == "EXPORT" and state in {"DRAFT", "CHANGES_REQUESTED", "APPROVED"}:
        return "ALLOW"
    return "DENY"


def verify(package_root: Path) -> int:
    failures: list[str] = []
    routes = load(package_root / "screen-route-contracts.json", failures)
    authz = load(package_root / "tch-015-authorization-contract.json", failures)
    semantics = load(package_root / "normative-test-semantics.json", failures)
    registry = load(package_root / "requirements-test-registry.json", failures)

    screens = routes.get("screens", []) if isinstance(routes, dict) else []
    if len(screens) != 36 or sum(len(row.get("operation_contracts", [])) for row in screens if isinstance(row, dict)) != 113:
        failures.append("screen/operation cardinality must remain 36/113")
    screen = next((row for row in screens if isinstance(row, dict) and row.get("screen_id") == "TCH-015"), {})
    if screen.get("route") != "/workspace/drafts/:draftId" or screen.get("allowed_roles") != ["TEACHER", "CONTENT_REVIEWER"] or screen.get("tenant_guard") != "ACTIVE_TENANT_MEMBERSHIP":
        failures.append("TCH-015 screen entry must allow tenant members but defer operation authorization")
    operation_rows = screen.get("operation_contracts", []) if isinstance(screen, dict) else []
    actual_operation_authz = {row.get("operation_id"): row.get("authorization_contract_id") for row in operation_rows if isinstance(row, dict)}
    if actual_operation_authz != OPERATIONS or len(set(actual_operation_authz.values())) != 4:
        failures.append("TCH-015 must bind four distinct operation authorization contracts")

    catalog = routes.get("operation_shared_catalogs", {}).get("authorization", []) if isinstance(routes, dict) else []
    tch_catalog = [row for row in catalog if isinstance(row, dict) and row.get("screen_id") == "TCH-015"]
    expected_catalog = [
        {"contract_id": "AUTHZ-TCH-015-DRAFT-READ-V1", "screen_id": "TCH-015", "allowed_roles": ["TEACHER", "CONTENT_REVIEWER"], "tenant_guard": "ACTIVE_TENANT_MEMBERSHIP", "unknown_role_or_guard": "DENY"},
        {"contract_id": "AUTHZ-TCH-015-DRAFT-EDIT-V1", "screen_id": "TCH-015", "allowed_roles": ["TEACHER"], "tenant_guard": "ACTIVE_TENANT_OWNERSHIP", "unknown_role_or_guard": "DENY"},
        {"contract_id": "AUTHZ-TCH-015-DRAFT-REVIEW-V1", "screen_id": "TCH-015", "allowed_roles": ["TEACHER", "CONTENT_REVIEWER"], "tenant_guard": "ACTIVE_TENANT_MEMBERSHIP", "unknown_role_or_guard": "DENY"},
        {"contract_id": "AUTHZ-TCH-015-DRAFT-EXPORT-V1", "screen_id": "TCH-015", "allowed_roles": ["TEACHER"], "tenant_guard": "ACTIVE_TENANT_OWNERSHIP", "unknown_role_or_guard": "DENY"},
    ]
    if tch_catalog != expected_catalog:
        failures.append("TCH-015 authorization catalog rows drifted")

    expected_header = {
        "schema_version": "tch-015-authorization.v1",
        "screen_id": "TCH-015",
        "route": "/workspace/drafts/:draftId",
        "screen_entry_guard": "ACTIVE_TENANT_MEMBERSHIP",
        "default_decision": "DENY",
    }
    if not isinstance(authz, dict) or set(authz) != {*expected_header, "operation_contracts", "cases"} or any(authz.get(key) != value for key, value in expected_header.items()):
        failures.append("TCH-015 authorization contract header drift")
    authz_operations = authz.get("operation_contracts", []) if isinstance(authz, dict) else []
    if authz_operations != EXPECTED_OPERATION_CONTRACTS:
        failures.append("TCH-015 detailed operation role/ABAC/state/action formulas drift")
    for row in authz_operations if isinstance(authz_operations, list) else []:
        if not isinstance(row, dict) or set(row) != {"contract_id", "operation_id", "allowed_roles", "authorization_formula", "allowed_actions"}:
            failures.append("TCH-015 detailed operation contract key drift")
            continue
        if OPERATIONS.get(row.get("operation_id")) != row.get("contract_id") or not isinstance(row.get("authorization_formula"), str) or "same_tenant" not in row.get("authorization_formula", ""):
            failures.append(f"{row.get('contract_id')} lacks exact operation or tenant ABAC binding")
        if not isinstance(row.get("allowed_roles"), list) or not isinstance(row.get("allowed_actions"), list):
            failures.append(f"{row.get('contract_id')} role/action vocabulary invalid")

    cases = authz.get("cases", []) if isinstance(authz, dict) else []
    if [row.get("case_id") for row in cases if isinstance(row, dict)] != CASE_IDS:
        failures.append("TCH-015 canonical authorization case inventory drift")
    expected_case_keys = {"case_id", "operation_id", "role", "tenant_relation", "resource_relation", "state", "action", "expected_decision", "denial_reason", "test_id", "evidence_id"}
    registry_by_id = {row.get("test_id"): row for row in registry.get("tests", []) if isinstance(row, dict)} if isinstance(registry, dict) else {}
    for case in cases if isinstance(cases, list) else []:
        if not isinstance(case, dict) or set(case) != expected_case_keys:
            failures.append(f"{case.get('case_id') if isinstance(case, dict) else '<invalid>'} case key contract drift")
            continue
        actual = evaluate(case)
        if case.get("expected_decision") != actual:
            failures.append(f"{case.get('case_id')} expected {case.get('expected_decision')} but ABAC evaluates {actual}")
        if (actual == "ALLOW") != (case.get("denial_reason") == "NONE"):
            failures.append(f"{case.get('case_id')} denial reason does not match decision")
        if case.get("test_id") != "T-DOC-012" or case.get("evidence_id") != "EVD-DOC-012":
            failures.append(f"{case.get('case_id')} is not linked to canonical draft authorization evidence")
        test = registry_by_id.get(case.get("test_id"), {})
        if test.get("evidence_id") != case.get("evidence_id"):
            failures.append(f"{case.get('case_id')} evidence/test edge does not resolve")

    required_denials = {
        "AUTHZ-TCH015-DENY-TEACHER-APPROVE": "ROLE_ACTION_DENIED",
        "AUTHZ-TCH015-DENY-REVIEWER-EDIT": "ROLE_ACTION_DENIED",
        "AUTHZ-TCH015-DENY-REVIEWER-EXPORT": "ROLE_ACTION_DENIED",
        "AUTHZ-TCH015-DENY-OTHER-TENANT": "TENANT_MISMATCH",
        "AUTHZ-TCH015-DENY-TEACHER-NOT-OWNER-READ": "RESOURCE_OWNERSHIP_REQUIRED",
        "AUTHZ-TCH015-DENY-REVIEWER-UNASSIGNED-READ": "REVIEW_ASSIGNMENT_REQUIRED",
        "AUTHZ-TCH015-DENY-REVIEWER-UNASSIGNED-DECISION": "REVIEW_ASSIGNMENT_REQUIRED",
        "AUTHZ-TCH015-DENY-TEACHER-WRONG-STATE-EDIT": "RESOURCE_STATE_DENIED",
        "AUTHZ-TCH015-DENY-TEACHER-WRONG-STATE-SUBMIT": "RESOURCE_STATE_DENIED",
        "AUTHZ-TCH015-DENY-TEACHER-WRONG-STATE-EXPORT": "RESOURCE_STATE_DENIED",
        "AUTHZ-TCH015-DENY-REVIEWER-WRONG-STATE-DECISION": "RESOURCE_STATE_DENIED",
    }
    actual_denials = {row.get("case_id"): row.get("denial_reason") for row in cases if isinstance(row, dict) and row.get("expected_decision") == "DENY"}
    if actual_denials != required_denials:
        failures.append("role, tenant, ownership/assignment, and state denial inventory must be exact")

    semantic_row = next((row for row in semantics.get("tests", []) if isinstance(row, dict) and row.get("test_id") == "T-DOC-012"), {}) if isinstance(semantics, dict) else {}
    if semantic_row.get("authorization_case_ids") != CASE_IDS or "draft_authorization_case_failure_count == 0" not in semantic_row.get("acceptance_formula", ""):
        failures.append("T-DOC-012 normative semantic row does not bind every authorization case")

    semantic_rows: list[dict[str, Any]] = []
    for row in screens if isinstance(screens, list) else []:
        if not isinstance(row, dict):
            continue
        for operation in row.get("operation_contracts", []):
            if not isinstance(operation, dict):
                continue
            projection = {key: value for key, value in operation.items() if key != "semantic_case_sha256"}
            digest = hashlib.sha256(canonical(projection).encode("utf-8")).hexdigest()
            if operation.get("semantic_case_sha256") != digest:
                failures.append(f"{operation.get('operation_id')} operation semantic digest mismatch")
            semantic_rows.append({"screen_id": row.get("screen_id"), **projection})
    aggregate = hashlib.sha256(canonical(semantic_rows).encode("utf-8")).hexdigest()
    if aggregate != routes.get("operation_semantic_contract", {}).get("aggregate_sha256") or aggregate != OPERATION_AGGREGATE_SHA256:
        failures.append("113-operation semantic aggregate drift")

    if failures:
        for failure in failures:
            print(f"FAIL [TCH015_AUTHZ]: {failure}")
        print("RESULT: FAIL")
        return 1
    print("PASS [TCH015_AUTHZ]: teacher ownership and assigned-reviewer duties are operation/state/tenant separated")
    print("RESULT: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-root", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    return verify(args.package_root.resolve())


if __name__ == "__main__":
    sys.exit(main())
