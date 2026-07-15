#!/usr/bin/env bash
set -euo pipefail

WORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCHEMA="$WORK_ROOT/yonlab-ai-training-platform-design/codex-final-result.schema.json"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/home" "$TMP_ROOT/npm-cache"

python3 - "$TMP_ROOT" <<'PY'
import copy
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
gate_ids = [
    "GATE-DESIGN-INTEGRITY", "GATE-CODE-QUALITY", "GATE-SECURITY-PRIVACY", "GATE-AI-KPI",
    "GATE-DOCUMENT-KPI", "GATE-UX-ACCESSIBILITY", "GATE-OPERATIONS-RECOVERY", "GATE-PILOT-ACCEPTANCE",
]
policy = {"KPI-001":(">=",.85),"KPI-002":(">=",.9),"KPI-003":(">=",.95),"KPI-004":(">=",.95),"KPI-005":(">=",.998),"KPI-006":(">=",90),"KPI-007":(">=",.9),"KPI-008":("<=",0),"KPI-009":("<=",0),"KPI-010":(">=",1)}

def gate():
    return {"status":"PASS","freshness":"FRESH","summary":"verified","evidence_paths":["docs/qa/ai-training-platform/evidence.json"]}

def kpi(kpi_id):
    comparison, threshold = policy[kpi_id]
    return {"status":"PASS","freshness":"FRESH","value":threshold,"comparison":comparison,"threshold":threshold,"auxiliary_value":0 if kpi_id=="KPI-004" else None,"acceptance_id":None,"evidence_paths":["docs/qa/ai-training-platform/evidence.json"]}

base = {
    "schema_version":"codex-final-result.v1",
    "baseline_id":"YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1",
    "run_id":"run-20260713-0001",
    "release_id":"v1.0.0-rc1",
    "generated_at":"2026-07-13T12:00:00Z",
    "release_state":"NOT_READY",
    "candidate_phase":"UNSIGNED_CANDIDATE / REVIEW PENDING",
    "summary":"independently verifiable unsigned handoff",
    "repository":{
        "root":"D:\\Views\\yonlab-inuri-site",
        "remote":"https://github.com/yubi-lee/yonlab-i-nuri-site.git",
        "branch":"feat/ai-training-platform-v1",
        "baseline_commit":"a"*40,
        "implementation_commit":"b"*40,
        "implementation_tree":"c"*40,
        "implementation_tree_sha256":"d"*64,
        "release_snapshot_commit":"e"*40,
        "worktree_clean":True,
        "push_status":"PUSHED",
        "pull_request_url":"https://github.com/yubi-lee/yonlab-i-nuri-site/pull/1",
    },
    "gates":{item:gate() for item in gate_ids},
    "kpi_results":{item:kpi(item) for item in policy},
    "acceptance_data":[],
    "blockers":[],
    "generated_documents":["docs/design/ai-training-platform/README.md"],
    "commits":[{"hash":"b"*40,"subject":"feat: implementation S"},{"hash":"e"*40,"subject":"docs: release snapshot R"}],
    "verification_commands":[{"command":"python -m tests.contract_runner","status":"PASS","exit_code":0,"finished_at":"2026-07-13T12:00:00Z","acceptance_id":None,"evidence_path":"docs/qa/ai-training-platform/evidence.json"}],
    "release_attestation":{"technical_approvals":[],"artifact_integrity":None,"acceptance_approval":None,"annotated_tag":None},
    "next_action":{"kind":"HUMAN_REVIEW","description":"collect external protected signatures","command":None},
}
(out / "valid-unsigned.json").write_text(json.dumps(base), encoding="utf-8")
blocked=copy.deepcopy(base)
blocked["candidate_phase"]="IMPLEMENTATION_BLOCKED"
blocked["blockers"]=[{"id":"BLOCK-001","status":"FAIL","description":"failed gate","owner":"OWN-QA","recovery":"remediate and resume"}]
blocked["next_action"]={"kind":"REMEDIATE","description":"fix blocker","command":"powershell -File .\\scripts\\invoke-ai-training-platform-v1.ps1 -ResumeRun run-20260713-0001"}
(out / "valid-blocked.json").write_text(json.dumps(blocked), encoding="utf-8")

invalid=[]
item=copy.deepcopy(base); del item["candidate_phase"]; invalid.append(("missing-candidate-phase",item))
item=copy.deepcopy(base); item["release_state"]="CODE_COMPLETE / ACCEPTANCE DATA PENDING"; invalid.append(("codex-signed-state",item))
item=copy.deepcopy(base); item["release_state"]="ACCEPTED"; invalid.append(("codex-accepted-state",item))
item=copy.deepcopy(base); item["blockers"]=blocked["blockers"]; invalid.append(("unsigned-with-blocker",item))
item=copy.deepcopy(base); item["release_attestation"]["technical_approvals"]=[{"owner_id":"OWN-QA"}]; invalid.append(("unsigned-with-signature",item))
item=copy.deepcopy(base); item["next_action"]={"kind":"NONE","description":"wrong","command":None}; invalid.append(("unsigned-wrong-next",item))
item=copy.deepcopy(base); item["generated_documents"]=[]; invalid.append(("unsigned-no-documents",item))
item=copy.deepcopy(blocked); item["blockers"]=[]; invalid.append(("blocked-no-blocker",item))
item=copy.deepcopy(blocked); item["next_action"]["command"]=None; invalid.append(("blocked-no-command",item))
item=copy.deepcopy(base); item["release_id"]="../../escape"; invalid.append(("unsafe-release-id",item))
item=copy.deepcopy(base); item["generated_at"]="2026-02-31T12:00:00Z"; invalid.append(("impossible-date",item))
item=copy.deepcopy(base); item["extra_property"]=True; invalid.append(("extra-top-property",item))
for name,value in invalid:
    (out / f"invalid-{name}.json").write_text(json.dumps(value),encoding="utf-8")
PY

HOME="$TMP_ROOT/home" NPM_CONFIG_CACHE="$TMP_ROOT/npm-cache" npm install --silent --prefix "$TMP_ROOT/npm" ajv-cli@5 ajv-formats@3
AJV="$TMP_ROOT/npm/node_modules/.bin/ajv"
"$AJV" validate --spec=draft2020 --strict=false -c ajv-formats -s "$SCHEMA" -d "$TMP_ROOT/valid-*.json"
for fixture in "$TMP_ROOT"/invalid-*.json; do
  if "$AJV" validate --spec=draft2020 --strict=false -c ajv-formats -s "$SCHEMA" -d "$fixture" >/dev/null 2>&1; then
    printf 'FAIL: invalid fixture passed: %s\n' "$(basename "$fixture")" >&2
    exit 1
  fi
  printf 'PASS: invalid fixture rejected: %s\n' "$(basename "$fixture")"
done
printf 'PASS: AJV fail-closed Codex result schema fixtures\n'
