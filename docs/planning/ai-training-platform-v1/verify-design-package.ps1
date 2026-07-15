[CmdletBinding()]
param(
    [string]$PackageRoot,
    [string]$PythonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
foreach ($PythonEnvironmentName in @("PYTHONPATH","PYTHONHOME","PYTHONSTARTUP","PYTHONUSERBASE","PYTHONINSPECT","PYTHONWARNINGS","PYTHONBREAKPOINT","PYTHONCASEOK","PYTHONEXECUTABLE","PYTHONSAFEPATH")) {
    Remove-Item -LiteralPath "Env:$PythonEnvironmentName" -ErrorAction SilentlyContinue
}
$env:PYTHONNOUSERSITE = "1"
$env:PYTHONDONTWRITEBYTECODE = "1"
$ProgressPreference = "SilentlyContinue"
$env:PYTHONDONTWRITEBYTECODE = "1"

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$PackageRoot = [IO.Path]::GetFullPath($PackageRoot)
$WorkRoot = [IO.Path]::GetFullPath((Join-Path $PackageRoot ".."))
$Failures = New-Object System.Collections.Generic.List[object]

# Shared with verify-design-package.sh. The regression suite checks these
# identifiers so a parity check cannot silently disappear from one verifier.
$OverlayPolicyParityMarker = "OVERLAY_POLICY_V2_RECURSIVE_EXACT"
$ParityCheckIds = @(
    "CANONICAL_FILES",
    "JSON_PARSE",
    "REQUIREMENT_COUNTS",
    "DOCUMENT_IDS",
    "MARKDOWN_STRUCTURE",
    "CANONICAL_COORDINATES",
    "KPI_THRESHOLDS",
    "PERSONA_HIERARCHY",
    "DATA_POLICY",
    "RELEASE_STATES",
    "FINAL_OUTPUT_ROOTS",
    "RUNBOOK_INVENTORY",
    "MANUAL_PAIRS",
    "RUNTIME_CONTRACT",
    "ACTIVE_SAFETY",
    "SHELL_MODES",
    "MODEL_OUTPUT_SCHEMA",
    "FINAL_DOCUMENT_INVENTORY",
    "MACHINE_CONTRACTS",
    "COMPLETENESS_CONTRACTS",
    "SOURCE_TRACEABILITY",
    "NORMATIVE_TEST_SEMANTICS",
    "SEMANTIC_DEPTH_CONTRACTS",
    "AI_GATEWAY_SAFEGUARDING",
    "TCH_015_AUTHORIZATION"
)

function Add-Failure([string]$Code, [string]$Message) {
    $Failures.Add([pscustomobject]@{ Code = $Code; Message = $Message }) | Out-Null
}

function Assert-True($Condition, [string]$Code, [string]$Message) {
    if (-not $Condition) { Add-Failure $Code $Message }
}

function Read-Text([string]$Path, [string]$Code = "CANONICAL_FILES") {
    try {
        return [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding -ArgumentList $false, $true))
    } catch {
        Add-Failure $Code "cannot read ${Path}: $($_.Exception.Message)"
        return ""
    }
}

function Read-Json([string]$Path) {
    try {
        $source = [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding -ArgumentList $false, $true))
        return $source | ConvertFrom-Json
    } catch {
        Add-Failure "JSON_PARSE" "invalid JSON ${Path}: $($_.Exception.Message)"
        return $null
    }
}

function Get-PropertyValue($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Has-Property($Object, [string]$Name) {
    if ($null -eq $Object) { return $false }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Same-Sequence([object[]]$Actual, [object[]]$Expected) {
    if ($Actual.Count -ne $Expected.Count) { return $false }
    for ($index = 0; $index -lt $Expected.Count; $index += 1) {
        if ([string]$Actual[$index] -cne [string]$Expected[$index]) { return $false }
    }
    return $true
}

function Same-Set([object[]]$Actual, [object[]]$Expected) {
    $actualValues = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedValues = @($Expected | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    return Same-Sequence -Actual $actualValues -Expected $expectedValues
}

function Get-MatchValues([string]$Body, [string]$Pattern, [int]$Group = 1) {
    return @([regex]::Matches($Body, $Pattern) | ForEach-Object { $_.Groups[$Group].Value })
}

function Is-SafeRelativePath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -match '^[A-Za-z]:[\\/]' -or $Value.StartsWith('/') -or $Value.StartsWith('\')) { return $false }
    return -not (@($Value -split '[\\/]') -contains '..')
}

function Invoke-PythonGate($PythonCommand, [string]$Code, [string]$Checker, [string[]]$Arguments) {
    if (-not (Test-Path -LiteralPath $Checker -PathType Leaf) -or (Get-Item -LiteralPath $Checker).Length -eq 0) {
        Add-Failure $Code "required checker is missing or empty: $Checker"
        return
    }
    if ($null -eq $PythonCommand) {
        Add-Failure $Code "python3/python is required for deterministic contract validation"
        return
    }
    $global:LASTEXITCODE = 0
    Push-Location -LiteralPath (Split-Path -Parent $PythonCommand)
    try {
        $Lines = @(& $PythonCommand -I -S -B $Checker @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $ExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $ResultLines = @($Lines | Where-Object { $_ -match '^RESULT: (?:PASS|FAIL)$' })
    $LastLine = $(if ($Lines.Count -gt 0) { $Lines[-1] } else { "" })
    if ($ExitCode -ne 0 -or $ResultLines.Count -ne 1 -or $LastLine -cne "RESULT: PASS") {
        $Diagnostic = @($Lines | Where-Object { $_ -notmatch '^RESULT: (?:PASS|FAIL)$' }) -join " | "
        Add-Failure $Code "checker failed or returned a nondeterministic result (exit $ExitCode): $Diagnostic"
    }
}

function Test-ModelOutputSchemaNode($Node, [string]$Location) {
    if ($null -eq $Node -or -not ($Node -is [System.Management.Automation.PSCustomObject])) {
        Add-Failure "MODEL_OUTPUT_SCHEMA" "schema node must be an object at $Location"
        return
    }

    $ForbiddenKeywords = @("allOf", "not", "if", "then", "else", "patternProperties", "oneOf")
    $NodeProperties = @($Node.PSObject.Properties)
    foreach ($entry in $NodeProperties) {
        if ($ForbiddenKeywords -contains $entry.Name -or $entry.Name.StartsWith("dependent", [StringComparison]::Ordinal)) {
            Add-Failure "MODEL_OUTPUT_SCHEMA" "unsupported Structured Outputs keyword at ${Location}: $($entry.Name)"
        }
    }

    $TypeValues = @()
    if (Has-Property $Node "type") { $TypeValues = @(Get-PropertyValue $Node "type") }
    $IsObjectSchema = ($TypeValues -contains "object") -or (Has-Property $Node "properties")
    if ($IsObjectSchema) {
        $SchemaProperties = Get-PropertyValue $Node "properties"
        Assert-True ($SchemaProperties -is [System.Management.Automation.PSCustomObject]) "MODEL_OUTPUT_SCHEMA" "object schema properties must be an object at $Location"
        Assert-True ((Has-Property $Node "additionalProperties") -and (Get-PropertyValue $Node "additionalProperties") -eq $false) "MODEL_OUTPUT_SCHEMA" "additionalProperties must be false at $Location"
        $PropertyNames = @()
        if ($SchemaProperties -is [System.Management.Automation.PSCustomObject]) { $PropertyNames = @($SchemaProperties.PSObject.Properties.Name) }
        $RequiredValue = Get-PropertyValue $Node "required"
        $RequiredNames = @()
        if ($null -ne $RequiredValue) { $RequiredNames = @($RequiredValue) }
        Assert-True ((Has-Property $Node "required") -and $RequiredValue -is [System.Array]) "MODEL_OUTPUT_SCHEMA" "object schema required must be an array at $Location"
        Assert-True ($RequiredNames.Count -eq @($RequiredNames | Sort-Object -Unique).Count -and $RequiredNames.Count -eq $PropertyNames.Count -and (Same-Set -Actual $RequiredNames -Expected $PropertyNames)) "MODEL_OUTPUT_SCHEMA" "every object property must be required exactly once at $Location"
    }

    foreach ($entry in $NodeProperties) {
        if ($entry.Name -in @("properties", '$defs', "definitions")) {
            if ($entry.Value -is [System.Management.Automation.PSCustomObject]) {
                foreach ($child in @($entry.Value.PSObject.Properties)) {
                    Test-ModelOutputSchemaNode $child.Value "$Location/$($entry.Name)/$($child.Name)"
                }
            }
        } elseif ($entry.Value -is [System.Management.Automation.PSCustomObject]) {
            Test-ModelOutputSchemaNode $entry.Value "$Location/$($entry.Name)"
        } elseif ($entry.Value -is [System.Collections.IEnumerable] -and -not ($entry.Value -is [string]) -and $entry.Name -notin @("required", "enum", "examples", "type")) {
            $index = 0
            foreach ($child in @($entry.Value)) {
                if ($child -is [System.Management.Automation.PSCustomObject]) { Test-ModelOutputSchemaNode $child "$Location/$($entry.Name)/$index" }
                $index += 1
            }
        }
    }
}

function Get-ExpectedMediaType([string]$Path) {
    if ($Path.EndsWith(".schema.json", [StringComparison]::Ordinal)) { return "application/schema+json" }
    $MediaByExtension = [ordered]@{
        ".md" = "text/markdown"
        ".csv" = "text/csv"
        ".pdf" = "application/pdf"
        ".yaml" = "application/yaml"
        ".sig" = "application/octet-stream"
        ".txt" = "text/plain"
        ".zip" = "application/zip"
        ".json" = "application/json"
    }
    foreach ($extension in $MediaByExtension.Keys) {
        if ($Path.EndsWith($extension, [StringComparison]::Ordinal)) { return $MediaByExtension[$extension] }
    }
    return $null
}

$NumberedDocs = @(
    "00-source-decision-baseline.md",
    "01-requirements-traceability.md",
    "02-functional-screen-design.md",
    "03-system-architecture-cdd-cdr.md",
    "04-ai-diagnosis-persona-recommendation.md",
    "05-document-ai-hwp-rag.md",
    "06-ai-gateway-model-selection.md",
    "07-data-api-interface-design.md",
    "08-security-privacy-operations.md",
    "09-test-procedure-acceptance.md",
    "10-delivery-implementation-plan.md",
    "11-codex-one-shot-implementation-prompt.md",
    "12-ui-ux-visual-system.md",
    "13-one-command-execution.md",
    "14-final-document-deliverables.md",
    "15-normative-policy-and-interface-contracts.md"
)

$RequiredPackageFiles = @(
    "README.md"
) + $NumberedDocs + @(
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
    "source-traceability.md"
)

$RequiredWorkspaceFiles = @(
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
    "repo-overlay/scripts/tests/test-validate-codex-final-result.ps1"
)

try {
    foreach ($relative in $RequiredPackageFiles) {
        $candidate = Join-Path $PackageRoot $relative
        Assert-True ((Test-Path -LiteralPath $candidate -PathType Leaf) -and (Get-Item -LiteralPath $candidate -ErrorAction SilentlyContinue).Length -gt 0) "CANONICAL_FILES" "missing or empty package file: $relative"
    }
    foreach ($relative in $RequiredWorkspaceFiles) {
        $candidate = Join-Path $WorkRoot $relative
        Assert-True ((Test-Path -LiteralPath $candidate -PathType Leaf) -and (Get-Item -LiteralPath $candidate -ErrorAction SilentlyContinue).Length -gt 0) "CANONICAL_FILES" "missing or empty workspace file: $relative"
    }

    $PowerShellSources = @(
        Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Filter "*.ps1" -ErrorAction Stop
        Get-ChildItem -LiteralPath (Join-Path $WorkRoot "repo-overlay") -Recurse -File -Filter "*.ps1" -ErrorAction Stop
        Get-Item -LiteralPath (Join-Path $WorkRoot "start-ai-training-platform-v1.ps1") -ErrorAction Stop
    ) | Sort-Object -Property FullName -Unique
    $RunnerAst = $null
    foreach ($PowerShellSource in $PowerShellSources) {
        $Tokens = $null
        $ParseErrors = $null
        $Ast = [Management.Automation.Language.Parser]::ParseFile($PowerShellSource.FullName, [ref]$Tokens, [ref]$ParseErrors)
        foreach ($ParseError in @($ParseErrors)) { Add-Failure "RUNTIME_CONTRACT" "PowerShell parse error in $($PowerShellSource.FullName): $($ParseError.Message)" }
        if ($PowerShellSource.FullName -ceq [IO.Path]::GetFullPath((Join-Path $WorkRoot "repo-overlay/scripts/invoke-ai-training-platform-v1.ps1"))) { $RunnerAst = $Ast }
    }
    if ($null -eq $RunnerAst) {
        Add-Failure "RUNTIME_CONTRACT" "guarded runner AST was not loaded"
    } else {
        $DirectRootExits = @($RunnerAst.FindAll({
            param($Node)
            $Node -is [Management.Automation.Language.ExitStatementAst] -and
            $Node.Parent -is [Management.Automation.Language.NamedBlockAst] -and
            $Node.Parent.Parent -is [Management.Automation.Language.ScriptBlockAst] -and
            $null -eq $Node.Parent.Parent.Parent
        }, $true))
        Assert-True ($DirectRootExits.Count -eq 1) "RUNTIME_CONTRACT" "runner must contain exactly one direct root exit at its terminal handoff; unguarded early exits are forbidden"
    }

    $Baseline = Read-Json (Join-Path $PackageRoot "design-baseline.json")
    $DocumentSchema = Read-Json (Join-Path $PackageRoot "document-graph.schema.json")
    $ModelOutputSchema = Read-Json (Join-Path $PackageRoot "codex-output.schema.json")
    $ResultSchema = Read-Json (Join-Path $PackageRoot "codex-final-result.schema.json")
    $FinalDocumentInventory = Read-Json (Join-Path $PackageRoot "final-document-inventory.json")
    $OverlayManifest = Read-Json (Join-Path $WorkRoot "overlay-manifest.json")
    foreach ($relative in @(
        "requirements-test-registry.json", "screen-route-contracts.json", "kpi-005-structured-output-matrix.json",
        "diagnosis-scoring-golden-vectors.json", "artifact-manifest.schema.json", "evidence-index.schema.json",
        "source-tree-hash-golden-vector.json", "fixtures/artifact-manifest.valid.json", "fixtures/artifact-manifest.invalid.json",
        "fixtures/evidence-index.valid.json", "fixtures/evidence-index.invalid.json"
    )) {
        Read-Json (Join-Path $PackageRoot $relative) | Out-Null
    }

    $PythonCommand = $null
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) {
        if ([IO.Path]::IsPathRooted($PythonPath) -and (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
            $PythonCommand = [IO.Path]::GetFullPath($PythonPath)
        } else {
            Add-Failure "RUNTIME_CONTRACT" "explicit PythonPath must be an existing absolute file"
        }
    } else {
        $PythonInfo = Get-Command python3 -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $PythonInfo) { $PythonInfo = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if ($null -ne $PythonInfo) { $PythonCommand = $PythonInfo.Source }
    }
    Invoke-PythonGate $PythonCommand "RUNTIME_CONTRACT" (Join-Path $WorkRoot "generate-overlay-manifest.py") @("--root", $WorkRoot, "--check")
    Invoke-PythonGate $PythonCommand "COMPLETENESS_CONTRACTS" (Join-Path $PackageRoot "verify-completeness-contracts.py") @("--root", $PackageRoot)
    Invoke-PythonGate $PythonCommand "SOURCE_TRACEABILITY" (Join-Path $PackageRoot "verify-source-traceability.py") @("--root", $PackageRoot)
    Invoke-PythonGate $PythonCommand "MACHINE_CONTRACTS" (Join-Path $PackageRoot "verify-machine-contracts.py") @("--package-root", $PackageRoot)
    Invoke-PythonGate $PythonCommand "NORMATIVE_TEST_SEMANTICS" (Join-Path $PackageRoot "verify-normative-test-semantics.py") @("--package-root", $PackageRoot)
    Invoke-PythonGate $PythonCommand "SEMANTIC_DEPTH_CONTRACTS" (Join-Path $PackageRoot "verify-semantic-depth-contracts.py") @("--base-dir", $PackageRoot)
    Invoke-PythonGate $PythonCommand "AI_GATEWAY_SAFEGUARDING" (Join-Path $PackageRoot "verify-ai-gateway-safeguarding.py") @("--package-root", $PackageRoot)
    Invoke-PythonGate $PythonCommand "TCH_015_AUTHORIZATION" (Join-Path $PackageRoot "verify-tch-015-authorization.py") @("--package-root", $PackageRoot)

    foreach ($schemaEntry in @(
        @("document-graph.schema.json", $DocumentSchema),
        @("codex-final-result.schema.json", $ResultSchema)
    )) {
        if ($null -ne $schemaEntry[1]) {
            Assert-True ((Get-PropertyValue $schemaEntry[1] '$schema') -ceq "https://json-schema.org/draft/2020-12/schema") "JSON_PARSE" "$($schemaEntry[0]) must declare JSON Schema 2020-12"
        }
    }
    if ($null -ne $ModelOutputSchema) { Test-ModelOutputSchemaNode $ModelOutputSchema '$' }

    $Traceability = Read-Text (Join-Path $PackageRoot "01-requirements-traceability.md")
    $RfpExpected = [ordered]@{ PLR = 4; ECR = 2; DER = 8; SIR = 3; DAR = 7; TER = 4; SER = 8; QUR = 5; COR = 6; PMR = 8; PSR = 5 }
    $RfpIds = @(Get-MatchValues $Traceability '(?m)^\|\s*((?:PLR|ECR|DER|SIR|DAR|TER|SER|QUR|COR|PMR|PSR)-\d{3})\s*\|')
    Assert-True ($RfpIds.Count -eq 60 -and @($RfpIds | Sort-Object -Unique).Count -eq 60) "REQUIREMENT_COUNTS" "RFP inventory must contain 60 unique rows; found $($RfpIds.Count)"
    foreach ($prefix in $RfpExpected.Keys) {
        $actualCount = @($RfpIds | Where-Object { $_.StartsWith("$prefix-") }).Count
        Assert-True ($actualCount -eq $RfpExpected[$prefix]) "REQUIREMENT_COUNTS" "$prefix must contain $($RfpExpected[$prefix]) rows; found $actualCount"
    }
    $SysF = @(Get-MatchValues $Traceability '(?m)^\|\s*(SYS-F-\d{3})\s*\|')
    $SysNf = @(Get-MatchValues $Traceability '(?m)^\|\s*(SYS-NF-\d{3})\s*\|')
    $ExpectedSysF = @(1..18 | ForEach-Object { "SYS-F-{0:D3}" -f $_ })
    $ExpectedSysNf = @(1..15 | ForEach-Object { "SYS-NF-{0:D3}" -f $_ })
    Assert-True (Same-Sequence -Actual $SysF -Expected $ExpectedSysF) "REQUIREMENT_COUNTS" "SYS-F inventory must be exactly SYS-F-001 through SYS-F-018"
    Assert-True (Same-Sequence -Actual $SysNf -Expected $ExpectedSysNf) "REQUIREMENT_COUNTS" "SYS-NF inventory must be exactly SYS-NF-001 through SYS-NF-015"

    $ExpectedDocumentIds = [ordered]@{
        "00-source-decision-baseline.md" = "SRC-CDR-000"
        "01-requirements-traceability.md" = "REQ-BASELINE-001"
        "02-functional-screen-design.md" = "UX-IA-002"
        "03-system-architecture-cdd-cdr.md" = "ARCH-CDR-003"
        "04-ai-diagnosis-persona-recommendation.md" = "AI-DIAG-004"
        "05-document-ai-hwp-rag.md" = "DOC-AI-005"
        "06-ai-gateway-model-selection.md" = "AI-GW-006"
        "07-data-api-interface-design.md" = "DATA-ICD-007"
        "08-security-privacy-operations.md" = "SEC-OPS-008"
        "09-test-procedure-acceptance.md" = "VER-ATP-009"
        "10-delivery-implementation-plan.md" = "PLAN-180D-010"
        "11-codex-one-shot-implementation-prompt.md" = "CODEX-EXEC-011"
        "12-ui-ux-visual-system.md" = "UX-VIS-012"
        "13-one-command-execution.md" = "CODEX-RUN-013"
        "14-final-document-deliverables.md" = "DEL-CONTRACT-014"
        "15-normative-policy-and-interface-contracts.md" = "NORM-CONTRACT-015"
        "REVIEW-CHANGELOG-v1.1.md" = "REVIEW-CHANGELOG-011"
    }
    $SeenDocumentIds = @{}
    foreach ($relative in $ExpectedDocumentIds.Keys) {
        $body = Read-Text (Join-Path $PackageRoot $relative)
        $matches = @(Get-MatchValues $body '(?m)^문서 ID:\s*([^\s]+)\s*$')
        Assert-True ($matches.Count -eq 1) "DOCUMENT_IDS" "$relative must contain exactly one document ID"
        if ($matches.Count -eq 1) {
            $actual = $matches[0]
            Assert-True ($actual -ceq $ExpectedDocumentIds[$relative]) "DOCUMENT_IDS" "$relative document ID must be $($ExpectedDocumentIds[$relative]); found $actual"
            if ($SeenDocumentIds.ContainsKey($actual)) {
                Add-Failure "DOCUMENT_IDS" "duplicate document ID ${actual}: $($SeenDocumentIds[$actual]) and $relative"
            } else {
                $SeenDocumentIds[$actual] = $relative
            }
        }
    }

    $MarkdownFiles = @((Join-Path $PackageRoot "README.md")) + @($NumberedDocs | ForEach-Object { Join-Path $PackageRoot $_ }) + @(
        (Join-Path $PackageRoot "REVIEW-CHANGELOG-v1.1.md"),
        (Join-Path $WorkRoot "AI-Gateway-UniClaudeProxy-Reuse-Design.md")
    )
    foreach ($markdown in $MarkdownFiles) {
        $body = Read-Text $markdown
        $fenceCount = @($body -split "`r?`n" | Where-Object { $_ -match '^\s*```' }).Count
        Assert-True (($fenceCount % 2) -eq 0) "MARKDOWN_STRUCTURE" "unbalanced code fences: $markdown"
        if ([IO.Path]::GetFileName($markdown) -cne "11-codex-one-shot-implementation-prompt.md") {
            Assert-True ($body -notmatch '(?i)\b(?:TBD|TODO|FIXME|implement later|fill in details)\b') "MARKDOWN_STRUCTURE" "unresolved placeholder: $markdown"
        }
        foreach ($match in [regex]::Matches($body, '!?\[[^\]]*\]\(([^)]+)\)')) {
            $target = $match.Groups[1].Value.Trim()
            if ($target.StartsWith('<') -and $target.EndsWith('>')) { $target = $target.Substring(1, $target.Length - 2) }
            if ($target -match '^(?:https?://|mailto:|#)') { continue }
            $target = ($target -split '#', 2)[0]
            if ([string]::IsNullOrWhiteSpace($target)) { continue }
            if ($target.Contains(' "') -or $target.Contains((' ' + [char]39))) { $target = ($target -split ' ', 2)[0] }
            $target = [Uri]::UnescapeDataString($target)
            $targetPath = Join-Path (Split-Path -Parent $markdown) $target
            Assert-True (Test-Path -LiteralPath $targetPath) "MARKDOWN_STRUCTURE" "broken relative link $markdown -> $($match.Groups[1].Value)"
        }
    }

    $ExpectedRoot = 'D:\Views\yonlab-inuri-site'
    $ExpectedRemote = 'https://github.com/yubi-lee/yonlab-i-nuri-site.git'
    $ExpectedBranch = 'feat/ai-training-platform-v1'
    $ExpectedRoots = [ordered]@{
        planning_source = "docs/planning/ai-training-platform-v1/"
        final_design = "docs/design/ai-training-platform/"
        operations = "docs/operations/ai-training-platform/"
        quality_assurance = "docs/qa/ai-training-platform/"
        manuals = "docs/manuals/ai-training-platform/"
        releases = "docs/releases/ai-training-platform/"
        distribution_docs = "dist/docs/"
    }

    if ($null -ne $Baseline) {
        Assert-True ($Baseline.baseline_id -ceq "YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1") "CANONICAL_COORDINATES" "baseline_id drift"
        Assert-True ($Baseline.normative_source_path -ceq "docs/planning/ai-training-platform-v1/design-baseline.json") "CANONICAL_COORDINATES" "normative source path drift"
        Assert-True ($Baseline.repository.windows_root -ceq $ExpectedRoot) "CANONICAL_COORDINATES" "canonical Windows root drift"
        Assert-True ($Baseline.repository.remote_name -ceq "origin" -and $Baseline.repository.remote -ceq $ExpectedRemote) "CANONICAL_COORDINATES" "canonical origin drift"
        Assert-True ($Baseline.repository.work_branch -ceq $ExpectedBranch -and $Baseline.repository.base_branch_heuristic_allowed -eq $false) "CANONICAL_COORDINATES" "deterministic work branch drift"

        foreach ($rootName in $ExpectedRoots.Keys) {
            Assert-True ((Get-PropertyValue $Baseline.artifact_roots $rootName) -ceq $ExpectedRoots[$rootName]) "FINAL_OUTPUT_ROOTS" "artifact root drift: $rootName"
        }
        Assert-True (@($Baseline.artifact_roots.PSObject.Properties).Count -eq $ExpectedRoots.Count) "FINAL_OUTPUT_ROOTS" "artifact root inventory drift"

        $ExpectedKpis = [ordered]@{
            "KPI-001" = @(">=", "minimum", 0.85, $true)
            "KPI-002" = @(">=", "minimum", 0.90, $true)
            "KPI-003" = @(">=", "minimum", 0.95, $false)
            "KPI-004" = @(">=", "minimum", 0.95, $false)
            "KPI-005" = @(">=", "minimum", 0.998, $false)
            "KPI-006" = @(">=", "minimum", 90, $true)
            "KPI-007" = @(">=", "minimum", 0.90, $true)
            "KPI-008" = @("<=", "maximum", 0, $false)
            "KPI-009" = @("<=", "maximum", 0, $false)
            "KPI-010" = @(">=", "minimum", 1.0, $true)
        }
        $Kpis = @($Baseline.kpis)
        Assert-True (Same-Sequence -Actual @($Kpis | ForEach-Object { $_.id }) -Expected @($ExpectedKpis.Keys)) "KPI_THRESHOLDS" "KPI IDs/order must be KPI-001 through KPI-010"
        foreach ($kpi in $Kpis) {
            if (-not $ExpectedKpis.Contains($kpi.id)) { continue }
            $spec = $ExpectedKpis[$kpi.id]
            $thresholdField = [string]$spec[1]
            $thresholdValue = Get-PropertyValue $kpi $thresholdField
            Assert-True ($kpi.comparison -ceq $spec[0] -and (Has-Property $kpi $thresholdField) -and [double]$thresholdValue -eq [double]$spec[2]) "KPI_THRESHOLDS" "$($kpi.id) threshold drift"
            Assert-True ($kpi.acceptance_data_required -eq [bool]$spec[3]) "KPI_THRESHOLDS" "$($kpi.id) acceptance-data classification drift"
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$kpi.formula)) "KPI_THRESHOLDS" "$($kpi.id) formula is missing"
        }
        $Kpi4 = @($Kpis | Where-Object { $_.id -ceq "KPI-004" } | Select-Object -First 1)
        Assert-True ($Kpi4.Count -eq 1 -and $Kpi4[0].invalid_citation_maximum -eq 0) "KPI_THRESHOLDS" "KPI-004 invalid citation maximum must be 0"

        $Families = @($Baseline.persona_hierarchy.families)
        $Profiles = @($Families | ForEach-Object { @($_.profiles) })
        $ExpectedProfileOrder = @(1..6 | ForEach-Object { "P-{0:D2}-A" -f $_; "P-{0:D2}-B" -f $_ })
        Assert-True ($Baseline.persona_hierarchy.family_count -eq 6 -and $Families.Count -eq 6) "PERSONA_HIERARCHY" "persona family count must be 6"
        Assert-True ($Baseline.persona_hierarchy.operational_profile_count -eq 12 -and $Profiles.Count -eq 12) "PERSONA_HIERARCHY" "operational profile count must be 12"
        Assert-True (Same-Sequence -Actual @($Profiles | ForEach-Object { $_.profile_id }) -Expected $ExpectedProfileOrder) "PERSONA_HIERARCHY" "operational profile IDs/order drift"
        Assert-True (@($Profiles | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.version) }).Count -eq 0) "PERSONA_HIERARCHY" "every operational profile must be versioned"
        $Inference = $Baseline.persona_hierarchy.inference_contract
        Assert-True ($Inference.profile_probability_count -eq 12 -and $Inference.family_aggregation_count -eq 6) "PERSONA_HIERARCHY" "persona inference output counts drift"
        Assert-True (Same-Sequence -Actual @($Inference.profile_output_order) -Expected $ExpectedProfileOrder) "PERSONA_HIERARCHY" "persona probability output order drift"
        Assert-True ([double]$Inference.profile_probability_sum -eq 1.0 -and [double]$Inference.family_probability_sum -eq 1.0) "PERSONA_HIERARCHY" "persona probability sums must equal 1"
        Assert-True ([double]$Inference.mixed_or_undetermined_threshold -eq 0.45) "PERSONA_HIERARCHY" "mixed/undetermined threshold drift"

        $ExpectedDataDefaults = [ordered]@{
            unknown_teacher_free_text = "RESTRICTED"
            unclassified_raw_or_scanned_upload = "RESTRICTED"
            external_ai_egress_before_classification_and_policy_authorization = "DENY"
        }
        foreach ($name in $ExpectedDataDefaults.Keys) {
            Assert-True ((Get-PropertyValue $Baseline.data_policy_defaults $name) -ceq $ExpectedDataDefaults[$name]) "DATA_POLICY" "data policy default drift: $name"
        }
        Assert-True (@($Baseline.data_policy_defaults.PSObject.Properties).Count -eq $ExpectedDataDefaults.Count) "DATA_POLICY" "unknown/raw data fail-closed default inventory drift"

        $ExpectedEvidenceStatuses = @("PASS", "FAIL", "BLOCKED", "REQUIRES_ACCEPTANCE_DATA")
        $ExpectedReleaseStates = @("NOT_READY", "CODE_COMPLETE / ACCEPTANCE DATA PENDING", "ACCEPTED")
        $ExpectedBlocking = @("FAIL", "BLOCKED", "MISSING", "STALE")
        Assert-True (Same-Sequence -Actual @($Baseline.status_model.evidence_statuses) -Expected $ExpectedEvidenceStatuses) "RELEASE_STATES" "evidence status vocabulary drift"
        Assert-True (Same-Sequence -Actual @($Baseline.status_model.release_states) -Expected $ExpectedReleaseStates) "RELEASE_STATES" "release state vocabulary drift"
        Assert-True (Same-Sequence -Actual @($Baseline.status_model.blocking_evidence_conditions) -Expected $ExpectedBlocking) "RELEASE_STATES" "blocking evidence conditions drift"
        $Rules = @{}
        foreach ($rule in @($Baseline.status_model.rules)) { $Rules[[string]$rule.release_state] = [string]$rule.when }
        Assert-True (Same-Set -Actual @($Rules.Keys) -Expected $ExpectedReleaseStates) "RELEASE_STATES" "release transition rule inventory drift"
        Assert-True ($Rules["NOT_READY"] -match '(?i)fail' -and $Rules["NOT_READY"] -match '(?i)blocked' -and $Rules["NOT_READY"] -match '(?i)missing' -and $Rules["NOT_READY"] -match '(?i)stale') "RELEASE_STATES" "NOT_READY rule must block FAIL/BLOCKED/missing/stale"
        Assert-True ($Rules["CODE_COMPLETE / ACCEPTANCE DATA PENDING"] -cmatch 'REQUIRES_ACCEPTANCE_DATA') "RELEASE_STATES" "pending rule must require acceptance data"
        Assert-True ($Rules["ACCEPTED"] -cmatch 'every required gate is PASS with fresh evidence') "RELEASE_STATES" "ACCEPTED rule must require every gate fresh PASS"
        Assert-True ($Baseline.recovery_objectives.acceptance_status -ceq "REQUIRES_ACCEPTANCE_DATA") "RELEASE_STATES" "recovery acceptance status drift"
        Assert-True ($Baseline.recovery_objectives.release_state_ceiling_before_acceptance -ceq "CODE_COMPLETE / ACCEPTANCE DATA PENDING") "RELEASE_STATES" "acceptance-data release ceiling drift"
        Assert-True ($Baseline.recovery_objectives.acceptance_rule -ceq "Each target requires institution approval and fresh isolated-drill PASS evidence before KPI-010 can PASS.") "RELEASE_STATES" "recovery acceptance rule drift"
        $ExpectedGateIds = @(
            "GATE-DESIGN-INTEGRITY", "GATE-CODE-QUALITY", "GATE-SECURITY-PRIVACY", "GATE-AI-KPI",
            "GATE-DOCUMENT-KPI", "GATE-UX-ACCESSIBILITY", "GATE-OPERATIONS-RECOVERY", "GATE-PILOT-ACCEPTANCE"
        )
        Assert-True (Same-Sequence -Actual @($Baseline.release_gates | ForEach-Object { $_.id }) -Expected $ExpectedGateIds) "RELEASE_STATES" "release gate inventory/order drift"
        Assert-True ($Baseline.launcher_policy.sandbox -ceq "workspace-write" -and $Baseline.launcher_policy.approval_policy -ceq "on-request") "ACTIVE_SAFETY" "launcher sandbox/approval drift"
        Assert-True (Same-Set -Actual @($Baseline.launcher_policy.forbidden_flags) -Expected @("--dangerously-bypass-approvals-and-sandbox", "--yolo")) "ACTIVE_SAFETY" "launcher forbidden flag policy drift"
    }

    $MirroredPlanningRoots = @(
        "docs/planning/ai-training-platform-v1/", "docs/design/ai-training-platform/", "docs/operations/ai-training-platform/",
        "docs/qa/ai-training-platform/", "docs/manuals/ai-training-platform/", "docs/releases/ai-training-platform/", "dist/docs/"
    )
    foreach ($relative in @("10-delivery-implementation-plan.md", "14-final-document-deliverables.md")) {
        $body = Read-Text (Join-Path $PackageRoot $relative)
        foreach ($requiredRoot in $MirroredPlanningRoots) {
            Assert-True ($body.Contains([string]$requiredRoot)) "FINAL_OUTPUT_ROOTS" "$relative does not mirror root $requiredRoot"
        }
    }

    $Deliverables = Read-Text (Join-Path $PackageRoot "14-final-document-deliverables.md")
    $ExpectedOwners = @("OWN-ARCH", "OWN-PROD", "OWN-UX", "OWN-AI", "OWN-DOC", "OWN-DATA", "OWN-SEC", "OWN-OPS", "OWN-QA", "OWN-ACC")
    $RegisteredOwners = @(Get-MatchValues $Deliverables '(?m)^\|\s*`(OWN-[A-Z]+)`\s*\|' | Sort-Object -Unique)
    Assert-True (Same-Set -Actual $RegisteredOwners -Expected $ExpectedOwners) "RUNBOOK_INVENTORY" "owner registry must contain the 10 canonical OWN-* IDs"

    $RunbookRows = [ordered]@{}
    $RunbookRowCount = 0
    foreach ($line in ($Deliverables -split "`r?`n")) {
        if ($line -notmatch '^\|\s*RB-\d{3}\s*\|') { continue }
        $RunbookRowCount += 1
        $columns = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($columns.Count -ne 7) {
            Add-Failure "RUNBOOK_INVENTORY" "runbook row must have 7 columns: $line"
            continue
        }
        if ($RunbookRows.Contains($columns[0])) { Add-Failure "RUNBOOK_INVENTORY" "duplicate runbook ID: $($columns[0])" }
        $RunbookRows[$columns[0]] = $columns
    }
    $ExpectedRunbookIds = @(1..23 | ForEach-Object { "RB-{0:D3}" -f $_ })
    Assert-True ($RunbookRowCount -eq 23 -and (Same-Sequence -Actual @($RunbookRows.Keys) -Expected $ExpectedRunbookIds)) "RUNBOOK_INVENTORY" "runbook inventory must be exactly RB-001 through RB-023"
    $BaselineGateIds = @()
    if ($null -ne $Baseline) { $BaselineGateIds = @($Baseline.release_gates | ForEach-Object { $_.id }) }
    $RunbookFiles = @()
    foreach ($runbookId in $RunbookRows.Keys) {
        $columns = $RunbookRows[$runbookId]
        $filenameMatch = [regex]::Match($columns[1], '^`([^`]+\.md)`$')
        Assert-True $filenameMatch.Success "RUNBOOK_INVENTORY" "$runbookId must define one Markdown filename"
        if ($filenameMatch.Success) { $RunbookFiles += $filenameMatch.Groups[1].Value }
        $ownerIds = @(Get-MatchValues $columns[3] '(OWN-[A-Z]+)' | Sort-Object -Unique)
        Assert-True ($ownerIds.Count -ge 2 -and @($ownerIds | Where-Object { $RegisteredOwners -notcontains $_ }).Count -eq 0) "RUNBOOK_INVENTORY" "$runbookId owner/escalation IDs are incomplete or unregistered"
        $cadenceParts = @($columns[4] -split '/', 2)
        Assert-True ($cadenceParts.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($cadenceParts[0]) -and -not [string]::IsNullOrWhiteSpace($cadenceParts[1])) "RUNBOOK_INVENTORY" "$runbookId must define cadence and dependency fingerprint"
        $gateIds = @(Get-MatchValues $columns[6] '(GATE-[A-Z-]+)' | Sort-Object -Unique)
        Assert-True ($gateIds.Count -gt 0 -and @($gateIds | Where-Object { $BaselineGateIds -notcontains $_ }).Count -eq 0) "RUNBOOK_INVENTORY" "$runbookId gate IDs are missing or unknown"
    }
    Assert-True ($RunbookFiles.Count -eq 23 -and @($RunbookFiles | Sort-Object -Unique).Count -eq 23) "RUNBOOK_INVENTORY" "runbook filenames must be 23 unique Markdown paths"

    $RequiredDualGates = [ordered]@{
        "RB-007" = @("GATE-DOCUMENT-KPI", "GATE-OPERATIONS-RECOVERY")
        "RB-010" = @("GATE-SECURITY-PRIVACY", "GATE-OPERATIONS-RECOVERY")
        "RB-011" = @("GATE-AI-KPI", "GATE-SECURITY-PRIVACY", "GATE-OPERATIONS-RECOVERY")
        "RB-014" = @("GATE-DOCUMENT-KPI", "GATE-SECURITY-PRIVACY", "GATE-OPERATIONS-RECOVERY")
    }
    foreach ($runbookId in $RequiredDualGates.Keys) {
        $actualGates = @()
        if ($RunbookRows.Contains($runbookId)) { $actualGates = @(Get-MatchValues $RunbookRows[$runbookId][6] '(GATE-[A-Z-]+)') }
        Assert-True (@($RequiredDualGates[$runbookId] | Where-Object { $actualGates -notcontains $_ }).Count -eq 0) "RUNBOOK_INVENTORY" "$runbookId cross-gate coverage drift"
    }

    $RequiredRunbookSections = @(
        "## Owner와 escalation", "## 목적·trigger·영향", "## 사전조건", "## copy-paste 명령", "## 예상 출력",
        "## 단계별 validation", "## 중단·rollback 기준", "## escalation과 통지", "## 증거 보존", "## 마지막 drill"
    )
    foreach ($heading in $RequiredRunbookSections) {
        $needle = ([char]96).ToString() + $heading + ([char]96).ToString()
        Assert-True ([regex]::Matches($Deliverables, [regex]::Escape($needle)).Count -eq 1) "RUNBOOK_INVENTORY" "required runbook section must appear exactly once: $heading"
    }
    foreach ($token in @("cadence_due_at_utc", "candidate_bound", "dependency_fingerprint_algorithm", "dependency_fingerprint", "tested_image_digests[]")) {
        Assert-True $Deliverables.Contains($token) "RUNBOOK_INVENTORY" "runbook freshness field missing: $token"
    }

    $ManualPairs = @()
    foreach ($line in ($Deliverables -split "`r?`n")) {
        $match = [regex]::Match($line, '^\|\s*`([^`]+\.md)`\s*\|\s*`([^`]+\.pdf)`\s*\|')
        if ($match.Success) { $ManualPairs += ,@($match.Groups[1].Value, $match.Groups[2].Value) }
    }
    $ExpectedManualStems = @("teacher-user-guide", "institution-admin-guide", "content-reviewer-guide", "system-admin-guide", "security-auditor-guide", "operations-operator-guide", "accessibility-and-support-guide", "quick-start")
    Assert-True ($ManualPairs.Count -eq 8) "MANUAL_PAIRS" "manual inventory must contain 8 Markdown/PDF pairs; found $($ManualPairs.Count)"
    $ActualManualStems = @($ManualPairs | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_[0]) })
    Assert-True (Same-Set -Actual $ActualManualStems -Expected $ExpectedManualStems) "MANUAL_PAIRS" "manual Markdown inventory drift"
    foreach ($pair in $ManualPairs) {
        Assert-True ([IO.Path]::GetFileNameWithoutExtension($pair[0]) -ceq [IO.Path]::GetFileNameWithoutExtension($pair[1])) "MANUAL_PAIRS" "every manual PDF must have the same basename as its Markdown source"
    }

    if ($null -ne $FinalDocumentInventory) {
        $ExpectedInventoryKeys = @("schema_version", "baseline_id", "canonical_contract", "release_id_pattern", "dynamic_segment_contract", "roots", "expected_counts", "manual_combination_contract", "artifacts")
        Assert-True (Same-Set -Actual @($FinalDocumentInventory.PSObject.Properties.Name) -Expected $ExpectedInventoryKeys) "FINAL_DOCUMENT_INVENTORY" "final document inventory top-level key contract drift"
        $ExpectedReleasePattern = '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(alpha|beta|rc)(0|[1-9][0-9]*))?$'
        Assert-True ($FinalDocumentInventory.schema_version -ceq "final-document-inventory.v1") "FINAL_DOCUMENT_INVENTORY" "final document inventory schema version drift"
        Assert-True ($FinalDocumentInventory.baseline_id -ceq "YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1") "FINAL_DOCUMENT_INVENTORY" "final document inventory baseline ID drift"
        Assert-True ($FinalDocumentInventory.release_id_pattern -ceq $ExpectedReleasePattern) "FINAL_DOCUMENT_INVENTORY" "final document inventory release ID pattern drift"
        if ($null -ne $Baseline) {
            Assert-True ($Baseline.release_identifier_policy.regex -ceq $ExpectedReleasePattern) "FINAL_DOCUMENT_INVENTORY" "baseline release ID pattern drift"
        }
        Assert-True ($FinalDocumentInventory.dynamic_segment_contract.only_placeholder -ceq '${release_id}') "FINAL_DOCUMENT_INVENTORY" 'only ${release_id} may be dynamic'
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$FinalDocumentInventory.dynamic_segment_contract.expansion_rule) -and -not [string]::IsNullOrWhiteSpace([string]$FinalDocumentInventory.dynamic_segment_contract.containment_rule)) "FINAL_DOCUMENT_INVENTORY" "dynamic segment expansion/containment rules are missing"

        $ExpectedInventoryRoots = [ordered]@{
            final_design = "docs/design/ai-training-platform/"
            operations = "docs/operations/ai-training-platform/"
            quality_assurance = "docs/qa/ai-training-platform/"
            manuals = "docs/manuals/ai-training-platform/"
            releases = "docs/releases/ai-training-platform/"
            distribution_docs = "dist/docs/"
        }
        Assert-True (@($FinalDocumentInventory.roots.PSObject.Properties).Count -eq $ExpectedInventoryRoots.Count) "FINAL_DOCUMENT_INVENTORY" "final document root registry inventory drift"
        foreach ($rootId in $ExpectedInventoryRoots.Keys) {
            Assert-True ((Get-PropertyValue $FinalDocumentInventory.roots $rootId) -ceq $ExpectedInventoryRoots[$rootId]) "FINAL_DOCUMENT_INVENTORY" "final document root registry drift: $rootId"
            if ($null -ne $Baseline) {
                Assert-True ((Get-PropertyValue $Baseline.artifact_roots $rootId) -ceq $ExpectedInventoryRoots[$rootId]) "FINAL_DOCUMENT_INVENTORY" "inventory root must match the baseline byte-for-byte: $rootId"
            }
        }

        $ExpectedInventoryCounts = [ordered]@{
            design = 48
            operations = 11
            runbook = 23
            qa = 18
            manual_markdown = 8
            manual_pdf = 8
            release = 10
            distribution = 21
            total = 147
        }
        Assert-True (@($FinalDocumentInventory.expected_counts.PSObject.Properties).Count -eq $ExpectedInventoryCounts.Count) "FINAL_DOCUMENT_INVENTORY" "final document expected-count inventory drift"
        foreach ($group in $ExpectedInventoryCounts.Keys) {
            Assert-True ((Get-PropertyValue $FinalDocumentInventory.expected_counts $group) -eq $ExpectedInventoryCounts[$group]) "FINAL_DOCUMENT_INVENTORY" "final document expected count drift: $group"
        }
        $Artifacts = @($FinalDocumentInventory.artifacts)
        Assert-True ($Artifacts.Count -eq $ExpectedInventoryCounts["total"]) "FINAL_DOCUMENT_INVENTORY" "final document inventory must contain $($ExpectedInventoryCounts['total']) artifacts"
        foreach ($group in @($ExpectedInventoryCounts.Keys | Where-Object { $_ -cne "total" })) {
            $actualCount = @($Artifacts | Where-Object { $_.group -ceq $group }).Count
            Assert-True ($actualCount -eq $ExpectedInventoryCounts[$group]) "FINAL_DOCUMENT_INVENTORY" "final document group $group must contain $($ExpectedInventoryCounts[$group]) artifacts; found $actualCount"
        }

        $ArtifactIds = @()
        $ContainedPaths = @()
        $ExpectedArtifactKeys = @("artifact_id", "group", "root_id", "root_path", "relative_path_template", "owner_ids", "gate_ids", "media_type", "source_kind", "required")
        $ExpectedSourceKinds = [ordered]@{
            design = @("authored_markdown", "machine_contract", "verified_machine_contract", "generated_contract", "golden_vector")
            operations = @("authored_markdown")
            runbook = @("authored_runbook")
            qa = @("generated_report", "generated_trace")
            manual_markdown = @("authored_manual")
            manual_pdf = @("generated_accessible_pdf")
            release = @("authored_markdown", "generated_manifest", "detached_signature", "checksum_catalog")
            distribution = @("generated_accessible_pdf", "generated_trace", "generated_evidence_index", "generated_manifest", "detached_signature", "checksum_catalog", "source_snapshot", "copied_verified_manual_pdf")
        }
        $ReservedWindowsNames = @("CON", "PRN", "AUX", "NUL") + @(1..9 | ForEach-Object { "COM$_"; "LPT$_" })
        for ($index = 0; $index -lt $Artifacts.Count; $index += 1) {
            $artifact = $Artifacts[$index]
            $location = "artifacts[$index]"
            Assert-True (Same-Set -Actual @($artifact.PSObject.Properties.Name) -Expected $ExpectedArtifactKeys) "FINAL_DOCUMENT_INVENTORY" "$location artifact key contract drift"
            $artifactId = [string](Get-PropertyValue $artifact "artifact_id")
            $group = [string](Get-PropertyValue $artifact "group")
            $ArtifactIds += $artifactId
            Assert-True ($artifactId -cmatch '^FDI-[A-Z]+(?:-[A-Z]+)*-[0-9]{3}$') "FINAL_DOCUMENT_INVENTORY" "invalid artifact ID at ${location}: $artifactId"
            Assert-True ((Get-PropertyValue $artifact "required") -eq $true) "FINAL_DOCUMENT_INVENTORY" "$artifactId must be required"
            $rootId = [string](Get-PropertyValue $artifact "root_id")
            $rootPath = [string](Get-PropertyValue $artifact "root_path")
            Assert-True ($ExpectedInventoryRoots.Contains($rootId) -and $rootPath -ceq $ExpectedInventoryRoots[$rootId]) "FINAL_DOCUMENT_INVENTORY" "$artifactId root registry mismatch"

            $relative = [string](Get-PropertyValue $artifact "relative_path_template")
            $Placeholders = @([regex]::Matches($relative, '\$\{[^}]*\}') | ForEach-Object { $_.Value })
            Assert-True (@($Placeholders | Where-Object { $_ -cne '${release_id}' }).Count -eq 0 -and @($Placeholders | Where-Object { $_ -ceq '${release_id}' }).Count -le 1) "FINAL_DOCUMENT_INVENTORY" "$artifactId uses an unsafe dynamic placeholder"
            $StaticRemainder = $relative.Replace('${release_id}', '')
            Assert-True ($StaticRemainder -notmatch '[$%\\:]' -and $StaticRemainder.IndexOf([char]0) -lt 0) "FINAL_DOCUMENT_INVENTORY" "$artifactId contains unsafe path expansion syntax"
            $Expanded = $relative.Replace('${release_id}', 'v1.0.0')
            $TemplateParts = @($relative -split '/')
            $PlaceholderSegmentCount = @($TemplateParts | Where-Object { $_ -ceq '${release_id}' }).Count
            if ($group -in @("release", "distribution")) {
                Assert-True ($PlaceholderSegmentCount -eq 1 -and $TemplateParts.Count -gt 0 -and $TemplateParts[0] -ceq '${release_id}') "FINAL_DOCUMENT_INVENTORY" "$artifactId must use release_id exactly once as its first path segment"
            } else {
                Assert-True ($PlaceholderSegmentCount -eq 0) "FINAL_DOCUMENT_INVENTORY" "$artifactId must not use a dynamic release segment"
            }
            $RelativeParts = @($Expanded -split '/')
            $HasUnsafePart = @($RelativeParts | Where-Object { [string]::IsNullOrEmpty($_) -or $_ -ceq '.' -or $_ -ceq '..' }).Count -gt 0
            Assert-True (-not [string]::IsNullOrWhiteSpace($Expanded) -and -not [IO.Path]::IsPathRooted($Expanded) -and $Expanded -notmatch '^[A-Za-z]:[\\/]' -and -not $HasUnsafePart) "FINAL_DOCUMENT_INVENTORY" "$artifactId path is not root-contained"
            foreach ($segment in $RelativeParts) {
                $DeviceStem = ($segment -split '\.', 2)[0].ToUpperInvariant()
                Assert-True ($segment.Normalize([Text.NormalizationForm]::FormC) -ceq $segment) "FINAL_DOCUMENT_INVENTORY" "$artifactId path segment is not NFC-normalized"
                Assert-True (@($segment.ToCharArray() | Where-Object { [char]::IsControl($_) }).Count -eq 0) "FINAL_DOCUMENT_INVENTORY" "$artifactId path segment contains a control character"
                Assert-True (-not $segment.EndsWith(".", [StringComparison]::Ordinal) -and -not $segment.EndsWith(" ", [StringComparison]::Ordinal) -and $ReservedWindowsNames -notcontains $DeviceStem) "FINAL_DOCUMENT_INVENTORY" "$artifactId path segment is unsafe on Windows"
            }
            $ContainedPaths += "$rootId|$relative"

            $OwnerIds = @((Get-PropertyValue $artifact "owner_ids"))
            $GateIds = @((Get-PropertyValue $artifact "gate_ids"))
            Assert-True ($OwnerIds.Count -gt 0 -and $OwnerIds.Count -eq @($OwnerIds | Sort-Object -Unique).Count -and @($OwnerIds | Where-Object { $RegisteredOwners -notcontains $_ }).Count -eq 0) "FINAL_DOCUMENT_INVENTORY" "$artifactId owner IDs are empty, duplicate, or unregistered"
            Assert-True ($GateIds.Count -gt 0 -and $GateIds.Count -eq @($GateIds | Sort-Object -Unique).Count -and @($GateIds | Where-Object { $BaselineGateIds -notcontains $_ }).Count -eq 0) "FINAL_DOCUMENT_INVENTORY" "$artifactId gate IDs are empty, duplicate, or unregistered"
            $ExpectedMediaType = Get-ExpectedMediaType $Expanded
            Assert-True ($null -ne $ExpectedMediaType -and [string](Get-PropertyValue $artifact "media_type") -ceq $ExpectedMediaType) "FINAL_DOCUMENT_INVENTORY" "$artifactId media type/extension contract drift"
            Assert-True ($ExpectedSourceKinds.Contains($group) -and $ExpectedSourceKinds[$group] -contains [string](Get-PropertyValue $artifact "source_kind")) "FINAL_DOCUMENT_INVENTORY" "$artifactId source kind/group contract drift"
        }
        Assert-True ($ArtifactIds.Count -eq @($ArtifactIds | Sort-Object -Unique).Count -and $ArtifactIds.Count -eq $ExpectedInventoryCounts["total"]) "FINAL_DOCUMENT_INVENTORY" "artifact IDs must be unique"
        Assert-True ($ContainedPaths.Count -eq @($ContainedPaths | Sort-Object -Unique).Count -and $ContainedPaths.Count -eq $ExpectedInventoryCounts["total"]) "FINAL_DOCUMENT_INVENTORY" "root-relative artifact paths must be unique"
        $ManualContract = $FinalDocumentInventory.manual_combination_contract
        Assert-True ($ManualContract.pair_count -eq 8 -and $ManualContract.administrator_guide_source_count -eq 5 -and $ManualContract.convenience_bundle_does_not_replace_pairs -eq $true) "FINAL_DOCUMENT_INVENTORY" "manual combination contract drift"
        Assert-True ($ManualContract.distribution_manual_directory -ceq '${release_id}/manuals/') "FINAL_DOCUMENT_INVENTORY" "distribution manual directory drift"
        $ExpectedManualPdfNames = @($ExpectedManualStems | ForEach-Object { "$_.pdf" })
        $ManualPdfEntries = @($Artifacts | Where-Object { $_.group -ceq "manual_pdf" })
        Assert-True (Same-Set -Actual @($ManualPdfEntries | ForEach-Object { $_.relative_path_template }) -Expected $ExpectedManualPdfNames) "FINAL_DOCUMENT_INVENTORY" "inventory manual PDF source set drift"
        Assert-True (@($ManualPdfEntries | Where-Object { $_.source_kind -cne "generated_accessible_pdf" }).Count -eq 0) "FINAL_DOCUMENT_INVENTORY" "inventory manual PDF source kind drift"
        $ExpectedDistributionManuals = @($ExpectedManualPdfNames | ForEach-Object { '${release_id}/manuals/' + $_ })
        $DistributionManualEntries = @($Artifacts | Where-Object { $_.group -ceq "distribution" -and $_.source_kind -ceq "copied_verified_manual_pdf" })
        Assert-True ($DistributionManualEntries.Count -eq 8 -and (Same-Set -Actual @($DistributionManualEntries | ForEach-Object { $_.relative_path_template }) -Expected $ExpectedDistributionManuals)) "FINAL_DOCUMENT_INVENTORY" "distribution must contain exact verified copies of all 8 manual PDFs"
        $ExpectedAdminSources = @("institution-admin-guide.pdf", "content-reviewer-guide.pdf", "system-admin-guide.pdf", "security-auditor-guide.pdf", "operations-operator-guide.pdf")
        $ActualAdminSources = @($ManualContract.administrator_guide_sources)
        Assert-True (Same-Sequence -Actual $ActualAdminSources -Expected $ExpectedAdminSources) "FINAL_DOCUMENT_INVENTORY" "administrator guide source order/inventory drift"
        Assert-True ($ActualAdminSources.Count -eq @($ActualAdminSources | Sort-Object -Unique).Count -and @($ActualAdminSources | Where-Object { $ExpectedManualPdfNames -notcontains $_ }).Count -eq 0) "FINAL_DOCUMENT_INVENTORY" "administrator guide sources must be unique manual PDFs"
    }

    if ($null -ne $OverlayManifest) {
        Assert-True ($OverlayManifest.manifest_version -ceq "overlay.v2") "RUNTIME_CONTRACT" "overlay manifest version drift"
        Assert-True ($OverlayManifest.policy_id -ceq $OverlayPolicyParityMarker) "RUNTIME_CONTRACT" "overlay policy parity marker drift"
        Assert-True ($OverlayManifest.baseline_id -ceq "YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1") "RUNTIME_CONTRACT" "overlay baseline ID drift"
        Assert-True ($OverlayManifest.target_root -ceq $ExpectedRoot) "RUNTIME_CONTRACT" "overlay target root drift"
        Assert-True ($OverlayManifest.target_remote -ceq $ExpectedRemote) "RUNTIME_CONTRACT" "overlay target remote drift"
        Assert-True ($OverlayManifest.target_branch -ceq $ExpectedBranch) "RUNTIME_CONTRACT" "overlay target branch drift"
        $Entries = @($OverlayManifest.files)
        $Sources = @($Entries | ForEach-Object { $_.source })
        $Destinations = @($Entries | ForEach-Object { $_.destination })
        Assert-True ($OverlayManifest.file_count -eq $Entries.Count -and $Entries.Count -gt 0) "RUNTIME_CONTRACT" "overlay file count drift"
        Assert-True ($Sources.Count -eq @($Sources | Sort-Object -Unique).Count -and $Destinations.Count -eq @($Destinations | Sort-Object -Unique).Count) "RUNTIME_CONTRACT" "overlay sources/destinations must be unique"
        foreach ($entry in $Entries) {
            Assert-True (Same-Set -Actual @($entry.PSObject.Properties.Name) -Expected @("source", "destination", "sha256", "bytes", "mode")) "RUNTIME_CONTRACT" "overlay file entry must contain exactly source, destination, sha256, bytes, and mode"
            foreach ($pathEntry in @(@("source", [string]$entry.source), @("destination", [string]$entry.destination))) {
                Assert-True (Is-SafeRelativePath $pathEntry[1]) "RUNTIME_CONTRACT" "unsafe overlay $($pathEntry[0]): $($pathEntry[1])"
            }
            $DeclaredHash = [string](Get-PropertyValue $entry "sha256")
            Assert-True ($DeclaredHash -cmatch '^[0-9a-f]{64}$') "RUNTIME_CONTRACT" "overlay sha256 must be lowercase SHA-256: $($entry.source)"
            Assert-True ((Get-PropertyValue $entry "bytes") -is [long] -or (Get-PropertyValue $entry "bytes") -is [int]) "RUNTIME_CONTRACT" "overlay bytes must be an integer: $($entry.source)"
            Assert-True ([long](Get-PropertyValue $entry "bytes") -gt 0) "RUNTIME_CONTRACT" "overlay bytes must be positive: $($entry.source)"
            Assert-True ([string](Get-PropertyValue $entry "mode") -ceq "100644") "RUNTIME_CONTRACT" "overlay install mode drift: $($entry.source)"
        }
    }

    $Runner = Read-Text (Join-Path $WorkRoot "repo-overlay/scripts/invoke-ai-training-platform-v1.ps1")
    $Starter = Read-Text (Join-Path $WorkRoot "start-ai-training-platform-v1.ps1")
    $Validator = Read-Text (Join-Path $WorkRoot "repo-overlay/scripts/validate-codex-final-result.ps1")
    $VerifierSource = Read-Text $MyInvocation.MyCommand.Path
    $TrustTemplate = Read-Json (Join-Path $PackageRoot "release-trust.example.json")
    Assert-True $Runner.Contains($ExpectedRoot) "RUNTIME_CONTRACT" "runner omits canonical root"
    Assert-True $Starter.Contains($ExpectedRoot) "RUNTIME_CONTRACT" "starter omits canonical root"
    Assert-True (-not [string]::IsNullOrWhiteSpace($Validator)) "RUNTIME_CONTRACT" "validator is missing or empty"
    Assert-True ($Runner.Contains("codex-output.schema.json")) "RUNTIME_CONTRACT" "runner must bind the model-facing output schema"
    Assert-True ($Runner.Contains("codex-final-result.schema.json")) "RUNTIME_CONTRACT" "runner must bind the strict final-result schema for second-stage validation"
    Assert-True ($Runner.Contains("final-document-inventory.json") -and $Runner.Contains("final_document_inventory_sha256")) "RUNTIME_CONTRACT" "runner must bind the normative final-document inventory hash"
    Assert-True ($Starter.Contains('$entry.sha256') -and $Starter.Contains('$entry.bytes') -and $Starter.Contains('$entry.mode') -and $Starter.Contains("overlay_manifest_sha256")) "RUNTIME_CONTRACT" "bootstrap must enforce manifest source hash, bytes, mode, and bind the manifest digest"
    Assert-True ($Starter.Contains("package verification did not PASS") -and $Starter.Contains("source is outside the closed recursive mapping policy")) "RUNTIME_CONTRACT" "bootstrap must invoke package verification and independently enforce the closed mapping"
    Assert-True ($Starter.Contains('Assert-NoReparseAncestor -Path $backupRoot') -and $Starter.Contains(".artifacts/codex/overlay-backups")) "RUNTIME_CONTRACT" "bootstrap must reject reparse backup roots before writing receipts"
    Assert-True ($Starter.Contains("TrustedGitCommand") -and $Starter.Contains("Assert-SafeLocalGitConfig") -and $Starter.Contains("PRE-GIT-CONFIG")) "RUNTIME_CONTRACT" "bootstrap must use the pinned Git executable and reject executable/transport local config"
    Assert-True ($Starter.Contains("TrustedPythonCommand") -and $Starter.Contains('-PythonPath $script:TrustedPythonCommand')) "RUNTIME_CONTRACT" "bootstrap must run semantic package gates with the protected pinned Python executable"
    $PythonIsolationInvocation = '& $PythonCommand ' + '-I -S -B $Checker'
    Assert-True (([regex]::Matches($VerifierSource, [regex]::Escape($PythonIsolationInvocation))).Count -eq 1) "RUNTIME_CONTRACT" "PowerShell verifier must have exactly one isolated Python gate invocation"
    $ProtectedPythonWorkingDirectory = 'Push-Location -LiteralPath (Split-Path -Parent $' + 'PythonCommand)'
    Assert-True (([regex]::Matches($VerifierSource, [regex]::Escape($ProtectedPythonWorkingDirectory))).Count -eq 1 -and $Starter.Contains('Push-Location -LiteralPath (Split-Path -Parent $script:TrustedGitCommand)')) "RUNTIME_CONTRACT" "trusted Python and Git child processes must run from their protected executable directories"
    Assert-True (([regex]::Matches($Starter, "Assert-CanonicalBootstrapHost")).Count -eq 2 -and $Starter.Contains('$expectedPrefix = @("-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File")') -and $Starter.Contains("bootstrap -File target must be this exact starter script") -and $Starter.Contains("bootstrapTrust.PowerShell")) "RUNTIME_CONTRACT" "bootstrap must invoke the canonical pinned exact-prefix PowerShell host preflight"
    Assert-True (([regex]::Matches($Starter, [regex]::Escape('Assert-TrustedPythonRuntimeClosure -PythonPath $python'))).Count -eq 1 -and $Starter.Contains("PRE-PYTHON-RUNTIME") -and $Starter.Contains("GetFolderPath([Environment+SpecialFolder]::ProgramFiles)") -and $Starter.Contains("bootstrap Python and PowerShell require exact valid Authenticode")) "RUNTIME_CONTRACT" "bootstrap must recursively close the signed Program Files Python runtime trust boundary"
    Assert-True (([regex]::Matches($Starter, [regex]::Escape('Assert-BootstrapTrustPathChain -Path $Path'))).Count -eq 2 -and $Starter.Contains('$trustHashBefore') -and $Starter.Contains('$trustHashAfter') -and $Starter.Contains('$insideAnchor')) "RUNTIME_CONTRACT" "bootstrap must validate and revalidate the entire protected release-trust path chain and bytes"
    Assert-True ($Starter.Contains("Assert-StrictBootstrapJsonLexical") -and $Starter.Contains('ConvertFrom-StrictBootstrapJsonFile -Path $Path') -and $Starter.Contains('Assert-ExactBootstrapProperties $trust') -and $Starter.Contains("duplicate/ambiguous JSON property")) "RUNTIME_CONTRACT" "bootstrap must parse bounded strict UTF-8 release trust with duplicate-key and exact-property rejection"
    Assert-True (-not $Starter.Contains('Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json')) "RUNTIME_CONTRACT" "bootstrap must not parse root-of-trust JSON with permissive raw ConvertFrom-Json"
    Assert-True ($Starter.Contains('& ([string]$bootstrapTrust.PowerShell) @runnerArguments') -and $Starter.Contains('"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $runner') -and -not $Starter.Contains('& $runner')) "RUNTIME_CONTRACT" "bootstrap must spawn the installed runner under the pinned exact-prefix PowerShell host"
    Assert-True ($Starter.Contains('$bootstrapCommandPrefix = "& ''$([string]$bootstrapTrust.PowerShell)'' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File') -and $Starter.Contains('Write-Host "Review without writes: $bootstrapCommandPrefix -InstallOverlay -DryRun"') -and $Starter.Contains('Write-Host "Install with backup: $bootstrapCommandPrefix -InstallOverlay"') -and -not $Starter.Contains('Review without writes: powershell -ExecutionPolicy')) "RUNTIME_CONTRACT" "bootstrap retry guidance must preserve the pinned canonical host, exact prefix, and exact starter path"
    $CanonicalResumeCommand = 'return "& ''$CanonicalRunnerHost'' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ''$CanonicalRunnerPath'' -Mode Implement -ResumeRun ''$RunId''"'
    Assert-True ($Runner.Contains('$CanonicalRunnerHost = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"') -and $Runner.Contains('$CanonicalRunnerPath = "D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1"') -and $Runner.Contains($CanonicalResumeCommand) -and $Runner.Contains('$resumeCommand = Get-ResumeCommand -RunId $runId') -and -not $Runner.Contains('RESUME: powershell -ExecutionPolicy')) "RUNTIME_CONTRACT" "runner resume guidance must preserve the canonical host, exact prefix, absolute runner path, and Implement mode"
    Assert-True ([string]$TrustTemplate.trusted_tools.powershell.path -ceq 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -and $TrustTemplate.trusted_tools.powershell.authenticode_required -eq $true) "RUNTIME_CONTRACT" "release trust template must pin the canonical signed production PowerShell host"
    Assert-True ($TrustTemplate.trusted_tools.python.authenticode_required -eq $true -and [string]$TrustTemplate.trusted_tools.python.authenticode_signer_thumbprint -ceq "REPLACE_WITH_40_OR_64_HEX_THUMBPRINT") "RUNTIME_CONTRACT" "release trust template must require the signed Program Files Python runtime"
    foreach ($WindowsCheck in @("design-package-windows", "release-signatures")) {
        $TemplateWorkflow = @($TrustTemplate.github_policy.workflows | Where-Object { [string]$_.check_name -ceq $WindowsCheck })
        Assert-True ($TemplateWorkflow.Count -eq 1 -and (@($TemplateWorkflow[0].required_runner_labels) -join "`n") -ceq (@("self-hosted", "Windows", "X64") -join "`n")) "RUNTIME_CONTRACT" "release trust template must pin exact self-hosted Windows labels for $WindowsCheck"
    }
    Assert-True (([regex]::Matches($Starter, "Assert-NoBootstrapExecutionEnvironmentOverrides")).Count -eq 2 -and $Starter.Contains("GIT_CONFIG_COUNT") -and $Starter.Contains("GIT_CONFIG_KEY_") -and $Starter.Contains("GIT_SSH")) "RUNTIME_CONTRACT" "bootstrap must reject ambient Git/GPG/GitHub execution overrides before its first Git call"
    $BootstrapEnvironmentCleanup = 'foreach ($bootstrapGitEnvironmentName in @("GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL", "GIT_TERMINAL_PROMPT", "GCM_INTERACTIVE"))'
    $RunnerSpawnMarker = '& ([string]$bootstrapTrust.PowerShell) @runnerArguments'
    $BootstrapEnvironmentCleanupIndex = $Starter.IndexOf($BootstrapEnvironmentCleanup, [StringComparison]::Ordinal)
    $RunnerSpawnIndex = $Starter.IndexOf($RunnerSpawnMarker, [StringComparison]::Ordinal)
    Assert-True ($BootstrapEnvironmentCleanupIndex -ge 0 -and $RunnerSpawnIndex -ge 0 -and $BootstrapEnvironmentCleanupIndex -lt $RunnerSpawnIndex) "RUNTIME_CONTRACT" "bootstrap must remove its fixed Git environment before spawning the runner"
    $ExecutableAclFunctionMatch = [regex]::Match($Starter, '(?ms)^function Assert-NonBroadWritablePathChain\b.*?(?=^function Resolve-TrustedExecutable\b)')
    Assert-True $ExecutableAclFunctionMatch.Success "RUNTIME_CONTRACT" "bootstrap trusted executable ACL function boundary is missing"
    $ExecutableAclFunction = $(if ($ExecutableAclFunctionMatch.Success) { $ExecutableAclFunctionMatch.Value } else { "" })
    $AclOwnerRead = '$ownerSid = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value'
    $AclOwnerCompare = 'if ($trustedWriteSids -notcontains $ownerSid)'
    Assert-True (([regex]::Matches($ExecutableAclFunction, [regex]::Escape($AclOwnerRead))).Count -eq 1 -and ([regex]::Matches($ExecutableAclFunction, [regex]::Escape($AclOwnerCompare))).Count -eq 1 -and $ExecutableAclFunction.Contains("untrusted ACL owner") -and $ExecutableAclFunction.Contains('GetPathRoot($resolved)') -and $ExecutableAclFunction.Contains('$replacementMask') -and $ExecutableAclFunction.Contains('$insideAllowedRoot')) "RUNTIME_CONTRACT" "bootstrap trusted executable ACL function must retrieve and compare each path owner and enforce two-tier replacement rights through the volume root"
    Assert-True ($Starter.Contains('$effectiveMask = $(if ($insideAllowedRoot) { $writeMask } else { $replacementMask })') -and $Starter.Contains('if ([StringComparer]::OrdinalIgnoreCase.Equals($current, $allowedRoot)) { $insideAllowedRoot = $false }')) "RUNTIME_CONTRACT" "bootstrap must switch from descendant-write checks to ancestor-replacement checks only above the allowed root"
    Assert-True (-not $Starter.Contains("LOCALAPPDATA")) "RUNTIME_CONTRACT" "bootstrap must not admit a user-writable LocalAppData executable trust root"
    Assert-True (-not $Runner.Contains("LOCALAPPDATA") -and $Runner.Contains('$replacementMask=') -and $Runner.Contains('$insideAllowedRoot=$false') -and $Runner.Contains('PropagationFlags]::InheritOnly') -and $Runner.Contains('$volumeRoot=[IO.Path]::GetPathRoot($resolved)')) "RUNTIME_CONTRACT" "runner and bootstrap must share the non-user-writable two-tier ACL path policy"
    Assert-True ($Starter.Contains("Write-DurableJson") -and $Starter.Contains("overlay-transaction.v1") -and $Starter.Contains("OVERLAY-RECOVERY")) "RUNTIME_CONTRACT" "bootstrap must durably journal before target writes and block incomplete recovery"
    $DurableBackupMarker = 'Copy-DurableFileData -Source $change.Destination -Destination $backup -CreateNew'
    $PreparedStateMarker = 'state = "PREPARED"'
    $DurableInstallMarker = 'Flush-DurableFileData -Path $change.Destination'
    $CommittedStateMarker = '$transactionJournal.state = "COMMITTED"'
    Assert-True ($Starter.Contains("function Copy-DurableFileData") -and $Starter.Contains("function Flush-DurableFileData") -and $Starter.Contains('$outputStream.Flush($true)')) "RUNTIME_CONTRACT" "bootstrap must durably flush backup and staged file bytes"
    Assert-True ($Starter.Contains($DurableBackupMarker) -and $Starter.Contains($PreparedStateMarker) -and $Starter.IndexOf($DurableBackupMarker, [StringComparison]::Ordinal) -lt $Starter.IndexOf($PreparedStateMarker, [StringComparison]::Ordinal)) "RUNTIME_CONTRACT" "durable backup flush must precede PREPARED journal state"
    Assert-True ($Starter.Contains($DurableInstallMarker) -and $Starter.Contains($CommittedStateMarker) -and $Starter.IndexOf($DurableInstallMarker, [StringComparison]::Ordinal) -lt $Starter.IndexOf($CommittedStateMarker, [StringComparison]::Ordinal)) "RUNTIME_CONTRACT" "installed file flush must precede COMMITTED journal state"
    Assert-True (-not $Starter.Contains('Copy-Item -LiteralPath $change.Destination') -and -not $Starter.Contains('[System.IO.File]::WriteAllBytes($temporaryDestination')) "RUNTIME_CONTRACT" "non-durable backup or staging writes are forbidden"
    Assert-True ($Starter.Contains("Copy-DurableFileData") -and $Starter.Contains("Assert-DataStreamPolicy") -and $Starter.Contains("FileStream")) "RUNTIME_CONTRACT" "bootstrap must copy only the unnamed stream and strip/reject undeclared NTFS alternate streams"
    Assert-True ([regex]::Matches($Runner, [regex]::Escape('Invoke-Utf8Process -Command $codexCommand')).Count -eq 1) "ACTIVE_SAFETY" "runner must have exactly one active Codex process invocation"
    $DangerousHelperPattern = '(?is)(?:SafeGit|Invoke-Git)\s+[^\r\n]{0,160}@\([^)]*["''](?:reset|checkout|switch|rebase|clean|update-ref)["'']'
    Assert-True (-not [regex]::IsMatch($Runner + "`n" + $Starter, $DangerousHelperPattern)) "ACTIVE_SAFETY" "Git helper invocation contains a forbidden history/worktree mutation subcommand"

    $ArgumentMatch = [regex]::Match($Runner, '(?s)\$CodexArguments\s*=\s*(.*?)(?=\r?\nAssert-SafeCodexArguments\b)')
    Assert-True $ArgumentMatch.Success "ACTIVE_SAFETY" "Codex argument assignment is missing"
    if ($ArgumentMatch.Success) {
        $ArgumentBlock = $ArgumentMatch.Groups[1].Value
        Assert-True ($ArgumentBlock.Contains('$outputSchemaPath')) "RUNTIME_CONTRACT" "active Codex output-schema argument must use the model-facing schema path"
        foreach ($requiredToken in @('"exec"', '"-C"', '"--sandbox"', '"workspace-write"', '"--ask-for-approval"', '"on-request"', '"--json"', '"--output-last-message"', '"--output-schema"', '"-"')) {
            Assert-True $ArgumentBlock.Contains($requiredToken) "ACTIVE_SAFETY" "Codex argument missing: $requiredToken"
        }
        Assert-True ($ArgumentBlock -notmatch '--dangerously-bypass-approvals-and-sandbox|--yolo|--full-auto|--last') "ACTIVE_SAFETY" "unsafe/deprecated flag appears in active Codex argument array"
    }
    foreach ($scriptEntry in @(@("runner", $Runner), @("starter", $Starter))) {
        Assert-True ($scriptEntry[1] -notmatch '(?im)^\s*(?:&\s*)?git(?:\.exe)?\s+(?:switch|checkout|rebase|reset|fetch|push\s+--force)\b') "ACTIVE_SAFETY" "$($scriptEntry[0]) contains active Git branch/history mutation"
    }
    foreach ($line in ($Runner -split "`r?`n")) {
        if ($line -match '(?i)codex\s+exec') {
            Assert-True ($line -notmatch '--dangerously-bypass-approvals-and-sandbox|--yolo|--full-auto|--last') "ACTIVE_SAFETY" "unsafe flag appears in active/resume Codex invocation"
        }
    }

    foreach ($markdown in $MarkdownFiles) {
        $body = Read-Text $markdown
        $inFence = $false
        foreach ($line in ($body -split "`r?`n")) {
            if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
            if (-not $inFence) { continue }
            if ($line -match '(?i)\bcodex\s+exec\b') {
                Assert-True ($line -notmatch '--dangerously-bypass-approvals-and-sandbox|--yolo|--full-auto|--last') "ACTIVE_SAFETY" "unsafe active Codex invocation in $markdown"
            }
            Assert-True ($line -notmatch '(?i)\bgit\s+(?:switch|checkout|rebase|reset|fetch|push\s+--force)\b') "ACTIVE_SAFETY" "active Git history mutation in $markdown"
        }
    }

    $ShellSources = @(
        Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Filter "*.sh" -ErrorAction Stop
        Get-ChildItem -LiteralPath (Join-Path $WorkRoot "repo-overlay") -Recurse -File -Filter "*.sh" -ErrorAction Stop
    )
    foreach ($candidateItem in $ShellSources) {
        $candidate = $candidateItem.FullName
        $relative = $candidate
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $firstLine = [IO.File]::ReadLines($candidate) | Select-Object -First 1
        Assert-True ($firstLine -ceq '#!/usr/bin/env bash') "SHELL_MODES" "shell source lacks canonical Bash shebang: $relative"
        if ([IO.Path]::DirectorySeparatorChar -eq '/') {
            $bash = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $bash) {
                Add-Failure "SHELL_MODES" "bash is required to validate executable modes"
            } else {
                & $bash.Source -c 'test -x "$1"' bash $candidate
                Assert-True ($LASTEXITCODE -eq 0) "SHELL_MODES" "shell source is not executable: $relative"
            }
        }
    }
} catch {
    Add-Failure "INTERNAL" "unexpected verifier error: $($_.Exception.Message) at $($_.ScriptStackTrace)"
}

if ($Failures.Count -gt 0) {
    foreach ($failure in $Failures) {
        [Console]::Error.WriteLine("FAIL [$($failure.Code)]: $($failure.Message)")
    }
    Write-Host "RESULT: FAIL"
    exit 1
}

$PassMessages = [ordered]@{
    "CANONICAL_FILES" = "canonical package/workspace files present"
    "JSON_PARSE" = "baseline, schemas, and overlay manifest parse as JSON"
    "REQUIREMENT_COUNTS" = "60 RFP and 33 system requirements are exact"
    "DOCUMENT_IDS" = "document IDs are exact and unique"
    "MARKDOWN_STRUCTURE" = "Markdown fences and relative links are valid"
    "CANONICAL_COORDINATES" = "repository coordinates are canonical"
    "KPI_THRESHOLDS" = "KPI-001 through KPI-010 thresholds are canonical"
    "PERSONA_HIERARCHY" = "six families and twelve profiles are canonical"
    "DATA_POLICY" = "unknown/raw data defaults are fail-closed"
    "RELEASE_STATES" = "release evidence and transition rules are fail-closed"
    "FINAL_OUTPUT_ROOTS" = "planning and final output roots are exact"
    "RUNBOOK_INVENTORY" = "23 runbooks, owners, gates, freshness, and sections are exact"
    "MANUAL_PAIRS" = "8 Markdown/PDF manual pairs are exact"
    "RUNTIME_CONTRACT" = "launcher, starter, validator, and overlay manifest contract is complete"
    "ACTIVE_SAFETY" = "active Codex and Git invocations are safe"
    "SHELL_MODES" = "shell sources are executable"
    "MODEL_OUTPUT_SCHEMA" = "model-facing schema uses the supported strict object subset"
    "FINAL_DOCUMENT_INVENTORY" = "147 final artifacts are exact, registered, and root-contained"
    "MACHINE_CONTRACTS" = "registries, routes, KPI cells, golden vectors, and schema fixtures are coherent"
    "COMPLETENESS_CONTRACTS" = "OpenAPI, AsyncAPI, entities, RAG, provider, reuse, and UI closure are coherent"
    "SOURCE_TRACEABILITY" = "public-safe source identities, mappings, and reverse test edges are coherent"
    "NORMATIVE_TEST_SEMANTICS" = "all normative tests have executable pass/fail semantics"
    "SEMANTIC_DEPTH_CONTRACTS" = "rubric, persona, ABAC, provider, evaluation, and HWP depth contracts are coherent"
    "AI_GATEWAY_SAFEGUARDING" = "AI safeguarding decisions are closed and fail-safe"
    "TCH_015_AUTHORIZATION" = "privileged Document AI operations require exact authorization evidence"
}
foreach ($checkId in $ParityCheckIds) {
    Write-Host "PASS [$checkId]: $($PassMessages[$checkId])"
}
Write-Host "RESULT: PASS"
exit 0
