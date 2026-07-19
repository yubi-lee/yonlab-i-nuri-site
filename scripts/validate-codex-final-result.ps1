[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [string]$ExpectedRunId = "",
    [string]$ExpectedReleaseId = "",
    [string]$ProjectRoot = "D:\Views\yonlab-inuri-site",
    [string]$ExpectedAttemptStartedAt = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Invalid([string]$Message) { [Console]::Error.WriteLine("FAIL [RESULT]: $Message"); exit 3 }
function Test-UtcTimestamp([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or -not $Value.EndsWith("Z", [StringComparison]::Ordinal)) { return $false }
    foreach ($format in @("yyyy-MM-dd'T'HH:mm:ssK", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFK")) {
        $parsed = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParseExact($Value, $format, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) { return $true }
    }
    return $false
}
function Require-Property($Object, [string]$Name, [string]$Context) {
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { Invalid "$Context is missing required property '$Name'" }
    return $Object.PSObject.Properties[$Name].Value
}
function Assert-ExactProperties($Object, [string[]]$Expected, [string]$Context) {
    if ($null -eq $Object -or $Object -isnot [Management.Automation.PSCustomObject]) { Invalid "$Context must be a JSON object" }
    $actual = @($Object.PSObject.Properties.Name)
    if ($actual.Count -ne $Expected.Count -or @($actual | Where-Object { $Expected -cnotcontains $_ }).Count -gt 0 -or @($Expected | Where-Object { $actual -cnotcontains $_ }).Count -gt 0) {
        Invalid "$Context properties must be exactly: $($Expected -join ', ')"
    }
}
function Assert-JsonArray($Value, [string]$Context) {
    if ($null -eq $Value -or $Value -isnot [Array]) { Invalid "$Context must be a JSON array" }
}
function Assert-String($Value, [string]$Context, [int]$Minimum = 0, [int]$Maximum = 2147483647) {
    if ($Value -isnot [string] -or $Value.Length -lt $Minimum -or $Value.Length -gt $Maximum) { Invalid "$Context must be a string of length $Minimum..$Maximum" }
}
function Test-JsonNumber($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]
}
function ConvertFrom-StrictJsonText([string]$Text, [string]$Context) {
    # Dependency-free duplicate-property scan for Windows PowerShell 5.1.
    # ConvertFrom-Json remains the syntax/value parser after this lexical pass.
    $containers = New-Object Collections.Stack
    $outside = New-Object Text.StringBuilder
    try {
        $index = 0
        while ($index -lt $Text.Length) {
            $character = $Text[$index]
            if ($character -ceq '{') { [void]$outside.Append($character); $containers.Push([pscustomobject]@{kind="object";names=(New-Object 'Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase))}); $index += 1; continue }
            if ($character -ceq '[') { [void]$outside.Append($character); $containers.Push([pscustomobject]@{kind="array";names=$null}); $index += 1; continue }
            if ($character -ceq '}') {
                [void]$outside.Append($character)
                if ($containers.Count -eq 0) { Invalid "$Context JSON container mismatch" }; $ended = $containers.Pop(); if ($ended.kind -cne "object") { Invalid "$Context JSON container mismatch" }
                $index += 1; continue
            }
            if ($character -ceq ']') {
                [void]$outside.Append($character)
                if ($containers.Count -eq 0) { Invalid "$Context JSON container mismatch" }; $ended = $containers.Pop(); if ($ended.kind -cne "array") { Invalid "$Context JSON container mismatch" }
                $index += 1; continue
            }
            if ($character -ceq '"') {
                $start = $index; $index += 1; $closed = $false
                while ($index -lt $Text.Length) {
                    $code = [int][char]$Text[$index]
                    if ($code -lt 0x20) { Invalid "$Context contains an unescaped control character" }
                    if ($Text[$index] -ceq '\') {
                        $index += 1
                        if ($index -ge $Text.Length) { Invalid "$Context contains an incomplete JSON escape" }
                        $escape = $Text[$index]
                        if ('"\/bfnrt'.IndexOf($escape) -ge 0) { $index += 1; continue }
                        if ($escape -cne 'u' -or $index + 4 -ge $Text.Length -or $Text.Substring($index + 1, 4) -notmatch '^[0-9A-Fa-f]{4}$') { Invalid "$Context contains an invalid JSON escape" }
                        $index += 5; continue
                    }
                    if ($Text[$index] -ceq '"') { $index += 1; $closed = $true; break }
                    $index += 1
                }
                if (-not $closed) { Invalid "$Context contains an unterminated JSON string" }
                $lookahead = $index
                while ($lookahead -lt $Text.Length -and [char]::IsWhiteSpace($Text[$lookahead])) { $lookahead += 1 }
                if ($lookahead -lt $Text.Length -and $Text[$lookahead] -ceq ':') {
                    if ($containers.Count -eq 0 -or $containers.Peek().kind -cne "object") { Invalid "$Context has a property outside an object" }
                    $literal = $Text.Substring($start, $index - $start)
                    try { $name = [string]($literal | ConvertFrom-Json) } catch { Invalid "$Context contains an invalid JSON property string" }
                    if (-not $containers.Peek().names.Add($name)) { Invalid "$Context contains a duplicate/ambiguous JSON property: $name" }
                }
                [void]$outside.Append('  ')
                continue
            }
            [void]$outside.Append($character)
            $index += 1
        }
        if ($containers.Count -ne 0) { Invalid "$Context JSON is incomplete" }
        $outsideText = $outside.ToString()
        if ($outsideText -match '/' -or $outsideText -match ',\s*[}\]]') { Invalid "$Context contains comments or a trailing comma" }
        foreach ($match in [regex]::Matches($outsideText, '[^{}\[\],:\s]+')) {
            $token = $match.Value
            if (@('true','false','null') -contains $token) { continue }
            if ($token -notmatch '^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$') { Invalid "$Context contains a non-RFC8259 token: $token" }
        }
    } catch { Invalid "$Context is not strict JSON: $($_.Exception.Message)" }
    try {
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey("DateKind")) { return $Text | ConvertFrom-Json -DateKind String }
        return $Text | ConvertFrom-Json
    } catch { Invalid "$Context conversion failed: $($_.Exception.Message)" }
}
function Resolve-VerifiedRelativeFile([string]$Relative, [string]$Context) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '^[A-Za-z]:' -or $Relative -match '^[\\/]' -or $Relative.IndexOf([char]0) -ge 0) { Invalid "$Context must be a safe relative path: $Relative" }
    $segments = @($Relative -split '[\\/]')
    if ($segments.Count -eq 0 -or @($segments | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -ceq "." -or $_ -ceq ".." -or $_.Contains(":") }).Count -gt 0) { Invalid "$Context contains an unsafe path component: $Relative" }
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { Invalid "ProjectRoot does not exist: $root" }
    $normalized = $segments -join [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath((Join-Path $root $normalized))
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { Invalid "$Context escapes ProjectRoot: $Relative" }
    $current = $root
    foreach ($segment in $segments) {
        $current = Join-Path $current $segment
        if (Test-Path -LiteralPath $current) {
            if ((((Get-Item -LiteralPath $current -Force).Attributes) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Invalid "$Context contains a reparse point: $Relative" }
        }
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf) -or (Get-Item -LiteralPath $full -Force).Length -le 0) { Invalid "$Context is missing or empty: $Relative" }
    return $full
}

if (-not (Test-Path -LiteralPath $ResultPath -PathType Leaf)) { Invalid "missing result: $ResultPath" }
try {
    $jsonText = Get-Content -Raw -Encoding UTF8 -LiteralPath $ResultPath
    $result = ConvertFrom-StrictJsonText $jsonText "final result"
} catch { Invalid "invalid JSON: $($_.Exception.Message)" }
$requiredTop = @("schema_version", "baseline_id", "run_id", "release_id", "generated_at", "release_state", "candidate_phase", "summary", "repository", "gates", "kpi_results", "acceptance_data", "blockers", "generated_documents", "commits", "verification_commands", "release_attestation", "next_action")
Assert-ExactProperties $result $requiredTop "result"
foreach ($name in $requiredTop) { [void](Require-Property $result $name "result") }
foreach ($name in @("schema_version", "baseline_id", "run_id", "release_id", "generated_at", "release_state", "candidate_phase", "summary")) { Assert-String $result.$name "result.$name" }
if ([string]$result.schema_version -cne "codex-final-result.v1") { Invalid "schema_version mismatch" }
if ([string]$result.baseline_id -cne "YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1") { Invalid "baseline_id mismatch" }
if ([string]$result.run_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{7,95}$') { Invalid "run_id is invalid" }
if (-not [string]::IsNullOrWhiteSpace($ExpectedRunId) -and [string]$result.run_id -cne $ExpectedRunId) { Invalid "run_id differs from active guarded run" }
if ([string]$result.release_id -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+-(rc|RC)[0-9]+$') { Invalid "release_id must be a safe RC SemVer identifier" }
if (-not [string]::IsNullOrWhiteSpace($ExpectedReleaseId) -and [string]$result.release_id -cne $ExpectedReleaseId) { Invalid "release_id differs from active guarded release" }
if (-not (Test-UtcTimestamp ([string]$result.generated_at))) { Invalid "generated_at must be a real UTC RFC3339 timestamp" }
if (-not [string]::IsNullOrWhiteSpace($ExpectedAttemptStartedAt)) {
    if (-not (Test-UtcTimestamp $ExpectedAttemptStartedAt)) { Invalid "ExpectedAttemptStartedAt is not UTC RFC3339" }
    $generated = [DateTimeOffset]::Parse([string]$result.generated_at, [Globalization.CultureInfo]::InvariantCulture)
    $attemptStarted = [DateTimeOffset]::Parse($ExpectedAttemptStartedAt, [Globalization.CultureInfo]::InvariantCulture)
    if ([string]$result.generated_at -cne $ExpectedAttemptStartedAt) { Invalid "generated_at differs from guarded attempt timestamp" }
    if ($generated -lt $attemptStarted -or $generated -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) { Invalid "generated_at is not fresh for the current attempt" }
}
if ([string]::IsNullOrWhiteSpace([string]$result.summary)) { Invalid "summary must be nonempty" }
if ([string]$result.release_state -cne "NOT_READY") { Invalid "Codex may output only baseline release_state NOT_READY; signed states are established by read-only verification modes" }
if (@("IMPLEMENTATION_BLOCKED", "UNSIGNED_CANDIDATE / REVIEW PENDING") -cnotcontains [string]$result.candidate_phase) { Invalid "unknown candidate_phase" }

$repository = Require-Property $result "repository" "result"
$repositoryProperties = @("root", "remote", "branch", "baseline_commit", "implementation_commit", "implementation_tree", "implementation_tree_sha256", "release_snapshot_commit", "worktree_clean", "push_status", "pull_request_url")
Assert-ExactProperties $repository $repositoryProperties "repository"
foreach ($name in $repositoryProperties) { [void](Require-Property $repository $name "repository") }
foreach ($name in @("root", "remote", "branch", "baseline_commit", "implementation_commit", "implementation_tree", "implementation_tree_sha256", "release_snapshot_commit", "push_status")) { Assert-String $repository.$name "repository.$name" }
if ($repository.worktree_clean -isnot [bool]) { Invalid "repository.worktree_clean must be boolean" }
if ($null -ne $repository.pull_request_url -and $repository.pull_request_url -isnot [string]) { Invalid "repository.pull_request_url must be string or null" }
if ([string]$repository.root -cne "D:\Views\yonlab-inuri-site" -or [string]$repository.remote -cne "https://github.com/yubi-lee/yonlab-i-nuri-site.git" -or [string]$repository.branch -cne "feat/ai-training-platform-v1") { Invalid "repository identity mismatch" }
if ([string]$repository.baseline_commit -notmatch '^[0-9a-f]{40}$') { Invalid "repository.baseline_commit must be a full 40-hex commit" }
if ([string]$result.candidate_phase -ceq "IMPLEMENTATION_BLOCKED") {
    if ([string]$repository.implementation_commit -cne "" -or [string]$repository.implementation_tree -cne "" -or [string]$repository.implementation_tree_sha256 -cne "" -or [string]$repository.release_snapshot_commit -cne "") {
        Invalid "IMPLEMENTATION_BLOCKED must not report implementation or release snapshot identities"
    }
    if ($null -ne $repository.pull_request_url) { Invalid "IMPLEMENTATION_BLOCKED must not report a pull request URL" }
} elseif ([string]$repository.implementation_commit -notmatch '^[0-9a-f]{40}$' -or [string]$repository.implementation_tree -notmatch '^[0-9a-f]{40}$' -or [string]$repository.implementation_tree_sha256 -notmatch '^[0-9a-f]{64}$' -or [string]$repository.release_snapshot_commit -notmatch '^[0-9a-f]{40}$' -or [string]$repository.implementation_commit -ceq [string]$repository.release_snapshot_commit) {
    Invalid "repository must report distinct implementation S and release snapshot R with exact tree identities"
}
if (@("PUSHED", "NOT_PUSHED", "BLOCKED") -cnotcontains [string]$repository.push_status) { Invalid "unknown repository push_status" }
$prUri = $null; $prValue = [string]$repository.pull_request_url
$prValid = -not [string]::IsNullOrWhiteSpace($prValue) -and [Uri]::TryCreate($prValue, [UriKind]::Absolute, [ref]$prUri) -and $prUri.Scheme -ceq "https" -and $prUri.Host -ceq "github.com" -and $prUri.AbsolutePath -match '^/yubi-lee/yonlab-i-nuri-site/pull/[0-9]+$'
if (-not [string]::IsNullOrWhiteSpace($prValue) -and -not $prValid) { Invalid "pull_request_url is not the canonical GitHub PR URI" }

$GateIds = @("GATE-DESIGN-INTEGRITY", "GATE-CODE-QUALITY", "GATE-SECURITY-PRIVACY", "GATE-AI-KPI", "GATE-DOCUMENT-KPI", "GATE-UX-ACCESSIBILITY", "GATE-OPERATIONS-RECOVERY", "GATE-PILOT-ACCEPTANCE")
$AllowedStatuses = @("PASS", "FAIL", "BLOCKED", "REQUIRES_ACCEPTANCE_DATA")
$AllowedFreshness = @("FRESH", "MISSING", "STALE")
$AllowedAcceptanceGates = @{
    "GATE-AI-KPI" = @("KPI-001", "KPI-002")
    "GATE-UX-ACCESSIBILITY" = @("KPI-006")
    "GATE-OPERATIONS-RECOVERY" = @("KPI-010")
    "GATE-PILOT-ACCEPTANCE" = @("KPI-007")
}
$KpiPolicy = @{
    "KPI-001" = @{ Gate="GATE-AI-KPI"; Comparison=">="; Threshold=0.85; Acceptance=$true }
    "KPI-002" = @{ Gate="GATE-AI-KPI"; Comparison=">="; Threshold=0.90; Acceptance=$true }
    "KPI-003" = @{ Gate="GATE-DOCUMENT-KPI"; Comparison=">="; Threshold=0.95; Acceptance=$false }
    "KPI-004" = @{ Gate="GATE-DOCUMENT-KPI"; Comparison=">="; Threshold=0.95; Acceptance=$false }
    "KPI-005" = @{ Gate="GATE-AI-KPI"; Comparison=">="; Threshold=0.998; Acceptance=$false }
    "KPI-006" = @{ Gate="GATE-UX-ACCESSIBILITY"; Comparison=">="; Threshold=90.0; Acceptance=$true }
    "KPI-007" = @{ Gate="GATE-PILOT-ACCEPTANCE"; Comparison=">="; Threshold=0.90; Acceptance=$true }
    "KPI-008" = @{ Gate="GATE-OPERATIONS-RECOVERY"; Comparison="<="; Threshold=0.0; Acceptance=$false }
    "KPI-009" = @{ Gate="GATE-UX-ACCESSIBILITY"; Comparison="<="; Threshold=0.0; Acceptance=$false }
    "KPI-010" = @{ Gate="GATE-OPERATIONS-RECOVERY"; Comparison=">="; Threshold=1.0; Acceptance=$true }
}

$gatesObject = Require-Property $result "gates" "result"; $gates = @{}
Assert-ExactProperties $gatesObject $GateIds "gates"
if (@($gatesObject.PSObject.Properties).Count -ne $GateIds.Count) { Invalid "gates must contain exactly the eight baseline gates" }
foreach ($id in $GateIds) {
    $gate = Require-Property $gatesObject $id "gates"; $gates[$id] = $gate
    $gateProperties = @("status", "freshness", "summary", "evidence_paths")
    Assert-ExactProperties $gate $gateProperties $id
    foreach ($name in $gateProperties) { [void](Require-Property $gate $name $id) }
    foreach ($name in @("status", "freshness", "summary")) { Assert-String $gate.$name "$id.$name" }
    Assert-JsonArray $gate.evidence_paths "$id.evidence_paths"
    if ($AllowedStatuses -cnotcontains [string]$gate.status -or $AllowedFreshness -cnotcontains [string]$gate.freshness) { Invalid "$id has unknown status/freshness" }
    if ([string]::IsNullOrWhiteSpace([string]$gate.summary)) { Invalid "$id summary must be nonempty" }
    if (([string]$gate.status -ceq "PASS" -or [string]$gate.status -ceq "REQUIRES_ACCEPTANCE_DATA") -and ([string]$gate.freshness -cne "FRESH" -or @($gate.evidence_paths).Count -eq 0)) { Invalid "$id requires FRESH nonempty evidence" }
    if ([string]$gate.status -ceq "REQUIRES_ACCEPTANCE_DATA" -and -not $AllowedAcceptanceGates.ContainsKey($id)) { Invalid "$id may not hide implementation work as acceptance data" }
    foreach ($relative in @($gate.evidence_paths)) { [void](Resolve-VerifiedRelativeFile ([string]$relative) "$id evidence") }
}

$kpisObject = Require-Property $result "kpi_results" "result"; $kpis = @{}
Assert-ExactProperties $kpisObject @($KpiPolicy.Keys) "kpi_results"
if (@($kpisObject.PSObject.Properties).Count -ne $KpiPolicy.Count) { Invalid "kpi_results must contain exactly KPI-001 through KPI-010" }
foreach ($kpiId in ($KpiPolicy.Keys | Sort-Object)) {
    $item = Require-Property $kpisObject $kpiId "kpi_results"; $policy = $KpiPolicy[$kpiId]; $kpis[$kpiId] = $item
    $kpiProperties = @("status", "freshness", "value", "comparison", "threshold", "auxiliary_value", "acceptance_id", "evidence_paths")
    Assert-ExactProperties $item $kpiProperties $kpiId
    foreach ($name in $kpiProperties) { [void](Require-Property $item $name $kpiId) }
    foreach ($name in @("status", "freshness", "comparison")) { Assert-String $item.$name "$kpiId.$name" }
    if (-not (Test-JsonNumber $item.threshold)) { Invalid "$kpiId.threshold must be numeric" }
    if ($null -ne $item.value -and -not (Test-JsonNumber $item.value)) { Invalid "$kpiId.value must be numeric or null" }
    if ($null -ne $item.auxiliary_value -and -not (Test-JsonNumber $item.auxiliary_value)) { Invalid "$kpiId.auxiliary_value must be numeric or null" }
    if ($null -ne $item.acceptance_id -and $item.acceptance_id -isnot [string]) { Invalid "$kpiId.acceptance_id must be string or null" }
    Assert-JsonArray $item.evidence_paths "$kpiId.evidence_paths"
    if ($AllowedStatuses -cnotcontains [string]$item.status -or $AllowedFreshness -cnotcontains [string]$item.freshness) { Invalid "$kpiId has unknown status/freshness" }
    if ([string]$item.comparison -cne $policy.Comparison -or [Math]::Abs(([double]$item.threshold) - ([double]$policy.Threshold)) -gt 0.000000001) { Invalid "$kpiId comparison/threshold differs from baseline" }
    if (([string]$item.status -ceq "PASS" -or [string]$item.status -ceq "REQUIRES_ACCEPTANCE_DATA") -and ([string]$item.freshness -cne "FRESH" -or @($item.evidence_paths).Count -eq 0)) { Invalid "$kpiId requires FRESH nonempty evidence" }
    foreach ($relative in @($item.evidence_paths)) { [void](Resolve-VerifiedRelativeFile ([string]$relative) "$kpiId evidence") }
    if ([string]$item.status -ceq "PASS") {
        if ($null -eq $item.value -or $null -ne $item.acceptance_id) { Invalid "$kpiId PASS requires numeric value and null acceptance_id (value=$($item.value), acceptance_id=$($item.acceptance_id))" }
        $value = [double]$item.value
        if (($policy.Comparison -ceq ">=" -and $value -lt $policy.Threshold) -or ($policy.Comparison -ceq "<=" -and $value -gt $policy.Threshold)) { Invalid "$kpiId value fails threshold" }
        if ($kpiId -ceq "KPI-004" -and ($null -eq $item.auxiliary_value -or [double]$item.auxiliary_value -ne 0.0)) { Invalid "KPI-004 invalid citation count must be 0" }
    } elseif ([string]$item.status -ceq "REQUIRES_ACCEPTANCE_DATA") {
        if (-not $policy.Acceptance -or $null -ne $item.value -or [string]::IsNullOrWhiteSpace([string]$item.acceptance_id)) { Invalid "$kpiId is not a valid external acceptance KPI result" }
    } elseif ($null -ne $item.acceptance_id) { Invalid "$kpiId non-pending state requires null acceptance_id" }
}

Assert-JsonArray $result.acceptance_data "acceptance_data"
$acceptanceItems = @($result.acceptance_data); $acceptanceIds = @{}
foreach ($item in $acceptanceItems) {
    $acceptanceProperties = @("id", "gate_id", "kpi_id", "owner_id", "status", "required_evidence", "missing_input_ids", "due_at_utc", "candidate_commit", "candidate_source_tree_sha256")
    Assert-ExactProperties $item $acceptanceProperties "acceptance item"
    foreach ($name in $acceptanceProperties) { [void](Require-Property $item $name "acceptance item") }
    foreach ($name in @("id", "gate_id", "kpi_id", "owner_id", "status", "required_evidence", "due_at_utc", "candidate_commit", "candidate_source_tree_sha256")) { Assert-String $item.$name "acceptance item.$name" }
    Assert-JsonArray $item.missing_input_ids "acceptance item.missing_input_ids"
    if (@($item.missing_input_ids).Count -eq 0 -or @($item.missing_input_ids | Sort-Object -Unique).Count -ne @($item.missing_input_ids).Count -or @($item.missing_input_ids | Where-Object { $_ -isnot [string] -or $_ -notmatch '^[A-Z][A-Z0-9-]{2,63}$' }).Count -gt 0) { Invalid "acceptance item missing_input_ids must be nonempty unique IDs" }
    if ([string]$item.owner_id -cne "OWN-ACC" -or -not (Test-UtcTimestamp ([string]$item.due_at_utc)) -or [string]$item.candidate_commit -notmatch '^[0-9a-f]{40}$' -or [string]$item.candidate_source_tree_sha256 -notmatch '^[0-9a-f]{64}$') { Invalid "acceptance item OWN-ACC scope/candidate/due contract is invalid" }
    $id = [string]$item.id
    if ([string]::IsNullOrWhiteSpace($id) -or $acceptanceIds.ContainsKey($id)) { Invalid "acceptance IDs must be nonempty and unique" }; $acceptanceIds[$id] = $item
    if ([string]$item.status -cne "REQUIRES_ACCEPTANCE_DATA" -or -not $AllowedAcceptanceGates.ContainsKey([string]$item.gate_id)) { Invalid "acceptance item has disallowed status/gate: $id" }
    if ([string]::IsNullOrWhiteSpace([string]$item.required_evidence)) { Invalid "acceptance item required_evidence must be nonempty: $id" }
    if ($AllowedAcceptanceGates[[string]$item.gate_id] -notcontains [string]$item.kpi_id) { Invalid "acceptance item KPI does not belong to gate: $id" }
    if ([string]$gates[[string]$item.gate_id].status -cne "REQUIRES_ACCEPTANCE_DATA") { Invalid "acceptance item is not linked to a pending gate: $id" }
    if ([string]$kpis[[string]$item.kpi_id].status -cne "REQUIRES_ACCEPTANCE_DATA" -or [string]$kpis[[string]$item.kpi_id].acceptance_id -cne $id) { Invalid "acceptance item is not linked 1:1 to a pending KPI: $id" }
}
foreach ($gateId in $AllowedAcceptanceGates.Keys) {
    if ([string]$gates[$gateId].status -ceq "REQUIRES_ACCEPTANCE_DATA" -and @($acceptanceItems | Where-Object { $_.gate_id -ceq $gateId }).Count -eq 0) { Invalid "$gateId lacks a linked acceptance item" }
    $pendingKpis = @($KpiPolicy.Keys | Where-Object { $KpiPolicy[$_].Gate -ceq $gateId -and [string]$kpis[$_].status -ceq "REQUIRES_ACCEPTANCE_DATA" })
    if ([string]$gates[$gateId].status -ceq "REQUIRES_ACCEPTANCE_DATA" -and $pendingKpis.Count -eq 0) { Invalid "$gateId pending state has no external-acceptance KPI" }
}
foreach ($kpiId in $KpiPolicy.Keys) {
    if ([string]$kpis[$kpiId].status -ceq "REQUIRES_ACCEPTANCE_DATA") {
        $expectedGate = $KpiPolicy[$kpiId].Gate
        if ([string]$gates[$expectedGate].status -cne "REQUIRES_ACCEPTANCE_DATA" -or @($acceptanceItems | Where-Object { $_.id -ceq $kpis[$kpiId].acceptance_id }).Count -ne 1) { Invalid "$kpiId pending state is not propagated/linkable" }
    }
}

Assert-JsonArray $result.verification_commands "verification_commands"
$commands = @($result.verification_commands)
if ($commands.Count -eq 0) { Invalid "verification_commands must be nonempty" }
foreach ($command in $commands) {
    $commandProperties = @("command", "status", "exit_code", "finished_at", "acceptance_id", "evidence_path")
    Assert-ExactProperties $command $commandProperties "verification command"
    foreach ($name in $commandProperties) { [void](Require-Property $command $name "verification command") }
    foreach ($name in @("command", "status", "finished_at", "evidence_path")) { Assert-String $command.$name "verification command.$name" }
    if ($null -ne $command.exit_code -and ($command.exit_code -isnot [int] -and $command.exit_code -isnot [long])) { Invalid "verification command.exit_code must be integer or null" }
    if ($null -ne $command.acceptance_id -and $command.acceptance_id -isnot [string]) { Invalid "verification command.acceptance_id must be string or null" }
    if ($AllowedStatuses -cnotcontains [string]$command.status) { Invalid "verification command has unknown status" }
    if ([string]::IsNullOrWhiteSpace([string]$command.command)) { Invalid "verification command text must be nonempty" }
    if (-not (Test-UtcTimestamp ([string]$command.finished_at))) { Invalid "verification timestamp is not real UTC RFC3339: $($command.command)" }
    [void](Resolve-VerifiedRelativeFile ([string]$command.evidence_path) "verification command evidence")
    if ([string]$command.status -ceq "PASS") {
        if ($command.exit_code -ne 0 -or $null -ne $command.acceptance_id) { Invalid "PASS command requires exit 0 and null acceptance_id: $($command.command)" }
    } elseif ([string]$command.status -ceq "FAIL") {
        if ($null -eq $command.exit_code -or $command.exit_code -lt 1 -or $null -ne $command.acceptance_id) { Invalid "FAIL command requires nonzero exit and null acceptance_id: $($command.command)" }
    } elseif ([string]$command.status -ceq "BLOCKED") {
        if ($null -ne $command.exit_code -or $null -ne $command.acceptance_id) { Invalid "BLOCKED command requires null exit/acceptance_id: $($command.command)" }
    } else {
        $acceptanceId = [string]$command.acceptance_id
        if ($null -ne $command.exit_code -or [string]::IsNullOrWhiteSpace($acceptanceId) -or -not $acceptanceIds.ContainsKey($acceptanceId)) { Invalid "REQUIRES_ACCEPTANCE_DATA command is not linked to an acceptance item: $($command.command)" }
    }
}

Assert-JsonArray $result.generated_documents "generated_documents"
$generatedDocuments = @($result.generated_documents)
if (@($generatedDocuments | Sort-Object -Unique).Count -ne $generatedDocuments.Count) { Invalid "generated_documents must not contain duplicates" }
foreach ($relative in $generatedDocuments) { [void](Resolve-VerifiedRelativeFile ([string]$relative) "generated document") }
Assert-JsonArray $result.commits "commits"
foreach ($commit in @($result.commits)) {
    Assert-ExactProperties $commit @("hash", "subject") "commit"
    foreach ($name in @("hash", "subject")) { [void](Require-Property $commit $name "commit"); Assert-String $commit.$name "commit.$name" }
    if ([string]$commit.hash -notmatch '^[0-9a-f]{40}$' -or [string]::IsNullOrWhiteSpace([string]$commit.subject)) { Invalid "commit entry is invalid" }
}
Assert-JsonArray $result.blockers "blockers"
foreach ($blocker in @($result.blockers)) {
    $blockerProperties = @("id", "status", "description", "owner", "recovery")
    Assert-ExactProperties $blocker $blockerProperties "blocker"
    foreach ($name in $blockerProperties) { [void](Require-Property $blocker $name "blocker"); Assert-String $blocker.$name "blocker.$name" }
    if (@("FAIL", "BLOCKED", "MISSING", "STALE") -cnotcontains [string]$blocker.status) { Invalid "blocker status is invalid" }
    if ([string]::IsNullOrWhiteSpace([string]$blocker.id) -or [string]::IsNullOrWhiteSpace([string]$blocker.description) -or [string]::IsNullOrWhiteSpace([string]$blocker.owner) -or [string]::IsNullOrWhiteSpace([string]$blocker.recovery)) { Invalid "blocker fields must be nonempty" }
}

$releaseAttestation = Require-Property $result "release_attestation" "result"
$attestationProperties = @("technical_approvals", "artifact_integrity", "acceptance_approval", "annotated_tag")
Assert-ExactProperties $releaseAttestation $attestationProperties "release_attestation"
foreach ($name in $attestationProperties) { [void](Require-Property $releaseAttestation $name "release_attestation") }
Assert-JsonArray $releaseAttestation.technical_approvals "release_attestation.technical_approvals"
$technicalScopeByOwner = [ordered]@{
    "OWN-ARCH" = "ARCHITECTURE"
    "OWN-UX" = "UX-ACCESSIBILITY"
    "OWN-AI" = "AI"
    "OWN-DOC" = "DOCUMENT-AI"
    "OWN-SEC" = "SECURITY-PRIVACY"
    "OWN-OPS" = "OPERATIONS"
    "OWN-QA" = "QUALITY"
}
$technicalOwners = @{}
foreach ($approval in @($releaseAttestation.technical_approvals)) {
    $approvalProperties = @("owner_id", "scope_id", "decision", "subject_commit", "signature_path", "signature_sha256", "verification_receipt_path")
    Assert-ExactProperties $approval $approvalProperties "technical approval"
    foreach ($name in $approvalProperties) { [void](Require-Property $approval $name "technical approval"); Assert-String $approval.$name "technical approval.$name" }
    $ownerId = [string]$approval.owner_id
    if (-not $technicalScopeByOwner.Contains($ownerId) -or $technicalOwners.ContainsKey($ownerId)) { Invalid "technical approval owner must be one of seven exact unique technical owners: $ownerId" }
    $technicalOwners[$ownerId] = $true
    if ([string]$approval.scope_id -cne $technicalScopeByOwner[$ownerId] -or [string]$approval.decision -cne "APPROVED" -or [string]$approval.subject_commit -cne [string]$repository.release_snapshot_commit -or [string]$approval.signature_sha256 -notmatch '^[0-9a-f]{64}$') { Invalid "technical approval scope/decision/commit/signature contract failed: $ownerId" }
    [void](Resolve-VerifiedRelativeFile ([string]$approval.signature_path) "$ownerId signature")
    [void](Resolve-VerifiedRelativeFile ([string]$approval.verification_receipt_path) "$ownerId signature receipt")
}

if ($null -ne $releaseAttestation.artifact_integrity) {
    Assert-ExactProperties $releaseAttestation.artifact_integrity @("release", "distribution") "artifact_integrity"
    $artifactIntegrityProperties = @("manifest_path", "manifest_signature_path", "checksums_path", "checksums_signature_path", "verification_receipt_path")
    foreach ($scope in @("release", "distribution")) {
        $scopeIntegrity = Require-Property $releaseAttestation.artifact_integrity $scope "artifact_integrity"
        Assert-ExactProperties $scopeIntegrity $artifactIntegrityProperties "artifact_integrity.$scope"
        foreach ($name in $artifactIntegrityProperties) {
            $value = Require-Property $scopeIntegrity $name "artifact_integrity.$scope"
            Assert-String $value "artifact_integrity.$scope.$name" 1 1000
            [void](Resolve-VerifiedRelativeFile ([string]$value) "artifact_integrity.$scope.$name")
        }
    }
}

if ($null -ne $releaseAttestation.acceptance_approval) {
    $acceptanceApprovalProperties = @("owner_id", "scope_id", "decision", "subject_commit", "signature_path", "signature_sha256", "verification_receipt_path")
    Assert-ExactProperties $releaseAttestation.acceptance_approval $acceptanceApprovalProperties "acceptance_approval"
    foreach ($name in $acceptanceApprovalProperties) { [void](Require-Property $releaseAttestation.acceptance_approval $name "acceptance_approval"); Assert-String $releaseAttestation.acceptance_approval.$name "acceptance_approval.$name" }
    if ([string]$releaseAttestation.acceptance_approval.owner_id -cne "OWN-ACC" -or [string]$releaseAttestation.acceptance_approval.scope_id -cne "FINAL-ACCEPTANCE" -or [string]$releaseAttestation.acceptance_approval.decision -cne "ACCEPTED" -or [string]$releaseAttestation.acceptance_approval.subject_commit -cne [string]$repository.release_snapshot_commit -or [string]$releaseAttestation.acceptance_approval.signature_sha256 -notmatch '^[0-9a-f]{64}$') { Invalid "acceptance approval scope/decision/commit/signature contract failed" }
    [void](Resolve-VerifiedRelativeFile ([string]$releaseAttestation.acceptance_approval.signature_path) "acceptance signature")
    [void](Resolve-VerifiedRelativeFile ([string]$releaseAttestation.acceptance_approval.verification_receipt_path) "acceptance signature receipt")
}

if ($null -ne $releaseAttestation.annotated_tag) {
    $tagProperties = @("name", "object_type", "tag_object_sha", "target_commit", "verification_receipt_path")
    Assert-ExactProperties $releaseAttestation.annotated_tag $tagProperties "annotated_tag"
    foreach ($name in $tagProperties) { [void](Require-Property $releaseAttestation.annotated_tag $name "annotated_tag"); Assert-String $releaseAttestation.annotated_tag.$name "annotated_tag.$name" }
    if ([string]$releaseAttestation.annotated_tag.name -cne [string]$result.release_id -or [string]$releaseAttestation.annotated_tag.object_type -cne "tag" -or [string]$releaseAttestation.annotated_tag.tag_object_sha -notmatch '^[0-9a-f]{40}$' -or [string]$releaseAttestation.annotated_tag.target_commit -cne [string]$repository.release_snapshot_commit) { Invalid "annotated tag identity/target contract failed" }
    [void](Resolve-VerifiedRelativeFile ([string]$releaseAttestation.annotated_tag.verification_receipt_path) "annotated tag verification receipt")
}

$next = Require-Property $result "next_action" "result"
Assert-ExactProperties $next @("kind", "description", "command") "next_action"
foreach ($name in @("kind", "description", "command")) { [void](Require-Property $next $name "next_action") }
Assert-String $next.kind "next_action.kind"; Assert-String $next.description "next_action.description"
if ($null -ne $next.command -and $next.command -isnot [string]) { Invalid "next_action.command must be string or null" }
if ([string]::IsNullOrWhiteSpace([string]$next.description)) { Invalid "next_action description must be nonempty" }

$handoff = $repository.worktree_clean -eq $true -and [string]$repository.push_status -ceq "PUSHED" -and $prValid -and @($result.generated_documents).Count -gt 0 -and @($result.commits).Count -gt 0
$hasBadKpi = @($kpis.Values | Where-Object { [string]$_.status -ceq "FAIL" -or [string]$_.status -ceq "BLOCKED" -or [string]$_.freshness -cne "FRESH" }).Count -gt 0
if ([string]$result.candidate_phase -ceq "UNSIGNED_CANDIDATE / REVIEW PENDING") {
    if ([string]$next.kind -cne "HUMAN_REVIEW" -or $null -ne $next.command) { Invalid "unsigned candidate next_action must be HUMAN_REVIEW with null command" }
    $badGate = @($gates.Values | Where-Object { ([string]$_.status -cne "PASS" -and [string]$_.status -cne "REQUIRES_ACCEPTANCE_DATA") -or [string]$_.freshness -cne "FRESH" }).Count -gt 0
    $badCommand = @($commands | Where-Object { [string]$_.status -cne "PASS" -and [string]$_.status -cne "REQUIRES_ACCEPTANCE_DATA" }).Count -gt 0
    if (-not $handoff -or $badCommand -or $hasBadKpi -or $badGate -or @($result.blockers).Count -gt 0 -or $technicalOwners.Count -ne 0 -or $null -ne $releaseAttestation.artifact_integrity -or $null -ne $releaseAttestation.acceptance_approval -or $null -ne $releaseAttestation.annotated_tag) { Invalid "unsigned candidate invariants failed" }
    [Console]::Error.WriteLine("REVIEW_PENDING [RESULT-UNSIGNED]: release_state remains NOT_READY until read-only external verification")
    exit 5
} elseif ([string]$result.candidate_phase -ceq "IMPLEMENTATION_BLOCKED") {
    if (@("RESUME", "REMEDIATE") -cnotcontains [string]$next.kind -or [string]::IsNullOrWhiteSpace([string]$next.command)) { Invalid "NOT_READY next_action must be RESUME/REMEDIATE with a command" }
    if (@($result.blockers).Count -eq 0) { Invalid "NOT_READY requires blockers" }
    if ($technicalOwners.Count -ne 0 -or $null -ne $releaseAttestation.artifact_integrity -or $null -ne $releaseAttestation.acceptance_approval -or $null -ne $releaseAttestation.annotated_tag) { Invalid "NOT_READY may not carry self-asserted signatures or tag" }
    [Console]::Error.WriteLine("IMPLEMENTATION_BLOCKED [RESULT-NOT-READY]: evidence preserved")
    exit 5
} else {
    Invalid "unknown candidate phase: $($result.candidate_phase)"
}


