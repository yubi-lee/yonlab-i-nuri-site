#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checker="$here/verify-completeness-contracts.py"

if [[ ! -f "$checker" ]]; then
  echo "FAIL: completeness checker missing" >&2
  exit 1
fi

python3 "$checker" --root "$here"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -R "$here/." "$tmp/design/"

expect_reject() {
  local name="$1"
  if python3 "$checker" --root "$tmp/design" >"$tmp/$name.out" 2>&1; then
    echo "FAIL: mutation accepted: $name" >&2
    cat "$tmp/$name.out" >&2
    exit 1
  fi
  echo "PASS: mutation rejected: $name"
  rm -rf "$tmp/design"
  cp -R "$here/." "$tmp/design/"
}

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
path = sorted(d["paths"])[0]; method = sorted(d["paths"][path])[0]
del d["paths"][path][method]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-operation-removal

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["classification_vocabulary"][2] = "PERSONAL"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject stale-data-class

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["entities"] = [e for e in d["entities"] if e["entity_id"] != "SafeguardingCase"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject safeguarding-entity-removal

python3 - "$tmp/design/rag-policy-golden-vectors.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["retrieval_policy"]["rrf_k"] = 1
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject rag-policy-drift

python3 - "$tmp/design/provider-decision-registry.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["routing_invariants"]["RESTRICTED"] = ["EXTERNAL_OPENAI"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject restricted-external-route

python3 - "$tmp/design/legacy-reuse-decision-matrix.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["assets"][0]["characterization_test_ids"] = []
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject reuse-without-characterization

python3 - "$tmp/design/ui-journey-contracts.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["key_journeys"] = d["key_journeys"][:-1]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject ui-key-journey-removal

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
op = d["paths"]["/api/v1/diagnoses/{id}/results"]["get"]
ref = op["responses"]["200"]["content"]["application/json"]["schema"]["$ref"].split("/")[-1]
d["components"]["schemas"][ref]["properties"].pop("competency_scores")
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-operation-semantic-payload

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["x-response-blueprint-contract"]["bindings"] = d["x-response-blueprint-contract"]["bindings"][:-1]
d["x-response-blueprint-contract"]["binding_count"] = 112
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-response-blueprint-keyset-removal

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["x-response-blueprint-contract"]["fallback_count"] = 1
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-response-blueprint-fallback-enabled

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
op = d["paths"]["/api/v1/public/search"]["get"]
ref = op["responses"]["200"]["content"]["application/json"]["schema"]["$ref"].split("/")[-1]
del d["components"]["schemas"][ref]["properties"]["search_hits"]["items"]["properties"]["title"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-public-search-title-removal

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
op = d["paths"]["/api/v1/admin/metrics-summary"]["get"]
ref = op["responses"]["200"]["content"]["application/json"]["schema"]["$ref"].split("/")[-1]
del d["components"]["schemas"][ref]["properties"]["latency_metrics"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-admin-metrics-latency-removal

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
op = d["paths"]["/api/v1/rag/sessions/{id}/messages"]["post"]
ref = op["responses"]["201"]["content"]["application/json"]["schema"]["$ref"].split("/")[-1]
del d["components"]["schemas"][ref]["properties"]["claim_evidence_bindings"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-rag-claim-evidence-binding-removal

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["x-request-blueprint-contract"]["bindings"] = d["x-request-blueprint-contract"]["bindings"][:-1]
d["x-request-blueprint-contract"]["binding_count"] = 56
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-request-blueprint-keyset-removal

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["x-request-blueprint-contract"]["fallback_count"] = 1
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-request-blueprint-fallback-enabled

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import copy, json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["paths"]["/api/v1/me/consents"]["get"]["requestBody"] = copy.deepcopy(d["paths"]["/api/v1/me/consents"]["post"]["requestBody"])
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-get-request-body-added

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["paths"]["/api/v1/auth/login"]["post"]["requestBody"]["required"] = False
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-write-request-body-not-required

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
op = d["paths"]["/api/v1/diagnoses/{id}/results"]["get"]
next(item for item in op["parameters"] if item["in"] == "path" and item["name"] == "id")["required"] = False
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-path-parameter-not-required

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["paths"]["/api/v1/auth/login"]["post"]["parameters"].append({
    "name": "X-Debug-Bypass", "in": "header", "required": False,
    "schema": {"type": "string", "maxLength": 8},
})
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject openapi-unpinned-header-parameter-added

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
op = d["paths"]["/api/v1/auth/refresh"]["post"]
op["responses"]["201"] = op["responses"].pop("200")
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject deployed-auth-success-status-drift

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
op = d["paths"]["/api/v1/auth/refresh"]["post"]
op["security"] = []
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject deployed-auth-security-scheme-drift

python3 - "$tmp/design/platform-openapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
op = d["paths"]["/api/v1/auth/refresh"]["post"]
ref = op["responses"]["default"]["content"]["application/problem+json"]["schema"]["$ref"].split("/")[-1]
d["components"]["schemas"][ref]["properties"]["code"]["enum"] = ["RATE_LIMITED"]
op["x-error-codes"] = ["RATE_LIMITED"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject deployed-auth-error-vocabulary-drift

mutate_request_field_and_expect_reject() {
  local name="$1"
  local path="$2"
  local method="$3"
  local field="$4"
  python3 - "$tmp/design/platform-openapi.json" "$path" "$method" "$field" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); path, method, field = sys.argv[2:]
d = json.loads(p.read_text(encoding="utf-8"))
op = d["paths"][path][method]
ref = op["requestBody"]["content"]["application/json"]["schema"]["$ref"].split("/")[-1]
del d["components"]["schemas"][ref]["properties"][field]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  expect_reject "$name"
}

mutate_request_field_and_expect_reject openapi-profile-career-band-removal "/api/v1/me" patch career_band
mutate_request_field_and_expect_reject openapi-learning-path-steps-removal "/api/v1/learning-paths/{id}" patch steps
mutate_request_field_and_expect_reject openapi-draft-field-changes-removal "/api/v1/drafts/{id}" patch field_changes
mutate_request_field_and_expect_reject openapi-catalog-accessibility-removal "/api/v1/admin/catalog/{id}" patch accessibility_features
mutate_request_field_and_expect_reject openapi-document-node-style-removal "/api/v1/admin/document-nodes/{id}" patch style_ref
mutate_request_field_and_expect_reject openapi-recommendation-feedback-decision-removal "/api/v1/recommendations/{id}/feedback" post decision

python3 - "$tmp/design/platform-asyncapi.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["components"]["schemas"]["GapEvent"]["properties"]["event_type"]["const"] = "heartbeat"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject asyncapi-discriminator-collision

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
e = next(item for item in d["entities"] if item["entity_id"] == "EvidenceSpan")
e["check_constraints"] = []
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject evidence-span-check-removal

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
e = next(item for item in d["entities"] if item["entity_id"] == "RefreshSession")
e["fields"] = [field for field in e["fields"] if field["name"] != "reuse_detected_at"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject refresh-reuse-field-removal

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
entity = next(item for item in d["entities"] if item["entity_id"] == "User")
next(item for item in entity["fields"] if item["name"] == "id")["nullable"] = True
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject entity-primary-key-nullable

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import copy, json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
entity = next(item for item in d["entities"] if item["entity_id"] == "User")
entity["fields"].append(copy.deepcopy(entity["fields"][0]))
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject entity-duplicate-field-name

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
entity = next(item for item in d["entities"] if item["entity_id"] == "RefreshSession")
entity["foreign_keys"][0]["columns"].append("tenant_id")
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject entity-foreign-key-arity-mismatch

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
entity = next(item for item in d["entities"] if item["entity_id"] == "RefreshSession")
entity["foreign_keys"][0]["referenced_columns"] = ["missing_column"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject entity-foreign-key-target-column-missing

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
entity = next(item for item in d["entities"] if item["entity_id"] == "RefreshSession")
next(item for item in entity["fields"] if item["name"] == "user_id")["type"] = "varchar(32)"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject entity-foreign-key-type-mismatch

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
entity = next(item for item in d["entities"] if item["entity_id"] == "RefreshSession")
next(item for item in entity["fields"] if item["name"] == "user_id")["type"] = "varchar(32)"
entity["foreign_keys"][0]["referenced_columns"] = ["status"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject entity-foreign-key-target-not-unique

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
entities = d["entities"]
entities[1]["indexes"][0]["name"] = entities[0]["indexes"][0]["name"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject entity-duplicate-index-name

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
entities = d["entities"]
entities[1]["check_constraints"][0]["name"] = entities[0]["check_constraints"][0]["name"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject entity-duplicate-constraint-name

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
entity = next(item for item in d["entities"] if item["entity_id"] == "RefreshSession")
entity["foreign_keys"][0]["references"] = "Tenant"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject entity-foreign-key-target-entity-drift

mutate_entity_field_and_expect_reject() {
  local name="$1"
  local entity_id="$2"
  local field="$3"
  python3 - "$tmp/design/persistent-domain-catalog.json" "$entity_id" "$field" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); entity_id, field = sys.argv[2:]
d = json.loads(p.read_text(encoding="utf-8"))
entity = next(item for item in d["entities"] if item["entity_id"] == entity_id)
entity["fields"] = [item for item in entity["fields"] if item["name"] != field]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  expect_reject "$name"
}

mutate_entity_field_and_expect_reject password-credential-boundary-removal PasswordCredential password_hash
mutate_entity_field_and_expect_reject competency-confidence-removal CompetencyScore confidence_microunit
mutate_entity_field_and_expect_reject persona-artifact-digest-removal PersonaDefinition artifact_digest
mutate_entity_field_and_expect_reject content-accessibility-removal ContentItem accessibility_features
mutate_entity_field_and_expect_reject document-node-style-removal DocumentNode style_ref
mutate_entity_field_and_expect_reject citation-current-rights-removal Citation rights_current
mutate_entity_field_and_expect_reject evidence-turn-sequence-removal EvidenceSpan turn_sequence
mutate_entity_field_and_expect_reject rubric-artifact-digest-removal RubricVersion artifact_digest

python3 - "$tmp/design/persistent-domain-catalog.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["association_contracts"]["LearningPathStepDependency"]["foreign_keys"] = d["association_contracts"]["LearningPathStepDependency"]["foreign_keys"][:1]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject learning-path-dependency-fk-removal

python3 - "$tmp/design/ai-service-contracts.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
t = next(item for item in d["task_contracts"] if item["task"] == "diagnosis.evidence.extract")
del t["output_schema"]["properties"]["evidence"]["items"]["properties"]["entailment_microunit"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject ai-evidence-score-removal

python3 - "$tmp/design/ai-service-contracts.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
t = next(item for item in d["task_contracts"] if item["task"] == "document.grounded_answer")
del t["output_schema"]["properties"]["claim_citation_bindings"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject grounded-binding-removal

python3 - "$tmp/design/data-use-policy-registry.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["operation_bindings"][0]["category_ids"] = ["UNKNOWN"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject data-use-unknown-category

python3 - "$tmp/design/acceptance-threshold-registry.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
next(item for item in d["thresholds"] if item["threshold_id"] == "THR-AI-FAIRNESS-MAX-GAP")["value"] = 999999
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject acceptance-threshold-drift

python3 - "$tmp/design/acceptance-threshold-registry.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
next(item for item in d["thresholds"] if item["threshold_id"] == "THR-UX-MEDIAN-TIME-MS")["comparison_role"] = "MINIMUM"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject ux-time-comparison-direction-drift

python3 - "$tmp/design/acceptance-threshold-registry.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
next(item for item in d["thresholds"] if item["threshold_id"] == "THR-CODE-STATEMENT-COVERAGE")["owner_ids"] = ["OWN-QA", "OWN-QA"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject threshold-duplicate-owner

python3 - "$tmp/design/acceptance-threshold-registry.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
next(item for item in d["thresholds"] if item["threshold_id"] == "THR-AI-SPAN-F1")["status"] = "PROPOSED"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject threshold-status-not-approved-baseline

python3 - "$tmp/design/acceptance-threshold-registry.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
del next(item for item in d["thresholds"] if item["threshold_id"] == "THR-AI-SPAN-F1")["due_at"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject threshold-due-at-removal

python3 - "$tmp/design/acceptance-threshold-registry.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
next(item for item in d["thresholds"] if item["threshold_id"] == "THR-AI-SPAN-F1")["candidate_binding"] = "UNBOUND"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject threshold-candidate-binding-drift

python3 - "$tmp/design/acceptance-threshold-registry.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
next(item for item in d["thresholds"] if item["threshold_id"] == "THR-AI-SPAN-F1")["source_contract_ids"] = ["T-AI-001"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject threshold-source-contract-closure-drift

python3 - "$tmp/design/acceptance-threshold-registry.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
row = next(item for item in d["thresholds"] if item["threshold_id"] == "THR-AI-SPAN-F1")
row["decision_id"] = "DEC-UNRELATED"
row["owner_ids"] = ["OWN-QA"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject threshold-decision-owner-drift

python3 - "$tmp/design/normative-test-semantics.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
t = next(item for item in d["tests"] if item["test_id"] == "T-AI-007")
t["acceptance_formula"] += " OR release_blocked == true"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject fairness-release-blocked-false-pass

python3 - "$tmp/design/09-test-procedure-acceptance.md" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); text = p.read_text(encoding="utf-8")
text = text.replace("fairness gap 100000 microunit 이내만 PASS; 초과는 FAIL, 표본·신뢰구간 부족은 INSUFFICIENT_DATA이며 둘 다 release block이고 PASS가 아님", "승인 fairness gap 이내 또는 배포 차단")
p.write_text(text, encoding="utf-8")
PY
expect_reject fairness-blocked-as-acceptance-narrative

python3 - "$tmp/design/legacy-reuse-decision-matrix.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["assets"][0]["characterization_test_ids"] = ["T-LEG-ORPHAN-001"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject orphan-legacy-characterization-test

python3 - "$tmp/design/legacy-reuse-decision-matrix.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
auth = d["authentication_api_union_contract"]
auth["service_only_operations"] = [item for item in auth["service_only_operations"] if not item["operation_id"].endswith("/logout-all")]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject deployed-auth-union-operation-removal

python3 - "$tmp/design/legacy-reuse-decision-matrix.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
op = next(item for item in d["authentication_api_union_contract"]["service_only_operations"] if item["operation_id"].endswith("/refresh"))
op["replay_policy"] = "ALLOW_RETRY"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject deployed-auth-refresh-replay-weakened

python3 - "$tmp/design/legacy-reuse-decision-matrix.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
op = next(item for item in d["authentication_api_union_contract"]["service_only_operations"] if item["operation_id"].endswith("password-resets/confirm"))
op["request_log_policy"] = "REDACT"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject deployed-auth-reset-secret-log-policy-weakened

python3 - "$tmp/design/legacy-reuse-decision-matrix.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
op = next(item for item in d["authentication_api_union_contract"]["service_only_operations"] if item["operation_id"].endswith("/refresh"))
op["request_field_codes"] = ["BOGUS"]
op["response_field_codes"] = ["BOGUS"]
op["state_transition"] = "NOOP"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject deployed-auth-exact-field-and-state-drift

python3 - "$tmp/design/final-document-inventory.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
d["artifacts"] = [item for item in d["artifacts"] if item["relative_path_template"] != "ai-service-contracts.json"]
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject final-inventory-completeness-contract-removal

python3 - "$tmp/design/normative-test-semantics.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding="utf-8"))
t = next(item for item in d["tests"] if item["test_id"] == "T-DOCS-002")
stale_count = 147 - 18
t["acceptance_formula"] = f"final_document_contract_error_count == 0 AND inventory_item_count == {stale_count} AND markdown_pdf_pair_count == 8"
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_reject stale-final-inventory-test-count

echo "RESULT: PASS"
