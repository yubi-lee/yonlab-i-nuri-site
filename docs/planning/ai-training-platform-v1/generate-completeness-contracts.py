#!/usr/bin/env python3
"""Generate the implementation-completeness contracts from the frozen screen registry.

The generator never modifies the existing normative registries.  It adds closed,
implementation-facing contracts whose exact operation and screen sets are checked
against those registries by verify-completeness-contracts.py.
"""

from __future__ import annotations

import hashlib
import json
import re
from copy import deepcopy
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent


def dump(name: str, value: Any) -> None:
    (ROOT / name).write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def schema_name(operation_id: str, suffix: str) -> str:
    words = re.findall(r"[A-Za-z0-9]+", operation_id.replace("{", "").replace("}", ""))
    return "".join(word[:1].upper() + word[1:] for word in words) + suffix


UUID = {"type": "string", "format": "uuid"}
DATE_TIME = {"type": "string", "format": "date-time"}


def scalar_schema(name: str) -> dict[str, Any]:
    lower = name.lower()
    if lower.endswith("_ids") or lower.endswith("_step_ids"):
        return {"type": "array", "minItems": 1, "uniqueItems": True, "items": UUID}
    if lower.endswith("_id") or lower in {"command_id", "challenge_id", "upload_id"}:
        return UUID
    if lower.endswith("_at") or lower.endswith("_start") or lower.endswith("_end"):
        return DATE_TIME
    if lower.endswith("_microunit"):
        return {"type": "integer", "minimum": 0, "maximum": 1_000_000}
    if lower.endswith("_count") or lower.endswith("_version") or lower.endswith("_sequence") or lower.endswith("_minutes") or lower.endswith("_seconds") or lower in {"page_size", "size_bytes", "expected_version", "topological_rank"}:
        return {"type": "integer", "minimum": 0}
    if lower.startswith(("is_", "has_")) or lower.endswith(("_required", "_allowed", "_enabled")) or lower in {"enabled", "accepted", "withdrawn", "mfa_required", "verification_required"}:
        return {"type": "boolean"}
    if lower in {"filters", "metadata", "rights", "fields", "changes", "constraints"}:
        # Keep generic extension bags closed and auditable: clients transmit an
        # ordered list of explicit key/value entries, never arbitrary JSON keys.
        return {
            "type": "object",
            "additionalProperties": False,
            "required": ["schema_version", "values"],
            "properties": {
                "schema_version": {"type": "string", "minLength": 1, "maxLength": 64},
                "values": {
                    "type": "array",
                    "maxItems": 100,
                    "items": {
                        "type": "object",
                        "additionalProperties": False,
                        "required": ["key", "value"],
                        "properties": {
                            "key": {"type": "string", "minLength": 1, "maxLength": 128},
                            "value": {"type": ["string", "number", "integer", "boolean", "null"]},
                        },
                    },
                },
            },
        }
    if lower in {"indicator_ids", "evidence_ids", "recommendation_ids", "attachment_ids", "roles", "interest_keywords", "competency_codes", "feature_codes", "removed_field_codes"}:
        return {"type": "array", "minItems": 1, "uniqueItems": True, "items": {"type": "string", "minLength": 1}}
    if lower in {"content", "reflection", "reason", "query", "summary"}:
        return {"type": "string", "minLength": 1, "maxLength": 20000}
    if "password" in lower:
        return {"type": "string", "minLength": 12, "maxLength": 256, "format": "password"}
    if lower == "email":
        return {"type": "string", "format": "email", "maxLength": 320}
    if lower == "sha256" or lower.endswith("_sha256") or lower.endswith("_hash"):
        return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    if lower.endswith("_status"):
        return {"type": "string", "enum": ["PENDING", "ACTIVE", "COMPLETED", "FAILED"]}
    if lower in {"access_token", "refresh_token"}:
        return {"type": "string", "minLength": 32, "maxLength": 4096}
    if lower in {"sections", "featured_content", "recent_activity", "recommended_actions"}:
        return {"type": "array", "items": {"type": "string", "minLength": 1, "maxLength": 2000}}
    return {"type": "string", "minLength": 1, "maxLength": 512}


def closed_object(properties: dict[str, Any], required: list[str] | None = None) -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": required if required is not None else list(properties),
        "properties": properties,
    }


IRREGULAR_SINGULAR = {
    "diagnoses": "diagnosis", "indices": "index", "indexes": "index",
    "policies": "policy", "activities": "activity", "categories": "category",
    "queries": "query", "personas": "persona", "schemas": "schema",
    "roles": "role", "consents": "consent", "notifications": "notification",
}


def singular(token: str) -> str:
    if token in IRREGULAR_SINGULAR:
        return IRREGULAR_SINGULAR[token]
    if token.endswith("ies"):
        return token[:-3] + "y"
    if token.endswith("sses"):
        return token[:-2]
    if token.endswith("s") and not token.endswith("ss"):
        return token[:-1]
    return token


def operation_subject(path: str) -> str:
    if path == "/api/v1/me":
        return "teacher_profile"
    tokens = [token for token in path.strip("/").split("/") if token not in {"api", "v1", "admin", "me"} and not token.startswith("{")]
    normalized = [singular(token.replace("-", "_")) for token in tokens]
    subject = "_".join(normalized)
    if not subject:
        raise ValueError(f"cannot derive semantic subject for {path}")
    return subject


def operation_domain(screen_id: str, path: str) -> str:
    if path.startswith(("/api/v1/portal/", "/api/v1/public/")):
        return "PUBLIC_PORTAL"
    if any(token in path for token in ("/auth/", "/me", "/tenants/", "/users", "/organizations", "/memberships", "/roles", "/consents", "/inquiries")):
        return "IDENTITY"
    if any(token in path for token in ("/diagnoses", "/evidence/", "/frameworks", "/rubrics", "/personas")):
        return "DIAGNOSIS"
    if "recommendation" in path:
        return "RECOMMENDATION"
    if any(token in path for token in ("/learning-paths", "/steps/", "/practice-submissions")):
        return "LEARNING"
    if any(token in path for token in ("/reports", "/analytics/")):
        return "REPORTING"
    if any(token in path for token in ("/documents", "/document-", "/files/", "/search", "/rag/", "/citations/")):
        return "DOCUMENT"
    if any(token in path for token in ("/drafts", "/draft-templates")):
        return "DRAFT"
    if path == "/health/ready" or any(token in path for token in ("/jobs", "/indexes", "/storage", "/backups", "/integrations")):
        return "OPERATIONS"
    if screen_id.startswith("ADM-"):
        return "ADMINISTRATION"
    raise ValueError(f"unclassified operation domain: {screen_id} {path}")


DETAIL_GET_PATHS = {
    "/api/v1/portal/home", "/api/v1/me/dashboard", "/api/v1/me",
    "/api/v1/admin/metrics-summary", "/api/v1/admin/ai-costs",
    "/api/v1/admin/ai-fallbacks", "/api/v1/admin/storage",
    "/api/v1/admin/integrations", "/health/ready",
}


def operation_kind(method: str, path: str) -> str:
    if method == "GET":
        if path == "/health/ready":
            return "HEALTH"
        if "{" in path or path in DETAIL_GET_PATHS:
            return "READ_DETAIL"
        return "READ_COLLECTION"
    if method == "PATCH":
        return "UPDATE"
    if any(path.endswith(suffix) for suffix in (
        "/verify", "/activate", "/pause", "/resume", "/rescore", "/feedback",
        "/start", "/complete", "/review", "/export", "/reprocess",
        "/review-decisions", "/publish", "/withdraw", "/rollback", "/retry", "/rotate",
        "/download-authorizations",
    )):
        return "ACTION"
    return "CREATE"


def enum(*values: str) -> dict[str, Any]:
    return {"type": "string", "enum": list(values)}


def strings(*, minimum: int = 0) -> dict[str, Any]:
    return {"type": "array", "minItems": minimum, "uniqueItems": True, "items": {"type": "string", "minLength": 1, "maxLength": 512}}


def uuids(*, minimum: int = 0) -> dict[str, Any]:
    return {"type": "array", "minItems": minimum, "uniqueItems": True, "items": UUID}


def records(properties: dict[str, Any], *, minimum: int = 0) -> dict[str, Any]:
    return {"type": "array", "minItems": minimum, "items": closed_object(properties)}


def catalog_records(noun: str, extras: dict[str, Any] | None = None) -> dict[str, Any]:
    properties = {
        f"{noun}_id": UUID,
        "display_name": {"type": "string", "minLength": 1, "maxLength": 500},
        "lifecycle_state": enum("DRAFT", "ACTIVE", "RETIRED"),
        "revision": {"type": "integer", "minimum": 1},
        "effective_at": DATE_TIME,
    }
    properties.update(extras or {})
    return records(properties)


def operation_receipt(noun: str, *, states: tuple[str, ...] = ("ACCEPTED", "COMPLETED"), extras: dict[str, Any] | None = None) -> dict[str, Any]:
    properties = {
        f"{noun}_id": UUID,
        f"{noun}_state": enum(*states),
        "revision": {"type": "integer", "minimum": 1},
        "accepted_at": DATE_TIME,
    }
    properties.update(extras or {})
    return properties


PAGE = closed_object(
    {
        "next_cursor": {"type": ["string", "null"], "maxLength": 512},
        "has_more": {"type": "boolean"},
        "returned_count": {"type": "integer", "minimum": 0, "maximum": 100},
    }
)
COMPETENCY_SCORE_RECORDS = records(
    {
        "competency_code": {"type": "string", "minLength": 1},
        "score_microunit": scalar_schema("score_microunit"),
        "confidence_microunit": scalar_schema("confidence_microunit"),
        "conflict_decision": enum("NONE", "REVIEW_REQUIRED", "INSUFFICIENT_EVIDENCE"),
        "evidence_coverage_microunit": scalar_schema("evidence_coverage_microunit"),
        "level_code": {"type": "string", "minLength": 1},
    }
)
LEARNING_STEP_RECORDS = records(
    {
        "step_id": UUID,
        "dag_node_key": {"type": "string", "minLength": 1},
        "predecessor_step_ids": uuids(),
        "content_item_id": UUID,
        "step_state": enum("LOCKED", "AVAILABLE", "IN_PROGRESS", "COMPLETED"),
        "progress_microunit": scalar_schema("progress_microunit"),
        "topological_rank": {"type": "integer", "minimum": 0},
    }
)
CITATION_RECORDS = records(
    {
        "citation_id": UUID,
        "claim_id": UUID,
        "evidence_id": UUID,
        "document_version_id": UUID,
        "source_locator": {"type": "string", "minLength": 1},
        "quoted_span": {"type": "string", "minLength": 1, "maxLength": 4000},
        "entailment_microunit": scalar_schema("entailment_microunit"),
        "rights_current": {"type": "boolean"},
    }
)


# Every public HTTP operation is statically bound below.  Shared schemas reduce
# repetition, but no path/subject inference and no default response exists.
RESPONSE_BLUEPRINTS: dict[str, dict[str, Any]] = {
    "portal.home": {"featured_content": catalog_records("content", {"content_type": {"type": "string"}}), "announcement_count": {"type": "integer", "minimum": 0}, "recommended_search_terms": strings()},
    "public.catalog": {"catalog_items": catalog_records("content", {"content_type": {"type": "string"}, "competency_codes": strings(), "accessibility_features": strings(), "region_availability_codes": strings()}), "facet_dimensions": strings(), "total_item_count": {"type": "integer", "minimum": 0}},
    "public.search": {"query_echo": {"type": "string"}, "search_hits": records({"content_id": UUID, "title": {"type": "string"}, "snippet": {"type": "string"}, "content_type": {"type": "string"}, "published_at": DATE_TIME}), "facets": records({"facet_code": {"type": "string"}, "values": records({"value_code": {"type": "string"}, "match_count": {"type": "integer", "minimum": 0}})}), "total_match_count": {"type": "integer", "minimum": 0}},
    "public.resource": {"public_resource_id": UUID, "title": {"type": "string"}, "summary": {"type": "string"}, "content_type": {"type": "string"}, "competency_codes": strings(), "accessibility_features": strings(), "region_availability_codes": strings(), "rights_code": {"type": "string"}, "published_at": DATE_TIME},
    "file.download.authorization": {"download_authorization_id": UUID, "file_id": UUID, "capability_token": {"type": "string", "minLength": 32}, "rights_decision": enum("ALLOW", "DENY"), "expires_at": DATE_TIME},
    "auth.register": {"user_id": UUID, "account_state": enum("PENDING_VERIFICATION", "ACTIVE"), "verification_required": {"type": "boolean"}},
    "auth.login": {"access_token": scalar_schema("access_token"), "expires_in_seconds": scalar_schema("expires_in_seconds"), "refresh_session_id": UUID, "session_family_id": UUID, "mfa_required": {"type": "boolean"}},
    "auth.refresh": {"access_token": scalar_schema("access_token"), "expires_in_seconds": scalar_schema("expires_in_seconds"), "rotated_refresh_session_id": UUID, "session_family_id": UUID},
    "auth.logout": {"revoked_refresh_session_id": UUID, "logged_out_at": DATE_TIME},
    "auth.logout-all": {"revoked_session_count": {"type": "integer", "minimum": 0}, "security_event_id": UUID, "logged_out_at": DATE_TIME},
    "auth.password-reset-confirm": {"password_changed_at": DATE_TIME, "revoked_session_count": {"type": "integer", "minimum": 0}, "security_event_id": UUID},
    "auth.password-reset": {"password_reset_request_id": UUID, "delivery_state": enum("QUEUED", "SUPPRESSED"), "expires_at": DATE_TIME},
    "auth.mfa-challenge": {"challenge_id": UUID, "challenge_state": enum("ISSUED", "VERIFIED", "EXPIRED"), "factor_options": strings(minimum=1), "expires_at": DATE_TIME},
    "auth.mfa-verify": {"challenge_id": UUID, "verification_decision": enum("ALLOW", "DENY"), "authentication_context": strings(minimum=1), "verified_at": DATE_TIME},
    "auth.mfa-recovery": {"recovery_attempt_id": UUID, "recovery_decision": enum("ALLOW", "DENY"), "remaining_recovery_code_count": {"type": "integer", "minimum": 0}, "verified_at": DATE_TIME},
    "auth.mfa-enrollment": {"enrollment_id": UUID, "factor_type": enum("TOTP", "WEBAUTHN"), "provisioning_uri": {"type": "string", "format": "uri"}, "enrollment_state": enum("PENDING_VERIFICATION", "ACTIVE"), "expires_at": DATE_TIME},
    "auth.mfa-enrollment-verify": {"enrollment_id": UUID, "factor_state": enum("ACTIVE", "REJECTED"), "recovery_codes_issued": {"type": "boolean"}, "verified_at": DATE_TIME},
    "auth.mfa-recovery-rotate": {"recovery_codes": strings(minimum=1), "issued_at": DATE_TIME, "previous_codes_revoked_at": DATE_TIME},
    "member.dashboard": {"next_action_codes": strings(), "active_learning_path_count": {"type": "integer", "minimum": 0}, "unread_notification_count": {"type": "integer", "minimum": 0}, "latest_diagnosis_id": {"oneOf": [UUID, {"type": "null"}]}},
    "member.profile": {"user_id": UUID, "display_name": {"type": "string"}, "career_band": {"type": "string"}, "region_category": {"type": "string"}, "interest_keywords": strings(), "profile_revision": {"type": "integer", "minimum": 1}},
    "member.profile-updated": {"user_id": UUID, "profile_revision": {"type": "integer", "minimum": 1}, "changed_field_codes": strings(minimum=1), "updated_at": DATE_TIME},
    "member.consents": {"consent_records": records({"consent_id": UUID, "purpose_code": {"type": "string"}, "decision": enum("GRANTED", "DENIED", "WITHDRAWN"), "policy_version": {"type": "string"}, "decided_at": DATE_TIME})},
    "member.consent-recorded": {"consent_id": UUID, "purpose_code": {"type": "string"}, "decision": enum("GRANTED", "DENIED", "WITHDRAWN"), "policy_version": {"type": "string"}, "effective_at": DATE_TIME},
    "tenant.activated": {"tenant_id": UUID, "membership_id": UUID, "tenant_context_revision": {"type": "integer", "minimum": 1}, "allowed_role_codes": strings(minimum=1), "activated_at": DATE_TIME},
    "diagnosis.created": {"diagnosis_id": UUID, "diagnosis_state": enum("CREATED", "IN_PROGRESS"), "rubric_version": {"type": "string"}, "scoring_policy_digest": scalar_schema("scoring_policy_digest"), "next_question_available": {"type": "boolean"}},
    "diagnosis.session": {"diagnosis_id": UUID, "diagnosis_state": enum("CREATED", "IN_PROGRESS", "PAUSED", "COMPLETED"), "current_question": closed_object({"question_id": UUID, "prompt_text": {"type": "string"}, "indicator_codes": strings(minimum=1)}), "turn_count": {"type": "integer", "minimum": 0}, "evidence_progress_microunit": scalar_schema("evidence_progress_microunit"), "scoring_policy_digest": scalar_schema("scoring_policy_digest")},
    "diagnosis.turn": {"dialogue_turn_id": UUID, "accepted_turn_sequence": {"type": "integer", "minimum": 0}, "next_question": closed_object({"question_id": UUID, "prompt_text": {"type": "string"}, "indicator_codes": strings(minimum=1), "selection_reason_codes": strings(minimum=1)}), "evidence_progress_microunit": scalar_schema("evidence_progress_microunit"), "scoring_policy_digest": scalar_schema("scoring_policy_digest"), "diagnosis_state": enum("IN_PROGRESS", "COMPLETED")},
    "diagnosis.state-change": {"diagnosis_id": UUID, "diagnosis_state": enum("IN_PROGRESS", "PAUSED", "COMPLETED"), "state_reason_code": {"type": "string"}, "state_changed_at": DATE_TIME},
    "diagnosis.result": {"diagnosis_result_id": UUID, "result_version": {"type": "integer", "minimum": 1}, "competency_scores": COMPETENCY_SCORE_RECORDS, "overall_confidence_microunit": scalar_schema("overall_confidence_microunit"), "evidence_coverage_microunit": scalar_schema("evidence_coverage_microunit"), "conflict_count": {"type": "integer", "minimum": 0}, "decision": enum("FINAL", "REVIEW_REQUIRED", "INSUFFICIENT_EVIDENCE")},
    "diagnosis.evidence": {"evidence_spans": records({"evidence_id": UUID, "dialogue_turn_id": UUID, "turn_sequence": {"type": "integer", "minimum": 0}, "indicator_code": {"type": "string"}, "quoted_span": {"type": "string"}, "entailment_microunit": scalar_schema("entailment_microunit"), "relevance_microunit": scalar_schema("relevance_microunit"), "evidence_strength_microunit": scalar_schema("evidence_strength_microunit"), "eligibility_decision": enum("ELIGIBLE", "REJECTED", "REVIEW_REQUIRED")}), "scoring_policy_digest": scalar_schema("scoring_policy_digest")},
    "diagnosis.evidence-reviewed": {"evidence_id": UUID, "review_decision": enum("ACCEPTED", "CORRECTED", "REJECTED"), "row_version": {"type": "integer", "minimum": 1}, "reviewed_at": DATE_TIME},
    "diagnosis.rescored": {"diagnosis_result_id": UUID, "result_version": {"type": "integer", "minimum": 1}, "competency_scores": COMPETENCY_SCORE_RECORDS, "overall_confidence_microunit": scalar_schema("overall_confidence_microunit"), "conflict_count": {"type": "integer", "minimum": 0}, "decision": enum("FINAL", "REVIEW_REQUIRED", "INSUFFICIENT_EVIDENCE")},
    "diagnosis.personas": {"persona_assessments": records({"persona_id": UUID, "persona_version": {"type": "string"}, "likelihood_microunit": scalar_schema("likelihood_microunit"), "feature_contributions": records({"feature_code": {"type": "string"}, "coefficient_microunit": scalar_schema("coefficient_microunit")}), "explanation": {"type": "string"}}), "inference_policy_digest": scalar_schema("inference_policy_digest")},
    "diagnosis.persona-context": {"diagnosis_id": UUID, "persona_context_revision": {"type": "integer", "minimum": 1}, "accepted_persona_ids": uuids(), "overridden_factor_codes": strings(), "updated_at": DATE_TIME},
    "recommendation.list": {"recommendations": records({"recommendation_id": UUID, "content_item_id": UUID, "score_microunit": scalar_schema("score_microunit"), "reason_codes": strings(minimum=1), "explanation": {"type": "string"}, "hard_filter_decision": enum("ALLOW", "DENY"), "hard_filter_reason_codes": strings(), "source_result_version": {"type": "integer", "minimum": 1}}), "policy_version": {"type": "string"}},
    "recommendation.feedback": {"recommendation_feedback_id": UUID, "recommendation_id": UUID, "feedback_decision": enum("ACCEPTED", "REJECTED", "DEFERRED"), "policy_learning_eligible": {"type": "boolean"}, "recorded_at": DATE_TIME},
    "learning.path": {"learning_path_id": UUID, "learning_path_state": enum("DRAFT", "ACTIVE", "COMPLETED"), "steps": LEARNING_STEP_RECORDS, "dependency_edges": records({"predecessor_step_id": UUID, "successor_step_id": UUID, "edge_type": enum("REQUIRED", "OPTIONAL")}), "constraint_codes": strings(), "overall_progress_microunit": scalar_schema("overall_progress_microunit")},
    "learning.path-updated": {"learning_path_id": UUID, "path_revision": {"type": "integer", "minimum": 1}, "steps": LEARNING_STEP_RECORDS, "dependency_validation_decision": enum("ACYCLIC", "REJECTED_CYCLE"), "updated_at": DATE_TIME},
    "learning.step-state": {"step_id": UUID, "learning_path_id": UUID, "step_state": enum("IN_PROGRESS", "COMPLETED"), "overall_progress_microunit": scalar_schema("overall_progress_microunit"), "recorded_at": DATE_TIME},
    "learning.practice-submission": {"practice_submission_id": UUID, "step_id": UUID, "review_state": enum("QUEUED", "REVIEWED"), "artifact_ids": uuids(), "submitted_at": DATE_TIME},
    "report.queued": {"report_id": UUID, "report_job_id": UUID, "report_state": enum("QUEUED", "GENERATING"), "snapshot_cutoff_at": DATE_TIME},
    "report.detail": {"report_id": UUID, "report_state": enum("GENERATING", "READY", "FAILED"), "period_start": DATE_TIME, "period_end": DATE_TIME, "competency_metrics": COMPETENCY_SCORE_RECORDS, "learning_outcome_metrics": records({"metric_code": {"type": "string"}, "value_microunit": scalar_schema("value_microunit"), "sample_count": {"type": "integer", "minimum": 0}}), "artifact_available": {"type": "boolean"}},
    "report.artifact": {"report_id": UUID, "artifact_id": UUID, "artifact_format": enum("PDF", "CSV", "JSON"), "content_sha256": scalar_schema("content_sha256"), "download_authorization_required": {"type": "boolean"}, "generated_at": DATE_TIME},
    "document.search": {"query_id": UUID, "search_hits": records({"chunk_id": UUID, "document_version_id": UUID, "document_title": {"type": "string"}, "source_locator": {"type": "string"}, "snippet": {"type": "string"}, "retrieval_score_microunit": scalar_schema("retrieval_score_microunit"), "rights_current": {"type": "boolean"}}), "facets": records({"facet_code": {"type": "string"}, "value_codes": strings()}), "retrieval_policy_version": {"type": "string"}},
    "rag.session-created": {"rag_session_id": UUID, "session_state": enum("ACTIVE", "BLOCKED"), "retrieval_policy_version": {"type": "string"}, "message_stream_url": {"type": "string", "format": "uri-reference"}},
    "rag.message": {"message_id": UUID, "rag_session_id": UUID, "message_state": enum("STREAMING", "COMPLETED", "BLOCKED"), "answer_text": {"type": "string"}, "claims": records({"claim_id": UUID, "claim_text": {"type": "string"}, "importance": enum("IMPORTANT", "SUPPORTING"), "grounding_decision": enum("GROUNDED", "UNGROUNDED")}), "citations": CITATION_RECORDS, "claim_evidence_bindings": records({"claim_id": UUID, "citation_id": UUID, "evidence_id": UUID, "relation": enum("SUPPORTS", "CONTRADICTS"), "entailment_microunit": scalar_schema("entailment_microunit")}), "important_claim_coverage_microunit": scalar_schema("important_claim_coverage_microunit"), "invalid_citation_count": {"type": "integer", "minimum": 0}},
    "citation.detail": {"citation_id": UUID, "claim_id": UUID, "evidence_id": UUID, "document_version_id": UUID, "source_locator": {"type": "string"}, "quoted_span": {"type": "string"}, "entailment_microunit": scalar_schema("entailment_microunit"), "rights_current": {"type": "boolean"}, "rights_snapshot_hash": scalar_schema("rights_snapshot_hash")},
    "draft.templates": {"draft_templates": catalog_records("draft_template", {"template_field_codes": strings(minimum=1), "export_format_codes": strings(minimum=1)})},
    "draft.detail": {"draft_id": UUID, "draft_state": enum("DRAFT", "IN_REVIEW", "APPROVED", "EXPORTED"), "template_version_id": UUID, "field_values": records({"field_code": {"type": "string"}, "value": {"type": "string"}, "evidence_ids": uuids()}), "review_decision": enum("PENDING", "APPROVED", "CHANGES_REQUESTED"), "draft_revision": {"type": "integer", "minimum": 1}},
    "draft.updated": {"draft_id": UUID, "draft_revision": {"type": "integer", "minimum": 1}, "changed_field_codes": strings(minimum=1), "evidence_binding_count": {"type": "integer", "minimum": 0}, "updated_at": DATE_TIME},
    "draft.reviewed": {"draft_id": UUID, "review_decision_id": UUID, "review_decision": enum("APPROVED", "CHANGES_REQUESTED", "REJECTED"), "reviewed_field_codes": strings(), "reviewed_at": DATE_TIME},
    "draft.export": {"draft_export_id": UUID, "draft_id": UUID, "export_state": enum("QUEUED", "READY", "FAILED"), "export_format": enum("HWPX", "PDF", "DOCX"), "artifact_id": {"oneOf": [UUID, {"type": "null"}]}, "structure_validation_decision": enum("PENDING", "VALID", "INVALID")},
    "member.activity": {"activity_records": records({"activity_id": UUID, "activity_type": {"type": "string"}, "occurred_at": DATE_TIME, "object_type": {"type": "string"}, "object_id": UUID})},
    "member.notifications": {"notifications": records({"notification_id": UUID, "notification_type": {"type": "string"}, "title": {"type": "string"}, "read_at": {"oneOf": [DATE_TIME, {"type": "null"}]}, "created_at": DATE_TIME})},
    "member.export-request": {"export_request_id": UUID, "export_state": enum("QUEUED", "READY", "EXPIRED"), "scope_codes": strings(minimum=1), "requested_at": DATE_TIME},
    "member.deletion-request": {"deletion_request_id": UUID, "deletion_state": enum("QUEUED", "REVIEW_REQUIRED", "SCHEDULED"), "retention_exception_codes": strings(), "requested_at": DATE_TIME},
    "inquiry.created": {"inquiry_id": UUID, "inquiry_state": enum("OPEN", "TRIAGED"), "service_level_due_at": DATE_TIME, "created_at": DATE_TIME},
    "admin.metrics": {"period_start": DATE_TIME, "period_end": DATE_TIME, "aggregate_counts": records({"metric_code": {"type": "string"}, "count": {"type": "integer", "minimum": 0}, "suppressed": {"type": "boolean"}}), "latency_metrics": records({"operation_code": {"type": "string"}, "p50_milliseconds": {"type": "integer", "minimum": 0}, "p95_milliseconds": {"type": "integer", "minimum": 0}, "sample_count": {"type": "integer", "minimum": 0}}), "cost_metrics": records({"provider_code": {"type": "string"}, "cost_microunit": scalar_schema("cost_microunit"), "token_count": {"type": "integer", "minimum": 0}}), "suppression_policy_version": {"type": "string"}},
    "admin.frameworks": {"frameworks": catalog_records("framework", {"dimension_codes": strings(minimum=1)})},
    "admin.framework-written": operation_receipt("framework", extras={"semantic_version": {"type": "string"}, "dimension_codes": strings(minimum=1)}),
    "admin.rubrics": {"rubrics": catalog_records("rubric", {"framework_id": UUID, "indicator_count": {"type": "integer", "minimum": 1}, "question_count": {"type": "integer", "minimum": 1}, "artifact_digest": scalar_schema("artifact_digest")})},
    "admin.rubric-written": operation_receipt("rubric", extras={"framework_id": UUID, "artifact_digest": scalar_schema("artifact_digest")}),
    "admin.personas": {"personas": catalog_records("persona", {"feature_coefficient_count": {"type": "integer", "minimum": 1}, "artifact_digest": scalar_schema("artifact_digest")})},
    "admin.persona-activated": operation_receipt("persona", states=("ACTIVE",), extras={"artifact_digest": scalar_schema("artifact_digest")}),
    "admin.catalog": {"catalog_items": catalog_records("content_item", {"content_type": {"type": "string"}, "prerequisite_codes": strings(), "accessibility_features": strings(), "region_availability_codes": strings()})},
    "admin.catalog-written": operation_receipt("content_item", extras={"publication_state": enum("DRAFT", "PUBLISHED", "WITHDRAWN"), "rights_decision": enum("ALLOW", "DENY")}),
    "admin.recommendation-policies": {"recommendation_policies": catalog_records("recommendation_policy", {"hard_filter_rule_count": {"type": "integer", "minimum": 1}, "scoring_feature_count": {"type": "integer", "minimum": 1}, "policy_digest": scalar_schema("policy_digest")})},
    "admin.recommendation-policy-activated": operation_receipt("recommendation_policy", states=("ACTIVE",), extras={"policy_digest": scalar_schema("policy_digest")}),
    "document.upload": {"upload_id": UUID, "file_object_id": UUID, "upload_state": enum("ACCEPTED", "QUARANTINED"), "malware_scan_state": enum("PENDING", "CLEAN", "BLOCKED"), "content_sha256": scalar_schema("content_sha256")},
    "document.created": {"document_id": UUID, "document_version_id": UUID, "processing_job_id": UUID, "ingestion_state": enum("QUEUED", "PROCESSING"), "rights_decision": enum("ALLOW", "DENY")},
    "admin.documents": {"documents": catalog_records("document", {"format_code": {"type": "string"}, "ingestion_state": enum("QUEUED", "PROCESSING", "REVIEW_REQUIRED", "READY", "FAILED"), "quality_microunit": scalar_schema("quality_microunit"), "rights_decision": enum("ALLOW", "DENY")})},
    "admin.document-graph": {"document_id": UUID, "document_version_id": UUID, "graph_root_node_id": UUID, "nodes": records({"node_id": UUID, "parent_node_id": {"oneOf": [UUID, {"type": "null"}]}, "node_type": enum("SECTION", "PARAGRAPH", "TABLE", "CELL", "IMAGE"), "node_path": {"type": "string"}, "source_locator": {"type": "string"}, "style_ref": {"type": ["string", "null"]}, "structure_confidence_microunit": scalar_schema("structure_confidence_microunit")}), "graph_digest": scalar_schema("graph_digest")},
    "admin.document-node-updated": operation_receipt("document_node", extras={"graph_digest": scalar_schema("graph_digest"), "structure_confidence_microunit": scalar_schema("structure_confidence_microunit")}),
    "admin.document-job": {"document_id": UUID, "processing_job_id": UUID, "job_state": enum("QUEUED", "RUNNING", "COMPLETED", "FAILED"), "stage_code": {"type": "string"}, "progress_microunit": scalar_schema("progress_microunit")},
    "admin.document-review": {"document_id": UUID, "review_decision_id": UUID, "review_decision": enum("APPROVED", "CHANGES_REQUESTED", "REJECTED"), "quality_microunit": scalar_schema("quality_microunit"), "decided_at": DATE_TIME},
    "admin.document-publications": {"document_publications": catalog_records("document_publication", {"document_version_id": UUID, "publication_state": enum("PUBLISHED", "WITHDRAWN"), "rights_snapshot_hash": scalar_schema("rights_snapshot_hash")})},
    "admin.document-publication-change": operation_receipt("document_publication", states=("PUBLISHED", "WITHDRAWN"), extras={"index_snapshot_id": UUID, "rights_snapshot_hash": scalar_schema("rights_snapshot_hash")}),
    "admin.index-rollback": {"index_snapshot_id": UUID, "rollback_state": enum("QUEUED", "COMPLETED", "FAILED"), "previous_snapshot_id": UUID, "active_snapshot_id": UUID, "completed_at": DATE_TIME},
    "admin.models": {"models": catalog_records("model_deployment", {"provider_code": {"type": "string"}, "model_code": {"type": "string"}, "allowed_data_classes": strings(minimum=1), "health_state": enum("HEALTHY", "DEGRADED", "DISABLED")})},
    "admin.model-written": operation_receipt("model_deployment", extras={"provider_code": {"type": "string"}, "allowed_data_classes": strings(minimum=1)}),
    "admin.prompts": {"prompts": catalog_records("prompt_version", {"task_code": {"type": "string"}, "prompt_digest": scalar_schema("prompt_digest")})},
    "admin.schemas": {"schemas": catalog_records("schema_version", {"task_code": {"type": "string"}, "schema_digest": scalar_schema("schema_digest")})},
    "admin.routing-policies": {"routing_policies": catalog_records("routing_policy", {"classification_code": {"type": "string"}, "route_codes": strings(minimum=1), "policy_digest": scalar_schema("policy_digest")})},
    "admin.evaluations": {"evaluations": records({"evaluation_run_id": UUID, "suite_id": UUID, "candidate_deployment_id": UUID, "run_state": enum("QUEUED", "RUNNING", "PASSED", "FAILED"), "gate_decision": enum("PENDING", "ALLOW", "DENY"), "completed_at": {"oneOf": [DATE_TIME, {"type": "null"}]}})},
    "admin.evaluation-created": {"evaluation_run_id": UUID, "run_state": enum("QUEUED", "RUNNING"), "suite_id": UUID, "holdout_snapshot_id": UUID, "gate_policy_digest": scalar_schema("gate_policy_digest")},
    "admin.evaluation-datasets": {"evaluation_datasets": catalog_records("evaluation_dataset", {"record_count": {"type": "integer", "minimum": 1}, "dataset_digest": scalar_schema("dataset_digest"), "holdout": {"type": "boolean"}})},
    "admin.ai-runs": {"ai_runs": records({"model_run_id": UUID, "task_code": {"type": "string"}, "provider_code": {"type": "string"}, "run_state": enum("RUNNING", "COMPLETED", "FAILED", "BLOCKED"), "latency_milliseconds": {"type": "integer", "minimum": 0}, "cost_microunit": scalar_schema("cost_microunit"), "created_at": DATE_TIME})},
    "admin.ai-costs": {"period_start": DATE_TIME, "period_end": DATE_TIME, "provider_costs": records({"provider_code": {"type": "string"}, "request_count": {"type": "integer", "minimum": 0}, "token_count": {"type": "integer", "minimum": 0}, "cost_microunit": scalar_schema("cost_microunit")}), "budget_utilization_microunit": scalar_schema("budget_utilization_microunit")},
    "admin.ai-fallbacks": {"period_start": DATE_TIME, "period_end": DATE_TIME, "fallback_events": records({"task_code": {"type": "string"}, "source_route": {"type": "string"}, "fallback_route": {"type": "string"}, "reason_code": {"type": "string"}, "event_count": {"type": "integer", "minimum": 0}}), "restricted_external_event_count": {"type": "integer", "minimum": 0}},
    "admin.users": {"users": catalog_records("user", {"account_state": enum("ACTIVE", "LOCKED", "DISABLED"), "mfa_enrolled": {"type": "boolean"}})},
    "admin.organizations": {"organizations": catalog_records("organization", {"organization_type": {"type": "string"}, "region_category": {"type": "string"}})},
    "admin.memberships": {"memberships": catalog_records("membership", {"user_id": UUID, "organization_id": UUID, "role_codes": strings(minimum=1)})},
    "admin.roles": {"roles": catalog_records("role", {"permission_codes": strings(minimum=1), "scope_code": {"type": "string"}})},
    "admin.consents": {"consents": records({"consent_id": UUID, "subject_id": UUID, "purpose_code": {"type": "string"}, "decision": enum("GRANTED", "DENIED", "WITHDRAWN"), "policy_version": {"type": "string"}, "decided_at": DATE_TIME})},
    "admin.pilot-cohorts": {"pilot_cohorts": catalog_records("pilot_cohort", {"region_codes": strings(minimum=1), "participant_count": {"type": "integer", "minimum": 0}, "pilot_state": enum("PLANNED", "ACTIVE", "COMPLETED")})},
    "admin.pilot-cohort-created": operation_receipt("pilot_cohort", extras={"pilot_state": enum("PLANNED", "ACTIVE"), "participant_count": {"type": "integer", "minimum": 0}}),
    "admin.fgi-sessions": {"fgi_sessions": catalog_records("fgi_session", {"cohort_id": UUID, "participant_count": {"type": "integer", "minimum": 0}, "analysis_state": enum("PLANNED", "TRANSCRIBED", "ANALYZED")})},
    "admin.improvement-issues": {"improvement_issues": records({"improvement_issue_id": UUID, "severity": enum("LOW", "MEDIUM", "HIGH", "CRITICAL"), "issue_state": enum("OPEN", "IN_PROGRESS", "RESOLVED"), "source_evidence_ids": uuids(minimum=1), "owner_id": UUID, "due_at": DATE_TIME})},
    "admin.analytics-outcomes": {"period_start": DATE_TIME, "period_end": DATE_TIME, "outcome_metrics": records({"competency_code": {"type": "string"}, "baseline_microunit": scalar_schema("baseline_microunit"), "current_microunit": scalar_schema("current_microunit"), "sample_count": {"type": "integer", "minimum": 0}, "suppressed": {"type": "boolean"}})},
    "admin.analytics-course-effects": {"period_start": DATE_TIME, "period_end": DATE_TIME, "course_effects": records({"course_id": UUID, "effect_size_microunit": scalar_schema("effect_size_microunit"), "confidence_microunit": scalar_schema("confidence_microunit"), "sample_count": {"type": "integer", "minimum": 0}, "suppressed": {"type": "boolean"}})},
    "admin.report-queued": {"admin_report_id": UUID, "report_job_id": UUID, "report_state": enum("QUEUED", "GENERATING"), "suppression_policy_version": {"type": "string"}, "snapshot_cutoff_at": DATE_TIME},
    "admin.audit-events": {"audit_events": records({"audit_event_id": UUID, "actor_pseudonym": {"type": "string"}, "action_code": {"type": "string"}, "object_type": {"type": "string"}, "object_pseudonym": {"type": "string"}, "occurred_at": DATE_TIME, "event_hash": scalar_schema("event_hash")})},
    "admin.audit-export": {"audit_export_id": UUID, "export_job_id": UUID, "export_state": enum("QUEUED", "READY", "FAILED"), "scope_digest": scalar_schema("scope_digest"), "requested_at": DATE_TIME},
    "admin.security-events": {"security_events": records({"security_event_id": UUID, "event_type": {"type": "string"}, "severity": enum("LOW", "MEDIUM", "HIGH", "CRITICAL"), "decision": enum("MONITOR", "BLOCK", "ESCALATE"), "occurred_at": DATE_TIME, "trace_id": UUID})},
    "admin.jobs": {"jobs": records({"processing_job_id": UUID, "job_type": {"type": "string"}, "job_state": enum("QUEUED", "RUNNING", "COMPLETED", "FAILED", "DEAD_LETTER"), "stage_code": {"type": "string"}, "progress_microunit": scalar_schema("progress_microunit"), "attempt_count": {"type": "integer", "minimum": 0}, "updated_at": DATE_TIME})},
    "admin.job-retry": {"processing_job_id": UUID, "retry_attempt_id": UUID, "job_state": enum("QUEUED", "RUNNING"), "attempt_count": {"type": "integer", "minimum": 1}, "queued_at": DATE_TIME},
    "admin.indexes": {"indexes": records({"index_snapshot_id": UUID, "index_kind": enum("LEXICAL", "VECTOR", "METADATA"), "index_state": enum("BUILDING", "ACTIVE", "DEGRADED", "ROLLED_BACK"), "document_count": {"type": "integer", "minimum": 0}, "embedding_count": {"type": "integer", "minimum": 0}, "built_at": DATE_TIME})},
    "admin.storage": {"storage_state": enum("HEALTHY", "DEGRADED", "UNAVAILABLE"), "object_count": {"type": "integer", "minimum": 0}, "used_bytes": {"type": "integer", "minimum": 0}, "quarantine_count": {"type": "integer", "minimum": 0}, "last_integrity_scan_at": DATE_TIME},
    "admin.backups": {"backups": records({"backup_manifest_id": UUID, "backup_state": enum("CREATING", "VERIFIED", "FAILED", "EXPIRED"), "snapshot_at": DATE_TIME, "size_bytes": {"type": "integer", "minimum": 0}, "content_sha256": scalar_schema("content_sha256"), "restore_drill_state": enum("NOT_RUN", "PASSED", "FAILED")})},
    "admin.integrations": {"integrations": records({"integration_id": UUID, "integration_type": enum("OBJECT_STORAGE", "EMAIL", "AI_PROVIDER", "OCR"), "integration_state": enum("HEALTHY", "DEGRADED", "DISABLED"), "last_success_at": {"oneOf": [DATE_TIME, {"type": "null"}]}, "failure_count": {"type": "integer", "minimum": 0}, "circuit_state": enum("CLOSED", "OPEN", "HALF_OPEN")}), "checked_at": DATE_TIME},
    "health.ready": {"readiness": enum("READY", "NOT_READY"), "checked_at": DATE_TIME, "dependency_checks": records({"dependency_code": {"type": "string"}, "dependency_state": enum("AVAILABLE", "DEGRADED", "UNAVAILABLE"), "latency_milliseconds": {"type": "integer", "minimum": 0}})},
}


OPERATION_RESPONSE_BLUEPRINT_IDS: dict[str, str] = {
    "GET /api/v1/portal/home": "portal.home",
    "GET /api/v1/public/catalog": "public.catalog",
    "GET /api/v1/public/search": "public.search",
    "GET /api/v1/public/resources/{resource_id}": "public.resource",
    "POST /api/v1/files/{file_id}/download-authorizations": "file.download.authorization",
    "POST /api/v1/auth/register": "auth.register",
    "POST /api/v1/auth/login": "auth.login",
    "POST /api/v1/auth/password-resets": "auth.password-reset",
    "POST /api/v1/auth/mfa/challenges": "auth.mfa-challenge",
    "POST /api/v1/auth/mfa/challenges/{challenge_id}/verify": "auth.mfa-verify",
    "POST /api/v1/auth/mfa/recovery": "auth.mfa-recovery",
    "GET /api/v1/me/dashboard": "member.dashboard",
    "GET /api/v1/me": "member.profile",
    "PATCH /api/v1/me": "member.profile-updated",
    "GET /api/v1/me/consents": "member.consents",
    "POST /api/v1/me/consents": "member.consent-recorded",
    "POST /api/v1/tenants/{tenant_id}/activate": "tenant.activated",
    "POST /api/v1/diagnoses": "diagnosis.created",
    "GET /api/v1/diagnoses/{id}": "diagnosis.session",
    "POST /api/v1/diagnoses/{id}/turns": "diagnosis.turn",
    "POST /api/v1/diagnoses/{id}/pause": "diagnosis.state-change",
    "POST /api/v1/diagnoses/{id}/resume": "diagnosis.state-change",
    "GET /api/v1/diagnoses/{id}/results": "diagnosis.result",
    "GET /api/v1/diagnoses/{id}/evidence": "diagnosis.evidence",
    "PATCH /api/v1/evidence/{id}": "diagnosis.evidence-reviewed",
    "POST /api/v1/diagnoses/{id}/rescore": "diagnosis.rescored",
    "GET /api/v1/diagnoses/{id}/personas": "diagnosis.personas",
    "PATCH /api/v1/diagnoses/{id}/persona-context": "diagnosis.persona-context",
    "GET /api/v1/recommendations": "recommendation.list",
    "POST /api/v1/recommendations/{id}/feedback": "recommendation.feedback",
    "POST /api/v1/learning-paths": "learning.path",
    "GET /api/v1/learning-paths/{id}": "learning.path",
    "PATCH /api/v1/learning-paths/{id}": "learning.path-updated",
    "POST /api/v1/steps/{id}/start": "learning.step-state",
    "POST /api/v1/steps/{id}/complete": "learning.step-state",
    "POST /api/v1/practice-submissions": "learning.practice-submission",
    "POST /api/v1/reports": "report.queued",
    "GET /api/v1/reports/{id}": "report.detail",
    "GET /api/v1/reports/{id}/artifact": "report.artifact",
    "POST /api/v1/search": "document.search",
    "POST /api/v1/rag/sessions": "rag.session-created",
    "POST /api/v1/rag/sessions/{id}/messages": "rag.message",
    "GET /api/v1/citations/{id}": "citation.detail",
    "GET /api/v1/draft-templates": "draft.templates",
    "POST /api/v1/drafts": "draft.detail",
    "GET /api/v1/drafts/{id}": "draft.detail",
    "PATCH /api/v1/drafts/{id}": "draft.updated",
    "POST /api/v1/drafts/{id}/review": "draft.reviewed",
    "POST /api/v1/drafts/{id}/export": "draft.export",
    "GET /api/v1/me/activity": "member.activity",
    "GET /api/v1/me/notifications": "member.notifications",
    "POST /api/v1/me/export-requests": "member.export-request",
    "POST /api/v1/me/deletion-requests": "member.deletion-request",
    "POST /api/v1/inquiries": "inquiry.created",
    "GET /api/v1/admin/metrics-summary": "admin.metrics",
    "GET /api/v1/admin/frameworks": "admin.frameworks",
    "POST /api/v1/admin/frameworks": "admin.framework-written",
    "GET /api/v1/admin/rubrics": "admin.rubrics",
    "POST /api/v1/admin/rubrics": "admin.rubric-written",
    "GET /api/v1/admin/personas": "admin.personas",
    "POST /api/v1/admin/personas/{id}/activate": "admin.persona-activated",
    "GET /api/v1/admin/catalog": "admin.catalog",
    "POST /api/v1/admin/catalog": "admin.catalog-written",
    "PATCH /api/v1/admin/catalog/{id}": "admin.catalog-written",
    "GET /api/v1/admin/recommendation-policies": "admin.recommendation-policies",
    "POST /api/v1/admin/recommendation-policies/{id}/activate": "admin.recommendation-policy-activated",
    "POST /api/v1/documents/uploads": "document.upload",
    "POST /api/v1/documents": "document.created",
    "GET /api/v1/admin/documents": "admin.documents",
    "GET /api/v1/admin/documents/{id}/graph": "admin.document-graph",
    "PATCH /api/v1/admin/document-nodes/{id}": "admin.document-node-updated",
    "POST /api/v1/admin/documents/{id}/reprocess": "admin.document-job",
    "POST /api/v1/admin/documents/{id}/review-decisions": "admin.document-review",
    "GET /api/v1/admin/document-publications": "admin.document-publications",
    "POST /api/v1/admin/documents/{id}/publish": "admin.document-publication-change",
    "POST /api/v1/admin/documents/{id}/withdraw": "admin.document-publication-change",
    "POST /api/v1/admin/index-snapshots/{id}/rollback": "admin.index-rollback",
    "GET /api/v1/admin/models": "admin.models",
    "POST /api/v1/admin/models": "admin.model-written",
    "GET /api/v1/admin/prompts": "admin.prompts",
    "GET /api/v1/admin/schemas": "admin.schemas",
    "GET /api/v1/admin/routing-policies": "admin.routing-policies",
    "GET /api/v1/admin/evaluations": "admin.evaluations",
    "POST /api/v1/admin/evaluations": "admin.evaluation-created",
    "GET /api/v1/admin/evaluation-datasets": "admin.evaluation-datasets",
    "GET /api/v1/admin/ai-runs": "admin.ai-runs",
    "GET /api/v1/admin/ai-costs": "admin.ai-costs",
    "GET /api/v1/admin/ai-fallbacks": "admin.ai-fallbacks",
    "GET /api/v1/admin/users": "admin.users",
    "GET /api/v1/admin/organizations": "admin.organizations",
    "GET /api/v1/admin/memberships": "admin.memberships",
    "GET /api/v1/admin/roles": "admin.roles",
    "GET /api/v1/admin/consents": "admin.consents",
    "POST /api/v1/auth/mfa/enrollments": "auth.mfa-enrollment",
    "POST /api/v1/auth/mfa/enrollments/{id}/verify": "auth.mfa-enrollment-verify",
    "POST /api/v1/auth/mfa/recovery-codes/rotate": "auth.mfa-recovery-rotate",
    "GET /api/v1/admin/pilot-cohorts": "admin.pilot-cohorts",
    "POST /api/v1/admin/pilot-cohorts": "admin.pilot-cohort-created",
    "GET /api/v1/admin/fgi-sessions": "admin.fgi-sessions",
    "GET /api/v1/admin/improvement-issues": "admin.improvement-issues",
    "GET /api/v1/admin/analytics/outcomes": "admin.analytics-outcomes",
    "GET /api/v1/admin/analytics/course-effects": "admin.analytics-course-effects",
    "POST /api/v1/admin/reports": "admin.report-queued",
    "GET /api/v1/admin/audit-events": "admin.audit-events",
    "POST /api/v1/admin/audit-exports": "admin.audit-export",
    "GET /api/v1/admin/security-events": "admin.security-events",
    "GET /api/v1/admin/jobs": "admin.jobs",
    "POST /api/v1/admin/jobs/{id}/retry": "admin.job-retry",
    "GET /api/v1/admin/indexes": "admin.indexes",
    "GET /api/v1/admin/storage": "admin.storage",
    "GET /api/v1/admin/backups": "admin.backups",
    "GET /api/v1/admin/integrations": "admin.integrations",
    "GET /health/ready": "health.ready",
}


def semantic_response_properties(operation_key: str) -> tuple[str, dict[str, Any]]:
    if operation_key not in OPERATION_RESPONSE_BLUEPRINT_IDS:
        raise ValueError(f"missing explicit response blueprint for {operation_key}")
    blueprint_id = OPERATION_RESPONSE_BLUEPRINT_IDS[operation_key]
    if blueprint_id not in RESPONSE_BLUEPRINTS:
        raise ValueError(f"unknown response blueprint {blueprint_id} for {operation_key}")
    properties: dict[str, Any] = {
        "schema_version": {"const": f"response.{blueprint_id}.v1"},
        "trace_id": UUID,
    }
    properties.update(deepcopy(RESPONSE_BLUEPRINTS[blueprint_id]))
    return blueprint_id, properties


REQUEST_BLUEPRINTS: dict[str, dict[str, Any]] = {
    "file.download.authorization": {"intended_use": {"type": "string"}, "rights_acknowledgement": {"type": "boolean"}},
    "auth.register": {"email": scalar_schema("email"), "password": scalar_schema("password"), "display_name": {"type": "string"}, "terms_version": {"type": "string"}},
    "auth.login": {"email": scalar_schema("email"), "password": scalar_schema("password")},
    "auth.refresh": {"command_id": UUID},
    "auth.logout": {"command_id": UUID},
    "auth.logout-all": {"command_id": UUID, "reauth_assertion": {"type": "string", "minLength": 16, "maxLength": 4096}, "reason_code": {"type": "string", "minLength": 1, "maxLength": 64}},
    "auth.password-reset-confirm": {"command_id": UUID, "one_time_reset_token": {"type": "string", "minLength": 32, "maxLength": 512}, "new_password": {"type": "string", "minLength": 12, "maxLength": 128}},
    "auth.password-reset": {"email": scalar_schema("email")},
    "auth.mfa-challenge": {"purpose": enum("LOGIN", "PRIVILEGED_OPERATION", "RECOVERY")},
    "auth.mfa-verify": {"verification_code": {"type": "string", "minLength": 6, "maxLength": 128}},
    "auth.mfa-recovery": {"recovery_code": {"type": "string", "minLength": 12, "maxLength": 128}},
    "member.profile-update": {"display_name": {"type": "string"}, "career_band": {"type": "string"}, "region_category": {"type": "string"}, "interest_keywords": strings(), "expected_version": {"type": "integer", "minimum": 1}},
    "member.consent": {"purpose_code": {"type": "string"}, "decision": enum("GRANTED", "DENIED", "WITHDRAWN"), "policy_version": {"type": "string"}},
    "tenant.activate": {"membership_id": UUID, "expected_context_revision": {"type": "integer", "minimum": 0}},
    "diagnosis.create": {"framework_version": {"type": "string"}, "consent_epoch": {"type": "integer", "minimum": 1}, "context_snapshot_id": UUID},
    "diagnosis.turn": {"content": scalar_schema("content"), "client_turn_sequence": {"type": "integer", "minimum": 0}},
    "diagnosis.state-change": {"reason": scalar_schema("reason"), "expected_version": {"type": "integer", "minimum": 1}},
    "diagnosis.evidence-review": {"action": enum("ACCEPT", "CORRECT", "REJECT"), "corrected_anchor": {"type": ["string", "null"], "maxLength": 4000}, "reason": scalar_schema("reason"), "row_version": {"type": "integer", "minimum": 1}},
    "diagnosis.rescore": {"evidence_ids": uuids(minimum=1), "reason": scalar_schema("reason")},
    "diagnosis.persona-context": {"decision": enum("ACCEPT", "OVERRIDE", "UNDETERMINED"), "accepted_persona_ids": uuids(), "context_factor_codes": strings(), "reason": scalar_schema("reason"), "expected_version": {"type": "integer", "minimum": 1}},
    "recommendation.feedback": {"decision": enum("ACCEPTED", "REJECTED", "DEFERRED"), "reason": scalar_schema("reason"), "presentation_context_code": {"type": "string"}},
    "learning.path-create": {"recommendation_ids": uuids(minimum=1), "constraint_codes": strings()},
    "learning.path-update": {"steps": records({"step_id": UUID, "predecessor_step_ids": uuids(), "client_position": {"type": "integer", "minimum": 0}}), "constraint_codes": strings(), "expected_version": {"type": "integer", "minimum": 1}},
    "learning.step-event": {"occurred_at": DATE_TIME, "client_event_id": UUID},
    "learning.practice-submission": {"step_id": UUID, "reflection": scalar_schema("reflection"), "attachment_ids": uuids()},
    "report.create": {"report_type": enum("COMPETENCY", "LEARNING_OUTCOME", "COMBINED"), "period_start": DATE_TIME, "period_end": DATE_TIME},
    "document.search": {"query": scalar_schema("query"), "filters": scalar_schema("filters")},
    "rag.session-create": {"query": scalar_schema("query"), "filters": scalar_schema("filters")},
    "rag.message": {"content": scalar_schema("content"), "client_turn_sequence": {"type": "integer", "minimum": 0}},
    "draft.create": {"template_version_id": UUID, "evidence_ids": uuids(minimum=1), "field_values": records({"field_code": {"type": "string"}, "value": {"type": "string"}, "evidence_ids": uuids()})},
    "draft.update": {"field_changes": records({"field_code": {"type": "string"}, "value": {"type": "string"}, "evidence_ids": uuids()}), "expected_version": {"type": "integer", "minimum": 1}},
    "draft.review": {"decision": enum("APPROVE", "REQUEST_CHANGES", "REJECT"), "reason": scalar_schema("reason"), "row_version": {"type": "integer", "minimum": 1}},
    "draft.export": {"format": enum("HWPX", "PDF", "DOCX"), "reason": scalar_schema("reason")},
    "member.export-request": {"format": enum("JSON", "CSV", "PDF"), "scope_codes": strings(minimum=1), "reason": scalar_schema("reason")},
    "member.deletion-request": {"scope": enum("PROFILE", "ACTIVITY", "ALL_ELIGIBLE_DATA"), "reason": scalar_schema("reason")},
    "inquiry.create": {"subject": {"type": "string"}, "content": scalar_schema("content"), "category": {"type": "string"}},
    "admin.framework-create": {"framework_name": {"type": "string"}, "semantic_version": {"type": "string"}, "dimension_codes": strings(minimum=1)},
    "admin.rubric-create": {"framework_id": UUID, "semantic_version": {"type": "string"}, "indicator_ids": uuids(minimum=1), "effective_at": DATE_TIME},
    "admin.version-activate": {"candidate_version_id": UUID, "reason": scalar_schema("reason"), "expected_version": {"type": "integer", "minimum": 1}},
    "admin.catalog-create": {"content_type": {"type": "string"}, "title": {"type": "string"}, "summary": scalar_schema("summary"), "competency_codes": strings(minimum=1), "prerequisite_codes": strings(), "accessibility_features": strings(), "region_availability_codes": strings(), "rights": scalar_schema("rights")},
    "admin.catalog-update": {"title": {"type": "string"}, "summary": scalar_schema("summary"), "competency_codes": strings(minimum=1), "prerequisite_codes": strings(), "accessibility_features": strings(), "region_availability_codes": strings(), "publication_state": enum("DRAFT", "PUBLISHED", "WITHDRAWN"), "expected_version": {"type": "integer", "minimum": 1}},
    "document.upload": {"filename": {"type": "string"}, "mime_type": {"type": "string"}, "size_bytes": {"type": "integer", "minimum": 1}, "sha256": scalar_schema("sha256")},
    "document.create": {"upload_id": UUID, "metadata": scalar_schema("metadata"), "rights": scalar_schema("rights")},
    "admin.document-node-update": {"normalized_text": {"type": "string"}, "style_ref": {"type": ["string", "null"]}, "structure_confidence_microunit": scalar_schema("structure_confidence_microunit"), "row_version": {"type": "integer", "minimum": 1}, "reason": scalar_schema("reason")},
    "admin.job-command": {"reason": scalar_schema("reason"), "expected_version": {"type": "integer", "minimum": 1}},
    "admin.document-review": {"decision": enum("APPROVE", "REQUEST_CHANGES", "REJECT"), "reason": scalar_schema("reason"), "row_version": {"type": "integer", "minimum": 1}},
    "admin.model-create": {"provider_id": UUID, "deployment_revision": {"type": "string"}, "allowed_data_classes": strings(minimum=1), "effective_at": DATE_TIME},
    "admin.evaluation-create": {"evaluation_suite_id": UUID, "candidate_deployment_id": UUID, "holdout_snapshot_id": UUID},
    "auth.mfa-enrollment": {"factor_type": enum("TOTP", "WEBAUTHN"), "display_name": {"type": "string"}},
    "auth.mfa-enrollment-verify": {"verification_code": {"type": "string", "minLength": 6, "maxLength": 128}},
    "auth.mfa-recovery-rotate": {"reason": scalar_schema("reason")},
    "admin.pilot-cohort-create": {"cohort_name": {"type": "string"}, "region_codes": strings(minimum=1), "career_bands": strings(minimum=1), "starts_at": DATE_TIME, "ends_at": DATE_TIME},
    "admin.report-create": {"report_type": {"type": "string"}, "period_start": DATE_TIME, "period_end": DATE_TIME, "suppression_policy_version": {"type": "string"}},
    "admin.audit-export": {"period_start": DATE_TIME, "period_end": DATE_TIME, "reason": scalar_schema("reason"), "format": enum("JSONL", "CSV")},
}


OPERATION_REQUEST_BLUEPRINT_IDS: dict[str, str] = {
    "POST /api/v1/files/{file_id}/download-authorizations": "file.download.authorization",
    "POST /api/v1/auth/register": "auth.register",
    "POST /api/v1/auth/login": "auth.login",
    "POST /api/v1/auth/refresh": "auth.refresh",
    "POST /api/v1/auth/logout": "auth.logout",
    "POST /api/v1/auth/logout-all": "auth.logout-all",
    "POST /api/v1/auth/password-resets/confirm": "auth.password-reset-confirm",
    "POST /api/v1/auth/password-resets": "auth.password-reset",
    "POST /api/v1/auth/mfa/challenges": "auth.mfa-challenge",
    "POST /api/v1/auth/mfa/challenges/{challenge_id}/verify": "auth.mfa-verify",
    "POST /api/v1/auth/mfa/recovery": "auth.mfa-recovery",
    "PATCH /api/v1/me": "member.profile-update",
    "POST /api/v1/me/consents": "member.consent",
    "POST /api/v1/tenants/{tenant_id}/activate": "tenant.activate",
    "POST /api/v1/diagnoses": "diagnosis.create",
    "POST /api/v1/diagnoses/{id}/turns": "diagnosis.turn",
    "POST /api/v1/diagnoses/{id}/pause": "diagnosis.state-change",
    "POST /api/v1/diagnoses/{id}/resume": "diagnosis.state-change",
    "PATCH /api/v1/evidence/{id}": "diagnosis.evidence-review",
    "POST /api/v1/diagnoses/{id}/rescore": "diagnosis.rescore",
    "PATCH /api/v1/diagnoses/{id}/persona-context": "diagnosis.persona-context",
    "POST /api/v1/recommendations/{id}/feedback": "recommendation.feedback",
    "POST /api/v1/learning-paths": "learning.path-create",
    "PATCH /api/v1/learning-paths/{id}": "learning.path-update",
    "POST /api/v1/steps/{id}/start": "learning.step-event",
    "POST /api/v1/steps/{id}/complete": "learning.step-event",
    "POST /api/v1/practice-submissions": "learning.practice-submission",
    "POST /api/v1/reports": "report.create",
    "POST /api/v1/search": "document.search",
    "POST /api/v1/rag/sessions": "rag.session-create",
    "POST /api/v1/rag/sessions/{id}/messages": "rag.message",
    "POST /api/v1/drafts": "draft.create",
    "PATCH /api/v1/drafts/{id}": "draft.update",
    "POST /api/v1/drafts/{id}/review": "draft.review",
    "POST /api/v1/drafts/{id}/export": "draft.export",
    "POST /api/v1/me/export-requests": "member.export-request",
    "POST /api/v1/me/deletion-requests": "member.deletion-request",
    "POST /api/v1/inquiries": "inquiry.create",
    "POST /api/v1/admin/frameworks": "admin.framework-create",
    "POST /api/v1/admin/rubrics": "admin.rubric-create",
    "POST /api/v1/admin/personas/{id}/activate": "admin.version-activate",
    "POST /api/v1/admin/catalog": "admin.catalog-create",
    "PATCH /api/v1/admin/catalog/{id}": "admin.catalog-update",
    "POST /api/v1/admin/recommendation-policies/{id}/activate": "admin.version-activate",
    "POST /api/v1/documents/uploads": "document.upload",
    "POST /api/v1/documents": "document.create",
    "PATCH /api/v1/admin/document-nodes/{id}": "admin.document-node-update",
    "POST /api/v1/admin/documents/{id}/reprocess": "admin.job-command",
    "POST /api/v1/admin/documents/{id}/review-decisions": "admin.document-review",
    "POST /api/v1/admin/documents/{id}/publish": "admin.job-command",
    "POST /api/v1/admin/documents/{id}/withdraw": "admin.job-command",
    "POST /api/v1/admin/index-snapshots/{id}/rollback": "admin.job-command",
    "POST /api/v1/admin/models": "admin.model-create",
    "POST /api/v1/admin/evaluations": "admin.evaluation-create",
    "POST /api/v1/auth/mfa/enrollments": "auth.mfa-enrollment",
    "POST /api/v1/auth/mfa/enrollments/{id}/verify": "auth.mfa-enrollment-verify",
    "POST /api/v1/auth/mfa/recovery-codes/rotate": "auth.mfa-recovery-rotate",
    "POST /api/v1/admin/pilot-cohorts": "admin.pilot-cohort-create",
    "POST /api/v1/admin/reports": "admin.report-create",
    "POST /api/v1/admin/audit-exports": "admin.audit-export",
    "POST /api/v1/admin/jobs/{id}/retry": "admin.job-command",
}


def field_contract(field_code: str, wire_name: str, location: str, schema: dict[str, Any], *, required: bool = True) -> dict[str, Any]:
    return {
        "field_code": field_code,
        "wire_name": wire_name,
        "location": location,
        "required": required,
        "schema": deepcopy(schema),
    }


SERVICE_AUTH_OPERATION_SPECS: dict[str, dict[str, Any]] = {
    "POST /api/v1/auth/refresh": {
        "operation_id": "post_api_v1_auth_refresh",
        "request_blueprint_id": "auth.refresh",
        "response_blueprint_id": "auth.refresh",
        "request_field_contracts": [
            field_contract("REFRESH_TOKEN_COOKIE", "yonlab_refresh", "COOKIE", {"type": "string", "minLength": 32, "maxLength": 2048}),
            field_contract("CSRF_TOKEN", "X-CSRF-Token", "HEADER", {"type": "string", "minLength": 32, "maxLength": 512}),
            field_contract("COMMAND_ID", "command_id", "BODY", UUID),
        ],
        "response_field_contracts": [
            field_contract("ACCESS_TOKEN", "access_token", "BODY", scalar_schema("access_token")),
            field_contract("EXPIRES_IN_SECONDS", "expires_in_seconds", "BODY", scalar_schema("expires_in_seconds")),
            field_contract("ROTATED_REFRESH_SESSION_ID", "rotated_refresh_session_id", "BODY", UUID),
            field_contract("SESSION_FAMILY_ID", "session_family_id", "BODY", UUID),
        ],
        "success_status": "200",
        "error_codes": ["AUTH_REFRESH_INVALID", "AUTH_REFRESH_REPLAY_DETECTED", "CSRF_INVALID", "RATE_LIMITED"],
        "security": [{"refreshCookie": [], "csrfHeader": []}],
        "state_transition": "ROTATE_ONCE_AND_REVOKE_PREDECESSOR",
        "replay_policy": "DENY_AND_REVOKE_SESSION_FAMILY",
        "request_log_policy": "REDACT_SECRETS",
    },
    "POST /api/v1/auth/logout": {
        "operation_id": "post_api_v1_auth_logout",
        "request_blueprint_id": "auth.logout",
        "response_blueprint_id": "auth.logout",
        "request_field_contracts": [
            field_contract("REFRESH_TOKEN_COOKIE", "yonlab_refresh", "COOKIE", {"type": "string", "minLength": 32, "maxLength": 2048}),
            field_contract("CSRF_TOKEN", "X-CSRF-Token", "HEADER", {"type": "string", "minLength": 32, "maxLength": 512}),
            field_contract("COMMAND_ID", "command_id", "BODY", UUID),
        ],
        "response_field_contracts": [
            field_contract("REVOKED_REFRESH_SESSION_ID", "revoked_refresh_session_id", "BODY", UUID),
            field_contract("LOGGED_OUT_AT", "logged_out_at", "BODY", DATE_TIME),
        ],
        "success_status": "200",
        "error_codes": ["AUTH_REFRESH_INVALID", "CSRF_INVALID", "RATE_LIMITED"],
        "security": [{"refreshCookie": [], "csrfHeader": []}],
        "state_transition": "REVOKE_CURRENT_REFRESH_SESSION",
        "replay_policy": "DENY_AND_REVOKE_SESSION_FAMILY",
        "request_log_policy": "REDACT_SECRETS",
    },
    "POST /api/v1/auth/logout-all": {
        "operation_id": "post_api_v1_auth_logout_all",
        "request_blueprint_id": "auth.logout-all",
        "response_blueprint_id": "auth.logout-all",
        "request_field_contracts": [
            field_contract("CSRF_TOKEN", "X-CSRF-Token", "HEADER", {"type": "string", "minLength": 32, "maxLength": 512}),
            field_contract("COMMAND_ID", "command_id", "BODY", UUID),
            field_contract("REAUTH_ASSERTION", "reauth_assertion", "BODY", {"type": "string", "minLength": 16, "maxLength": 4096}),
            field_contract("REASON_CODE", "reason_code", "BODY", {"type": "string", "minLength": 1, "maxLength": 64}),
        ],
        "response_field_contracts": [
            field_contract("REVOKED_SESSION_COUNT", "revoked_session_count", "BODY", {"type": "integer", "minimum": 0}),
            field_contract("SECURITY_EVENT_ID", "security_event_id", "BODY", UUID),
            field_contract("LOGGED_OUT_AT", "logged_out_at", "BODY", DATE_TIME),
        ],
        "success_status": "200",
        "error_codes": ["AUTHENTICATION_REQUIRED", "CSRF_INVALID", "REAUTH_REQUIRED", "RATE_LIMITED"],
        "security": [{"bearerAuth": [], "csrfHeader": []}],
        "state_transition": "REVOKE_ENTIRE_REFRESH_SESSION_FAMILY",
        "replay_policy": "DENY_AND_REVOKE_SESSION_FAMILY",
        "request_log_policy": "REDACT_SECRETS",
    },
    "POST /api/v1/auth/password-resets/confirm": {
        "operation_id": "post_api_v1_auth_password_resets_confirm",
        "request_blueprint_id": "auth.password-reset-confirm",
        "response_blueprint_id": "auth.password-reset-confirm",
        "request_field_contracts": [
            field_contract("COMMAND_ID", "command_id", "BODY", UUID),
            field_contract("ONE_TIME_RESET_TOKEN", "one_time_reset_token", "BODY", {"type": "string", "minLength": 32, "maxLength": 512}),
            field_contract("NEW_PASSWORD", "new_password", "BODY", {"type": "string", "minLength": 12, "maxLength": 128}),
        ],
        "response_field_contracts": [
            field_contract("PASSWORD_CHANGED_AT", "password_changed_at", "BODY", DATE_TIME),
            field_contract("REVOKED_SESSION_COUNT", "revoked_session_count", "BODY", {"type": "integer", "minimum": 0}),
            field_contract("SECURITY_EVENT_ID", "security_event_id", "BODY", UUID),
        ],
        "success_status": "200",
        "error_codes": ["PASSWORD_POLICY_REJECTED", "RATE_LIMITED", "RESET_TOKEN_CONSUMED", "RESET_TOKEN_EXPIRED", "RESET_TOKEN_INVALID"],
        "security": [],
        "state_transition": "CONSUME_TOKEN_ROTATE_PASSWORD_REVOKE_ALL_SESSIONS",
        "replay_policy": "DENY_AND_REVOKE_SESSION_FAMILY",
        "request_log_policy": "NEVER",
        "secret_request_field_codes": ["ONE_TIME_RESET_TOKEN", "NEW_PASSWORD"],
        "secret_path_parameter_count": 0,
    },
}

OPERATION_RESPONSE_BLUEPRINT_IDS.update(
    {operation_key: spec["response_blueprint_id"] for operation_key, spec in SERVICE_AUTH_OPERATION_SPECS.items()}
)


def semantic_request_properties(operation_key: str) -> tuple[str, dict[str, Any]]:
    if operation_key not in OPERATION_REQUEST_BLUEPRINT_IDS:
        raise ValueError(f"missing explicit request blueprint for {operation_key}")
    blueprint_id = OPERATION_REQUEST_BLUEPRINT_IDS[operation_key]
    if blueprint_id not in REQUEST_BLUEPRINTS:
        raise ValueError(f"unknown request blueprint {blueprint_id} for {operation_key}")
    return blueprint_id, deepcopy(REQUEST_BLUEPRINTS[blueprint_id])


def operation_error_codes(domain: str, subject: str, kind: str) -> list[str]:
    prefix = re.sub(r"[^A-Z0-9]+", "_", subject.upper())
    codes = [] if domain == "PUBLIC_PORTAL" else ["AUTHENTICATION_REQUIRED", "AUTHORIZATION_DENIED", "TENANT_SCOPE_VIOLATION"]
    if kind in {"READ_DETAIL", "UPDATE", "ACTION"}:
        codes.append(f"{prefix}_NOT_FOUND")
    if kind in {"CREATE", "UPDATE", "ACTION"}:
        codes.extend(["VALIDATION_FAILED", f"{prefix}_CONFLICT", "IDEMPOTENCY_REPLAY"])
    if kind == "HEALTH":
        return ["DEPENDENCY_UNAVAILABLE"]
    codes.append("RATE_LIMITED")
    return sorted(set(codes))


DOMAIN_DATA_USE = {
    "PUBLIC_PORTAL": ["PUBLIC_CONTENT"],
    "IDENTITY": ["IDENTITY_CREDENTIAL"],
    "DIAGNOSIS": ["TEACHER_CONTEXT", "DIAGNOSIS_DIALOGUE", "DIAGNOSIS_EVIDENCE"],
    "RECOMMENDATION": ["DIAGNOSIS_EVIDENCE", "RECOMMENDATION_FEATURE"],
    "LEARNING": ["LEARNING_ACTIVITY", "RECOMMENDATION_FEATURE"],
    "REPORTING": ["LEARNING_ACTIVITY"],
    "DOCUMENT": ["DOCUMENT_QUERY", "DOCUMENT_EVIDENCE"],
    "DRAFT": ["DOCUMENT_EVIDENCE", "DRAFT_FIELD"],
    "ADMINISTRATION": ["OPERATIONAL_METADATA"],
    "OPERATIONS": ["OPERATIONAL_METADATA"],
}


def generate_openapi(screen_registry: dict[str, Any]) -> dict[str, Any]:
    normative_operation_keys = {
        f"{contract['method']} {contract['path_template']}"
        for screen in screen_registry["screens"]
        for contract in screen["operation_contracts"]
    }
    deployed_operation_keys = normative_operation_keys | set(SERVICE_AUTH_OPERATION_SPECS)
    blueprint_operation_keys = set(OPERATION_RESPONSE_BLUEPRINT_IDS)
    if blueprint_operation_keys != deployed_operation_keys or len(blueprint_operation_keys) != 117:
        missing = sorted(deployed_operation_keys - blueprint_operation_keys)
        extra = sorted(blueprint_operation_keys - deployed_operation_keys)
        raise ValueError(f"response blueprint closure drift: missing={missing}, extra={extra}")
    unknown_blueprint_ids = set(OPERATION_RESPONSE_BLUEPRINT_IDS.values()) - set(RESPONSE_BLUEPRINTS)
    if unknown_blueprint_ids:
        raise ValueError(f"unknown response blueprint IDs: {sorted(unknown_blueprint_ids)}")
    deployed_write_keys = {
        operation_key
        for operation_key in deployed_operation_keys
        if operation_key.split(" ", 1)[0] in {"POST", "PATCH", "PUT", "DELETE"}
    }
    request_blueprint_operation_keys = set(OPERATION_REQUEST_BLUEPRINT_IDS)
    if request_blueprint_operation_keys != deployed_write_keys or len(request_blueprint_operation_keys) != 61:
        missing = sorted(deployed_write_keys - request_blueprint_operation_keys)
        extra = sorted(request_blueprint_operation_keys - deployed_write_keys)
        raise ValueError(f"request blueprint closure drift: missing={missing}, extra={extra}")
    unknown_request_blueprint_ids = set(OPERATION_REQUEST_BLUEPRINT_IDS.values()) - set(REQUEST_BLUEPRINTS)
    if unknown_request_blueprint_ids:
        raise ValueError(f"unknown request blueprint IDs: {sorted(unknown_request_blueprint_ids)}")
    paths: dict[str, Any] = {}
    schemas: dict[str, Any] = {
        "Problem": closed_object(
            {
                "type": {"type": "string", "format": "uri"},
                "title": {"type": "string"},
                "status": {"type": "integer", "minimum": 400, "maximum": 599},
                "code": {"type": "string", "pattern": "^[A-Z][A-Z0-9_]+$"},
                "trace_id": UUID,
            }
        )
    }
    semantic_rows: list[dict[str, Any]] = []
    blueprint_bindings: list[dict[str, str]] = []
    request_blueprint_bindings: list[dict[str, str]] = []
    for screen in screen_registry["screens"]:
        for contract in screen["operation_contracts"]:
            method_upper = contract["method"]
            method = method_upper.lower()
            path = contract["path_template"]
            operation_id = contract["operation_id"]
            subject = operation_subject(path)
            domain = operation_domain(screen["screen_id"], path)
            kind = operation_kind(method_upper, path)
            req_name = schema_name(operation_id, "Request")
            query_name = schema_name(operation_id, "Query")
            res_name = schema_name(operation_id, "Response")
            error_name = schema_name(operation_id, "Error")
            request_ref: str | None = None
            request_blueprint_id: str | None = None
            canonical_operation_key = f"{method_upper} {path}"
            if canonical_operation_key in OPERATION_REQUEST_BLUEPRINT_IDS:
                request_blueprint_id, request_properties = semantic_request_properties(canonical_operation_key)
                request_ref = req_name
                schemas[req_name] = closed_object(request_properties)
            blueprint_id, response_props = semantic_response_properties(canonical_operation_key)
            query_ref: str | None = None
            pagination = {"mode": "NONE"}
            parameters: list[dict[str, Any]] = []
            for parameter in re.findall(r"\{([^}]+)\}", path):
                parameters.append({"name": parameter, "in": "path", "required": True, "schema": UUID})
            if kind == "READ_COLLECTION":
                query_ref = query_name
                query_props = {
                    "cursor": {"type": ["string", "null"], "maxLength": 512},
                    "page_size": {"type": "integer", "minimum": 1, "maximum": 100},
                    "sort": {"type": "string", "enum": ["UPDATED_DESC", "CREATED_DESC", "LABEL_ASC"]},
                    f"{subject}_filter": {"type": ["string", "null"], "maxLength": 200},
                }
                schemas[query_name] = closed_object(query_props, required=[])
                pagination = {"mode": "CURSOR", "query_schema_ref": f"#/components/schemas/{query_name}"}
                response_props["page"] = deepcopy(PAGE)
                for name, schema in query_props.items():
                    parameters.append({"name": name, "in": "query", "required": False, "schema": schema})
            schemas[res_name] = closed_object(response_props)
            error_codes = operation_error_codes(domain, subject, kind)
            schemas[error_name] = closed_object(
                {
                    "type": {"type": "string", "format": "uri"},
                    "title": {"type": "string", "minLength": 1},
                    "http_status": {"type": "integer", "minimum": 400, "maximum": 599},
                    "code": {"type": "string", "enum": error_codes},
                    "trace_id": UUID,
                    "violations": {"type": "array", "items": closed_object({"field": {"type": "string"}, "rule": {"type": "string"}})},
                }
            )
            if method_upper == "POST" and any(token in path for token in ["reports", "uploads", "export", "reprocess", "evaluations", "audit-exports"]):
                status = "202"
            elif method_upper == "POST" and kind == "CREATE":
                status = "201"
            else:
                status = "200"
            operation: dict[str, Any] = {
                "operationId": slug(operation_id).replace("-", "_"),
                "summary": f"{screen['screen_id']} {subject} {kind.lower()}",
                "parameters": parameters,
                "responses": {
                    status: {"description": f"{subject} {kind.lower()} response", "content": {"application/json": {"schema": {"$ref": f"#/components/schemas/{res_name}"}}}},
                    "default": {"description": f"{subject} closed error vocabulary", "content": {"application/problem+json": {"schema": {"$ref": f"#/components/schemas/{error_name}"}}}},
                },
                "security": [{"bearerAuth": []}] if not screen["screen_id"].startswith("PUB-") else [],
                "x-screen-id": screen["screen_id"],
                "x-capability-id": contract["capability_id"],
                "x-authorization-contract-id": contract["authorization_contract_id"],
                "x-reject-unknown-query": True,
                "x-owner-ids": contract["owner_ids"],
                "x-requirement-ids": contract["requirement_ids"],
                "x-test-ids": contract["test_ids"],
                "x-evidence-ids": contract["evidence_ids"],
                "x-domain": domain,
                "x-operation-kind": kind,
                "x-response-blueprint-id": blueprint_id,
                "x-pagination": pagination,
                "x-error-codes": error_codes,
                "x-data-use-field-categories": sorted(DOMAIN_DATA_USE[domain]),
            }
            if request_ref:
                operation["requestBody"] = {"required": True, "content": {"application/json": {"schema": {"$ref": f"#/components/schemas/{request_ref}"}}}}
                operation["x-request-blueprint-id"] = request_blueprint_id
            projection = {
                "method": method_upper,
                "path": path,
                "operation_id": operation["operationId"],
                "domain": domain,
                "kind": kind,
                "success_status": status,
                "parameters": parameters,
                "request_body_required": operation.get("requestBody", {}).get("required") if request_ref else None,
                "security": operation["security"],
                "request_ref": request_ref,
                "request_blueprint_id": request_blueprint_id,
                "query_ref": query_ref,
                "response_ref": res_name,
                "response_blueprint_id": blueprint_id,
                "error_ref": error_name,
                "request_schema": schemas.get(request_ref) if request_ref else None,
                "query_schema": schemas.get(query_ref) if query_ref else None,
                "response_schema": schemas[res_name],
                "error_schema": schemas[error_name],
                "data_use_field_categories": operation["x-data-use-field-categories"],
            }
            operation["x-semantic-sha256"] = hashlib.sha256(json.dumps(projection, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
            semantic_rows.append(projection)
            blueprint_bindings.append({"method": method_upper, "path": path, "blueprint_id": blueprint_id})
            if request_blueprint_id is not None:
                request_blueprint_bindings.append({"method": method_upper, "path": path, "blueprint_id": request_blueprint_id})
            paths.setdefault(path, {})[method] = operation

    for canonical_operation_key, spec in SERVICE_AUTH_OPERATION_SPECS.items():
        method_upper, path = canonical_operation_key.split(" ", 1)
        method = method_upper.lower()
        operation_id = spec["operation_id"]
        req_name = schema_name(operation_id, "Request")
        res_name = schema_name(operation_id, "Response")
        error_name = schema_name(operation_id, "Error")
        request_blueprint_id, request_properties = semantic_request_properties(canonical_operation_key)
        body_contracts = [row for row in spec["request_field_contracts"] if row["location"] == "BODY"]
        if set(request_properties) != {row["wire_name"] for row in body_contracts}:
            raise ValueError(f"{canonical_operation_key} body field contract/request blueprint drift")
        schemas[req_name] = closed_object(request_properties)
        blueprint_id, response_properties = semantic_response_properties(canonical_operation_key)
        if set(response_properties) - {"schema_version", "trace_id"} != {row["wire_name"] for row in spec["response_field_contracts"]}:
            raise ValueError(f"{canonical_operation_key} response field contract/blueprint drift")
        schemas[res_name] = closed_object(response_properties)
        error_codes = spec["error_codes"]
        schemas[error_name] = closed_object(
            {
                "type": {"type": "string", "format": "uri"},
                "title": {"type": "string", "minLength": 1},
                "http_status": {"type": "integer", "minimum": 400, "maximum": 599},
                "code": {"type": "string", "enum": error_codes},
                "trace_id": UUID,
                "violations": {"type": "array", "items": closed_object({"field": {"type": "string"}, "rule": {"type": "string"}})},
            }
        )
        parameters = [
            {
                "name": row["wire_name"],
                "in": row["location"].lower(),
                "required": row["required"],
                "schema": deepcopy(row["schema"]),
            }
            for row in spec["request_field_contracts"]
            if row["location"] != "BODY"
        ]
        operation = {
            "operationId": operation_id,
            "summary": f"SERVICE-AUTH {path.rsplit('/', 1)[-1]} action",
            "parameters": parameters,
            "responses": {
                spec["success_status"]: {"description": "service authentication action response", "content": {"application/json": {"schema": {"$ref": f"#/components/schemas/{res_name}"}}}},
                "default": {"description": "service authentication closed error vocabulary", "content": {"application/problem+json": {"schema": {"$ref": f"#/components/schemas/{error_name}"}}}},
            },
            "security": deepcopy(spec["security"]),
            "x-service-only": True,
            "x-capability-id": "CAP-AUTH-SERVICE-V1",
            "x-authorization-contract-id": "AUTHZ-AUTH-SERVICE-V1",
            "x-reject-unknown-query": True,
            "x-owner-ids": ["OWN-ARCH", "OWN-SEC"],
            "x-requirement-ids": ["SIR-002", "SYS-NF-001"],
            "x-test-ids": ["T-API-001", "T-SEC-005"],
            "x-evidence-ids": ["EVD-API-001", "EVD-SEC-005"],
            "x-domain": "IDENTITY",
            "x-operation-kind": "ACTION",
            "x-response-blueprint-id": blueprint_id,
            "x-pagination": {"mode": "NONE"},
            "x-error-codes": error_codes,
            "x-data-use-field-categories": ["IDENTITY_CREDENTIAL"],
            "x-request-field-contracts": deepcopy(spec["request_field_contracts"]),
            "x-response-field-contracts": deepcopy(spec["response_field_contracts"]),
            "x-state-transition": spec["state_transition"],
            "x-replay-policy": spec["replay_policy"],
            "x-request-log-policy": spec["request_log_policy"],
            "requestBody": {"required": True, "content": {"application/json": {"schema": {"$ref": f"#/components/schemas/{req_name}"}}}},
            "x-request-blueprint-id": request_blueprint_id,
        }
        projection = {
            "method": method_upper,
            "path": path,
            "operation_id": operation_id,
            "domain": "IDENTITY",
            "kind": "ACTION",
            "success_status": spec["success_status"],
            "parameters": parameters,
            "request_body_required": True,
            "security": operation["security"],
            "request_ref": req_name,
            "request_blueprint_id": request_blueprint_id,
            "query_ref": None,
            "response_ref": res_name,
            "response_blueprint_id": blueprint_id,
            "error_ref": error_name,
            "request_schema": schemas[req_name],
            "query_schema": None,
            "response_schema": schemas[res_name],
            "error_schema": schemas[error_name],
            "data_use_field_categories": operation["x-data-use-field-categories"],
            "request_field_contracts": operation["x-request-field-contracts"],
            "response_field_contracts": operation["x-response-field-contracts"],
            "state_transition": operation["x-state-transition"],
            "replay_policy": operation["x-replay-policy"],
            "request_log_policy": operation["x-request-log-policy"],
        }
        operation["x-semantic-sha256"] = hashlib.sha256(json.dumps(projection, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
        semantic_rows.append(projection)
        blueprint_bindings.append({"method": method_upper, "path": path, "blueprint_id": blueprint_id})
        request_blueprint_bindings.append({"method": method_upper, "path": path, "blueprint_id": request_blueprint_id})
        paths.setdefault(path, {})[method] = operation
    aggregate = hashlib.sha256(json.dumps(sorted(semantic_rows, key=lambda row: (row["path"], row["method"])), ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    sorted_blueprint_bindings = sorted(blueprint_bindings, key=lambda row: (row["path"], row["method"]))
    blueprint_binding_digest = hashlib.sha256(json.dumps(sorted_blueprint_bindings, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    sorted_request_blueprint_bindings = sorted(request_blueprint_bindings, key=lambda row: (row["path"], row["method"]))
    request_blueprint_binding_digest = hashlib.sha256(json.dumps(sorted_request_blueprint_bindings, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    return {
        "openapi": "3.1.0",
        "info": {"title": "YOnLab AI Training Platform implementation contract", "version": "1.1.0"},
        "jsonSchemaDialect": "https://json-schema.org/draft/2020-12/schema",
        "servers": [{"url": "/"}],
        "paths": paths,
        "components": {"securitySchemes": {
            "bearerAuth": {"type": "http", "scheme": "bearer", "bearerFormat": "JWT"},
            "refreshCookie": {"type": "apiKey", "in": "cookie", "name": "yonlab_refresh"},
            "csrfHeader": {"type": "apiKey", "in": "header", "name": "X-CSRF-Token"},
        }, "schemas": schemas},
        "x-operation-count": sum(len(item) for item in paths.values()),
        "x-source-contract": "screen-route-contracts.json",
        "x-data-use-policy-registry": "data-use-policy-registry.json",
        "x-response-blueprint-contract": {
            "binding_count": 117,
            "fallback_count": 0,
            "blueprint_count": len(set(OPERATION_RESPONSE_BLUEPRINT_IDS.values())),
            "binding_sha256": blueprint_binding_digest,
            "bindings": sorted_blueprint_bindings,
        },
        "x-request-blueprint-contract": {
            "binding_count": 61,
            "fallback_count": 0,
            "blueprint_count": len(set(OPERATION_REQUEST_BLUEPRINT_IDS.values())),
            "get_request_body_count": 0,
            "binding_sha256": request_blueprint_binding_digest,
            "bindings": sorted_request_blueprint_bindings,
        },
        "x-semantic-contract": {"algorithm": "SHA-256", "canonicalization": "RFC8785-compatible integer/string subset", "operation_count": 117, "aggregate_sha256": aggregate},
    }
def generate_asyncapi() -> dict[str, Any]:
    def event(event_type: str, data: dict[str, Any], *, terminal: bool) -> dict[str, Any]:
        return closed_object(
            {
                "event_id": UUID,
                "event_type": {"const": event_type},
                "occurred_at": DATE_TIME,
                "trace_id": UUID,
                "sequence": {"type": "integer", "minimum": 0},
                "previous_event_id": {"oneOf": [UUID, {"type": "null"}]},
                "replayed": {"type": "boolean"},
                "terminal": {"const": terminal},
                "data": closed_object(data),
            }
        )
    variants = {
        "MessageDeltaEvent": event("message.delta", {"stream_id": UUID, "delta_text": {"type": "string", "minLength": 1, "maxLength": 20000}, "delta_index": {"type": "integer", "minimum": 0}}, terminal=False),
        "MessageCompletedEvent": event("message.completed", {"stream_id": UUID, "content_sha256": scalar_schema("content_sha256"), "finish_reason": {"enum": ["STOP", "LENGTH", "POLICY"]}, "total_sequence": {"type": "integer", "minimum": 1}}, terminal=True),
        "JobProgressEvent": event("job.progress", {"job_id": UUID, "stage_code": {"type": "string"}, "progress_microunit": scalar_schema("progress_microunit")}, terminal=False),
        "JobCompletedEvent": event("job.completed", {"job_id": UUID, "artifact_id": UUID, "artifact_sha256": scalar_schema("artifact_sha256")}, terminal=True),
        "ErrorEvent": event("error", {"code": {"type": "string", "pattern": "^[A-Z][A-Z0-9_]+$"}, "retryable": {"type": "boolean"}, "safe_message": {"type": "string"}}, terminal=True),
        "GapEvent": event("stream.gap", {"expected_sequence": {"type": "integer", "minimum": 0}, "received_sequence": {"type": "integer", "minimum": 1}, "resume_from_event_id": UUID}, terminal=False),
        "HeartbeatEvent": event("heartbeat", {"server_time": DATE_TIME}, terminal=False),
    }
    sse_payload = {"oneOf": [{"$ref": f"#/components/schemas/{name}"} for name in variants]}
    channels = {}
    for name, address, purpose in [
        ("diagnosisTurns", "/api/v1/diagnoses/{diagnosisId}/events", "Diagnosis turn streaming"),
        ("ragMessages", "/api/v1/rag/sessions/{sessionId}/events", "Grounded answer streaming"),
        ("jobProgress", "/api/v1/jobs/{jobId}/events", "Long-running job progress"),
    ]:
        channels[name] = {
            "address": address,
            "description": purpose,
            "parameters": {re.findall(r"\{([^}]+)\}", address)[0]: {"description": "Tenant-scoped UUID", "schema": UUID}},
            "messages": {"sseEvent": {"$ref": "#/components/messages/SseEvent"}},
            "x-last-event-id-required": True,
            "x-current-authorization-recheck": True,
            "x-gap-policy": "EMIT_STREAM_GAP_AND_REQUIRE_REPLAY",
            "x-terminal-event-required": True,
        }
    return {
        "asyncapi": "3.0.0",
        "info": {"title": "YOnLab SSE and job event contract", "version": "1.1.0"},
        "defaultContentType": "application/json",
        "channels": channels,
        "operations": {
            "receiveDiagnosisTurns": {"action": "receive", "channel": {"$ref": "#/channels/diagnosisTurns"}},
            "receiveRagMessages": {"action": "receive", "channel": {"$ref": "#/channels/ragMessages"}},
            "receiveJobProgress": {"action": "receive", "channel": {"$ref": "#/channels/jobProgress"}},
        },
        "components": {"messages": {"SseEvent": {"name": "SseEvent.v1", "payload": sse_payload}}, "schemas": variants},
        "x-stream-semantics": {
            "sequence_start": 0,
            "next_sequence_rule": "CURRENT_EQUALS_PREVIOUS_PLUS_ONE",
            "duplicate_rule": "SAME_EVENT_ID_AND_PAYLOAD_HASH_IS_IDEMPOTENT",
            "gap_event_type": "stream.gap",
            "replay_cursor_header": "Last-Event-ID",
            "replay_requires_current_authorization": True,
            "terminal_event_types": ["message.completed", "job.completed", "error"],
            "events_after_terminal": "REJECT",
        },
    }


DATA_USE_CATEGORY_SPECS: dict[str, tuple[str, bool, list[tuple[str, str, str]]]] = {
    "PUBLIC_CONTENT": ("PUBLIC", True, [("PUBLIC_CONTENT_ID", "ContentItem.id", "TOKENIZE"), ("PUBLIC_CONTENT_TEXT", "ContentItem.public_text", "PASS"), ("PUBLIC_RIGHTS_CODE", "RightsGrant.rights_code", "PASS")]),
    "IDENTITY_CREDENTIAL": ("RESTRICTED", False, [("SUBJECT_PSEUDONYM", "User.id", "HMAC_SHA256"), ("TENANT_PSEUDONYM", "Tenant.id", "HMAC_SHA256"), ("AUTH_FACTOR_RESULT", "MfaChallenge.result", "ENUM_ONLY")]),
    "TEACHER_CONTEXT": ("RESTRICTED", False, [("CAREER_BAND", "TeacherContext.career_band", "ENUM_ONLY"), ("REGION_CATEGORY", "Organization.region_category", "COARSE_ENUM"), ("WORK_CONSTRAINT_CODES", "TeacherContext.work_constraints", "ALLOWLIST")]),
    "DIAGNOSIS_DIALOGUE": ("RESTRICTED", False, [("DIALOGUE_TURN_TEXT", "DialogueTurn.content", "PII_REDACT"), ("DIALOGUE_TURN_SEQUENCE", "DialogueTurn.sequence", "PASS"), ("DIAGNOSIS_SESSION_PSEUDONYM", "DiagnosisSession.id", "HMAC_SHA256")]),
    "DIAGNOSIS_EVIDENCE": ("RESTRICTED", False, [("INDICATOR_CODE", "EvidenceSpan.indicator_id", "ALLOWLIST"), ("EVIDENCE_ANCHOR", "EvidenceSpan.anchor_id", "TOKENIZE"), ("EVIDENCE_SCORE", "EvidenceSpan.evidence_strength_microunit", "PASS")]),
    "RECOMMENDATION_FEATURE": ("CONFIDENTIAL", True, [("COMPETENCY_SCORE", "CompetencyScore.score_microunit", "PASS"), ("CONTENT_FEATURE_CODE", "ContentItem.recommendation_feature_codes", "ALLOWLIST"), ("LEARNING_CONSTRAINT_CODE", "LearningPath.constraint_codes", "ALLOWLIST")]),
    "LEARNING_ACTIVITY": ("CONFIDENTIAL", True, [("LEARNING_ACTIVITY_CODE", "LearningActivity.activity_type", "ALLOWLIST"), ("LEARNING_PROGRESS", "Enrollment.progress_microunit", "PASS"), ("PRACTICE_OUTCOME_CODE", "PracticeTask.outcome_code", "ALLOWLIST")]),
    "DOCUMENT_QUERY": ("CONFIDENTIAL", True, [("DOCUMENT_QUERY_TEXT", "RagSession.query", "PII_REDACT"), ("DOCUMENT_FILTER_CODE", "RagSession.filter_codes", "ALLOWLIST"), ("QUERY_TENANT_SCOPE", "RagSession.tenant_id", "HMAC_SHA256")]),
    "DOCUMENT_EVIDENCE": ("RESTRICTED", False, [("DOCUMENT_VERSION_PSEUDONYM", "DocumentVersion.id", "HMAC_SHA256"), ("DOCUMENT_CHUNK_TEXT", "Chunk.normalized_text", "PII_REDACT"), ("DOCUMENT_SOURCE_LOCATOR", "DocumentNode.source_locator", "TOKENIZE")]),
    "DRAFT_FIELD": ("RESTRICTED", False, [("DRAFT_TEMPLATE_FIELD", "TemplateVersion.field_values", "SCHEMA_ALLOWLIST"), ("DRAFT_EVIDENCE_REFERENCE", "GeneratedDraft.evidence_ids", "TOKENIZE"), ("DRAFT_SUBJECT_PSEUDONYM", "GeneratedDraft.user_id", "HMAC_SHA256")]),
    "OPERATIONAL_METADATA": ("INTERNAL", False, [("TRACE_PSEUDONYM", "TelemetrySignal.trace_id", "HMAC_SHA256"), ("OPERATION_METRIC_CODE", "TelemetrySignal.metric_code", "ALLOWLIST"), ("OPERATION_DURATION_MS", "TelemetrySignal.duration_ms", "PASS")]),
}


AI_TASK_DATA_USE = {
    "diagnosis.evidence.extract": ["TEACHER_CONTEXT", "DIAGNOSIS_DIALOGUE", "DIAGNOSIS_EVIDENCE"],
    "diagnosis.next_question.compose": ["TEACHER_CONTEXT", "DIAGNOSIS_EVIDENCE"],
    "persona.explanation.compose": ["TEACHER_CONTEXT", "DIAGNOSIS_EVIDENCE"],
    "recommendation.explanation.compose": ["DIAGNOSIS_EVIDENCE", "RECOMMENDATION_FEATURE"],
    "document.query.rewrite": ["DOCUMENT_QUERY"],
    "document.rerank": ["DOCUMENT_QUERY", "DOCUMENT_EVIDENCE"],
    "document.grounded_answer": ["DOCUMENT_QUERY", "DOCUMENT_EVIDENCE"],
    "draft.hwpx.section.compose": ["DOCUMENT_EVIDENCE", "DRAFT_FIELD"],
    "document.metadata.tag": ["DOCUMENT_EVIDENCE"],
}


def generate_data_use_policy(screen_registry: dict[str, Any]) -> dict[str, Any]:
    categories = []
    fields = []
    fields_by_category: dict[str, list[str]] = {}
    for category_id, (classification, external_allowed, field_specs) in DATA_USE_CATEGORY_SPECS.items():
        codes = [item[0] for item in field_specs]
        fields_by_category[category_id] = codes
        categories.append(
            {
                "category_id": category_id,
                "classification_floor": classification,
                "purpose_codes": [f"PURPOSE_{category_id}"],
                "field_codes": codes,
                "redaction_profile_id": f"REDACT-{category_id}-V1",
                "external_provider_allowed": external_allowed,
                "consent_required": classification in {"CONFIDENTIAL", "RESTRICTED"},
            }
        )
        for code, source, transform in field_specs:
            fields.append(
                {
                    "field_code": code,
                    "category_id": category_id,
                    "classification": classification,
                    "source_contract": source,
                    "provider_transform": transform,
                    "log_policy": "HASH_ONLY",
                }
            )
    operation_bindings = []
    for screen in screen_registry["screens"]:
        for operation in screen["operation_contracts"]:
            domain = operation_domain(screen["screen_id"], operation["path_template"])
            category_ids = sorted(DOMAIN_DATA_USE[domain])
            field_codes = sorted({code for category in category_ids for code in fields_by_category[category]})
            operation_bindings.append(
                {
                    "method": operation["method"],
                    "path": operation["path_template"],
                    "purpose_code": f"PURPOSE_OPERATION_{domain}",
                    "category_ids": category_ids,
                    "field_codes": field_codes,
                    "provider_call_allowed": bool(category_ids) and all(DATA_USE_CATEGORY_SPECS[item][1] for item in category_ids),
                }
            )
    task_bindings = []
    for task, category_ids in AI_TASK_DATA_USE.items():
        task_bindings.append(
            {
                "task": task,
                "purpose_code": f"PURPOSE_AI_{task.upper().replace('.', '_')}",
                "category_ids": category_ids,
                "field_codes": sorted({code for category in category_ids for code in fields_by_category[category]}),
            }
        )
    privileged_specs = [
        ("OP-DIAGNOSIS-OVERRIDE", "/internal/operations/v1/diagnosis-evidence-overrides", "diagnosis.evidence.override", "PURPOSE_DIAGNOSIS_OVERRIDE", ["DIAGNOSIS_EVIDENCE"], "INTERNAL_DIAGNOSIS_SERVICE"),
        ("OP-RUBRIC-PUBLISH", "/internal/operations/v1/rubric-publications", "rubric.version.publish", "PURPOSE_RUBRIC_PUBLISH", ["OPERATIONAL_METADATA"], "INTERNAL_POLICY_REGISTRY"),
        ("OP-EVAL-EXPORT", "/internal/operations/v1/evaluation-exports", "evaluation.export", "PURPOSE_EVALUATION_EXPORT", ["DIAGNOSIS_EVIDENCE", "RECOMMENDATION_FEATURE"], "APPROVED_EXPORT_VAULT"),
        ("OP-HWP-PUBLISH", "/internal/operations/v1/hwp-publications", "hwp.template.publish", "PURPOSE_HWP_PUBLISH", ["DOCUMENT_EVIDENCE", "DRAFT_FIELD"], "INTERNAL_DOCUMENT_SERVICE"),
        ("OP-PROVIDER-ACTIVATE", "/internal/operations/v1/provider-activations", "provider.deployment.activate", "PURPOSE_PROVIDER_ACTIVATE", ["OPERATIONAL_METADATA"], "INTERNAL_AI_CONTROL_PLANE"),
        ("OP-LINEAGE-DELETE", "/internal/operations/v1/lineage-deletions", "privacy.lineage.delete", "PURPOSE_LINEAGE_DELETE", ["IDENTITY_CREDENTIAL", "OPERATIONAL_METADATA"], "INTERNAL_PRIVACY_SERVICE"),
        ("OP-BACKUP-RESTORE", "/internal/operations/v1/backup-restores", "backup.restore", "PURPOSE_BACKUP_RESTORE", ["OPERATIONAL_METADATA"], "INTERNAL_RECOVERY_SERVICE"),
        ("OP-ADMIN-GRANT", "/internal/operations/v1/admin-role-grants", "identity.admin.grant", "PURPOSE_ADMIN_GRANT", ["IDENTITY_CREDENTIAL", "OPERATIONAL_METADATA"], "INTERNAL_IDENTITY_SERVICE"),
    ]
    privileged_bindings = [
        {
            "privileged_operation_id": operation_id,
            "canonical_http_operation_id": f"POST {path}",
            "method": "POST",
            "path": path,
            "task": task,
            "purpose_code": purpose,
            "category_ids": category_ids,
            "field_codes": sorted({code for category in category_ids for code in fields_by_category[category]}),
            "destination": destination,
            "provider_call_allowed": False,
        }
        for operation_id, path, task, purpose, category_ids, destination in privileged_specs
    ]
    return {
        "schema_version": "data-use-policy-registry.v1",
        "policy_version": "data-use-policy.v1.0.0",
        "unknown_category_policy": "DENY",
        "classification_vocabulary": ["PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"],
        "category_enum": [item["category_id"] for item in categories],
        "field_code_enum": [item["field_code"] for item in fields],
        "categories": categories,
        "fields": fields,
        "operation_bindings": operation_bindings,
        "privileged_operation_bindings": privileged_bindings,
        "ai_task_bindings": task_bindings,
        "redaction_receipt_contract": {
            "hash_algorithm": "SHA-256",
            "required_fields": ["receipt_id", "policy_version", "input_hash", "output_hash", "removed_field_codes", "decision", "provider_call_count"],
            "decision_enum": ["ALLOW", "REDACT_AND_ALLOW", "DENY"],
            "provider_call_count_on_denial": 0,
            "receipt_write_stage": "BEFORE_PROVIDER_CALL",
        },
    }
def task_contract(task: str, input_fields: dict[str, Any], output_fields: dict[str, Any]) -> dict[str, Any]:
    category_ids = AI_TASK_DATA_USE[task]
    field_codes = sorted({field[0] for category in category_ids for field in DATA_USE_CATEGORY_SPECS[category][2]})
    data_use_context = closed_object(
        {
            "policy_version": {"const": "data-use-policy.v1.0.0"},
            "purpose_code": {"const": f"PURPOSE_AI_{task.upper().replace('.', '_')}"},
            "category_ids": {"type": "array", "minItems": 1, "uniqueItems": True, "items": {"type": "string", "enum": category_ids}},
            "field_codes": {"type": "array", "minItems": 1, "uniqueItems": True, "items": {"type": "string", "enum": field_codes}},
            "classification": {"enum": ["PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"]},
            "subject_pseudonym": {"type": "string", "minLength": 32, "maxLength": 128},
            "tenant_pseudonym": {"type": "string", "minLength": 32, "maxLength": 128},
            "consent_epoch": {"type": "integer", "minimum": 0},
            "redaction_receipt_hash": scalar_schema("redaction_receipt_hash"),
        }
    )
    return {
        "task": task,
        "input_schema": closed_object({"data_use_context": data_use_context, **input_fields}),
        "output_schema": closed_object(output_fields),
        "repair_budget": 1,
        "fallback_requires_new_data_use_context": True,
        "data_use_contract": {
            "registry_ref": "data-use-policy-registry.json",
            "task": task,
            "category_ids": category_ids,
            "field_codes": field_codes,
        },
    }


def generate_ai_contracts() -> dict[str, Any]:
    string_array = {"type": "array", "minItems": 1, "items": {"type": "string", "minLength": 1}}
    evidence_array = {
        "type": "array",
        "items": closed_object(
            {
                "evidence_id": UUID,
                "dialogue_turn_id": UUID,
                "indicator_id": {"type": "string"},
                "anchor_id": {"type": "string"},
                "start_offset": {"type": "integer", "minimum": 0},
                "end_offset": {"type": "integer", "minimum": 1},
                "quoted_span_sha256": scalar_schema("quoted_span_sha256"),
                "entailment_microunit": scalar_schema("entailment_microunit"),
                "relevance_microunit": scalar_schema("relevance_microunit"),
                "specificity_microunit": scalar_schema("specificity_microunit"),
                "contradiction_risk_microunit": scalar_schema("contradiction_risk_microunit"),
                "evidence_strength_microunit": scalar_schema("evidence_strength_microunit"),
                "scoring_policy_version": {"const": "evidence-scoring.v1.0.0"},
                "eligibility_decision": {"enum": ["ELIGIBLE", "INSUFFICIENT", "CONTRADICTED", "INVALID"]},
            }
        ),
    }
    claim = closed_object({"claim_id": UUID, "claim_text": {"type": "string", "minLength": 1}, "importance": {"enum": ["IMPORTANT", "SUPPORTING"]}})
    citation = closed_object({"citation_id": UUID, "evidence_id": UUID, "document_version_id": UUID, "source_locator": {"type": "string"}, "source_sha256": scalar_schema("source_sha256"), "rights_snapshot_hash": scalar_schema("rights_snapshot_hash")})
    binding = closed_object({"claim_id": UUID, "citation_id": UUID, "evidence_id": UUID, "relation": {"enum": ["ENTAILS", "QUALIFIES", "CONTRADICTS"]}, "entailment_microunit": scalar_schema("entailment_microunit"), "rights_snapshot_hash": scalar_schema("rights_snapshot_hash")})
    tasks = [
        task_contract("diagnosis.evidence.extract", {"messages": string_array, "rubric_version": {"type": "string"}, "indicator_ids": string_array}, {"evidence": evidence_array, "needs_clarification": {"type": "boolean"}}),
        task_contract("diagnosis.next_question.compose", {"unmet_indicator_ids": string_array, "context_summary": {"type": "string"}}, {"question": {"type": "string"}, "target_indicator_id": {"type": "string"}, "safety_flags": {"type": "array", "items": {"type": "string"}}}),
        task_contract("persona.explanation.compose", {"profile_probabilities_microunit": {"type": "array", "minItems": 12, "maxItems": 12, "items": {"type": "integer", "minimum": 0, "maximum": 1_000_000}}, "supporting_factors": string_array}, {"summary": {"type": "string"}, "top_profile_ids": {"type": "array", "minItems": 3, "maxItems": 3, "items": {"type": "string"}}, "limitations": string_array}),
        task_contract("recommendation.explanation.compose", {"content_id": UUID, "feature_codes": string_array, "evidence_ids": string_array}, {"reason": {"type": "string"}, "expected_outcome": {"type": "string"}, "alternative_ids": {"type": "array", "items": UUID}}),
        task_contract("document.query.rewrite", {"query": {"type": "string", "minLength": 1}, "filters": closed_object({"document_types": {"type": "array", "items": {"type": "string"}}, "effective_at": DATE_TIME}, required=["document_types"])}, {"queries": {"type": "array", "minItems": 1, "maxItems": 5, "items": {"type": "string"}}, "preserved_constraints": string_array}),
        task_contract("document.rerank", {"query": {"type": "string"}, "candidate_ids": {"type": "array", "minItems": 1, "maxItems": 200, "items": UUID}}, {"ranked": {"type": "array", "items": closed_object({"candidate_id": UUID, "relevance_microunit": {"type": "integer", "minimum": 0, "maximum": 1_000_000}})}}),
        task_contract("document.grounded_answer", {"query": {"type": "string"}, "evidence_ids": string_array}, {"answer": {"type": "string"}, "claims": {"type": "array", "items": claim}, "citations": {"type": "array", "items": citation}, "claim_citation_bindings": {"type": "array", "items": binding}, "answerability_microunit": scalar_schema("answerability_microunit"), "important_claim_coverage_microunit": scalar_schema("important_claim_coverage_microunit"), "invalid_citation_count": {"type": "integer", "minimum": 0, "maximum": 0}, "limitations": {"type": "array", "items": {"type": "string"}}}),
        task_contract("draft.hwpx.section.compose", {"template_version_id": UUID, "section_id": {"type": "string"}, "evidence_ids": string_array, "field_values": closed_object({"title": {"type": "string"}, "body": {"type": "string"}})}, {"field_values": closed_object({"title": {"type": "string"}, "body": {"type": "string"}}), "citation_ids": string_array, "review_required": {"type": "boolean"}}),
        task_contract("document.metadata.tag", {"normalized_text": {"type": "string"}, "allowed_tag_codes": string_array}, {"tag_codes": {"type": "array", "uniqueItems": True, "items": {"type": "string"}}, "summary": {"type": "string"}}),
    ]
    endpoint_schema = {
        "responses": "CanonicalResponsesRequest.v1/CanonicalResponsesResponse.v1",
        "embeddings": "CanonicalEmbeddingsRequest.v1/CanonicalEmbeddingsResponse.v1",
        "rerank": "CanonicalRerankRequest.v1/CanonicalRerankResponse.v1",
    }
    return {
        "schema_version": "ai-service-contracts.v1",
        "endpoints": [
            {"method": "POST", "path": f"/internal/ai/v1/{name}", "contract": contract}
            for name, contract in endpoint_schema.items()
        ],
        "classification_vocabulary": ["PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"],
        "safeguarding_decisions": ["STANDARD", "CHILD_SAFEGUARDING", "IMMINENT_DANGER", "SECURITY_EXFILTRATION", "POLICY_BLOCK"],
        "data_use_policy_registry_ref": "data-use-policy-registry.json",
        "task_contracts": tasks,
        "embedding_contract": closed_object({"data_use_receipt_hash": scalar_schema("data_use_receipt_hash"), "texts": {"type": "array", "minItems": 1, "maxItems": 128, "items": {"type": "string"}}, "embedding_deployment_id": UUID, "normalization": {"enum": ["L2", "NONE"]}}),
        "rerank_contract": closed_object({"data_use_receipt_hash": scalar_schema("data_use_receipt_hash"), "query": {"type": "string"}, "candidate_ids": {"type": "array", "minItems": 1, "maxItems": 200, "items": UUID}, "reranker_deployment_id": UUID}),
        "evidence_scoring_contract": {
            "policy_version": "evidence-scoring.v1.0.0",
            "scale": 1_000_000,
            "formula": "round_half_up((entailment*400000 + relevance*250000 + specificity*200000 + (1000000-contradiction_risk)*150000)/1000000)",
            "offset_rule": "0 <= start_offset < end_offset <= normalized_turn_utf8_codepoint_length",
            "invalid_precedence": True,
        },
        "grounding_binding_contract": {
            "cardinality": "CLAIM_M:N_CITATION_VIA_BINDING",
            "unique_key": ["claim_id", "citation_id"],
            "orphan_policy": "REJECT",
            "important_claim_minimum_citations": 1,
            "citation_reuse_across_claims": True,
        },
        "response_invariants": {"unknown_fields": "REJECT", "provider_raw_response": "BOUNDARY_INTERNAL_ONLY", "all_objects_closed": True},
    }


RETENTION = {
    "PII": "RET-PII-3Y-OR-WITHDRAWAL",
    "DOMAIN": "RET-DOMAIN-3Y",
    "CONFIG": "RET-CONFIG-SUPERSEDED-3Y",
    "AUDIT": "RET-AUDIT-7Y",
    "EVIDENCE": "RET-EVIDENCE-1Y",
    "RECOVERY": "RET-RECOVERY-1Y",
}


def entity(
    entity_id: str,
    domain: str,
    classification: str,
    scope: str,
    extra_fields: list[tuple[str, str, bool]],
    *,
    retention: str = "DOMAIN",
    deletion: str = "VERSIONED_DELETE",
    parents: list[str] | None = None,
    classification_mode: str = "FIXED_FLOOR",
) -> dict[str, Any]:
    fields = []
    if scope == "TENANT":
        fields.append({"name": "tenant_id", "type": "uuid", "nullable": False})
    fields.append({"name": "id", "type": "uuid", "nullable": False})
    fields.extend({"name": name, "type": typ, "nullable": nullable} for name, typ, nullable in extra_fields)
    fields.extend(
        [
            {"name": "created_at", "type": "timestamptz", "nullable": False},
            {"name": "updated_at", "type": "timestamptz", "nullable": False},
            {"name": "row_version", "type": "bigint", "nullable": False},
        ]
    )
    primary_key = ["tenant_id", "id"] if scope == "TENANT" else ["id"]
    foreign_keys = []
    for parent in parents or []:
        column = re.sub(r"(?<!^)(?=[A-Z])", "_", parent).lower() + "_id"
        if column not in {field["name"] for field in fields}:
            fields.insert(len(primary_key), {"name": column, "type": "uuid", "nullable": False})
        foreign_keys.append(
            {
                "name": f"fk_{slug(entity_id).replace('-', '_')}_{slug(parent).replace('-', '_')}",
                "columns": (["tenant_id"] if scope == "TENANT" else []) + [column],
                "references": parent,
                "referenced_columns": (["tenant_id"] if scope == "TENANT" and parent != "User" else []) + ["id"],
                "on_delete": "RESTRICT",
            }
        )
    indexes = [{"name": f"ix_{slug(entity_id).replace('-', '_')}_updated", "columns": (["tenant_id"] if scope == "TENANT" else []) + ["updated_at"], "method": "btree", "unique": False}]
    unique_constraints = [{"name": f"uq_{slug(entity_id).replace('-', '_')}_identity_version", "columns": primary_key + ["row_version"]}]
    check_constraints = [
        {"name": f"ck_{slug(entity_id).replace('-', '_')}_row_version", "expression": "row_version >= 0", "enforcement": "DATABASE"},
        {"name": f"ck_{slug(entity_id).replace('-', '_')}_timestamps", "expression": "updated_at >= created_at", "enforcement": "DATABASE"},
    ]
    return {
        "entity_id": entity_id,
        "table_name": re.sub(r"(?<!^)(?=[A-Z])", "_", entity_id).lower(),
        "domain": domain,
        "classification_floor": classification,
        "classification_mode": classification_mode,
        "classification_source_entities": parents or [],
        "tenant_scope": scope,
        "retention_policy_id": RETENTION[retention],
        "deletion_policy": deletion,
        "primary_key": primary_key,
        "fields": fields,
        "foreign_keys": foreign_keys,
        "indexes": indexes,
        "unique_constraints": unique_constraints,
        "check_constraints": check_constraints,
        "retention_contract": {"policy_id": RETENTION[retention], "clock_start": "created_at", "legal_hold_override": True, "expiry_action": deletion},
        "delete_contract": {"strategy": deletion, "audit_ledger_required": True, "hard_delete_requires_expired_retention": True, "cross_tenant_cascade": "FORBIDDEN"},
        "cardinality": [f"{parent} 1:N {entity_id}" for parent in parents or []] or ["ROOT_OR_LOOKUP"],
        "rls_required": scope == "TENANT",
    }


def generate_entity_catalog() -> dict[str, Any]:
    specs: list[tuple[Any, ...]] = [
        ("User", "IDENTITY", "RESTRICTED", "GLOBAL", [("email_hash", "bytea", False), ("status", "varchar(32)", False)]),
        ("Tenant", "IDENTITY", "INTERNAL", "GLOBAL", [("code", "varchar(64)", False), ("acl_version", "bigint", False)]),
        ("Organization", "IDENTITY", "INTERNAL", "TENANT", [("name", "varchar(200)", False), ("region_category", "varchar(64)", True)], "DOMAIN", "VERSIONED_DELETE", ["Tenant"]),
        ("Membership", "IDENTITY", "CONFIDENTIAL", "TENANT", [("user_id", "uuid", False), ("organization_id", "uuid", False), ("membership_version", "bigint", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["Tenant", "User", "Organization"]),
        ("Role", "IDENTITY", "INTERNAL", "TENANT", [("code", "varchar(64)", False), ("policy_version", "varchar(64)", False)]),
        ("Permission", "IDENTITY", "INTERNAL", "GLOBAL", [("code", "varchar(128)", False)]),
        ("ConsentRecord", "IDENTITY", "RESTRICTED", "TENANT", [("user_id", "uuid", False), ("purpose", "varchar(128)", False), ("consent_epoch", "bigint", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["Tenant", "User"]),
        ("TeacherContext", "IDENTITY", "RESTRICTED", "TENANT", [("user_id", "uuid", False), ("career_band", "varchar(32)", True), ("constraints_json", "jsonb", True)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["Tenant", "User"]),
        ("PasswordCredential", "IDENTITY", "RESTRICTED", "GLOBAL", [("password_hash", "bytea", False), ("password_algorithm", "varchar(32)", False), ("password_changed_at", "timestamptz", False), ("failed_login_count", "integer", False), ("locked_until", "timestamptz", True)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User"]),
        ("DataProcessingRegistry", "GOVERNANCE", "INTERNAL", "GLOBAL", [("purpose_code", "varchar(128)", False), ("retention_policy_id", "varchar(128)", False), ("processor", "varchar(256)", False)], "CONFIG", "VERSIONED_DELETE"),
        ("SafeguardingCase", "SAFEGUARDING", "RESTRICTED", "TENANT", [("subject_pseudonym", "varchar(128)", False), ("decision", "varchar(64)", False), ("state", "varchar(32)", False), ("assigned_role", "varchar(64)", False), ("due_at", "timestamptz", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["Tenant", "User"]),
        ("CompetencyFramework", "DIAGNOSIS", "INTERNAL", "TENANT", [("version", "varchar(64)", False), ("state", "varchar(32)", False)]),
        ("CompetencyDimension", "DIAGNOSIS", "INTERNAL", "TENANT", [("code", "varchar(32)", False), ("weight_microunit", "integer", False)], "DOMAIN", "VERSIONED_DELETE", ["CompetencyFramework"]),
        ("RubricVersion", "DIAGNOSIS", "INTERNAL", "TENANT", [("semantic_version", "varchar(64)", False), ("content_hash", "bytea", False), ("state", "varchar(32)", False)], "CONFIG", "VERSIONED_DELETE", ["CompetencyFramework"]),
        ("DiagnosisSession", "DIAGNOSIS", "RESTRICTED", "TENANT", [("user_id", "uuid", False), ("state", "varchar(32)", False), ("consent_epoch", "bigint", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User", "RubricVersion"]),
        ("DialogueTurn", "DIAGNOSIS", "RESTRICTED", "TENANT", [("sequence", "integer", False), ("content_ref", "uuid", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["DiagnosisSession"]),
        ("EvidenceSpan", "DIAGNOSIS", "RESTRICTED", "TENANT", [("indicator_id", "varchar(64)", False), ("quoted_span", "text", False), ("confidence_microunit", "integer", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["DialogueTurn"]),
        ("DiagnosisResult", "DIAGNOSIS", "RESTRICTED", "TENANT", [("result_version", "integer", False), ("policy_hash", "bytea", False), ("status", "varchar(64)", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["DiagnosisSession"]),
        ("CompetencyScore", "DIAGNOSIS", "RESTRICTED", "TENANT", [("dimension_id", "uuid", False), ("score_microunit", "integer", True), ("level", "varchar(8)", True)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["DiagnosisResult"]),
        ("PersonaDefinition", "RECOMMENDATION", "INTERNAL", "GLOBAL", [("profile_id", "varchar(16)", False), ("version", "varchar(32)", False), ("policy_hash", "bytea", False)], "CONFIG", "VERSIONED_DELETE"),
        ("PersonaAssessment", "RECOMMENDATION", "RESTRICTED", "TENANT", [("probabilities_json", "jsonb", False), ("user_correction_json", "jsonb", True)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["DiagnosisResult"]),
        ("Course", "LEARNING", "INTERNAL", "TENANT", [("code", "varchar(64)", False), ("publication_state", "varchar(32)", False)]),
        ("ContentItem", "LEARNING", "INTERNAL", "TENANT", [("content_type", "varchar(64)", False), ("rights_state", "varchar(32)", False), ("publication_state", "varchar(32)", False)], "DOMAIN", "VERSIONED_DELETE", ["Course"]),
        ("Recommendation", "RECOMMENDATION", "RESTRICTED", "TENANT", [("rank", "integer", False), ("score_microunit", "integer", False), ("reason_features_json", "jsonb", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["DiagnosisResult", "ContentItem"]),
        ("LearningPath", "LEARNING", "CONFIDENTIAL", "TENANT", [("user_id", "uuid", False), ("state", "varchar(32)", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User"]),
        ("LearningPathStep", "LEARNING", "CONFIDENTIAL", "TENANT", [("sequence", "integer", False), ("required", "boolean", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["LearningPath", "ContentItem"]),
        ("Enrollment", "LEARNING", "CONFIDENTIAL", "TENANT", [("user_id", "uuid", False), ("state", "varchar(32)", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User", "Course"]),
        ("LearningActivity", "LEARNING", "CONFIDENTIAL", "TENANT", [("activity_type", "varchar(64)", False), ("occurred_at", "timestamptz", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["Enrollment"]),
        ("PracticeTask", "LEARNING", "RESTRICTED", "TENANT", [("submission_ref", "uuid", True), ("review_state", "varchar(32)", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["LearningPathStep"]),
        ("ReportSnapshot", "REPORTING", "CONFIDENTIAL", "TENANT", [("period_start", "timestamptz", False), ("period_end", "timestamptz", False), ("fact_version", "varchar(64)", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User"]),
        ("SourceDocument", "DOCUMENT", "RESTRICTED", "TENANT", [("title", "varchar(500)", False), ("classification", "varchar(32)", False), ("rights_state", "varchar(32)", False)]),
        ("DocumentVersion", "DOCUMENT", "RESTRICTED", "TENANT", [("source_sha256", "bytea", False), ("acl_version", "bigint", False), ("publication_state", "varchar(32)", False)], "DOMAIN", "VERSIONED_DELETE", ["SourceDocument"]),
        ("FileObject", "DOCUMENT", "RESTRICTED", "TENANT", [("object_key", "varchar(1024)", False), ("sha256", "bytea", False), ("mime_type", "varchar(128)", False)], "DOMAIN", "PURGE_BY_LINEAGE", ["DocumentVersion"], "MAX_OF_SOURCES"),
        ("ProcessingJob", "DOCUMENT", "INTERNAL", "TENANT", [("stage", "varchar(32)", False), ("state", "varchar(32)", False), ("attempt", "integer", False)], "DOMAIN", "VERSIONED_DELETE", ["DocumentVersion"], "MAX_OF_SOURCES"),
        ("Artifact", "DOCUMENT", "INTERNAL", "TENANT", [("artifact_type", "varchar(64)", False), ("sha256", "bytea", False), ("tool_version", "varchar(128)", False)], "DOMAIN", "PURGE_BY_LINEAGE", ["DocumentVersion", "ProcessingJob"], "MAX_OF_SOURCES"),
        ("DocumentNode", "DOCUMENT", "INTERNAL", "TENANT", [("node_type", "varchar(32)", False), ("locator_json", "jsonb", False), ("text", "text", False)], "DOMAIN", "PURGE_BY_LINEAGE", ["DocumentVersion"], "MAX_OF_SOURCES"),
        ("TableCell", "DOCUMENT", "INTERNAL", "TENANT", [("row_start", "integer", False), ("row_end", "integer", False), ("column_start", "integer", False), ("column_end", "integer", False)], "DOMAIN", "PURGE_BY_LINEAGE", ["DocumentNode"], "MAX_OF_SOURCES"),
        ("Chunk", "RETRIEVAL", "INTERNAL", "TENANT", [("content_hash", "bytea", False), ("acl_version", "bigint", False), ("normalized_text", "text", False)], "DOMAIN", "PURGE_BY_LINEAGE", ["DocumentVersion"], "MAX_OF_SOURCES"),
        ("EmbeddingRecord", "RETRIEVAL", "INTERNAL", "TENANT", [("deployment_id", "uuid", False), ("dimension", "integer", False), ("vector_ref", "uuid", False)], "DOMAIN", "PURGE_BY_LINEAGE", ["Chunk"], "MAX_OF_SOURCES"),
        ("IndexSnapshot", "RETRIEVAL", "INTERNAL", "TENANT", [("generation", "bigint", False), ("manifest_hash", "bytea", False), ("state", "varchar(32)", False)], "DOMAIN", "PURGE_BY_LINEAGE", ["DocumentVersion"], "MAX_OF_SOURCES"),
        ("Citation", "RETRIEVAL", "INTERNAL", "TENANT", [("claim_id", "uuid", False), ("locator_json", "jsonb", False), ("source_hash", "bytea", False), ("acl_version", "bigint", False)], "DOMAIN", "PURGE_BY_LINEAGE", ["DocumentVersion", "Claim"], "MAX_OF_SOURCES"),
        ("DraftTemplate", "DRAFT", "INTERNAL", "TENANT", [("document_type", "varchar(64)", False), ("state", "varchar(32)", False)]),
        ("TemplateVersion", "DRAFT", "INTERNAL", "TENANT", [("semantic_version", "varchar(64)", False), ("schema_hash", "bytea", False), ("state", "varchar(32)", False)], "CONFIG", "VERSIONED_DELETE", ["DraftTemplate"]),
        ("GeneratedDraft", "DRAFT", "RESTRICTED", "TENANT", [("state", "varchar(32)", False), ("artifact_ref", "uuid", True), ("watermarked", "boolean", False)], "PII", "PURGE_BY_LINEAGE", ["TemplateVersion", "User"], "MAX_OF_SOURCES"),
        ("ReviewDecision", "DRAFT", "CONFIDENTIAL", "TENANT", [("reviewer_user_id", "uuid", False), ("decision", "varchar(32)", False), ("reason", "text", False)], "DOMAIN", "IMMUTABLE_APPEND_ONLY", ["GeneratedDraft", "User"]),
        ("ModelProvider", "AI_GATEWAY", "INTERNAL", "GLOBAL", [("provider_code", "varchar(64)", False), ("contract_state", "varchar(32)", False)], "CONFIG", "VERSIONED_DELETE"),
        ("ModelDeployment", "AI_GATEWAY", "INTERNAL", "GLOBAL", [("deployment_revision", "varchar(128)", False), ("allowed_data_classes", "jsonb", False), ("state", "varchar(32)", False)], "CONFIG", "VERSIONED_DELETE", ["ModelProvider"]),
        ("RoutingPolicy", "AI_GATEWAY", "INTERNAL", "GLOBAL", [("semantic_version", "varchar(64)", False), ("policy_hash", "bytea", False), ("state", "varchar(32)", False)], "CONFIG", "VERSIONED_DELETE"),
        ("PromptVersion", "AI_GATEWAY", "INTERNAL", "GLOBAL", [("task", "varchar(128)", False), ("content_hash", "bytea", False), ("state", "varchar(32)", False)], "CONFIG", "VERSIONED_DELETE"),
        ("SchemaVersion", "AI_GATEWAY", "INTERNAL", "GLOBAL", [("schema_id", "varchar(256)", False), ("content_hash", "bytea", False), ("state", "varchar(32)", False)], "CONFIG", "VERSIONED_DELETE"),
        ("ModelRun", "AI_GATEWAY", "CONFIDENTIAL", "TENANT", [("task", "varchar(128)", False), ("input_hash", "bytea", False), ("output_hash", "bytea", False), ("cost_microunit", "bigint", False)], "EVIDENCE", "PURGE_BY_LINEAGE", ["ModelDeployment"]),
        ("EvaluationSuite", "AI_EVALUATION", "INTERNAL", "GLOBAL", [("suite_version", "varchar(64)", False), ("dataset_hash", "bytea", False)]),
        ("EvaluationRun", "AI_EVALUATION", "CONFIDENTIAL", "GLOBAL", [("candidate_digest", "bytea", False), ("result", "varchar(32)", False), ("evidence_hash", "bytea", False)], "EVIDENCE", "IMMUTABLE_APPEND_ONLY", ["EvaluationSuite"]),
        ("PilotCohort", "PILOT", "CONFIDENTIAL", "TENANT", [("round", "integer", False), ("state", "varchar(32)", False)]),
        ("Feedback", "PILOT", "RESTRICTED", "TENANT", [("participant_pseudonym", "varchar(128)", False), ("feedback_type", "varchar(64)", False), ("content_ref", "uuid", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["PilotCohort"]),
        ("Notification", "PORTAL", "CONFIDENTIAL", "TENANT", [("recipient_user_id", "uuid", False), ("channel", "varchar(32)", False), ("state", "varchar(32)", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User"]),
        ("Inquiry", "PORTAL", "RESTRICTED", "TENANT", [("requester_user_id", "uuid", False), ("state", "varchar(32)", False), ("content_ref", "uuid", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User"]),
        ("AuditEvent", "AUDIT", "CONFIDENTIAL", "TENANT", [("action", "varchar(128)", False), ("target_hash", "bytea", False), ("event_hash", "bytea", False)], "AUDIT", "IMMUTABLE_APPEND_ONLY"),
        ("OutboxEvent", "INTEGRATION", "INTERNAL", "TENANT", [("event_type", "varchar(128)", False), ("payload_schema", "varchar(128)", False), ("delivery_state", "varchar(32)", False)]),
        ("FeatureFlag", "OPERATIONS", "INTERNAL", "GLOBAL", [("code", "varchar(128)", False), ("state", "varchar(32)", False), ("effective_at", "timestamptz", False)], "CONFIG", "VERSIONED_DELETE"),
        ("DeletionLedger", "PRIVACY", "CONFIDENTIAL", "TENANT", [("target_keyed_hash", "bytea", False), ("state", "varchar(32)", False), ("receipt_hashes", "jsonb", False)], "AUDIT", "IMMUTABLE_APPEND_ONLY"),
        ("ObjectCapability", "DOCUMENT", "RESTRICTED", "TENANT", [("object_id", "uuid", False), ("operation", "varchar(32)", False), ("expires_at", "timestamptz", False)], "EVIDENCE", "CRYPTO_ERASE_OR_TOMBSTONE"),
        ("HwpConversionAttestation", "DOCUMENT", "CONFIDENTIAL", "TENANT", [("input_sha256", "bytea", False), ("output_sha256", "bytea", False), ("converter_digest", "bytea", False), ("signature", "bytea", False)], "EVIDENCE", "IMMUTABLE_APPEND_ONLY", ["DocumentVersion"]),
        ("BackupManifest", "OPERATIONS", "CONFIDENTIAL", "TENANT", [("backup_id", "uuid", False), ("manifest_hash", "bytea", False), ("completed_at", "timestamptz", False)], "RECOVERY", "IMMUTABLE_APPEND_ONLY"),
        ("RecoveryEvidence", "OPERATIONS", "CONFIDENTIAL", "TENANT", [("drill_id", "uuid", False), ("result", "varchar(32)", False), ("artifact_hash", "bytea", False)], "RECOVERY", "IMMUTABLE_APPEND_ONLY"),
        ("SecurityEvent", "SECURITY", "RESTRICTED", "TENANT", [("category", "varchar(64)", False), ("severity", "varchar(16)", False), ("details_hash", "bytea", False)], "AUDIT", "IMMUTABLE_APPEND_ONLY"),
        # Identity/operation records implied by the REST and lifecycle contracts.
        ("RefreshSession", "IDENTITY", "RESTRICTED", "TENANT", [("family_id", "uuid", False), ("token_hash", "bytea", False), ("expires_at", "timestamptz", False), ("revoked_at", "timestamptz", True)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User"]),
        ("PasswordResetToken", "IDENTITY", "RESTRICTED", "TENANT", [("token_hash", "bytea", False), ("expires_at", "timestamptz", False), ("consumed_at", "timestamptz", True)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User"]),
        ("MfaCredential", "IDENTITY", "RESTRICTED", "TENANT", [("credential_type", "varchar(32)", False), ("secret_ciphertext", "bytea", False), ("state", "varchar(32)", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User"]),
        ("MfaChallenge", "IDENTITY", "RESTRICTED", "TENANT", [("nonce_hash", "bytea", False), ("purpose", "varchar(64)", False), ("expires_at", "timestamptz", False), ("attempt_count", "integer", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User"]),
        ("IdempotencyRecord", "INTEGRATION", "CONFIDENTIAL", "TENANT", [("operation_id", "varchar(256)", False), ("key_hash", "bytea", False), ("response_hash", "bytea", True), ("expires_at", "timestamptz", False)], "EVIDENCE", "PURGE_BY_LINEAGE", ["User"]),
        ("EmailDelivery", "INTEGRATION", "CONFIDENTIAL", "TENANT", [("template_id", "varchar(128)", False), ("recipient_hash", "bytea", False), ("provider_message_hash", "bytea", True), ("state", "varchar(32)", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["Notification"]),
        ("ExportRequest", "PRIVACY", "RESTRICTED", "TENANT", [("scope", "varchar(128)", False), ("state", "varchar(32)", False), ("artifact_ref", "uuid", True), ("expires_at", "timestamptz", True)], "PII", "PURGE_BY_LINEAGE", ["User"]),
        ("DeletionRequest", "PRIVACY", "RESTRICTED", "TENANT", [("scope", "varchar(128)", False), ("state", "varchar(32)", False), ("verified_at", "timestamptz", True)], "AUDIT", "IMMUTABLE_APPEND_ONLY", ["User"]),
        ("FgiSession", "PILOT", "RESTRICTED", "TENANT", [("scheduled_at", "timestamptz", False), ("consent_version", "varchar(64)", False), ("transcript_ref", "uuid", True)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["PilotCohort"]),
        ("ImprovementIssue", "PILOT", "CONFIDENTIAL", "TENANT", [("category", "varchar(64)", False), ("priority", "varchar(16)", False), ("state", "varchar(32)", False), ("owner_id", "varchar(64)", False)], "DOMAIN", "VERSIONED_DELETE", ["PilotCohort"]),
        ("RightsGrant", "DOCUMENT", "CONFIDENTIAL", "TENANT", [("license_code", "varchar(128)", False), ("effective_at", "timestamptz", False), ("expires_at", "timestamptz", True), ("state", "varchar(32)", False)], "DOMAIN", "VERSIONED_DELETE", ["SourceDocument"]),
        ("RagSession", "RETRIEVAL", "RESTRICTED", "TENANT", [("user_id", "uuid", False), ("index_snapshot_id", "uuid", False), ("state", "varchar(32)", False)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["User", "IndexSnapshot"]),
        ("AnswerRun", "RETRIEVAL", "RESTRICTED", "TENANT", [("query_hash", "bytea", False), ("answerability_microunit", "integer", False), ("policy_version", "varchar(64)", False), ("state", "varchar(32)", False)], "PII", "PURGE_BY_LINEAGE", ["RagSession", "ModelRun"]),
        ("Claim", "RETRIEVAL", "RESTRICTED", "TENANT", [("claim_type", "varchar(64)", False), ("text_ref", "uuid", False), ("important", "boolean", False)], "PII", "PURGE_BY_LINEAGE", ["AnswerRun"]),
        ("RecommendationFeedback", "RECOMMENDATION", "RESTRICTED", "TENANT", [("decision", "varchar(32)", False), ("reason_ref", "uuid", True)], "PII", "CRYPTO_ERASE_OR_TOMBSTONE", ["Recommendation", "User"]),
        ("DraftExport", "DRAFT", "RESTRICTED", "TENANT", [("format", "varchar(16)", False), ("artifact_ref", "uuid", False), ("watermarked", "boolean", False), ("expires_at", "timestamptz", False)], "PII", "PURGE_BY_LINEAGE", ["GeneratedDraft", "User"]),
        # The 58-item requirement-facing catalog also contains governance,
        # verification and handover entities.  They are physical evidence
        # records, not aliases, so the DDL catalog closes them explicitly.
        ("AccessibilityEvidence", "VERIFICATION", "INTERNAL", "GLOBAL", [("evidence_hash", "bytea", False), ("viewport", "varchar(32)", False), ("result", "varchar(16)", False)], "EVIDENCE", "IMMUTABLE_APPEND_ONLY"),
        ("AdapterContract", "INTEGRATION", "INTERNAL", "GLOBAL", [("adapter_type", "varchar(64)", False), ("schema_version", "varchar(64)", False), ("state", "varchar(32)", False)], "CONFIG", "VERSIONED_DELETE"),
        ("ApiOperation", "INTERFACE", "INTERNAL", "GLOBAL", [("method", "varchar(16)", False), ("path_template", "varchar(512)", False), ("contract_hash", "bytea", False)], "CONFIG", "VERSIONED_DELETE"),
        ("CleanRoomEvidence", "GOVERNANCE", "INTERNAL", "GLOBAL", [("source_manifest_hash", "bytea", False), ("review_result", "varchar(32)", False)], "AUDIT", "IMMUTABLE_APPEND_ONLY"),
        ("DataDictionaryEntry", "DATA_GOVERNANCE", "INTERNAL", "GLOBAL", [("term_code", "varchar(128)", False), ("definition", "text", False), ("schema_version", "varchar(64)", False)], "CONFIG", "VERSIONED_DELETE"),
        ("DataQualityResult", "DATA_GOVERNANCE", "CONFIDENTIAL", "TENANT", [("rule_id", "varchar(128)", False), ("result", "varchar(16)", False), ("failure_count", "bigint", False)], "EVIDENCE", "IMMUTABLE_APPEND_ONLY"),
        ("DeploymentProfile", "OPERATIONS", "INTERNAL", "GLOBAL", [("environment", "varchar(32)", False), ("topology_hash", "bytea", False), ("state", "varchar(32)", False)], "CONFIG", "VERSIONED_DELETE"),
        ("DomainAggregate", "ARCHITECTURE", "INTERNAL", "GLOBAL", [("aggregate_name", "varchar(128)", False), ("contract_hash", "bytea", False)], "CONFIG", "VERSIONED_DELETE"),
        ("GovernanceRecord", "GOVERNANCE", "CONFIDENTIAL", "GLOBAL", [("record_type", "varchar(64)", False), ("decision", "varchar(32)", False), ("evidence_hash", "bytea", False)], "AUDIT", "IMMUTABLE_APPEND_ONLY"),
        ("HandoverArtifact", "HANDOVER", "CONFIDENTIAL", "GLOBAL", [("artifact_path", "varchar(1024)", False), ("sha256", "bytea", False), ("acceptance_state", "varchar(32)", False)], "EVIDENCE", "IMMUTABLE_APPEND_ONLY"),
        ("Migration", "DATA", "INTERNAL", "GLOBAL", [("revision", "varchar(128)", False), ("down_revision", "varchar(128)", True), ("checksum", "bytea", False)], "CONFIG", "IMMUTABLE_APPEND_ONLY"),
        ("PerformanceEvidence", "VERIFICATION", "INTERNAL", "GLOBAL", [("scenario_id", "varchar(128)", False), ("topology_hash", "bytea", False), ("result_hash", "bytea", False)], "EVIDENCE", "IMMUTABLE_APPEND_ONLY"),
        ("ProjectControl", "GOVERNANCE", "INTERNAL", "GLOBAL", [("control_id", "varchar(128)", False), ("owner_id", "varchar(64)", False), ("state", "varchar(32)", False)], "DOMAIN", "VERSIONED_DELETE"),
        ("QualityGate", "VERIFICATION", "INTERNAL", "GLOBAL", [("gate_id", "varchar(128)", False), ("candidate_digest", "bytea", False), ("result", "varchar(16)", False)], "EVIDENCE", "IMMUTABLE_APPEND_ONLY"),
        ("RequirementTrace", "GOVERNANCE", "INTERNAL", "GLOBAL", [("requirement_id", "varchar(64)", False), ("design_ref", "varchar(512)", False), ("test_id", "varchar(64)", False)], "CONFIG", "VERSIONED_DELETE"),
        ("SecurityControl", "SECURITY", "CONFIDENTIAL", "GLOBAL", [("control_id", "varchar(128)", False), ("implementation_hash", "bytea", False), ("state", "varchar(32)", False)], "CONFIG", "VERSIONED_DELETE"),
        ("ServiceHealth", "OPERATIONS", "INTERNAL", "GLOBAL", [("service_id", "varchar(128)", False), ("observed_at", "timestamptz", False), ("state", "varchar(32)", False)], "EVIDENCE", "PURGE_BY_LINEAGE"),
        ("TelemetrySignal", "OBSERVABILITY", "CONFIDENTIAL", "TENANT", [("signal_type", "varchar(32)", False), ("trace_id", "uuid", True), ("payload_hash", "bytea", False)], "EVIDENCE", "PURGE_BY_LINEAGE"),
        ("TestEvidence", "VERIFICATION", "INTERNAL", "GLOBAL", [("test_id", "varchar(64)", False), ("candidate_digest", "bytea", False), ("result", "varchar(16)", False), ("artifact_hash", "bytea", False)], "EVIDENCE", "IMMUTABLE_APPEND_ONLY"),
        ("VersionManifest", "RELEASE", "INTERNAL", "GLOBAL", [("release_id", "varchar(128)", False), ("source_tree_hash", "bytea", False), ("manifest_hash", "bytea", False)], "EVIDENCE", "IMMUTABLE_APPEND_ONLY"),
    ]
    entities = []
    for spec in specs:
        base = spec[:5]
        optional = list(spec[5:])
        retention = optional[0] if len(optional) > 0 else "DOMAIN"
        deletion = optional[1] if len(optional) > 1 else "VERSIONED_DELETE"
        parents = optional[2] if len(optional) > 2 else None
        mode = optional[3] if len(optional) > 3 else "FIXED_FLOOR"
        entities.append(entity(*base, retention=retention, deletion=deletion, parents=parents, classification_mode=mode))

    # Normalize every FK against the referenced entity's actual key shape.
    # This prevents accidental tenant_id duplication for Tenant itself and
    # prevents tenant-scoped children from pretending that GLOBAL parents use
    # composite keys.
    scope_by_entity = {item["entity_id"]: item["tenant_scope"] for item in entities}
    for item in entities:
        field_names = {field["name"] for field in item["fields"]}
        for foreign_key in item["foreign_keys"]:
            parent = foreign_key["references"]
            if parent == "Tenant":
                columns = ["tenant_id"]
            else:
                parent_column = re.sub(r"(?<!^)(?=[A-Z])", "_", parent).lower() + "_id"
                columns = [parent_column]
                if scope_by_entity[parent] == "TENANT":
                    columns.insert(0, "tenant_id")
            if not set(columns).issubset(field_names):
                raise ValueError(f"{item['entity_id']} FK {parent} lacks local columns {columns}")
            foreign_key["columns"] = columns
            foreign_key["referenced_columns"] = ["tenant_id", "id"] if scope_by_entity[parent] == "TENANT" else ["id"]

    by_id = {item["entity_id"]: item for item in entities}

    def add_field(entity_id: str, name: str, typ: str, nullable: bool, **contract: Any) -> None:
        item = by_id[entity_id]
        existing = next((field for field in item["fields"] if field["name"] == name), None)
        if existing is None:
            existing = {"name": name, "type": typ, "nullable": nullable}
            item["fields"].insert(max(2, len(item["fields"]) - 3), existing)
        existing.update(contract)

    for name, typ, nullable, security in [
        ("password_hash", "bytea", False, {"secret": True, "write_only": True, "log_policy": "NEVER"}),
        ("password_algorithm", "varchar(32)", False, {"allowed_values": ["ARGON2ID"]}),
        ("password_changed_at", "timestamptz", False, {}),
        ("failed_login_count", "integer", False, {"minimum": 0}),
        ("locked_until", "timestamptz", True, {}),
    ]:
        add_field("PasswordCredential", name, typ, nullable, **security)
    for name, typ, nullable in [
        ("rotated_from_id", "uuid", True), ("issued_at", "timestamptz", False),
        ("reuse_detected_at", "timestamptz", True), ("user_agent_hash", "bytea", False),
        ("ip_prefix_hash", "bytea", False),
    ]:
        add_field("RefreshSession", name, typ, nullable, secret=name.endswith("hash"), log_policy="HASH_ONLY" if name.endswith("hash") else "METADATA_ONLY")
    add_field("PasswordResetToken", "requested_ip_hash", "bytea", False, secret=True, log_policy="HASH_ONLY")
    for name, typ, nullable, contract in [
        ("factor_type", "varchar(32)", False, {"allowed_values": ["TOTP", "WEBAUTHN"]}),
        ("encryption_key_id", "varchar(128)", False, {"log_policy": "METADATA_ONLY"}),
        ("verified_at", "timestamptz", True, {}),
    ]:
        add_field("MfaCredential", name, typ, nullable, **contract)
    add_field("MfaCredential", "secret_ciphertext", "bytea", False, secret=True, encrypted_at_rest=True, log_policy="NEVER")
    add_field("MfaChallenge", "challenge_hash", "bytea", False, secret=True, log_policy="HASH_ONLY")
    add_field("MfaChallenge", "consumed_at", "timestamptz", True)
    for name, typ in [
        ("indicator_catalog", "RubricIndicator[]"),
        ("evidence_anchor_catalog", "EvidenceAnchorRule[]"),
        ("question_catalog", "DiagnosticQuestion[]"),
        ("scoring_policy_version", "varchar(64)"),
        ("indicator_catalog_digest", "bytea"),
        ("anchor_catalog_digest", "bytea"),
        ("question_catalog_digest", "bytea"),
        ("artifact_digest", "bytea"),
    ]:
        add_field("RubricVersion", name, typ, False, storage_type="jsonb" if typ.endswith("[]") else typ)
    for name, typ, nullable in [
        ("anchor_id", "varchar(128)", False), ("anchor_type", "varchar(32)", False),
        ("start_offset", "integer", False), ("end_offset", "integer", False),
        ("source_text_sha256", "bytea", False), ("extraction_policy_version", "varchar(64)", False),
        ("evidence_strength_microunit", "integer", False),
        ("turn_sequence", "integer", False),
    ]:
        add_field("EvidenceSpan", name, typ, nullable)
    for name, typ, nullable, contract in [
        ("confidence_microunit", "integer", False, {"minimum": 0, "maximum": 1_000_000}),
        ("conflict_decision", "varchar(32)", False, {"allowed_values": ["NONE", "REVIEW_REQUIRED", "INSUFFICIENT_EVIDENCE"]}),
        ("evidence_coverage_microunit", "integer", False, {"minimum": 0, "maximum": 1_000_000}),
        ("decision", "varchar(32)", False, {"allowed_values": ["FINAL", "REVIEW_REQUIRED", "INSUFFICIENT_EVIDENCE"]}),
    ]:
        add_field("CompetencyScore", name, typ, nullable, **contract)
    for name, typ, nullable, contract in [
        ("feature_coefficient_catalog", "PersonaFeatureCoefficient[]", False, {"storage_type": "jsonb", "immutable": True}),
        ("feature_coefficients_hash", "bytea", False, {"immutable": True}),
        ("artifact_digest", "bytea", False, {"immutable": True}),
    ]:
        add_field("PersonaDefinition", name, typ, nullable, **contract)
    for name, typ, nullable in [
        ("recommendation_feature_codes", "varchar(64)[]", False),
        ("competency_codes", "varchar(64)[]", False),
        ("modality_code", "varchar(32)", False), ("duration_minutes", "integer", False),
        ("difficulty_level", "varchar(32)", False),
        ("prerequisite_codes", "varchar(64)[]", False),
        ("accessibility_features", "varchar(64)[]", False),
        ("region_availability_codes", "varchar(64)[]", False),
    ]:
        add_field("ContentItem", name, typ, nullable)
    for name, typ, nullable in [
        ("dag_node_key", "varchar(128)", False), ("topological_rank", "integer", False),
    ]:
        add_field("LearningPathStep", name, typ, nullable)
    for name, typ, nullable in [
        ("parent_node_id", "uuid", True), ("node_path", "ltree", False),
        ("sibling_order", "integer", False), ("source_artifact_id", "uuid", False),
        ("source_locator", "varchar(2048)", False), ("source_sha256", "bytea", False),
        ("extraction_engine", "varchar(128)", False), ("extraction_version", "varchar(64)", False),
        ("style_ref", "varchar(512)", True), ("structure_confidence_microunit", "integer", False),
    ]:
        add_field("DocumentNode", name, typ, nullable)
    for name, typ, nullable, contract in [
        ("quoted_span", "text", False, {}),
        ("entailment_microunit", "integer", False, {"minimum": 0, "maximum": 1_000_000}),
        ("rights_current", "boolean", False, {}),
    ]:
        add_field("Citation", name, typ, nullable, **contract)

    # Replace generic identity-version uniqueness with implementable natural keys
    # for the aggregates whose lookup and version semantics are externally visible.
    natural_unique = {
        "User": ["email_hash"], "PasswordCredential": ["user_id"], "Tenant": ["code"], "Role": ["tenant_id", "code"],
        "Permission": ["code"], "CompetencyFramework": ["tenant_id", "version"],
        "CompetencyDimension": ["tenant_id", "competency_framework_id", "code"],
        "RubricVersion": ["tenant_id", "competency_framework_id", "semantic_version"],
        "DialogueTurn": ["tenant_id", "diagnosis_session_id", "sequence"],
        "EvidenceSpan": ["tenant_id", "dialogue_turn_id", "indicator_id", "start_offset", "end_offset"],
        "PersonaDefinition": ["profile_id", "version"], "Course": ["tenant_id", "code"],
        "LearningPathStep": ["tenant_id", "learning_path_id", "dag_node_key"],
        "DocumentVersion": ["tenant_id", "source_document_id", "source_sha256"],
        "FileObject": ["tenant_id", "object_key"], "DocumentNode": ["tenant_id", "document_version_id", "node_path"],
        "Chunk": ["tenant_id", "document_version_id", "content_hash"],
        "RefreshSession": ["tenant_id", "token_hash"], "PasswordResetToken": ["tenant_id", "token_hash"],
        "MfaChallenge": ["tenant_id", "challenge_hash"],
    }
    for entity_id, columns in natural_unique.items():
        by_id[entity_id]["unique_constraints"] = [{"name": f"uq_{slug(entity_id).replace('-', '_')}_natural", "columns": columns}]

    by_id["DialogueTurn"]["unique_constraints"].append(
        {"name": "uq_dialogue_turn_order_reference", "columns": ["tenant_id", "id", "sequence"]}
    )
    by_id["LearningPathStep"]["unique_constraints"].append(
        {"name": "uq_learning_path_step_edge_reference", "columns": ["tenant_id", "learning_path_id", "id"]}
    )
    by_id["EvidenceSpan"]["foreign_keys"].append(
        {
            "name": "fk_evidence_span_dialogue_turn_sequence",
            "columns": ["tenant_id", "dialogue_turn_id", "turn_sequence"],
            "references": "DialogueTurn",
            "referenced_columns": ["tenant_id", "id", "sequence"],
            "on_delete": "RESTRICT",
        }
    )

    by_id["EvidenceSpan"]["check_constraints"].extend([
        {"name": "ck_evidence_span_offsets", "expression": "start_offset >= 0 AND end_offset > start_offset", "enforcement": "DATABASE"},
        {"name": "ck_evidence_span_scores", "expression": "confidence_microunit BETWEEN 0 AND 1000000 AND evidence_strength_microunit BETWEEN 0 AND 1000000", "enforcement": "DATABASE"},
        {"name": "ck_evidence_span_turn_sequence", "expression": "turn_sequence >= 0", "enforcement": "DATABASE"},
    ])
    by_id["LearningPathStep"]["check_constraints"].append({"name": "ck_learning_path_step_dag", "expression": "topological_rank >= 0", "enforcement": "DATABASE_AND_SERVICE"})
    by_id["DocumentNode"]["check_constraints"].extend([
        {"name": "ck_document_node_topology", "expression": "sibling_order >= 0 AND node_path IS NOT NULL", "enforcement": "DATABASE_AND_SERVICE"},
        {"name": "ck_document_node_structure_confidence", "expression": "structure_confidence_microunit BETWEEN 0 AND 1000000", "enforcement": "DATABASE"},
    ])
    by_id["ContentItem"]["check_constraints"].append({"name": "ck_content_item_recommendation_features", "expression": "cardinality(recommendation_feature_codes) > 0 AND duration_minutes > 0 AND prerequisite_codes IS NOT NULL AND accessibility_features IS NOT NULL AND region_availability_codes IS NOT NULL", "enforcement": "DATABASE"})
    by_id["CompetencyScore"]["check_constraints"].append({"name": "ck_competency_score_confidence_coverage", "expression": "confidence_microunit BETWEEN 0 AND 1000000 AND evidence_coverage_microunit BETWEEN 0 AND 1000000 AND (score_microunit IS NULL OR score_microunit BETWEEN 0 AND 1000000)", "enforcement": "DATABASE"})
    by_id["Citation"]["check_constraints"].append({"name": "ck_citation_entailment", "expression": "entailment_microunit BETWEEN 0 AND 1000000 AND char_length(quoted_span) > 0", "enforcement": "DATABASE"})
    by_id["PasswordCredential"]["check_constraints"].append({"name": "ck_password_credential_policy", "expression": "password_algorithm = 'ARGON2ID' AND failed_login_count >= 0", "enforcement": "DATABASE"})

    constraint_names: set[str] = set()
    index_names: set[str] = set()
    for item in entities:
        field_name_list = [field["name"] for field in item["fields"]]
        if len(field_name_list) != len(set(field_name_list)):
            raise ValueError(f"{item['entity_id']} field names are not unique")
        field_names = set(field_name_list)
        field_by_name = {field["name"]: field for field in item["fields"]}
        if any(field_by_name[column]["nullable"] is not False for column in item["primary_key"]):
            raise ValueError(f"{item['entity_id']} primary key column is nullable")
        for foreign_key in item["foreign_keys"]:
            local_columns = foreign_key["columns"]
            referenced_columns = foreign_key["referenced_columns"]
            target = by_id[foreign_key["references"]]
            target_fields = {field["name"]: field for field in target["fields"]}
            candidate_keys = [target["primary_key"]] + [row["columns"] for row in target["unique_constraints"]]
            if len(local_columns) != len(referenced_columns):
                raise ValueError(f"{item['entity_id']} foreign key arity mismatch")
            if not set(local_columns).issubset(field_names) or not set(referenced_columns).issubset(target_fields):
                raise ValueError(f"{item['entity_id']} foreign key field missing")
            if referenced_columns not in candidate_keys:
                raise ValueError(f"{item['entity_id']} foreign key target is not PK/UNIQUE")
            if any(field_by_name[local]["type"] != target_fields[remote]["type"] for local, remote in zip(local_columns, referenced_columns)):
                raise ValueError(f"{item['entity_id']} foreign key type mismatch")
            if foreign_key["name"] in constraint_names:
                raise ValueError(f"duplicate constraint name {foreign_key['name']}")
            constraint_names.add(foreign_key["name"])
        for unique in item["unique_constraints"]:
            if not set(unique["columns"]).issubset(field_names):
                raise ValueError(f"{item['entity_id']} unique constraint lacks fields {unique['columns']}")
            if unique["name"] in constraint_names:
                raise ValueError(f"duplicate constraint name {unique['name']}")
            constraint_names.add(unique["name"])
        for check in item["check_constraints"]:
            if check["name"] in constraint_names:
                raise ValueError(f"duplicate constraint name {check['name']}")
            constraint_names.add(check["name"])
        for index in item["indexes"]:
            index.setdefault("method", "btree")
            index.setdefault("unique", False)
            if index["name"] in index_names:
                raise ValueError(f"duplicate index name {index['name']}")
            index_names.add(index["name"])

    value_object_contracts = {
        "RubricIndicator": closed_object({"indicator_id": {"type": "string"}, "dimension_code": {"type": "string"}, "weight_microunit": scalar_schema("weight_microunit"), "required_evidence_count": {"type": "integer", "minimum": 1}, "level_thresholds_microunit": {"type": "array", "minItems": 4, "maxItems": 4, "items": scalar_schema("threshold_microunit")}}),
        "EvidenceAnchorRule": closed_object({"anchor_id": {"type": "string"}, "indicator_id": {"type": "string"}, "anchor_type": {"enum": ["EXACT_SPAN", "TURN", "STRUCTURED_FACT"]}, "minimum_span_codepoints": {"type": "integer", "minimum": 1}, "maximum_span_codepoints": {"type": "integer", "minimum": 1}}),
        "DiagnosticQuestion": closed_object({"question_id": {"type": "string"}, "indicator_id": {"type": "string"}, "prompt_ko": {"type": "string"}, "priority": {"type": "integer", "minimum": 0}, "prohibited_probe_codes": {"type": "array", "items": {"type": "string"}}}),
        "LearningDagEdge": closed_object({"from_step_id": UUID, "to_step_id": UUID, "edge_type": {"enum": ["PREREQUISITE", "RECOMMENDED"]}, "minimum_score_microunit": scalar_schema("minimum_score_microunit")}),
        "DocumentProvenance": closed_object({"document_version_id": UUID, "artifact_id": UUID, "source_locator": {"type": "string"}, "source_sha256": scalar_schema("source_sha256"), "engine": {"type": "string"}, "engine_version": {"type": "string"}}),
        "PersonaFeatureCoefficient": closed_object({"feature_code": {"type": "string"}, "coefficient_microunit": {"type": "integer", "minimum": -1_000_000, "maximum": 1_000_000}, "normalization_policy_version": {"type": "string"}}),
    }
    association_contracts = {
        "LearningPathStepDependency": {
            "table_name": "learning_path_step_dependency",
            "fields": [
                {"name": "tenant_id", "type": "uuid", "nullable": False},
                {"name": "learning_path_id", "type": "uuid", "nullable": False},
                {"name": "predecessor_step_id", "type": "uuid", "nullable": False},
                {"name": "successor_step_id", "type": "uuid", "nullable": False},
                {"name": "edge_type", "type": "varchar(32)", "nullable": False},
            ],
            "primary_key": ["tenant_id", "learning_path_id", "predecessor_step_id", "successor_step_id"],
            "foreign_keys": [
                {"name": "fk_learning_edge_predecessor", "columns": ["tenant_id", "learning_path_id", "predecessor_step_id"], "references": "LearningPathStep", "referenced_columns": ["tenant_id", "learning_path_id", "id"], "on_delete": "CASCADE"},
                {"name": "fk_learning_edge_successor", "columns": ["tenant_id", "learning_path_id", "successor_step_id"], "references": "LearningPathStep", "referenced_columns": ["tenant_id", "learning_path_id", "id"], "on_delete": "CASCADE"},
            ],
            "check_constraints": [
                {"name": "ck_learning_edge_no_self", "expression": "predecessor_step_id <> successor_step_id", "enforcement": "DATABASE"},
                {"name": "ck_learning_edge_acyclic", "expression": "DEFERRED_CONSTRAINT_TRIGGER_REJECTS_TRANSITIVE_CYCLE", "enforcement": "DATABASE_AND_SERVICE"},
            ],
            "rls_required": True,
            "array_fk_forbidden": True,
        }
    }
    for association_id, association in association_contracts.items():
        association_fields = {field["name"]: field for field in association["fields"]}
        if len(association_fields) != len(association["fields"]):
            raise ValueError(f"{association_id} field names are not unique")
        if any(association_fields[column]["nullable"] is not False for column in association["primary_key"]):
            raise ValueError(f"{association_id} primary key column is nullable")
        for foreign_key in association["foreign_keys"]:
            target = by_id[foreign_key["references"]]
            target_fields = {field["name"]: field for field in target["fields"]}
            candidate_keys = [target["primary_key"]] + [row["columns"] for row in target["unique_constraints"]]
            if len(foreign_key["columns"]) != len(foreign_key["referenced_columns"]) or foreign_key["referenced_columns"] not in candidate_keys:
                raise ValueError(f"{association_id} foreign key arity/target invalid")
            if any(association_fields[local]["type"] != target_fields[remote]["type"] for local, remote in zip(foreign_key["columns"], foreign_key["referenced_columns"])):
                raise ValueError(f"{association_id} foreign key type mismatch")
            if foreign_key["name"] in constraint_names:
                raise ValueError(f"duplicate constraint name {foreign_key['name']}")
            constraint_names.add(foreign_key["name"])
        for check in association["check_constraints"]:
            if check["name"] in constraint_names:
                raise ValueError(f"duplicate constraint name {check['name']}")
            constraint_names.add(check["name"])
    immutable_artifact_contracts = {
        "RubricVersion": {
            "value_object_fields": ["indicator_catalog", "evidence_anchor_catalog", "question_catalog"],
            "digest_fields": ["indicator_catalog_digest", "anchor_catalog_digest", "question_catalog_digest", "artifact_digest"],
            "digest_algorithm": "SHA-256",
            "canonicalization": "RFC8785-compatible integer/string subset",
            "mutation_rule": "ACTIVE_OR_SUPERSEDED_ROWS_ARE_IMMUTABLE; CHANGES_CREATE_NEW_SEMANTIC_VERSION",
            "foreign_reference_rule": "DiagnosisSession.rubric_version_id REFERENCES exact immutable RubricVersion row",
        },
        "PersonaDefinition": {
            "value_object_fields": ["feature_coefficient_catalog"],
            "digest_fields": ["feature_coefficients_hash", "artifact_digest"],
            "digest_algorithm": "SHA-256",
            "canonicalization": "RFC8785-compatible integer/string subset",
            "mutation_rule": "VERSION_ROWS_ARE_IMMUTABLE; ACTIVATION_CHANGES_POINTER_ONLY",
        },
    }
    retention_registry = [
        {"policy_id": "RET-PII-3Y-OR-WITHDRAWAL", "duration_days": 1095, "trigger": "CREATED_OR_CONSENT_WITHDRAWAL", "expiry_action": "CRYPTO_ERASE_OR_TOMBSTONE"},
        {"policy_id": "RET-DOMAIN-3Y", "duration_days": 1095, "trigger": "CREATED", "expiry_action": "VERSIONED_DELETE"},
        {"policy_id": "RET-CONFIG-SUPERSEDED-3Y", "duration_days": 1095, "trigger": "SUPERSEDED", "expiry_action": "VERSIONED_DELETE"},
        {"policy_id": "RET-AUDIT-7Y", "duration_days": 2555, "trigger": "CREATED", "expiry_action": "APPROVED_PURGE"},
        {"policy_id": "RET-EVIDENCE-1Y", "duration_days": 365, "trigger": "CREATED", "expiry_action": "PURGE_BY_LINEAGE"},
        {"policy_id": "RET-RECOVERY-1Y", "duration_days": 365, "trigger": "CREATED", "expiry_action": "APPROVED_PURGE"},
    ]
    return {
        "schema_version": "persistent-domain-catalog.v1",
        "classification_vocabulary": ["PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"],
        "classification_order": ["PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"],
        "unknown_classification_default": "RESTRICTED",
        "derived_data_rule": "MAX_OF_SOURCES",
        "tenant_key_rule": "TENANT entities use PRIMARY KEY (tenant_id,id), tenant-inclusive FK/index and FORCE RLS",
        "suppression_default": {"minimum_group_size": 10, "minimum_allowed": 5, "change_requires": "OWN-SEC+OWN-PROD approval and privacy regression"},
        "retention_policy_registry": retention_registry,
        "value_object_contracts": value_object_contracts,
        "association_contracts": association_contracts,
        "immutable_artifact_contracts": immutable_artifact_contracts,
        "entities": entities,
        "entity_count": len(entities),
    }


def div_half_up(n: int, d: int) -> int:
    return (2 * n + d) // (2 * d)


def rag_score(ranks: list[int | None], metadata: int, structure: int, duplicate: int) -> dict[str, int]:
    scale = 1_000_000
    k = 60
    contributions = [0 if rank is None else div_half_up(scale, k + rank) for rank in ranks]
    max_sum = len(ranks) * div_half_up(scale, k + 1)
    rrf = div_half_up(scale * sum(contributions), max_sum)
    weighted = div_half_up(800_000 * rrf + 100_000 * metadata + 100_000 * structure, scale)
    penalty = div_half_up(50_000 * duplicate, scale)
    return {"rrf_microunit": rrf, "final_score_microunit": max(0, weighted - penalty)}


def quality_score(values: list[int]) -> int:
    return div_half_up(sum(w * v for w, v in zip([250_000, 250_000, 250_000, 150_000, 100_000], values)), 1_000_000)


def generate_rag_policy() -> dict[str, Any]:
    vector_inputs = [
        ("RAG-RANK-001", [1, 3], 800_000, 600_000, 200_000),
        ("RAG-RANK-002", [1, None], 1_000_000, 1_000_000, 0),
        ("RAG-RANK-003", [None, None], 0, 0, 0),
    ]
    quality_vectors = [
        ("DOC-QUALITY-001", [900_000] * 5),
        ("DOC-QUALITY-002", [750_000] * 5),
        ("DOC-QUALITY-003", [749_999] * 5),
    ]
    return {
        "schema_version": "rag-policy-golden.v1",
        "retrieval_policy": {
            "policy_version": "retrieval-ranking.v1",
            "scale": 1_000_000,
            "candidate_budgets": {"lexical": 100, "vector": 100, "metadata_union_max": 200, "rerank_input_max": 80, "evidence_budget_max": 20},
            "acl_filter_stage": "BEFORE_LEXICAL_AND_ANN_CANDIDATE_GENERATION",
            "rrf_k": 60,
            "rrf_channels": ["lexical", "vector"],
            "weights_microunit": {"rrf": 800_000, "metadata": 100_000, "structure": 100_000, "duplicate_penalty": 50_000},
            "formula": "rrf_norm=div_half_up(SCALE*sum(channel contribution), channel_count*div_half_up(SCALE,k+1)); final=max(0,div_half_up(800000*rrf_norm+100000*metadata+100000*structure,SCALE)-div_half_up(50000*duplicate,SCALE))",
            "tie_break": ["final_score_microunit DESC", "current_rights_decision=ALLOW", "effective_at DESC", "document_version_id UTF8 ASC", "chunk_id UTF8 ASC"],
            "unknown_feature": "REJECT_CANDIDATE",
        },
        "claim_citation_policy": {
            "policy_version": "claim-citation.v1",
            "claim_segmentation": "sentence and list-item boundaries after NFC normalization; one atomic predicate per claim",
            "important_claim_types": ["NUMERIC", "DATE_OR_VERSION", "LEGAL_OR_SAFETY", "PRESCRIPTIVE", "ATTRIBUTED_FACT", "DIRECT_QUOTE"],
            "nonclaim_types": ["GREETING", "NAVIGATION", "DISCLOSURE", "LIMITATION"],
            "importance_source": "independent rule classifier; generator label cannot remove denominator",
            "validity_checks": ["CURRENT_TENANT_MEMBERSHIP", "CURRENT_ACL_VERSION", "CURRENT_PUBLICATION_AND_LICENSE", "SOURCE_SHA256", "LOCATOR_RESOLVES", "QUOTED_SPAN_MATCHES", "ENTAILMENT_THRESHOLD"],
            "entailment_microunit_minimum": 850_000,
            "important_claim_coverage_minimum": 950_000,
            "invalid_citation_maximum": 0,
            "authorization_failure": "REMOVE_CLAIM_OR_NO_ANSWER",
        },
        "document_quality_policy": {
            "policy_version": "document-quality.v1",
            "scale": 1_000_000,
            "weights_microunit": {"text": 250_000, "reading_order": 250_000, "table_structure": 250_000, "style_preservation": 150_000, "metadata": 100_000},
            "rounding": "div_half_up",
            "automatic_review_candidate_minimum": 900_000,
            "sample_review_minimum": 750_000,
            "below_sample_review": "FULL_REVIEW",
            "automatic_publish": False,
        },
        "retrieval_vectors": [
            {"vector_id": vid, "input": {"ranks": ranks, "metadata_microunit": metadata, "structure_microunit": structure, "duplicate_microunit": duplicate}, "expected": rag_score(ranks, metadata, structure, duplicate)}
            for vid, ranks, metadata, structure, duplicate in vector_inputs
        ],
        "quality_vectors": [
            {"vector_id": vid, "input_scores_microunit": scores, "expected_quality_microunit": quality_score(scores)}
            for vid, scores in quality_vectors
        ],
    }


def generate_provider_registry() -> dict[str, Any]:
    return {
        "schema_version": "provider-decision-registry.v1",
        "routing_invariants": {
            "PUBLIC": ["EXTERNAL_OPENAI", "INTERNAL_SLLM", "DETERMINISTIC"],
            "INTERNAL": ["EXTERNAL_OPENAI_AFTER_POLICY_AUTHORIZATION", "INTERNAL_SLLM", "DETERMINISTIC"],
            "CONFIDENTIAL": ["INTERNAL_SLLM", "DETERMINISTIC", "EXTERNAL_OPENAI_AFTER_FIELD_REDACTION_AND_POLICY_AUTHORIZATION"],
            "RESTRICTED": ["INTERNAL_SLLM", "DETERMINISTIC"],
            "unknown": ["DENY"],
        },
        "decisions": [
            {"decision_id": "DEC-AI-OPENAI-001", "subject": "OpenAI Responses deployment snapshot and data-control terms", "status": "REQUIRES_ACCEPTANCE_DATA", "owner_ids": ["OWN-AI", "OWN-SEC"], "due_at": "D+20", "required_input_ids": ["IN-OAI-DPA", "IN-OAI-REGION", "IN-OAI-GOLDEN-EVAL", "IN-OAI-COST"], "gate_ids": ["GATE-AI-KPI", "GATE-SECURITY-PRIVACY"]},
            {"decision_id": "DEC-AI-SLLM-002", "subject": "sLLM model, quantization, tokenizer and serving image", "status": "REQUIRES_ACCEPTANCE_DATA", "owner_ids": ["OWN-AI", "OWN-OPS"], "due_at": "D+30", "required_input_ids": ["IN-SLLM-QWEN3", "IN-SLLM-GPT-OSS", "IN-SLLM-KOREAN-EVAL", "IN-SLLM-LICENSE"], "gate_ids": ["GATE-AI-KPI", "GATE-OPERATIONS-RECOVERY"]},
            {"decision_id": "DEC-OCR-003", "subject": "Korean OCR and table-layout engine", "status": "REQUIRES_ACCEPTANCE_DATA", "owner_ids": ["OWN-DOC", "OWN-SEC"], "due_at": "D+25", "required_input_ids": ["IN-OCR-PADDLE-PPSTRUCTURE", "IN-OCR-RAPIDOCR", "IN-OCR-KOREAN-CORPUS", "IN-OCR-DATA-TERMS"], "gate_ids": ["GATE-DOCUMENT-KPI", "GATE-SECURITY-PRIVACY"]},
            {"decision_id": "DEC-EMBED-004", "subject": "Korean embedding and reranker deployment", "status": "REQUIRES_ACCEPTANCE_DATA", "owner_ids": ["OWN-AI", "OWN-DOC"], "due_at": "D+30", "required_input_ids": ["IN-EMBED-GOLDEN-QUERY", "IN-RERANK-GOLDEN-QUERY", "IN-INDEX-CAPACITY"], "gate_ids": ["GATE-DOCUMENT-KPI", "GATE-AI-KPI"]},
            {"decision_id": "DEC-HARDWARE-005", "subject": "sLLM/OCR GPU and Windows converter capacity", "status": "REQUIRES_ACCEPTANCE_DATA", "owner_ids": ["OWN-OPS", "OWN-AI", "OWN-DOC"], "due_at": "D+30", "required_input_ids": ["IN-LOAD-PROFILE", "IN-GPU-24-48-80GB-BENCH", "IN-CONVERTER-CONCURRENCY", "IN-MONTHLY-TCO"], "gate_ids": ["GATE-OPERATIONS-RECOVERY"]},
            {"decision_id": "DEC-HWP-006", "subject": "Licensed production HWP converter binary and isolated-node evidence", "status": "BLOCKED", "owner_ids": ["OWN-DOC", "OWN-SEC", "OWN-OPS"], "due_at": "D+45", "required_input_ids": ["IN-HWP-BINARY-LICENSE", "IN-HWP-GOLDEN-CORPUS", "IN-HWP-SANDBOX-ATTESTATION"], "gate_ids": ["GATE-DOCUMENT-KPI", "GATE-SECURITY-PRIVACY"]},
        ],
        "ocr_acceptance": {"korean_character_accuracy_minimum": 0.97, "complex_table_topology_minimum": 0.95, "locator_accuracy_minimum": 1.0, "restricted_external_pages_maximum": 0, "metrics": ["CER", "reading_order", "merged_cell", "nested_table", "latency_page_p95", "cost_per_page", "license"]},
        "model_acceptance": {"diagnosis_agreement_minimum": 0.85, "recommendation_relevance_minimum": 0.90, "rag_top5_minimum": 0.95, "structured_output_minimum": 0.998, "restricted_external_events_maximum": 0},
        "activation_rule": "Only immutable deployment revisions with all decision inputs and fresh PASS gates may become ACTIVE; model binaries are never downloaded automatically by the implementation launcher.",
    }


def generate_acceptance_threshold_registry() -> dict[str, Any]:
    rows = [
        ("THR-AI-SPAN-F1", "T-AI-001", 850_000, "microunit_ratio", "MINIMUM", "OWN-AI"),
        ("THR-AI-FAIRNESS-MAX-GAP", "T-AI-007", 100_000, "microunit_ratio", "MAXIMUM", "OWN-AI"),
        ("THR-DEP-ROLLBACK-MAX-MS", "T-DEP-003", 300_000, "milliseconds", "MAXIMUM", "OWN-OPS"),
        ("THR-CODE-STATEMENT-COVERAGE", "T-GATE-001", 850_000, "microunit_ratio", "MINIMUM", "OWN-QA"),
        ("THR-CODE-BRANCH-COVERAGE", "T-GATE-001", 800_000, "microunit_ratio", "MINIMUM", "OWN-QA"),
        ("THR-REC-CONTENT-COVERAGE", "T-REC-004", 950_000, "microunit_ratio", "MINIMUM", "OWN-AI"),
        ("THR-REC-DIVERSITY", "T-REC-004", 800_000, "microunit_ratio", "MINIMUM", "OWN-AI"),
        ("THR-UX-TASK-COMPLETION", "T-UX-008", 900_000, "microunit_ratio", "MINIMUM", "OWN-UX"),
        ("THR-UX-MEDIAN-TIME-MS", "T-UX-008", 180_000, "milliseconds", "MAXIMUM", "OWN-UX"),
    ]
    return {
        "schema_version": "acceptance-threshold-registry.v1",
        "registry_version": "acceptance-thresholds.v1.0.0",
        "unknown_symbol_policy": "DENY",
        "thresholds": [
            {
                "threshold_id": threshold_id,
                "test_ids": [test_id],
                "value": value,
                "unit": unit,
                "comparison_role": comparison_role,
                "decision_id": f"DEC-{threshold_id}",
                "owner_ids": [owner] if owner == "OWN-QA" else [owner, "OWN-QA"],
                "status": "APPROVED_BASELINE",
                "effective_at": "2026-07-14T00:00:00Z",
                "due_at": "2027-07-14T00:00:00Z",
                "source_contract_ids": ["VER-ATP-009", test_id],
                "candidate_binding": "DESIGN_BASELINE_AND_TEST_FIXTURE",
                "change_control_gate_id": "GATE-DESIGN-INTEGRITY",
            }
        for threshold_id, test_id, value, unit, comparison_role, owner in rows
        ],
        "failure_release_transition": {
            "test_id": "T-AI-007",
            "on_failure": "NOT_READY",
            "test_result": "FAIL",
            "release_blocked_is_not_pass": True,
        },
    }


def generate_reuse_matrix() -> dict[str, Any]:
    assets = [
        ("LEG-001", "backend authentication rotation/reset/session", "backend/app/rc1.py", "ADAPT", ["T-API-001", "T-SEC-005"], ["domains/identity", "PUB-004", "ADM-012", "deployed-auth-api-union.v1"]),
        ("LEG-002", "Alembic migration foundation", "backend/alembic/", "REUSE", ["T-DATA-005"], ["db/migrations"]),
        ("LEG-003", "production admin bootstrap", "backend/app/admin_bootstrap.py", "REUSE", ["T-DEP-001"], ["ADM-012"]),
        ("LEG-004", "Docker isolated verification", "scripts/verify-docker.ps1", "ADAPT", ["T-GATE-003"], ["infra/compose", "scripts/verify"]),
        ("LEG-005", "PostgreSQL backup/restore drill", "scripts/backup-postgres.ps1;scripts/restore-postgres.ps1", "REUSE", ["T-DR-001"], ["runbooks/backup", "runbooks/restore"]),
        ("LEG-006", "StorageAdapter and upload defenses", "backend/app/storage.py", "ADAPT", ["T-DOC-005"], ["domains/documents", "ADM-006"]),
        ("LEG-007", "public resource/search/catalog", "frontend/src/;backend/app/main.py", "ADAPT", ["T-UX-001"], ["PUB-001", "PUB-002", "PUB-003"]),
        ("LEG-008", "notice/article/FAQ content", "backend/app/models.py;backend/app/seed.py", "ADAPT", ["T-API-003"], ["ContentItem types", "PUB-002", "PUB-003", "ADM-004"]),
        ("LEG-009", "100-resource education content pack", "backend/app/seed.py", "ADAPT", ["T-GATE-002"], ["synthetic content import", "PUB-001", "PUB-002"]),
        ("LEG-010", "inquiry and inquiry history", "frontend/src/MemberPages.tsx;backend/app/rc1.py", "ADAPT", ["T-API-009"], ["TCH-016", "ADM support queue"]),
        ("LEG-011", "bookmark storage", "backend/app/rc1.py", "REWRITE", ["T-REC-007"], ["saved recommendation/content activity", "TCH-007", "TCH-016"]),
        ("LEG-012", "monolithic RC1 CMS/API module", "backend/app/rc1.py", "REWRITE", ["T-ARCH-001"], ["domain packages", "generated OpenAPI client"]),
        ("LEG-013", "Playwright responsive E2E", "frontend/e2e/portal.spec.ts", "ADAPT", ["T-UX-003"], ["36-screen E2E catalog", "VIS-001~006"]),
        ("LEG-014", "reference source assets", "reference/private/", "RETIRE", ["T-QUAL-001"], ["manifest-only provenance; no runtime bundle"]),
    ]
    screen_auth_operations = [
        "POST /api/v1/auth/register",
        "POST /api/v1/auth/login",
        "POST /api/v1/auth/password-resets",
        "POST /api/v1/auth/mfa/challenges",
        "POST /api/v1/auth/mfa/challenges/{challenge_id}/verify",
        "POST /api/v1/auth/mfa/recovery",
        "POST /api/v1/auth/mfa/enrollments",
        "POST /api/v1/auth/mfa/enrollments/{id}/verify",
        "POST /api/v1/auth/mfa/recovery-codes/rotate",
    ]
    service_operations = []
    for operation_id, spec in SERVICE_AUTH_OPERATION_SPECS.items():
        operation = {
            "operation_id": operation_id,
            "request_field_codes": [row["field_code"] for row in spec["request_field_contracts"]],
            "response_field_codes": [row["field_code"] for row in spec["response_field_contracts"]],
            "request_field_contracts": deepcopy(spec["request_field_contracts"]),
            "response_field_contracts": deepcopy(spec["response_field_contracts"]),
            "success_status": spec["success_status"],
            "error_codes": deepcopy(spec["error_codes"]),
            "security": deepcopy(spec["security"]),
            "state_transition": spec["state_transition"],
            "owner_ids": ["OWN-ARCH", "OWN-SEC"],
            "requirement_ids": ["SIR-002", "SYS-NF-001"],
            "test_ids": ["T-API-001", "T-SEC-005"],
            "data_use_category_ids": ["IDENTITY_CREDENTIAL"],
            "data_use_field_codes": ["SUBJECT_PSEUDONYM", "TENANT_PSEUDONYM", "AUTH_FACTOR_RESULT"],
            "unknown_field_policy": "REJECT",
            "audit_event_required": True,
            "replay_policy": spec["replay_policy"],
            "request_log_policy": spec["request_log_policy"],
        }
        if "secret_request_field_codes" in spec:
            operation["secret_request_field_codes"] = deepcopy(spec["secret_request_field_codes"])
            operation["secret_path_parameter_count"] = spec["secret_path_parameter_count"]
        service_operations.append(operation)
    return {
        "schema_version": "legacy-reuse-matrix.v1",
        "decision_vocabulary": ["REUSE", "ADAPT", "REWRITE", "RETIRE"],
        "source_repository": "https://github.com/yubi-lee/yonlab-i-nuri-site.git",
        "source_branch": "feat/production-readiness",
        "assets": [
            {"asset_id": aid, "capability": capability, "source_paths": paths.split(";"), "decision": decision, "characterization_test_ids": tests, "target_contract_ids": targets, "clean_room_rule": "No third-party portal code, copy, image, attachment or distinctive layout is reused."}
            for aid, capability, paths, decision, tests, targets in assets
        ],
        "authentication_api_union_contract": {
            "contract_id": "deployed-auth-api-union.v1",
            "screen_scoped_contract_ref": "platform-openapi.json",
            "screen_scoped_operation_count": 113,
            "screen_scoped_write_operation_count": 57,
            "deployed_operation_count": 117,
            "deployed_write_operation_count": 61,
            "screen_scoped_auth_operation_ids": screen_auth_operations,
            "service_only_operations": service_operations,
            "deployed_required_auth_operation_ids": screen_auth_operations + [item["operation_id"] for item in service_operations],
            "merge_rule": "DEPLOYED_OPENAPI_AUTH_SET_EQUALS_SCREEN_SCOPED_UNION_SERVICE_ONLY",
            "duplicate_operation_policy": "REJECT",
            "missing_operation_policy": "FAIL_RELEASE",
            "acceptance_test_ids": ["T-API-001", "T-SEC-005"],
            "owner_ids": ["OWN-ARCH", "OWN-SEC"],
        },
        "portal_content_rule": "Notices, articles and FAQs remain typed ContentItem records in public search/detail and ADM-004 rather than creating duplicate silos.",
        "content_pack_rule": "The 100-resource synthetic pack is retained as development/pilot demonstration data and is never represented as institution-approved production content.",
    }


def journey(
    jid: str,
    title: str,
    screens: list[str],
    components: list[str],
    primary: str,
    fields: list[tuple[str, str]],
    copy: str,
    states: list[str],
) -> dict[str, Any]:
    return {
        "journey_id": jid,
        "title": title,
        "screen_ids": screens,
        "component_hierarchy": components,
        "primary_action": primary,
        "secondary_actions": ["도움말", "안전하게 중단", "이전 단계"],
        "fields": [{"field_id": field, "label_ko": label, "required": True, "validation": "inline+summary; invalid focus; no data existence disclosure"} for field, label in fields],
        "sample_copy_ko": copy,
        "responsive_order": {
            "1440": components,
            "768": components,
            "390": [components[0], primary] + components[1:],
        },
        "required_states": states,
        "acceptance": ["keyboard complete", "390/768/1440 no page overflow", "200% reflow", "loading/empty/error/degraded recovery", "Korean long-copy snapshot"],
    }


def generate_ui_contracts(screen_registry: dict[str, Any]) -> dict[str, Any]:
    journeys = [
        journey("UJ-001", "공개 자료 발견", ["PUB-001", "PUB-002", "PUB-003"], ["PublicShell", "SearchHero", "FilterBar", "ResultGrid", "RightsAndVersionPanel"], "자료 검색", [("query", "찾고 싶은 자료")], "검증된 교육자료를 주제와 현장 상황에 맞게 찾아보세요.", ["DEFAULT", "LOADING", "EMPTY", "ERROR", "STALE", "FORBIDDEN"]),
        journey("UJ-002", "가입·로그인·MFA 복구", ["PUB-004"], ["AuthShell", "IdentityForm", "PasswordGuidance", "MfaChallenge", "RecoveryNotice"], "안전하게 계속", [("email", "이메일"), ("password", "비밀번호")], "계정 존재 여부는 표시하지 않습니다. 입력을 확인하고 다시 시도해 주세요.", ["DEFAULT", "LOADING", "ERROR", "MFA_REQUIRED", "MFA_RECOVERY"]),
        journey("UJ-003", "프로필·동의·기관 전환", ["TCH-001", "TCH-002"], ["TeacherShell", "NextActionCard", "ConsentPurposeList", "OptionalContextForm", "TenantSelector"], "변경사항 저장", [("career_band", "경력 범주"), ("consent", "목적별 동의")], "선택 정보는 맞춤 지원에만 사용하며 언제든 철회할 수 있습니다.", ["DEFAULT", "LOADING", "EMPTY", "ERROR", "CONSENT_WITHDRAWN"]),
        journey("UJ-004", "대화형 역량진단", ["TCH-003", "TCH-004"], ["PurposeAndSafetyNotice", "ProgressStepper", "ConversationTranscript", "ResponseComposer", "PauseResumeControls"], "응답 보내기", [("teacher_response", "나의 경험")], "정답을 평가하지 않습니다. 실제 경험을 편안하게 이야기해 주세요.", ["QUEUED", "STREAMING", "COMPLETED", "PARTIAL", "ERROR", "OFFLINE", "POLICY_BLOCKED"]),
        journey("UJ-005", "진단결과·근거·페르소나 정정", ["TCH-005", "TCH-006"], ["ResultSummary", "CompetencyEvidenceAccordion", "UncertaintyPanel", "PersonaDistribution", "CorrectionDialog"], "근거 확인", [("correction_reason", "정정 사유")], "이 결과는 학습 지원용이며 인사평가나 심리진단에 사용되지 않습니다.", ["DEFAULT", "INSUFFICIENT_EVIDENCE", "DISPUTED", "MIXED_OR_UNDETERMINED", "ERROR"]),
        journey("UJ-006", "추천·학습경로·성과", ["TCH-007", "TCH-008", "TCH-009", "TCH-010"], ["RecommendationReasonCard", "AlternativeList", "LearningDag", "PracticeEditor", "AccessibleOutcomeChart"], "학습경로 시작", [("reflection", "현장 적용 기록")], "추천 이유와 대안을 함께 확인한 뒤 나에게 맞는 순서로 시작하세요.", ["DEFAULT", "EMPTY", "POLICY_CONFLICT", "AUTOSAVING", "SUBMITTED", "STALE"]),
        journey("UJ-007", "문서검색·RAG·근거", ["TCH-011", "TCH-012", "TCH-013"], ["DocumentSearch", "StructurePreview", "GroundedConversation", "ClaimCitationList", "CurrentRightsEvidenceViewer"], "근거와 함께 질문", [("query", "자료에 묻기")], "근거가 확인되지 않은 내용은 답변하지 않습니다.", ["QUEUED", "STREAMING", "GROUNDED", "NO_ANSWER", "PARTIAL", "REVOKED", "LOCATOR_UNRESOLVABLE"]),
        journey("UJ-008", "HWPX 초안·검수·내보내기", ["TCH-014", "TCH-015"], ["TemplatePicker", "EvidencePicker", "RequiredFieldStepper", "StructuredDraftEditor", "ReviewAndExportPanel"], "검수 요청", [("template", "승인 템플릿"), ("evidence", "사용 근거")], "AI 초안은 검수 전 문서입니다. 개인정보와 근거를 확인해 주세요.", ["DEFAULT", "RIGHTS_BLOCKED", "JOB_RUNNING", "REVIEW_REQUIRED", "APPROVED", "EXPORTING"]),
        journey("UJ-009", "역량·페르소나·추천정책 운영", ["ADM-002", "ADM-003", "ADM-005"], ["AdminShell", "VersionList", "PolicyDiff", "OfflineEvaluationSummary", "DualApprovalBar"], "새 버전 검수 요청", [("change_reason", "변경 사유")], "게시된 버전은 수정하지 않고 새 버전으로 검증합니다.", ["DEFAULT", "EMPTY", "ERROR", "REAUTH_REQUIRED"]),
        journey("UJ-010", "문서 수집·OCR 검수·게시", ["ADM-006", "ADM-007", "ADM-008"], ["UploadQuarantinePanel", "PipelineTimeline", "SourceGraphSplitView", "TableCellEditor", "PublicationSnapshot"], "검수 완료", [("rights", "이용 권리"), ("review_reason", "검수 의견")], "원문과 구조를 비교하고 낮은 신뢰도 항목을 확인하세요.", ["QUARANTINED", "REVIEW_REQUIRED", "LOCATOR_UNRESOLVABLE", "REAUTH_REQUIRED", "ERROR"]),
        journey("UJ-011", "AI 모델·평가·비용 관제", ["ADM-009", "ADM-010", "ADM-011"], ["DeploymentRegistry", "RoutingPolicyDiff", "EvaluationGateTable", "CostLatencyChart", "FallbackTimeline"], "평가 실행", [("candidate", "후보 배포"), ("suite", "평가셋")], "Hard gate를 통과하지 않은 모델은 활성화할 수 없습니다.", ["DEFAULT", "GATE_FAILED", "PARTIAL", "STALE", "REAUTH_REQUIRED"]),
        journey("UJ-012", "운영·시범·감사", ["ADM-001", "ADM-004", "ADM-012", "ADM-013", "ADM-014", "ADM-015", "ADM-016", "TCH-016"], ["OperationalOverview", "AccessAndMfa", "PilotCohortProgress", "PrivacySuppressedAnalytics", "ImmutableAuditSearch", "RunbookActions"], "상세 상태 확인", [("period", "집계 기간"), ("reason", "작업 사유")], "최신 시각과 집계 범위를 확인한 뒤 승인된 작업만 실행하세요.", ["DEFAULT", "EMPTY", "PARTIAL", "STALE", "PRIVACY_SUPPRESSED", "REAUTH_REQUIRED", "REQUEST_PENDING"]),
    ]
    screen_closure = []
    for screen in screen_registry["screens"]:
        journey_ids = [item["journey_id"] for item in journeys if screen["screen_id"] in item["screen_ids"]]
        screen_closure.append(
            {
                "screen_id": screen["screen_id"],
                "route": screen["route"],
                "journey_ids": journey_ids,
                "component_contract_id": f"COMP-{screen['screen_id']}-V1",
                "required_state_ids": screen["state_ids"],
                "responsive_viewports": ["1440x900", "768x1024", "390x844"],
                "visual_evidence_required": True,
            }
        )
    return {"schema_version": "ui-journey-contracts.v1", "key_journey_count": 12, "key_journeys": journeys, "screen_count": len(screen_closure), "screen_closure": screen_closure}


def synchronize_final_inventory() -> None:
    path = ROOT / "final-document-inventory.json"
    inventory = json.loads(path.read_text(encoding="utf-8"))
    generated_ids = {f"FDI-DES-{index:03d}" for index in range(31, 49)}
    artifacts = [item for item in inventory["artifacts"] if item.get("artifact_id") not in generated_ids]
    additions = [
        ("platform-openapi.json", ["OWN-ARCH", "OWN-QA"], ["GATE-DESIGN-INTEGRITY"]),
        ("platform-asyncapi.json", ["OWN-ARCH", "OWN-QA"], ["GATE-DESIGN-INTEGRITY"]),
        ("persistent-domain-catalog.json", ["OWN-ARCH", "OWN-SEC"], ["GATE-DESIGN-INTEGRITY", "GATE-SECURITY-PRIVACY"]),
        ("ai-service-contracts.json", ["OWN-AI", "OWN-SEC"], ["GATE-AI-KPI", "GATE-SECURITY-PRIVACY"]),
        ("data-use-policy-registry.json", ["OWN-SEC", "OWN-AI"], ["GATE-SECURITY-PRIVACY"]),
        ("acceptance-threshold-registry.json", ["OWN-QA", "OWN-ACC"], ["GATE-DESIGN-INTEGRITY", "GATE-PILOT-ACCEPTANCE"]),
        ("normative-test-semantics.json", ["OWN-QA"], ["GATE-DESIGN-INTEGRITY"]),
        ("rag-policy-golden-vectors.json", ["OWN-AI", "OWN-DOC"], ["GATE-DOCUMENT-KPI"]),
        ("provider-decision-registry.json", ["OWN-ARCH", "OWN-OPS"], ["GATE-OPERATIONS-RECOVERY"]),
        ("legacy-reuse-decision-matrix.json", ["OWN-ARCH", "OWN-QA"], ["GATE-DESIGN-INTEGRITY"]),
        ("ui-journey-contracts.json", ["OWN-UX", "OWN-QA"], ["GATE-UX-ACCESSIBILITY"]),
        ("rubric-question-contract.json", ["OWN-AI", "OWN-PROD"], ["GATE-AI-KPI"]),
        ("persona-inference-policy.json", ["OWN-AI", "OWN-SEC"], ["GATE-AI-KPI", "GATE-SECURITY-PRIVACY"]),
        ("operation-authorization-contracts.json", ["OWN-SEC"], ["GATE-SECURITY-PRIVACY"]),
        ("evaluation-policy-contract.json", ["OWN-QA", "OWN-AI"], ["GATE-AI-KPI", "GATE-UX-ACCESSIBILITY"]),
        ("hwp-conversion-boundary-contract.json", ["OWN-DOC", "OWN-SEC"], ["GATE-DOCUMENT-KPI", "GATE-SECURITY-PRIVACY"]),
        ("tch-015-authorization-contract.json", ["OWN-SEC", "OWN-DOC"], ["GATE-SECURITY-PRIVACY"]),
        ("source-traceability-manifest.json", ["OWN-QA", "OWN-PROD"], ["GATE-DESIGN-INTEGRITY"]),
    ]
    generated = [
        {
            "artifact_id": f"FDI-DES-{index:03d}",
            "group": "design",
            "root_id": "final_design",
            "root_path": "docs/design/ai-training-platform/",
            "relative_path_template": relative_path,
            "owner_ids": owners,
            "gate_ids": gates,
            "media_type": "application/json",
            "source_kind": "verified_machine_contract",
            "required": True,
        }
        for index, (relative_path, owners, gates) in enumerate(additions, 31)
    ]
    insert_at = next(index for index, item in enumerate(artifacts) if item["group"] != "design")
    inventory["artifacts"] = artifacts[:insert_at] + generated + artifacts[insert_at:]
    counts: dict[str, int] = {}
    for artifact in inventory["artifacts"]:
        counts[artifact["group"]] = counts.get(artifact["group"], 0) + 1
    inventory["expected_counts"] = {
        "design": counts["design"],
        "operations": counts["operations"],
        "runbook": counts["runbook"],
        "qa": counts["qa"],
        "manual_markdown": counts["manual_markdown"],
        "manual_pdf": counts["manual_pdf"],
        "release": counts["release"],
        "distribution": counts["distribution"],
        "total": len(inventory["artifacts"]),
    }
    projection = {key: value for key, value in inventory.items() if key != "canonical_contract"}
    inventory["canonical_contract"]["digest_sha256"] = hashlib.sha256(
        json.dumps(projection, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    dump("final-document-inventory.json", inventory)


def synchronize_final_document_test_semantics() -> None:
    inventory = json.loads((ROOT / "final-document-inventory.json").read_text(encoding="utf-8"))
    item_count = inventory["expected_counts"]["total"]
    design_count = inventory["expected_counts"]["design"]
    if item_count != 147 or design_count != 48:
        raise ValueError(f"final inventory baseline drift: total={item_count}, design={design_count}")

    registry_path = ROOT / "requirements-test-registry.json"
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    test = next(item for item in registry["tests"] if item["test_id"] == "T-DOCS-002")
    test["title"] = f"T-DOCS-002 {item_count}-item inventory와 8 Markdown/PDF pair 최종 산출물 검증"
    projection = {key: value for key, value in test.items() if key != "semantic_case_sha256"}
    test["semantic_case_sha256"] = hashlib.sha256(
        json.dumps(projection, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    case_rows = [
        {key: value for key, value in item.items() if key != "semantic_case_sha256"}
        for item in registry["tests"]
    ]
    registry["semantic_case_contract"]["aggregate_sha256"] = hashlib.sha256(
        json.dumps(case_rows, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    dump("requirements-test-registry.json", registry)

    semantics_path = ROOT / "normative-test-semantics.json"
    semantics = json.loads(semantics_path.read_text(encoding="utf-8"))
    row = next(item for item in semantics["tests"] if item["test_id"] == "T-DOCS-002")
    row["title"] = test["title"]
    row["acceptance_formula"] = (
        f"final_document_contract_error_count == 0 AND inventory_item_count == {item_count} "
        "AND markdown_pdf_pair_count == 8"
    )
    dump("normative-test-semantics.json", semantics)


def main() -> None:
    screen_registry = json.loads((ROOT / "screen-route-contracts.json").read_text(encoding="utf-8"))
    dump("platform-openapi.json", generate_openapi(screen_registry))
    dump("platform-asyncapi.json", generate_asyncapi())
    dump("data-use-policy-registry.json", generate_data_use_policy(screen_registry))
    dump("ai-service-contracts.json", generate_ai_contracts())
    dump("persistent-domain-catalog.json", generate_entity_catalog())
    dump("rag-policy-golden-vectors.json", generate_rag_policy())
    dump("acceptance-threshold-registry.json", generate_acceptance_threshold_registry())
    dump("legacy-reuse-decision-matrix.json", generate_reuse_matrix())
    dump("ui-journey-contracts.json", generate_ui_contracts(screen_registry))
    synchronize_final_inventory()
    synchronize_final_document_test_semantics()


if __name__ == "__main__":
    main()
