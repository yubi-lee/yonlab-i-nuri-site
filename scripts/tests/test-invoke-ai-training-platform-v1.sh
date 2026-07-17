#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLED_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[
  -s "$INSTALLED_ROOT/scripts/invoke-ai-training-platform-v1.ps1" &&
  -s "$INSTALLED_ROOT/scripts/validate-codex-final-result.ps1" &&
  -s "$INSTALLED_ROOT/docs/planning/ai-training-platform-v1/codex-final-result.schema.json" &&
  -s "$INSTALLED_ROOT/docs/planning/ai-training-platform-v1/codex-output.schema.json" &&
  -s "$INSTALLED_ROOT/docs/planning/ai-training-platform-v1/release-trust.example.json"
]]; then
  LAYOUT="installed"
  RUNNER="$INSTALLED_ROOT/scripts/invoke-ai-training-platform-v1.ps1"
  VALIDATOR="$INSTALLED_ROOT/scripts/validate-codex-final-result.ps1"
  STRICT_SCHEMA="$INSTALLED_ROOT/docs/planning/ai-training-platform-v1/codex-final-result.schema.json"
  OUTPUT_SCHEMA="$INSTALLED_ROOT/docs/planning/ai-training-platform-v1/codex-output.schema.json"
  TRUST_EXAMPLE="$INSTALLED_ROOT/docs/planning/ai-training-platform-v1/release-trust.example.json"
  TEST_ROOT="$INSTALLED_ROOT/scripts/tests"
elif [[
  -s "$PACKAGE_ROOT/repo-overlay/scripts/invoke-ai-training-platform-v1.ps1" &&
  -s "$PACKAGE_ROOT/repo-overlay/scripts/validate-codex-final-result.ps1" &&
  -s "$PACKAGE_ROOT/yonlab-ai-training-platform-design/codex-final-result.schema.json" &&
  -s "$PACKAGE_ROOT/yonlab-ai-training-platform-design/codex-output.schema.json" &&
  -s "$PACKAGE_ROOT/yonlab-ai-training-platform-design/release-trust.example.json"
]]; then
  LAYOUT="package"
  OVERLAY_ROOT="$PACKAGE_ROOT/repo-overlay"
  RUNNER="$OVERLAY_ROOT/scripts/invoke-ai-training-platform-v1.ps1"
  VALIDATOR="$OVERLAY_ROOT/scripts/validate-codex-final-result.ps1"
  STRICT_SCHEMA="$PACKAGE_ROOT/yonlab-ai-training-platform-design/codex-final-result.schema.json"
  OUTPUT_SCHEMA="$PACKAGE_ROOT/yonlab-ai-training-platform-design/codex-output.schema.json"
  TRUST_EXAMPLE="$PACKAGE_ROOT/yonlab-ai-training-platform-design/release-trust.example.json"
  TEST_ROOT="$OVERLAY_ROOT/scripts/tests"
else
  printf 'FAIL: unable to resolve installed repository or overlay package layout\n' >&2
  exit 1
fi

printf 'INFO: runner contract layout=%s\n' "$LAYOUT"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$1"; }
assert_fixed() { grep -Fq -- "$1" "$RUNNER" || fail "$2"; }
assert_absent() { ! grep -Fq -- "$1" "$RUNNER" || fail "$2"; }

for file in "$RUNNER" "$VALIDATOR" "$STRICT_SCHEMA" "$OUTPUT_SCHEMA" "$TRUST_EXAMPLE"; do
  [[ -s "$file" ]] || fail "required runner contract file missing or empty: $file"
done
pass 'runner contract files exist'

# Canonical repository and mode boundary.
assert_fixed 'D:\Views\yonlab-inuri-site' 'canonical Windows repository root is not fixed'
assert_fixed 'feat/ai-training-platform-v1' 'canonical implementation branch is not fixed'
assert_fixed 'https://github.com/yubi-lee/yonlab-i-nuri-site.git' 'canonical origin is not fixed'
assert_fixed '[ValidateSet("Implement", "VerifyCandidate", "VerifyAccepted", "PolicySelfTest")]' 'four guarded modes are not closed'
assert_fixed 'read-only verification modes do not accept -ResumeRun' 'read-only modes do not reject resume'
assert_fixed 'Invoke-ReadOnlyReleaseVerification $Mode $AttestationBundlePath' 'read-only verification path is not explicit'
assert_fixed 'if ((Snapshot-Digest $before) -cne (Snapshot-Digest $after))' 'read-only worktree closure is missing'
assert_fixed 'Get-GitReferenceSnapshot' 'read-only Git index/ref snapshot is missing'
assert_fixed 'modified the index, HEAD, refs/heads, refs/tags, or packed-refs' 'read-only ref closure is incomplete'
assert_fixed 'Assert-GitControlPlaneSnapshot $ExpectedGitControlPlane' 'read-only Git control-plane closure is missing'
push_guard_line="$(grep -nF 'if ($Mode -ceq "Implement") {' "$RUNNER" | tail -1 | cut -d: -f1)"
push_probe_line="$(grep -nF '$pushProbe = SafeGit ' "$RUNNER" | cut -d: -f1)"
[[ -n "$push_guard_line" && -n "$push_probe_line" && "$push_guard_line" -lt "$push_probe_line" ]] || fail 'push dry-run is not restricted to Implement'
pass 'canonical repository and four-mode boundary'

# Production modes must enter through a direct canonical Windows PowerShell
# host, without profiles or command/encoded-command startup paths.
for token in 'Assert-CanonicalProductionHostInvocation' 'Assert-HostInvocationObservation' '[Environment]::GetCommandLineArgs()' '[Environment]::SystemDirectory' 'WindowsPowerShell\v1.0\powershell.exe' '-NoProfile' '-NonInteractive' 'file_target_matches'; do
  assert_fixed "$token" "canonical production host invocation contract missing: $token"
done
assert_fixed '$hostStartupArgumentsValid' 'host startup switch parser is missing'
assert_fixed '$forbiddenTokens=@(' 'forbidden pre-File switch set is missing'
assert_fixed '-PSConsoleFile' 'PowerShell ISE startup rejection is missing'
assert_fixed '-Version' 'PowerShell version startup rejection is missing'
assert_absent '$expectedPrefix=@(' 'legacy fixed argv prefix remains'
assert_fixed 'if ($Mode -ceq "PolicySelfTest") { Invoke-PolicySelfTest $PolicyFixture; exit 0 }' 'Linux-only policy fixture exception is not explicit'
assert_fixed '$CanonicalRunnerHost = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"' 'resume guidance does not pin the canonical production host'
assert_fixed '$CanonicalRunnerPath = "D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1"' 'resume guidance does not pin the canonical runner path'
assert_fixed "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File '\$CanonicalRunnerPath' -Mode Implement -ResumeRun" 'resume guidance does not preserve the exact production host prefix and Implement mode'
assert_absent "RESUME: powershell -ExecutionPolicy" 'legacy relative resume command remains'
host_guard_line="$(grep -nF 'Assert-CanonicalProductionHostInvocation $Mode $PSCommandPath' "$RUNNER" | cut -d: -f1)"
root_guard_line="$(grep -nF '$literalProjectRoot = $ProjectRoot.TrimEnd' "$RUNNER" | cut -d: -f1)"
[[ -n "$host_guard_line" && -n "$root_guard_line" && "$host_guard_line" -lt "$root_guard_line" ]] || fail 'production host invocation is not the first production-mode guard'
pass 'canonical no-profile non-interactive file host boundary'

# release-trust.v2 and exact seven-tool execution policy.
assert_fixed 'release-trust.v2' 'release trust v2 is not required'
assert_fixed '$requiredNames = @("powershell", "python", "git", "gh", "docker", "codex", "gpg")' 'trusted executable set is not exactly seven tools'
assert_fixed 'Assert-ExactObjectProperties $TrustedTools $requiredNames' 'trusted tool set is not closed'
assert_fixed 'Test-SafeTrustedExecutablePathSyntax' 'safe executable path syntax policy is missing'
assert_fixed 'Assert-NonBroadWritablePathChain' 'executable ACL path-chain validation is missing'
assert_absent 'LOCALAPPDATA' 'user-writable LocalAppData remains an executable trust root'
assert_fixed '$replacementMask=' 'ancestor replacement ACL mask is missing'
assert_fixed '$insideAllowedRoot=$false' 'ACL policy does not switch above the trusted executable anchor'
assert_fixed '[Security.AccessControl.PropagationFlags]::InheritOnly' 'inherit-only ACEs are incorrectly applied to the current ACL object'
assert_fixed '$volumeRoot=[IO.Path]::GetPathRoot($resolved)' 'trusted executable ACL walk does not reach the volume root'
local_root_block="$(sed -n '/^function Get-TrustedExecutableAllowedRoots/,/^}/p' "$RUNNER")"
if grep -Eq '^[[:space:]]*\$candidates=@\(.*LOCALAPPDATA' <<<"$local_root_block"; then
  fail 'raw user-writable LOCALAPPDATA is an allowed executable root'
fi
assert_fixed 'authenticode_required -eq $true' 'conditional Authenticode enforcement is missing'
assert_fixed 'optional Authenticode policy must use null thumbprint' 'optional Authenticode null-thumbprint rule is missing'
assert_fixed 'shell shims are forbidden' 'direct executable policy does not reject cmd/bat shims'
assert_absent 'function Executable' 'ambient PATH executable discovery helper remains'
assert_absent 'Get-Command git' 'Git is discovered from ambient PATH'
assert_fixed "return '!\"' + \$GhCommand.Replace(" 'quoted fixed gh credential helper is missing'
assert_fixed "return '\"' + \$GpgCommand.Replace(" 'quoted fixed gpg.program is missing'
pass 'release-trust.v2 seven-tool hash/ACL/conditional-Authenticode policy'

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
  elif command -v python >/dev/null 2>&1 && python --version >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python)"
  else
    printf 'PLATFORM-BLOCKED: Python 3 is required for runner contract tests\n' >&2
    exit 3
  fi
fi

# Every external root of trust is bounded from its leaf through the canonical
# YOnLab anchor. C:\ProgramData and the volume root are outside this policy.
for token in \
  'Assert-ProtectedRootPathChain' 'Assert-ProtectedPathChainObservation' \
  '$TrustedProtectionOwnerSids' '$ProtectedTrustRoot' 'PROTECTED_CONTENT' \
  'DeleteSubdirectoriesAndFiles' 'ChangePermissions' 'TakeOwnership' \
  'protected trust roots changed during execution'; do
  assert_fixed "$token" "external root-of-trust chain contract missing: $token"
done
assert_fixed 'protected_root=$resolvedRoot' 'protected chain does not record its canonical YOnLab anchor'
assert_fixed 'path chain extends beyond the YOnLab anchor' 'protected chain does not reject nodes above the YOnLab anchor'
assert_fixed 'if ([StringComparer]::OrdinalIgnoreCase.Equals($current,$resolvedRoot)) { $reachedProtectedRoot=$true; break }' 'protected chain does not stop at the YOnLab anchor'
"$PYTHON_BIN" - "$RUNNER" <<'PY'
import re, sys
text=open(sys.argv[1], encoding='utf-8-sig').read()
m=re.search(r'function Get-ProtectedPathChainObservation\(.*?\n}\n\nfunction Assert-ProtectedRootPathChain', text, re.S)
if not m:
    raise SystemExit('FAIL: protected path-chain function is missing')
block=m.group(0)
for forbidden in ('GetPathRoot', 'volumeRoot', 'ANCESTOR_REPLACEMENT'):
    if forbidden in block:
        raise SystemExit(f'FAIL: protected path-chain still inspects volume ancestry: {forbidden}')
print('PASS: protected path-chain is bounded at the YOnLab anchor')
PY
assert_fixed 'Assert-ProtectedRootPathChain $resolvedTrustPath (Split-Path -Parent $resolvedTrustPath) "PRE-TRUST" "release trust"' 'release trust file does not validate its YOnLab-bounded chain'
assert_fixed 'Assert-ProtectedRootPathChain $resolved $resolved' 'hooks/GPG protected roots do not validate their YOnLab-bounded chain'
assert_fixed 'Assert-ProtectedRootPathChain $full $AttestationRoot' 'attestation leaf does not validate root/intermediate/leaf ACLs'
assert_fixed 'Get-ProtectedRootSnapshot' 'protected roots have no byte/ACL snapshot for TOCTOU revalidation'
assert_fixed 'Assert-ProtectedTrustRootsUnchanged' 'protected roots are not revalidated after use'
pass 'external release trust, hooks, GPG, and attestation roots are bounded at the YOnLab anchor and resist TOCTOU'

# Every recursive security traversal must inspect a node before descending.
assert_fixed 'function Get-NoFollowTreeEntries' 'shared no-follow BFS is missing'
assert_fixed '[IO.SearchOption]::TopDirectoryOnly' 'no-follow BFS does not enumerate one level at a time'
assert_fixed 'Get-NoFollowTreeEntries $resolved "PRE-TRUST" "protected GnuPG home"' 'GPG home does not use no-follow BFS'
assert_fixed 'Get-NoFollowTreeEntries $path "GIT-CONTROL"' 'Git control tree does not use no-follow BFS'
assert_fixed 'Get-NoFollowTreeEntries $path "GIT-REFS"' 'Git ref tree does not use no-follow BFS'
assert_fixed 'Get-NoFollowTreeEntries $artifactRoot "POST-ARTIFACT"' 'artifact tree does not use no-follow BFS'
assert_absent '[IO.SearchOption]::AllDirectories' 'unsafe pre-check recursive traversal remains'
pass 'no-follow BFS protects Git, GPG, and artifact subtrees'

# Bounded, resumable process execution.
for token in \
  '$MaxNativeCaptureBytes' '$MaxJsonlBytes' '$MaxJsonlLineBytes' \
  '$MaxNativeSeconds' '$MaxCodexSeconds' 'New-BoundedCaptureStream' \
  'CopyToAsync' 'hard timeout' 'codex-run-manifest.v6' 'run.lock' \
  'Assert-ResumeBindingObservation' 'execution_boundary_inventory_sha256' \
  'Get-TrustedExecutableWorkingDirectory' '$psi.WorkingDirectory = Get-TrustedExecutableWorkingDirectory'; do
  assert_fixed "$token" "bounded/resume contract missing: $token"
done
working_directory_assignments="$(grep -cF '$psi.WorkingDirectory = Get-TrustedExecutableWorkingDirectory' "$RUNNER")"
[[ "$working_directory_assignments" -eq 3 ]] || fail "all three process helpers must pin WorkingDirectory to the executable parent (found $working_directory_assignments)"
assert_fixed 'Assert-TrustedExecutableInventoryUnchanged $trustedToolInventory $releaseTrust.trusted_tools $resolvedRoot' 'trusted tools are not rechecked after Codex'
codex_line="$(grep -nF '$codexExit = Invoke-Utf8Process -Command $codexCommand' "$RUNNER" | cut -d: -f1)"
tool_line="$(grep -nF 'Assert-TrustedExecutableInventoryUnchanged $trustedToolInventory $releaseTrust.trusted_tools $resolvedRoot' "$RUNNER" | awk -F: -v start="$codex_line" '$1 > start {print $1; exit}')"
control_line="$(grep -nF 'Assert-GitControlPlaneSnapshot $gitControlPlaneSnapshot' "$RUNNER" | awk -F: -v start="$codex_line" '$1 > start {print $1; exit}')"
post_git_line="$(grep -nF '$afterHead = SafeGit ' "$RUNNER" | awk -F: -v start="$codex_line" '$1 > start {print $1; exit}')"
[[ -n "$codex_line" && "$tool_line" -eq $((codex_line + 1)) && "$control_line" -eq $((codex_line + 2)) && "$control_line" -lt "$post_git_line" ]] \
  || fail 'tool bytes and Git control plane are not checked immediately after Codex and before post-run Git'
pass 'bounded process, protected executable working directory, exclusive resume, and immediate post-Codex trust recheck'

# Constructible S -> R release identity; R contains only the six final roots.
for token in \
  'Get-ReleaseCandidateIdentity' 'R must have exactly one parent S' \
  'merge-base", "--is-ancestor"' 'S is not the first parent of R' \
  'release_diff_paths' 'implementation_commit' 'release_snapshot_commit' \
  'artifact_source_commit' 'evidence_source_commit' \
  'prohibited self-reference OID or tracked Actions run URL'; do
  assert_fixed "$token" "S/R constructibility contract missing: $token"
done
"$PYTHON_BIN" - "$RUNNER" <<'PY'
import re, sys
text=open(sys.argv[1], encoding='utf-8-sig').read()
m=re.search(r'function Assert-ReleaseIdentityObservation\(.*?\n}\n\nfunction ', text, re.S)
if not m:
    raise SystemExit('FAIL: R allowlist function is missing')
paths=re.findall(r'\$path\.StartsWith\("([^"]+)"', m.group(0))
expected=[
  'docs/design/ai-training-platform/',
  'docs/operations/ai-training-platform/',
  'docs/qa/ai-training-platform/',
  'docs/manuals/ai-training-platform/',
  'docs/releases/ai-training-platform/',
  'dist/docs/',
]
if paths != expected:
    raise SystemExit(f'FAIL: R allowlist differs: {paths!r}')
print('PASS: R diff allowlist is the exact six final roots')
PY
assert_absent 'run_url' 'tracked run_url field remains in the release runner'
assert_absent 'signature-verification-receipt.v1' 'tracked signature receipt remains in the release runner'
assert_absent 'final_commit' 'ambiguous final_commit identity remains in the release runner'
pass 'constructible two-commit S/R identity and self-reference exclusions'

# Exact live GitHub and protected-main workflow binding.
for token in \
  'exactly one open same-repository feature-to-main PR is required' \
  'workflow_id' 'workflow_path' 'workflow_sha256' 'allowed_actor_logins' \
  'Get-GitHubRepositoryFileSha256AtCommit' 'pull_request_base_sha' 'base_workflow_sha256' 'release_workflow_sha256' \
  'required_runner_labels' 'actions/runs/([0-9]+)/job/([0-9]+)' \
  'pull_request' 'github-actions' 'completed' 'success' \
  'trusted workflow id/path/state mismatch'; do
  assert_fixed "$token" "exact GitHub/CI binding missing: $token"
done
assert_fixed 'Assert-ExactRequiredCiInventory' 'exact required CI inventory is not used'
assert_fixed 'if ($trustedWorkflowByCheck.Count -ne $RequiredCiChecks.Count)' 'workflow trust set is not exact'
pass 'exact PR, protected-main workflow, actor, job, and runner-label binding'

# External candidate result, technical approvals, artifact signatures, acceptance, and tag.
for token in \
  'release-attestation-bundle.v2' 'candidate_result_path' 'candidate_result_sha256' \
  'release-approval-subject.v2' 'signed subject is not bound to exact S/R/result' \
  'exactly seven technical approvals are required' \
  'exactly four external artifact signatures are required' \
  'VerifyCandidate' 'CODE_COMPLETE / ACCEPTANCE DATA PENDING' \
  'VerifyAccepted' 'FINAL-ACCEPTANCE' 'ACCEPTED' \
  'release tag must be annotated' 'verify-tag' 'remote tag target/signature verification mismatch'; do
  assert_fixed "$token" "external attestation/release state contract missing: $token"
done
assert_fixed 'Assert-ProtectedPathAcl $literal "EXTERNAL-ATTESTATION" "attestation bundle"' 'external bundle ACL is not verified'
assert_fixed 'Assert-DetachedSignature' 'external detached signature verification is missing'
assert_fixed 'function TrustedGpg([string]$GpgCommand, [string[]]$Arguments = @())' 'direct trusted GPG helper is missing'
assert_fixed '@("--homedir", $ProtectedGpgHome, "--no-options", "--no-auto-key-retrieve", "--no-auto-check-trustdb", "--no-autostart", "--lock-never", "--batch", "--no-tty")' 'direct trusted GPG calls do not disable automatic trustdb checks'
for token in 'Assert-ProtectedGpgVerificationConfiguration' 'gpg.conf' 'no-auto-check-trustdb' 'trustdb.gpg' 'Assert-ProtectedGpgHomeUnchanged'; do
  assert_fixed "$token" "protected read-only GPG contract missing: $token"
done
gpg_snapshot_line="$(grep -nF '$protectedTrustRootsSnapshot=Get-ProtectedTrustRootsSnapshot' "$RUNNER" | cut -d: -f1)"
gpg_version_line="$(grep -nF '$gpgVersion = TrustedGpg ' "$RUNNER" | cut -d: -f1)"
[[ -n "$gpg_snapshot_line" && -n "$gpg_version_line" && "$gpg_snapshot_line" -lt "$gpg_version_line" ]] || fail 'protected GPG snapshot must be captured before the first GPG process'
assert_fixed 'Assert-ProtectedGpgHomeUnchanged $gpgSnapshotBefore $ProtectedGpgHome "POST-GPG"' 'direct GPG calls are not checked for protected-home mutation'
assert_fixed 'Assert-ProtectedGpgHomeUnchanged $tagGpgSnapshot $ProtectedGpgHome "POST-TAG-GPG"' 'Git verify-tag is not checked immediately for protected-home mutation'
pass 'protected GPG config, preprovisioned trustdb, and no-write verification boundary'
assert_fixed 'Get-GitHubApiResponseWithStatus' 'authenticated tag HTTP status lookup is missing'
assert_fixed 'remote tag absence requires an authenticated exact HTTP 404' 'arbitrary gh failure can be mistaken for tag absence'
assert_fixed 'Assert-RemoteTagLookupObservation' 'remote tag lookup policy is not shared with executable fixtures'
assert_absent '$remoteTag.ExitCode -eq 0' 'arbitrary nonzero remote tag lookup is still treated as absence'
pass 'external result/approval/artifact signature and accepted-tag verification'

# Implement must remain NOT_READY; candidate phase is separate and exit 5.
assert_fixed 'if ([string]$result.release_state -cne "NOT_READY")' 'Implement can claim an elevated release state'
assert_fixed 'IMPLEMENTATION_BLOCKED' 'blocked candidate phase is missing'
assert_fixed 'UNSIGNED_CANDIDATE / REVIEW PENDING' 'unsigned review-pending candidate phase is missing'
assert_fixed 'Implement produced independently verified, unsigned S -> R handoff' 'unsigned handoff closure is missing'
assert_fixed 'exit 5' 'fail-closed Implement exit is missing'
pass 'NOT_READY release_state and separate Implement candidate_phase'

# Evidence is an exact closed set and all consumers bind registry evidence.
for token in \
  'Assert-ExactEvidencePackage' 'registry-derived evidence set' \
  'gate evidence consumer set mismatch' 'KPI evidence consumer set mismatch' \
  'verification command set must be one-to-one with trusted registry tests' \
  'evidence artifact digest mismatch' 'evidence time/freshness window mismatch'; do
  assert_fixed "$token" "exact evidence closure missing: $token"
done
pass 'closed evidence registry, hashes, freshness, and consumers'

# Strict and model-facing schemas must expose only NOT_READY plus the two phases.
"$PYTHON_BIN" - "$STRICT_SCHEMA" "$OUTPUT_SCHEMA" "$TRUST_EXAMPLE" <<'PY'
import json, sys
strict, output, trust=(json.load(open(p, encoding='utf-8-sig')) for p in sys.argv[1:])
required='candidate_phase'
for name, schema in [('strict',strict),('output',output)]:
    if schema.get('additionalProperties') is not False or required not in schema.get('required',[]):
        raise SystemExit(f'FAIL: {name} schema is not closed or candidate_phase is optional')
    state=schema['properties']['release_state']
    states=[state['const']] if 'const' in state else state.get('enum',[])
    if states != ['NOT_READY']:
        raise SystemExit(f'FAIL: {name} schema permits elevated release states: {states!r}')
    phases=schema['properties']['candidate_phase'].get('enum',[])
    if phases != ['IMPLEMENTATION_BLOCKED','UNSIGNED_CANDIDATE / REVIEW PENDING']:
        raise SystemExit(f'FAIL: {name} candidate phases differ: {phases!r}')
repo=strict['properties']['repository']
for field in ('baseline_commit','implementation_commit','implementation_tree','implementation_tree_sha256','release_snapshot_commit'):
    if field not in repo.get('required',[]):
        raise SystemExit(f'FAIL: strict repository identity missing {field}')
tools=trust.get('trusted_tools',{})
expected=['powershell','python','git','gh','docker','codex','gpg']
if list(tools) != expected:
    raise SystemExit(f'FAIL: trust example tool set/order differs: {list(tools)!r}')
for name,spec in tools.items():
    if set(spec) != {'path','sha256','authenticode_required','authenticode_signer_thumbprint'}:
        raise SystemExit(f'FAIL: trust example tool shape differs for {name}')
    if spec['authenticode_required'] is False and spec['authenticode_signer_thumbprint'] is not None:
        raise SystemExit(f'FAIL: optional Authenticode thumbprint must be null for {name}')
print('PASS: schemas and release-trust example implement the closed state/tool contracts')
PY

# Parse and execute the focused adversarial tests with a real PowerShell.
PWSH="${PWSH_BIN:-}"
if [[ -z "$PWSH" ]]; then
  if command -v pwsh >/dev/null 2>&1; then PWSH="$(command -v pwsh)"
  elif command -v powershell >/dev/null 2>&1; then PWSH="$(command -v powershell)"
  else printf 'PLATFORM-BLOCKED: PowerShell is required for runner contract tests\n' >&2; exit 3
  fi
fi
[[ -x "$PWSH" ]] || fail "PowerShell executable is not runnable: $PWSH"
RUNNER_PWSH="$(cygpath -w "$RUNNER")"
VALIDATOR_PWSH="$(cygpath -w "$VALIDATOR")"
TEST_ROOT_PWSH="$(cygpath -w "$TEST_ROOT")"
"$PWSH" -NoLogo -NoProfile -Command "[void][scriptblock]::Create((Get-Content -Raw -LiteralPath '$RUNNER_PWSH')); [void][scriptblock]::Create((Get-Content -Raw -LiteralPath '$VALIDATOR_PWSH'))"
"$PWSH" -NoLogo -NoProfile -File "$TEST_ROOT_PWSH\\test-invoke-utf8-process.ps1"
"$PWSH" -NoLogo -NoProfile -File "$TEST_ROOT_PWSH\\test-validate-codex-final-result.ps1"
"$PWSH" -NoLogo -NoProfile -File "$TEST_ROOT_PWSH\\test-runner-policy-fixtures.ps1" -RunnerPath "$RUNNER_PWSH"
pass 'guarded runner, validator, process, and executable adversarial contracts'
