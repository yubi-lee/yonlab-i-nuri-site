#!/usr/bin/env bash
set -uo pipefail

unset PYTHONPATH PYTHONHOME PYTHONSTARTUP PYTHONUSERBASE PYTHONINSPECT PYTHONWARNINGS PYTHONBREAKPOINT PYTHONCASEOK PYTHONEXECUTABLE PYTHONSAFEPATH
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE=1

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_ROOT="$(cd "$PACKAGE_ROOT/.." && pwd)"

# These identifiers are mirrored by verify-design-package.ps1. The mutation
# suite verifies that the PowerShell source declares the same core contract.
OVERLAY_POLICY_PARITY_MARKER="OVERLAY_POLICY_V2_RECURSIVE_EXACT"
PARITY_CHECK_IDS=(
  CANONICAL_FILES JSON_PARSE REQUIREMENT_COUNTS DOCUMENT_IDS MARKDOWN_STRUCTURE
  CANONICAL_COORDINATES KPI_THRESHOLDS PERSONA_HIERARCHY DATA_POLICY RELEASE_STATES
  FINAL_OUTPUT_ROOTS RUNBOOK_INVENTORY MANUAL_PAIRS RUNTIME_CONTRACT ACTIVE_SAFETY
  SHELL_MODES MODEL_OUTPUT_SCHEMA FINAL_DOCUMENT_INVENTORY MACHINE_CONTRACTS
  COMPLETENESS_CONTRACTS SOURCE_TRACEABILITY NORMATIVE_TEST_SEMANTICS
  SEMANTIC_DEPTH_CONTRACTS AI_GATEWAY_SAFEGUARDING TCH_015_AUTHORIZATION
)

if ! command -v python3 >/dev/null 2>&1; then
  printf 'FAIL [JSON_PARSE]: python3 is required for deterministic semantic validation\n' >&2
  printf 'RESULT: FAIL\n'
  exit 1
fi

gate_failures=0

run_python_gate() {
  local check_id="$1"
  local checker="$2"
  shift 2
  if [[ ! -s "$checker" ]]; then
    printf 'FAIL [%s]: required checker is missing or empty: %s\n' "$check_id" "$checker" >&2
    gate_failures=$((gate_failures + 1))
    return
  fi
  local output status result_count last_line
  output="$(python3 -I -S -B "$checker" "$@" 2>&1)"
  status=$?
  result_count="$(grep -Ec '^RESULT: (PASS|FAIL)$' <<<"$output" || true)"
  last_line="${output##*$'\n'}"
  if ((status != 0)) || [[ "$result_count" != 1 || "$last_line" != "RESULT: PASS" ]]; then
    while IFS= read -r line; do
      [[ "$line" == "RESULT: PASS" || "$line" == "RESULT: FAIL" ]] || printf '%s\n' "$line" >&2
    done <<<"$output"
    printf 'FAIL [%s]: checker failed or returned a nondeterministic result (exit %d)\n' "$check_id" "$status" >&2
    gate_failures=$((gate_failures + 1))
  fi
}

run_python_gate RUNTIME_CONTRACT "$WORK_ROOT/generate-overlay-manifest.py" --root "$WORK_ROOT" --check
run_python_gate COMPLETENESS_CONTRACTS "$PACKAGE_ROOT/verify-completeness-contracts.py" --root "$PACKAGE_ROOT"
run_python_gate SOURCE_TRACEABILITY "$PACKAGE_ROOT/verify-source-traceability.py" --root "$PACKAGE_ROOT"
run_python_gate MACHINE_CONTRACTS "$PACKAGE_ROOT/verify-machine-contracts.py" --package-root "$PACKAGE_ROOT"
run_python_gate NORMATIVE_TEST_SEMANTICS "$PACKAGE_ROOT/verify-normative-test-semantics.py" --package-root "$PACKAGE_ROOT"
run_python_gate SEMANTIC_DEPTH_CONTRACTS "$PACKAGE_ROOT/verify-semantic-depth-contracts.py" --base-dir "$PACKAGE_ROOT"
run_python_gate AI_GATEWAY_SAFEGUARDING "$PACKAGE_ROOT/verify-ai-gateway-safeguarding.py" --package-root "$PACKAGE_ROOT"
run_python_gate TCH_015_AUTHORIZATION "$PACKAGE_ROOT/verify-tch-015-authorization.py" --package-root "$PACKAGE_ROOT"

python3 -I -S -B - "$PACKAGE_ROOT" "$WORK_ROOT" <<'PY'
from __future__ import annotations

from collections import Counter
import json
import os
from pathlib import Path
import re
import stat
import sys
import unicodedata
from urllib.parse import unquote

package = Path(sys.argv[1]).resolve()
work = Path(sys.argv[2]).resolve()
failures: list[tuple[str, str]] = []


def fail(code: str, message: str) -> None:
    failures.append((code, message))


def require(condition: bool, code: str, message: str) -> None:
    if not condition:
        fail(code, message)


def text(path: Path, code: str = "CANONICAL_FILES") -> str:
    try:
        return path.read_text(encoding="utf-8")
    except Exception as exc:
        fail(code, f"cannot read {path.relative_to(work)}: {exc}")
        return ""


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_keys)
    except Exception as exc:
        fail("JSON_PARSE", f"invalid JSON {path.relative_to(work)}: {exc}")
        return None


numbered_docs = [f"{index:02d}-{name}" for index, name in enumerate([
    "source-decision-baseline.md",
    "requirements-traceability.md",
    "functional-screen-design.md",
    "system-architecture-cdd-cdr.md",
    "ai-diagnosis-persona-recommendation.md",
    "document-ai-hwp-rag.md",
    "ai-gateway-model-selection.md",
    "data-api-interface-design.md",
    "security-privacy-operations.md",
    "test-procedure-acceptance.md",
    "delivery-implementation-plan.md",
    "codex-one-shot-implementation-prompt.md",
    "ui-ux-visual-system.md",
    "one-command-execution.md",
    "final-document-deliverables.md",
    "normative-policy-and-interface-contracts.md",
])]

required_package_files = [
    "README.md",
    *numbered_docs,
    "design-baseline.json",
    "document-graph.schema.json",
    "codex-output.schema.json",
    "codex-final-result.schema.json",
    "requirements-test-registry.json",
    "screen-route-contracts.json",
    "kpi-005-structured-output-matrix.json",
    "diagnosis-scoring-golden-vectors.json",
    "artifact-manifest.schema.json",
    "evidence-index.schema.json",
    "source-tree-hash-golden-vector.json",
    "final-document-inventory.json",
    "fixtures/artifact-manifest.valid.json",
    "fixtures/artifact-manifest.invalid.json",
    "fixtures/evidence-index.valid.json",
    "fixtures/evidence-index.invalid.json",
    "REVIEW-CHANGELOG-v1.1.md",
    "verify-design-package.sh",
    "verify-design-package.ps1",
    "test-verify-design-package.sh",
    "verify-machine-contracts.py",
    "verify-completeness-contracts.py",
    "verify-source-traceability.py",
    "verify-normative-test-semantics.py",
    "verify-semantic-depth-contracts.py",
    "verify-ai-gateway-safeguarding.py",
    "verify-tch-015-authorization.py",
    "generate-completeness-contracts.py",
    "generate-semantic-depth-contracts.py",
    "test-completeness-contracts.sh",
    "test-machine-contracts.sh",
    "test-semantic-depth-contracts.sh",
    "test-source-traceability.sh",
    "tests/test-ai-gateway-safeguarding-enum.sh",
    "tests/test-normative-test-semantics.sh",
    "tests/test-tch-015-authorization.sh",
    "source-traceability-manifest.json",
    "source-traceability.md",
]
required_workspace_files = [
    "AI-Gateway-UniClaudeProxy-Reuse-Design.md",
    "generate-overlay-manifest.py",
    "overlay-manifest.json",
    "start-ai-training-platform-v1.ps1",
    "repo-overlay/scripts/invoke-ai-training-platform-v1.ps1",
    "repo-overlay/scripts/validate-codex-final-result.ps1",
    "repo-overlay/scripts/tests/test-invoke-ai-training-platform-v1.sh",
    "repo-overlay/scripts/tests/test-codex-final-result-schema-ajv.sh",
    "repo-overlay/scripts/tests/test-invoke-utf8-process.ps1",
    "repo-overlay/scripts/tests/test-overlay-bootstrap.ps1",
    "repo-overlay/scripts/tests/test-runner-policy-fixtures.ps1",
    "repo-overlay/scripts/tests/test-validate-codex-final-result.ps1",
]

for relative in required_package_files:
    candidate = package / relative
    require(candidate.is_file() and candidate.stat().st_size > 0, "CANONICAL_FILES", f"missing or empty package file: {relative}")
for relative in required_workspace_files:
    candidate = work / relative
    require(candidate.is_file() and candidate.stat().st_size > 0, "CANONICAL_FILES", f"missing or empty workspace file: {relative}")

baseline = load_json(package / "design-baseline.json")
document_schema = load_json(package / "document-graph.schema.json")
model_output_schema = load_json(package / "codex-output.schema.json")
result_schema = load_json(package / "codex-final-result.schema.json")
final_document_inventory = load_json(package / "final-document-inventory.json")
manifest = load_json(work / "overlay-manifest.json")

additional_json_files = [
    "requirements-test-registry.json",
    "screen-route-contracts.json",
    "kpi-005-structured-output-matrix.json",
    "diagnosis-scoring-golden-vectors.json",
    "artifact-manifest.schema.json",
    "evidence-index.schema.json",
    "source-tree-hash-golden-vector.json",
    "fixtures/artifact-manifest.valid.json",
    "fixtures/artifact-manifest.invalid.json",
    "fixtures/evidence-index.valid.json",
    "fixtures/evidence-index.invalid.json",
]
additional_json = {relative: load_json(package / relative) for relative in additional_json_files}

# Parse every JSON file with duplicate-key rejection. A newly added registry or
# fixture cannot sit outside the package PASS boundary merely because it was
# not yet added to a hand-maintained list.
for json_path in sorted(package.rglob("*.json")):
    load_json(json_path)

for name, schema in (("document-graph.schema.json", document_schema), ("codex-final-result.schema.json", result_schema)):
    if schema is not None:
        require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "JSON_PARSE", f"{name} must declare JSON Schema 2020-12")


def validate_model_output_schema(node, location: str) -> None:
    if not isinstance(node, dict):
        fail("MODEL_OUTPUT_SCHEMA", f"schema node must be an object at {location}")
        return

    forbidden_keywords = {"allOf", "not", "if", "then", "else", "patternProperties", "oneOf"}
    for key in node:
        if key in forbidden_keywords or key.startswith("dependent"):
            fail("MODEL_OUTPUT_SCHEMA", f"unsupported Structured Outputs keyword at {location}: {key}")

    schema_type = node.get("type")
    type_values = schema_type if isinstance(schema_type, list) else [schema_type]
    if "object" in type_values or "properties" in node:
        properties = node.get("properties")
        require(isinstance(properties, dict), "MODEL_OUTPUT_SCHEMA", f"object schema properties must be an object at {location}")
        require(node.get("additionalProperties") is False, "MODEL_OUTPUT_SCHEMA", f"additionalProperties must be false at {location}")
        required = node.get("required")
        property_names = list(properties) if isinstance(properties, dict) else []
        require(isinstance(required, list), "MODEL_OUTPUT_SCHEMA", f"object schema required must be an array at {location}")
        if isinstance(required, list):
            require(
                len(required) == len(set(required)) == len(property_names) and set(required) == set(property_names),
                "MODEL_OUTPUT_SCHEMA",
                f"every object property must be required exactly once at {location}",
            )

    for key, value in node.items():
        if key in {"properties", "$defs", "definitions"}:
            if isinstance(value, dict):
                for child_name, child in value.items():
                    validate_model_output_schema(child, f"{location}/{key}/{child_name}")
        elif isinstance(value, dict):
            validate_model_output_schema(value, f"{location}/{key}")
        elif isinstance(value, list) and key not in {"required", "enum", "examples", "type"}:
            for index, child in enumerate(value):
                if isinstance(child, dict):
                    validate_model_output_schema(child, f"{location}/{key}/{index}")


if model_output_schema is not None:
    validate_model_output_schema(model_output_schema, "$")

# RFP and system requirement inventories are exact, sequential, and unique.
traceability = text(package / "01-requirements-traceability.md")
rfp_expected = {"PLR": 4, "ECR": 2, "DER": 8, "SIR": 3, "DAR": 7, "TER": 4, "SER": 8, "QUR": 5, "COR": 6, "PMR": 8, "PSR": 5}
rfp_ids = re.findall(r"^\|\s*((?:PLR|ECR|DER|SIR|DAR|TER|SER|QUR|COR|PMR|PSR)-\d{3})\s*\|", traceability, re.MULTILINE)
rfp_counts = Counter(item.split("-", 1)[0] for item in rfp_ids)
require(len(rfp_ids) == 60 and len(set(rfp_ids)) == 60, "REQUIREMENT_COUNTS", f"RFP inventory must contain 60 unique rows; found {len(rfp_ids)}")
for prefix, expected in rfp_expected.items():
    require(rfp_counts[prefix] == expected, "REQUIREMENT_COUNTS", f"{prefix} must contain {expected} rows; found {rfp_counts[prefix]}")

sys_f = re.findall(r"^\|\s*(SYS-F-\d{3})\s*\|", traceability, re.MULTILINE)
sys_nf = re.findall(r"^\|\s*(SYS-NF-\d{3})\s*\|", traceability, re.MULTILINE)
require(sys_f == [f"SYS-F-{i:03d}" for i in range(1, 19)], "REQUIREMENT_COUNTS", "SYS-F inventory must be exactly SYS-F-001 through SYS-F-018")
require(sys_nf == [f"SYS-NF-{i:03d}" for i in range(1, 16)], "REQUIREMENT_COUNTS", "SYS-NF inventory must be exactly SYS-NF-001 through SYS-NF-015")

# Document IDs are a package-level namespace, not merely per-file labels.
expected_doc_ids = {
    "00-source-decision-baseline.md": "SRC-CDR-000",
    "01-requirements-traceability.md": "REQ-BASELINE-001",
    "02-functional-screen-design.md": "UX-IA-002",
    "03-system-architecture-cdd-cdr.md": "ARCH-CDR-003",
    "04-ai-diagnosis-persona-recommendation.md": "AI-DIAG-004",
    "05-document-ai-hwp-rag.md": "DOC-AI-005",
    "06-ai-gateway-model-selection.md": "AI-GW-006",
    "07-data-api-interface-design.md": "DATA-ICD-007",
    "08-security-privacy-operations.md": "SEC-OPS-008",
    "09-test-procedure-acceptance.md": "VER-ATP-009",
    "10-delivery-implementation-plan.md": "PLAN-180D-010",
    "11-codex-one-shot-implementation-prompt.md": "CODEX-EXEC-011",
    "12-ui-ux-visual-system.md": "UX-VIS-012",
    "13-one-command-execution.md": "CODEX-RUN-013",
    "14-final-document-deliverables.md": "DEL-CONTRACT-014",
    "15-normative-policy-and-interface-contracts.md": "NORM-CONTRACT-015",
    "REVIEW-CHANGELOG-v1.1.md": "REVIEW-CHANGELOG-011",
}
seen_ids: dict[str, str] = {}
for relative, expected in expected_doc_ids.items():
    matches = re.findall(r"^문서 ID:\s*([^\s]+)\s*$", text(package / relative), re.MULTILINE)
    require(len(matches) == 1, "DOCUMENT_IDS", f"{relative} must contain exactly one document ID")
    if len(matches) == 1:
        actual = matches[0]
        require(actual == expected, "DOCUMENT_IDS", f"{relative} document ID must be {expected}; found {actual}")
        if actual in seen_ids:
            fail("DOCUMENT_IDS", f"duplicate document ID {actual}: {seen_ids[actual]} and {relative}")
        seen_ids[actual] = relative

# Markdown structure and relative links include the parent AI Gateway analysis.
markdown_files = [package / "README.md", *(package / item for item in numbered_docs), package / "REVIEW-CHANGELOG-v1.1.md", work / "AI-Gateway-UniClaudeProxy-Reuse-Design.md"]
link_pattern = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
placeholder_pattern = re.compile(r"\b(?:TBD|TODO|FIXME|implement later|fill in details)\b", re.IGNORECASE)
for markdown in markdown_files:
    body = text(markdown)
    fences = sum(1 for line in body.splitlines() if re.match(r"^\s*```", line))
    require(fences % 2 == 0, "MARKDOWN_STRUCTURE", f"unbalanced code fences: {markdown.relative_to(work)}")
    if markdown.name != "11-codex-one-shot-implementation-prompt.md":
        require(not placeholder_pattern.search(body), "MARKDOWN_STRUCTURE", f"unresolved placeholder: {markdown.relative_to(work)}")
    for raw_target in link_pattern.findall(body):
        target = raw_target.strip()
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1]
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        target = target.split("#", 1)[0]
        if not target:
            continue
        if " \"" in target or " '" in target:
            target = target.split(" ", 1)[0]
        target_path = (markdown.parent / unquote(target)).resolve()
        require(target_path.exists(), "MARKDOWN_STRUCTURE", f"broken relative link {markdown.relative_to(work)} -> {raw_target}")

if baseline is not None:
    expected_root = r"D:\Views\yonlab-inuri-site"
    expected_remote = "https://github.com/yubi-lee/yonlab-i-nuri-site.git"
    expected_branch = "feat/ai-training-platform-v1"
    repository = baseline.get("repository", {})
    require(baseline.get("baseline_id") == "YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1", "CANONICAL_COORDINATES", "baseline_id drift")
    require(baseline.get("normative_source_path") == "docs/planning/ai-training-platform-v1/design-baseline.json", "CANONICAL_COORDINATES", "normative source path drift")
    require(repository.get("windows_root") == expected_root, "CANONICAL_COORDINATES", "canonical Windows root drift")
    require(repository.get("remote_name") == "origin" and repository.get("remote") == expected_remote, "CANONICAL_COORDINATES", "canonical origin drift")
    require(repository.get("work_branch") == expected_branch and repository.get("base_branch_heuristic_allowed") is False, "CANONICAL_COORDINATES", "deterministic work branch drift")

    expected_roots = {
        "planning_source": "docs/planning/ai-training-platform-v1/",
        "final_design": "docs/design/ai-training-platform/",
        "operations": "docs/operations/ai-training-platform/",
        "quality_assurance": "docs/qa/ai-training-platform/",
        "manuals": "docs/manuals/ai-training-platform/",
        "releases": "docs/releases/ai-training-platform/",
        "distribution_docs": "dist/docs/",
    }
    require(baseline.get("artifact_roots") == expected_roots, "FINAL_OUTPUT_ROOTS", "artifact root contract drift")

    kpis = baseline.get("kpis", [])
    expected_kpis = {
        "KPI-001": (">=", "minimum", 0.85, True),
        "KPI-002": (">=", "minimum", 0.90, True),
        "KPI-003": (">=", "minimum", 0.95, False),
        "KPI-004": (">=", "minimum", 0.95, False),
        "KPI-005": (">=", "minimum", 0.998, False),
        "KPI-006": (">=", "minimum", 90, True),
        "KPI-007": (">=", "minimum", 0.90, True),
        "KPI-008": ("<=", "maximum", 0, False),
        "KPI-009": ("<=", "maximum", 0, False),
        "KPI-010": (">=", "minimum", 1.0, True),
    }
    require([item.get("id") for item in kpis if isinstance(item, dict)] == list(expected_kpis), "KPI_THRESHOLDS", "KPI IDs/order must be KPI-001 through KPI-010")
    for item in kpis:
        if not isinstance(item, dict) or item.get("id") not in expected_kpis:
            continue
        comparison, field, threshold, acceptance_required = expected_kpis[item["id"]]
        require(item.get("comparison") == comparison and item.get(field) == threshold, "KPI_THRESHOLDS", f"{item['id']} threshold drift")
        require(item.get("acceptance_data_required") is acceptance_required, "KPI_THRESHOLDS", f"{item['id']} acceptance-data classification drift")
        require(isinstance(item.get("formula"), str) and bool(item["formula"].strip()), "KPI_THRESHOLDS", f"{item['id']} formula is missing")
    kpi4 = next((item for item in kpis if isinstance(item, dict) and item.get("id") == "KPI-004"), {})
    require(kpi4.get("invalid_citation_maximum") == 0, "KPI_THRESHOLDS", "KPI-004 invalid citation maximum must be 0")

    persona = baseline.get("persona_hierarchy", {})
    families = persona.get("families", []) if isinstance(persona, dict) else []
    profiles = [profile for family in families if isinstance(family, dict) for profile in family.get("profiles", []) if isinstance(profile, dict)]
    expected_profile_order = [f"P-{family:02d}-{suffix}" for family in range(1, 7) for suffix in ("A", "B")]
    require(persona.get("family_count") == 6 and len(families) == 6, "PERSONA_HIERARCHY", "persona family count must be 6")
    require(persona.get("operational_profile_count") == 12 and len(profiles) == 12, "PERSONA_HIERARCHY", "operational profile count must be 12")
    require([item.get("profile_id") for item in profiles] == expected_profile_order, "PERSONA_HIERARCHY", "operational profile IDs/order drift")
    require(all(isinstance(item.get("version"), str) and item["version"] for item in profiles), "PERSONA_HIERARCHY", "every operational profile must be versioned")
    inference = persona.get("inference_contract", {})
    require(inference.get("profile_probability_count") == 12 and inference.get("family_aggregation_count") == 6, "PERSONA_HIERARCHY", "persona inference output counts drift")
    require(inference.get("profile_output_order") == expected_profile_order, "PERSONA_HIERARCHY", "persona probability output order drift")
    require(inference.get("profile_probability_sum") == 1.0 and inference.get("family_probability_sum") == 1.0, "PERSONA_HIERARCHY", "persona probability sums must equal 1")
    require(inference.get("mixed_or_undetermined_threshold") == 0.45, "PERSONA_HIERARCHY", "mixed/undetermined threshold drift")

    expected_data_defaults = {
        "unknown_teacher_free_text": "RESTRICTED",
        "unclassified_raw_or_scanned_upload": "RESTRICTED",
        "external_ai_egress_before_classification_and_policy_authorization": "DENY",
    }
    require(baseline.get("data_policy_defaults") == expected_data_defaults, "DATA_POLICY", "unknown/raw data fail-closed defaults drift")

    status = baseline.get("status_model", {})
    expected_evidence = ["PASS", "FAIL", "BLOCKED", "REQUIRES_ACCEPTANCE_DATA"]
    expected_release = ["NOT_READY", "CODE_COMPLETE / ACCEPTANCE DATA PENDING", "ACCEPTED"]
    expected_blocking = ["FAIL", "BLOCKED", "MISSING", "STALE"]
    require(status.get("evidence_statuses") == expected_evidence, "RELEASE_STATES", "evidence status vocabulary drift")
    require(status.get("release_states") == expected_release, "RELEASE_STATES", "release state vocabulary drift")
    require(status.get("blocking_evidence_conditions") == expected_blocking, "RELEASE_STATES", "blocking evidence conditions drift")
    rules = {item.get("release_state"): item.get("when", "") for item in status.get("rules", []) if isinstance(item, dict)}
    require(set(rules) == set(expected_release), "RELEASE_STATES", "release transition rule inventory drift")
    require(all(token in rules.get("NOT_READY", "").lower() for token in ("fail", "blocked", "missing", "stale")), "RELEASE_STATES", "NOT_READY rule must block FAIL/BLOCKED/missing/stale")
    require("REQUIRES_ACCEPTANCE_DATA" in rules.get("CODE_COMPLETE / ACCEPTANCE DATA PENDING", ""), "RELEASE_STATES", "pending rule must require acceptance data")
    require("every required gate is PASS with fresh evidence" in rules.get("ACCEPTED", ""), "RELEASE_STATES", "ACCEPTED rule must require every gate fresh PASS")
    recovery = baseline.get("recovery_objectives", {})
    require(recovery.get("acceptance_status") == "REQUIRES_ACCEPTANCE_DATA", "RELEASE_STATES", "recovery acceptance status drift")
    require(recovery.get("release_state_ceiling_before_acceptance") == "CODE_COMPLETE / ACCEPTANCE DATA PENDING", "RELEASE_STATES", "acceptance-data release ceiling drift")
    require(recovery.get("acceptance_rule") == "Each target requires institution approval and fresh isolated-drill PASS evidence before KPI-010 can PASS.", "RELEASE_STATES", "recovery acceptance rule drift")
    gate_ids = [item.get("id") for item in baseline.get("release_gates", []) if isinstance(item, dict)]
    expected_gate_ids = [
        "GATE-DESIGN-INTEGRITY", "GATE-CODE-QUALITY", "GATE-SECURITY-PRIVACY", "GATE-AI-KPI",
        "GATE-DOCUMENT-KPI", "GATE-UX-ACCESSIBILITY", "GATE-OPERATIONS-RECOVERY", "GATE-PILOT-ACCEPTANCE",
    ]
    require(gate_ids == expected_gate_ids, "RELEASE_STATES", "release gate inventory/order drift")
    launcher = baseline.get("launcher_policy", {})
    require(launcher.get("sandbox") == "workspace-write" and launcher.get("approval_policy") == "on-request", "ACTIVE_SAFETY", "launcher sandbox/approval drift")
    require(set(launcher.get("forbidden_flags", [])) == {"--dangerously-bypass-approvals-and-sandbox", "--yolo"}, "ACTIVE_SAFETY", "launcher forbidden flag policy drift")

# Final-root mirrors must remain explicit in the implementation and deliverable contracts.
for relative in ("10-delivery-implementation-plan.md", "14-final-document-deliverables.md"):
    body = text(package / relative)
    for required_root in (
        "docs/planning/ai-training-platform-v1/", "docs/design/ai-training-platform/", "docs/operations/ai-training-platform/",
        "docs/qa/ai-training-platform/", "docs/manuals/ai-training-platform/", "docs/releases/ai-training-platform/", "dist/docs/",
    ):
        require(required_root in body, "FINAL_OUTPUT_ROOTS", f"{relative} does not mirror root {required_root}")

# Exact runbook inventory, registered owners, gates, cadence/fingerprint, and required sections.
deliverables = text(package / "14-final-document-deliverables.md")
registered_owners = set(re.findall(r"^\|\s*`(OWN-[A-Z]+)`\s*\|", deliverables, re.MULTILINE))
expected_owners = {"OWN-ARCH", "OWN-PROD", "OWN-UX", "OWN-AI", "OWN-DOC", "OWN-DATA", "OWN-SEC", "OWN-OPS", "OWN-QA", "OWN-ACC"}
require(registered_owners == expected_owners, "RUNBOOK_INVENTORY", "owner registry must contain the 10 canonical OWN-* IDs")

runbook_rows = {}
runbook_row_count = 0
for line in deliverables.splitlines():
    if re.match(r"^\|\s*RB-\d{3}\s*\|", line):
        runbook_row_count += 1
        columns = [column.strip() for column in line.strip().strip("|").split("|")]
        if len(columns) != 7:
            fail("RUNBOOK_INVENTORY", f"runbook row must have 7 columns: {line}")
            continue
        if columns[0] in runbook_rows:
            fail("RUNBOOK_INVENTORY", f"duplicate runbook ID: {columns[0]}")
        runbook_rows[columns[0]] = columns
expected_runbook_ids = [f"RB-{index:03d}" for index in range(1, 24)]
require(runbook_row_count == 23 and list(runbook_rows) == expected_runbook_ids, "RUNBOOK_INVENTORY", "runbook inventory must be exactly RB-001 through RB-023")
runbook_files = []
baseline_gate_set = set(item.get("id") for item in (baseline or {}).get("release_gates", []) if isinstance(item, dict))
for runbook_id, columns in runbook_rows.items():
    filename = re.fullmatch(r"`([^`]+\.md)`", columns[1])
    require(filename is not None, "RUNBOOK_INVENTORY", f"{runbook_id} must define one Markdown filename")
    if filename:
        runbook_files.append(filename.group(1))
    owner_ids = set(re.findall(r"OWN-[A-Z]+", columns[3]))
    require(len(owner_ids) >= 2 and owner_ids <= registered_owners, "RUNBOOK_INVENTORY", f"{runbook_id} owner/escalation IDs are incomplete or unregistered")
    cadence_parts = [part.strip() for part in columns[4].split("/", 1)]
    require(len(cadence_parts) == 2 and all(cadence_parts), "RUNBOOK_INVENTORY", f"{runbook_id} must define cadence and dependency fingerprint")
    gate_ids = set(re.findall(r"GATE-[A-Z-]+", columns[6]))
    require(bool(gate_ids) and gate_ids <= baseline_gate_set, "RUNBOOK_INVENTORY", f"{runbook_id} gate IDs are missing or unknown")
require(len(runbook_files) == len(set(runbook_files)) == 23, "RUNBOOK_INVENTORY", "runbook filenames must be 23 unique Markdown paths")

required_dual_gates = {
    "RB-007": {"GATE-DOCUMENT-KPI", "GATE-OPERATIONS-RECOVERY"},
    "RB-010": {"GATE-SECURITY-PRIVACY", "GATE-OPERATIONS-RECOVERY"},
    "RB-011": {"GATE-AI-KPI", "GATE-SECURITY-PRIVACY", "GATE-OPERATIONS-RECOVERY"},
    "RB-014": {"GATE-DOCUMENT-KPI", "GATE-SECURITY-PRIVACY", "GATE-OPERATIONS-RECOVERY"},
}
for runbook_id, expected in required_dual_gates.items():
    actual = set(re.findall(r"GATE-[A-Z-]+", runbook_rows.get(runbook_id, ["", "", "", "", "", "", ""])[6]))
    require(expected <= actual, "RUNBOOK_INVENTORY", f"{runbook_id} cross-gate coverage drift")

required_runbook_sections = [
    "## Owner와 escalation", "## 목적·trigger·영향", "## 사전조건", "## copy-paste 명령", "## 예상 출력",
    "## 단계별 validation", "## 중단·rollback 기준", "## escalation과 통지", "## 증거 보존", "## 마지막 drill",
]
for heading in required_runbook_sections:
    require(deliverables.count(f"`{heading}`") == 1, "RUNBOOK_INVENTORY", f"required runbook section must appear exactly once: {heading}")
for token in ("cadence_due_at_utc", "candidate_bound", "dependency_fingerprint_algorithm", "dependency_fingerprint", "tested_image_digests[]"):
    require(token in deliverables, "RUNBOOK_INVENTORY", f"runbook freshness field missing: {token}")

manual_pairs = []
for line in deliverables.splitlines():
    match = re.match(r"^\|\s*`([^`]+\.md)`\s*\|\s*`([^`]+\.pdf)`\s*\|", line)
    if match:
        manual_pairs.append(match.groups())
expected_manual_stems = {
    "teacher-user-guide", "institution-admin-guide", "content-reviewer-guide", "system-admin-guide",
    "security-auditor-guide", "operations-operator-guide", "accessibility-and-support-guide", "quick-start",
}
require(len(manual_pairs) == 8, "MANUAL_PAIRS", f"manual inventory must contain 8 Markdown/PDF pairs; found {len(manual_pairs)}")
require({Path(md).stem for md, _ in manual_pairs} == expected_manual_stems, "MANUAL_PAIRS", "manual Markdown inventory drift")
require(all(Path(md).stem == Path(pdf).stem for md, pdf in manual_pairs), "MANUAL_PAIRS", "every manual PDF must have the same basename as its Markdown source")

# The normative final-document inventory is a closed, root-contained set.
if final_document_inventory is not None:
    expected_inventory_keys = {"schema_version", "baseline_id", "canonical_contract", "release_id_pattern", "dynamic_segment_contract", "roots", "expected_counts", "manual_combination_contract", "artifacts"}
    require(set(final_document_inventory) == expected_inventory_keys, "FINAL_DOCUMENT_INVENTORY", "final document inventory top-level key contract drift")
    expected_release_pattern = r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(alpha|beta|rc)(0|[1-9][0-9]*))?$"
    require(final_document_inventory.get("schema_version") == "final-document-inventory.v1", "FINAL_DOCUMENT_INVENTORY", "final document inventory schema version drift")
    require(final_document_inventory.get("baseline_id") == "YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1", "FINAL_DOCUMENT_INVENTORY", "final document inventory baseline ID drift")
    require(final_document_inventory.get("release_id_pattern") == expected_release_pattern, "FINAL_DOCUMENT_INVENTORY", "final document inventory release ID pattern drift")
    if baseline is not None:
        require(baseline.get("release_identifier_policy", {}).get("regex") == expected_release_pattern, "FINAL_DOCUMENT_INVENTORY", "baseline release ID pattern drift")

    dynamic_contract = final_document_inventory.get("dynamic_segment_contract", {})
    require(dynamic_contract.get("only_placeholder") == "${release_id}", "FINAL_DOCUMENT_INVENTORY", "only ${release_id} may be dynamic")
    require(all(isinstance(dynamic_contract.get(field), str) and dynamic_contract[field].strip() for field in ("expansion_rule", "containment_rule")), "FINAL_DOCUMENT_INVENTORY", "dynamic segment expansion/containment rules are missing")

    expected_inventory_roots = {
        "final_design": "docs/design/ai-training-platform/",
        "operations": "docs/operations/ai-training-platform/",
        "quality_assurance": "docs/qa/ai-training-platform/",
        "manuals": "docs/manuals/ai-training-platform/",
        "releases": "docs/releases/ai-training-platform/",
        "distribution_docs": "dist/docs/",
    }
    inventory_roots = final_document_inventory.get("roots", {})
    require(inventory_roots == expected_inventory_roots, "FINAL_DOCUMENT_INVENTORY", "final document root registry drift")
    if baseline is not None:
        require(all(baseline.get("artifact_roots", {}).get(key) == value for key, value in expected_inventory_roots.items()), "FINAL_DOCUMENT_INVENTORY", "inventory roots must match the baseline byte-for-byte")

    expected_counts = {
        "design": 48,
        "operations": 11,
        "runbook": 23,
        "qa": 18,
        "manual_markdown": 8,
        "manual_pdf": 8,
        "release": 10,
        "distribution": 21,
        "total": 147,
    }
    require(final_document_inventory.get("expected_counts") == expected_counts, "FINAL_DOCUMENT_INVENTORY", "final document expected counts drift")
    artifacts = final_document_inventory.get("artifacts", [])
    require(isinstance(artifacts, list) and len(artifacts) == expected_counts["total"], "FINAL_DOCUMENT_INVENTORY", f"final document inventory must contain {expected_counts['total']} artifacts")
    group_counts = Counter(item.get("group") for item in artifacts if isinstance(item, dict))
    for group, expected in expected_counts.items():
        if group != "total":
            require(group_counts[group] == expected, "FINAL_DOCUMENT_INVENTORY", f"final document group {group} must contain {expected} artifacts; found {group_counts[group]}")

    artifact_ids = []
    contained_paths = []
    expected_artifact_keys = {"artifact_id", "group", "root_id", "root_path", "relative_path_template", "owner_ids", "gate_ids", "media_type", "source_kind", "required"}
    expected_source_kinds = {
        "design": {"authored_markdown", "machine_contract", "verified_machine_contract", "generated_contract", "golden_vector"},
        "operations": {"authored_markdown"},
        "runbook": {"authored_runbook"},
        "qa": {"generated_report", "generated_trace"},
        "manual_markdown": {"authored_manual"},
        "manual_pdf": {"generated_accessible_pdf"},
        "release": {"authored_markdown", "generated_manifest", "detached_signature", "checksum_catalog"},
        "distribution": {"generated_accessible_pdf", "generated_trace", "generated_evidence_index", "generated_manifest", "detached_signature", "checksum_catalog", "source_snapshot", "copied_verified_manual_pdf"},
    }
    media_by_extension = {
        ".md": "text/markdown",
        ".csv": "text/csv",
        ".pdf": "application/pdf",
        ".yaml": "application/yaml",
        ".sig": "application/octet-stream",
        ".txt": "text/plain",
        ".zip": "application/zip",
        ".json": "application/json",
    }
    reserved_windows_names = {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}
    for index, artifact in enumerate(artifacts):
        location = f"artifacts[{index}]"
        if not isinstance(artifact, dict):
            fail("FINAL_DOCUMENT_INVENTORY", f"{location} must be an object")
            continue
        require(set(artifact) == expected_artifact_keys, "FINAL_DOCUMENT_INVENTORY", f"{location} artifact key contract drift")
        artifact_id = artifact.get("artifact_id", "")
        group = artifact.get("group", "")
        artifact_ids.append(artifact_id)
        require(bool(re.fullmatch(r"FDI-[A-Z]+(?:-[A-Z]+)*-\d{3}", artifact_id)), "FINAL_DOCUMENT_INVENTORY", f"invalid artifact ID at {location}: {artifact_id}")
        require(artifact.get("required") is True, "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} must be required")
        root_id = artifact.get("root_id", "")
        root_path = artifact.get("root_path", "")
        require(root_id in expected_inventory_roots and root_path == expected_inventory_roots.get(root_id), "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} root registry mismatch")

        relative = artifact.get("relative_path_template", "")
        placeholders = re.findall(r"\$\{[^}]*\}", relative) if isinstance(relative, str) else []
        require(all(item == "${release_id}" for item in placeholders) and placeholders.count("${release_id}") <= 1, "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} uses an unsafe dynamic placeholder")
        static_remainder = relative.replace("${release_id}", "") if isinstance(relative, str) else ""
        require("$" not in static_remainder and "%" not in static_remainder and "\\" not in static_remainder and ":" not in static_remainder and "\x00" not in static_remainder, "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} contains unsafe path expansion syntax")
        expanded = relative.replace("${release_id}", "v1.0.0") if isinstance(relative, str) else ""
        template_parts = relative.split("/") if isinstance(relative, str) else []
        placeholder_segment_count = template_parts.count("${release_id}")
        if group in {"release", "distribution"}:
            require(placeholder_segment_count == 1 and bool(template_parts) and template_parts[0] == "${release_id}", "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} must use release_id exactly once as its first path segment")
        else:
            require(placeholder_segment_count == 0, "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} must not use a dynamic release segment")
        relative_parts = expanded.split("/")
        require(bool(expanded) and not Path(expanded).is_absolute() and ".." not in relative_parts and "." not in relative_parts and all(relative_parts), "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} path is not root-contained")
        for segment in relative_parts:
            device_stem = segment.split(".", 1)[0].upper()
            require(unicodedata.normalize("NFC", segment) == segment, "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} path segment is not NFC-normalized")
            require(not any(ord(character) < 32 or ord(character) == 127 for character in segment), "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} path segment contains a control character")
            require(not segment.endswith((".", " ")) and device_stem not in reserved_windows_names, "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} path segment is unsafe on Windows")
        contained_paths.append((root_id, relative))

        owner_ids = artifact.get("owner_ids", [])
        gate_ids = artifact.get("gate_ids", [])
        require(isinstance(owner_ids, list) and bool(owner_ids) and len(owner_ids) == len(set(owner_ids)) and set(owner_ids) <= registered_owners, "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} owner IDs are empty, duplicate, or unregistered")
        require(isinstance(gate_ids, list) and bool(gate_ids) and len(gate_ids) == len(set(gate_ids)) and set(gate_ids) <= baseline_gate_set, "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} gate IDs are empty, duplicate, or unregistered")
        expected_media_type = "application/schema+json" if expanded.endswith(".schema.json") else next((media for extension, media in media_by_extension.items() if expanded.endswith(extension)), None)
        require(expected_media_type is not None and artifact.get("media_type") == expected_media_type, "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} media type/extension contract drift")
        require(group in expected_source_kinds and artifact.get("source_kind") in expected_source_kinds.get(group, set()), "FINAL_DOCUMENT_INVENTORY", f"{artifact_id or location} source kind/group contract drift")

    require(len(artifact_ids) == len(set(artifact_ids)) == expected_counts["total"], "FINAL_DOCUMENT_INVENTORY", "artifact IDs must be unique")
    require(len(contained_paths) == len(set(contained_paths)) == expected_counts["total"], "FINAL_DOCUMENT_INVENTORY", "root-relative artifact paths must be unique")
    manual_contract = final_document_inventory.get("manual_combination_contract", {})
    require(manual_contract.get("pair_count") == 8 and manual_contract.get("administrator_guide_source_count") == 5 and manual_contract.get("convenience_bundle_does_not_replace_pairs") is True, "FINAL_DOCUMENT_INVENTORY", "manual combination contract drift")
    require(manual_contract.get("distribution_manual_directory") == "${release_id}/manuals/", "FINAL_DOCUMENT_INVENTORY", "distribution manual directory drift")
    expected_manual_pdf_names = {f"{stem}.pdf" for stem in expected_manual_stems}
    manual_pdf_entries = [item for item in artifacts if isinstance(item, dict) and item.get("group") == "manual_pdf"]
    require({item.get("relative_path_template") for item in manual_pdf_entries} == expected_manual_pdf_names and all(item.get("source_kind") == "generated_accessible_pdf" for item in manual_pdf_entries), "FINAL_DOCUMENT_INVENTORY", "inventory manual PDF source set drift")
    expected_distribution_manuals = {f"${{release_id}}/manuals/{name}" for name in expected_manual_pdf_names}
    distribution_manual_entries = [item for item in artifacts if isinstance(item, dict) and item.get("group") == "distribution" and item.get("source_kind") == "copied_verified_manual_pdf"]
    require({item.get("relative_path_template") for item in distribution_manual_entries} == expected_distribution_manuals and len(distribution_manual_entries) == 8, "FINAL_DOCUMENT_INVENTORY", "distribution must contain exact verified copies of all 8 manual PDFs")
    expected_admin_sources = ["institution-admin-guide.pdf", "content-reviewer-guide.pdf", "system-admin-guide.pdf", "security-auditor-guide.pdf", "operations-operator-guide.pdf"]
    actual_admin_sources = manual_contract.get("administrator_guide_sources", [])
    require(actual_admin_sources == expected_admin_sources and len(actual_admin_sources) == len(set(actual_admin_sources)) and set(actual_admin_sources) <= expected_manual_pdf_names, "FINAL_DOCUMENT_INVENTORY", "administrator guide source inventory drift")

# The shared generator above validates the complete dynamic recursive mapping,
# exclusions, canonical JSON bytes, per-source digest/size/mode, and ordering.
if manifest is not None:
    require(manifest.get("manifest_version") == "overlay.v2", "RUNTIME_CONTRACT", "overlay manifest version drift")
    require(manifest.get("policy_id") == "OVERLAY_POLICY_V2_RECURSIVE_EXACT", "RUNTIME_CONTRACT", "overlay policy parity marker drift")
    require(manifest.get("baseline_id") == "YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1", "RUNTIME_CONTRACT", "overlay baseline ID drift")
    require(manifest.get("target_root") == r"D:\Views\yonlab-inuri-site", "RUNTIME_CONTRACT", "overlay target root drift")
    require(manifest.get("target_remote") == "https://github.com/yubi-lee/yonlab-i-nuri-site.git", "RUNTIME_CONTRACT", "overlay target remote drift")
    require(manifest.get("target_branch") == "feat/ai-training-platform-v1", "RUNTIME_CONTRACT", "overlay target branch drift")
    entries = manifest.get("files", [])
    sources = [entry.get("source") for entry in entries if isinstance(entry, dict)]
    destinations = [entry.get("destination") for entry in entries if isinstance(entry, dict)]
    require(manifest.get("file_count") == len(entries) and len(entries) > 0, "RUNTIME_CONTRACT", "overlay file count drift")
    require(len(sources) == len(set(sources)) and len(destinations) == len(set(destinations)), "RUNTIME_CONTRACT", "overlay sources/destinations must be unique")
    for entry in entries:
        if not isinstance(entry, dict):
            fail("RUNTIME_CONTRACT", "overlay file entry must be an object")
            continue
        require(set(entry) == {"source", "destination", "sha256", "bytes", "mode"}, "RUNTIME_CONTRACT", "overlay file entry must contain exactly source, destination, sha256, bytes, and mode")
        source = entry.get("source", "")
        destination = entry.get("destination", "")
        for value, label in ((source, "source"), (destination, "destination")):
            pure = Path(value)
            require(bool(value) and not pure.is_absolute() and ".." not in pure.parts, "RUNTIME_CONTRACT", f"unsafe overlay {label}: {value}")
        declared_hash = entry.get("sha256", "")
        require(bool(re.fullmatch(r"[0-9a-f]{64}", declared_hash)), "RUNTIME_CONTRACT", f"overlay sha256 must be lowercase SHA-256: {source}")
        require(isinstance(entry.get("bytes"), int) and entry.get("bytes", 0) > 0, "RUNTIME_CONTRACT", f"overlay bytes must be a positive integer: {source}")
        require(entry.get("mode") == "100644", "RUNTIME_CONTRACT", f"overlay install mode drift: {source}")

runner = text(work / "repo-overlay/scripts/invoke-ai-training-platform-v1.ps1")
starter = text(work / "start-ai-training-platform-v1.ps1")
validator = text(work / "repo-overlay/scripts/validate-codex-final-result.ps1")
ps_verifier = text(package / "verify-design-package.ps1")
trust_template = json.loads(text(package / "release-trust.example.json"))
require(bool(validator.strip()), "RUNTIME_CONTRACT", "validator is missing or empty")
for body, name in ((runner, "runner"), (starter, "starter"), (validator, "validator")):
    require("D:\\Views\\yonlab-inuri-site" in body or name == "validator", "RUNTIME_CONTRACT", f"{name} omits canonical root")
require("codex-output.schema.json" in runner, "RUNTIME_CONTRACT", "runner must bind the model-facing output schema")
require("codex-final-result.schema.json" in runner, "RUNTIME_CONTRACT", "runner must bind the strict final-result schema for second-stage validation")
require("final-document-inventory.json" in runner and "final_document_inventory_sha256" in runner, "RUNTIME_CONTRACT", "runner must bind the normative final-document inventory hash")
require("$entry.sha256" in starter and "overlay_manifest_sha256" in starter, "RUNTIME_CONTRACT", "bootstrap must enforce manifest source hashes and bind the manifest digest")
require("package verification did not PASS" in starter and "source is outside the closed recursive mapping policy" in starter, "RUNTIME_CONTRACT", "bootstrap must invoke package verification and independently enforce the closed mapping")
require("Assert-NoReparseAncestor -Path $backupRoot" in starter and ".artifacts/codex/overlay-backups" in starter, "RUNTIME_CONTRACT", "bootstrap must reject reparse backup roots before writing receipts")
require("TrustedGitCommand" in starter and "Assert-SafeLocalGitConfig" in starter and "PRE-GIT-CONFIG" in starter, "RUNTIME_CONTRACT", "bootstrap must use the pinned Git executable and reject executable/transport local config")
require("TrustedPythonCommand" in starter and "-PythonPath $script:TrustedPythonCommand" in starter, "RUNTIME_CONTRACT", "bootstrap must run semantic package gates with the protected pinned Python executable")
require(ps_verifier.count("& $PythonCommand -I -S -B $Checker") == 1, "RUNTIME_CONTRACT", "PowerShell verifier must have exactly one isolated Python gate invocation")
require(ps_verifier.count("Push-Location -LiteralPath (Split-Path -Parent $PythonCommand)") == 1 and "Push-Location -LiteralPath (Split-Path -Parent $script:TrustedGitCommand)" in starter, "RUNTIME_CONTRACT", "trusted Python and Git child processes must run from their protected executable directories")
require(starter.count("Assert-CanonicalBootstrapHost") == 2 and '$expectedPrefix = @("-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File")' in starter and "bootstrap -File target must be this exact starter script" in starter and "bootstrapTrust.PowerShell" in starter, "RUNTIME_CONTRACT", "bootstrap must invoke the canonical pinned exact-prefix PowerShell host preflight")
require(starter.count("Assert-TrustedPythonRuntimeClosure -PythonPath $python") == 1 and "PRE-PYTHON-RUNTIME" in starter and "GetFolderPath([Environment+SpecialFolder]::ProgramFiles)" in starter and "bootstrap Python and PowerShell require exact valid Authenticode" in starter, "RUNTIME_CONTRACT", "bootstrap must recursively close the signed Program Files Python runtime trust boundary")
require(starter.count("Assert-BootstrapTrustPathChain -Path $Path") == 2 and "$trustHashBefore" in starter and "$trustHashAfter" in starter and "$insideAnchor" in starter, "RUNTIME_CONTRACT", "bootstrap must validate and revalidate the entire protected release-trust path chain and bytes")
require("Assert-StrictBootstrapJsonLexical" in starter and "ConvertFrom-StrictBootstrapJsonFile -Path $Path" in starter and "Assert-ExactBootstrapProperties $trust" in starter and "duplicate/ambiguous JSON property" in starter, "RUNTIME_CONTRACT", "bootstrap must parse bounded strict UTF-8 release trust with duplicate-key and exact-property rejection")
require("Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json" not in starter, "RUNTIME_CONTRACT", "bootstrap must not parse root-of-trust JSON with permissive raw ConvertFrom-Json")
require('& ([string]$bootstrapTrust.PowerShell) @runnerArguments' in starter and '"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $runner' in starter and "& $runner" not in starter, "RUNTIME_CONTRACT", "bootstrap must spawn the installed runner under the pinned exact-prefix PowerShell host")
require('$bootstrapCommandPrefix = "& \'$([string]$bootstrapTrust.PowerShell)\' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File' in starter and 'Write-Host "Review without writes: $bootstrapCommandPrefix -InstallOverlay -DryRun"' in starter and 'Write-Host "Install with backup: $bootstrapCommandPrefix -InstallOverlay"' in starter and "Review without writes: powershell -ExecutionPolicy" not in starter, "RUNTIME_CONTRACT", "bootstrap retry guidance must preserve the pinned canonical host, exact prefix, and exact starter path")
canonical_resume = "return \"& '$CanonicalRunnerHost' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File '$CanonicalRunnerPath' -Mode Implement -ResumeRun '$RunId'\""
require('$CanonicalRunnerHost = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"' in runner and '$CanonicalRunnerPath = "D:\\Views\\yonlab-inuri-site\\scripts\\invoke-ai-training-platform-v1.ps1"' in runner and canonical_resume in runner and "$resumeCommand = Get-ResumeCommand -RunId $runId" in runner and "RESUME: powershell -ExecutionPolicy" not in runner, "RUNTIME_CONTRACT", "runner resume guidance must preserve the canonical host, exact prefix, absolute runner path, and Implement mode")
require(trust_template.get("trusted_tools", {}).get("powershell", {}).get("path") == r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" and trust_template["trusted_tools"]["powershell"].get("authenticode_required") is True, "RUNTIME_CONTRACT", "release trust template must pin the canonical signed production PowerShell host")
require(trust_template.get("trusted_tools", {}).get("python", {}).get("authenticode_required") is True and trust_template["trusted_tools"]["python"].get("authenticode_signer_thumbprint") == "REPLACE_WITH_40_OR_64_HEX_THUMBPRINT", "RUNTIME_CONTRACT", "release trust template must require the signed Program Files Python runtime")
template_workflows = {item.get("check_name"): item for item in trust_template.get("github_policy", {}).get("workflows", [])}
for windows_check in ("design-package-windows", "release-signatures"):
    require(template_workflows.get(windows_check, {}).get("required_runner_labels") == ["self-hosted", "Windows", "X64"], "RUNTIME_CONTRACT", f"release trust template must pin exact self-hosted Windows labels for {windows_check}")
require(starter.count("Assert-NoBootstrapExecutionEnvironmentOverrides") == 2 and "GIT_CONFIG_COUNT" in starter and "GIT_CONFIG_KEY_" in starter and "GIT_SSH" in starter, "RUNTIME_CONTRACT", "bootstrap must reject ambient Git/GPG/GitHub execution overrides before its first Git call")
bootstrap_environment_cleanup = 'foreach ($bootstrapGitEnvironmentName in @("GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL", "GIT_TERMINAL_PROMPT", "GCM_INTERACTIVE"))'
runner_spawn = '& ([string]$bootstrapTrust.PowerShell) @runnerArguments'
cleanup_index = starter.find(bootstrap_environment_cleanup)
runner_spawn_index = starter.find(runner_spawn)
require(cleanup_index >= 0 and runner_spawn_index >= 0 and cleanup_index < runner_spawn_index, "RUNTIME_CONTRACT", "bootstrap must remove its fixed Git environment before spawning the runner")
acl_function_start = starter.find("function Assert-NonBroadWritablePathChain")
acl_function_end = starter.find("function Resolve-TrustedExecutable", max(acl_function_start, 0))
require(acl_function_start >= 0 and acl_function_end > acl_function_start, "RUNTIME_CONTRACT", "bootstrap trusted executable ACL function boundary is missing")
acl_function = starter[acl_function_start:acl_function_end] if acl_function_start >= 0 and acl_function_end > acl_function_start else ""
acl_owner_read = "$ownerSid = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value"
acl_owner_compare = "if ($trustedWriteSids -notcontains $ownerSid)"
require(acl_function.count(acl_owner_read) == 1 and acl_function.count(acl_owner_compare) == 1 and "untrusted ACL owner" in acl_function and "GetPathRoot($resolved)" in acl_function and "$replacementMask" in acl_function and "$insideAllowedRoot" in acl_function, "RUNTIME_CONTRACT", "bootstrap trusted executable ACL function must retrieve and compare each path owner and enforce two-tier replacement rights through the volume root")
require('$effectiveMask = $(if ($insideAllowedRoot) { $writeMask } else { $replacementMask })' in starter and 'if ([StringComparer]::OrdinalIgnoreCase.Equals($current, $allowedRoot)) { $insideAllowedRoot = $false }' in starter, "RUNTIME_CONTRACT", "bootstrap must switch from descendant-write checks to ancestor-replacement checks only above the allowed root")
require("LOCALAPPDATA" not in starter, "RUNTIME_CONTRACT", "bootstrap must not admit a user-writable LocalAppData executable trust root")
require("LOCALAPPDATA" not in runner and "$replacementMask=" in runner and "$insideAllowedRoot=$false" in runner and "PropagationFlags]::InheritOnly" in runner and "$volumeRoot=[IO.Path]::GetPathRoot($resolved)" in runner, "RUNTIME_CONTRACT", "runner and bootstrap must share the non-user-writable two-tier ACL path policy")
require("Write-DurableJson" in starter and "overlay-transaction.v1" in starter and "OVERLAY-RECOVERY" in starter, "RUNTIME_CONTRACT", "bootstrap must durably journal before target writes and block incomplete recovery")
durable_backup = "Copy-DurableFileData -Source $change.Destination -Destination $backup -CreateNew"
prepared_state = 'state = "PREPARED"'
durable_install = "Flush-DurableFileData -Path $change.Destination"
committed_state = '$transactionJournal.state = "COMMITTED"'
require("function Copy-DurableFileData" in starter and "function Flush-DurableFileData" in starter and "$outputStream.Flush($true)" in starter, "RUNTIME_CONTRACT", "bootstrap must durably flush backup and staged file bytes")
require(durable_backup in starter and prepared_state in starter and starter.index(durable_backup) < starter.index(prepared_state), "RUNTIME_CONTRACT", "durable backup flush must precede PREPARED journal state")
require(durable_install in starter and committed_state in starter and starter.index(durable_install) < starter.index(committed_state), "RUNTIME_CONTRACT", "installed file flush must precede COMMITTED journal state")
require("Copy-Item -LiteralPath $change.Destination" not in starter and "[System.IO.File]::WriteAllBytes($temporaryDestination" not in starter, "RUNTIME_CONTRACT", "non-durable backup or staging writes are forbidden")
require("Copy-DurableFileData" in starter and "Assert-DataStreamPolicy" in starter and "FileStream" in starter, "RUNTIME_CONTRACT", "bootstrap must copy only the unnamed stream and strip/reject undeclared NTFS alternate streams")

def strip_powershell_here_strings(source: str) -> str:
    """Remove here-string payloads before conservative line-oriented checks.

    The PowerShell parity verifier performs the authoritative AST check.  This
    Bash-side precheck must nevertheless avoid treating an embedded child
    process script as a root statement in the outer runner.
    """

    output: list[str] = []
    closing: str | None = None
    for line in source.splitlines():
        if closing is not None:
            if re.fullmatch(rf"\s*{re.escape(closing)}\s*", line):
                closing = None
            output.append("")
            continue
        match = re.search(r"@(['\"])\s*$", line)
        if match:
            closing = match.group(1) + "@"
            output.append(line[: match.start()])
        else:
            output.append(line)
    require(closing is None, "RUNTIME_CONTRACT", "runner contains an unterminated PowerShell here-string")
    return "\n".join(output)


runner_code_without_here_strings = strip_powershell_here_strings(runner)
direct_root_exits = re.findall(r"(?m)^exit\s+[^\r\n]+$", runner_code_without_here_strings)
require(len(direct_root_exits) == 1, "RUNTIME_CONTRACT", "runner must contain exactly one direct root exit at its terminal handoff")
require(runner.count("Invoke-Utf8Process -Command $codexCommand") == 1, "ACTIVE_SAFETY", "runner must have exactly one active Codex process invocation")
dangerous_helper = re.compile(
    r"(?is)(?:SafeGit|Invoke-Git)\s+[^\r\n]{0,160}@\([^)]*['\"](?:reset|checkout|switch|rebase|clean|update-ref)['\"]"
)
require(not dangerous_helper.search(runner + "\n" + starter), "ACTIVE_SAFETY", "Git helper invocation contains a forbidden history/worktree mutation subcommand")

argument_match = re.search(
    r"\$CodexArguments\s*=\s*(.*?)(?=^\s*Assert-SafeCodexArguments\b)",
    runner,
    re.MULTILINE | re.DOTALL,
)
require(argument_match is not None, "ACTIVE_SAFETY", "Codex argument assignment is missing")
if argument_match:
    argument_block = argument_match.group(1)
    require("$outputSchemaPath" in argument_block, "RUNTIME_CONTRACT", "active Codex output-schema argument must use the model-facing schema path")
    for required_token in ('"exec"', '"-C"', '"--sandbox"', '"workspace-write"', '"--ask-for-approval"', '"on-request"', '"--json"', '"--output-last-message"', '"--output-schema"', '"-"'):
        require(required_token in argument_block, "ACTIVE_SAFETY", f"Codex argument missing: {required_token}")
    require(not re.search(r"--dangerously-bypass-approvals-and-sandbox|--yolo|--full-auto|--last", argument_block), "ACTIVE_SAFETY", "unsafe/deprecated flag appears in active Codex argument array")

for source, name in ((runner, "runner"), (starter, "starter")):
    require(not re.search(r"(?im)^\s*(?:&\s*)?git(?:\.exe)?\s+(?:switch|checkout|rebase|reset|fetch|push\s+--force)\b", source), "ACTIVE_SAFETY", f"{name} contains active Git branch/history mutation")
for line in runner.splitlines():
    if "codex exec" in line.lower():
        require(not re.search(r"--dangerously-bypass-approvals-and-sandbox|--yolo|--full-auto|--last", line), "ACTIVE_SAFETY", "unsafe flag appears in active/resume Codex invocation")

def code_fences(body: str):
    in_fence = False
    current = []
    for line in body.splitlines():
        if re.match(r"^\s*```", line):
            if in_fence:
                yield "\n".join(current)
                current = []
            in_fence = not in_fence
        elif in_fence:
            current.append(line)

for markdown in markdown_files:
    for block in code_fences(text(markdown)):
        for line in block.splitlines():
            if re.search(r"\bcodex\s+exec\b", line, re.IGNORECASE):
                require(not re.search(r"--dangerously-bypass-approvals-and-sandbox|--yolo|--full-auto|--last", line), "ACTIVE_SAFETY", f"unsafe active Codex invocation in {markdown.relative_to(work)}")
            require(not re.search(r"(?i)\bgit\s+(?:switch|checkout|rebase|reset|fetch|push\s+--force)\b", line), "ACTIVE_SAFETY", f"active Git history mutation in {markdown.relative_to(work)}")

shell_sources = sorted({*package.rglob("*.sh"), *(work / "repo-overlay").rglob("*.sh")})
for candidate in shell_sources:
    if candidate.is_file():
        executable = bool(candidate.stat().st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
        require(executable, "SHELL_MODES", f"shell source is not executable: {candidate.relative_to(work)}")

if failures:
    for code, message in failures:
        print(f"FAIL [{code}]: {message}", file=sys.stderr)
    raise SystemExit(1)

for code, message in (
    ("CANONICAL_FILES", f"canonical package/workspace files present ({len(required_package_files) + len(required_workspace_files)})"),
    ("JSON_PARSE", "baseline, schemas, and overlay manifest parse as strict JSON"),
    ("MODEL_OUTPUT_SCHEMA", "model-facing schema uses the supported strict object subset"),
    ("FINAL_DOCUMENT_INVENTORY", "147 final artifacts are exact, registered, and root-contained"),
    ("COMPLETENESS_CONTRACTS", "OpenAPI, AsyncAPI, entities, RAG, provider, reuse, and UI closure are coherent"),
    ("SOURCE_TRACEABILITY", "public-safe source identities, mappings, and reverse test edges are coherent"),
    ("NORMATIVE_TEST_SEMANTICS", "all normative tests have executable pass/fail semantics"),
    ("SEMANTIC_DEPTH_CONTRACTS", "rubric, persona, ABAC, provider, evaluation, and HWP depth contracts are coherent"),
    ("AI_GATEWAY_SAFEGUARDING", "AI safeguarding decisions are closed and fail-safe"),
    ("TCH_015_AUTHORIZATION", "privileged Document AI operations require exact authorization evidence"),
    ("MACHINE_CONTRACTS", "registries, routes, KPI cells, golden vectors, and schema fixtures are coherent"),
    ("REQUIREMENT_COUNTS", "60 RFP and 33 system requirements are exact"),
    ("DOCUMENT_IDS", f"{len(expected_doc_ids)} document IDs are exact and unique"),
    ("MARKDOWN_STRUCTURE", "Markdown fences and relative links are valid"),
    ("CANONICAL_COORDINATES", "repository coordinates are canonical"),
    ("KPI_THRESHOLDS", "KPI-001 through KPI-010 thresholds are canonical"),
    ("PERSONA_HIERARCHY", "six families and twelve profiles are canonical"),
    ("DATA_POLICY", "unknown/raw data defaults are fail-closed"),
    ("RELEASE_STATES", "release evidence and transition rules are fail-closed"),
    ("FINAL_OUTPUT_ROOTS", "planning and final output roots are exact"),
    ("RUNBOOK_INVENTORY", "23 runbooks, owners, gates, freshness, and sections are exact"),
    ("MANUAL_PAIRS", "8 Markdown/PDF manual pairs are exact"),
    ("RUNTIME_CONTRACT", "launcher, starter, validator, and overlay manifest contract is complete"),
    ("ACTIVE_SAFETY", "active Codex and Git invocations are safe"),
    ("SHELL_MODES", "shell sources are executable"),
):
    print(f"PASS [{code}]: {message}")
PY
python_status=$?

if ((python_status != 0 || gate_failures != 0)); then
  printf 'RESULT: FAIL\n'
  exit 1
fi

printf 'RESULT: PASS\n'
