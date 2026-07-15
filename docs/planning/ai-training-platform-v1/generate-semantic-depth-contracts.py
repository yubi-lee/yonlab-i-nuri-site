#!/usr/bin/env python3
"""Generate the tightly pinned semantic-depth design contracts.

The generated artifacts are normative design inputs.  Runtime implementations
must reproduce their closed vocabularies and fail-closed policies; this script
does not select or activate a production provider.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
SCALE = 1_000_000


def write_json(name: str, value: dict[str, Any]) -> None:
    (ROOT / name).write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )


COMPETENCIES = [
    ("COMP-01", "보육과정 실행", [
        ("I01", "놀이 관찰을 목표와 연결한다"),
        ("I02", "영유아 반응에 따라 계획을 조정한다"),
        ("I03", "실행 결과를 다음 계획에 환류한다"),
    ]),
    ("COMP-02", "영유아 발달 이해", [
        ("I01", "발달 차이를 관찰 근거로 설명한다"),
        ("I02", "개별 발달 수준에 맞는 지원을 선택한다"),
        ("I03", "발달 낙인 없이 강점과 필요를 함께 기록한다"),
    ]),
    ("COMP-03", "교사-영유아 상호작용", [
        ("I01", "영유아 신호에 민감하게 반응한다"),
        ("I02", "열린 질문과 기다림으로 사고를 확장한다"),
        ("I03", "갈등을 권리 존중 방식으로 중재한다"),
    ]),
    ("COMP-04", "관찰·기록·평가", [
        ("I01", "사실과 해석을 구분해 기록한다"),
        ("I02", "복수 시점의 근거를 종합한다"),
        ("I03", "기록을 지원 계획과 연결한다"),
    ]),
    ("COMP-05", "가정·지역사회 연계", [
        ("I01", "보호자와 상호 존중 방식으로 소통한다"),
        ("I02", "필요한 지역 자원을 적절히 연계한다"),
        ("I03", "개인정보와 동의 경계를 지킨다"),
    ]),
    ("COMP-06", "안전·권리·윤리", [
        ("I01", "위험을 사전에 식별하고 예방한다"),
        ("I02", "아동권리와 신고 절차를 준수한다"),
        ("I03", "안전사건 후 기록·보고·재발방지를 수행한다"),
    ]),
    ("COMP-07", "전문성·학습운영", [
        ("I01", "실천을 성찰하고 개선 목표를 세운다"),
        ("I02", "동료와 근거 기반 피드백을 주고받는다"),
        ("I03", "디지털 도구를 안전하고 목적에 맞게 활용한다"),
    ]),
]


FEATURES = [
    ("context.return_after_leave", "BOOLEAN_MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "UNTIL_WITHDRAWAL_OR_365_DAYS", "false=0,true=1000000"),
    ("context.career_band", "ENCODED_ENUM_MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "UNTIL_WITHDRAWAL_OR_365_DAYS", "ENTRY_0_2=1000000,DEVELOPING_3_5=500000,EXPERIENCED_6_PLUS=0,NOT_PROVIDED=MISSING"),
    ("context.region_resource_category", "ENCODED_ENUM_MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "UNTIL_WITHDRAWAL_OR_180_DAYS", "LIMITED=1000000,PARTIAL=500000,ADEQUATE=0,NOT_PROVIDED=MISSING; exact location forbidden"),
    ("experience.practice_context_breadth", "MICROUNIT", "EXPLICIT_APPROVED_TAXONOMY", "INTERNAL", "UNTIL_WITHDRAWAL_OR_365_DAYS", "approved IDs INFANT,EARLY_CHILDHOOD,MIXED_AGE,INCLUSIVE,LEAD_TEACHER,RETURNING; count/6 half-up"),
    ("interest.keyword_id", "PROFILE_AFFINITY_MICROUNIT", "EXPLICIT_APPROVED_TAXONOMY", "INTERNAL", "UNTIL_WITHDRAWAL_OR_180_DAYS", "approved IDs KW-PLAY,KW-OBSERVATION,KW-SAFETY,KW-FAMILY,KW-DIGITAL,KW-COACHING; unknown reject; per-profile match 0 or 1000000"),
    ("constraint.time_pressure", "MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "UNTIL_WITHDRAWAL_OR_90_DAYS", "integer 0..1000000"),
    ("constraint.low_bandwidth", "MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "UNTIL_WITHDRAWAL_OR_90_DAYS", "integer 0..1000000"),
    ("preference.mentor_support", "MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "UNTIL_WITHDRAWAL_OR_180_DAYS", "integer 0..1000000"),
    ("preference.examples_first", "MICROUNIT", "DIALOGUE_EVIDENCE", "INTERNAL", "SESSION_OR_30_DAYS", "integer 0..1000000"),
    ("preference.small_steps", "MICROUNIT", "DIALOGUE_EVIDENCE", "INTERNAL", "SESSION_OR_30_DAYS", "integer 0..1000000"),
    ("need.policy_change_refresh", "MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "UNTIL_WITHDRAWAL_OR_180_DAYS", "integer 0..1000000"),
    ("need.digital_reentry", "MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "UNTIL_WITHDRAWAL_OR_180_DAYS", "integer 0..1000000"),
    ("interest.advanced_cases", "MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "UNTIL_WITHDRAWAL_OR_180_DAYS", "integer 0..1000000"),
    ("interest.peer_coaching", "MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "UNTIL_WITHDRAWAL_OR_180_DAYS", "integer 0..1000000"),
    ("need.local_resource_alternative", "MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "UNTIL_WITHDRAWAL_OR_90_DAYS", "integer 0..1000000"),
    ("preference.human_support", "MICROUNIT", "EXPLICIT_USER_STATEMENT", "INTERNAL", "SESSION_OR_30_DAYS", "integer 0..1000000"),
    ("support.current_emotional_load", "ENCODED_ENUM_MICROUNIT", "EXPLICIT_SESSION_OPT_IN_SELF_REPORT", "RESTRICTED", "SESSION_OR_24_HOURS", "NONE=0,LOW=333333,MODERATE=666667,HIGH=1000000; no inference"),
    ("support.encouragement_preference", "ENCODED_ENUM_MICROUNIT", "EXPLICIT_SESSION_OPT_IN_SELF_REPORT", "RESTRICTED", "SESSION_OR_24_HOURS", "NONE=0,GENTLE=500000,ACTIVE=1000000; no inference"),
]


def rubric_question_contract() -> dict[str, Any]:
    indicators: list[dict[str, Any]] = []
    questions: list[dict[str, Any]] = []
    for competency_id, competency_name, indicator_rows in COMPETENCIES:
        for ordinal, (suffix, statement) in enumerate(indicator_rows, start=1):
            indicator_id = f"{competency_id}-{suffix}"
            anchors = [
                {"level": "L1", "anchor_microunit": 0, "observable_behavior": f"{statement}의 필요성을 인식하지만 구체적 실행 근거가 없다", "counterexample": f"{statement}에 대해 의도나 일반론만 말하고 실제 행동을 제시하지 않는다"},
                {"level": "L2", "anchor_microunit": 333_333, "observable_behavior": f"안내 또는 예시가 있을 때 {statement}", "counterexample": f"{statement}의 한 사례를 모든 상황에 그대로 적용한다"},
                {"level": "L3", "anchor_microunit": 666_667, "observable_behavior": f"일상에서 근거를 확인하며 일관되게 {statement}", "counterexample": f"{statement} 뒤 상황 조정이나 결과 확인 없이 반복한다"},
                {"level": "L4", "anchor_microunit": 1_000_000, "observable_behavior": f"복합 상황에서 근거를 비교하고 동료와 성찰하며 {statement}", "counterexample": f"{statement}의 근거 없이 타인에게 적용을 강요하거나 예외를 무시한다"},
            ]
            indicators.append({
                "indicator_id": indicator_id,
                "competency_id": competency_id,
                "competency_name": competency_name,
                "statement": statement,
                "priority": ordinal,
                "minimum_distinct_turns": 2,
                "anchors": anchors,
            })
            for form, prompt in (
                ("SITUATIONAL", f"최근 현장에서 ‘{statement}’와 관련해 판단이 필요했던 한 장면을 사실과 행동 중심으로 설명해 주세요."),
                ("REFLECTIVE", f"‘{statement}’를 실행한 뒤 무엇을 확인했고, 다음에는 무엇을 다르게 하시겠습니까?"),
            ):
                questions.append({
                    "question_id": f"Q-{indicator_id}-{form[:3]}",
                    "indicator_ids": [indicator_id],
                    "question_form": form,
                    "prompt_ko": prompt,
                    "response_schema": "FREE_TEXT_NFC_20_TO_2000_CODEPOINTS",
                    "leading_language": "FORBIDDEN",
                    "sensitive_attribute_request": "FORBIDDEN",
                    "expected_information_gain_microunit": 700_000 if form == "SITUATIONAL" else 500_000,
                })
    feature_dictionary = [
        {
            "feature_id": feature_id,
            "value_type": value_type,
            "source": source,
            "missingness": "NEUTRAL_ZERO",
            "data_class": data_class,
            "retention": retention,
            "consent": "EXPLICIT_SESSION_OPT_IN" if source == "EXPLICIT_SESSION_OPT_IN_SELF_REPORT" else "EXPLICIT_OR_DIALOGUE_CONFIRMATION",
            "encoding": encoding,
            "allowed_use": "PERSONA_CONTEXT_AND_RECOMMENDATION_ONLY",
            "diagnosis_score_effect": "FORBIDDEN",
            "user_control": "VIEW_CORRECT_WITHDRAW",
        }
        for feature_id, value_type, source, data_class, retention, encoding in FEATURES
    ]
    return {
        "schema_version": "rubric-question-contract.v1",
        "release_state": "NON_PRODUCTION_REQUIRES_PILOT_CALIBRATION",
        "rubric_version": "teacher-competency-rubric.v1",
        "question_bank_version": "teacher-diagnostic-question-bank.v1",
        "scale": {
            "levels": ["L1", "L2", "L3", "L4"],
            "anchor_microunits": [0, 333_333, 666_667, 1_000_000],
            "interpretation": ["기초 인식", "부분 적용", "일관 적용", "상황 확장"],
        },
        "competencies": [
            {"competency_id": cid, "name": name, "indicator_ids": [f"{cid}-{suffix}" for suffix, _ in rows]}
            for cid, name, rows in COMPETENCIES
        ],
        "indicators": indicators,
        "questions": questions,
        "feature_dictionary": feature_dictionary,
        "missingness_policy": {
            "unknown_is_not_false": True,
            "missing_value_encoding": "MISSING",
            "persona_neutral_value_microunit": 0,
            "missing_feature_ids_are_audited": True,
            "maximum_missing_features_before_insufficient_context": 6,
            "outcome": "INSUFFICIENT_CONTEXT",
        },
        "protected_attribute_policy": {
            "forbidden_direct_features": ["sex", "gender_identity", "age", "disability", "nationality", "race", "religion", "union_membership", "health", "inferred_psychological_state"],
            "forbidden_proxy_features": ["postal_code", "exact_region", "school_name", "device_price", "native_language_inference", "name_embedding", "free_text_demographic_inference"],
            "proxy_review_required_for_new_feature": True,
            "competency_score_use": "FORBIDDEN",
            "employment_or_medical_decision_use": "FORBIDDEN",
        },
        "evidence_pipeline": {
            "stages": ["RAW_DIALOGUE_MINIMIZATION", "NFC_SPAN_EXTRACTION", "INDICATOR_MAPPING", "ANCHOR_CLASSIFICATION", "DETERMINISTIC_SCORING", "HUMAN_REVIEW_IF_REQUIRED"],
            "raw_dialogue_retention": "SEPARATE_RESTRICTED_STORE_WITH_TTL",
            "extracted_span_minimization": "REQUIRED",
            "unknown_indicator": "REJECT",
            "unknown_anchor": "REJECT",
            "score_mutation_by_llm": "FORBIDDEN",
        },
        "release_gate": {
            "required_evaluation_suite_id": "EVAL-DIAG-RAW-E2E",
            "technical_pass_does_not_activate": True,
            "pilot_calibration_owner_ids": ["OWN-AI", "OWN-ACC"],
            "state_until_fresh_evidence": "NOT_READY",
        },
    }


PROFILE_ROWS = [
    ("P-01-A", "P-01", "기초 루틴 구축형", {"context.career_band": 700_000, "preference.examples_first": 900_000, "preference.small_steps": 700_000, "preference.mentor_support": 400_000, "interest.keyword_id": 400_000}),
    ("P-01-B", "P-01", "멘토 동행 적용형", {"context.career_band": 500_000, "preference.mentor_support": 1_000_000, "preference.examples_first": 500_000, "interest.peer_coaching": 300_000, "interest.keyword_id": 400_000}),
    ("P-02-A", "P-02", "예시 확인 우선형", {"preference.examples_first": 1_000_000, "preference.small_steps": 400_000}),
    ("P-02-B", "P-02", "작은 단계 확신형", {"preference.small_steps": 1_000_000, "preference.examples_first": 400_000, "constraint.time_pressure": 200_000}),
    ("P-03-A", "P-03", "제도 변화 재정렬형", {"context.return_after_leave": 800_000, "need.policy_change_refresh": 1_000_000}),
    ("P-03-B", "P-03", "디지털 도구 재진입형", {"context.return_after_leave": 600_000, "need.digital_reentry": 1_000_000, "preference.small_steps": 300_000}),
    ("P-04-A", "P-04", "고급 사례 탐구형", {"context.career_band": -400_000, "experience.practice_context_breadth": 700_000, "interest.advanced_cases": 1_000_000, "interest.peer_coaching": 300_000, "interest.keyword_id": 400_000}),
    ("P-04-B", "P-04", "동료 코칭 확장형", {"context.career_band": -400_000, "experience.practice_context_breadth": 800_000, "interest.peer_coaching": 1_000_000, "interest.advanced_cases": 500_000, "preference.mentor_support": -200_000, "interest.keyword_id": 400_000}),
    ("P-05-A", "P-05", "시간제약 핵심형", {"constraint.time_pressure": 1_000_000, "preference.small_steps": 500_000, "preference.human_support": 200_000, "support.current_emotional_load": 600_000}),
    ("P-05-B", "P-05", "사람지원 연계형", {"preference.human_support": 1_000_000, "constraint.time_pressure": 500_000, "support.current_emotional_load": 800_000, "support.encouragement_preference": 700_000}),
    ("P-06-A", "P-06", "저대역폭 비동기형", {"context.region_resource_category": 600_000, "constraint.low_bandwidth": 1_000_000, "need.local_resource_alternative": 400_000}),
    ("P-06-B", "P-06", "지역자원 연계형", {"context.region_resource_category": 900_000, "need.local_resource_alternative": 1_000_000, "constraint.low_bandwidth": 400_000, "interest.peer_coaching": 200_000, "interest.keyword_id": 400_000}),
]


def persona_contract() -> dict[str, Any]:
    feature_ids = [row[0] for row in FEATURES]
    profiles = []
    for profile_id, family_id, name, nonzero in PROFILE_ROWS:
        profiles.append({
            "profile_id": profile_id,
            "family_id": family_id,
            "name": name,
            "intercept_microunit": 0,
            "coefficients": [
                {"feature_id": feature_id, "coefficient_microunit": nonzero.get(feature_id, 0)}
                for feature_id in feature_ids
            ],
        })
    return {
        "schema_version": "persona-inference-policy.v1",
        "policy_version": "persona-inference.v1",
        "release_state": "NON_PRODUCTION_REQUIRES_PILOT_CALIBRATION",
        "feature_dictionary_ref": "rubric-question-contract.json#/feature_dictionary",
        "features": [
            {"feature_id": feature_id, "input_minimum_microunit": 0, "input_maximum_microunit": SCALE, "missing_value_microunit": 0, "missing_indicator_audited": True}
            for feature_id in feature_ids
        ],
        "profiles": profiles,
        "normalization": {
            "arithmetic": "ARBITRARY_PRECISION_INTEGER",
            "coefficient_scale": SCALE,
            "raw_score_formula": "intercept_microunit + div_half_up(sum(coefficient_microunit * feature_value_microunit), 1000000)",
            "positive_score_formula": "max(1, 20000000 + raw_score_microunit)",
            "probability_formula": "div_half_up(1000000 * positive_score, sum_positive_scores)",
            "residual_rule": "assign 1000000-sum(probabilities) to lexicographically greatest profile_id",
            "profile_probability_sum": SCALE,
            "family_probability_formula": "sum(profile probabilities for family_id)",
            "family_probability_sum": SCALE,
            "mixed_family_threshold_microunit": 450_000,
            "top_profile_count": 3,
            "tie_break": "probability descending then profile_id NFC UTF-8 bytewise ascending",
        },
        "missingness": {
            "encoding": "MISSING",
            "neutral_imputation_microunit": 0,
            "maximum_missing_features": 6,
            "exceeded_outcome": "INSUFFICIENT_CONTEXT",
            "silent_imputation": "FORBIDDEN",
        },
        "prohibited_inputs": {
            "direct": ["sex", "gender_identity", "age", "disability", "nationality", "race", "religion", "health", "inferred_psychological_state"],
            "proxies": ["postal_code", "exact_region", "school_name", "device_price", "name_embedding", "free_text_demographic_inference"],
            "inferred_protected_attribute": "FORBIDDEN",
            "effect_on_competency_score": "FORBIDDEN",
        },
        "sensitive_support_policy": {
            "field_ids": ["support.current_emotional_load", "support.encouragement_preference"],
            "collection": "EXPLICIT_SESSION_OPT_IN_SELF_REPORT_ONLY",
            "data_class": "RESTRICTED",
            "retention": "SESSION_OR_24_HOURS",
            "allowed_use": ["RESPONSE_TONE", "LOW_BURDEN_PATH", "OPTIONAL_HUMAN_SUPPORT_OFFER"],
            "clinical_or_emotion_inference": "FORBIDDEN",
            "diagnosis_score_effect": "FORBIDDEN",
            "employment_decision_use": "FORBIDDEN",
            "withdrawal_effect": "PURGE_IMMEDIATELY_AND_RECOMPUTE_WITHOUT_FIELDS",
        },
        "calibration": {
            "dataset_split": "LOCKED_SUBJECT_DISJOINT_HOLDOUT",
            "minimum_sessions": 600,
            "minimum_per_profile": 40,
            "expected_calibration_error_maximum_microunit": 50_000,
            "brier_score_maximum_microunit": 180_000,
            "maximum_slice_ece_gap_microunit": 50_000,
            "confidence_level_microunit": 950_000,
            "current_evidence_state": "MISSING",
            "activation_outcome": "NOT_READY",
        },
        "user_control": {
            "responses": ["CONFIRM", "PARTIALLY_DIFFERENT", "DO_NOT_USE"],
            "do_not_use_effect": "PERSONA_CONTEXT_REMOVED_AND_RECOMMENDATIONS_RECOMPUTED",
            "competency_score_mutation": "FORBIDDEN",
            "immutable_version_history": True,
        },
    }


OPERATION_ROWS = [
    ("OP-DIAGNOSIS-OVERRIDE", "DIAGNOSIS_EVIDENCE_OVERRIDE", ["ROLE_DIAGNOSIS_REVIEWER"], ["ROLE_CHILD_SAFEGUARDING_REVIEWER", "ROLE_PRIVACY_REVIEWER"]),
    ("OP-RUBRIC-PUBLISH", "RUBRIC_VERSION_PUBLISH", ["ROLE_RUBRIC_EDITOR"], ["ROLE_EDUCATION_APPROVER", "ROLE_MODEL_RISK_APPROVER"]),
    ("OP-EVAL-EXPORT", "PSEUDONYMOUS_EVALUATION_EXPORT", ["ROLE_EVALUATION_OPERATOR"], ["ROLE_PRIVACY_REVIEWER", "ROLE_DATA_OWNER"]),
    ("OP-HWP-PUBLISH", "HWP_DRAFT_TEMPLATE_PUBLISH", ["ROLE_DOCUMENT_EDITOR"], ["ROLE_DOCUMENT_APPROVER", "ROLE_RIGHTS_APPROVER"]),
    ("OP-PROVIDER-ACTIVATE", "PROVIDER_DEPLOYMENT_ACTIVATE", ["ROLE_AI_PLATFORM_OPERATOR"], ["ROLE_SECURITY_APPROVER", "ROLE_MODEL_RISK_APPROVER"]),
    ("OP-LINEAGE-DELETE", "LINEAGE_CASCADE_DELETE", ["ROLE_PRIVACY_OPERATOR"], ["ROLE_DATA_OWNER", "ROLE_PRIVACY_APPROVER"]),
    ("OP-BACKUP-RESTORE", "PRODUCTION_BACKUP_RESTORE", ["ROLE_DATABASE_OPERATOR"], ["ROLE_SERVICE_OWNER", "ROLE_SECURITY_APPROVER"]),
    ("OP-ADMIN-GRANT", "PRIVILEGED_ROLE_GRANT", ["ROLE_IDENTITY_OPERATOR"], ["ROLE_SECURITY_APPROVER", "ROLE_SERVICE_OWNER"]),
]


def operation_authorization_contract() -> dict[str, Any]:
    operations = []
    operation_vectors = []
    for operation_id, action, initiator_roles, approver_roles in OPERATION_ROWS:
        operations.append({
            "operation_id": operation_id,
            "action": action,
            "risk_tier": "HIGH_PRIVILEGE",
            "initiator_roles": initiator_roles,
            "subject_constraints": ["active=true", "mfa_age_seconds<=300", "session_assurance=AAL2_OR_HIGHER"],
            "resource_constraints": ["tenant_id==subject.tenant_id", "resource.tenant_id==request.tenant_id", "resource_state_is_current=true"],
            "environment_constraints": ["approved_change_window=true", "policy_bundle_fresh=true", "audit_sink_ready=true"],
            "separation_of_duties": {
                "initiator_cannot_approve": True,
                "approvers_must_be_distinct": True,
                "approver_role_sets": approver_roles,
            },
            "dual_approval": {
                "required": True,
                "minimum_distinct_approvers": 2,
                "approval_ttl_seconds": 1800,
                "bind_fields": ["operation_id", "tenant_id", "resource_id", "resource_version", "request_sha256", "purpose", "expires_at"],
            },
            "data_use_authorization": {
                "registry_ref": "data-use-policy-registry.json",
                "required_decision": "ALLOW",
                "purpose_exact_match": True,
                "field_allowlist_exact_match": True,
                "redaction_receipt_required": True,
            },
            "success_receipts": ["POLICY_DECISION_RECEIPT", "DUAL_APPROVAL_RECEIPT", "REDACTION_RECEIPT", "AUDIT_COMMIT_RECEIPT"],
        })
        operation_vectors.extend([
            {
                "case_id": f"{operation_id}-ALLOW",
                "operation_id": operation_id,
                "initiator_role": initiator_roles[0],
                "approver_roles": approver_roles,
                "tenant_relation": "SAME_TENANT",
                "redaction_receipt": "VALID_AND_PAYLOAD_BOUND",
                "expected_decision": "ALLOW",
                "provider_calls_before_allow": 0,
            },
            {
                "case_id": f"{operation_id}-DENY-SOD",
                "operation_id": operation_id,
                "initiator_role": initiator_roles[0],
                "approver_roles": [initiator_roles[0], approver_roles[0]],
                "tenant_relation": "SAME_TENANT",
                "redaction_receipt": "VALID_AND_PAYLOAD_BOUND",
                "expected_decision": "DENY",
                "provider_calls_before_allow": 0,
            },
        ])
    return {
        "schema_version": "operation-authorization-contracts.v1",
        "policy_version": "high-privilege-abac.v1",
        "default_decision": "DENY",
        "data_use_policy_registry_ref": "data-use-policy-registry.json",
        "role_vocabulary": sorted({role for _, _, initiators, approvers in OPERATION_ROWS for role in initiators + approvers}),
        "operations": operations,
        "operation_vectors": operation_vectors,
        "decision_algorithm": [
            "STRICT_PARSE_AND_REJECT_UNKNOWN",
            "AUTHENTICATE_AAL2_AND_CURRENT_SESSION",
            "BIND_TENANT_SUBJECT_RESOURCE_AND_REQUEST_HASH",
            "EVALUATE_OPERATION_ABAC_DENY_OVERRIDES",
            "VERIFY_SOD_AND_TWO_DISTINCT_FRESH_APPROVALS",
            "AUTHORIZE_DATA_PURPOSE_FIELDS_AND_DESTINATION",
            "VERIFY_REDACTION_RECEIPT_AGAINST_PAYLOAD_HASH",
            "COMMIT_IMMUTABLE_AUDIT_PRECONDITION",
            "EXECUTE_ONCE_WITH_IDEMPOTENCY_KEY",
            "COMMIT_RESULT_RECEIPT_OR_COMPENSATE",
        ],
        "deny_invariants": {
            "unknown_operation": "DENY",
            "unknown_attribute": "DENY",
            "missing_attribute": "DENY",
            "cross_tenant": "DENY_AND_SECURITY_EVENT",
            "stale_or_replayed_approval": "DENY",
            "missing_redaction_receipt": "DENY",
            "provider_call_count": 0,
            "side_effect_count": 0,
            "sensitive_field_in_log_count": 0,
        },
        "redaction_receipt": {
            "registry_contract_ref": "data-use-policy-registry.json#/redaction_receipt_contract",
            "required_fields": ["receipt_id", "policy_version", "input_hash", "output_hash", "removed_field_codes", "decision", "provider_call_count", "tenant_id", "operation_id", "issued_at", "expires_at", "issuer", "signature"],
            "signature": "ED25519_OVER_RFC8785_JCS",
            "maximum_lifetime_seconds": 300,
            "empty_removed_fields_allowed_only_if_policy_expected_empty": True,
        },
        "negative_vectors": [
            {"case_id": "AUTH-N-001", "mutation": "missing_second_approval", "expected_decision": "DENY", "expected_provider_calls": 0},
            {"case_id": "AUTH-N-002", "mutation": "initiator_is_approver", "expected_decision": "DENY", "expected_provider_calls": 0},
            {"case_id": "AUTH-N-003", "mutation": "cross_tenant_resource", "expected_decision": "DENY_AND_SECURITY_EVENT", "expected_provider_calls": 0},
            {"case_id": "AUTH-N-004", "mutation": "stale_policy_bundle", "expected_decision": "DENY", "expected_provider_calls": 0},
            {"case_id": "AUTH-N-005", "mutation": "missing_redaction_receipt", "expected_decision": "DENY", "expected_provider_calls": 0},
            {"case_id": "AUTH-N-006", "mutation": "unknown_operation", "expected_decision": "DENY", "expected_provider_calls": 0},
        ],
        "audit": {
            "required_fields": ["decision_id", "operation_id", "tenant_id", "subject_pseudonym", "resource_id", "policy_hash", "approval_receipt_hashes", "redaction_receipt_hash", "request_sha256", "decision", "reason_codes", "provider_call_count", "occurred_at"],
            "raw_payload": "FORBIDDEN",
            "append_only": True,
        },
    }


def evaluation_contract() -> dict[str, Any]:
    suites = [
        {
            "suite_id": "EVAL-DIAG-RAW-E2E",
            "target": "raw dialogue -> minimized span -> indicator/anchor -> deterministic score/decision",
            "minimum_sample_size": 300,
            "unit": "SUBJECT_DISJOINT_SESSION",
            "required_slices": [
                {"slice_id": "RETURN_AFTER_LEAVE", "minimum_sample_size": 30},
                {"slice_id": "LOW_BANDWIDTH_CONTEXT", "minimum_sample_size": 30},
                {"slice_id": "TIME_PRESSURE_CONTEXT", "minimum_sample_size": 30},
                {"slice_id": "MISSING_CONTEXT", "minimum_sample_size": 30},
            ],
            "metrics": [
                {"metric_id": "SPAN_F1", "threshold_operator": ">=", "threshold_microunit": 900_000},
                {"metric_id": "WEIGHTED_EXPERT_AGREEMENT", "threshold_operator": ">=", "threshold_microunit": 850_000},
                {"metric_id": "STRUCTURED_OUTPUT_SUCCESS", "threshold_operator": ">=", "threshold_microunit": 998_000},
                {"metric_id": "TRAIN_HOLDOUT_LEAKAGE", "threshold_operator": "==", "threshold_microunit": 0},
            ],
            "confidence_interval": {"method": "STRATIFIED_SUBJECT_BOOTSTRAP", "level_microunit": 950_000, "replicates": 10_000, "pass_rule": "LOWER_BOUND_MEETS_THRESHOLD"},
            "adjudication": {"independent_raters": 2, "blinded": True, "disagreement_resolution": "THIRD_EXPERT", "retain_original_labels": True},
        },
        {
            "suite_id": "EVAL-PERSONA-CALIBRATION",
            "target": "12-profile probability calibration and six-family aggregation",
            "minimum_sample_size": 600,
            "unit": "SUBJECT_DISJOINT_SESSION",
            "required_slices": [{"slice_id": profile_id, "minimum_sample_size": 40} for profile_id, _, _, _ in PROFILE_ROWS],
            "metrics": [
                {"metric_id": "EXPECTED_CALIBRATION_ERROR", "threshold_operator": "<=", "threshold_microunit": 50_000},
                {"metric_id": "BRIER_SCORE", "threshold_operator": "<=", "threshold_microunit": 180_000},
                {"metric_id": "PROFILE_PROBABILITY_SUM_ERROR", "threshold_operator": "==", "threshold_microunit": 0},
            ],
            "confidence_interval": {"method": "STRATIFIED_SUBJECT_BOOTSTRAP", "level_microunit": 950_000, "replicates": 10_000, "pass_rule": "UPPER_BOUND_MEETS_THRESHOLD"},
            "adjudication": {"independent_raters": 2, "blinded": True, "disagreement_resolution": "CONSENSUS_WITH_THIRD_EXPERT", "retain_original_labels": True},
        },
        {
            "suite_id": "EVAL-RAG-CLAIM-CITATION",
            "target": "hybrid retrieval and accessible claim citation",
            "minimum_sample_size": 200,
            "unit": "LOCKED_QUERY",
            "required_slices": [{"slice_id": sid, "minimum_sample_size": 30} for sid in ["PARAGRAPH", "TABLE", "MULTI_DOCUMENT", "CURRENT_VERSION", "NO_ANSWER", "RIGHTS_SAFETY"]],
            "metrics": [
                {"metric_id": "TOP5_HIT_RATE", "threshold_operator": ">=", "threshold_microunit": 950_000},
                {"metric_id": "CRITICAL_CLAIM_CITATION_COVERAGE", "threshold_operator": ">=", "threshold_microunit": 950_000},
                {"metric_id": "INVALID_OR_INACCESSIBLE_CITATIONS", "threshold_operator": "==", "threshold_microunit": 0},
            ],
            "confidence_interval": {"method": "WILSON_SCORE", "level_microunit": 950_000, "replicates": 0, "pass_rule": "LOWER_BOUND_MEETS_THRESHOLD"},
            "adjudication": {"independent_raters": 2, "blinded": True, "disagreement_resolution": "THIRD_EXPERT", "retain_original_labels": True},
        },
        {
            "suite_id": "EVAL-HWP-LICENSED-ROUNDTRIP",
            "target": "licensed HWP open-edit-save-reopen-print structural preservation",
            "minimum_sample_size": 100,
            "unit": "LICENSED_GOLDEN_DOCUMENT",
            "required_slices": [{"slice_id": sid, "minimum_sample_size": 15} for sid in ["MERGED_TABLE", "NESTED_TABLE", "STYLE", "IMAGE_ALT", "FIELD", "MACRO_OLE_QUARANTINE"]],
            "metrics": [
                {"metric_id": "OPEN_EDIT_SAVE_REOPEN_SUCCESS", "threshold_operator": ">=", "threshold_microunit": 980_000},
                {"metric_id": "PRINT_RENDER_ACCEPTANCE", "threshold_operator": ">=", "threshold_microunit": 950_000},
                {"metric_id": "ACTIVE_CONTENT_EXECUTIONS", "threshold_operator": "==", "threshold_microunit": 0},
            ],
            "confidence_interval": {"method": "WILSON_SCORE", "level_microunit": 950_000, "replicates": 0, "pass_rule": "LOWER_BOUND_MEETS_THRESHOLD"},
            "adjudication": {"independent_raters": 2, "blinded": True, "disagreement_resolution": "DOCUMENT_ENGINEER_REVIEW", "retain_original_labels": True},
        },
        {
            "suite_id": "EVAL-AUTHZ-HIGH-PRIVILEGE",
            "target": "ABAC SoD dual approval tenant isolation and deny-before-provider",
            "minimum_sample_size": 400,
            "unit": "AUTHORIZATION_VECTOR",
            "required_slices": [{"slice_id": sid, "minimum_sample_size": 40} for sid in ["CROSS_TENANT", "SOD", "DUAL_APPROVAL", "STALE_POLICY", "REDACTION", "UNKNOWN"]],
            "metrics": [
                {"metric_id": "UNAUTHORIZED_ALLOWS", "threshold_operator": "==", "threshold_microunit": 0},
                {"metric_id": "DENIED_PROVIDER_CALLS", "threshold_operator": "==", "threshold_microunit": 0},
                {"metric_id": "AUDIT_RECEIPT_COMPLETENESS", "threshold_operator": ">=", "threshold_microunit": 1_000_000},
            ],
            "confidence_interval": {"method": "CLOPPER_PEARSON", "level_microunit": 950_000, "replicates": 0, "pass_rule": "ZERO_EVENT_UPPER_BOUND_WITHIN_APPROVED_BUDGET"},
            "adjudication": {"independent_raters": 2, "blinded": True, "disagreement_resolution": "SECURITY_OWNER", "retain_original_labels": True},
        },
        {
            "suite_id": "EVAL-PROVIDER-ROUTING",
            "target": "data-class provider routing quality latency and fail-closed behavior",
            "minimum_sample_size": 1000,
            "unit": "LOCKED_PROVIDER_REQUEST",
            "required_slices": [{"slice_id": sid, "minimum_sample_size": 100} for sid in ["PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED", "UNKNOWN"]],
            "metrics": [
                {"metric_id": "RESTRICTED_EXTERNAL_EVENTS", "threshold_operator": "==", "threshold_microunit": 0},
                {"metric_id": "UNKNOWN_CLASS_ALLOWS", "threshold_operator": "==", "threshold_microunit": 0},
                {"metric_id": "ROUTING_POLICY_CONFORMANCE", "threshold_operator": ">=", "threshold_microunit": 1_000_000},
            ],
            "confidence_interval": {"method": "CLOPPER_PEARSON", "level_microunit": 950_000, "replicates": 0, "pass_rule": "ZERO_EVENT_UPPER_BOUND_WITHIN_APPROVED_BUDGET"},
            "adjudication": {"independent_raters": 2, "blinded": True, "disagreement_resolution": "MODEL_RISK_OWNER", "retain_original_labels": True},
        },
    ]
    return {
        "schema_version": "evaluation-policy-contract.v1",
        "policy_version": "evaluation-policy.v1",
        "result_states": ["PASS", "FAIL", "INSUFFICIENT_DATA", "BLOCKED"],
        "global_decision_order": ["INVALID_EVIDENCE_TO_FAIL", "LEAKAGE_TO_FAIL", "INSUFFICIENT_DATA", "METRIC_OR_SLICE_FAIL", "PASS"],
        "holdout_policy": {
            "minimum_fraction_microunit": 200_000,
            "subject_disjoint": True,
            "dataset_hash_locked_before_evaluation": True,
            "training_or_prompt_tuning_reuse": "FORBIDDEN",
            "post_unblinding_changes_require_new_dataset_version": True,
        },
        "adjudication_policy": {
            "minimum_independent_raters": 2,
            "rater_identity_separation": True,
            "retain_original_and_adjudicated_labels": True,
            "adjudicator_cannot_be_model_tuner": True,
        },
        "confidence_interval_policy": {
            "required_for_every_metric": True,
            "minimum_level_microunit": 950_000,
            "point_estimate_only": "FORBIDDEN",
            "rounding": "INTEGER_MICROUNIT_HALF_UP",
        },
        "multiplicity_policy": {
            "family_definition": "suite_id",
            "method": "HOLM_BONFERRONI",
            "family_wise_alpha_microunit": 50_000,
            "unadjusted_significance_claim": "FORBIDDEN",
        },
        "leakage_controls": {
            "training_corpus_overlap_maximum": 0,
            "subject_overlap_maximum": 0,
            "near_duplicate_hash_overlap_maximum": 0,
            "prompt_example_overlap_maximum": 0,
            "retrieval_index_contains_holdout_labels": False,
            "leakage_scan_receipt_required": True,
            "detected_outcome": "FAIL",
        },
        "insufficient_data_policy": {
            "sample_below_minimum": "INSUFFICIENT_DATA",
            "empty_required_slice": "INSUFFICIENT_DATA",
            "slice_below_minimum": "INSUFFICIENT_DATA",
            "missing_confidence_interval": "INSUFFICIENT_DATA",
            "missing_adjudication": "INSUFFICIENT_DATA",
            "cannot_be_overridden_to_pass": True,
        },
        "suites": suites,
        "negative_vectors": [
            {"case_id": "EVAL-N-001", "condition": "one_query_only", "expected_state": "INSUFFICIENT_DATA"},
            {"case_id": "EVAL-N-002", "condition": "required_slice_empty", "expected_state": "INSUFFICIENT_DATA"},
            {"case_id": "EVAL-N-003", "condition": "training_subject_reused_in_holdout", "expected_state": "FAIL"},
            {"case_id": "EVAL-N-004", "condition": "confidence_interval_missing", "expected_state": "INSUFFICIENT_DATA"},
            {"case_id": "EVAL-N-005", "condition": "adjudication_missing", "expected_state": "INSUFFICIENT_DATA"},
            {"case_id": "EVAL-N-006", "condition": "unadjusted_multiple_comparisons", "expected_state": "FAIL"},
        ],
        "release_rule": {
            "all_suites_fresh_pass_required": True,
            "insufficient_data_is_not_pass": True,
            "nonproduction_calibration_pending_outcome": "NOT_READY",
            "acceptance_owner_signature_required": True,
        },
    }


def patch_document_graph() -> None:
    path = ROOT / "document-graph.schema.json"
    schema = json.loads(path.read_text(encoding="utf-8"))
    props = schema["properties"]
    props.update({
        "styles": {"type": "array", "uniqueItems": True, "items": {"$ref": "#/$defs/styleDefinition"}},
        "resources": {"type": "array", "uniqueItems": True, "items": {"$ref": "#/$defs/resourceDefinition"}},
        "losses": {"type": "array", "items": {"$ref": "#/$defs/lossRecord"}},
        "active_content_findings": {"type": "array", "items": {"$ref": "#/$defs/activeContentFinding"}},
    })
    defs = schema["$defs"]
    defs.update({
        "styleDefinition": {
            "type": "object", "additionalProperties": False,
            "required": ["style_id", "style_type", "canonical_properties_sha256", "source_style_name"],
            "properties": {
                "style_id": {"type": "string", "pattern": "^[a-z][a-z0-9._-]{0,63}$"},
                "style_type": {"enum": ["PARAGRAPH", "CHARACTER", "TABLE", "CELL", "BORDER", "NUMBERING"]},
                "canonical_properties_sha256": {"$ref": "#/$defs/sha256"},
                "source_style_name": {"type": "string"},
            },
        },
        "resourceDefinition": {
            "type": "object", "additionalProperties": False,
            "required": ["resource_id", "resource_type", "sha256", "media_type", "size_bytes"],
            "properties": {
                "resource_id": {"type": "string", "pattern": "^res-[a-z0-9][a-z0-9._-]{0,63}$"},
                "resource_type": {"enum": ["IMAGE", "FONT", "EMBEDDED_FILE_QUARANTINED"]},
                "sha256": {"$ref": "#/$defs/sha256"},
                "media_type": {"type": "string", "minLength": 3},
                "size_bytes": {"type": "integer", "minimum": 0},
            },
        },
        "lossRecord": {
            "type": "object", "additionalProperties": False,
            "required": ["loss_id", "category", "severity", "source_locator", "action", "review_required"],
            "properties": {
                "loss_id": {"$ref": "#/$defs/uuidV5"},
                "category": {"enum": ["STYLE_SUBSTITUTION", "BORDER_DEGRADATION", "IMAGE_ALT_MISSING", "FIELD_FLATTENED", "FONT_SUBSTITUTION", "LAYOUT_SHIFT", "MACRO_QUARANTINED", "OLE_QUARANTINED", "UNSUPPORTED_OBJECT"]},
                "severity": {"enum": ["INFO", "WARNING", "BLOCKING"]},
                "source_locator": {"$ref": "#/$defs/sourceLocator"},
                "action": {"enum": ["PRESERVED_WITH_SUBSTITUTION", "REVIEW_REQUIRED", "QUARANTINED", "REJECTED"]},
                "review_required": {"type": "boolean"},
            },
        },
        "activeContentFinding": {
            "type": "object", "additionalProperties": False,
            "required": ["finding_id", "kind", "source_sha256", "action", "executed"],
            "properties": {
                "finding_id": {"$ref": "#/$defs/uuidV5"},
                "kind": {"enum": ["MACRO", "SCRIPT", "OLE", "EXTERNAL_LINK"]},
                "source_sha256": {"$ref": "#/$defs/sha256"},
                "action": {"const": "QUARANTINED"},
                "executed": {"const": False},
            },
        },
        "imageData": {
            "type": "object", "additionalProperties": False,
            "required": ["resource_id", "alt_text", "decorative", "caption_node_id"],
            "properties": {
                "resource_id": {"type": "string", "pattern": "^res-[a-z0-9][a-z0-9._-]{0,63}$"},
                "alt_text": {"type": "string", "maxLength": 1000},
                "decorative": {"type": "boolean"},
                "caption_node_id": {"oneOf": [{"$ref": "#/$defs/uuidV5"}, {"type": "null"}]},
            },
        },
        "fieldData": {
            "type": "object", "additionalProperties": False,
            "required": ["field_type", "field_name", "display_text", "locked"],
            "properties": {
                "field_type": {"enum": ["BOOKMARK", "DATE", "PAGE_NUMBER", "MERGE_FIELD", "FORM_TEXT"]},
                "field_name": {"type": "string", "minLength": 1},
                "display_text": {"type": "string"},
                "locked": {"type": "boolean"},
            },
        },
    })
    cell = defs["cellData"]
    cell["properties"]["border_ref"] = {"oneOf": [{"type": "string", "pattern": "^[a-z][a-z0-9._-]{0,63}$"}, {"type": "null"}]}
    node_props = defs["node"]["properties"]
    node_props["image"] = {"$ref": "#/$defs/imageData"}
    node_props["field"] = {"$ref": "#/$defs/fieldData"}
    node_props["type"]["enum"] = node_props["type"]["enum"] + ["FIELD"] if "FIELD" not in node_props["type"]["enum"] else node_props["type"]["enum"]
    semantic = schema["x-semantic-contract"]
    semantic.update({
        "production_profile_required_properties": ["styles", "resources", "losses", "active_content_findings"],
        "resource_integrity": [
            "every non-null style_ref resolves to exactly one styles[].style_id",
            "every non-null CELL border_ref resolves to exactly one BORDER styles[].style_id",
            "every IMAGE image.resource_id resolves to exactly one IMAGE resources[].resource_id",
            "every non-decorative IMAGE has non-empty alt_text and every decorative IMAGE has empty alt_text",
            "every image caption_node_id resolves to a CAPTION node when non-null",
            "every FIELD has field data and FIELD data is absent on non-FIELD nodes",
        ],
        "loss_taxonomy": ["STYLE_SUBSTITUTION", "BORDER_DEGRADATION", "IMAGE_ALT_MISSING", "FIELD_FLATTENED", "FONT_SUBSTITUTION", "LAYOUT_SHIFT", "MACRO_QUARANTINED", "OLE_QUARANTINED", "UNSUPPORTED_OBJECT"],
        "active_content_policy": {
            "macro_ole_action": "QUARANTINE_AND_NEVER_EXECUTE",
            "finding_executed_must_equal": False,
            "missing_scan_receipt": "REJECT",
            "blocking_finding_release_state": "BLOCKED",
        },
    })
    write_json("document-graph.schema.json", schema)


def patch_hwp_boundary() -> None:
    path = ROOT / "hwp-conversion-boundary-contract.json"
    contract = json.loads(path.read_text(encoding="utf-8"))
    contract["licensed_roundtrip_acceptance"] = {
        "release_state": "NOT_READY",
        "environment": "LICENSED_WINDOWS_CONVERTER_ISOLATED_NODE",
        "minimum_golden_documents": 100,
        "required_actions": ["OPEN", "EDIT", "SAVE_AS_HWPX", "REOPEN", "PRINT_TO_PDF"],
        "edit_script": ["REPLACE_TEXT_IN_PARAGRAPH", "EDIT_MERGED_CELL", "UPDATE_FIELD_VALUE", "REPLACE_IMAGE_ALT_TEXT"],
        "required_slices": ["MERGED_TABLE", "NESTED_TABLE", "STYLE", "BORDER", "IMAGE_ALT", "FIELD", "MACRO", "OLE"],
        "acceptance_metrics": [
            {"metric_id": "OPEN_EDIT_SAVE_REOPEN_SUCCESS", "operator": ">=", "threshold_microunit": 980_000},
            {"metric_id": "PRINT_RENDER_ACCEPTANCE", "operator": ">=", "threshold_microunit": 950_000},
            {"metric_id": "TABLE_TOPOLOGY_PRESERVATION", "operator": ">=", "threshold_microunit": 950_000},
            {"metric_id": "STYLE_BORDER_FIELD_RESOURCE_DANGLING_REFERENCES", "operator": "==", "threshold_microunit": 0},
            {"metric_id": "MACRO_OLE_EXECUTIONS", "operator": "==", "threshold_microunit": 0},
        ],
        "required_evidence": ["LICENSE_RECEIPT_SHA256", "CONVERTER_BINARY_SHA256", "SANDBOX_ATTESTATION_SHA256", "OPEN_EDIT_SAVE_TRACE_SHA256", "PRINT_PDF_SHA256", "STRUCTURE_DIFF_SHA256", "VISUAL_DIFF_SHA256", "ACTIVE_CONTENT_SCAN_SHA256"],
        "simulator_or_hwpx_only_result": "BLOCKED",
    }
    contract["active_content_roundtrip_policy"] = {
        "macro": "QUARANTINE_NEVER_EXECUTE_NEVER_REEMBED",
        "ole": "QUARANTINE_NEVER_ACTIVATE_STATIC_NONINTERACTIVE_RENDER_ONLY",
        "external_link": "REMOVE_OR_APPROVED_STATIC_TEXT_ONLY",
        "scan_receipt_required_before_child_execution": True,
        "detected_execution": "QUARANTINE_HOST_AND_FAIL_RELEASE",
    }
    write_json("hwp-conversion-boundary-contract.json", contract)


def patch_provider_registry() -> None:
    path = ROOT / "provider-decision-registry.json"
    registry = json.loads(path.read_text(encoding="utf-8"))
    existing = {item["decision_id"]: item for item in registry["decisions"]}
    additions = [
        ("DEC-OBJECT-STORAGE-007", "Tenant-bound object storage and immutable retention", ["OWN-OPS", "OWN-SEC"], "D+20", ["IN-STORAGE-DPA", "IN-STORAGE-REGION", "IN-STORAGE-LOCK-EVAL"], ["GATE-SECURITY-PRIVACY", "GATE-OPERATIONS-RECOVERY"]),
        ("DEC-EMAIL-008", "Transactional email provider and suppression handling", ["OWN-OPS", "OWN-PRIV"], "D+20", ["IN-EMAIL-DPA", "IN-EMAIL-REGION", "IN-EMAIL-DELIVERABILITY"], ["GATE-SECURITY-PRIVACY"]),
        ("DEC-OIDC-009", "OIDC identity provider MFA and lifecycle", ["OWN-SEC", "OWN-OPS"], "D+20", ["IN-OIDC-DPA", "IN-OIDC-REGION", "IN-OIDC-AAL2"], ["GATE-SECURITY-PRIVACY"]),
        ("DEC-BROKER-010", "Durable job and event broker", ["OWN-OPS", "OWN-ARCH"], "D+25", ["IN-BROKER-DPA", "IN-BROKER-REGION", "IN-BROKER-DR"], ["GATE-OPERATIONS-RECOVERY"]),
        ("DEC-MALWARE-011", "Malware scanning and archive bomb analysis service", ["OWN-SEC", "OWN-DOC"], "D+20", ["IN-MALWARE-DPA", "IN-MALWARE-REGION", "IN-MALWARE-EVASION-CORPUS"], ["GATE-SECURITY-PRIVACY", "GATE-DOCUMENT-KPI"]),
        ("DEC-HOSTING-DNS-TLS-WAF-012", "Hosting, DNS, TLS certificate automation and WAF", ["OWN-OPS", "OWN-SEC"], "D+20", ["IN-HOSTING-DPA", "IN-HOSTING-REGION", "IN-DNS-TLS-WAF-DRILL"], ["GATE-OPERATIONS-RECOVERY", "GATE-SECURITY-PRIVACY"]),
        ("DEC-MANAGED-DB-013", "Managed PostgreSQL high availability and point-in-time recovery", ["OWN-DATA", "OWN-OPS"], "D+25", ["IN-DB-DPA", "IN-DB-REGION", "IN-DB-PITR-DRILL"], ["GATE-OPERATIONS-RECOVERY"]),
        ("DEC-REDIS-014", "Redis-compatible cache, rate-limit and ephemeral state", ["OWN-ARCH", "OWN-OPS"], "D+25", ["IN-REDIS-DPA", "IN-REDIS-REGION", "IN-REDIS-FAILOVER"], ["GATE-OPERATIONS-RECOVERY"]),
        ("DEC-OFFHOST-BACKUP-015", "Encrypted off-host backup vault and retention", ["OWN-DATA", "OWN-SEC", "OWN-OPS"], "D+25", ["IN-BACKUP-DPA", "IN-BACKUP-REGION", "IN-BACKUP-RESTORE-DRILL"], ["GATE-OPERATIONS-RECOVERY", "GATE-SECURITY-PRIVACY"]),
        ("DEC-CICD-016", "CI/CD platform, artifact signing and protected release environment", ["OWN-DEV", "OWN-SEC", "OWN-OPS"], "D+20", ["IN-CICD-DPA", "IN-CICD-REGION", "IN-CICD-SUPPLY-CHAIN"], ["GATE-SECURITY-PRIVACY", "GATE-OPERATIONS-RECOVERY"]),
    ]
    for decision_id, subject, owners, due, inputs, gates in additions:
        existing[decision_id] = {
            "decision_id": decision_id,
            "subject": subject,
            "status": "REQUIRES_ACCEPTANCE_DATA",
            "owner_ids": owners,
            "due_at": due,
            "required_input_ids": inputs,
            "gate_ids": gates,
        }
    ordered_ids = [f"DEC-{name}-{number:03d}" for name, number in []]  # documents intent; explicit order follows below
    del ordered_ids
    decisions = list(registry["decisions"])
    known = {item["decision_id"] for item in decisions}
    decisions.extend(existing[key] for key, *_ in additions if key not in known)
    for item in decisions:
        item["data_processing_agreement"] = "REQUIRED" if item["decision_id"] != "DEC-HARDWARE-005" else "CONDITIONAL_ON_HOSTING_MODEL"
        item["approved_regions"] = []
        item["region_decision_state"] = "REQUIRES_ACCEPTANCE_DATA"
        item["exit_plan_id"] = f"EXIT-{item['decision_id'][4:]}"
        item["evidence_freshness_days"] = 90
        item["release_state"] = "NOT_READY"
    registry["overall_release_state"] = "NOT_READY"
    registry["decision_required_fields"] = ["decision_id", "subject", "status", "owner_ids", "due_at", "required_input_ids", "gate_ids", "data_processing_agreement", "approved_regions", "region_decision_state", "exit_plan_id", "evidence_freshness_days", "release_state"]
    registry["decisions"] = decisions
    registry["activation_rule"] = "Every decision row must have approved DPA applicability, non-empty approved_regions where data is processed, a tested exit plan, fresh PASS gates and release_state READY; until then the overall state is NOT_READY. Model binaries and service credentials are never downloaded automatically by the implementation launcher."
    write_json("provider-decision-registry.json", registry)


def main() -> int:
    write_json("rubric-question-contract.json", rubric_question_contract())
    write_json("persona-inference-policy.json", persona_contract())
    write_json("operation-authorization-contracts.json", operation_authorization_contract())
    write_json("evaluation-policy-contract.json", evaluation_contract())
    patch_document_graph()
    patch_hwp_boundary()
    patch_provider_registry()
    print("Generated semantic-depth contracts: rubric, persona, authorization, evaluation, DocumentGraph, HWP, provider")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
