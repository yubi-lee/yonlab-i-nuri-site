#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$PACKAGE_ROOT/verify-tch-015-authorization.py"

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
path = root / "tch-015-authorization-contract.json"
contract = json.loads(path.read_text(encoding="utf-8"))
cases = {row["case_id"]: row for row in contract["cases"]}
if mutation == "reviewer-edit":
    cases["AUTHZ-TCH015-DENY-REVIEWER-EDIT"]["expected_decision"] = "ALLOW"
elif mutation == "teacher-approve":
    cases["AUTHZ-TCH015-DENY-TEACHER-APPROVE"]["expected_decision"] = "ALLOW"
elif mutation == "other-tenant":
    cases["AUTHZ-TCH015-DENY-OTHER-TENANT"]["expected_decision"] = "ALLOW"
elif mutation == "shared-operation-authz":
    routes_path = root / "screen-route-contracts.json"
    routes = json.loads(routes_path.read_text(encoding="utf-8"))
    screen = next(row for row in routes["screens"] if row["screen_id"] == "TCH-015")
    shared = screen["operation_contracts"][0]["authorization_contract_id"]
    for operation in screen["operation_contracts"]:
        operation["authorization_contract_id"] = shared
    routes_path.write_text(json.dumps(routes, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
elif mutation == "weaken-formula":
    contract["operation_contracts"][0]["authorization_formula"] = "same_tenant AND allow_all"
else:
    raise SystemExit(mutation)
path.write_text(json.dumps(contract, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  if python3 "$temp_root/verify-tch-015-authorization.py" --package-root "$temp_root" >/dev/null 2>&1; then
    echo "FAIL: TCH-015 authz mutation accepted: $mutation" >&2
    rm -rf "$temp_root"
    exit 1
  fi
  rm -rf "$temp_root"
  echo "PASS: TCH-015 authz mutation rejected: $mutation"
}

reject_mutation "reviewer-edit"
reject_mutation "teacher-approve"
reject_mutation "other-tenant"
reject_mutation "shared-operation-authz"
reject_mutation "weaken-formula"
echo "RESULT: PASS"
