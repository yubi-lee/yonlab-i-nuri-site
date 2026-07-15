#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$PACKAGE_ROOT/verify-ai-gateway-safeguarding.py"

python3 "$CHECKER" --package-root "$PACKAGE_ROOT"

reject_mutation() {
  local mutation="$1"
  local temp_root
  temp_root="$(mktemp -d)"
  cp -R "$PACKAGE_ROOT/." "$temp_root/"
  python3 - "$temp_root" "$mutation" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
mutation = sys.argv[2]
schema_path = root / "ai-gateway-request.schema.json"
schema = json.loads(schema_path.read_text(encoding="utf-8"))
enum = schema["$defs"]["dataUsePayload"]["properties"]["safeguarding_decision"]["enum"]
if mutation == "restore-legacy-enum":
    enum[:] = ["STANDARD", "HUMAN_REVIEW", "DENY"]
elif mutation == "accept-unknown":
    enum.append("UNKNOWN")
else:
    raise SystemExit(mutation)
schema_path.write_text(json.dumps(schema, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  if python3 "$temp_root/verify-ai-gateway-safeguarding.py" --package-root "$temp_root" >/dev/null 2>&1; then
    echo "FAIL: safeguarding mutation accepted: $mutation" >&2
    rm -rf "$temp_root"
    exit 1
  fi
  rm -rf "$temp_root"
  echo "PASS: safeguarding mutation rejected: $mutation"
}

reject_mutation "restore-legacy-enum"
reject_mutation "accept-unknown"
echo "RESULT: PASS"
