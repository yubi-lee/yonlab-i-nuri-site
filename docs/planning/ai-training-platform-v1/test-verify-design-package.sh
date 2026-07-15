#!/usr/bin/env bash
set -uo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_ROOT="$(cd "$PACKAGE_ROOT/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

failures=0
passes=0
powershell_runtime_blocked=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'PASS: %s\n' "$1"
  passes=$((passes + 1))
}

copy_fixture() {
  local name="$1"
  local fixture="$TMP_ROOT/$name"
  mkdir -p "$fixture"
  cp -a "$PACKAGE_ROOT" "$fixture/yonlab-ai-training-platform-design"
  cp -a "$WORK_ROOT/repo-overlay" "$fixture/repo-overlay"
  cp -a "$WORK_ROOT/AI-Gateway-UniClaudeProxy-Reuse-Design.md" "$fixture/"
  cp -a "$WORK_ROOT/generate-overlay-manifest.py" "$fixture/"
  cp -a "$WORK_ROOT/overlay-manifest.json" "$fixture/"
  cp -a "$WORK_ROOT/start-ai-training-platform-v1.ps1" "$fixture/"
  printf '%s\n' "$fixture"
}

result_line_is() {
  local expected="$1"
  local output="$2"
  [[ "$(grep -Ec '^RESULT: (PASS|FAIL)$' "$output" || true)" = 1 ]] &&
    [[ "$(tail -n 1 "$output")" == "RESULT: $expected" ]]
}

run_bash_verifier() {
  local fixture="$1"
  local output="$2"
  bash "$fixture/yonlab-ai-training-platform-design/verify-design-package.sh" >"$output" 2>&1
}

run_powershell_verifier() {
  local fixture="$1"
  local output="$2"
  local verifier="$fixture/yonlab-ai-training-platform-design/verify-design-package.ps1"
  if [[ -n "${PWSH_BIN:-}" && -x "${PWSH_BIN}" ]]; then
    "${PWSH_BIN}" -NoLogo -NoProfile -File "$verifier" -PackageRoot "$fixture/yonlab-ai-training-platform-design" >"$output" 2>&1
  elif command -v pwsh >/dev/null 2>&1; then
    pwsh -NoLogo -NoProfile -File "$verifier" -PackageRoot "$fixture/yonlab-ai-training-platform-design" >"$output" 2>&1
  elif command -v powershell >/dev/null 2>&1; then
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$verifier" -PackageRoot "$fixture/yonlab-ai-training-platform-design" >"$output" 2>&1
  else
    return 125
  fi
}

run_overlay_bootstrap_test() {
  local fixture="$1"
  local output="$2"
  local test_script="$fixture/repo-overlay/scripts/tests/test-overlay-bootstrap.ps1"
  local starter="$fixture/start-ai-training-platform-v1.ps1"
  if [[ -n "${PWSH_BIN:-}" && -x "${PWSH_BIN}" ]]; then
    "${PWSH_BIN}" -NoLogo -NoProfile -File "$test_script" -StarterPath "$starter" >"$output" 2>&1
  elif command -v pwsh >/dev/null 2>&1; then
    pwsh -NoLogo -NoProfile -File "$test_script" -StarterPath "$starter" >"$output" 2>&1
  elif command -v powershell >/dev/null 2>&1; then
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$test_script" -StarterPath "$starter" >"$output" 2>&1
  else
    return 125
  fi
}

mutate_fixture() {
  local case_name="$1"
  local fixture="$2"
  python3 - "$case_name" "$fixture" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

case_name = sys.argv[1]
root = Path(sys.argv[2])
package = root / "yonlab-ai-training-platform-design"

def load(path):
    return json.loads(path.read_text(encoding="utf-8"))

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

if case_name == "canonical_path":
    path = package / "design-baseline.json"
    value = load(path)
    value["repository"]["windows_root"] = r"D:\Views\wrong-repository"
    save(path, value)
elif case_name == "kpi_minimum":
    path = package / "design-baseline.json"
    value = load(path)
    value["kpis"][0]["minimum"] = 0.84
    save(path, value)
elif case_name == "persona_count":
    path = package / "design-baseline.json"
    value = load(path)
    value["persona_hierarchy"]["operational_profile_count"] = 11
    save(path, value)
elif case_name == "required_document":
    (package / "15-normative-policy-and-interface-contracts.md").unlink()
elif case_name == "broken_link":
    path = package / "README.md"
    text = path.read_text(encoding="utf-8")
    text = text.replace("(12-ui-ux-visual-system.md)", "(missing-ui-system.md)", 1)
    path.write_text(text, encoding="utf-8")
elif case_name == "duplicate_document_id":
    path = package / "15-normative-policy-and-interface-contracts.md"
    text = path.read_text(encoding="utf-8")
    text = text.replace("문서 ID: NORM-CONTRACT-015", "문서 ID: CODEX-RUN-013", 1)
    path.write_text(text, encoding="utf-8")
elif case_name == "unsafe_codex_invocation":
    path = root / "repo-overlay/scripts/invoke-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    start = text.index("$CodexArguments")
    end = text.index("Assert-SafeCodexArguments", start)
    argument_block = text[start:end]
    if '"--json"' not in argument_block:
        raise SystemExit("fixture runner has no active --json argument")
    argument_block = argument_block.replace('"--json"', '"--yolo", "--json"', 1)
    text = text[:start] + argument_block + text[end:]
    path.write_text(text, encoding="utf-8")
elif case_name == "history_mutation":
    path = root / "repo-overlay/scripts/invoke-ai-training-platform-v1.ps1"
    path.write_text(path.read_text(encoding="utf-8") + "\n& git reset --hard HEAD\n", encoding="utf-8")
elif case_name == "runner_early_exit":
    path = root / "repo-overlay/scripts/invoke-ai-training-platform-v1.ps1"
    path.write_text("exit 0\n" + path.read_text(encoding="utf-8"), encoding="utf-8")
elif case_name == "runner_helper_reset":
    path = root / "repo-overlay/scripts/invoke-ai-training-platform-v1.ps1"
    path.write_text(path.read_text(encoding="utf-8") + '\nSafeGit $gitCommand @("reset","--hard","HEAD")\n', encoding="utf-8")
elif case_name == "runner_second_codex":
    path = root / "repo-overlay/scripts/invoke-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "$codexExit = Invoke-Utf8Process -Command $codexCommand"
    if text.count(needle) != 1:
        raise SystemExit("fixture runner must contain exactly one active Codex invocation")
    text = text.replace(needle, "$duplicateCodexExit = Invoke-Utf8Process -Command $codexCommand\n" + needle, 1)
    path.write_text(text, encoding="utf-8")
elif case_name == "completeness_contract_mutation":
    path = package / "platform-openapi.json"
    value = load(path)
    api_path = sorted(value["paths"])[0]
    method = sorted(value["paths"][api_path])[0]
    del value["paths"][api_path][method]
    save(path, value)
elif case_name == "source_trace_mutation":
    path = package / "source-traceability-manifest.json"
    value = load(path)
    value["rfp_requirements"][0]["physical_pages"] = [9]
    save(path, value)
elif case_name == "new_contract_mutation":
    path = package / "normative-test-semantics.json"
    value = load(path)
    value["tests"][0]["test_id"] = "T-UNKNOWN-999"
    save(path, value)
elif case_name == "release_state_rule":
    path = package / "design-baseline.json"
    value = load(path)
    value["recovery_objectives"]["release_state_ceiling_before_acceptance"] = "ACCEPTED"
    save(path, value)
elif case_name == "final_output_root":
    path = package / "design-baseline.json"
    value = load(path)
    value["artifact_roots"]["manuals"] = "docs/manuals/"
    save(path, value)
elif case_name == "runbook_inventory":
    path = package / "14-final-document-deliverables.md"
    lines = path.read_text(encoding="utf-8").splitlines()
    path.write_text("\n".join(line for line in lines if not line.startswith("| RB-023 |")) + "\n", encoding="utf-8")
elif case_name == "manual_pdf_pair":
    path = package / "14-final-document-deliverables.md"
    text = path.read_text(encoding="utf-8")
    text = text.replace("`quick-start.pdf`", "`quick-start-accessible.pdf`", 1)
    path.write_text(text, encoding="utf-8")
elif case_name == "invalid_json":
    path = package / "document-graph.schema.json"
    path.write_text('{"broken":\n', encoding="utf-8")
elif case_name == "model_schema_unsupported_keyword":
    path = package / "codex-output.schema.json"
    value = load(path)
    value["oneOf"] = []
    save(path, value)
elif case_name in {"model_schema_additional_properties", "model_schema_required_properties"}:
    path = package / "codex-output.schema.json"
    value = load(path)

    def find_nested_object(node, is_root=True):
        if isinstance(node, dict):
            if not is_root and node.get("type") == "object" and isinstance(node.get("properties"), dict) and node["properties"]:
                return node
            for child in node.values():
                found = find_nested_object(child, False)
                if found is not None:
                    return found
        elif isinstance(node, list):
            for child in node:
                found = find_nested_object(child, False)
                if found is not None:
                    return found
        return None

    target = find_nested_object(value)
    if target is None:
        raise SystemExit("model-facing schema has no nested object fixture")
    if case_name == "model_schema_additional_properties":
        target["additionalProperties"] = True
    else:
        required = target.get("required")
        if not isinstance(required, list) or not required:
            raise SystemExit("nested object fixture has no required properties")
        target["required"] = required[:-1]
    save(path, value)
elif case_name == "inventory_entry_removal":
    path = package / "final-document-inventory.json"
    value = load(path)
    if not isinstance(value.get("artifacts"), list) or not value["artifacts"]:
        raise SystemExit("final document inventory has no artifact fixture")
    value["artifacts"].pop()
    save(path, value)
elif case_name == "inventory_unsafe_placeholder":
    path = package / "final-document-inventory.json"
    value = load(path)
    for artifact in value.get("artifacts", []):
        template = artifact.get("relative_path_template", "")
        if "${release_id}" in template:
            artifact["relative_path_template"] = template.replace("${release_id}", "${HOME}", 1)
            break
    else:
        raise SystemExit("final document inventory has no release placeholder fixture")
    save(path, value)
elif case_name == "inventory_duplicate_path":
    path = package / "final-document-inventory.json"
    value = load(path)
    artifacts = value.get("artifacts", [])
    if len(artifacts) < 2:
        raise SystemExit("final document inventory has fewer than two artifact fixtures")
    artifacts[1]["root_id"] = artifacts[0]["root_id"]
    artifacts[1]["root_path"] = artifacts[0]["root_path"]
    artifacts[1]["relative_path_template"] = artifacts[0]["relative_path_template"]
    save(path, value)
elif case_name == "inventory_embedded_placeholder":
    path = package / "final-document-inventory.json"
    value = load(path)
    for artifact in value.get("artifacts", []):
        template = artifact.get("relative_path_template", "")
        if template.startswith("${release_id}/"):
            artifact["relative_path_template"] = template.replace("${release_id}", "x${release_id}y", 1)
            break
    else:
        raise SystemExit("final document inventory has no release placeholder fixture")
    save(path, value)
elif case_name == "inventory_admin_sources":
    path = package / "final-document-inventory.json"
    value = load(path)
    sources = value.get("manual_combination_contract", {}).get("administrator_guide_sources", [])
    if len(sources) < 2:
        raise SystemExit("administrator guide source fixture is incomplete")
    sources[1] = sources[0]
    save(path, value)
elif case_name == "inventory_distribution_manual":
    path = package / "final-document-inventory.json"
    value = load(path)
    for artifact in value.get("artifacts", []):
        if artifact.get("artifact_id") == "FDI-DST-MAN-008":
            artifact["relative_path_template"] = "${release_id}/manuals/quick-start-copy.pdf"
            break
    else:
        raise SystemExit("distribution manual fixture is missing")
    save(path, value)
elif case_name == "inventory_media_contract":
    path = package / "final-document-inventory.json"
    value = load(path)
    if not value.get("artifacts"):
        raise SystemExit("final document inventory has no media fixture")
    value["artifacts"][0]["media_type"] = "application/octet-stream"
    save(path, value)
elif case_name == "machine_registry_contract":
    path = package / "requirements-test-registry.json"
    value = load(path)
    if not isinstance(value.get("system_requirements"), list) or not value["system_requirements"]:
        raise SystemExit("requirements registry has no system requirement fixture")
    value["system_requirements"][0]["test_ids"] = ["T-UNKNOWN-999"]
    save(path, value)
elif case_name == "screen_authorization_wildcard":
    path = package / "screen-route-contracts.json"
    value = load(path)
    if not isinstance(value.get("screens"), list) or not value["screens"]:
        raise SystemExit("screen registry has no authorization fixture")
    value["screens"][0]["allowed_roles"][0] = "SUPERUSER"
    value["screens"][0]["tenant_guard"] = "ALLOW_ALL"
    save(path, value)
elif case_name == "requirement_api_nonexistent":
    path = package / "requirements-test-registry.json"
    value = load(path)
    requirements = [
        *value.get("rfp_requirements", []),
        *value.get("system_requirements", []),
    ]
    for requirement in requirements:
        if requirement.get("api_operation_ids"):
            requirement["api_operation_ids"][0] = "GET /api/v1/nonexistent-contract"
            break
    else:
        raise SystemExit("requirements registry has no API operation fixture")
    save(path, value)
elif case_name == "inventory_canonical_path":
    path = package / "final-document-inventory.json"
    value = load(path)
    if not isinstance(value.get("artifacts"), list) or not value["artifacts"]:
        raise SystemExit("final document inventory has no canonical path fixture")
    value["artifacts"][0]["relative_path_template"] = "fake-design.md"
    save(path, value)
elif case_name == "document_graph_core_bound":
    path = package / "document-graph.schema.json"
    value = load(path)
    value["$defs"]["normalizedBoundingBox"]["properties"]["x1_microunit"]["maximum"] = 1
    save(path, value)
elif case_name == "artifact_files_minimum":
    path = package / "artifact-manifest.schema.json"
    value = load(path)
    value["properties"]["files"]["minItems"] = 0
    save(path, value)
elif case_name == "machine_validator_missing":
    (package / "verify-machine-contracts.py").unlink()
elif case_name == "runtime_contract":
    (root / "repo-overlay/scripts/validate-codex-final-result.ps1").unlink()
elif case_name == "bootstrap_hash_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    if "$entry.sha256" not in text:
        raise SystemExit("bootstrap has no manifest hash fixture")
    path.write_text(text.replace("$entry.sha256", "$entry.missing_sha256", 1), encoding="utf-8")
elif case_name == "bootstrap_acl_owner_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "$ownerSid = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value"
    start = text.index("function Assert-NonBroadWritablePathChain")
    end = text.index("function Resolve-TrustedExecutable", start)
    block = text[start:end]
    if block.count(needle) != 1:
        raise SystemExit("bootstrap executable-chain function has no exact ACL owner fixture")
    block = block.replace(needle, '$ownerSid = "S-1-5-18"', 1)
    path.write_text(text[:start] + block + text[end:], encoding="utf-8")
elif case_name == "bootstrap_acl_boundary_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "if ([StringComparer]::OrdinalIgnoreCase.Equals($current, $allowedRoot)) { $insideAllowedRoot = $false }"
    if text.count(needle) != 1:
        raise SystemExit("bootstrap has no exact ACL boundary fixture")
    path.write_text(text.replace(needle, "if ([StringComparer]::OrdinalIgnoreCase.Equals($current, $allowedRoot)) { $insideAllowedRoot = $true }", 1), encoding="utf-8")
elif case_name == "bootstrap_durable_backup_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "Copy-DurableFileData -Source $change.Destination -Destination $backup -CreateNew"
    if text.count(needle) != 1:
        raise SystemExit("bootstrap has no exact durable backup fixture")
    path.write_text(text.replace(needle, "Copy-Item -LiteralPath $change.Destination -Destination $backup -Force", 1), encoding="utf-8")
elif case_name == "bootstrap_durable_install_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "Flush-DurableFileData -Path $change.Destination"
    if text.count(needle) != 1:
        raise SystemExit("bootstrap has no exact durable installed-file fixture")
    path.write_text(text.replace(needle, "# installed file flush removed", 1), encoding="utf-8")
elif case_name == "python_isolation_contract":
    path = package / "verify-design-package.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "& $PythonCommand -I -S -B $Checker"
    if text.count(needle) != 1:
        raise SystemExit("PowerShell verifier must contain one isolated invocation fixture")
    path.write_text(text.replace(needle, "& $PythonCommand $Checker", 1), encoding="utf-8")
elif case_name == "bootstrap_trust_chain_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "Assert-BootstrapTrustPathChain -Path $Path"
    if text.count(needle) != 2:
        raise SystemExit("bootstrap must contain pre/post release-trust chain fixtures")
    path.write_text(text.replace(needle, 'Assert-NoReparseAncestor -Path $Path -Code "PRE-TRUST"', 1), encoding="utf-8")
elif case_name == "python_working_directory_contract":
    path = package / "verify-design-package.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "Push-Location -LiteralPath (Split-Path -Parent $PythonCommand)"
    if text.count(needle) != 1:
        raise SystemExit("PowerShell verifier must contain one protected Python working-directory fixture")
    path.write_text(text.replace(needle, "Push-Location -LiteralPath $PWD", 1), encoding="utf-8")
elif case_name == "git_working_directory_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "Push-Location -LiteralPath (Split-Path -Parent $script:TrustedGitCommand)"
    if text.count(needle) != 1:
        raise SystemExit("bootstrap must contain one protected Git working-directory fixture")
    path.write_text(text.replace(needle, "Push-Location -LiteralPath $resolvedRoot", 1), encoding="utf-8")
elif case_name == "bootstrap_host_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "\nAssert-CanonicalBootstrapHost\n"
    if text.count(needle) != 1:
        raise SystemExit("bootstrap must invoke one canonical host preflight")
    path.write_text(text.replace(needle, "\n# canonical host preflight removed\n", 1), encoding="utf-8")
elif case_name == "python_runtime_closure_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "Assert-TrustedPythonRuntimeClosure -PythonPath $python"
    if text.count(needle) != 1:
        raise SystemExit("bootstrap must invoke one Python runtime closure preflight")
    path.write_text(text.replace(needle, "# Python runtime closure removed", 1), encoding="utf-8")
elif case_name == "runner_spawn_host_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "& ([string]$bootstrapTrust.PowerShell) @runnerArguments"
    if text.count(needle) != 1:
        raise SystemExit("bootstrap must spawn runner once under pinned PowerShell")
    path.write_text(text.replace(needle, "& $runner -ProjectRoot $resolvedRoot", 1), encoding="utf-8")
elif case_name == "bootstrap_retry_guidance_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "$bootstrapCommandPrefix = \"& '$([string]$bootstrapTrust.PowerShell)' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File"
    if text.count(needle) != 1:
        raise SystemExit("bootstrap must contain one canonical retry guidance fixture")
    path.write_text(text.replace(needle, '$bootstrapCommandPrefix = "powershell -ExecutionPolicy Bypass -File', 1), encoding="utf-8")
elif case_name == "runner_resume_guidance_contract":
    path = root / "repo-overlay/scripts/invoke-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "$CanonicalRunnerHost = \"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\""
    if text.count(needle) != 1:
        raise SystemExit("runner must contain one canonical resume host fixture")
    path.write_text(text.replace(needle, '$CanonicalRunnerHost = "powershell"', 1), encoding="utf-8")
elif case_name == "bootstrap_environment_guard_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "\nAssert-NoBootstrapExecutionEnvironmentOverrides\n"
    if text.count(needle) != 1:
        raise SystemExit("bootstrap must invoke one environment override guard")
    path.write_text(text.replace(needle, "\n# environment guard removed\n", 1), encoding="utf-8")
elif case_name == "runner_environment_cleanup_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = 'foreach ($bootstrapGitEnvironmentName in @("GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL", "GIT_TERMINAL_PROMPT", "GCM_INTERACTIVE"))'
    if text.count(needle) != 1:
        raise SystemExit("bootstrap must contain one child environment cleanup fixture")
    path.write_text(text.replace(needle, "foreach ($bootstrapGitEnvironmentName in @())", 1), encoding="utf-8")
elif case_name == "trust_template_contract":
    path = package / "release-trust.example.json"
    value = load(path)
    value["trusted_tools"]["python"]["authenticode_required"] = False
    value["trusted_tools"]["python"]["authenticode_signer_thumbprint"] = None
    save(path, value)
elif case_name == "trust_template_labels_contract":
    path = package / "release-trust.example.json"
    value = load(path)
    for workflow in value["github_policy"]["workflows"]:
        if workflow["check_name"] == "design-package-windows":
            workflow["required_runner_labels"] = ["Windows", "X64"]
    save(path, value)
elif case_name == "bootstrap_strict_json_contract":
    path = root / "start-ai-training-platform-v1.ps1"
    text = path.read_text(encoding="utf-8")
    needle = "ConvertFrom-StrictBootstrapJsonFile -Path $Path"
    if text.count(needle) != 1:
        raise SystemExit("bootstrap must contain one strict trust parser invocation")
    path.write_text(text.replace(needle, 'Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json', 1), encoding="utf-8")
elif case_name == "manifest_contract":
    path = root / "overlay-manifest.json"
    value = load(path)
    value["files"] = [entry for entry in value["files"] if entry["source"] != "yonlab-ai-training-platform-design/normative-test-semantics.json"]
    save(path, value)
elif case_name == "manifest_hash":
    path = root / "overlay-manifest.json"
    value = load(path)
    if not value.get("files"):
        raise SystemExit("overlay manifest has no file entry fixture")
    value["files"][0]["sha256"] = "0" * 64
    save(path, value)
elif case_name == "manifest_destination":
    path = root / "overlay-manifest.json"
    value = load(path)
    if not value.get("files"):
        raise SystemExit("overlay manifest has no file entry fixture")
    value["files"][0]["destination"] = "docs/planning/wrong-ai-gateway-design.md"
    save(path, value)
elif case_name == "manifest_bytes":
    path = root / "overlay-manifest.json"
    value = load(path)
    if not value.get("files"):
        raise SystemExit("overlay manifest has no file entry fixture")
    value["files"][0]["bytes"] += 1
    save(path, value)
elif case_name == "manifest_mode":
    path = root / "overlay-manifest.json"
    value = load(path)
    if not value.get("files"):
        raise SystemExit("overlay manifest has no file entry fixture")
    value["files"][0]["mode"] = "100755"
    save(path, value)
elif case_name == "manifest_recursive_omission":
    path = root / "overlay-manifest.json"
    value = load(path)
    omitted = "yonlab-ai-training-platform-design/fixtures/document-graph.valid.json"
    value["files"] = [entry for entry in value["files"] if entry["source"] != omitted]
    save(path, value)
elif case_name == "manifest_private_source":
    private_path = root / "reference/private/secret.txt"
    private_path.parent.mkdir(parents=True, exist_ok=True)
    private_path.write_text("must never be distributed\n", encoding="utf-8")
    path = root / "overlay-manifest.json"
    value = load(path)
    value["files"].append({
        "source": "reference/private/secret.txt",
        "destination": "docs/planning/private/secret.txt",
        "sha256": hashlib.sha256(private_path.read_bytes()).hexdigest(),
        "bytes": private_path.stat().st_size,
        "mode": "100644",
    })
    save(path, value)
elif case_name == "manifest_package_only":
    source_path = package / "verify-design-package.sh"
    path = root / "overlay-manifest.json"
    value = load(path)
    value["files"].append({
        "source": "yonlab-ai-training-platform-design/verify-design-package.sh",
        "destination": "docs/planning/ai-training-platform-v1/verify-design-package.sh",
        "sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
        "bytes": source_path.stat().st_size,
        "mode": "100644",
    })
    save(path, value)
elif case_name == "package_nested_private":
    path = package / "reference/private/secret.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("private source must never be canonicalized\n", encoding="utf-8")
elif case_name == "windows_reserved_path":
    (package / "CON.txt").write_text("reserved\n", encoding="utf-8")
elif case_name == "windows_ads_path":
    (package / "stream:ads.txt").write_text("ads\n", encoding="utf-8")
elif case_name == "windows_case_collision":
    (package / "Foo.txt").write_text("upper\n", encoding="utf-8")
    (package / "foo.txt").write_text("lower\n", encoding="utf-8")
elif case_name == "cache_case":
    path = package / "__PYCACHE__/cache.PYC"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"cache")
elif case_name == "package_artifacts_case":
    path = package / ".ArTiFaCtS/generated.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('{"generated":true}\n', encoding="utf-8")
elif case_name == "repo_overlay_duplicate_json":
    path = root / "repo-overlay/contracts/ambiguous.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('{"owner":"trusted","OWNER":"shadow"}\n', encoding="utf-8")
elif case_name == "shell_mode":
    path = root / "repo-overlay/scripts/tests/test-invoke-ai-training-platform-v1.sh"
    path.chmod(path.stat().st_mode & ~0o111)
else:
    raise SystemExit(f"unknown mutation: {case_name}")

# Keep non-manifest semantic mutations fully canonical at the overlay layer so
# they are rejected by their owning semantic gate rather than a stale digest.
if not case_name.startswith("manifest_"):
    completed = subprocess.run(
        [sys.executable, str(root / "generate-overlay-manifest.py"), "--root", str(root), "--write"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    generator_rejection_cases = {
        "runtime_contract", "invalid_json", "package_nested_private", "windows_reserved_path",
        "windows_ads_path", "windows_case_collision", "cache_case",
        "package_artifacts_case", "repo_overlay_duplicate_json",
    }
    if completed.returncode != 0 and case_name not in generator_rejection_cases:
        raise SystemExit(f"cannot canonicalize semantic mutation {case_name}: {completed.stderr}")
PY
}

history_branch_count="$(grep -Ec '^elif case_name == "history_mutation":$' "$PACKAGE_ROOT/test-verify-design-package.sh" || true)"
if [[ "$history_branch_count" = 1 ]]; then
  pass "history mutation has exactly one reachable mutation branch"
else
  fail "history mutation must have exactly one reachable mutation branch; found $history_branch_count"
fi

baseline_fixture="$(copy_fixture baseline)"
baseline_output="$TMP_ROOT/baseline.out"
baseline_manifest_before="$TMP_ROOT/overlay-manifest.before.json"
cp -a "$baseline_fixture/overlay-manifest.json" "$baseline_manifest_before"
if python3 "$baseline_fixture/generate-overlay-manifest.py" --root "$baseline_fixture" --write >/dev/null 2>&1 &&
   cmp -s "$baseline_manifest_before" "$baseline_fixture/overlay-manifest.json"; then
  pass "overlay manifest regeneration is byte-for-byte deterministic"
else
  fail "overlay manifest regeneration must be byte-for-byte deterministic"
fi
if run_bash_verifier "$baseline_fixture" "$baseline_output" && result_line_is PASS "$baseline_output"; then
  pass "baseline package accepted by Bash verifier"
else
  sed -n '1,160p' "$baseline_output" >&2
  fail "baseline package must produce exactly one terminal RESULT: PASS"
fi

mutation_cases=(
  canonical_path
  kpi_minimum
  persona_count
  required_document
  broken_link
  duplicate_document_id
  unsafe_codex_invocation
  history_mutation
  runner_early_exit
  runner_helper_reset
  runner_second_codex
  completeness_contract_mutation
  source_trace_mutation
  new_contract_mutation
  release_state_rule
  final_output_root
  runbook_inventory
  manual_pdf_pair
  invalid_json
  model_schema_unsupported_keyword
  model_schema_additional_properties
  model_schema_required_properties
  inventory_entry_removal
  inventory_unsafe_placeholder
  inventory_duplicate_path
  inventory_embedded_placeholder
  inventory_admin_sources
  inventory_distribution_manual
  inventory_media_contract
  machine_registry_contract
  screen_authorization_wildcard
  requirement_api_nonexistent
  inventory_canonical_path
  document_graph_core_bound
  artifact_files_minimum
  machine_validator_missing
  runtime_contract
  bootstrap_hash_contract
  bootstrap_acl_owner_contract
  bootstrap_acl_boundary_contract
  bootstrap_durable_backup_contract
  bootstrap_durable_install_contract
  python_isolation_contract
  bootstrap_trust_chain_contract
  python_working_directory_contract
  git_working_directory_contract
  bootstrap_host_contract
  python_runtime_closure_contract
  runner_spawn_host_contract
  bootstrap_retry_guidance_contract
  runner_resume_guidance_contract
  bootstrap_environment_guard_contract
  runner_environment_cleanup_contract
  trust_template_contract
  trust_template_labels_contract
  bootstrap_strict_json_contract
  manifest_contract
  manifest_hash
  manifest_destination
  manifest_bytes
  manifest_mode
  manifest_recursive_omission
  manifest_private_source
  manifest_package_only
  package_nested_private
  windows_reserved_path
  windows_ads_path
  windows_case_collision
  cache_case
  package_artifacts_case
  repo_overlay_duplicate_json
  shell_mode
)

declare -A expected_failure_codes=(
  [canonical_path]=CANONICAL_COORDINATES
  [kpi_minimum]=KPI_THRESHOLDS
  [persona_count]=PERSONA_HIERARCHY
  [required_document]=CANONICAL_FILES
  [broken_link]=MARKDOWN_STRUCTURE
  [duplicate_document_id]=DOCUMENT_IDS
  [unsafe_codex_invocation]=ACTIVE_SAFETY
  [history_mutation]=ACTIVE_SAFETY
  [runner_early_exit]=RUNTIME_CONTRACT
  [runner_helper_reset]=ACTIVE_SAFETY
  [runner_second_codex]=ACTIVE_SAFETY
  [completeness_contract_mutation]=COMPLETENESS_CONTRACTS
  [source_trace_mutation]=SOURCE_TRACEABILITY
  [new_contract_mutation]=MACHINE_CONTRACTS
  [release_state_rule]=RELEASE_STATES
  [final_output_root]=FINAL_OUTPUT_ROOTS
  [runbook_inventory]=RUNBOOK_INVENTORY
  [manual_pdf_pair]=MANUAL_PAIRS
  [invalid_json]=JSON_PARSE
  [model_schema_unsupported_keyword]=MODEL_OUTPUT_SCHEMA
  [model_schema_additional_properties]=MODEL_OUTPUT_SCHEMA
  [model_schema_required_properties]=MODEL_OUTPUT_SCHEMA
  [inventory_entry_removal]=MACHINE_CONTRACTS
  [inventory_unsafe_placeholder]=MACHINE_CONTRACTS
  [inventory_duplicate_path]=MACHINE_CONTRACTS
  [inventory_embedded_placeholder]=MACHINE_CONTRACTS
  [inventory_admin_sources]=MACHINE_CONTRACTS
  [inventory_distribution_manual]=MACHINE_CONTRACTS
  [inventory_media_contract]=MACHINE_CONTRACTS
  [machine_registry_contract]=MACHINE_CONTRACTS
  [screen_authorization_wildcard]=MACHINE_CONTRACTS
  [requirement_api_nonexistent]=MACHINE_CONTRACTS
  [inventory_canonical_path]=MACHINE_CONTRACTS
  [document_graph_core_bound]=MACHINE_CONTRACTS
  [artifact_files_minimum]=MACHINE_CONTRACTS
  [machine_validator_missing]=MACHINE_CONTRACTS
  [runtime_contract]=RUNTIME_CONTRACT
  [bootstrap_hash_contract]=RUNTIME_CONTRACT
  [bootstrap_acl_owner_contract]=RUNTIME_CONTRACT
  [bootstrap_acl_boundary_contract]=RUNTIME_CONTRACT
  [bootstrap_durable_backup_contract]=RUNTIME_CONTRACT
  [bootstrap_durable_install_contract]=RUNTIME_CONTRACT
  [python_isolation_contract]=RUNTIME_CONTRACT
  [bootstrap_trust_chain_contract]=RUNTIME_CONTRACT
  [python_working_directory_contract]=RUNTIME_CONTRACT
  [git_working_directory_contract]=RUNTIME_CONTRACT
  [bootstrap_host_contract]=RUNTIME_CONTRACT
  [python_runtime_closure_contract]=RUNTIME_CONTRACT
  [runner_spawn_host_contract]=RUNTIME_CONTRACT
  [bootstrap_retry_guidance_contract]=RUNTIME_CONTRACT
  [runner_resume_guidance_contract]=RUNTIME_CONTRACT
  [bootstrap_environment_guard_contract]=RUNTIME_CONTRACT
  [runner_environment_cleanup_contract]=RUNTIME_CONTRACT
  [trust_template_contract]=RUNTIME_CONTRACT
  [trust_template_labels_contract]=RUNTIME_CONTRACT
  [bootstrap_strict_json_contract]=RUNTIME_CONTRACT
  [manifest_contract]=RUNTIME_CONTRACT
  [manifest_hash]=RUNTIME_CONTRACT
  [manifest_destination]=RUNTIME_CONTRACT
  [manifest_bytes]=RUNTIME_CONTRACT
  [manifest_mode]=RUNTIME_CONTRACT
  [manifest_recursive_omission]=RUNTIME_CONTRACT
  [manifest_private_source]=RUNTIME_CONTRACT
  [manifest_package_only]=RUNTIME_CONTRACT
  [package_nested_private]=RUNTIME_CONTRACT
  [windows_reserved_path]=RUNTIME_CONTRACT
  [windows_ads_path]=RUNTIME_CONTRACT
  [windows_case_collision]=RUNTIME_CONTRACT
  [cache_case]=RUNTIME_CONTRACT
  [package_artifacts_case]=RUNTIME_CONTRACT
  [repo_overlay_duplicate_json]=RUNTIME_CONTRACT
  [shell_mode]=SHELL_MODES
)

for case_name in "${mutation_cases[@]}"; do
  fixture="$(copy_fixture "$case_name")"
  mutate_fixture "$case_name" "$fixture"
  output="$TMP_ROOT/$case_name.out"
  expected_code="${expected_failure_codes[$case_name]}"
  if run_bash_verifier "$fixture" "$output"; then
    fail "$case_name mutation was accepted by Bash verifier"
  elif result_line_is FAIL "$output" && grep -Fq -- "FAIL [$expected_code]:" "$output"; then
    pass "$case_name mutation rejected fail-closed by Bash verifier"
  else
    sed -n '1,120p' "$output" >&2
    fail "$case_name rejection must end with exactly one RESULT: FAIL"
  fi

  ps_mutation_output="$TMP_ROOT/$case_name.powershell.out"
  if run_powershell_verifier "$fixture" "$ps_mutation_output"; then
    fail "$case_name mutation was accepted by PowerShell verifier"
  else
    ps_mutation_code=$?
    if [[ "$ps_mutation_code" = 125 ]]; then
      powershell_runtime_blocked=1
    elif result_line_is FAIL "$ps_mutation_output" && grep -Fq -- "FAIL [$expected_code]:" "$ps_mutation_output"; then
      pass "$case_name mutation rejected fail-closed by PowerShell verifier"
    else
      sed -n '1,120p' "$ps_mutation_output" >&2
      fail "$case_name PowerShell rejection must end with exactly one RESULT: FAIL"
    fi
  fi
done

PS_VERIFIER="$PACKAGE_ROOT/verify-design-package.ps1"
if [[ ! -s "$PS_VERIFIER" ]]; then
  fail "PowerShell parity verifier is missing"
else
  contract_failure_count="$failures"
  policy_marker='OVERLAY_POLICY_V2_RECURSIVE_EXACT'
  policy_generator="$WORK_ROOT/generate-overlay-manifest.py"
  for parity_source in "$PACKAGE_ROOT/verify-design-package.sh" "$PS_VERIFIER" "$policy_generator"; do
    grep -Fq -- "$policy_marker" "$parity_source" || fail "overlay policy parity marker missing: $parity_source"
  done
  for parity_verifier in "$PACKAGE_ROOT/verify-design-package.sh" "$PS_VERIFIER"; do
    grep -Fq -- 'generate-overlay-manifest.py' "$parity_verifier" || fail "shared dynamic overlay generator is not invoked: $parity_verifier"
    grep -Fq -- '--check' "$parity_verifier" || fail "shared dynamic overlay generator is not invoked in check mode: $parity_verifier"
  done
  parity_ids=(
    CANONICAL_FILES JSON_PARSE REQUIREMENT_COUNTS DOCUMENT_IDS MARKDOWN_STRUCTURE
    CANONICAL_COORDINATES KPI_THRESHOLDS PERSONA_HIERARCHY DATA_POLICY RELEASE_STATES
    FINAL_OUTPUT_ROOTS RUNBOOK_INVENTORY MANUAL_PAIRS RUNTIME_CONTRACT ACTIVE_SAFETY
    SHELL_MODES MODEL_OUTPUT_SCHEMA FINAL_DOCUMENT_INVENTORY MACHINE_CONTRACTS
    COMPLETENESS_CONTRACTS SOURCE_TRACEABILITY NORMATIVE_TEST_SEMANTICS
    SEMANTIC_DEPTH_CONTRACTS AI_GATEWAY_SAFEGUARDING TCH_015_AUTHORIZATION
  )
  for parity_id in "${parity_ids[@]}"; do
    grep -Fq -- "\"$parity_id\"" "$PS_VERIFIER" || fail "PowerShell parity marker missing: $parity_id"
  done
  for token in \
    'OVERLAY_POLICY_V2_RECURSIVE_EXACT' \
    'D:\Views\yonlab-inuri-site' \
    'https://github.com/yubi-lee/yonlab-i-nuri-site.git' \
    'feat/ai-training-platform-v1' \
    'CODE_COMPLETE / ACCEPTANCE DATA PENDING' \
    'REQUIRES_ACCEPTANCE_DATA' \
    'sha256' \
    'RESULT: PASS' \
    'RESULT: FAIL'; do
    grep -Fq -- "$token" "$PS_VERIFIER" || fail "PowerShell core invariant missing: $token"
  done
  if [[ "$failures" = "$contract_failure_count" ]]; then
    pass "PowerShell verifier declares the shared core invariant contract"
  fi
fi

if [[ -s "$PS_VERIFIER" ]]; then
  ps_output="$TMP_ROOT/powershell-baseline.out"
  if run_powershell_verifier "$baseline_fixture" "$ps_output"; then
    if result_line_is PASS "$ps_output"; then
      pass "baseline package accepted by PowerShell verifier"
    else
      sed -n '1,160p' "$ps_output" >&2
      fail "PowerShell baseline result is not deterministic"
    fi
  else
    ps_code=$?
    if [[ "$ps_code" = 125 ]]; then
      powershell_runtime_blocked=1
      printf 'BLOCKED: PowerShell runtime unavailable; behavioral parity was not executed.\n'
    else
      sed -n '1,160p' "$ps_output" >&2
      fail "PowerShell verifier rejected the baseline package"
    fi
  fi
fi

hostile_python_site="$TMP_ROOT/hostile-python-site"
mkdir -p "$hostile_python_site"
printf '%s\n' 'import os; os._exit(97)' >"$hostile_python_site/sitecustomize.py"
hostile_bash_output="$TMP_ROOT/hostile-python-bash.out"
if PYTHONPATH="$hostile_python_site" run_bash_verifier "$baseline_fixture" "$hostile_bash_output" && result_line_is PASS "$hostile_bash_output"; then
  pass "Bash verifier ignores hostile ambient PYTHONPATH/sitecustomize"
else
  sed -n '1,160p' "$hostile_bash_output" >&2
  fail "Bash verifier must isolate all Python gates from ambient sitecustomize"
fi
hostile_ps_output="$TMP_ROOT/hostile-python-powershell.out"
if PYTHONPATH="$hostile_python_site" run_powershell_verifier "$baseline_fixture" "$hostile_ps_output"; then
  if result_line_is PASS "$hostile_ps_output"; then
    pass "PowerShell verifier ignores hostile ambient PYTHONPATH/sitecustomize"
  else
    sed -n '1,160p' "$hostile_ps_output" >&2
    fail "PowerShell verifier isolation result is not deterministic"
  fi
else
  hostile_ps_code=$?
  if [[ "$hostile_ps_code" = 125 ]]; then
    powershell_runtime_blocked=1
  else
    sed -n '1,160p' "$hostile_ps_output" >&2
    fail "PowerShell verifier must isolate all Python gates from ambient sitecustomize"
  fi
fi

bootstrap_policy_output="$TMP_ROOT/overlay-bootstrap-policy.out"
if run_overlay_bootstrap_test "$baseline_fixture" "$bootstrap_policy_output"; then
  if grep -Fq -- 'PASS: overlay bootstrap rejects a reparse ancestor' "$bootstrap_policy_output" && tail -n 1 "$bootstrap_policy_output" | grep -Fxq 'RESULT: PASS'; then
    pass "overlay bootstrap reparse policy executes against a real junction/symlink fixture"
  else
    sed -n '1,160p' "$bootstrap_policy_output" >&2
    fail "overlay bootstrap policy test must produce terminal RESULT: PASS"
  fi
else
  bootstrap_policy_code=$?
  if [[ "$bootstrap_policy_code" = 125 ]]; then
    powershell_runtime_blocked=1
  else
    sed -n '1,160p' "$bootstrap_policy_output" >&2
    fail "overlay bootstrap policy test failed"
  fi
fi

runner_suite_output="$TMP_ROOT/runner-suite.out"
runner_suite="$baseline_fixture/repo-overlay/scripts/tests/test-invoke-ai-training-platform-v1.sh"
runner_path_prefix=""
if [[ -n "${PWSH_BIN:-}" && -x "${PWSH_BIN}" ]]; then
  runner_path_prefix="$(dirname "${PWSH_BIN}")"
fi
if [[ -n "$runner_path_prefix" ]]; then
  PATH="$runner_path_prefix:$PATH" PWSH_BIN="${PWSH_BIN}" bash "$runner_suite" >"$runner_suite_output" 2>&1
  runner_suite_code=$?
else
  bash "$runner_suite" >"$runner_suite_output" 2>&1
  runner_suite_code=$?
fi
if [[ "$runner_suite_code" = 0 ]] && grep -Fq -- 'PASS: guarded runner, validator, process, and executable adversarial contracts' "$runner_suite_output"; then
  pass "guarded runner, validator, UTF-8 process, policy fixtures, and PowerShell AST suite execute"
elif [[ "$runner_suite_code" = 3 ]]; then
  powershell_runtime_blocked=1
  printf 'BLOCKED: guarded runner behavioral suite requires PowerShell.\n'
else
  sed -n '1,240p' "$runner_suite_output" >&2
  fail "guarded runner behavioral suite failed"
fi

ajv_output="$TMP_ROOT/ajv-schema.out"
ajv_suite="$baseline_fixture/repo-overlay/scripts/tests/test-codex-final-result-schema-ajv.sh"
if command -v npm >/dev/null 2>&1; then
  if bash "$ajv_suite" >"$ajv_output" 2>&1 && grep -Fq -- 'PASS: AJV fail-closed Codex result schema fixtures' "$ajv_output"; then
    pass "AJV strict final-result positive/negative fixtures execute"
  else
    sed -n '1,240p' "$ajv_output" >&2
    fail "AJV final-result schema suite failed"
  fi
else
  powershell_runtime_blocked=1
  printf 'BLOCKED: npm is unavailable; AJV schema fixtures were not executed.\n'
fi

if ((failures > 0)); then
  printf 'RESULT: FAIL (%d passed, %d failed)\n' "$passes" "$failures" >&2
  exit 1
fi

if ((powershell_runtime_blocked > 0)); then
  printf 'RESULT: BLOCKED (PowerShell runtime unavailable; parity was not executed)\n' >&2
  exit 3
fi

printf 'RESULT: PASS (%d checks)\n' "$passes"
