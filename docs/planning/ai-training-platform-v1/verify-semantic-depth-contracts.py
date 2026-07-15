#!/usr/bin/env python3
"""Fail-closed verifier for YOnLab semantic-depth design contracts."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, NoReturn


SCALE = 1_000_000
LEVELS = ["L1", "L2", "L3", "L4"]
ANCHORS = [0, 333_333, 666_667, 1_000_000]
COMPETENCIES = [f"COMP-{index:02d}" for index in range(1, 8)]
FEATURE_IDS = [
    "context.return_after_leave",
    "context.career_band",
    "context.region_resource_category",
    "experience.practice_context_breadth",
    "interest.keyword_id",
    "constraint.time_pressure",
    "constraint.low_bandwidth",
    "preference.mentor_support",
    "preference.examples_first",
    "preference.small_steps",
    "need.policy_change_refresh",
    "need.digital_reentry",
    "interest.advanced_cases",
    "interest.peer_coaching",
    "need.local_resource_alternative",
    "preference.human_support",
    "support.current_emotional_load",
    "support.encouragement_preference",
]
PROFILE_IDS = [f"P-{family:02d}-{suffix}" for family in range(1, 7) for suffix in ("A", "B")]
PROFILE_NONZERO = {
    "P-01-A": {"context.career_band": 700_000, "preference.examples_first": 900_000, "preference.small_steps": 700_000, "preference.mentor_support": 400_000, "interest.keyword_id": 400_000},
    "P-01-B": {"context.career_band": 500_000, "preference.mentor_support": 1_000_000, "preference.examples_first": 500_000, "interest.peer_coaching": 300_000, "interest.keyword_id": 400_000},
    "P-02-A": {"preference.examples_first": 1_000_000, "preference.small_steps": 400_000},
    "P-02-B": {"preference.small_steps": 1_000_000, "preference.examples_first": 400_000, "constraint.time_pressure": 200_000},
    "P-03-A": {"context.return_after_leave": 800_000, "need.policy_change_refresh": 1_000_000},
    "P-03-B": {"context.return_after_leave": 600_000, "need.digital_reentry": 1_000_000, "preference.small_steps": 300_000},
    "P-04-A": {"context.career_band": -400_000, "experience.practice_context_breadth": 700_000, "interest.advanced_cases": 1_000_000, "interest.peer_coaching": 300_000, "interest.keyword_id": 400_000},
    "P-04-B": {"context.career_band": -400_000, "experience.practice_context_breadth": 800_000, "interest.peer_coaching": 1_000_000, "interest.advanced_cases": 500_000, "preference.mentor_support": -200_000, "interest.keyword_id": 400_000},
    "P-05-A": {"constraint.time_pressure": 1_000_000, "preference.small_steps": 500_000, "preference.human_support": 200_000, "support.current_emotional_load": 600_000},
    "P-05-B": {"preference.human_support": 1_000_000, "constraint.time_pressure": 500_000, "support.current_emotional_load": 800_000, "support.encouragement_preference": 700_000},
    "P-06-A": {"context.region_resource_category": 600_000, "constraint.low_bandwidth": 1_000_000, "need.local_resource_alternative": 400_000},
    "P-06-B": {"context.region_resource_category": 900_000, "need.local_resource_alternative": 1_000_000, "constraint.low_bandwidth": 400_000, "interest.peer_coaching": 200_000, "interest.keyword_id": 400_000},
}
ROLE_VOCABULARY = sorted({
    "ROLE_DIAGNOSIS_REVIEWER", "ROLE_CHILD_SAFEGUARDING_REVIEWER", "ROLE_PRIVACY_REVIEWER",
    "ROLE_RUBRIC_EDITOR", "ROLE_EDUCATION_APPROVER", "ROLE_MODEL_RISK_APPROVER",
    "ROLE_EVALUATION_OPERATOR", "ROLE_DATA_OWNER", "ROLE_DOCUMENT_EDITOR", "ROLE_DOCUMENT_APPROVER",
    "ROLE_RIGHTS_APPROVER", "ROLE_AI_PLATFORM_OPERATOR", "ROLE_SECURITY_APPROVER", "ROLE_PRIVACY_OPERATOR",
    "ROLE_PRIVACY_APPROVER", "ROLE_DATABASE_OPERATOR", "ROLE_SERVICE_OWNER", "ROLE_IDENTITY_OPERATOR",
})
OPERATION_IDS = [
    "OP-DIAGNOSIS-OVERRIDE", "OP-RUBRIC-PUBLISH", "OP-EVAL-EXPORT", "OP-HWP-PUBLISH",
    "OP-PROVIDER-ACTIVATE", "OP-LINEAGE-DELETE", "OP-BACKUP-RESTORE", "OP-ADMIN-GRANT",
]
SUITE_MINIMUMS = {
    "EVAL-DIAG-RAW-E2E": 300,
    "EVAL-PERSONA-CALIBRATION": 600,
    "EVAL-RAG-CLAIM-CITATION": 200,
    "EVAL-HWP-LICENSED-ROUNDTRIP": 100,
    "EVAL-AUTHZ-HIGH-PRIVILEGE": 400,
    "EVAL-PROVIDER-ROUTING": 1000,
}
PROVIDER_DECISIONS = [
    "DEC-AI-OPENAI-001", "DEC-AI-SLLM-002", "DEC-OCR-003", "DEC-EMBED-004",
    "DEC-HARDWARE-005", "DEC-HWP-006", "DEC-OBJECT-STORAGE-007", "DEC-EMAIL-008",
    "DEC-OIDC-009", "DEC-BROKER-010", "DEC-MALWARE-011", "DEC-HOSTING-DNS-TLS-WAF-012",
    "DEC-MANAGED-DB-013", "DEC-REDIS-014", "DEC-OFFHOST-BACKUP-015", "DEC-CICD-016",
]


class DuplicateKey(ValueError):
    pass


def die(message: str) -> NoReturn:
    print(f"FAIL: {message}", file=sys.stderr)
    print("RESULT: FAIL", file=sys.stderr)
    raise SystemExit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        die(message)


def pairs_no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKey(key)
        result[key] = value
    return result


def load(root: Path, name: str) -> dict[str, Any]:
    path = root / name
    require(path.is_file(), f"missing {name}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs_no_duplicates)
    except (UnicodeError, json.JSONDecodeError, DuplicateKey) as exc:
        die(f"invalid strict JSON {name}: {exc}")
    require(isinstance(value, dict), f"{name} root must be object")
    return value


def exact_keys(value: Any, keys: set[str], label: str) -> None:
    require(isinstance(value, dict), f"{label} must be object")
    require(set(value) == keys, f"{label} keys drift: {sorted(set(value) ^ keys)}")


def integer(value: Any, label: str) -> int:
    require(isinstance(value, int) and not isinstance(value, bool), f"{label} must be integer")
    return value


def verify_rubric(root: Path) -> dict[str, Any]:
    d = load(root, "rubric-question-contract.json")
    exact_keys(d, {"schema_version", "release_state", "rubric_version", "question_bank_version", "scale", "competencies", "indicators", "questions", "feature_dictionary", "missingness_policy", "protected_attribute_policy", "evidence_pipeline", "release_gate"}, "rubric root")
    require(d["schema_version"] == "rubric-question-contract.v1", "rubric schema version drift")
    require(d["release_state"] == "NON_PRODUCTION_REQUIRES_PILOT_CALIBRATION", "rubric must remain non-production pending calibration")
    require(d["scale"] == {"levels": LEVELS, "anchor_microunits": ANCHORS, "interpretation": ["기초 인식", "부분 적용", "일관 적용", "상황 확장"]}, "four-level scale drift")
    competencies = d["competencies"]
    require(isinstance(competencies, list) and len(competencies) == 7, "exact seven competency dimensions required")
    require([row.get("competency_id") for row in competencies] == COMPETENCIES, "competency IDs/order drift")
    all_declared: list[str] = []
    for row in competencies:
        exact_keys(row, {"competency_id", "name", "indicator_ids"}, "competency")
        require(isinstance(row["name"], str) and row["name"], "competency name required")
        require(isinstance(row["indicator_ids"], list) and len(row["indicator_ids"]) == 3, "three indicators per competency required")
        all_declared.extend(row["indicator_ids"])
    indicators = d["indicators"]
    require(isinstance(indicators, list) and len(indicators) == 21, "exact 21 indicator contracts required")
    require([row.get("indicator_id") for row in indicators] == all_declared, "indicator catalog/order does not close competency references")
    for row in indicators:
        exact_keys(row, {"indicator_id", "competency_id", "competency_name", "statement", "priority", "minimum_distinct_turns", "anchors"}, f"indicator {row.get('indicator_id')}")
        require(row["competency_id"] in COMPETENCIES and row["minimum_distinct_turns"] == 2, "indicator identity/evidence minimum drift")
        require(isinstance(row["statement"], str) and len(row["statement"]) >= 10, "indicator must define observable statement")
        anchors = row["anchors"]
        require(isinstance(anchors, list) and len(anchors) == 4, "every indicator requires four anchors")
        require([a.get("level") for a in anchors] == LEVELS and [a.get("anchor_microunit") for a in anchors] == ANCHORS, "indicator anchor levels/values drift")
        for anchor in anchors:
            exact_keys(anchor, {"level", "anchor_microunit", "observable_behavior", "counterexample"}, "anchor")
            require(len(anchor["observable_behavior"]) >= 15 and len(anchor["counterexample"]) >= 10, "anchor behavior and counterexample must be substantive")
            require(row["statement"] in anchor["observable_behavior"] and row["statement"] in anchor["counterexample"], "anchor must be indicator-specific rather than a repeated generic template")
    questions = d["questions"]
    require(isinstance(questions, list) and len(questions) == 42, "exact two questions per indicator required")
    counts = {indicator_id: 0 for indicator_id in all_declared}
    seen_questions: set[str] = set()
    for row in questions:
        exact_keys(row, {"question_id", "indicator_ids", "question_form", "prompt_ko", "response_schema", "leading_language", "sensitive_attribute_request", "expected_information_gain_microunit"}, f"question {row.get('question_id')}")
        require(row["question_id"] not in seen_questions, "duplicate question_id")
        seen_questions.add(row["question_id"])
        require(row["question_form"] in {"SITUATIONAL", "REFLECTIVE"}, "question form drift")
        require(row["leading_language"] == "FORBIDDEN" and row["sensitive_attribute_request"] == "FORBIDDEN", "leading or sensitive question enabled")
        require(isinstance(row["indicator_ids"], list) and len(row["indicator_ids"]) == 1 and row["indicator_ids"][0] in counts, "question indicator reference invalid")
        counts[row["indicator_ids"][0]] += 1
        linked_indicator = next(item for item in indicators if item["indicator_id"] == row["indicator_ids"][0])
        require(linked_indicator["statement"] in row["prompt_ko"], "question prompt must name its indicator-specific observable behavior")
        gain = integer(row["expected_information_gain_microunit"], "question information gain")
        require(0 < gain <= SCALE and len(row["prompt_ko"]) >= 30, "question content/information gain insufficient")
    require(set(counts.values()) == {2}, "question bank does not cover every indicator exactly twice")
    features = d["feature_dictionary"]
    require([row.get("feature_id") for row in features] == FEATURE_IDS, "feature dictionary IDs/order drift")
    for row in features:
        exact_keys(row, {"feature_id", "value_type", "source", "missingness", "data_class", "retention", "consent", "encoding", "allowed_use", "diagnosis_score_effect", "user_control"}, f"feature {row.get('feature_id')}")
        require(row["allowed_use"] == "PERSONA_CONTEXT_AND_RECOMMENDATION_ONLY" and row["diagnosis_score_effect"] == "FORBIDDEN", "persona context feature leaked into diagnosis score")
        require(row["missingness"] == "NEUTRAL_ZERO", "feature missingness policy drift")
        require(row["user_control"] == "VIEW_CORRECT_WITHDRAW" and row["retention"], "feature correction/withdrawal/retention contract missing")
    feature_by_id = {row["feature_id"]: row for row in features}
    require(feature_by_id["context.region_resource_category"]["encoding"].endswith("exact location forbidden"), "region feature must be resource-category only")
    require("approved IDs" in feature_by_id["experience.practice_context_breadth"]["encoding"] and "approved IDs" in feature_by_id["interest.keyword_id"]["encoding"], "experience/interest taxonomies must be closed")
    for feature_id in ("support.current_emotional_load", "support.encouragement_preference"):
        row = feature_by_id[feature_id]
        require(row["data_class"] == "RESTRICTED" and row["consent"] == "EXPLICIT_SESSION_OPT_IN" and row["retention"] == "SESSION_OR_24_HOURS" and "no inference" in row["encoding"], "sensitive support self-report must be opt-in, short-lived, Restricted and non-inferred")
    protected = d["protected_attribute_policy"]
    exact_keys(protected, {"forbidden_direct_features", "forbidden_proxy_features", "proxy_review_required_for_new_feature", "competency_score_use", "employment_or_medical_decision_use"}, "protected policy")
    forbidden = set(protected["forbidden_direct_features"]) | set(protected["forbidden_proxy_features"])
    require(not (forbidden & set(FEATURE_IDS)), "protected attribute/proxy appears in feature dictionary")
    require(protected["proxy_review_required_for_new_feature"] is True and protected["competency_score_use"] == "FORBIDDEN", "protected attribute policy must fail closed")
    require(d["missingness_policy"] == {"unknown_is_not_false": True, "missing_value_encoding": "MISSING", "persona_neutral_value_microunit": 0, "missing_feature_ids_are_audited": True, "maximum_missing_features_before_insufficient_context": 6, "outcome": "INSUFFICIENT_CONTEXT"}, "rubric missingness policy drift")
    require(d["release_gate"]["required_evaluation_suite_id"] == "EVAL-DIAG-RAW-E2E" and d["release_gate"]["state_until_fresh_evidence"] == "NOT_READY", "rubric release gate drift")
    print("PASS: 7 competencies, 21 observable indicators, 84 anchors, 42 questions and protected-feature closure")
    return d


def verify_persona(root: Path, rubric: dict[str, Any]) -> None:
    d = load(root, "persona-inference-policy.json")
    exact_keys(d, {"schema_version", "policy_version", "release_state", "feature_dictionary_ref", "features", "profiles", "normalization", "missingness", "prohibited_inputs", "sensitive_support_policy", "calibration", "user_control"}, "persona root")
    require(d["schema_version"] == "persona-inference-policy.v1" and d["policy_version"] == "persona-inference.v1", "persona identity drift")
    require(d["release_state"] == "NON_PRODUCTION_REQUIRES_PILOT_CALIBRATION", "persona cannot be production ready without calibration")
    require(d["feature_dictionary_ref"] == "rubric-question-contract.json#/feature_dictionary", "persona feature dictionary reference drift")
    features = d["features"]
    require([row.get("feature_id") for row in features] == FEATURE_IDS, "persona features must exactly follow rubric feature dictionary")
    require([row["feature_id"] for row in rubric["feature_dictionary"]] == FEATURE_IDS, "rubric feature cross-reference drift")
    for row in features:
        exact_keys(row, {"feature_id", "input_minimum_microunit", "input_maximum_microunit", "missing_value_microunit", "missing_indicator_audited"}, f"persona feature {row.get('feature_id')}")
        require(row["input_minimum_microunit"] == 0 and row["input_maximum_microunit"] == SCALE, "persona feature range drift")
        require(row["missing_value_microunit"] == 0 and row["missing_indicator_audited"] is True, "persona missing value must be neutral and audited")
    profiles = d["profiles"]
    require([row.get("profile_id") for row in profiles] == PROFILE_IDS, "exact 12 persona profiles/order required")
    for row in profiles:
        exact_keys(row, {"profile_id", "family_id", "name", "intercept_microunit", "coefficients"}, f"profile {row.get('profile_id')}")
        require(row["family_id"] == row["profile_id"][:4] and row["intercept_microunit"] == 0, "profile family/intercept drift")
        coefficients = row["coefficients"]
        require([item.get("feature_id") for item in coefficients] == FEATURE_IDS, "profile coefficient feature order/closure drift")
        expected = PROFILE_NONZERO[row["profile_id"]]
        for item in coefficients:
            exact_keys(item, {"feature_id", "coefficient_microunit"}, "profile coefficient")
            require(integer(item["coefficient_microunit"], "persona coefficient") == expected.get(item["feature_id"], 0), f"coefficient drift for {row['profile_id']} {item['feature_id']}")
    normalization = d["normalization"]
    exact_keys(normalization, {"arithmetic", "coefficient_scale", "raw_score_formula", "positive_score_formula", "probability_formula", "residual_rule", "profile_probability_sum", "family_probability_formula", "family_probability_sum", "mixed_family_threshold_microunit", "top_profile_count", "tie_break"}, "persona normalization")
    require(normalization["arithmetic"] == "ARBITRARY_PRECISION_INTEGER" and normalization["coefficient_scale"] == SCALE, "persona arithmetic must be fixed-point")
    require(normalization["profile_probability_sum"] == SCALE and normalization["family_probability_sum"] == SCALE and normalization["mixed_family_threshold_microunit"] == 450_000, "persona normalization sums/threshold drift")
    require(d["missingness"] == {"encoding": "MISSING", "neutral_imputation_microunit": 0, "maximum_missing_features": 6, "exceeded_outcome": "INSUFFICIENT_CONTEXT", "silent_imputation": "FORBIDDEN"}, "persona missingness drift")
    prohibited = d["prohibited_inputs"]
    require(prohibited["inferred_protected_attribute"] == "FORBIDDEN" and prohibited["effect_on_competency_score"] == "FORBIDDEN", "protected attributes/proxies not forbidden")
    require(not (set(prohibited["direct"]) | set(prohibited["proxies"])) & set(FEATURE_IDS), "forbidden persona feature present")
    support = d["sensitive_support_policy"]
    exact_keys(support, {"field_ids", "collection", "data_class", "retention", "allowed_use", "clinical_or_emotion_inference", "diagnosis_score_effect", "employment_decision_use", "withdrawal_effect"}, "sensitive support policy")
    require(support["field_ids"] == ["support.current_emotional_load", "support.encouragement_preference"] and support["collection"] == "EXPLICIT_SESSION_OPT_IN_SELF_REPORT_ONLY", "sensitive support field/collection drift")
    require(support["data_class"] == "RESTRICTED" and support["retention"] == "SESSION_OR_24_HOURS", "sensitive support data class/retention drift")
    require(all(support[key] == "FORBIDDEN" for key in ("clinical_or_emotion_inference", "diagnosis_score_effect", "employment_decision_use")), "sensitive support data may not drive inference, competency or employment decisions")
    require(support["withdrawal_effect"] == "PURGE_IMMEDIATELY_AND_RECOMPUTE_WITHOUT_FIELDS", "sensitive support withdrawal must purge and recompute")
    calibration = d["calibration"]
    require(calibration["minimum_sessions"] == 600 and calibration["minimum_per_profile"] == 40 and calibration["current_evidence_state"] == "MISSING" and calibration["activation_outcome"] == "NOT_READY", "persona calibration gate drift")
    print("PASS: exact 12-profile coefficients, deterministic normalization, missingness and non-production calibration gate close")


def verify_authorization(root: Path) -> None:
    d = load(root, "operation-authorization-contracts.json")
    exact_keys(d, {"schema_version", "policy_version", "default_decision", "data_use_policy_registry_ref", "role_vocabulary", "operations", "operation_vectors", "decision_algorithm", "deny_invariants", "redaction_receipt", "negative_vectors", "audit"}, "authorization root")
    require(d["schema_version"] == "operation-authorization-contracts.v1" and d["policy_version"] == "high-privilege-abac.v1", "authorization identity drift")
    require(d["default_decision"] == "DENY" and d["data_use_policy_registry_ref"] == "data-use-policy-registry.json", "authorization must deny-by-default and reference canonical data-use registry")
    data_use_registry = load(root, "data-use-policy-registry.json")
    require(data_use_registry.get("schema_version") == "data-use-policy-registry.v1" and data_use_registry.get("unknown_category_policy") == "DENY", "referenced data-use policy registry identity/default drift")
    category_ids = {row.get("category_id") for row in data_use_registry.get("categories", [])}
    require({"TEACHER_CONTEXT", "DIAGNOSIS_EVIDENCE", "DRAFT_FIELD", "OPERATIONAL_METADATA"} <= category_ids, "data-use registry lacks categories required by high-privilege operations")
    registry_receipt = data_use_registry.get("redaction_receipt_contract", {})
    require(registry_receipt.get("provider_call_count_on_denial") == 0 and registry_receipt.get("receipt_write_stage") == "BEFORE_PROVIDER_CALL", "data-use registry redaction receipt does not deny before provider")
    require(d["role_vocabulary"] == ROLE_VOCABULARY and "ROLE_CLINICAL_SAFETY_REVIEWER" not in d["role_vocabulary"], "authorization role vocabulary drift or medicalized role leaked")
    operations = d["operations"]
    require([row.get("operation_id") for row in operations] == OPERATION_IDS, "high-privilege operation inventory/order drift")
    for row in operations:
        exact_keys(row, {"operation_id", "action", "risk_tier", "initiator_roles", "subject_constraints", "resource_constraints", "environment_constraints", "separation_of_duties", "dual_approval", "data_use_authorization", "success_receipts"}, f"operation {row.get('operation_id')}")
        require(row["risk_tier"] == "HIGH_PRIVILEGE" and row["initiator_roles"], "operation role/risk missing")
        require(set(row["initiator_roles"] + row["separation_of_duties"]["approver_role_sets"]) <= set(ROLE_VOCABULARY), "operation references role outside exact vocabulary")
        require("tenant_id==subject.tenant_id" in row["resource_constraints"] and "resource.tenant_id==request.tenant_id" in row["resource_constraints"], "tenant ABAC binding missing")
        sod = row["separation_of_duties"]
        exact_keys(sod, {"initiator_cannot_approve", "approvers_must_be_distinct", "approver_role_sets"}, "SoD")
        require(sod["initiator_cannot_approve"] is True and sod["approvers_must_be_distinct"] is True and len(sod["approver_role_sets"]) == 2, "SoD must require two role-distinct approvers")
        dual = row["dual_approval"]
        exact_keys(dual, {"required", "minimum_distinct_approvers", "approval_ttl_seconds", "bind_fields"}, "dual approval")
        require(dual["required"] is True and dual["minimum_distinct_approvers"] == 2 and dual["approval_ttl_seconds"] == 1800, "dual approval gate drift")
        data_use = row["data_use_authorization"]
        require(data_use == {"registry_ref": "data-use-policy-registry.json", "required_decision": "ALLOW", "purpose_exact_match": True, "field_allowlist_exact_match": True, "redaction_receipt_required": True}, "operation data-use/redaction binding drift")
        require(set(row["success_receipts"]) == {"POLICY_DECISION_RECEIPT", "DUAL_APPROVAL_RECEIPT", "REDACTION_RECEIPT", "AUDIT_COMMIT_RECEIPT"}, "operation success receipt closure drift")
    vectors = d["operation_vectors"]
    require(isinstance(vectors, list) and len(vectors) == 16, "each high-privilege operation requires exact allow and deny vector")
    for operation_id in OPERATION_IDS:
        rows = [row for row in vectors if row.get("operation_id") == operation_id]
        require([row.get("case_id") for row in rows] == [f"{operation_id}-ALLOW", f"{operation_id}-DENY-SOD"], f"operation vectors missing for {operation_id}")
        for row in rows:
            exact_keys(row, {"case_id", "operation_id", "initiator_role", "approver_roles", "tenant_relation", "redaction_receipt", "expected_decision", "provider_calls_before_allow"}, "operation vector")
            require(row["initiator_role"] in ROLE_VOCABULARY and set(row["approver_roles"]) <= set(ROLE_VOCABULARY), "operation vector role outside exact vocabulary")
            require(row["tenant_relation"] == "SAME_TENANT" and row["redaction_receipt"] == "VALID_AND_PAYLOAD_BOUND" and row["provider_calls_before_allow"] == 0, "operation vector precondition/provider-call drift")
        require(rows[0]["expected_decision"] == "ALLOW" and rows[0]["initiator_role"] not in rows[0]["approver_roles"] and len(set(rows[0]["approver_roles"])) == 2, "operation allow vector does not prove SoD/dual approval")
        require(rows[1]["expected_decision"] == "DENY" and rows[1]["initiator_role"] in rows[1]["approver_roles"], "operation deny vector does not prove initiator-approver SoD")
    expected_algorithm = ["STRICT_PARSE_AND_REJECT_UNKNOWN", "AUTHENTICATE_AAL2_AND_CURRENT_SESSION", "BIND_TENANT_SUBJECT_RESOURCE_AND_REQUEST_HASH", "EVALUATE_OPERATION_ABAC_DENY_OVERRIDES", "VERIFY_SOD_AND_TWO_DISTINCT_FRESH_APPROVALS", "AUTHORIZE_DATA_PURPOSE_FIELDS_AND_DESTINATION", "VERIFY_REDACTION_RECEIPT_AGAINST_PAYLOAD_HASH", "COMMIT_IMMUTABLE_AUDIT_PRECONDITION", "EXECUTE_ONCE_WITH_IDEMPOTENCY_KEY", "COMMIT_RESULT_RECEIPT_OR_COMPENSATE"]
    require(d["decision_algorithm"] == expected_algorithm, "authorization decision order drift")
    deny = d["deny_invariants"]
    require(deny["provider_call_count"] == 0 and deny["side_effect_count"] == 0 and deny["sensitive_field_in_log_count"] == 0, "denied request must cause zero provider calls/side effects/leaks")
    require(all(row.get("expected_provider_calls") == 0 and row.get("expected_decision", "").startswith("DENY") for row in d["negative_vectors"]), "authorization negative vectors must deny before provider")
    receipt = d["redaction_receipt"]
    exact_keys(receipt, {"registry_contract_ref", "required_fields", "signature", "maximum_lifetime_seconds", "empty_removed_fields_allowed_only_if_policy_expected_empty"}, "redaction receipt")
    require(receipt["registry_contract_ref"] == "data-use-policy-registry.json#/redaction_receipt_contract", "redaction receipt registry reference drift")
    require(set(registry_receipt.get("required_fields", [])) <= set(receipt["required_fields"]), "operation receipt does not include every canonical registry receipt field")
    require(receipt["signature"] == "ED25519_OVER_RFC8785_JCS" and receipt["maximum_lifetime_seconds"] == 300 and "output_hash" in receipt["required_fields"], "redaction receipt signature/binding drift")
    print("PASS: 8 high-privilege operations bind ABAC, SoD, dual approval, data use, redaction and zero-call denial")


def verify_evaluation(root: Path) -> None:
    d = load(root, "evaluation-policy-contract.json")
    exact_keys(d, {"schema_version", "policy_version", "result_states", "global_decision_order", "holdout_policy", "adjudication_policy", "confidence_interval_policy", "multiplicity_policy", "leakage_controls", "insufficient_data_policy", "suites", "negative_vectors", "release_rule"}, "evaluation root")
    require(d["schema_version"] == "evaluation-policy-contract.v1" and d["policy_version"] == "evaluation-policy.v1", "evaluation identity drift")
    require(d["result_states"] == ["PASS", "FAIL", "INSUFFICIENT_DATA", "BLOCKED"], "evaluation state vocabulary drift")
    holdout = d["holdout_policy"]
    require(holdout == {"minimum_fraction_microunit": 200_000, "subject_disjoint": True, "dataset_hash_locked_before_evaluation": True, "training_or_prompt_tuning_reuse": "FORBIDDEN", "post_unblinding_changes_require_new_dataset_version": True}, "holdout policy drift")
    require(d["adjudication_policy"]["minimum_independent_raters"] == 2 and d["adjudication_policy"]["adjudicator_cannot_be_model_tuner"] is True, "independent adjudication policy drift")
    ci_policy = d["confidence_interval_policy"]
    require(ci_policy["required_for_every_metric"] is True and ci_policy["minimum_level_microunit"] == 950_000 and ci_policy["point_estimate_only"] == "FORBIDDEN", "confidence interval policy drift")
    multiplicity = d["multiplicity_policy"]
    require(multiplicity == {"family_definition": "suite_id", "method": "HOLM_BONFERRONI", "family_wise_alpha_microunit": 50_000, "unadjusted_significance_claim": "FORBIDDEN"}, "multiplicity control drift")
    leakage = d["leakage_controls"]
    for field in ("training_corpus_overlap_maximum", "subject_overlap_maximum", "near_duplicate_hash_overlap_maximum", "prompt_example_overlap_maximum"):
        require(leakage[field] == 0, f"leakage control {field} must be zero")
    require(leakage["retrieval_index_contains_holdout_labels"] is False and leakage["detected_outcome"] == "FAIL", "leakage detection must fail release")
    insufficient = d["insufficient_data_policy"]
    require(all(insufficient[field] == "INSUFFICIENT_DATA" for field in ("sample_below_minimum", "empty_required_slice", "slice_below_minimum", "missing_confidence_interval", "missing_adjudication")), "insufficient data mapping drift")
    require(insufficient["cannot_be_overridden_to_pass"] is True, "INSUFFICIENT_DATA cannot become PASS")
    suites = d["suites"]
    require([row.get("suite_id") for row in suites] == list(SUITE_MINIMUMS), "evaluation suite inventory/order drift")
    for row in suites:
        exact_keys(row, {"suite_id", "target", "minimum_sample_size", "unit", "required_slices", "metrics", "confidence_interval", "adjudication"}, f"evaluation suite {row.get('suite_id')}")
        require(integer(row["minimum_sample_size"], "minimum sample") == SUITE_MINIMUMS[row["suite_id"]], f"minimum sample drift for {row['suite_id']}")
        require(row["required_slices"] and all(integer(item.get("minimum_sample_size"), "slice sample") > 0 for item in row["required_slices"]), "required evaluation slice empty or unbounded")
        require(len({item.get("slice_id") for item in row["required_slices"]}) == len(row["required_slices"]), "duplicate evaluation slice")
        require(row["metrics"] and all(set(item) == {"metric_id", "threshold_operator", "threshold_microunit"} for item in row["metrics"]), "evaluation metric contract not closed")
        for metric in row["metrics"]:
            integer(metric["threshold_microunit"], "metric threshold")
        ci = row["confidence_interval"]
        exact_keys(ci, {"method", "level_microunit", "replicates", "pass_rule"}, "suite confidence interval")
        require(ci["level_microunit"] == 950_000 and ci["pass_rule"], "suite confidence interval missing or too weak")
        adj = row["adjudication"]
        exact_keys(adj, {"independent_raters", "blinded", "disagreement_resolution", "retain_original_labels"}, "suite adjudication")
        require(adj["independent_raters"] >= 2 and adj["blinded"] is True and adj["retain_original_labels"] is True, "suite adjudication weak")
    raw = suites[0]
    require(raw["target"] == "raw dialogue -> minimized span -> indicator/anchor -> deterministic score/decision", "raw dialogue E2E target drift")
    raw_metrics = {item["metric_id"]: item for item in raw["metrics"]}
    require(raw_metrics["WEIGHTED_EXPERT_AGREEMENT"]["threshold_microunit"] == 850_000 and raw_metrics["TRAIN_HOLDOUT_LEAKAGE"]["threshold_microunit"] == 0, "raw dialogue agreement/leakage gate drift")
    negative = {row.get("case_id"): row for row in d["negative_vectors"]}
    require(negative.get("EVAL-N-001", {}).get("expected_state") == "INSUFFICIENT_DATA", "one-query negative must be insufficient")
    require(negative.get("EVAL-N-002", {}).get("expected_state") == "INSUFFICIENT_DATA", "empty-slice negative must be insufficient")
    require(negative.get("EVAL-N-003", {}).get("expected_state") == "FAIL", "training reuse must fail")
    require(negative.get("EVAL-N-004", {}).get("expected_state") == "INSUFFICIENT_DATA", "missing CI must be insufficient")
    require(d["release_rule"]["nonproduction_calibration_pending_outcome"] == "NOT_READY" and d["release_rule"]["insufficient_data_is_not_pass"] is True, "evaluation release rule drift")
    print("PASS: minimum samples/slices, holdout, adjudication, CI, multiplicity, leakage and INSUFFICIENT_DATA close")


def verify_document_graph(root: Path) -> None:
    d = load(root, "document-graph.schema.json")
    props = d.get("properties", {})
    require(all(name in props for name in ("styles", "resources", "losses", "active_content_findings")), "DocumentGraph style/resource/loss/active-content collections missing")
    defs = d.get("$defs", {})
    for name in ("styleDefinition", "resourceDefinition", "lossRecord", "activeContentFinding", "imageData", "fieldData"):
        require(name in defs and defs[name].get("additionalProperties") is False, f"DocumentGraph closed definition missing: {name}")
    require(defs["styleDefinition"]["required"] == ["style_id", "style_type", "canonical_properties_sha256", "source_style_name"], "style definition closure drift")
    require(defs["resourceDefinition"]["required"] == ["resource_id", "resource_type", "sha256", "media_type", "size_bytes"], "resource definition closure drift")
    require(defs["imageData"]["required"] == ["resource_id", "alt_text", "decorative", "caption_node_id"], "image alt/resource contract drift")
    require(defs["fieldData"]["required"] == ["field_type", "field_name", "display_text", "locked"], "field preservation contract drift")
    require("border_ref" in defs["cellData"]["properties"], "cell border reference contract missing")
    require(defs["node"]["properties"].get("image") == {"$ref": "#/$defs/imageData"} and defs["node"]["properties"].get("field") == {"$ref": "#/$defs/fieldData"}, "node image/field contracts missing")
    require("FIELD" in defs["node"]["properties"]["type"]["enum"], "FIELD node vocabulary missing")
    semantic = d.get("x-semantic-contract", {})
    require(semantic.get("production_profile_required_properties") == ["styles", "resources", "losses", "active_content_findings"], "DocumentGraph production profile closure drift")
    expected_integrity = [
        "every non-null style_ref resolves to exactly one styles[].style_id",
        "every non-null CELL border_ref resolves to exactly one BORDER styles[].style_id",
        "every IMAGE image.resource_id resolves to exactly one IMAGE resources[].resource_id",
        "every non-decorative IMAGE has non-empty alt_text and every decorative IMAGE has empty alt_text",
        "every image caption_node_id resolves to a CAPTION node when non-null",
        "every FIELD has field data and FIELD data is absent on non-FIELD nodes",
    ]
    require(semantic.get("resource_integrity") == expected_integrity, "DocumentGraph dangling style/resource/border/field rules drift")
    expected_losses = ["STYLE_SUBSTITUTION", "BORDER_DEGRADATION", "IMAGE_ALT_MISSING", "FIELD_FLATTENED", "FONT_SUBSTITUTION", "LAYOUT_SHIFT", "MACRO_QUARANTINED", "OLE_QUARANTINED", "UNSUPPORTED_OBJECT"]
    require(semantic.get("loss_taxonomy") == expected_losses and defs["lossRecord"]["properties"]["category"]["enum"] == expected_losses, "DocumentGraph loss taxonomy drift")
    active = semantic.get("active_content_policy", {})
    require(active == {"macro_ole_action": "QUARANTINE_AND_NEVER_EXECUTE", "finding_executed_must_equal": False, "missing_scan_receipt": "REJECT", "blocking_finding_release_state": "BLOCKED"}, "macro/OLE fail-closed policy drift")
    require(defs["activeContentFinding"]["properties"]["action"] == {"const": "QUARANTINED"} and defs["activeContentFinding"]["properties"]["executed"] == {"const": False}, "active content schema must quarantine and forbid execution")
    print("PASS: DocumentGraph style/resource/loss/image-alt/border/field and macro/OLE integrity contracts close")


def verify_hwp(root: Path) -> None:
    d = load(root, "hwp-conversion-boundary-contract.json")
    acceptance = d.get("licensed_roundtrip_acceptance", {})
    exact_keys(acceptance, {"release_state", "environment", "minimum_golden_documents", "required_actions", "edit_script", "required_slices", "acceptance_metrics", "required_evidence", "simulator_or_hwpx_only_result"}, "licensed HWP roundtrip")
    require(acceptance["release_state"] == "NOT_READY" and acceptance["environment"] == "LICENSED_WINDOWS_CONVERTER_ISOLATED_NODE", "licensed HWP acceptance state/environment drift")
    require(acceptance["minimum_golden_documents"] == 100, "licensed HWP golden corpus minimum drift")
    require(acceptance["required_actions"] == ["OPEN", "EDIT", "SAVE_AS_HWPX", "REOPEN", "PRINT_TO_PDF"], "licensed HWP open-edit-save-reopen-print sequence drift")
    require(set(acceptance["required_slices"]) == {"MERGED_TABLE", "NESTED_TABLE", "STYLE", "BORDER", "IMAGE_ALT", "FIELD", "MACRO", "OLE"}, "licensed HWP slice closure drift")
    metrics = {row.get("metric_id"): row for row in acceptance["acceptance_metrics"]}
    require(metrics.get("MACRO_OLE_EXECUTIONS", {}).get("threshold_microunit") == 0 and metrics.get("STYLE_BORDER_FIELD_RESOURCE_DANGLING_REFERENCES", {}).get("threshold_microunit") == 0, "HWP active-content/dangling-reference zero budget drift")
    require(acceptance["simulator_or_hwpx_only_result"] == "BLOCKED", "simulator/HWPX-only evidence cannot satisfy HWP gate")
    active = d.get("active_content_roundtrip_policy", {})
    require(active.get("macro") == "QUARANTINE_NEVER_EXECUTE_NEVER_REEMBED" and active.get("ole") == "QUARANTINE_NEVER_ACTIVATE_STATIC_NONINTERACTIVE_RENDER_ONLY" and active.get("detected_execution") == "QUARANTINE_HOST_AND_FAIL_RELEASE", "HWP macro/OLE policy drift")
    print("PASS: licensed HWP open-edit-save-reopen-print and active-content fail-closed acceptance close")


def verify_provider(root: Path) -> None:
    d = load(root, "provider-decision-registry.json")
    require(d.get("overall_release_state") == "NOT_READY", "provider registry must remain NOT_READY")
    required_fields = ["decision_id", "subject", "status", "owner_ids", "due_at", "required_input_ids", "gate_ids", "data_processing_agreement", "approved_regions", "region_decision_state", "exit_plan_id", "evidence_freshness_days", "release_state"]
    require(d.get("decision_required_fields") == required_fields, "provider decision required fields drift")
    decisions = d.get("decisions", [])
    require([row.get("decision_id") for row in decisions] == PROVIDER_DECISIONS, "provider/infrastructure decision inventory/order drift")
    for row in decisions:
        require(set(row) == set(required_fields), f"provider decision {row.get('decision_id')} is not closed")
        require(row["owner_ids"] and row["due_at"] and row["required_input_ids"] and row["gate_ids"], f"provider decision {row['decision_id']} is not actionable")
        require(row["data_processing_agreement"] in {"REQUIRED", "CONDITIONAL_ON_HOSTING_MODEL"}, "provider DPA decision missing")
        require(row["approved_regions"] == [] and row["region_decision_state"] == "REQUIRES_ACCEPTANCE_DATA", "unapproved provider region must remain empty/pending")
        require(row["exit_plan_id"].startswith("EXIT-") and row["evidence_freshness_days"] == 90 and row["release_state"] == "NOT_READY", "provider exit/freshness/release state drift")
    require("Every decision row" in d.get("activation_rule", "") and "NOT_READY" in d["activation_rule"], "provider activation fail-closed rule missing")
    print("PASS: 16 AI/document/infrastructure provider decisions bind owner, due, DPA, region, exit and NOT_READY")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-dir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    root = args.base_dir.resolve()
    rubric = verify_rubric(root)
    verify_persona(root, rubric)
    verify_authorization(root)
    verify_evaluation(root)
    verify_document_graph(root)
    verify_hwp(root)
    verify_provider(root)
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
