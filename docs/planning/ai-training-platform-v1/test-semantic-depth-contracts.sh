#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

run_verify() {
  local base="$1"
  "$PYTHON_BIN" "$ROOT/verify-semantic-depth-contracts.py" --base-dir "$base"
}

expect_rejected() {
  local case_id="$1"
  local mutation_py="$2"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN
  cp "$ROOT"/*.json "$tmp/"
  MUTATION="$mutation_py" BASE_DIR="$tmp" "$PYTHON_BIN" - <<'PY'
import os
from pathlib import Path

base = Path(os.environ["BASE_DIR"])
exec(os.environ["MUTATION"], {"base": base})
PY
  if run_verify "$tmp" >/dev/null 2>&1; then
    echo "FAIL: mutation accepted: $case_id" >&2
    return 1
  fi
  echo "PASS: mutation rejected: $case_id"
  rm -rf "$tmp"
  trap - RETURN
}

run_verify "$ROOT"

expect_rejected "rubric-missing-fourth-anchor" $'import json\np=base/"rubric-question-contract.json"\nd=json.loads(p.read_text())\nd["indicators"][0]["anchors"].pop()\np.write_text(json.dumps(d))'
expect_rejected "question-bank-missing-indicator-coverage" $'import json\np=base/"rubric-question-contract.json"\nd=json.loads(p.read_text())\nd["questions"]=[q for q in d["questions"] if d["indicators"][0]["indicator_id"] not in q["indicator_ids"]]\np.write_text(json.dumps(d))'
expect_rejected "rubric-generic-counterexample" $'import json\np=base/"rubric-question-contract.json"\nd=json.loads(p.read_text())\nd["indicators"][0]["anchors"][0]["counterexample"]="일반적이고 반복되는 반례 문장으로 대체한다"\np.write_text(json.dumps(d))'
expect_rejected "region-exact-location-policy-gap" $'import json\np=base/"rubric-question-contract.json"\nd=json.loads(p.read_text())\nrow=next(x for x in d["feature_dictionary"] if x["feature_id"]=="context.region_resource_category")\nrow["encoding"]=row["encoding"].replace("; exact location forbidden","")\np.write_text(json.dumps(d))'
expect_rejected "persona-protected-proxy-coefficient" $'import json\np=base/"persona-inference-policy.json"\nd=json.loads(p.read_text())\nd["features"][0]["feature_id"]="teacher.gender"\np.write_text(json.dumps(d))'
expect_rejected "persona-profile-coefficient-drift" $'import json\np=base/"persona-inference-policy.json"\nd=json.loads(p.read_text())\nd["profiles"][0]["coefficients"][0]["coefficient_microunit"]+=1\np.write_text(json.dumps(d))'
expect_rejected "sensitive-support-not-restricted" $'import json\np=base/"persona-inference-policy.json"\nd=json.loads(p.read_text())\nd["sensitive_support_policy"]["data_class"]="INTERNAL"\np.write_text(json.dumps(d))'
expect_rejected "authorization-dual-approval-bypass" $'import json\np=base/"operation-authorization-contracts.json"\nd=json.loads(p.read_text())\nd["operations"][0]["dual_approval"]["required"]=False\np.write_text(json.dumps(d))'
expect_rejected "authorization-provider-call-on-deny" $'import json\np=base/"operation-authorization-contracts.json"\nd=json.loads(p.read_text())\nd["deny_invariants"]["provider_call_count"]=1\np.write_text(json.dumps(d))'
expect_rejected "authorization-medicalized-role" $'import json\np=base/"operation-authorization-contracts.json"\nd=json.loads(p.read_text())\nd["role_vocabulary"][0]="ROLE_CLINICAL_SAFETY_REVIEWER"\np.write_text(json.dumps(d))'
expect_rejected "authorization-operation-vector-role" $'import json\np=base/"operation-authorization-contracts.json"\nd=json.loads(p.read_text())\nd["operation_vectors"][0]["approver_roles"]=[d["operation_vectors"][0]["initiator_role"],d["operation_vectors"][0]["approver_roles"][0]]\np.write_text(json.dumps(d))'
expect_rejected "evaluation-one-query" $'import json\np=base/"evaluation-policy-contract.json"\nd=json.loads(p.read_text())\nd["suites"][0]["minimum_sample_size"]=1\np.write_text(json.dumps(d))'
expect_rejected "evaluation-empty-slice" $'import json\np=base/"evaluation-policy-contract.json"\nd=json.loads(p.read_text())\nd["suites"][0]["required_slices"][0]["minimum_sample_size"]=0\np.write_text(json.dumps(d))'
expect_rejected "evaluation-training-reuse" $'import json\np=base/"evaluation-policy-contract.json"\nd=json.loads(p.read_text())\nd["leakage_controls"]["training_corpus_overlap_maximum"]=1\np.write_text(json.dumps(d))'
expect_rejected "evaluation-missing-confidence-interval" $'import json\np=base/"evaluation-policy-contract.json"\nd=json.loads(p.read_text())\nd["suites"][0].pop("confidence_interval")\np.write_text(json.dumps(d))'
expect_rejected "document-graph-dangling-style" $'import json\np=base/"document-graph.schema.json"\nd=json.loads(p.read_text())\nd["x-semantic-contract"]["resource_integrity"].remove("every non-null style_ref resolves to exactly one styles[].style_id")\np.write_text(json.dumps(d))'
expect_rejected "document-graph-image-alt-gap" $'import json\np=base/"document-graph.schema.json"\nd=json.loads(p.read_text())\nd["$defs"]["imageData"]["required"].remove("alt_text")\np.write_text(json.dumps(d))'
expect_rejected "document-graph-border-loss-gap" $'import json\np=base/"document-graph.schema.json"\nd=json.loads(p.read_text())\nd["$defs"]["cellData"]["properties"].pop("border_ref")\np.write_text(json.dumps(d))'
expect_rejected "document-graph-field-loss-gap" $'import json\np=base/"document-graph.schema.json"\nd=json.loads(p.read_text())\nd["$defs"]["fieldData"]["required"].remove("field_type")\np.write_text(json.dumps(d))'
expect_rejected "document-graph-macro-ole-allowed" $'import json\np=base/"document-graph.schema.json"\nd=json.loads(p.read_text())\nd["x-semantic-contract"]["active_content_policy"]["macro_ole_action"]="ALLOW"\np.write_text(json.dumps(d))'
expect_rejected "hwp-roundtrip-no-print" $'import json\np=base/"hwp-conversion-boundary-contract.json"\nd=json.loads(p.read_text())\nd["licensed_roundtrip_acceptance"]["required_actions"].remove("PRINT_TO_PDF")\np.write_text(json.dumps(d))'
expect_rejected "provider-decision-missing-hosting" $'import json\np=base/"provider-decision-registry.json"\nd=json.loads(p.read_text())\nd["decisions"]=[x for x in d["decisions"] if x["decision_id"]!="DEC-HOSTING-DNS-TLS-WAF-012"]\np.write_text(json.dumps(d))'

echo "RESULT: PASS"
