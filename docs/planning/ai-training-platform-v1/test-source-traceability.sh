#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$ROOT/verify-source-traceability.py"
MANIFEST="$ROOT/source-traceability-manifest.json"
REGISTRY="$ROOT/requirements-test-registry.json"
MIRROR="$ROOT/source-traceability.md"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for required in "$CHECKER" "$MANIFEST" "$REGISTRY" "$MIRROR"; do
  [[ -s "$required" ]] || fail "missing source-traceability artifact: $required"
done

python3 "$CHECKER" --root "$ROOT"

if [[ -n "${PRIVATE_SOURCE_DIR:-}" ]]; then
  python3 "$CHECKER" --root "$ROOT" --private-source-dir "$PRIVATE_SOURCE_DIR"
fi

mutate_and_reject() {
  local name="$1"
  local mutation="$2"
  local temp
  temp="$(mktemp -d)"
  cp "$CHECKER" "$MANIFEST" "$REGISTRY" "$MIRROR" "$temp/"
  python3 - "$temp" "$mutation" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
mutation = sys.argv[2]
manifest_path = root / "source-traceability-manifest.json"
registry_path = root / "requirements-test-registry.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

if mutation == "rfp-page":
    manifest["rfp_requirements"][0]["physical_pages"] = [9]
elif mutation == "rfp-row-missing":
    manifest["rfp_requirements"].pop()
elif mutation == "test-edge":
    manifest["rfp_requirements"][0]["acceptance_test_ids"] = ["T-UNKNOWN-001"]
elif mutation == "proposal-locator":
    manifest["proposal_topics"][0]["locators"][0]["body_child_index"] += 1
elif mutation == "source-hash":
    manifest["sources"][0]["sha256"] = "0" * 64
elif mutation == "unsafe-excerpt":
    manifest["proposal_topics"][0]["source_excerpt"] = "private source text"
elif mutation == "registry-edge":
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    registry["rfp_requirements"][0]["test_ids"] = ["T-GOV-002"]
    registry_path.write_text(json.dumps(registry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
else:
    raise SystemExit(f"unknown mutation: {mutation}")

manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  if python3 "$temp/verify-source-traceability.py" --root "$temp" >/dev/null 2>&1; then
    rm -rf "$temp"
    fail "mutation passed: $name"
  fi
  rm -rf "$temp"
  printf 'PASS: mutation rejected: %s\n' "$name"
}

mutate_and_reject "RFP physical page" "rfp-page"
mutate_and_reject "RFP row deletion" "rfp-row-missing"
mutate_and_reject "acceptance test edge" "test-edge"
mutate_and_reject "proposal OPC locator" "proposal-locator"
mutate_and_reject "source digest" "source-hash"
mutate_and_reject "verbatim/private excerpt field" "unsafe-excerpt"
mutate_and_reject "registry reverse edge" "registry-edge"

printf 'RESULT: PASS\n'
