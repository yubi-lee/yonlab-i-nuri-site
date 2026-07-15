#!/usr/bin/env python3
"""Fail-closed verifier for implementation-completeness design contracts."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


CLASSES = ["PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"]
SAFEGUARDING = [
    "STANDARD",
    "CHILD_SAFEGUARDING",
    "IMMINENT_DANGER",
    "SECURITY_EXFILTRATION",
    "POLICY_BLOCK",
]
TASKS = {
    "diagnosis.evidence.extract",
    "diagnosis.next_question.compose",
    "persona.explanation.compose",
    "recommendation.explanation.compose",
    "document.query.rewrite",
    "document.rerank",
    "document.grounded_answer",
    "draft.hwpx.section.compose",
    "document.metadata.tag",
}
OPENAPI_SEMANTIC_AGGREGATE_SHA256 = "06f7548b02983b5fa092bcb3239c0ffe95719ba6b06437c09a824523688926bb"
OPENAPI_BLUEPRINT_BINDING_SHA256 = "ba65d888deac606c411685344610bfdf3177ccf029b0d89cbc7f53fdc9ba76f9"
OPENAPI_REQUEST_BLUEPRINT_BINDING_SHA256 = "35819ba362ffbbff71584b7aeed583e2e21dffa9286b1c7d3577bd442fc951cf"
PERSISTENT_DOMAIN_CATALOG_SHA256 = "4dd6dc41933c7581c019d4bbf07f607a5df3643a02c32b11f70b9cbddd76c1c7"
GENERIC_RESULT_FIELDS = {"status", "resource_id", "resource_type", "state", "job_id"}
CORE_PHYSICAL_DOMAINS = {
    "IDENTITY", "DIAGNOSIS", "RECOMMENDATION", "LEARNING", "DOCUMENT",
    "RETRIEVAL", "DRAFT", "AI_GATEWAY", "SAFEGUARDING",
}
RETENTION_POLICY_IDS = {
    "RET-PII-3Y-OR-WITHDRAWAL", "RET-DOMAIN-3Y", "RET-CONFIG-SUPERSEDED-3Y",
    "RET-AUDIT-7Y", "RET-EVIDENCE-1Y", "RET-RECOVERY-1Y",
}
REQUIRED_ENTITY_FIELDS = {
    "PasswordCredential": {"user_id", "password_hash", "password_algorithm", "password_changed_at", "failed_login_count", "locked_until"},
    "RefreshSession": {"token_hash", "family_id", "rotated_from_id", "issued_at", "expires_at", "revoked_at", "reuse_detected_at"},
    "PasswordResetToken": {"token_hash", "expires_at", "consumed_at", "requested_ip_hash"},
    "MfaCredential": {"factor_type", "secret_ciphertext", "encryption_key_id", "verified_at"},
    "MfaChallenge": {"challenge_hash", "purpose", "attempt_count", "expires_at", "consumed_at"},
    "RubricVersion": {"indicator_catalog", "evidence_anchor_catalog", "question_catalog", "scoring_policy_version", "indicator_catalog_digest", "anchor_catalog_digest", "question_catalog_digest", "artifact_digest"},
    "EvidenceSpan": {"anchor_id", "anchor_type", "start_offset", "end_offset", "source_text_sha256", "extraction_policy_version", "turn_sequence"},
    "CompetencyScore": {"score_microunit", "confidence_microunit", "conflict_decision", "evidence_coverage_microunit", "decision"},
    "PersonaDefinition": {"feature_coefficient_catalog", "feature_coefficients_hash", "artifact_digest"},
    "ContentItem": {"recommendation_feature_codes", "competency_codes", "modality_code", "duration_minutes", "difficulty_level", "prerequisite_codes", "accessibility_features", "region_availability_codes"},
    "LearningPathStep": {"dag_node_key", "topological_rank"},
    "DocumentNode": {"parent_node_id", "node_path", "sibling_order", "source_artifact_id", "source_locator", "source_sha256", "extraction_engine", "extraction_version", "style_ref", "structure_confidence_microunit"},
    "Citation": {"claim_id", "quoted_span", "entailment_microunit", "rights_current"},
}
REQUIRED_FINAL_MACHINE_CONTRACTS = {
    "screen-route-contracts.json", "requirements-test-registry.json",
    "normative-test-semantics.json", "platform-openapi.json",
    "platform-asyncapi.json", "persistent-domain-catalog.json",
    "ai-service-contracts.json", "data-use-policy-registry.json",
    "acceptance-threshold-registry.json", "rag-policy-golden-vectors.json",
    "provider-decision-registry.json", "legacy-reuse-decision-matrix.json",
    "ui-journey-contracts.json", "rubric-question-contract.json",
    "persona-inference-policy.json", "operation-authorization-contracts.json",
    "evaluation-policy-contract.json", "document-graph.schema.json",
}
REQUIRED_ENTITIES = {
    "User", "PasswordCredential", "Tenant", "Organization", "Membership", "Role", "Permission",
    "ConsentRecord", "TeacherContext", "DataProcessingRegistry", "SafeguardingCase",
    "CompetencyFramework", "CompetencyDimension", "RubricVersion", "DiagnosisSession",
    "DialogueTurn", "EvidenceSpan", "DiagnosisResult", "CompetencyScore",
    "PersonaDefinition", "PersonaAssessment", "Course", "ContentItem", "Recommendation",
    "LearningPath", "LearningPathStep", "Enrollment", "LearningActivity", "PracticeTask",
    "ReportSnapshot", "SourceDocument", "DocumentVersion", "FileObject", "ProcessingJob",
    "Artifact", "DocumentNode", "TableCell", "Chunk", "EmbeddingRecord", "IndexSnapshot",
    "Citation", "DraftTemplate", "TemplateVersion", "GeneratedDraft", "ReviewDecision",
    "ModelProvider", "ModelDeployment", "RoutingPolicy", "PromptVersion", "SchemaVersion",
    "ModelRun", "EvaluationSuite", "EvaluationRun", "PilotCohort", "Feedback",
    "Notification", "Inquiry", "AuditEvent", "OutboxEvent", "FeatureFlag",
    "DeletionLedger", "ObjectCapability", "HwpConversionAttestation", "BackupManifest",
    "RecoveryEvidence", "SecurityEvent",
    "RefreshSession", "PasswordResetToken", "MfaCredential", "MfaChallenge",
    "IdempotencyRecord", "EmailDelivery", "ExportRequest", "DeletionRequest",
    "FgiSession", "ImprovementIssue", "RightsGrant", "RagSession", "AnswerRun",
    "Claim", "RecommendationFeedback", "DraftExport",
}


class ContractError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def canonical(value: Any) -> bytes:
    def reject(node: Any) -> None:
        if isinstance(node, float):
            raise ContractError("canonical contract cannot contain float")
        if isinstance(node, dict):
            require(all(isinstance(key, str) for key in node), "canonical object key must be string")
            for child in node.values():
                reject(child)
        elif isinstance(node, list):
            for child in node:
                reject(child)
        elif node is not None and not isinstance(node, (str, int, bool)):
            raise ContractError(f"unsupported canonical value {type(node).__name__}")

    reject(value)
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def expected_service_auth_contracts() -> dict[tuple[str, str], dict[str, Any]]:
    uuid_schema = {"type": "string", "format": "uuid"}
    date_time_schema = {"type": "string", "format": "date-time"}
    access_token_schema = {"type": "string", "minLength": 32, "maxLength": 4096}
    expires_schema = {"type": "integer", "minimum": 0}

    def field(code: str, wire: str, location: str, schema: dict[str, Any]) -> dict[str, Any]:
        return {"field_code": code, "wire_name": wire, "location": location, "required": True, "schema": schema}

    common_cookie = field("REFRESH_TOKEN_COOKIE", "yonlab_refresh", "COOKIE", {"type": "string", "minLength": 32, "maxLength": 2048})
    common_csrf = field("CSRF_TOKEN", "X-CSRF-Token", "HEADER", {"type": "string", "minLength": 32, "maxLength": 512})
    command_id = field("COMMAND_ID", "command_id", "BODY", uuid_schema)
    return {
        ("post", "/api/v1/auth/refresh"): {
            "operation_id": "post_api_v1_auth_refresh", "request_blueprint_id": "auth.refresh", "response_blueprint_id": "auth.refresh",
            "request_field_contracts": [common_cookie, common_csrf, command_id],
            "response_field_contracts": [field("ACCESS_TOKEN", "access_token", "BODY", access_token_schema), field("EXPIRES_IN_SECONDS", "expires_in_seconds", "BODY", expires_schema), field("ROTATED_REFRESH_SESSION_ID", "rotated_refresh_session_id", "BODY", uuid_schema), field("SESSION_FAMILY_ID", "session_family_id", "BODY", uuid_schema)],
            "success_status": "200", "error_codes": ["AUTH_REFRESH_INVALID", "AUTH_REFRESH_REPLAY_DETECTED", "CSRF_INVALID", "RATE_LIMITED"],
            "security": [{"refreshCookie": [], "csrfHeader": []}], "state_transition": "ROTATE_ONCE_AND_REVOKE_PREDECESSOR", "replay_policy": "DENY_AND_REVOKE_SESSION_FAMILY", "request_log_policy": "REDACT_SECRETS",
        },
        ("post", "/api/v1/auth/logout"): {
            "operation_id": "post_api_v1_auth_logout", "request_blueprint_id": "auth.logout", "response_blueprint_id": "auth.logout",
            "request_field_contracts": [common_cookie, common_csrf, command_id],
            "response_field_contracts": [field("REVOKED_REFRESH_SESSION_ID", "revoked_refresh_session_id", "BODY", uuid_schema), field("LOGGED_OUT_AT", "logged_out_at", "BODY", date_time_schema)],
            "success_status": "200", "error_codes": ["AUTH_REFRESH_INVALID", "CSRF_INVALID", "RATE_LIMITED"],
            "security": [{"refreshCookie": [], "csrfHeader": []}], "state_transition": "REVOKE_CURRENT_REFRESH_SESSION", "replay_policy": "DENY_AND_REVOKE_SESSION_FAMILY", "request_log_policy": "REDACT_SECRETS",
        },
        ("post", "/api/v1/auth/logout-all"): {
            "operation_id": "post_api_v1_auth_logout_all", "request_blueprint_id": "auth.logout-all", "response_blueprint_id": "auth.logout-all",
            "request_field_contracts": [common_csrf, command_id, field("REAUTH_ASSERTION", "reauth_assertion", "BODY", {"type": "string", "minLength": 16, "maxLength": 4096}), field("REASON_CODE", "reason_code", "BODY", {"type": "string", "minLength": 1, "maxLength": 64})],
            "response_field_contracts": [field("REVOKED_SESSION_COUNT", "revoked_session_count", "BODY", {"type": "integer", "minimum": 0}), field("SECURITY_EVENT_ID", "security_event_id", "BODY", uuid_schema), field("LOGGED_OUT_AT", "logged_out_at", "BODY", date_time_schema)],
            "success_status": "200", "error_codes": ["AUTHENTICATION_REQUIRED", "CSRF_INVALID", "REAUTH_REQUIRED", "RATE_LIMITED"],
            "security": [{"bearerAuth": [], "csrfHeader": []}], "state_transition": "REVOKE_ENTIRE_REFRESH_SESSION_FAMILY", "replay_policy": "DENY_AND_REVOKE_SESSION_FAMILY", "request_log_policy": "REDACT_SECRETS",
        },
        ("post", "/api/v1/auth/password-resets/confirm"): {
            "operation_id": "post_api_v1_auth_password_resets_confirm", "request_blueprint_id": "auth.password-reset-confirm", "response_blueprint_id": "auth.password-reset-confirm",
            "request_field_contracts": [command_id, field("ONE_TIME_RESET_TOKEN", "one_time_reset_token", "BODY", {"type": "string", "minLength": 32, "maxLength": 512}), field("NEW_PASSWORD", "new_password", "BODY", {"type": "string", "minLength": 12, "maxLength": 128})],
            "response_field_contracts": [field("PASSWORD_CHANGED_AT", "password_changed_at", "BODY", date_time_schema), field("REVOKED_SESSION_COUNT", "revoked_session_count", "BODY", {"type": "integer", "minimum": 0}), field("SECURITY_EVENT_ID", "security_event_id", "BODY", uuid_schema)],
            "success_status": "200", "error_codes": ["PASSWORD_POLICY_REJECTED", "RATE_LIMITED", "RESET_TOKEN_CONSUMED", "RESET_TOKEN_EXPIRED", "RESET_TOKEN_INVALID"],
            "security": [], "state_transition": "CONSUME_TOKEN_ROTATE_PASSWORD_REVOKE_ALL_SESSIONS", "replay_policy": "DENY_AND_REVOKE_SESSION_FAMILY", "request_log_policy": "NEVER",
            "secret_request_field_codes": ["ONE_TIME_RESET_TOKEN", "NEW_PASSWORD"], "secret_path_parameter_count": 0,
        },
    }


def load(root: Path, name: str) -> dict[str, Any]:
    path = root / name
    require(path.is_file(), f"missing {name}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ContractError(f"invalid {name}: {exc}") from exc
    require(isinstance(value, dict), f"{name} root must be an object")
    return value


def ref_name(ref: str) -> str:
    prefix = "#/components/schemas/"
    require(ref.startswith(prefix), f"unexpected schema reference {ref}")
    return ref[len(prefix):]


def assert_closed_schema(schema: Any, where: str) -> None:
    require(isinstance(schema, dict), f"{where} schema must be object")
    if "$ref" in schema:
        return
    schema_type = schema.get("type")
    if schema_type == "object" or "properties" in schema:
        require(schema.get("additionalProperties") is False, f"{where} object is not closed")
        properties = schema.get("properties")
        require(isinstance(properties, dict), f"{where} closed object lacks properties")
        required = schema.get("required", [])
        require(isinstance(required, list), f"{where} required must be list")
        require(set(required).issubset(properties), f"{where} requires undeclared property")
        for name, child in properties.items():
            assert_closed_schema(child, f"{where}.{name}")
    if schema_type == "array":
        require("items" in schema, f"{where} array lacks items")
        assert_closed_schema(schema["items"], f"{where}[]")
    for keyword in ("oneOf", "anyOf", "allOf"):
        for index, child in enumerate(schema.get(keyword, [])):
            assert_closed_schema(child, f"{where}.{keyword}[{index}]")


def screen_operations(screen_registry: dict[str, Any]) -> dict[tuple[str, str], dict[str, Any]]:
    result: dict[tuple[str, str], dict[str, Any]] = {}
    for screen in screen_registry.get("screens", []):
        for contract in screen.get("operation_contracts", []):
            key = (contract["method"].lower(), contract["path_template"])
            require(key not in result, f"duplicate normative operation {key}")
            result[key] = {"screen": screen, "contract": contract}
    return result


def verify_openapi(root: Path, screens: dict[str, Any]) -> None:
    api = load(root, "platform-openapi.json")
    require(api.get("openapi") == "3.1.0", "OpenAPI must be 3.1.0")
    require(api.get("jsonSchemaDialect") == "https://json-schema.org/draft/2020-12/schema", "OpenAPI JSON Schema dialect drift")
    require(api.get("servers") == [{"url": "/"}], "OpenAPI server must not duplicate /api/v1")
    screen_expected = screen_operations(screens)
    service_expected = expected_service_auth_contracts()
    expected = {**screen_expected, **{key: {"service": value} for key, value in service_expected.items()}}
    actual: dict[tuple[str, str], dict[str, Any]] = {}
    allowed = {"get", "post", "patch", "put", "delete"}
    for path, path_item in api.get("paths", {}).items():
        require(isinstance(path_item, dict), f"OpenAPI path {path} invalid")
        for method, operation in path_item.items():
            if method not in allowed:
                continue
            actual[(method, path)] = operation
    require(set(actual) == set(expected), f"OpenAPI operation closure differs: missing={sorted(set(expected)-set(actual))}, extra={sorted(set(actual)-set(expected))}")
    require(api.get("x-operation-count") == len(expected) == 117, "deployed OpenAPI operation count must be exactly 117")
    blueprint_contract = api.get("x-response-blueprint-contract", {})
    blueprint_bindings = blueprint_contract.get("bindings", [])
    require(
        blueprint_contract.get("binding_count") == len(blueprint_bindings) == 117
        and blueprint_contract.get("fallback_count") == 0,
        "OpenAPI must bind exactly 117 explicit response blueprints with zero fallback",
    )
    require(
        isinstance(blueprint_contract.get("blueprint_count"), int)
        and 104 <= blueprint_contract["blueprint_count"] <= 117,
        "OpenAPI response blueprint catalog is unexpectedly generic",
    )
    blueprint_map: dict[tuple[str, str], str] = {}
    for binding in blueprint_bindings:
        key = (str(binding.get("method", "")).lower(), binding.get("path"))
        require(key not in blueprint_map, f"duplicate response blueprint binding {key}")
        blueprint_id = binding.get("blueprint_id")
        require(
            isinstance(blueprint_id, str)
            and blueprint_id
            and not {"default", "generic", "fallback"}.intersection(blueprint_id.lower().split(".")),
            f"{key} response blueprint ID is not explicit",
        )
        blueprint_map[key] = blueprint_id
    require(set(blueprint_map) == set(expected), "response blueprint key set must equal all 117 deployed operations")
    normalized_bindings = sorted(blueprint_bindings, key=lambda row: (row["path"], row["method"]))
    blueprint_digest = hashlib.sha256(canonical(normalized_bindings)).hexdigest()
    require(
        blueprint_contract.get("binding_sha256") == blueprint_digest == OPENAPI_BLUEPRINT_BINDING_SHA256,
        "response blueprint binding digest is not independently pinned",
    )
    write_operations = {key for key in expected if key[0] in {"post", "patch", "put", "delete"}}
    get_operations = {key for key in expected if key[0] == "get"}
    require(len(write_operations) == 61 and len(get_operations) == 56, "deployed HTTP method closure must be 61 writes and 56 GETs")
    request_blueprint_contract = api.get("x-request-blueprint-contract", {})
    request_blueprint_bindings = request_blueprint_contract.get("bindings", [])
    require(
        request_blueprint_contract.get("binding_count") == len(request_blueprint_bindings) == 61
        and request_blueprint_contract.get("fallback_count") == 0
        and request_blueprint_contract.get("get_request_body_count") == 0,
        "OpenAPI must bind exactly 61 write request blueprints, zero fallback and zero GET bodies",
    )
    require(
        isinstance(request_blueprint_contract.get("blueprint_count"), int)
        and 49 <= request_blueprint_contract["blueprint_count"] <= 61,
        "OpenAPI request blueprint catalog is unexpectedly generic",
    )
    request_blueprint_map: dict[tuple[str, str], str] = {}
    for binding in request_blueprint_bindings:
        key = (str(binding.get("method", "")).lower(), binding.get("path"))
        require(key not in request_blueprint_map, f"duplicate request blueprint binding {key}")
        blueprint_id = binding.get("blueprint_id")
        require(
            isinstance(blueprint_id, str)
            and blueprint_id
            and not {"default", "generic", "fallback"}.intersection(blueprint_id.lower().split(".")),
            f"{key} request blueprint ID is not explicit",
        )
        request_blueprint_map[key] = blueprint_id
    require(set(request_blueprint_map) == write_operations, "request blueprint key set must equal all 61 deployed write operations")
    normalized_request_bindings = sorted(request_blueprint_bindings, key=lambda row: (row["path"], row["method"]))
    request_blueprint_digest = hashlib.sha256(canonical(normalized_request_bindings)).hexdigest()
    require(
        request_blueprint_contract.get("binding_sha256") == request_blueprint_digest == OPENAPI_REQUEST_BLUEPRINT_BINDING_SHA256,
        "request blueprint binding digest is not independently pinned",
    )
    schemas = api.get("components", {}).get("schemas", {})
    require(isinstance(schemas, dict), "OpenAPI schemas missing")
    request_refs: set[str] = set()
    response_refs: set[str] = set()
    error_refs: set[str] = set()
    semantic_rows: list[dict[str, Any]] = []
    for key, operation in actual.items():
        service_spec = service_expected.get(key)
        if service_spec is None:
            normative = screen_expected[key]
            contract = normative["contract"]
            screen = normative["screen"]
            require(operation.get("x-service-only") is not True, f"{key} screen operation marked service-only")
            require(operation.get("x-screen-id") == screen["screen_id"], f"{key} screen binding drift")
            require(operation.get("x-capability-id") == contract["capability_id"], f"{key} capability binding drift")
            require(operation.get("x-authorization-contract-id") == contract["authorization_contract_id"], f"{key} authorization binding drift")
            require(operation.get("x-owner-ids") == contract["owner_ids"], f"{key} owner binding drift")
            require(operation.get("x-requirement-ids") == contract["requirement_ids"], f"{key} requirement binding drift")
            require(operation.get("x-test-ids") == contract["test_ids"], f"{key} test binding drift")
            require(operation.get("x-evidence-ids") == contract["evidence_ids"], f"{key} evidence binding drift")
        else:
            require(operation.get("x-service-only") is True and "x-screen-id" not in operation, f"{key} service-only scope drift")
            require(operation.get("operationId") == service_spec["operation_id"], f"{key} service operationId drift")
            require(operation.get("x-capability-id") == "CAP-AUTH-SERVICE-V1" and operation.get("x-authorization-contract-id") == "AUTHZ-AUTH-SERVICE-V1", f"{key} service capability/authz drift")
            require(operation.get("x-owner-ids") == ["OWN-ARCH", "OWN-SEC"], f"{key} service owner drift")
            require(operation.get("x-requirement-ids") == ["SIR-002", "SYS-NF-001"], f"{key} service requirement drift")
            require(operation.get("x-test-ids") == ["T-API-001", "T-SEC-005"], f"{key} service test drift")
            require(operation.get("x-request-field-contracts") == service_spec["request_field_contracts"], f"{key} exact request field contract drift")
            require(operation.get("x-response-field-contracts") == service_spec["response_field_contracts"], f"{key} exact response field contract drift")
            require(operation.get("x-state-transition") == service_spec["state_transition"], f"{key} exact state transition drift")
            require(operation.get("x-replay-policy") == service_spec["replay_policy"], f"{key} replay policy drift")
            require(operation.get("x-request-log-policy") == service_spec["request_log_policy"], f"{key} request log policy drift")
        require(operation.get("x-reject-unknown-query") is True, f"{key} must reject unknown query fields")
        parameters = operation.get("parameters")
        require(isinstance(parameters, list), f"{key} parameters must be an exact list")
        parameter_keys = [(row.get("in"), row.get("name")) for row in parameters if isinstance(row, dict)]
        require(len(parameter_keys) == len(parameters) == len(set(parameter_keys)), f"{key} parameter names/locations must be unique")
        require(all(row.get("in") in {"path", "query", "header", "cookie"} and isinstance(row.get("schema"), dict) for row in parameters), f"{key} parameter location/schema invalid")
        placeholders = set(re.findall(r"\{([^}]+)\}", key[1]))
        path_parameters = {row.get("name") for row in parameters if row.get("in") == "path"}
        require(path_parameters == placeholders, f"{key} path placeholders/parameters differ")
        require(all(row.get("required") is True for row in parameters if row.get("in") == "path"), f"{key} path parameters must be required")
        if service_spec is not None:
            expected_parameters = [
                {"name": row["wire_name"], "in": row["location"].lower(), "required": row["required"], "schema": row["schema"]}
                for row in service_spec["request_field_contracts"] if row["location"] != "BODY"
            ]
            require(parameters == expected_parameters, f"{key} service cookie/header parameter contract drift")
        responses = operation.get("responses", {})
        success = [code for code in responses if code != "default"]
        require(len(success) == 1 and "default" in responses, f"{key} response closure invalid")
        if service_spec is not None:
            require(success == [service_spec["success_status"]], f"{key} success status drift")
        response_ref = ref_name(operation["responses"][success[0]]["content"]["application/json"]["schema"]["$ref"])
        require(response_ref not in response_refs, f"{key} reuses an operation response schema")
        response_refs.add(response_ref)
        require(response_ref in schemas, f"{key} response schema missing")
        assert_closed_schema(schemas[response_ref], response_ref)
        response_properties = schemas[response_ref].get("properties", {})
        require(not (GENERIC_RESULT_FIELDS & set(response_properties)), f"{key} retains generic response stub fields")
        require("result" not in response_properties, f"{key} retains generic result wrapper")
        error_ref = ref_name(responses["default"]["content"]["application/problem+json"]["schema"]["$ref"])
        require(error_ref not in error_refs and error_ref in schemas, f"{key} must have a unique error schema")
        error_refs.add(error_ref)
        assert_closed_schema(schemas[error_ref], error_ref)
        error_code = schemas[error_ref].get("properties", {}).get("code", {})
        error_codes = error_code.get("enum", [])
        require(isinstance(error_codes, list) and len(error_codes) >= 1 and len(error_codes) == len(set(error_codes)), f"{key} error vocabulary is not exact")
        require(operation.get("x-error-codes") == error_codes, f"{key} error metadata/schema drift")
        if service_spec is not None:
            require(error_codes == service_spec["error_codes"], f"{key} service error vocabulary drift")
            require(operation.get("security") == service_spec["security"], f"{key} service security scheme drift")
        require(operation.get("x-domain") in {"PUBLIC_PORTAL", "IDENTITY", "DIAGNOSIS", "RECOMMENDATION", "LEARNING", "REPORTING", "DOCUMENT", "DRAFT", "ADMINISTRATION", "OPERATIONS"}, f"{key} domain missing")
        require(operation.get("x-operation-kind") in {"READ_DETAIL", "READ_COLLECTION", "CREATE", "UPDATE", "ACTION", "HEALTH"}, f"{key} operation kind missing")
        blueprint_id = blueprint_map[key]
        require(operation.get("x-response-blueprint-id") == blueprint_id, f"{key} response blueprint metadata drift")
        if service_spec is not None:
            require(blueprint_id == service_spec["response_blueprint_id"], f"{key} response blueprint ID drift")
        require(
            response_properties.get("schema_version", {}).get("const") == f"response.{blueprint_id}.v1",
            f"{key} response schema version is not bound to its explicit blueprint",
        )
        semantic_field_names = set(response_properties) - {"schema_version", "trace_id"}
        require(len(semantic_field_names) >= 2, f"{key} explicit response blueprint is semantically empty")
        pagination = operation.get("x-pagination")
        require(isinstance(pagination, dict) and pagination.get("mode") in {"NONE", "CURSOR"}, f"{key} pagination contract missing")
        query_ref: str | None = None
        if pagination.get("mode") == "CURSOR":
            require(operation.get("x-operation-kind") == "READ_COLLECTION", f"{key} cursor pagination on non-collection")
            query_ref = ref_name(pagination.get("query_schema_ref", ""))
            require(query_ref in schemas, f"{key} cursor query schema missing")
            assert_closed_schema(schemas[query_ref], query_ref)
            require("page" in response_properties, f"{key} cursor response lacks page contract")
            assert_closed_schema(response_properties["page"], f"{response_ref}.page")
        else:
            require(pagination == {"mode": "NONE"}, f"{key} NONE pagination contract must be exact")
        if key in write_operations:
            require("requestBody" in operation, f"{key} mutation lacks requestBody")
            require(operation["requestBody"].get("required") is True, f"{key} mutation requestBody must be required=true")
            require(operation.get("x-request-blueprint-id") == request_blueprint_map[key], f"{key} request blueprint metadata drift")
        else:
            require("requestBody" not in operation and "x-request-blueprint-id" not in operation, f"{key} read operation must not carry a request body")
        request_ref: str | None = None
        request_blueprint_id: str | None = None
        if "requestBody" in operation:
            request_ref = ref_name(operation["requestBody"]["content"]["application/json"]["schema"]["$ref"])
            request_blueprint_id = request_blueprint_map[key]
            if service_spec is not None:
                require(request_blueprint_id == service_spec["request_blueprint_id"], f"{key} request blueprint ID drift")
            require(request_ref not in request_refs, f"{key} reuses an operation request schema")
            request_refs.add(request_ref)
            require(request_ref in schemas, f"{key} request schema missing")
            assert_closed_schema(schemas[request_ref], request_ref)
            request_properties = schemas[request_ref].get("properties", {})
            require("attributes" not in request_properties, f"{key} retains generic attributes request wrapper")
            require(not any(name.endswith("_label") for name in request_properties), f"{key} retains inferred label request field")
            require("enabled" not in request_properties and "client_request_id" not in request_properties, f"{key} retains generic fallback request fields")
        categories = operation.get("x-data-use-field-categories")
        require(isinstance(categories, list) and categories == sorted(set(categories)), f"{key} DataUse categories must be sorted and unique")
        semantic_projection = {
            "method": key[0].upper(),
            "path": key[1],
            "operation_id": operation.get("operationId"),
            "domain": operation.get("x-domain"),
            "kind": operation.get("x-operation-kind"),
            "success_status": success[0],
            "parameters": parameters,
            "request_body_required": operation.get("requestBody", {}).get("required") if request_ref else None,
            "security": operation.get("security"),
            "request_ref": request_ref,
            "request_blueprint_id": request_blueprint_id,
            "query_ref": query_ref,
            "response_ref": response_ref,
            "response_blueprint_id": blueprint_id,
            "error_ref": error_ref,
            "request_schema": schemas.get(request_ref) if request_ref else None,
            "query_schema": schemas.get(query_ref) if query_ref else None,
            "response_schema": schemas[response_ref],
            "error_schema": schemas[error_ref],
            "data_use_field_categories": categories,
        }
        if service_spec is not None:
            semantic_projection.update({
                "request_field_contracts": operation.get("x-request-field-contracts"),
                "response_field_contracts": operation.get("x-response-field-contracts"),
                "state_transition": operation.get("x-state-transition"),
                "replay_policy": operation.get("x-replay-policy"),
                "request_log_policy": operation.get("x-request-log-policy"),
            })
        semantic_digest = hashlib.sha256(canonical(semantic_projection)).hexdigest()
        require(operation.get("x-semantic-sha256") == semantic_digest, f"{key} semantic payload digest mismatch")
        semantic_rows.append(semantic_projection)
    aggregate = hashlib.sha256(canonical(sorted(semantic_rows, key=lambda row: (row["path"], row["method"])))).hexdigest()
    contract = api.get("x-semantic-contract", {})
    require(contract == {
        "algorithm": "SHA-256",
        "canonicalization": "RFC8785-compatible integer/string subset",
        "operation_count": 117,
        "aggregate_sha256": aggregate,
    }, "OpenAPI semantic aggregate contract drift")
    require(aggregate == OPENAPI_SEMANTIC_AGGREGATE_SHA256, "OpenAPI semantic aggregate is not independently pinned")
    required_top_level_fields: dict[tuple[str, str], set[str]] = {
        ("get", "/api/v1/public/catalog"): {"catalog_items", "facet_dimensions", "total_item_count", "page"},
        ("get", "/api/v1/public/search"): {"query_echo", "search_hits", "facets", "total_match_count", "page"},
        ("post", "/api/v1/auth/login"): {"access_token", "refresh_session_id", "session_family_id", "mfa_required"},
        ("post", "/api/v1/diagnoses/{id}/turns"): {"next_question", "evidence_progress_microunit", "scoring_policy_digest", "diagnosis_state"},
        ("get", "/api/v1/diagnoses/{id}/results"): {"competency_scores", "overall_confidence_microunit", "evidence_coverage_microunit", "conflict_count", "decision"},
        ("get", "/api/v1/recommendations"): {"recommendations", "policy_version", "page"},
        ("get", "/api/v1/learning-paths/{id}"): {"steps", "dependency_edges", "constraint_codes", "overall_progress_microunit"},
        ("get", "/api/v1/reports/{id}"): {"competency_metrics", "learning_outcome_metrics", "artifact_available"},
        ("get", "/api/v1/reports/{id}/artifact"): {"artifact_id", "artifact_format", "content_sha256"},
        ("post", "/api/v1/search"): {"search_hits", "facets", "retrieval_policy_version"},
        ("post", "/api/v1/rag/sessions/{id}/messages"): {"message_id", "message_state", "answer_text", "claims", "citations", "claim_evidence_bindings", "important_claim_coverage_microunit", "invalid_citation_count"},
        ("get", "/api/v1/drafts/{id}"): {"field_values", "review_decision", "draft_revision"},
        ("post", "/api/v1/drafts/{id}/review"): {"review_decision_id", "review_decision", "reviewed_field_codes"},
        ("post", "/api/v1/drafts/{id}/export"): {"draft_export_id", "export_state", "export_format", "structure_validation_decision"},
        ("get", "/api/v1/admin/metrics-summary"): {"period_start", "period_end", "aggregate_counts", "latency_metrics", "cost_metrics"},
        ("get", "/api/v1/admin/models"): {"models", "page"},
        ("get", "/api/v1/admin/evaluations"): {"evaluations", "page"},
        ("get", "/api/v1/admin/jobs"): {"jobs", "page"},
        ("get", "/api/v1/admin/indexes"): {"indexes", "page"},
        ("get", "/api/v1/admin/storage"): {"storage_state", "object_count", "used_bytes", "last_integrity_scan_at"},
        ("get", "/api/v1/admin/backups"): {"backups", "page"},
        ("get", "/api/v1/admin/integrations"): {"integrations", "checked_at"},
    }
    for key, required_fields in required_top_level_fields.items():
        operation = actual[key]
        success = next(code for code in operation["responses"] if code != "default")
        response_ref = ref_name(operation["responses"][success]["content"]["application/json"]["schema"]["$ref"])
        properties = schemas[response_ref]["properties"]
        require(required_fields.issubset(properties), f"{key} response loses required domain fields: {sorted(required_fields-set(properties))}")

    required_item_fields: dict[tuple[str, str, str], set[str]] = {
        ("get", "/api/v1/public/search", "search_hits"): {"title", "snippet", "content_type"},
        ("get", "/api/v1/recommendations", "recommendations"): {"score_microunit", "reason_codes", "hard_filter_decision", "hard_filter_reason_codes"},
        ("get", "/api/v1/learning-paths/{id}", "steps"): {"dag_node_key", "predecessor_step_ids", "step_state", "progress_microunit"},
        ("post", "/api/v1/search", "search_hits"): {"document_version_id", "source_locator", "snippet", "retrieval_score_microunit", "rights_current"},
        ("post", "/api/v1/rag/sessions/{id}/messages", "claims"): {"claim_id", "claim_text", "grounding_decision"},
        ("post", "/api/v1/rag/sessions/{id}/messages", "citations"): {"claim_id", "evidence_id", "source_locator", "quoted_span", "entailment_microunit", "rights_current"},
        ("get", "/api/v1/admin/models", "models"): {"provider_code", "allowed_data_classes", "health_state"},
        ("get", "/api/v1/admin/evaluations", "evaluations"): {"run_state", "gate_decision"},
        ("get", "/api/v1/admin/jobs", "jobs"): {"job_state", "stage_code", "progress_microunit", "attempt_count"},
        ("get", "/api/v1/admin/indexes", "indexes"): {"index_kind", "index_state", "document_count", "embedding_count"},
        ("get", "/api/v1/admin/backups", "backups"): {"backup_state", "content_sha256", "restore_drill_state"},
        ("get", "/api/v1/admin/integrations", "integrations"): {"integration_type", "integration_state", "circuit_state"},
    }
    for (method, path, field), required_fields in required_item_fields.items():
        operation = actual[(method, path)]
        success = next(code for code in operation["responses"] if code != "default")
        response_ref = ref_name(operation["responses"][success]["content"]["application/json"]["schema"]["$ref"])
        item_properties = schemas[response_ref]["properties"][field]["items"]["properties"]
        require(required_fields.issubset(item_properties), f"{method} {path} {field} loses required item fields: {sorted(required_fields-set(item_properties))}")

    required_request_fields: dict[tuple[str, str], set[str]] = {
        ("patch", "/api/v1/me"): {"display_name", "career_band", "region_category", "interest_keywords", "expected_version"},
        ("patch", "/api/v1/learning-paths/{id}"): {"steps", "constraint_codes", "expected_version"},
        ("patch", "/api/v1/drafts/{id}"): {"field_changes", "expected_version"},
        ("patch", "/api/v1/admin/catalog/{id}"): {"title", "summary", "competency_codes", "prerequisite_codes", "accessibility_features", "region_availability_codes", "publication_state", "expected_version"},
        ("patch", "/api/v1/admin/document-nodes/{id}"): {"normalized_text", "style_ref", "structure_confidence_microunit", "row_version", "reason"},
        ("post", "/api/v1/recommendations/{id}/feedback"): {"decision", "reason", "presentation_context_code"},
    }
    for key, required_fields in required_request_fields.items():
        operation = actual[key]
        request_ref = ref_name(operation["requestBody"]["content"]["application/json"]["schema"]["$ref"])
        request_properties = schemas[request_ref]["properties"]
        require(required_fields.issubset(request_properties), f"{key} request loses required domain fields: {sorted(required_fields-set(request_properties))}")
    assert_closed_schema(schemas["Problem"], "Problem")
    print("PASS: deployed OpenAPI closes 117 response and 61 write request blueprints with exact service-auth, parameters and required bodies")


def verify_asyncapi(root: Path) -> None:
    contract = load(root, "platform-asyncapi.json")
    require(contract.get("asyncapi") == "3.0.0", "AsyncAPI must be 3.0.0")
    channels = contract.get("channels", {})
    require(set(channels) == {"diagnosisTurns", "ragMessages", "jobProgress"}, "AsyncAPI channel closure drift")
    operations = contract.get("operations", {})
    require(set(operations) == {"receiveDiagnosisTurns", "receiveRagMessages", "receiveJobProgress"}, "AsyncAPI operation closure drift")
    for name, channel in channels.items():
        require(channel.get("x-last-event-id-required") is True, f"{name} lacks Last-Event-ID replay contract")
        require(channel.get("x-current-authorization-recheck") is True, f"{name} lacks current authorization recheck")
        require(channel.get("address", "").startswith("/api/v1/"), f"{name} address invalid")
        require(channel.get("x-gap-policy") == "EMIT_STREAM_GAP_AND_REQUIRE_REPLAY", f"{name} gap policy missing")
        require(channel.get("x-terminal-event-required") is True, f"{name} terminal event rule missing")
    payload = contract["components"]["messages"]["SseEvent"]["payload"]
    assert_closed_schema(payload, "AsyncAPI.SseEvent")
    variants = contract.get("components", {}).get("schemas", {})
    expected_variants = {"MessageDeltaEvent", "MessageCompletedEvent", "JobProgressEvent", "JobCompletedEvent", "ErrorEvent", "GapEvent", "HeartbeatEvent"}
    require(set(variants) == expected_variants, "AsyncAPI discriminated event variants drift")
    event_types: set[str] = set()
    for name, schema in variants.items():
        assert_closed_schema(schema, f"AsyncAPI.{name}")
        properties = schema.get("properties", {})
        event_type = properties.get("event_type", {}).get("const")
        require(isinstance(event_type, str) and event_type not in event_types, f"{name} event discriminator invalid")
        event_types.add(event_type)
        require(set(properties) == {"event_id", "event_type", "occurred_at", "trace_id", "sequence", "previous_event_id", "replayed", "terminal", "data"}, f"{name} envelope drift")
    require(event_types == {"message.delta", "message.completed", "job.progress", "job.completed", "error", "stream.gap", "heartbeat"}, "AsyncAPI event type closure drift")
    semantics = contract.get("x-stream-semantics", {})
    require(semantics == {
        "sequence_start": 0,
        "next_sequence_rule": "CURRENT_EQUALS_PREVIOUS_PLUS_ONE",
        "duplicate_rule": "SAME_EVENT_ID_AND_PAYLOAD_HASH_IS_IDEMPOTENT",
        "gap_event_type": "stream.gap",
        "replay_cursor_header": "Last-Event-ID",
        "replay_requires_current_authorization": True,
        "terminal_event_types": ["message.completed", "job.completed", "error"],
        "events_after_terminal": "REJECT",
    }, "AsyncAPI sequence/replay/gap/terminal semantics drift")
    print("PASS: AsyncAPI closes discriminated SSE delta/completed/job/error, sequence, replay, gap and terminal semantics")


def verify_data_use(root: Path, screens: dict[str, Any]) -> dict[str, Any]:
    registry = load(root, "data-use-policy-registry.json")
    require(registry.get("schema_version") == "data-use-policy-registry.v1", "DataUse registry version drift")
    require(registry.get("unknown_category_policy") == "DENY", "unknown DataUse category must deny")
    categories = registry.get("categories", [])
    category_ids = [item.get("category_id") for item in categories]
    require(category_ids == registry.get("category_enum") and len(category_ids) == len(set(category_ids)) >= 8, "DataUse category enum/catalog drift")
    fields = registry.get("fields", [])
    field_codes = [item.get("field_code") for item in fields]
    require(field_codes == registry.get("field_code_enum") and len(field_codes) == len(set(field_codes)) >= 24, "DataUse field enum/catalog drift")
    category_set = set(category_ids)
    field_set = set(field_codes)
    for category in categories:
        require(category.get("classification_floor") in CLASSES, f"{category.get('category_id')} classification invalid")
        require(category.get("purpose_codes") and category.get("field_codes"), f"{category.get('category_id')} purpose/field closure missing")
        require(set(category["field_codes"]).issubset(field_set), f"{category.get('category_id')} unknown field code")
        require(category.get("redaction_profile_id") and isinstance(category.get("external_provider_allowed"), bool), f"{category.get('category_id')} egress rule missing")
    for field in fields:
        require(field.get("category_id") in category_set and field.get("classification") in CLASSES, f"{field.get('field_code')} category/classification invalid")
        require(field.get("source_contract") and field.get("provider_transform") and field.get("log_policy") == "HASH_ONLY", f"{field.get('field_code')} field handling incomplete")
    operation_bindings = registry.get("operation_bindings", [])
    expected_ops = set(screen_operations(screens))
    actual_ops = {(item.get("method", "").lower(), item.get("path")) for item in operation_bindings}
    require(actual_ops == expected_ops and len(operation_bindings) == 113, "DataUse operation closure must equal 113 OpenAPI operations")
    api = load(root, "platform-openapi.json")
    binding_map = {(item["method"].lower(), item["path"]): item for item in operation_bindings}
    for key in expected_ops:
        operation = api["paths"][key[1]][key[0]]
        binding = binding_map[key]
        require(operation.get("x-data-use-field-categories") == binding.get("category_ids"), f"{key} OpenAPI/DataUse category drift")
        require(set(binding.get("category_ids", [])).issubset(category_set), f"{key} unknown DataUse category")
        require(set(binding.get("field_codes", [])).issubset(field_set), f"{key} unknown DataUse field code")
        require(binding.get("purpose_code") and isinstance(binding.get("provider_call_allowed"), bool), f"{key} DataUse execution rule missing")
    authorization = load(root, "operation-authorization-contracts.json")
    authorization_ids = [item.get("operation_id") for item in authorization.get("operations", [])]
    privileged = registry.get("privileged_operation_bindings", [])
    privileged_ids = [item.get("privileged_operation_id") for item in privileged]
    require(privileged_ids == authorization_ids and len(privileged_ids) == len(set(privileged_ids)) == 8, "DataUse/high-privilege operation closure drift")
    canonical_ids: set[str] = set()
    for binding in privileged:
        canonical = binding.get("canonical_http_operation_id")
        require(canonical == f"{binding.get('method')} {binding.get('path')}" and canonical not in canonical_ids, f"{binding.get('privileged_operation_id')} canonical operation duplicate/drift")
        canonical_ids.add(canonical)
        require(binding.get("method") == "POST" and str(binding.get("path", "")).startswith("/internal/operations/v1/"), f"{binding.get('privileged_operation_id')} internal command path invalid")
        require(binding.get("task") and binding.get("purpose_code") and binding.get("destination"), f"{binding.get('privileged_operation_id')} task/purpose/destination missing")
        require(set(binding.get("category_ids", [])).issubset(category_set) and set(binding.get("field_codes", [])).issubset(field_set), f"{binding.get('privileged_operation_id')} allowlist invalid")
        require(binding.get("provider_call_allowed") is False, f"{binding.get('privileged_operation_id')} high-privilege provider call must be denied")
    receipt = registry.get("redaction_receipt_contract", {})
    require(receipt.get("hash_algorithm") == "SHA-256" and receipt.get("provider_call_count_on_denial") == 0, "redaction denial must produce hash receipt and zero provider calls")
    require(set(receipt.get("required_fields", [])) >= {"receipt_id", "policy_version", "input_hash", "output_hash", "removed_field_codes", "decision", "provider_call_count"}, "redaction receipt fields incomplete")
    print("PASS: exact DataUse fields bind 113 HTTP and 8 high-privilege operations with zero-call denial receipts")
    return registry


def verify_ai(root: Path, data_use: dict[str, Any]) -> None:
    contract = load(root, "ai-service-contracts.json")
    require(contract.get("classification_vocabulary") == CLASSES, "AI classification vocabulary drift")
    require(contract.get("safeguarding_decisions") == SAFEGUARDING, "AI safeguarding decision vocabulary drift")
    endpoints = {(item.get("method"), item.get("path")) for item in contract.get("endpoints", [])}
    require(endpoints == {("POST", "/internal/ai/v1/responses"), ("POST", "/internal/ai/v1/embeddings"), ("POST", "/internal/ai/v1/rerank")}, "AI endpoint closure drift")
    tasks = contract.get("task_contracts", [])
    require({task.get("task") for task in tasks} == TASKS and len(tasks) == 9, "AI task closure must be exact nine")
    for task in tasks:
        require(task.get("repair_budget") == 1, f"{task.get('task')} repair budget drift")
        require(task.get("fallback_requires_new_data_use_context") is True, f"{task.get('task')} fallback privacy invariant missing")
        assert_closed_schema(task.get("input_schema"), f"{task.get('task')}.input")
        assert_closed_schema(task.get("output_schema"), f"{task.get('task')}.output")
        data_contract = task.get("data_use_contract", {})
        require(data_contract.get("registry_ref") == "data-use-policy-registry.json", f"{task.get('task')} DataUse registry link missing")
        require(data_contract.get("task") == task.get("task"), f"{task.get('task')} DataUse task binding drift")
        require(data_contract.get("category_ids") and data_contract.get("field_codes"), f"{task.get('task')} DataUse allowlist empty")
        require(set(data_contract["category_ids"]).issubset(set(data_use["category_enum"])), f"{task.get('task')} unknown DataUse category")
        require(set(data_contract["field_codes"]).issubset(set(data_use["field_code_enum"])), f"{task.get('task')} unknown DataUse field")
        require("data_use_context" in task["input_schema"].get("properties", {}), f"{task.get('task')} input omits DataUse context")
    task_map = {item["task"]: item for item in tasks}
    evidence_output = task_map["diagnosis.evidence.extract"]["output_schema"]["properties"]
    evidence_item = evidence_output["evidence"]["items"]
    evidence_fields = set(evidence_item.get("properties", {}))
    require({"dialogue_turn_id", "anchor_id", "start_offset", "end_offset", "quoted_span_sha256", "entailment_microunit", "relevance_microunit", "specificity_microunit", "contradiction_risk_microunit", "evidence_strength_microunit", "scoring_policy_version", "eligibility_decision"}.issubset(evidence_fields), "diagnosis evidence scoring/anchor contract incomplete")
    grounded = task_map["document.grounded_answer"]["output_schema"]["properties"]
    require({"claims", "citations", "claim_citation_bindings", "important_claim_coverage_microunit", "invalid_citation_count"}.issubset(grounded), "grounded answer claim/citation binding contract incomplete")
    binding_fields = set(grounded["claim_citation_bindings"]["items"].get("properties", {}))
    require({"claim_id", "citation_id", "evidence_id", "relation", "entailment_microunit", "rights_snapshot_hash"}.issubset(binding_fields), "claim/citation many-to-many edge incomplete")
    grounding = contract.get("grounding_binding_contract", {})
    require(grounding.get("cardinality") == "CLAIM_M:N_CITATION_VIA_BINDING" and grounding.get("unique_key") == ["claim_id", "citation_id"], "claim/citation cardinality or uniqueness drift")
    scoring = contract.get("evidence_scoring_contract", {})
    require(scoring.get("scale") == 1_000_000 and scoring.get("policy_version") and scoring.get("formula") and scoring.get("invalid_precedence") is True, "evidence scoring policy incomplete")
    assert_closed_schema(contract.get("embedding_contract"), "embedding_contract")
    assert_closed_schema(contract.get("rerank_contract"), "rerank_contract")
    require(contract.get("response_invariants", {}).get("all_objects_closed") is True, "AI closed-object invariant missing")
    print("PASS: AI tasks close evidence scoring, grounded claim/citation bindings and exact DataUse allowlists")


def verify_entities(root: Path) -> None:
    catalog = load(root, "persistent-domain-catalog.json")
    require(hashlib.sha256(canonical(catalog)).hexdigest() == PERSISTENT_DOMAIN_CATALOG_SHA256, "persistent domain catalog physical topology is not independently pinned")
    requirement_catalog = load(root, "entity-catalog.json")
    require(catalog.get("classification_vocabulary") == CLASSES, "entity classification vocabulary drift")
    require(catalog.get("classification_order") == CLASSES, "entity classification order drift")
    require(catalog.get("unknown_classification_default") == "RESTRICTED", "unknown classification must deny as RESTRICTED")
    require(catalog.get("derived_data_rule") == "MAX_OF_SOURCES", "derived classification inheritance drift")
    suppression = catalog.get("suppression_default", {})
    require(suppression.get("minimum_group_size") == 10 and suppression.get("minimum_allowed") == 5, "privacy suppression default/minimum drift")
    entities = catalog.get("entities", [])
    require(catalog.get("entity_count") == len(entities) == 102, "entity_count must close exactly 102 persistent entities")
    by_id = {item.get("entity_id"): item for item in entities}
    require(len(by_id) == len(entities), "duplicate entity_id")
    require(REQUIRED_ENTITIES.issubset(by_id), f"required entity gap: {sorted(REQUIRED_ENTITIES-set(by_id))}")
    requirement_entities = {item.get("entity_id") for item in requirement_catalog.get("entities", [])}
    require(len(requirement_entities) == 58 and requirement_entities.issubset(by_id), f"physical catalog misses requirement-facing entities: {sorted(requirement_entities-set(by_id))}")
    seen_constraint_names: set[str] = set()
    seen_index_names: set[str] = set()

    def reserve_name(name: Any, seen: set[str], kind: str, where: str) -> None:
        require(isinstance(name, str) and name, f"{where} {kind} name missing")
        require(name not in seen, f"duplicate {kind} name {name}")
        seen.add(name)

    for entity_id, item in by_id.items():
        require(item.get("classification_floor") in CLASSES, f"{entity_id} classification invalid")
        require(item.get("classification_mode") in {"FIXED_FLOOR", "MAX_OF_SOURCES"}, f"{entity_id} inheritance mode invalid")
        require(item.get("retention_policy_id") and item.get("deletion_policy"), f"{entity_id} lifecycle policy missing")
        require(item.get("fields") and item.get("primary_key") and item.get("indexes") and item.get("cardinality"), f"{entity_id} physical model incomplete")
        require(item.get("delete_contract", {}).get("strategy") == item.get("deletion_policy"), f"{entity_id} delete strategy is not executable")
        require(item.get("delete_contract", {}).get("audit_ledger_required") is True, f"{entity_id} delete audit ledger missing")
        require(item.get("retention_contract", {}).get("policy_id") == item.get("retention_policy_id"), f"{entity_id} retention contract drift")
        require(isinstance(item.get("unique_constraints"), list) and isinstance(item.get("check_constraints"), list), f"{entity_id} unique/check contract missing")
        if item.get("domain") in CORE_PHYSICAL_DOMAINS:
            require(item["unique_constraints"], f"{entity_id} core domain has zero unique constraints")
            require(item["check_constraints"], f"{entity_id} core domain has zero check constraints")
        field_name_list = [field.get("name") for field in item["fields"]]
        require(all(isinstance(name, str) and name for name in field_name_list), f"{entity_id} field name missing")
        require(len(field_name_list) == len(set(field_name_list)), f"{entity_id} field names must be unique")
        field_names = set(field_name_list)
        field_by_name = {field["name"]: field for field in item["fields"]}
        require(set(item["primary_key"]).issubset(field_names), f"{entity_id} PK field missing")
        require(len(item["primary_key"]) == len(set(item["primary_key"])), f"{entity_id} PK columns must be unique")
        require(all(field_by_name[name].get("nullable") is False for name in item["primary_key"]), f"{entity_id} PK columns must be nullable=false")
        if item.get("tenant_scope") == "TENANT":
            require(item["primary_key"][:1] == ["tenant_id"] and item.get("rls_required") is True, f"{entity_id} tenant isolation incomplete")
            require(any(index.get("columns", [])[:1] == ["tenant_id"] for index in item["indexes"]), f"{entity_id} tenant index missing")
        for foreign_key in item.get("foreign_keys", []):
            reserve_name(foreign_key.get("name"), seen_constraint_names, "constraint", entity_id)
            target_id = foreign_key.get("references")
            require(target_id in by_id, f"{entity_id} FK target missing")
            local_columns = foreign_key.get("columns", [])
            referenced_columns = foreign_key.get("referenced_columns", [])
            require(local_columns and len(local_columns) == len(set(local_columns)) and set(local_columns).issubset(field_names), f"{entity_id} FK local fields missing/duplicate")
            require(len(local_columns) == len(referenced_columns) and len(referenced_columns) == len(set(referenced_columns)), f"{entity_id} FK arity/target column duplication invalid")
            target = by_id[target_id]
            target_fields = {field.get("name"): field for field in target.get("fields", [])}
            require(set(referenced_columns).issubset(target_fields), f"{entity_id} FK referenced target fields missing")
            candidate_keys = [target.get("primary_key", [])] + [row.get("columns", []) for row in target.get("unique_constraints", [])]
            require(referenced_columns in candidate_keys, f"{entity_id} FK target columns are not exact PK/UNIQUE")
            require(all(field_by_name[local]["type"] == target_fields[remote]["type"] for local, remote in zip(local_columns, referenced_columns)), f"{entity_id} FK local/target types incompatible")
            require(foreign_key.get("on_delete") in {"RESTRICT", "CASCADE", "SET_NULL"}, f"{entity_id} FK contract incomplete")
        for unique in item["unique_constraints"]:
            reserve_name(unique.get("name"), seen_constraint_names, "constraint", entity_id)
            require(unique.get("columns") and len(unique["columns"]) == len(set(unique["columns"])) and set(unique["columns"]).issubset(field_names), f"{entity_id} unique constraint invalid")
        for check in item["check_constraints"]:
            reserve_name(check.get("name"), seen_constraint_names, "constraint", entity_id)
            require(check.get("expression") and check.get("enforcement") in {"DATABASE", "DATABASE_AND_SERVICE"}, f"{entity_id} check constraint invalid")
        for index in item["indexes"]:
            reserve_name(index.get("name"), seen_index_names, "index", entity_id)
            require(index.get("columns") and len(index["columns"]) == len(set(index["columns"])) and set(index["columns"]).issubset(field_names), f"{entity_id} index invalid")
            require(index.get("method") in {"btree", "gin", "gist", "hnsw"}, f"{entity_id} index method missing")
    for entity_id, required_fields in REQUIRED_ENTITY_FIELDS.items():
        actual_fields = {field.get("name") for field in by_id[entity_id]["fields"]}
        require(required_fields.issubset(actual_fields), f"{entity_id} specialized field gap: {sorted(required_fields-actual_fields)}")
    user_fields = {field.get("name") for field in by_id["User"]["fields"]}
    require(not {"password_hash", "password_algorithm", "password_changed_at", "failed_login_count", "locked_until"}.intersection(user_fields), "User must not store credential material/state")
    credential = by_id["PasswordCredential"]
    require(
        credential.get("tenant_scope") == "GLOBAL"
        and any(fk.get("references") == "User" and fk.get("columns") == ["user_id"] and fk.get("on_delete") == "RESTRICT" for fk in credential.get("foreign_keys", []))
        and any(unique.get("columns") == ["user_id"] for unique in credential.get("unique_constraints", [])),
        "PasswordCredential must be a one-to-one User credential boundary",
    )
    require(
        any(
            fk.get("references") == "DialogueTurn"
            and fk.get("columns") == ["tenant_id", "dialogue_turn_id", "turn_sequence"]
            and fk.get("referenced_columns") == ["tenant_id", "id", "sequence"]
            for fk in by_id["EvidenceSpan"].get("foreign_keys", [])
        ),
        "EvidenceSpan must bind its turn_sequence through a composite DialogueTurn FK",
    )
    require(
        any(fk.get("references") == "Claim" and fk.get("columns") == ["tenant_id", "claim_id"] for fk in by_id["Citation"].get("foreign_keys", [])),
        "Citation must have a tenant-scoped Claim FK",
    )
    value_objects = catalog.get("value_object_contracts", {})
    require(set(value_objects) >= {"RubricIndicator", "EvidenceAnchorRule", "DiagnosticQuestion", "LearningDagEdge", "DocumentProvenance", "PersonaFeatureCoefficient"}, "persistent value-object contracts incomplete")
    for name, schema in value_objects.items():
        assert_closed_schema(schema, f"value_object_contracts.{name}")
    associations = catalog.get("association_contracts", {})
    edge = associations.get("LearningPathStepDependency", {})
    edge_field_rows = edge.get("fields", [])
    edge_field_names = [field.get("name") for field in edge_field_rows]
    require(len(edge_field_names) == len(set(edge_field_names)), "LearningPathStepDependency field names must be unique")
    edge_fields = set(edge_field_names)
    edge_field_by_name = {field["name"]: field for field in edge_field_rows}
    require(
        edge.get("table_name") == "learning_path_step_dependency"
        and edge.get("array_fk_forbidden") is True
        and edge.get("rls_required") is True
        and edge.get("primary_key") == ["tenant_id", "learning_path_id", "predecessor_step_id", "successor_step_id"]
        and edge_fields == {"tenant_id", "learning_path_id", "predecessor_step_id", "successor_step_id", "edge_type"},
        "LearningPathStepDependency physical association contract incomplete",
    )
    require(all(edge_field_by_name[name].get("nullable") is False for name in edge.get("primary_key", [])), "LearningPathStepDependency PK columns must be nullable=false")
    edge_fks = edge.get("foreign_keys", [])
    require(
        len(edge_fks) == 2
        and {fk.get("columns", [])[-1] for fk in edge_fks} == {"predecessor_step_id", "successor_step_id"}
        and all(fk.get("references") == "LearningPathStep" and fk.get("referenced_columns") == ["tenant_id", "learning_path_id", "id"] for fk in edge_fks),
        "LearningPathStepDependency predecessor/successor FKs incomplete",
    )
    target_step = by_id["LearningPathStep"]
    target_step_fields = {field["name"]: field for field in target_step["fields"]}
    target_step_candidate_keys = [target_step["primary_key"]] + [row["columns"] for row in target_step["unique_constraints"]]
    for foreign_key in edge_fks:
        reserve_name(foreign_key.get("name"), seen_constraint_names, "constraint", "LearningPathStepDependency")
        require(len(foreign_key["columns"]) == len(foreign_key["referenced_columns"]), "LearningPathStepDependency FK arity invalid")
        require(foreign_key["referenced_columns"] in target_step_candidate_keys, "LearningPathStepDependency FK target is not exact PK/UNIQUE")
        require(all(edge_field_by_name[local]["type"] == target_step_fields[remote]["type"] for local, remote in zip(foreign_key["columns"], foreign_key["referenced_columns"])), "LearningPathStepDependency FK types incompatible")
    edge_checks = {check.get("name"): check for check in edge.get("check_constraints", [])}
    require(
        set(edge_checks) == {"ck_learning_edge_no_self", "ck_learning_edge_acyclic"}
        and edge_checks["ck_learning_edge_acyclic"].get("enforcement") == "DATABASE_AND_SERVICE",
        "LearningPathStepDependency self/cycle enforcement incomplete",
    )
    for check in edge.get("check_constraints", []):
        reserve_name(check.get("name"), seen_constraint_names, "constraint", "LearningPathStepDependency")
    require("predecessor_step_ids" not in {field.get("name") for field in by_id["LearningPathStep"]["fields"]}, "LearningPathStep must not use unenforceable predecessor UUID arrays")
    immutable = catalog.get("immutable_artifact_contracts", {})
    rubric_immutable = immutable.get("RubricVersion", {})
    persona_immutable = immutable.get("PersonaDefinition", {})
    require(
        rubric_immutable.get("value_object_fields") == ["indicator_catalog", "evidence_anchor_catalog", "question_catalog"]
        and rubric_immutable.get("digest_fields") == ["indicator_catalog_digest", "anchor_catalog_digest", "question_catalog_digest", "artifact_digest"]
        and rubric_immutable.get("digest_algorithm") == "SHA-256"
        and "IMMUTABLE" in rubric_immutable.get("mutation_rule", ""),
        "RubricVersion value-object schema/digest immutability boundary incomplete",
    )
    require(
        persona_immutable.get("value_object_fields") == ["feature_coefficient_catalog"]
        and persona_immutable.get("digest_fields") == ["feature_coefficients_hash", "artifact_digest"]
        and persona_immutable.get("digest_algorithm") == "SHA-256"
        and "IMMUTABLE" in persona_immutable.get("mutation_rule", ""),
        "PersonaDefinition coefficient/artifact immutability boundary incomplete",
    )
    policy_registry = catalog.get("retention_policy_registry", [])
    require({item.get("policy_id") for item in policy_registry} == set(RETENTION_POLICY_IDS), "retention policy registry closure drift")
    for derived in {"FileObject", "ProcessingJob", "Artifact", "DocumentNode", "TableCell", "Chunk", "EmbeddingRecord", "IndexSnapshot", "Citation", "GeneratedDraft"}:
        require(by_id[derived].get("classification_mode") == "MAX_OF_SOURCES", f"{derived} must inherit maximum source classification")
    print(f"PASS: persistent catalog closes {len(entities)} entities with implementable keys, unique/check/index, retention, deletion and domain topology")


def div_half_up(numerator: int, denominator: int) -> int:
    require(denominator > 0, "division denominator must be positive")
    return (2 * numerator + denominator) // (2 * denominator)


def rag_score(vector: dict[str, Any], policy: dict[str, Any]) -> dict[str, int]:
    values = vector["input"]
    scale = policy["scale"]
    k = policy["rrf_k"]
    ranks = values["ranks"]
    contributions = [0 if rank is None else div_half_up(scale, k + rank) for rank in ranks]
    max_sum = len(ranks) * div_half_up(scale, k + 1)
    rrf = div_half_up(scale * sum(contributions), max_sum)
    weights = policy["weights_microunit"]
    weighted = div_half_up(weights["rrf"] * rrf + weights["metadata"] * values["metadata_microunit"] + weights["structure"] * values["structure_microunit"], scale)
    penalty = div_half_up(weights["duplicate_penalty"] * values["duplicate_microunit"], scale)
    return {"rrf_microunit": rrf, "final_score_microunit": max(0, weighted - penalty)}


def verify_rag(root: Path) -> None:
    contract = load(root, "rag-policy-golden-vectors.json")
    policy = contract.get("retrieval_policy", {})
    require(policy.get("policy_version") == "retrieval-ranking.v1", "retrieval policy version drift")
    require(policy.get("scale") == 1_000_000 and policy.get("rrf_k") == 60, "retrieval fixed-point/RRF drift")
    require(policy.get("candidate_budgets") == {"lexical": 100, "vector": 100, "metadata_union_max": 200, "rerank_input_max": 80, "evidence_budget_max": 20}, "retrieval candidate budget drift")
    require(policy.get("acl_filter_stage") == "BEFORE_LEXICAL_AND_ANN_CANDIDATE_GENERATION", "ACL must filter before retrieval")
    require(policy.get("weights_microunit") == {"rrf": 800_000, "metadata": 100_000, "structure": 100_000, "duplicate_penalty": 50_000}, "retrieval weight drift")
    require(policy.get("tie_break") == ["final_score_microunit DESC", "current_rights_decision=ALLOW", "effective_at DESC", "document_version_id UTF8 ASC", "chunk_id UTF8 ASC"], "retrieval tie-break drift")
    for vector in contract.get("retrieval_vectors", []):
        require(rag_score(vector, policy) == vector.get("expected"), f"retrieval golden vector {vector.get('vector_id')} mismatch")
    claim = contract.get("claim_citation_policy", {})
    require(claim.get("entailment_microunit_minimum") == 850_000, "citation entailment threshold drift")
    require(claim.get("important_claim_coverage_minimum") == 950_000, "important claim coverage drift")
    require(claim.get("invalid_citation_maximum") == 0, "invalid citation budget must be zero")
    validity = set(claim.get("validity_checks", []))
    require({"CURRENT_TENANT_MEMBERSHIP", "CURRENT_ACL_VERSION", "CURRENT_PUBLICATION_AND_LICENSE", "ENTAILMENT_THRESHOLD"}.issubset(validity), "current-rights/entailment citation check missing")
    quality = contract.get("document_quality_policy", {})
    weights = quality.get("weights_microunit", {})
    require(quality.get("scale") == 1_000_000 and sum(weights.values()) == 1_000_000, "document quality fixed-point weights drift")
    require(quality.get("automatic_review_candidate_minimum") == 900_000 and quality.get("sample_review_minimum") == 750_000, "document quality boundary drift")
    require(quality.get("automatic_publish") is False, "document quality must never auto-publish")
    ordered_weights = [weights[key] for key in ["text", "reading_order", "table_structure", "style_preservation", "metadata"]]
    for vector in contract.get("quality_vectors", []):
        computed = div_half_up(sum(w * value for w, value in zip(ordered_weights, vector["input_scores_microunit"])), 1_000_000)
        require(computed == vector.get("expected_quality_microunit"), f"quality golden vector {vector.get('vector_id')} mismatch")
    print("PASS: deterministic RAG, claim/citation rights and fixed-point document quality vectors close")


def verify_provider(root: Path) -> None:
    registry = load(root, "provider-decision-registry.json")
    routes = registry.get("routing_invariants", {})
    require(set(routes) == {*CLASSES, "unknown"}, "provider routing class closure drift")
    require(routes.get("RESTRICTED") == ["INTERNAL_SLLM", "DETERMINISTIC"], "RESTRICTED data must remain local-only")
    require(not any("EXTERNAL" in route for route in routes["RESTRICTED"]), "RESTRICTED external provider route forbidden")
    require(routes.get("unknown") == ["DENY"], "unknown class must deny")
    decisions = registry.get("decisions", [])
    require(len(decisions) >= 6, "provider/OCR/hardware decision coverage incomplete")
    subjects = " ".join(
        f"{item.get('decision_id', '')} {item.get('subject', '')}".lower()
        for item in decisions
    )
    for keyword in ("openai", "sllm", "ocr", "embedding", "hardware", "hwp"):
        require(keyword in subjects, f"decision registry lacks {keyword}")
    for item in decisions:
        require(item.get("decision_id") and item.get("status") and item.get("owner_ids") and item.get("due_at") and item.get("required_input_ids") and item.get("gate_ids"), f"decision {item.get('decision_id')} is not actionable")
    model = registry.get("model_acceptance", {})
    require(model.get("diagnosis_agreement_minimum") == 0.85, "diagnosis gate drift")
    require(model.get("recommendation_relevance_minimum") == 0.90, "recommendation gate drift")
    require(model.get("rag_top5_minimum") == 0.95, "RAG gate drift")
    require(model.get("structured_output_minimum") == 0.998, "structured output gate drift")
    require(model.get("restricted_external_events_maximum") == 0, "RESTRICTED external event budget must be zero")
    print("PASS: OpenAI/sLLM/OCR/embedding/hardware decisions and local-only RESTRICTED routing close")


def verify_reuse(root: Path) -> None:
    matrix = load(root, "legacy-reuse-decision-matrix.json")
    registry = load(root, "requirements-test-registry.json")
    registered_test_ids = {item.get("test_id") for item in registry.get("tests", [])}
    require(matrix.get("decision_vocabulary") == ["REUSE", "ADAPT", "REWRITE", "RETIRE"], "legacy decision vocabulary drift")
    assets = matrix.get("assets", [])
    require(len(assets) >= 14 and len({item.get("asset_id") for item in assets}) == len(assets), "legacy asset closure incomplete")
    capabilities = " ".join(item.get("capability", "").lower() for item in assets)
    for required in ("authentication", "migration", "admin bootstrap", "docker", "backup/restore", "storageadapter", "public resource", "notice/article/faq", "content pack", "inquiry", "bookmark", "monolithic", "playwright", "reference source"):
        require(required in capabilities, f"legacy reuse matrix lacks {required}")
    for item in assets:
        require(item.get("decision") in matrix["decision_vocabulary"], f"{item.get('asset_id')} decision invalid")
        require(item.get("source_paths") and item.get("characterization_test_ids") and item.get("target_contract_ids"), f"{item.get('asset_id')} lacks characterization/target closure")
        require(set(item["characterization_test_ids"]).issubset(registered_test_ids), f"{item.get('asset_id')} references orphan characterization test")
        require(not any(test_id.startswith("T-LEG-") for test_id in item["characterization_test_ids"]), f"{item.get('asset_id')} retains unregistered T-LEG test")
        require("third-party portal" in item.get("clean_room_rule", ""), f"{item.get('asset_id')} clean-room rule missing")
    require("ContentItem" in matrix.get("portal_content_rule", ""), "legacy public content preservation rule missing")
    auth = matrix.get("authentication_api_union_contract", {})
    require(
        auth.get("contract_id") == "deployed-auth-api-union.v1"
        and auth.get("screen_scoped_contract_ref") == "platform-openapi.json"
        and auth.get("screen_scoped_operation_count") == 113
        and auth.get("screen_scoped_write_operation_count") == 57
        and auth.get("deployed_operation_count") == 117
        and auth.get("deployed_write_operation_count") == 61,
        "deployed authentication union header/screen scope drift",
    )
    api = load(root, "platform-openapi.json")
    actual_screen_auth = {
        f"{method.upper()} {path}"
        for path, path_item in api.get("paths", {}).items()
        for method in path_item
        if method in {"get", "post", "patch", "put", "delete"} and path.startswith("/api/v1/auth/") and path_item[method].get("x-service-only") is not True
    }
    screen_auth = auth.get("screen_scoped_auth_operation_ids", [])
    require(set(screen_auth) == actual_screen_auth and len(screen_auth) == len(actual_screen_auth) == 9, "screen-scoped auth operation set drift")
    expected_service_operations = {
        "POST /api/v1/auth/refresh",
        "POST /api/v1/auth/logout",
        "POST /api/v1/auth/logout-all",
        "POST /api/v1/auth/password-resets/confirm",
    }
    service_operations = auth.get("service_only_operations", [])
    service_by_id = {item.get("operation_id"): item for item in service_operations}
    require(set(service_by_id) == expected_service_operations and len(service_operations) == 4, "service-only auth operation closure drift")
    actual_deployed_auth = {
        f"{method.upper()} {path}"
        for path, path_item in api.get("paths", {}).items()
        for method in path_item
        if method in {"get", "post", "patch", "put", "delete"} and path.startswith("/api/v1/auth/")
    }
    deployed = auth.get("deployed_required_auth_operation_ids", [])
    require(
        deployed == screen_auth + [item.get("operation_id") for item in service_operations]
        and len(deployed) == len(set(deployed)) == 13,
        "deployed auth operation union must be exact 9 screen plus 4 service operations",
    )
    require(set(deployed) == actual_deployed_auth, "deployed OpenAPI authentication set must equal exact 13-operation union")
    require(
        auth.get("merge_rule") == "DEPLOYED_OPENAPI_AUTH_SET_EQUALS_SCREEN_SCOPED_UNION_SERVICE_ONLY"
        and auth.get("duplicate_operation_policy") == "REJECT"
        and auth.get("missing_operation_policy") == "FAIL_RELEASE"
        and auth.get("acceptance_test_ids") == ["T-API-001", "T-SEC-005"]
        and auth.get("owner_ids") == ["OWN-ARCH", "OWN-SEC"],
        "deployed auth union merge/release policy drift",
    )
    requirement_ids = {
        item.get("requirement_id")
        for group in (registry.get("rfp_requirements", []), registry.get("system_requirements", []))
        for item in group
    }
    data_use = load(root, "data-use-policy-registry.json")
    category_ids = set(data_use.get("category_enum", []))
    field_codes = set(data_use.get("field_code_enum", []))
    expected_specs = expected_service_auth_contracts()
    for key, spec in expected_specs.items():
        operation_id = f"{key[0].upper()} {key[1]}"
        operation = service_by_id[operation_id]
        expected_row = {
            "operation_id": operation_id,
            "request_field_codes": [row["field_code"] for row in spec["request_field_contracts"]],
            "response_field_codes": [row["field_code"] for row in spec["response_field_contracts"]],
            "request_field_contracts": spec["request_field_contracts"],
            "response_field_contracts": spec["response_field_contracts"],
            "success_status": spec["success_status"],
            "error_codes": spec["error_codes"],
            "security": spec["security"],
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
            expected_row["secret_request_field_codes"] = spec["secret_request_field_codes"]
            expected_row["secret_path_parameter_count"] = spec["secret_path_parameter_count"]
        require(operation == expected_row, f"{operation_id} exact request/response/status/error/security/state contract drift")
        require(set(operation["requirement_ids"]).issubset(requirement_ids), f"{operation_id} unknown requirement binding")
        require(set(operation["test_ids"]).issubset(registered_test_ids), f"{operation_id} unknown test binding")
        require(set(operation["data_use_category_ids"]).issubset(category_ids), f"{operation_id} unknown DataUse category")
        require(set(operation["data_use_field_codes"]).issubset(field_codes), f"{operation_id} unknown DataUse field")
        openapi_operation = api["paths"][key[1]][key[0]]
        require(openapi_operation.get("x-request-field-contracts") == spec["request_field_contracts"], f"{operation_id} matrix/OpenAPI request field drift")
        require(openapi_operation.get("x-response-field-contracts") == spec["response_field_contracts"], f"{operation_id} matrix/OpenAPI response field drift")
        require(openapi_operation.get("x-state-transition") == spec["state_transition"] and openapi_operation.get("x-replay-policy") == spec["replay_policy"], f"{operation_id} matrix/OpenAPI transition drift")
    reset_confirm = service_by_id["POST /api/v1/auth/password-resets/confirm"]
    require(
        reset_confirm.get("secret_request_field_codes") == ["ONE_TIME_RESET_TOKEN", "NEW_PASSWORD"]
        and reset_confirm.get("request_log_policy") == "NEVER"
        and reset_confirm.get("secret_path_parameter_count") == 0
        and "{" not in reset_confirm["operation_id"],
        "password reset token/password must remain body-only secrets and never enter URL/logs",
    )
    leg_auth = next(item for item in assets if item.get("asset_id") == "LEG-001")
    require("deployed-auth-api-union.v1" in leg_auth.get("target_contract_ids", []) and leg_auth.get("characterization_test_ids") == ["T-API-001", "T-SEC-005"], "LEG-001 is not bound to deployed auth union tests")
    print("PASS: legacy REUSE/ADAPT/REWRITE/RETIRE matrix preserves useful portal capability under characterization")


def verify_thresholds(root: Path) -> None:
    registry = load(root, "acceptance-threshold-registry.json")
    semantics = load(root, "normative-test-semantics.json")
    require(registry.get("schema_version") == "acceptance-threshold-registry.v1", "threshold registry version drift")
    require(registry.get("unknown_symbol_policy") == "DENY", "undefined threshold symbols must deny")
    expected = {
        "THR-AI-SPAN-F1": ("T-AI-001", 850_000, "microunit_ratio", "MINIMUM", "OWN-AI"),
        "THR-AI-FAIRNESS-MAX-GAP": ("T-AI-007", 100_000, "microunit_ratio", "MAXIMUM", "OWN-AI"),
        "THR-DEP-ROLLBACK-MAX-MS": ("T-DEP-003", 300_000, "milliseconds", "MAXIMUM", "OWN-OPS"),
        "THR-CODE-STATEMENT-COVERAGE": ("T-GATE-001", 850_000, "microunit_ratio", "MINIMUM", "OWN-QA"),
        "THR-CODE-BRANCH-COVERAGE": ("T-GATE-001", 800_000, "microunit_ratio", "MINIMUM", "OWN-QA"),
        "THR-REC-CONTENT-COVERAGE": ("T-REC-004", 950_000, "microunit_ratio", "MINIMUM", "OWN-AI"),
        "THR-REC-DIVERSITY": ("T-REC-004", 800_000, "microunit_ratio", "MINIMUM", "OWN-AI"),
        "THR-UX-TASK-COMPLETION": ("T-UX-008", 900_000, "microunit_ratio", "MINIMUM", "OWN-UX"),
        "THR-UX-MEDIAN-TIME-MS": ("T-UX-008", 180_000, "milliseconds", "MAXIMUM", "OWN-UX"),
    }
    rows = registry.get("thresholds", [])
    by_id = {item.get("threshold_id"): item for item in rows}
    require(set(by_id) == set(expected) and len(rows) == len(expected), "threshold registry is not exact")
    semantic_by_id = {item.get("test_id"): item for item in semantics.get("tests", [])}
    expected_row_keys = {
        "threshold_id", "test_ids", "value", "unit", "comparison_role", "decision_id",
        "owner_ids", "status", "effective_at", "due_at", "source_contract_ids",
        "candidate_binding", "change_control_gate_id",
    }
    for threshold_id, (test_id, value, unit, comparison_role, owner) in expected.items():
        row = by_id[threshold_id]
        require(set(row) == expected_row_keys, f"{threshold_id} row schema must be exact and closed")
        expected_row = {
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
        require(row == expected_row, f"{threshold_id} approved decision/source/owner/candidate baseline drift")
        require(str(value) in semantic_by_id[test_id].get("acceptance_formula", ""), f"{threshold_id} exact value absent from test formula")
    for test in semantics.get("tests", []):
        formula = test.get("acceptance_formula", "")
        require(not re.search(r"\bapproved_[a-z0-9_]+\b", formula), f"{test.get('test_id')} has undefined approved threshold symbol")
    fairness = semantic_by_id["T-AI-007"].get("acceptance_formula", "")
    require("release_blocked" not in fairness and " OR " not in fairness, "T-AI-007 must not pass by release-blocked alternative")
    transition = registry.get("failure_release_transition", {})
    require(transition == {"test_id": "T-AI-007", "on_failure": "NOT_READY", "test_result": "FAIL", "release_blocked_is_not_pass": True}, "fairness release-state separation drift")
    procedure_text = (root / "09-test-procedure-acceptance.md").read_text(encoding="utf-8")
    require("승인 fairness gap 이내 또는 배포 차단" not in procedure_text, "T-AI-007 procedure retains blocked-as-acceptance wording")
    require("초과는 FAIL" in procedure_text and "INSUFFICIENT_DATA" in procedure_text and "PASS가 아님" in procedure_text, "T-AI-007 procedure must separate PASS, FAIL and insufficient-data release blocks")
    print("PASS: all symbolic thresholds are exact decisions and fairness blocking cannot become PASS")


def verify_final_inventory(root: Path) -> None:
    inventory = load(root, "final-document-inventory.json")
    artifacts = inventory.get("artifacts", [])
    expected_counts = inventory.get("expected_counts", {})
    require(expected_counts.get("total") == len(artifacts), "final inventory total does not equal artifact rows")
    groups: dict[str, int] = {}
    for artifact in artifacts:
        groups[artifact.get("group")] = groups.get(artifact.get("group"), 0) + 1
    require(all(expected_counts.get(group) == count for group, count in groups.items()), "final inventory per-group counts drift")
    require(len(artifacts) == 147 and expected_counts.get("design") == 48, "final inventory must close exact total=147 and design=48")
    design_paths = {item.get("relative_path_template") for item in artifacts if item.get("group") == "design"}
    require(REQUIRED_FINAL_MACHINE_CONTRACTS.issubset(design_paths), f"final inventory machine contract gap: {sorted(REQUIRED_FINAL_MACHINE_CONTRACTS-design_paths)}")
    contract = inventory.get("canonical_contract", {})
    projection = {key: value for key, value in inventory.items() if key != "canonical_contract"}
    digest = hashlib.sha256(canonical(projection)).hexdigest()
    require(contract.get("algorithm") == "SHA-256" and contract.get("digest_sha256") == digest, "final inventory canonical digest mismatch")
    semantics = load(root, "normative-test-semantics.json")
    registry = load(root, "requirements-test-registry.json")
    semantic_test = next((item for item in semantics.get("tests", []) if item.get("test_id") == "T-DOCS-002"), {})
    registry_test = next((item for item in registry.get("tests", []) if item.get("test_id") == "T-DOCS-002"), {})
    expected_title_fragment = "147-item inventory"
    expected_formula = "final_document_contract_error_count == 0 AND inventory_item_count == 147 AND markdown_pdf_pair_count == 8"
    require(expected_title_fragment in semantic_test.get("title", "") and expected_title_fragment in registry_test.get("title", ""), "T-DOCS-002 title is stale against 147-item inventory")
    require(semantic_test.get("acceptance_formula") == expected_formula, "T-DOCS-002 acceptance formula is stale against exact inventory count")
    doc = (root / "14-final-document-deliverables.md").read_text(encoding="utf-8")
    require(f"`{len(artifacts)}`" in doc and f"`{expected_counts['design']}`" in doc and digest in doc, "document 14 count/digest is not synchronized")
    print(f"PASS: final inventory closes {len(artifacts)} artifacts including all semantic completeness contracts")


def verify_ui(root: Path, screens: dict[str, Any]) -> None:
    contract = load(root, "ui-journey-contracts.json")
    journeys = contract.get("key_journeys", [])
    require(contract.get("key_journey_count") == 12 == len(journeys), "key journey count must be 12")
    required_viewports = {"1440", "768", "390"}
    journey_ids = set()
    for journey in journeys:
        journey_id = journey.get("journey_id")
        require(journey_id and journey_id not in journey_ids, "duplicate/missing UI journey id")
        journey_ids.add(journey_id)
        require(journey.get("screen_ids") and journey.get("component_hierarchy") and journey.get("primary_action"), f"{journey_id} hierarchy/action incomplete")
        require(journey.get("secondary_actions") and journey.get("fields") and journey.get("sample_copy_ko"), f"{journey_id} field/copy contract incomplete")
        require(set(journey.get("responsive_order", {})) == required_viewports, f"{journey_id} responsive closure incomplete")
        require(len(journey.get("required_states", [])) >= 4 and len(journey.get("acceptance", [])) >= 5, f"{journey_id} state/acceptance closure incomplete")
    expected = {item["screen_id"]: item for item in screens.get("screens", [])}
    closure = contract.get("screen_closure", [])
    actual = {item.get("screen_id"): item for item in closure}
    require(contract.get("screen_count") == len(expected) == 36 and set(actual) == set(expected), "UI screen closure must equal all 36 normative screens")
    for screen_id, item in actual.items():
        require(item.get("route") == expected[screen_id]["route"], f"{screen_id} route drift")
        require(item.get("journey_ids") and set(item["journey_ids"]).issubset(journey_ids), f"{screen_id} has no valid journey")
        require(item.get("required_state_ids") == expected[screen_id]["state_ids"], f"{screen_id} state closure drift")
        require(item.get("responsive_viewports") == ["1440x900", "768x1024", "390x844"], f"{screen_id} viewport closure drift")
        require(item.get("visual_evidence_required") is True, f"{screen_id} visual evidence not required")
    print("PASS: 12 detailed UI journeys close all 36 screen routes, states and viewports")


def verify_stale_vocabulary(root: Path) -> None:
    security = root / "08-security-privacy-operations.md"
    require(security.is_file(), "08-security-privacy-operations.md missing")
    security_text = security.read_text(encoding="utf-8")
    require(not re.search(r"\bPERSONAL\b", security_text), "stale PERSONAL classification remains in security design")
    require("CONFIDENTIAL" in security_text, "security design lacks CONFIDENTIAL classification")
    analysis = root.parent / "AI-Gateway-UniClaudeProxy-Reuse-Design.md"
    if analysis.is_file():
        text = analysis.read_text(encoding="utf-8")
        stale_patterns = {
            r'(?i)data_class\s*[=:]\s*["`\']?personal': "stale personal AI data class",
            r"5\s*[~～-]\s*6\s*개\s*페르소나": "stale 5~6 persona count",
            r"역량.*(?:0\.80|80%)": "stale diagnosis threshold",
            r"추천.*(?:0\.85|85%)": "stale recommendation threshold",
            r"RAG.*(?:0\.90|90%)": "stale RAG threshold",
            r"구조화.*(?:0\.995|99\.5%)": "stale structured-output threshold",
        }
        for pattern, message in stale_patterns.items():
            require(not re.search(pattern, text), message)
        for required in ("PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED", "6개 family", "12 operational profile", "0.85", "0.90", "0.95", "0.998"):
            require(required in text, f"AI Gateway analysis lacks canonical {required}")
    print("PASS: stale PERSONAL, KPI and persona vocabulary is rejected")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        screens = load(root, "screen-route-contracts.json")
        data_use = verify_data_use(root, screens)
        verify_openapi(root, screens)
        verify_asyncapi(root)
        verify_ai(root, data_use)
        verify_entities(root)
        verify_rag(root)
        verify_provider(root)
        verify_reuse(root)
        verify_thresholds(root)
        verify_ui(root, screens)
        verify_final_inventory(root)
        verify_stale_vocabulary(root)
    except (ContractError, KeyError, TypeError, ValueError, IndexError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        print("RESULT: FAIL", file=sys.stderr)
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
