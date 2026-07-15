Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$validator = Join-Path (Split-Path -Parent $PSScriptRoot) "validate-codex-final-result.ps1"
$shell = (Get-Process -Id $PID).Path
$temp = Join-Path ([IO.Path]::GetTempPath()) ("yonlab-validator-" + [Guid]::NewGuid().ToString("N"))
[IO.Directory]::CreateDirectory((Join-Path $temp "docs/qa")) | Out-Null
[IO.File]::WriteAllText((Join-Path $temp "docs/qa/evidence.json"), '{"status":"PASS"}', (New-Object Text.UTF8Encoding -ArgumentList $false))

$gateIds = @("GATE-DESIGN-INTEGRITY", "GATE-CODE-QUALITY", "GATE-SECURITY-PRIVACY", "GATE-AI-KPI", "GATE-DOCUMENT-KPI", "GATE-UX-ACCESSIBILITY", "GATE-OPERATIONS-RECOVERY", "GATE-PILOT-ACCEPTANCE")
$kpiPolicy = [ordered]@{
    "KPI-001" = @(">=", 0.85); "KPI-002" = @(">=", 0.90); "KPI-003" = @(">=", 0.95); "KPI-004" = @(">=", 0.95); "KPI-005" = @(">=", 0.998)
    "KPI-006" = @(">=", 90.0); "KPI-007" = @(">=", 0.90); "KPI-008" = @("<=", 0.0); "KPI-009" = @("<=", 0.0); "KPI-010" = @(">=", 1.0)
}

function New-Gate([string]$Status = "PASS") { return [ordered]@{status=$Status;freshness="FRESH";summary="verified";evidence_paths=@("docs/qa/evidence.json")} }
function New-Kpi([string]$Id, [string]$Status = "PASS", $AcceptanceId = $null) {
    $definition = $kpiPolicy[$Id]
    return [ordered]@{status=$Status;freshness="FRESH";value=$(if ($Status -ceq "PASS") { $definition[1] } else { $null });comparison=$definition[0];threshold=$definition[1];auxiliary_value=$(if ($Id -ceq "KPI-004") { 0.0 } else { $null });acceptance_id=$AcceptanceId;evidence_paths=@("docs/qa/evidence.json")}
}
function New-Unsigned {
    $gates = [ordered]@{}; foreach ($id in $gateIds) { $gates[$id] = New-Gate }
    $kpis = [ordered]@{}; foreach ($id in $kpiPolicy.Keys) { $kpis[$id] = New-Kpi $id }
    return [ordered]@{
        schema_version="codex-final-result.v1";baseline_id="YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1";run_id="run-20260713-0001";release_id="v1.0.0-rc1";generated_at="2026-07-13T12:00:00Z";release_state="NOT_READY";candidate_phase="UNSIGNED_CANDIDATE / REVIEW PENDING";summary="verified"
        repository=[ordered]@{root="D:\Views\yonlab-inuri-site";remote="https://github.com/yubi-lee/yonlab-i-nuri-site.git";branch="feat/ai-training-platform-v1";baseline_commit=("a"*40);implementation_commit=("b"*40);implementation_tree=("c"*40);implementation_tree_sha256=("d"*64);release_snapshot_commit=("e"*40);worktree_clean=$true;push_status="PUSHED";pull_request_url="https://github.com/yubi-lee/yonlab-i-nuri-site/pull/1"}
        gates=$gates;kpi_results=$kpis;acceptance_data=@();blockers=@();generated_documents=@("docs/qa/evidence.json");commits=@([ordered]@{hash=("b"*40);subject="feat: complete"},[ordered]@{hash=("e"*40);subject="docs: create release snapshot"})
        verification_commands=@([ordered]@{command="verify";status="PASS";exit_code=0;finished_at="2026-07-13T12:00:00Z";acceptance_id=$null;evidence_path="docs/qa/evidence.json"})
        release_attestation=[ordered]@{technical_approvals=@();artifact_integrity=$null;acceptance_approval=$null;annotated_tag=$null}
        next_action=[ordered]@{kind="HUMAN_REVIEW";description="external technical review and detached signatures required";command=$null}
    }
}
function Copy-Object($Value) { return (($Value | ConvertTo-Json -Depth 30) | ConvertFrom-Json) }
function Write-Fixture([string]$Name, $Value) { $path = Join-Path $temp "$Name.json"; [IO.File]::WriteAllText($path, ($Value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding -ArgumentList $false)); return $path }
function Invoke-Validator([string]$Path) {
    $output = @(& $shell -NoLogo -NoProfile -File $validator -ResultPath $Path -ExpectedRunId "run-20260713-0001" -ProjectRoot $temp 2>&1)
    return [pscustomobject]@{ ExitCode=$LASTEXITCODE; Output=(($output | ForEach-Object { $_.ToString() }) -join "`n") }
}
function Expect([string]$Name, $Value, [int]$Expected) {
    $result = Invoke-Validator (Write-Fixture $Name $Value)
    if ($result.ExitCode -ne $Expected) { throw "$Name expected exit $Expected, received $($result.ExitCode): $($result.Output)" }
    Write-Host "PASS: validator $Name -> $Expected"
}

try {
    $unsigned = New-Unsigned
    Expect "unsigned-review-pending" $unsigned 5
    $pending = Copy-Object $unsigned; $pending.release_state = "CODE_COMPLETE / ACCEPTANCE DATA PENDING"
    Expect "reject-codex-signed-candidate" $pending 3
    $accepted = Copy-Object $unsigned; $accepted.release_state = "ACCEPTED"
    Expect "reject-codex-accepted" $accepted 3
    $notReady = Copy-Object $unsigned; $notReady.candidate_phase="IMPLEMENTATION_BLOCKED"; $notReady.blockers=@([ordered]@{id="BLOCK";status="FAIL";description="failed";owner="dev";recovery="fix"}); $notReady.next_action=[ordered]@{kind="REMEDIATE";description="fix";command="resume"}
    Expect "not-ready" $notReady 5

    $cases = [ordered]@{}
    $item=Copy-Object $unsigned; $item.release_id="../../escape"; $cases["unsafe-release"]=$item
    $item=Copy-Object $unsigned; $item.run_id="other-run"; $cases["wrong-run"]=$item
    $item=Copy-Object $unsigned; $item.repository.root="C:\other"; $cases["wrong-root"]=$item
    $item=Copy-Object $unsigned; $item.repository.remote="https://github.com/attacker/repo.git"; $cases["wrong-remote"]=$item
    $item=Copy-Object $unsigned; $item.repository.branch="main"; $cases["wrong-branch"]=$item
    $item=Copy-Object $unsigned; $item.repository.release_snapshot_commit="short"; $cases["bad-commit"]=$item
    $item=Copy-Object $unsigned; $item.schema_version="unknown"; $cases["bad-schema-version"]=$item
    $item=Copy-Object $unsigned; $item.baseline_id="unknown"; $cases["bad-baseline"]=$item
    $item=Copy-Object $unsigned; $item.next_action.kind="RESUME"; $item.next_action.command="resume"; $cases["unsigned-next-action"]=$item
    $item=Copy-Object $unsigned; $item.verification_commands[0].status="REQUIRES_ACCEPTANCE_DATA"; $item.verification_commands[0].exit_code=$null; $cases["unlinked-requires-command"]=$item
    $item=Copy-Object $unsigned; $item.verification_commands[0].evidence_path="../escape"; $cases["unsafe-command-evidence"]=$item
    $item=Copy-Object $unsigned; $item.gates."GATE-CODE-QUALITY".evidence_paths=@("/absolute/evidence"); $cases["absolute-gate-evidence"]=$item
    $item=Copy-Object $unsigned; $item.kpi_results."KPI-003".status="UNKNOWN"; $cases["unknown-kpi-status"]=$item
    $item=Copy-Object $unsigned; $item.verification_commands[0].status="UNKNOWN"; $cases["unknown-command-status"]=$item
    $item=Copy-Object $unsigned; $item.verification_commands[0].evidence_path="docs/qa/missing.json"; $cases["missing-command-evidence"]=$item
    $item=Copy-Object $unsigned; $item.generated_documents=@("..\escape.md"); $cases["unsafe-generated-document"]=$item
    $item=Copy-Object $unsigned; $item | Add-Member -NotePropertyName extra_property -NotePropertyValue "schema bypass"; $cases["extra-top-property"]=$item
    $item=Copy-Object $unsigned; $item.repository | Add-Member -NotePropertyName extra_property -NotePropertyValue $true; $cases["extra-repository-property"]=$item
    $item=Copy-Object $unsigned; $item.gates."GATE-CODE-QUALITY" | Add-Member -NotePropertyName extra_property -NotePropertyValue 1; $cases["extra-gate-property"]=$item
    $item=Copy-Object $unsigned; $item.release_attestation.technical_approvals=@([ordered]@{owner_id="OWN-ARCH";scope_id="ARCHITECTURE";decision="APPROVED";subject_commit=("e"*40);signature_path="docs/qa/evidence.json";signature_sha256=("c"*64);verification_receipt_path="docs/qa/evidence.json"}); $cases["codex-signature-forbidden"]=$item
    foreach ($entry in $cases.GetEnumerator()) { Expect $entry.Key $entry.Value 3 }
    $duplicatePath = Join-Path $temp "duplicate-property.json"
    $acceptedJson = $unsigned | ConvertTo-Json -Depth 30
    $duplicateJson = $acceptedJson.Substring(0, $acceptedJson.LastIndexOf("}")) + ',"schema_version":"codex-final-result.v1"}'
    [IO.File]::WriteAllText($duplicatePath, $duplicateJson, (New-Object Text.UTF8Encoding -ArgumentList $false))
    $duplicateResult = Invoke-Validator $duplicatePath
    if ($duplicateResult.ExitCode -ne 3 -or -not $duplicateResult.Output.Contains("duplicate/ambiguous")) { throw "duplicate JSON property was not rejected: $($duplicateResult.Output)" }
    Write-Host "PASS: validator duplicate property -> 3"
    foreach ($variant in @('SCHEMA_VERSION', 'schema_\u0076ersion')) {
        $variantPath = Join-Path $temp ("duplicate-" + [Guid]::NewGuid().ToString("N") + ".json")
        $variantJson = $acceptedJson.Substring(0, $acceptedJson.LastIndexOf("}")) + ',"' + $variant + '":"codex-final-result.v1"}'
        [IO.File]::WriteAllText($variantPath, $variantJson, (New-Object Text.UTF8Encoding -ArgumentList $false))
        $variantResult = Invoke-Validator $variantPath
        if ($variantResult.ExitCode -ne 3 -or -not $variantResult.Output.Contains("duplicate/ambiguous")) { throw "case/escape duplicate JSON property was not rejected: $variant -> $($variantResult.Output)" }
    }
    Write-Host "PASS: validator case-insensitive and escaped duplicate properties -> 3"
    $nonStrictVariants = [ordered]@{
        comment = $acceptedJson.Insert($acceptedJson.IndexOf('{') + 1, '/*not-json*/')
        trailing_comma = $acceptedJson.Substring(0, $acceptedJson.LastIndexOf('}')) + ',}'
        nan = (New-Object regex '"threshold"\s*:\s*0\.85').Replace($acceptedJson, '"threshold": NaN', 1)
        leading_zero = (New-Object regex '"exit_code"\s*:\s*0').Replace($acceptedJson, '"exit_code": 01', 1)
    }
    foreach ($entry in $nonStrictVariants.GetEnumerator()) {
        $variantPath = Join-Path $temp ("non-strict-" + $entry.Key + ".json")
        [IO.File]::WriteAllText($variantPath, [string]$entry.Value, (New-Object Text.UTF8Encoding -ArgumentList $false))
        $variantResult = Invoke-Validator $variantPath
        if ($variantResult.ExitCode -ne 3) { throw "non-RFC JSON was not rejected: $($entry.Key) -> $($variantResult.Output)" }
    }
    Write-Host "PASS: validator rejects comments, trailing commas, NaN and leading-zero numbers -> 3"
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
