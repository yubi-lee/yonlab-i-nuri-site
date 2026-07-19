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
        schema_version="codex-final-result.v1";baseline_id="YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1";run_id="run-20260713-0001";release_id="v0.1.0-rc5";generated_at="2026-07-13T12:00:00.0000000Z";release_state="NOT_READY";candidate_phase="UNSIGNED_CANDIDATE / REVIEW PENDING";summary="verified"
        repository=[ordered]@{root="D:\Views\yonlab-inuri-site";remote="https://github.com/yubi-lee/yonlab-i-nuri-site.git";branch="feat/ai-training-platform-v1";baseline_commit=("a"*40);implementation_commit=("b"*40);implementation_tree=("c"*40);implementation_tree_sha256=("d"*64);release_snapshot_commit=("e"*40);worktree_clean=$true;push_status="PUSHED";pull_request_url="https://github.com/yubi-lee/yonlab-i-nuri-site/pull/1"}
        gates=$gates;kpi_results=$kpis;acceptance_data=@();blockers=@();generated_documents=@("docs/qa/evidence.json");commits=@([ordered]@{hash=("b"*40);subject="feat: complete"},[ordered]@{hash=("e"*40);subject="docs: create release snapshot"})
        verification_commands=@([ordered]@{command="verify";status="PASS";exit_code=0;finished_at="2026-07-13T12:00:00Z";acceptance_id=$null;evidence_path="docs/qa/evidence.json"})
        release_attestation=[ordered]@{technical_approvals=@();artifact_integrity=$null;acceptance_approval=$null;annotated_tag=$null}
        next_action=[ordered]@{kind="HUMAN_REVIEW";description="external technical review and detached signatures required";command=$null}
    }
}
function Copy-Object($Value) { return (($Value | ConvertTo-Json -Depth 30) | ConvertFrom-Json) }
function Write-Fixture([string]$Name, $Value) { $path = Join-Path $temp "$Name.json"; [IO.File]::WriteAllText($path, ($Value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding -ArgumentList $false)); return $path }
function Invoke-Validator([string]$Path, [string]$ExpectedReleaseId = "v0.1.0-rc5", [string]$ExpectedAttemptStartedAt = "2026-07-13T12:00:00.0000000Z") {
    $previousErrorActionPreference = $ErrorActionPreference
    $output = @()
    $exitCode = $null

    try {
        $ErrorActionPreference = "Continue"

        $output = @(
            & $shell `
                -NoLogo `
                -NoProfile `
                -NonInteractive `
                -ExecutionPolicy Bypass `
                -File $validator `
                -ResultPath $Path `
                -ExpectedRunId "run-20260713-0001" `
                -ExpectedReleaseId $ExpectedReleaseId `
                -ExpectedAttemptStartedAt $ExpectedAttemptStartedAt `
                -ProjectRoot $temp `
                2>&1 |
                ForEach-Object {
                    $_.ToString()
                }
        )

        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($null -eq $exitCode) {
        throw "validator native exit code was not captured"
    }

    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output = ($output -join "`n")
    }
}
function Expect([string]$Name, $Value, [int]$Expected) {
    $result = Invoke-Validator (Write-Fixture $Name $Value)
    if ($result.ExitCode -ne $Expected) { throw "$Name expected exit $Expected, received $($result.ExitCode): $($result.Output)" }
    Write-Host "PASS: validator $Name -> $Expected"
}

try {
    $unsigned = New-Unsigned
    $unsignedResult = Invoke-Validator (
        Write-Fixture "unsigned-review-pending" $unsigned
    )
    if (
        $unsignedResult.ExitCode -ne 5 -or
        -not $unsignedResult.Output.Contains("REVIEW_PENDING") -or
        -not $unsignedResult.Output.Contains("RESULT-UNSIGNED")
    ) {
        throw "unsigned-review-pending expected exit 5 with retained stderr: $($unsignedResult.Output)"
    }
    Write-Host "PASS: validator unsigned-review-pending -> 5 with retained stderr"
    $offsetAttemptResult = Invoke-Validator (Write-Fixture "reject-offset-attempt-start" $unsigned) "v0.1.0-rc5" "2026-07-13T12:00:00.0000000+00:00"
    if ($offsetAttemptResult.ExitCode -ne 3 -or -not $offsetAttemptResult.Output.Contains("ExpectedAttemptStartedAt is not UTC RFC3339")) { throw "validator accepted non-Z guarded attempt timestamp: $($offsetAttemptResult.Output)" }
    Write-Host "PASS: validator rejects non-Z guarded attempt timestamp -> 3"
    $zAttemptResult = Invoke-Validator (Write-Fixture "accept-z-attempt-start" $unsigned) "v0.1.0-rc5" "2026-07-13T12:00:00.0000000Z"
    if ($zAttemptResult.ExitCode -ne 5 -or -not $zAttemptResult.Output.Contains("REVIEW_PENDING")) { throw "validator rejected canonical UTC-Z guarded attempt timestamp: $($zAttemptResult.Output)" }
    Write-Host "PASS: validator accepts canonical UTC-Z guarded attempt timestamp -> 5"
    $future = Copy-Object $unsigned; $future.generated_at = '2026-07-19T00:00:00Z'
    $futureResult = Invoke-Validator (Write-Fixture "reject-future-generated-at" $future) "v0.1.0-rc5" "2026-07-18T16:46:16.5810991Z"
    if ($futureResult.ExitCode -ne 3 -or -not $futureResult.Output.Contains('generated_at differs from guarded attempt timestamp')) { throw "validator accepted future generated_at: $($futureResult.Output)" }
    Write-Host "PASS: validator rejects future generated_at exact-binding mismatch -> 3"
    $tick = Copy-Object $unsigned; $tick.generated_at = '2026-07-13T12:00:00.0000001Z'
    $tickResult = Invoke-Validator (Write-Fixture "reject-tick-generated-at" $tick) "v0.1.0-rc5" "2026-07-13T12:00:00.0000000Z"
    if ($tickResult.ExitCode -ne 3 -or -not $tickResult.Output.Contains('generated_at differs from guarded attempt timestamp')) { throw "validator accepted one-tick generated_at mismatch: $($tickResult.Output)" }
    Write-Host "PASS: validator rejects one-tick generated_at mismatch -> 3"
    $pending = Copy-Object $unsigned; $pending.release_state = "CODE_COMPLETE / ACCEPTANCE DATA PENDING"
    Expect "reject-codex-signed-candidate" $pending 3
    $accepted = Copy-Object $unsigned; $accepted.release_state = "ACCEPTED"
    Expect "reject-codex-accepted" $accepted 3
    $notReady = Copy-Object $unsigned; $notReady.candidate_phase="IMPLEMENTATION_BLOCKED"; $notReady.blockers=@([ordered]@{id="BLOCK";status="FAIL";description="failed";owner="dev";recovery="fix"}); $notReady.next_action=[ordered]@{kind="REMEDIATE";description="fix";command="resume"}
    $notReady.generated_at = "2026-07-13T12:00:00.0000000Z"
    Expect "not-ready" $notReady 5

    $cases = [ordered]@{}
    $item=Copy-Object $unsigned; $item.release_id="../../escape"; $cases["unsafe-release"]=$item
    $item=Copy-Object $unsigned; $item.release_id="v0.1.0-rc4"; $cases["wrong-guarded-release"]=$item
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
