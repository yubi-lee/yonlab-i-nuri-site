#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/yonlab-machine-contracts.XXXXXX")"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

run_validator() {
  local root="$1"
  python "$root/verify-machine-contracts.py" --package-root "$root"
}

for required in \
  entity-catalog.json \
  normative-test-semantics.json \
  tch-015-authorization-contract.json \
  hwp-conversion-boundary-contract.json \
  ai-gateway-request.schema.json \
  fixtures/ai-gateway-safeguarding-decision-vectors.json \
  fixtures/ai-gateway-request.valid.json \
  fixtures/ai-gateway-request.invalid.json \
  fixtures/document-graph.valid.json \
  fixtures/document-graph.invalid-topology.json \
  fixtures/document-graph.invalid-uuid.json \
  fixtures/document-graph.invalid-range.json \
  fixtures/document-graph.invalid-nested-dangling.json \
  fixtures/document-graph.invalid-nested-cycle.json \
  fixtures/document-graph.invalid-cell-overlap.json \
  fixtures/document-graph.invalid-cell-gap.json \
  fixtures/artifact-manifest.invalid-duplicate-path.json \
  fixtures/artifact-manifest.invalid-source-path.json \
  fixtures/evidence-index.valid.json \
  fixtures/evidence-index.invalid.json \
  fixtures/artifact-root/release/final-system-design.pdf \
  fixtures/artifact-root/source/docs/design/ai-training-platform/README.md; do
  [[ -s "$PACKAGE_ROOT/$required" ]] || fail "missing required machine-contract artifact: $required"
done

run_validator "$PACKAGE_ROOT" >/dev/null || fail "baseline machine contracts rejected"
pass "baseline machine contracts accepted"

bash "$PACKAGE_ROOT/tests/test-normative-test-semantics.sh" >/dev/null || fail "normative test semantics suite rejected"
pass "normative test semantics and anti-swap mutations accepted"

bash "$PACKAGE_ROOT/tests/test-ai-gateway-safeguarding-enum.sh" >/dev/null || fail "AI gateway safeguarding suite rejected"
pass "AI gateway safeguarding canonical/unknown mutations accepted"

bash "$PACKAGE_ROOT/tests/test-tch-015-authorization.sh" >/dev/null || fail "TCH-015 authorization suite rejected"
pass "TCH-015 operation authorization mutations accepted"

mutate_and_expect_failure() {
  local name="$1"
  local python_body="$2"
  local fixture="$TMP_ROOT/$name"
  cp -R "$PACKAGE_ROOT" "$fixture"
  python - "$fixture" "$python_body" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
exec(sys.argv[2], {"json": json, "root": root})
PY
  if run_validator "$fixture" >"$TMP_ROOT/$name.out" 2>&1; then
    sed -n '1,160p' "$TMP_ROOT/$name.out" >&2
    fail "$name mutation was accepted"
  fi
  grep -Fq 'RESULT: FAIL' "$TMP_ROOT/$name.out" || fail "$name did not fail closed"
  pass "$name mutation rejected"
}

mutate_and_expect_failure operation_requirement_edge '
p=root/"screen-route-contracts.json"; d=json.loads(p.read_text()); d["screens"][0]["operation_contracts"][0]["requirement_ids"]=["SYS-F-001"]; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure generic_test_contract '
p=root/"requirements-test-registry.json"; d=json.loads(p.read_text()); d["tests"][0]["title"]="A11Y contract case T-A11Y-001"; d["tests"][0]["command"]=["true"]; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure arbitrary_test_title '
p=root/"requirements-test-registry.json"; d=json.loads(p.read_text()); d["tests"][0]["title"]="T-A11Y-001: 임의로 바꾼 의미 없는 문장"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure nonsense_test_threshold '
p=root/"requirements-test-registry.json"; d=json.loads(p.read_text()); d["tests"][0]["threshold"]={"metric":"astronomical_penguin_flux","comparison":">=","value":-999999,"unit":"bananas"}; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure test_oracle_catalog_drift '
p=root/"requirements-test-registry.json"; d=json.loads(p.read_text()); d["test_semantic_catalog"][0]["observation_path"]="$.metrics.always_pass"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure test_dataset_reference_drift '
p=root/"requirements-test-registry.json"; d=json.loads(p.read_text()); d["tests"][0]["dataset_contract_id"]="DATASET-DOES-NOT-EXIST"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure normative_acceptance_formula_drift '
p=root/"normative-test-semantics.json"; d=json.loads(p.read_text()); row=next(item for item in d["tests"] if item["test_id"]=="T-AI-004"); row["acceptance_formula"]="always_pass == true"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure stale_final_inventory_test_count '
p=root/"normative-test-semantics.json"; d=json.loads(p.read_text()); row=next(item for item in d["tests"] if item["test_id"]=="T-DOCS-002"); stale_count=147-18; row["acceptance_formula"]=f"final_document_contract_error_count == 0 AND inventory_item_count == {stale_count} AND markdown_pdf_pair_count == 8"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure stale_final_inventory_group_count '
p=root/"final-document-inventory.json"; d=json.loads(p.read_text()); d["expected_counts"]["design"]=48-18; d["expected_counts"]["total"]=147-18; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure tch015_authz_formula_drift '
p=root/"tch-015-authorization-contract.json"; d=json.loads(p.read_text()); d["operation_contracts"][0]["authorization_formula"]="same_tenant AND allow_all"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure safeguarding_route_action_drift '
p=root/"fixtures/ai-gateway-safeguarding-decision-vectors.json"; d=json.loads(p.read_text()); row=next(item for item in d["positive_cases"] if item["decision"]=="POLICY_BLOCK"); row["expected_route_action"]="MODEL_ROUTE_POLICY_EVALUATION"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure screen_operation_semantic_drift '
p=root/"screen-route-contracts.json"; d=json.loads(p.read_text()); registry=json.loads((root/"requirements-test-registry.json").read_text()); requirement_operations={op for group in (registry["rfp_requirements"],registry["system_requirements"]) for requirement in group for op in requirement["api_operation_ids"]}; row=next(screen for screen in d["screens"] if any(op not in requirement_operations for op in screen["api_operations"])); index=next(i for i,op in enumerate(row["api_operations"]) if op not in requirement_operations); row["api_operations"][index]="GET /api/v1/nonsense"; row["operation_contracts"][index]["operation_id"]="GET /api/v1/nonsense"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure screen_operation_request_oracle_drift '
p=root/"screen-route-contracts.json"; d=json.loads(p.read_text()); d["screens"][0]["operation_contracts"][0]["request_contract_id"]="HTTP-REQUEST-POST-V1"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure entity_reverse_edge '
p=root/"entity-catalog.json"; d=json.loads(p.read_text()); d["entities"].pop(); p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure source_document_public_global '
p=root/"entity-catalog.json"; d=json.loads(p.read_text()); row=next(item for item in d["entities"] if item["entity_id"]=="SourceDocument"); row["classification"]="PUBLIC"; row["tenant_scope"]="GLOBAL"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure hwp_child_network_enabled '
p=root/"hwp-conversion-boundary-contract.json"; d=json.loads(p.read_text()); d["child_sandbox"]["network"]="DEFAULT"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure hwp_output_attestation_weakened '
p=root/"hwp-conversion-boundary-contract.json"; d=json.loads(p.read_text()); d["output_attestation"]["required_fields"].remove("output_sha256"); p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure diagnosis_level_boundary '
p=root/"diagnosis-scoring-golden-vectors.json"; d=json.loads(p.read_text()); d["decision_contract"]["level_boundaries"][0]["maximum_score_microunit"]=25000000; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure diagnosis_invalid_precedence '
p=root/"diagnosis-scoring-golden-vectors.json"; d=json.loads(p.read_text()); row=next(item for item in d["decision_vectors"] if item["id"]=="GV-CONFIDENCE-BELOW"); row["input"]["overall_score_microunit"]=100000001; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure gateway_unknown_body_field '
p=root/"fixtures/ai-gateway-request.valid.json"; d=json.loads(p.read_text()); d["body"]["provider_model"]="forbidden"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure gateway_input_digest_mismatch '
p=root/"fixtures/ai-gateway-request.valid.json"; d=json.loads(p.read_text()); d["body"]["input"]["messages"][0]["content"]="해시가 갱신되지 않은 변조 입력"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure gateway_policy_binding_mismatch '
p=root/"fixtures/ai-gateway-request.valid.json"; d=json.loads(p.read_text()); d["body"]["policy_versions"]["data_use"]="data-use.v2"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure document_graph_topology '
p=root/"fixtures/document-graph.valid.json"; d=json.loads(p.read_text()); d["nodes"][0]["children"]=["00000000-0000-5000-8000-000000000000"]; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure document_graph_nested_dangling '
p=root/"fixtures/document-graph.valid.json"; d=json.loads(p.read_text()); cell=next(item for item in d["nodes"] if item["type"]=="CELL" and item["cell"]["nested_table_ids"]); cell["cell"]["nested_table_ids"]=["00000000-0000-5000-8000-000000000099"]; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure document_graph_cell_coverage_gap '
p=root/"fixtures/document-graph.valid.json"; d=json.loads(p.read_text()); table=next(item for item in d["nodes"] if item["type"]=="TABLE"); table["table"]["row_count"]+=1; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure artifact_duplicate_path_fixture '
p=root/"fixtures/artifact-manifest.valid.json"; d=json.loads(p.read_text()); d["files"].append(dict(d["files"][0])); p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure artifact_actual_bytes_mismatch '
p=root/"fixtures/artifact-manifest.valid.json"; d=json.loads(p.read_text()); d["files"][0]["size_bytes"]+=1; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure artifact_owner_catalog_mismatch '
p=root/"fixtures/artifact-manifest.valid.json"; d=json.loads(p.read_text()); d["files"][0]["owner_ids"]=["OWN-NOT-REGISTERED"]; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure artifact_gate_catalog_mismatch '
p=root/"fixtures/artifact-manifest.valid.json"; d=json.loads(p.read_text()); d["files"][0]["gate_ids"]=["GATE-NOT-REGISTERED"]; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure artifact_source_resolution_mismatch '
p=root/"fixtures/artifact-manifest.valid.json"; d=json.loads(p.read_text()); d["files"][0]["source_paths"]=["docs/design/missing.md"]; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure artifact_timestamp_epoch_mismatch '
p=root/"fixtures/artifact-manifest.valid.json"; d=json.loads(p.read_text()); d["generated_at_utc"]="2026-07-13T00:00:00Z"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure artifact_distribution_provenance_missing '
p=root/"fixtures/artifact-manifest.valid.json"; d=json.loads(p.read_text()); d["scope"]="DISTRIBUTION"; d["source_release_manifest_sha256"]=None; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure evidence_safe_path_weakened '
p=root/"evidence-index.schema.json"; d=json.loads(p.read_text()); d["$defs"]["evidence"]["properties"]["artifact_path"]["pattern"]=".*"; p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

mutate_and_expect_failure evidence_freshness_vocabulary_weakened '
p=root/"evidence-index.schema.json"; d=json.loads(p.read_text()); d["$defs"]["evidence"]["properties"]["freshness"]["enum"].append("UNKNOWN"); p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

printf 'RESULT: PASS\n'
