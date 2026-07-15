#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$PACKAGE_ROOT/verify-normative-test-semantics.py"

python3 "$CHECKER" --package-root "$PACKAGE_ROOT"

expect_rejected() {
  local label="$1"
  local mutation="$2"
  local temp_root
  temp_root="$(mktemp -d)"
  cp -R "$PACKAGE_ROOT/." "$temp_root/"
  python3 - "$temp_root" "$mutation" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
mutation = sys.argv[2]
map_path = root / "normative-test-semantics.json"
registry_path = root / "requirements-test-registry.json"
semantic_map = json.loads(map_path.read_text(encoding="utf-8"))
registry = json.loads(registry_path.read_text(encoding="utf-8"))

map_by_id = {row["test_id"]: row for row in semantic_map["tests"]}
registry_by_id = {row["test_id"]: row for row in registry["tests"]}

if mutation == "swap-ai-003-004":
    left = map_by_id["T-AI-003"]
    right = map_by_id["T-AI-004"]
    for field in ("title", "metric_id", "acceptance_formula", "threshold"):
        left[field], right[field] = right[field], left[field]
elif mutation == "weaken-doc-008":
    map_by_id["T-DOC-008"]["threshold"]["value"] = 900_000
elif mutation == "replace-kpi-005":
    map_by_id["T-KPI-005"]["metric_id"] = "METRIC-KPI-005-TENANT-TRACE"
elif mutation == "rotate-rec-title":
    registry_by_id["T-REC-002"]["title"] = registry_by_id["T-REC-003"]["title"].replace("T-REC-003", "T-REC-002")
elif mutation == "remove-anchor":
    map_by_id["T-DR-002"]["normative_anchor"] = "VER-ATP-009#MISSING-ANCHOR"
else:
    raise SystemExit(f"unknown mutation: {mutation}")

map_path.write_text(json.dumps(semantic_map, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
registry_path.write_text(json.dumps(registry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  if python3 "$temp_root/verify-normative-test-semantics.py" --package-root "$temp_root" >/dev/null 2>&1; then
    echo "FAIL: mutation was accepted: $label" >&2
    rm -rf "$temp_root"
    exit 1
  fi
  rm -rf "$temp_root"
  echo "PASS: mutation rejected: $label"
}

expect_rejected "AI-003/004 semantic swap" "swap-ai-003-004"
expect_rejected "DOC-008 threshold weakening" "weaken-doc-008"
expect_rejected "KPI-005 metric replacement" "replace-kpi-005"
expect_rejected "REC title rotation" "rotate-rec-title"
expect_rejected "missing normative anchor" "remove-anchor"

echo "RESULT: PASS"
