Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$runner = Join-Path (Split-Path -Parent $PSScriptRoot) "invoke-ai-training-platform-v1.ps1"
$runnerText = Get-Content -Raw -LiteralPath $runner
if ($runnerText -notmatch 'public static extern IntPtr GetCurrentProcess\(\);') { throw "NativeJob must expose the Win32 GetCurrentProcess pseudo-handle" }
if ($runnerText -match '\[Diagnostics\.Process\]::GetCurrentProcess\(\)\.Handle') { throw "NativeJob must not borrow a managed Process-owned handle for membership checks" }
if ($runnerText -match '\[IntPtr\]\(-1\)') { throw "NativeJob must not hardcode the pseudo-handle value" }
if ($runnerText -match 'CloseHandle\(\$currentProcessPseudoHandle\)') { throw "NativeJob must not close the GetCurrentProcess pseudo-handle" }
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw "runner parse failed" }
foreach ($name in @("Canonical", "String-Sha256", "Bytes-Sha256", "Assert-BoundedFile", "Assert-NoReparseComponent", "Get-NoFollowTreeEntries", "Assert-StrictJsonLexical", "ConvertFrom-StrictJsonText", "Assert-CodexEventSemantics", "Read-CodexEvents", "Quote-WindowsArgument", "Get-ForbiddenExecutionEnvironmentNames", "Assert-NoExecutionEnvironmentOverrides", "Set-SafeProcessEnvironment", "Get-SafeGitArguments", "Get-TrustedExecutableWorkingDirectory", "Test-SafeTrustedExecutablePathSyntax", "Get-GitGpgProgramSpec", "Get-GitHubCredentialHelperSpec", "New-KillOnCloseJob", "Close-KillOnCloseJob", "Stop-NativeProcessTree", "New-BoundedCaptureStream", "Invoke-NativeCaptureBytes", "Native", "Write-AtomicUtf8Text", "Read-Utf8NoBomText", "Try-PersistThreadReceipt", "Invoke-Utf8Process", "Invoke-TrustedValidatorProcess", "Get-FinalDocumentInventoryPaths", "Get-ThreadId", "Get-GitControlPlaneSnapshot", "Compare-GitControlPlaneSnapshot", "Get-GitReferenceSnapshot", "Compare-GitReferenceSnapshot", "Get-BoundedFileInventory", "Snapshot-Digest", "Test-UnsafeGitConfigName", "Assert-SafeGitConfigScopeNameFields", "Get-ValidSignatureStatus", "Assert-ValidSignaturePolicy", "Assert-ExactRequiredCiInventory")) {
    $functionAst = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name }, $true)
    if ($null -eq $functionAst) { throw "missing function $name" }
    . ([scriptblock]::Create($functionAst.Extent.Text))
}
$nativeReadOnlyFunctionAst = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq "Native-ReadOnly" }, $true)
if ($null -eq $nativeReadOnlyFunctionAst) { throw "missing function Native-ReadOnly" }
. ([scriptblock]::Create($nativeReadOnlyFunctionAst.Extent.Text))

$splitNulFunctionAst = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq "Split-NulDelimitedText" }, $true)
if ($null -eq $splitNulFunctionAst) { throw "missing function Split-NulDelimitedText" }
. ([scriptblock]::Create($splitNulFunctionAst.Extent.Text))

function Stop-Launcher([string]$Code, [string]$Message, [int]$ExitCode = 2) { throw "$Code/${ExitCode}: $Message" }
$MaxJsonBytes = 8388608
$MaxJsonlBytes = 268435456
$MaxJsonlLineBytes = 1048576
$MaxNativeCaptureBytes = 67108864
$MaxNativeSeconds = 120
$MaxCodexSeconds = 21600
$MaxWorktreeSnapshotBytes = 268435456
$MaxWorktreeFileBytes = 67108864
$MaxWorktreeFiles = 20000
$ProtectedGpgHome = "C:\ProgramData\YOnLab\gnupg"
$ProtectedHooksPath = "C:\ProgramData\YOnLab\empty-git-hooks"
$script:GitHubCredentialHelper = $null
$jobStressPowerShell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$jobStressEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Start-Sleep -Seconds 10'))
$jobStressPseudoHandle = [IntPtr]::Zero
for ($jobStressIteration = 1; $jobStressIteration -le 3; $jobStressIteration++) {
    $jobStressPsi = New-Object Diagnostics.ProcessStartInfo
    $jobStressPsi.UseShellExecute = $false
    $jobStressPsi.CreateNoWindow = $true
    $jobStressPsi.FileName = $jobStressPowerShell
    $jobStressPsi.Arguments = "-NoLogo -NoProfile -NonInteractive -EncodedCommand $jobStressEncoded"
    $jobStressProcess = New-Object Diagnostics.Process
    $jobStressProcess.StartInfo = $jobStressPsi
    $jobStressStarted = $false
    $jobStressJob = [IntPtr]::Zero
    try {
        if (-not $jobStressProcess.Start()) { throw "job stress child did not start on iteration $jobStressIteration" }
        $jobStressStarted = $true
        $jobStressJob = New-KillOnCloseJob $jobStressProcess 'Required'
        if ($jobStressJob -eq [IntPtr]::Zero) { throw "job stress returned a zero Job handle on iteration $jobStressIteration" }
        if ($jobStressPseudoHandle -eq [IntPtr]::Zero) {
            $jobStressPseudoHandle = [YOnLab.NativeJob]::GetCurrentProcess()
            if ($jobStressPseudoHandle -eq [IntPtr]::Zero) { throw 'GetCurrentProcess returned zero in regression fixture' }
        }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        $jobStressInJob = $false
        if (-not [YOnLab.NativeJob]::IsProcessInJob($jobStressPseudoHandle, [IntPtr]::Zero, [ref]$jobStressInJob)) {
            throw "GC-stressed pseudo-handle membership probe failed on iteration $jobStressIteration with Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
    } finally {
        if ($jobStressJob -ne [IntPtr]::Zero) { Close-KillOnCloseJob $jobStressJob; $jobStressJob = [IntPtr]::Zero }
        if ($jobStressStarted -and -not $jobStressProcess.HasExited) {
            try { Stop-NativeProcessTree $jobStressProcess } catch { }
            try { $jobStressProcess.WaitForExit() } catch { }
        }
        $jobStressProcess.Dispose()
    }
}Write-Host 'PASS: current-process Job membership uses a GC-stable Win32 pseudo-handle'
$savedGitDir = $env:GIT_DIR
$nativeReadOnlyPowerShell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$nativeReadOnlyScript = '[Console]::Out.Write("readonly")'
$nativeReadOnlyEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($nativeReadOnlyScript))
$nativeReadOnlyResult = Native-ReadOnly $nativeReadOnlyPowerShell @("-NoLogo", "-NoProfile", "-EncodedCommand", $nativeReadOnlyEncoded)
if ($nativeReadOnlyResult.ExitCode -ne 0 -or $nativeReadOnlyResult.Text -cne "readonly") { throw "Native-ReadOnly did not return an ExitCode/Text result contract" }
Write-Host "PASS: Native-ReadOnly returns decoded text result contract"
$nulFields = @(Split-NulDelimitedText ("system" + [char]0 + "core.pager" + [char]0))
if ($nulFields.Count -ne 2 -or $nulFields[0] -cne "system" -or $nulFields[1] -cne "core.pager") { throw "Split-NulDelimitedText did not remove the trailing NUL in Windows PowerShell 5.1" }
Write-Host "PASS: Split-NulDelimitedText removes trailing NUL in Windows PowerShell 5.1"
try {
    $env:GIT_DIR = "C:\attacker\forged-git-dir"
    $environmentRejected = $false
    try { Assert-NoExecutionEnvironmentOverrides } catch { $environmentRejected = $true }
    if (-not $environmentRejected) { throw "GIT_DIR environment override was accepted" }
} finally { $env:GIT_DIR = $savedGitDir }
if (-not (Test-UnsafeGitConfigName "filter.evil.process") -or -not (Test-UnsafeGitConfigName "url.https://evil.invalid/.insteadOf") -or -not (Test-UnsafeGitConfigName "credential.helper") -or (Test-UnsafeGitConfigName "core.repositoryformatversion")) { throw "Git executable/redirect config classifier mismatch" }
$safeCommandFields = @("command","core.fsmonitor","command","core.hookspath","command","core.pager","command","pager.branch","command","pager.log","command","credential.https://github.com.helper","local","core.repositoryformatversion")
Assert-SafeGitConfigScopeNameFields $safeCommandFields
foreach ($unsafePair in @(
    @("system","filter.evil.process"),
    @("system","diff.astextplain.textconv"),
    @("global","credential.helper"),
    @("local","url.https://evil.invalid/.insteadOf"),
    @("local","filter.evil.process"),
    @("command","alias.evil")
)) {
    $fixture = @($safeCommandFields) + @($unsafePair[0],$unsafePair[1])
    $scopeRejected = $false
    try { Assert-SafeGitConfigScopeNameFields $fixture } catch { $scopeRejected = $true }
    if (-not $scopeRejected) { throw "unsafe $($unsafePair[0])-scope Git config was accepted: $($unsafePair[1])" }
}
$spaceSafeGpg = Get-GitGpgProgramSpec "C:\Program Files (x86)\GnuPG\bin\gpg.exe" "C:\ProgramData\YOnLab\gnupg"
if ($spaceSafeGpg -cne '"C:/Program Files (x86)/GnuPG/bin/gpg.exe"') { throw "protected GPG executable specification mismatch" }
$script:GitHubCredentialHelper = Get-GitHubCredentialHelperSpec "C:\Program Files\GitHub CLI\gh.exe"
$safePsi = New-Object Diagnostics.ProcessStartInfo
$safePsi.EnvironmentVariables["GIT_PAGER"] = "attacker-pager"
$safePsi.EnvironmentVariables["GIT_CONFIG_SYSTEM"] = "attacker-system"
$safePsi.EnvironmentVariables["GIT_CONFIG_GLOBAL"] = "attacker-global"
$safePsi.EnvironmentVariables["GIT_CONFIG_NOSYSTEM"] = "0"
$safePsi.EnvironmentVariables["GIT_ATTR_NOSYSTEM"] = "0"
$safePsi.EnvironmentVariables["GIT_CONFIG_COUNT"] = "7"
$safePsi.EnvironmentVariables["GIT_CONFIG_KEY_99"] = "attacker-key"
$safePsi.EnvironmentVariables["GIT_CONFIG_VALUE_99"] = "attacker-value"
Set-SafeProcessEnvironment $safePsi
$pagerWasPreserved = $safePsi.EnvironmentVariables.ContainsKey("GIT_PAGER")
$forgedKeyWasPreserved = $safePsi.EnvironmentVariables.ContainsKey("GIT_CONFIG_KEY_99")
$forgedValueWasPreserved = $safePsi.EnvironmentVariables.ContainsKey("GIT_CONFIG_VALUE_99")
if ($pagerWasPreserved -or
    $safePsi.EnvironmentVariables["GIT_CONFIG_SYSTEM"] -cne "NUL" -or
    $safePsi.EnvironmentVariables["GIT_CONFIG_GLOBAL"] -cne "NUL" -or
    $safePsi.EnvironmentVariables["GIT_CONFIG_NOSYSTEM"] -cne "1" -or
    $safePsi.EnvironmentVariables["GIT_ATTR_NOSYSTEM"] -cne "1" -or
    $safePsi.EnvironmentVariables["GIT_CONFIG_COUNT"] -cne "1" -or
    $forgedKeyWasPreserved -or
    $forgedValueWasPreserved) { throw "safe Git child environment did not isolate system/global config and pager" }
if (@(Get-SafeGitArguments @("status")) -notcontains "core.hooksPath=C:\ProgramData\YOnLab\empty-git-hooks") { throw "SafeGit did not pin the protected empty hooks path" }
if ($safePsi.EnvironmentVariables["GIT_CONFIG_KEY_0"] -cne "credential.https://github.com.helper" -or $safePsi.EnvironmentVariables["GIT_CONFIG_VALUE_0"] -cne '!"C:/Program Files/GitHub CLI/gh.exe" auth git-credential') { throw "pinned gh credential helper injection mismatch" }
$script:GitHubCredentialHelper = $null
Write-Host "PASS: isolates Git system/global config, pager, hooks, and executable configuration overrides"

$signatureFingerprint = "0123456789ABCDEF0123456789ABCDEF01234567"
$ed25519Status = "[GNUPG:] VALIDSIG $signatureFingerprint 2026-07-14 1784000000 0 4 0 22 8 00 $signatureFingerprint"
[void](Assert-ValidSignaturePolicy $ed25519Status $signatureFingerprint "Ed25519 fixture")
$rsaStatus = "[GNUPG:] VALIDSIG $signatureFingerprint 2026-07-14 1784000000 0 4 0 1 8 00 $signatureFingerprint"
$rsaRejected = $false
try { [void](Assert-ValidSignaturePolicy $rsaStatus $signatureFingerprint "RSA fixture") } catch { $rsaRejected = $true }
if (-not $rsaRejected) { throw "RSA signature was accepted under Ed25519 signing policy" }
Write-Host "PASS: rejects RSA signature under exact Ed25519/SHA-256 policy"

$requiredChecks = @("design-package-linux", "design-package-windows", "security-and-schema", "release-signatures")
$exactChecks = @($requiredChecks | ForEach-Object { [pscustomobject]@{name=$_} })
if (@(Assert-ExactRequiredCiInventory ([pscustomobject]@{total_count=4;check_runs=$exactChecks}) $requiredChecks).Count -ne 4) { throw "exact CI inventory was rejected" }
$extraChecks = @($exactChecks) + @([pscustomobject]@{name="trusted-extra-success"})
$extraCiRejected = $false
try { [void](Assert-ExactRequiredCiInventory ([pscustomobject]@{total_count=5;check_runs=$extraChecks}) $requiredChecks) } catch { $extraCiRejected = $true }
if (-not $extraCiRejected) { throw "extra successful CI context was accepted" }
Write-Host "PASS: rejects extra successful CI context outside exact four-check set"
$strictJsonCases = @(
    '{"A":1,"nested":{"b":[true,false,null,-1.25e+3]},"text":"한글\\n😀"}',
    '[]',
    '"root-string"'
)
foreach ($json in $strictJsonCases) { Assert-StrictJsonLexical $json "valid fixture" }
$nonStrictJsonCases = @(
    '{"a":1,"A":2}',
    '{"schema_version":1,"schema_\u0076ersion":2}',
    '{"a":01}',
    '{"a":.1}',
    '{"a":1.}',
    '{"a":NaN}',
    '{"a":1,}',
    '{/*comment*/"a":1}',
    '[1,]',
    'true false'
)
foreach ($json in $nonStrictJsonCases) {
    $rejected = $false
    try { Assert-StrictJsonLexical $json "invalid fixture" } catch { $rejected = $true }
    if (-not $rejected) { throw "strict JSON scanner accepted: $json" }
}
Write-Host "PASS: dependency-free strict JSON grammar and duplicate-property scanner"
$threadId = "01990000-0000-7000-8000-000000000001"
if ((Get-ThreadId @([pscustomobject]@{type="thread.started";thread_id=$threadId})) -cne $threadId) { throw "Codex thread UUID was rejected" }
Write-Host "PASS: validated exact Codex thread UUID extraction"
$atomicReplaceRoot = Join-Path ([IO.Path]::GetTempPath()) ("yonlab-atomic-replace-" + [Guid]::NewGuid().ToString("N"))
[IO.Directory]::CreateDirectory($atomicReplaceRoot) | Out-Null
try {
    $atomicReplacePath = Join-Path $atomicReplaceRoot "resume-state.json"
    $firstValue = '{"attempt":"first"}'
    $secondValue = '{"attempt":"second"}'

    Write-AtomicUtf8Text -Path $atomicReplacePath -Value $firstValue

    $replaceError = $null
    try {
        Write-AtomicUtf8Text -Path $atomicReplacePath -Value $secondValue -Replace
    } catch {
        $replaceError = $_
    }

    if ($null -ne $replaceError) {
        throw (
            "Write-AtomicUtf8Text replacement failed: " +
            "$($replaceError.Exception.GetType().FullName): " +
            "$($replaceError.Exception.Message)"
        )
    }

    $actualValue = [IO.File]::ReadAllText($atomicReplacePath, [Text.Encoding]::UTF8)
    if ($actualValue -cne $secondValue) {
        throw "atomic replacement content mismatch"
    }

    $bytes = [IO.File]::ReadAllBytes($atomicReplacePath)
    if (
        $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    ) {
        throw "atomic replacement emitted a UTF-8 BOM"
    }

    $residualFiles = @(
        Get-ChildItem -LiteralPath $atomicReplaceRoot -Force |
            Where-Object {
                $_.Name -like 'resume-state.json.tmp-*' -or
                $_.Name -like 'resume-state.json.bak-*'
            }
    )

    if ($residualFiles.Count -ne 0) {
        throw "atomic replacement left temporary files: $($residualFiles.Name -join ', ')"
    }
} finally {
    if (Test-Path -LiteralPath $atomicReplaceRoot) {
        Remove-Item -LiteralPath $atomicReplaceRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "PASS: atomic UTF-8 receipt replacement preserves content, no-BOM encoding, and cleanup"

$installedRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../..")
)

$packageRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../../..")
)

$installedInventoryPath = Join-Path `
    $installedRoot `
    "docs/planning/ai-training-platform-v1/final-document-inventory.json"

$packageInventoryPath = Join-Path `
    $packageRoot `
    "yonlab-ai-training-platform-design/final-document-inventory.json"

if (
    Test-Path `
        -LiteralPath $installedInventoryPath `
        -PathType Leaf
) {
    $layout = "installed"
    $inventoryPath = $installedInventoryPath
} elseif (
    Test-Path `
        -LiteralPath $packageInventoryPath `
        -PathType Leaf
) {
    $layout = "package"
    $inventoryPath = $packageInventoryPath
} else {
    throw (
        "cannot resolve final-document inventory for installed " +
        "or package layout; installed=$installedInventoryPath; " +
        "package=$packageInventoryPath"
    )
}

$inventoryItem = Get-Item `
    -LiteralPath $inventoryPath `
    -Force

if (
    ($inventoryItem.Attributes -band
        [IO.FileAttributes]::ReparsePoint) -ne 0
) {
    throw "final-document inventory must not be a reparse point: $inventoryPath"
}

$inventory = Get-Content `
    -Raw `
    -Encoding UTF8 `
    -LiteralPath $inventoryPath |
    ConvertFrom-Json

Write-Host (
    "PASS: final-document inventory layout=$layout path=$inventoryPath"
)

$inventoryPaths = @(Get-FinalDocumentInventoryPaths $inventory "v1.0.0-rc1")
$expectedInventoryCount = [int]$inventory.expected_counts.total
if ($expectedInventoryCount -le 0 -or $inventoryPaths.Count -ne $expectedInventoryCount -or $inventoryPaths -notcontains "docs/releases/ai-training-platform/v1.0.0-rc1/README.md" -or $inventoryPaths -notcontains "dist/docs/v1.0.0-rc1/manuals/quick-start.pdf") { throw "normative final-document inventory expansion mismatch" }
Write-Host "PASS: normative $expectedInventoryCount-path final-document inventory expansion"

$temp = Join-Path ([IO.Path]::GetTempPath()) ("yonlab process test " + [Guid]::NewGuid().ToString("N"))
[IO.Directory]::CreateDirectory($temp) | Out-Null
$savedConsoleInputEncoding = [Console]::InputEncoding
try {
    [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
    $gitDirectory = Join-Path $temp "repository/.git"
    $commonDirectory = $gitDirectory
    [IO.Directory]::CreateDirectory((Join-Path $gitDirectory "hooks")) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $gitDirectory "info")) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $gitDirectory "objects/info")) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $gitDirectory "refs/replace")) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $gitDirectory "refs/heads")) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $gitDirectory "refs/tags")) | Out-Null
    $dotGitPath = $gitDirectory
    [IO.File]::WriteAllText((Join-Path $gitDirectory "config"), "[core]`n`tbare = false`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    [IO.File]::WriteAllText((Join-Path $gitDirectory "info/exclude"), "# baseline`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    [IO.File]::WriteAllText((Join-Path $gitDirectory "HEAD"), "ref: refs/heads/main`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    [IO.File]::WriteAllText((Join-Path $gitDirectory "index"), "synthetic-index", (New-Object Text.UTF8Encoding -ArgumentList $false))
    [IO.File]::WriteAllText((Join-Path $gitDirectory "refs/heads/main"), ("a" * 40) + "`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    $baselineControlPlane = Get-GitControlPlaneSnapshot $gitDirectory $commonDirectory $dotGitPath
    $baselineReferences = Get-GitReferenceSnapshot $gitDirectory $commonDirectory

    [IO.File]::AppendAllText((Join-Path $gitDirectory "config"), "`tfsmonitor = C:\attacker\marker.cmd`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    if (Compare-GitControlPlaneSnapshot $baselineControlPlane (Get-GitControlPlaneSnapshot $gitDirectory $commonDirectory $dotGitPath)) { throw "core.fsmonitor mutation was not detected before post-Codex Git" }
    [IO.File]::WriteAllText((Join-Path $gitDirectory "config"), "[core]`n`tbare = false`n", (New-Object Text.UTF8Encoding -ArgumentList $false))

    [IO.File]::AppendAllText((Join-Path $gitDirectory "config"), "[gpg]`n`tprogram = C:\attacker\fake-gpg.cmd`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    if (Compare-GitControlPlaneSnapshot $baselineControlPlane (Get-GitControlPlaneSnapshot $gitDirectory $commonDirectory $dotGitPath)) { throw "fake gpg.program mutation was not detected before signed-tag verification" }
    [IO.File]::WriteAllText((Join-Path $gitDirectory "config"), "[core]`n`tbare = false`n", (New-Object Text.UTF8Encoding -ArgumentList $false))

    [IO.File]::AppendAllText((Join-Path $gitDirectory "info/exclude"), ".forged-release-evidence`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    if (Compare-GitControlPlaneSnapshot $baselineControlPlane (Get-GitControlPlaneSnapshot $gitDirectory $commonDirectory $dotGitPath)) { throw "info/exclude mutation was not detected before clean-worktree verification" }
    [IO.File]::WriteAllText((Join-Path $gitDirectory "info/exclude"), "# baseline`n", (New-Object Text.UTF8Encoding -ArgumentList $false))

    $gitmodulesPath = Join-Path (Split-Path -Parent $gitDirectory) ".gitmodules"
    [IO.File]::WriteAllText($gitmodulesPath, "[submodule `"evil`"]`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    $gitmodulesRejected = $false
    try { [void](Get-GitControlPlaneSnapshot $gitDirectory $commonDirectory $dotGitPath) } catch { $gitmodulesRejected = $true }
    Remove-Item -LiteralPath $gitmodulesPath -Force
    if (-not $gitmodulesRejected) { throw ".gitmodules creation was accepted" }
    [IO.Directory]::CreateDirectory((Join-Path $gitDirectory "modules/evil/hooks")) | Out-Null
    $submoduleMetadataRejected = $false
    try { [void](Get-GitControlPlaneSnapshot $gitDirectory $commonDirectory $dotGitPath) } catch { $submoduleMetadataRejected = $true }
    Remove-Item -LiteralPath (Join-Path $gitDirectory "modules") -Recurse -Force
    if (-not $submoduleMetadataRejected) { throw ".git/modules creation was accepted" }
    Write-Host "PASS: Git control-plane detects fsmonitor, fake GPG, exclude, and submodule mutations"

    [IO.File]::WriteAllText((Join-Path $gitDirectory "refs/heads/main"), ("b" * 40) + "`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    if (Compare-GitReferenceSnapshot $baselineReferences (Get-GitReferenceSnapshot $gitDirectory $commonDirectory)) { throw "Git ref mutation was not detected" }
    [IO.File]::WriteAllText((Join-Path $gitDirectory "refs/heads/main"), ("a" * 40) + "`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    if (-not (Compare-GitReferenceSnapshot $baselineReferences (Get-GitReferenceSnapshot $gitDirectory $commonDirectory))) { throw "Git reference snapshot did not return to baseline" }
    Write-Host "PASS: Git reference snapshot detects index/HEAD/heads/tags/packed-refs mutation"

    $outsideTree = Join-Path $temp "outside-tree"
    [IO.Directory]::CreateDirectory($outsideTree) | Out-Null
    foreach ($fixture in @(
        [pscustomobject]@{root=(Join-Path $gitDirectory "hooks");code="GIT-CONTROL";label="hooks subtree"},
        [pscustomobject]@{root=(Join-Path $gitDirectory "refs/tags");code="GIT-REFS";label="refs/tags subtree"},
        [pscustomobject]@{root=(Join-Path $temp "gpg-home");code="PRE-TRUST";label="GPG subtree"},
        [pscustomobject]@{root=(Join-Path $temp "artifact-root");code="POST-ARTIFACT";label="artifact subtree"}
    )) {
        [IO.Directory]::CreateDirectory([string]$fixture.root) | Out-Null
        $link = Join-Path ([string]$fixture.root) "forbidden-reparse"
        $itemType=$(if($env:OS -ceq "Windows_NT"){"Junction"}else{"SymbolicLink"})
        New-Item -ItemType $itemType -Path $link -Target $outsideTree -ErrorAction Stop | Out-Null
        $reparseRejected=$false
        try {
            if ([string]$fixture.code -ceq "GIT-CONTROL") { [void](Get-GitControlPlaneSnapshot $gitDirectory $commonDirectory $dotGitPath) }
            elseif ([string]$fixture.code -ceq "GIT-REFS") { [void](Get-GitReferenceSnapshot $gitDirectory $commonDirectory) }
            else { [void](Get-NoFollowTreeEntries ([string]$fixture.root) ([string]$fixture.code) ([string]$fixture.label)) }
        } catch { $reparseRejected=$true }
        Remove-Item -LiteralPath $link -Force
        if (-not $reparseRejected) { throw "no-follow traversal accepted a reparse point in $($fixture.label)" }
    }
    Write-Host "PASS: no-follow BFS rejects hooks, refs/tags, GPG, and artifact subtree reparse points before descent"

    $ignoredProbe = Join-Path (Split-Path -Parent $gitDirectory) "ignored-probe.bin"
    [IO.File]::WriteAllText($ignoredProbe, "AAAA", (New-Object Text.UTF8Encoding -ArgumentList $false))
    $ignoredBaseline = Get-BoundedFileInventory (Split-Path -Parent $gitDirectory) @("ignored-probe.bin") "ignored"
    [IO.File]::WriteAllText($ignoredProbe, "BBBB", (New-Object Text.UTF8Encoding -ArgumentList $false))
    $ignoredMutated = Get-BoundedFileInventory (Split-Path -Parent $gitDirectory) @("ignored-probe.bin") "ignored"
    if ((Snapshot-Digest $ignoredBaseline) -ceq (Snapshot-Digest $ignoredMutated)) { throw "same-path/same-length ignored file content mutation was not detected" }
    Write-Host "PASS: ignored inventory detects same-path same-length content mutation"

    $malformedJsonl = Join-Path $temp "malformed-after-thread.jsonl"
    [IO.File]::WriteAllText($malformedJsonl, "{`"type`":`"thread.started`",`"thread_id`":`"$threadId`"}`n{not-json}`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    $parsed = Read-CodexEvents $malformedJsonl
    if (@($parsed.Events).Count -ne 1 -or $null -eq $parsed.ParseError -or (Get-ThreadId @($parsed.Events)) -cne $threadId) { throw "stream parser did not preserve the validated thread receipt before malformed JSONL" }
    Write-Host "PASS: malformed trailing JSONL preserves validated thread identity and fails closed"

    $nonStringEvent = Join-Path $temp "non-string-thread-event.jsonl"
    [IO.File]::WriteAllText($nonStringEvent, '{"type":["thread.started"],"thread_id":"01990000-0000-7000-8000-000000000001"}' + "`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    if ($null -eq (Read-CodexEvents $nonStringEvent).ParseError) { throw "non-string Codex event type was accepted" }
    $ambiguousEvent = Join-Path $temp "ambiguous-thread-event.jsonl"
    [IO.File]::WriteAllText($ambiguousEvent, '{"type":"thread.started","thread_id":"01990000-0000-7000-8000-000000000001","message":"forged"}' + "`n", (New-Object Text.UTF8Encoding -ArgumentList $false))
    if ($null -eq (Read-CodexEvents $ambiguousEvent).ParseError) { throw "ambiguous thread event property set was accepted" }
    Write-Host "PASS: rejects-non-string-or-ambiguous-thread-events"

    $oversizedJsonl = Join-Path $temp "oversized-line.jsonl"
    [IO.File]::WriteAllText($oversizedJsonl, ('{"type":"error","message":"' + ('x' * ($MaxJsonlLineBytes + 1)) + '"}' + "`n"), (New-Object Text.UTF8Encoding -ArgumentList $false))
    if ($null -eq (Read-CodexEvents $oversizedJsonl).ParseError) { throw "oversized JSONL line was accepted" }
    $oversizedFinal = Join-Path $temp "oversized-final.json"
    [IO.File]::WriteAllBytes($oversizedFinal, (New-Object byte[] ([int]($MaxJsonBytes + 1))))
    $sizeRejected = $false; try { [void](Assert-BoundedFile $oversizedFinal $MaxJsonBytes "TEST" "oversized final JSON") } catch { $sizeRejected = $true }
    if (-not $sizeRejected) { throw "oversized final JSON was accepted" }
    Write-Host "PASS: fails-closed-on-oversized-jsonl-diff-and-final-json"

    $noBomJson = Join-Path $temp "run-manifest.json"
    Write-AtomicUtf8Text $noBomJson '{"manifest":"한글"}'
    $rawNoBom = [IO.File]::ReadAllBytes($noBomJson)
    if ($rawNoBom.Length -ge 3 -and $rawNoBom[0] -eq 0xEF -and $rawNoBom[1] -eq 0xBB -and $rawNoBom[2] -eq 0xBF) { throw "atomic UTF-8 writer emitted BOM" }
    if ((Read-Utf8NoBomText $noBomJson 1024 "manifest") -cne '{"manifest":"한글"}') { throw "UTF-8 no-BOM round trip failed" }
    Write-Host "PASS: WinPS5-safe no-BOM run/resume artifact encoding"

    $currentPowerShell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

    function ConvertTo-TestEncodedCommand {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Script
        )

        return [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($Script)
        )
    }

    function Get-TestPowerShellArguments {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Script
        )

        return @(
            '-NoLogo'
            '-NoProfile'
            '-NonInteractive'
            '-EncodedCommand'
            (ConvertTo-TestEncodedCommand $Script)
        )
    }

    $oversizedNativeScript = '[Console]::Out.Write("x" * 4096); [Console]::Error.Write("y" * 4096)'
    $oversizedNativeEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($oversizedNativeScript))
    $savedNativeLimit = $MaxNativeCaptureBytes
    $nativeLimitRejected = $false
    try {
        $MaxNativeCaptureBytes = 1024
        [void](Native $currentPowerShell @("-NoLogo", "-NoProfile", "-EncodedCommand", $oversizedNativeEncoded))
    } catch { $nativeLimitRejected = $_.Exception.Message -match 'bounded total capture limit' }
    finally { $MaxNativeCaptureBytes = $savedNativeLimit }
    if (-not $nativeLimitRejected) { throw "bounded Native helper accepted oversized stdout/stderr" }
    Write-Host "PASS: bounded Native helper rejects oversized stdout/stderr"

    $nativeTimeoutScript = 'Start-Sleep -Seconds 3; [Console]::Out.Write("late")'
    $nativeTimeoutEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($nativeTimeoutScript))
    $nativeTimeoutRejected = $false
    try { [void](Invoke-NativeCaptureBytes $currentPowerShell @("-NoLogo", "-NoProfile", "-EncodedCommand", $nativeTimeoutEncoded) 1024 1) }
    catch { $nativeTimeoutRejected = $_.Exception.Message -match 'hard timeout' }
    if (-not $nativeTimeoutRejected) { throw "Native helper accepted a process past its hard deadline" }
    Write-Host "PASS: Native helper enforces a hard per-command deadline"

    $nativeWorkingDirectoryScript = @'
$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
[Console]::Out.Write([Environment]::CurrentDirectory)
'@
    $nativeWorkingDirectoryResult = Invoke-NativeCaptureBytes `
        $currentPowerShell `
        (Get-TestPowerShellArguments $nativeWorkingDirectoryScript) `
        4096 `
        10
    $expectedNativeWorkingDirectory = [IO.Path]::GetFullPath(
        (Split-Path -Parent $currentPowerShell)
    )
    $nativeObservedWorkingDirectory = (New-Object Text.UTF8Encoding -ArgumentList $false, $true).GetString($nativeWorkingDirectoryResult.Bytes)
    if (-not [StringComparer]::Ordinal.Equals($expectedNativeWorkingDirectory, ([IO.Path]::GetFullPath($nativeObservedWorkingDirectory)))) { throw "Native helper inherited repository/current working directory instead of executable parent" }
    Write-Host "PASS: Native helper pins executable-parent working directory"

    $inputReceipt = Join-Path $temp "input.bin"
    $stdout = Join-Path $temp "stdout.jsonl"
    $stderr = Join-Path $temp "stderr.log"
    $streamScript = @'
$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
[Console]::InputEncoding = $utf8

[IO.File]::WriteAllText(
    $env:MOCK_WORKING_DIRECTORY_RECEIPT,
    [Environment]::CurrentDirectory,
    $utf8
)

$inputStream = [Console]::OpenStandardInput()
$receiptStream = [IO.File]::Open(
    $env:MOCK_INPUT_RECEIPT,
    [IO.FileMode]::Create,
    [IO.FileAccess]::Write,
    [IO.FileShare]::None
)

try {
    $inputStream.CopyTo($receiptStream)
    $receiptStream.Flush()
} finally {
    $receiptStream.Dispose()
}

[Console]::Out.WriteLine(
    '{"type":"thread.started","thread_id":"01990000-0000-4000-8000-000000000001","text":"한글"}'
)

for ($i = 1; $i -le 20000; $i += 1) {
    [Console]::Out.WriteLine(
        ('{"type":"item","i":' + $i + ',"text":"가나다"}')
    )
}

for ($i = 1; $i -le 20000; $i += 1) {
    [Console]::Error.WriteLine(
        ('오류-stream-' + $i + '-abcdefghijklmnopqrstuvwxyz')
    )
}

[Console]::Out.Flush()
[Console]::Error.Flush()
'@
    $env:MOCK_INPUT_RECEIPT = $inputReceipt
    $workingDirectoryReceipt = Join-Path $temp "codex-working-directory.txt"
    $env:MOCK_WORKING_DIRECTORY_RECEIPT = $workingDirectoryReceipt
    $input = "한국어 프롬프트`n경로 공백 및 😀`n"
    $code = Invoke-Utf8Process `
        -Command $currentPowerShell `
        -Arguments (Get-TestPowerShellArguments $streamScript) `
        -InputText $input `
        -StdoutPath $stdout `
        -StderrPath $stderr
    if ($code -ne 0) { throw "mock returned $code" }
    $expected = (New-Object Text.UTF8Encoding -ArgumentList $false, $true).GetBytes($input)
    $actual = [IO.File]::ReadAllBytes($inputReceipt)
    if ([Convert]::ToBase64String($expected) -cne [Convert]::ToBase64String($actual)) { throw "UTF-8 stdin bytes differ" }
    $expectedCodexWorkingDirectory = [IO.Path]::GetFullPath(
        (Split-Path -Parent $currentPowerShell)
    )
    $observedCodexWorkingDirectory = [IO.File]::ReadAllText($workingDirectoryReceipt).Trim()
    if (-not [StringComparer]::Ordinal.Equals($expectedCodexWorkingDirectory, ([IO.Path]::GetFullPath($observedCodexWorkingDirectory)))) { throw "Codex process inherited repository/current working directory instead of executable parent" }
    $strict = New-Object Text.UTF8Encoding -ArgumentList $false, $true
    $outText = $strict.GetString([IO.File]::ReadAllBytes($stdout)); $errText = $strict.GetString([IO.File]::ReadAllBytes($stderr))
    if (-not $outText.Contains('"text":"한글"') -or -not $outText.Contains('"i":20000')) { throw "stdout capture incomplete" }
    if (-not $errText.Contains('오류-stream-20000')) { throw "stderr capture incomplete" }
    Write-Host "PASS: UTF-8 concurrent large stdout/stderr direct executable mock with space-bearing paths"

    $timeoutScript = @'
$inputStream = [Console]::OpenStandardInput()
$inputStream.CopyTo([IO.Stream]::Null)
[Threading.Thread]::Sleep(3000)
'@
    $codexTimeoutRejected = $false
    try {
        [void](Invoke-Utf8Process `
            -Command $currentPowerShell `
            -Arguments (Get-TestPowerShellArguments $timeoutScript) `
            -InputText "deadline`n" `
            -StdoutPath $stdout `
            -StderrPath $stderr `
            -TimeoutSeconds 1)
    }
    catch { $codexTimeoutRejected = $_.Exception.Message -match 'hard timeout' }
    if (-not $codexTimeoutRejected) { throw "Codex process helper accepted a process past its hard deadline" }
    Write-Host "PASS: Codex process helper enforces a hard execution deadline"

    $heartbeatScript = @'
$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8

$inputStream = [Console]::OpenStandardInput()
$inputStream.CopyTo([IO.Stream]::Null)

for ($i = 1; $i -le 20000; $i += 1) {
    [Console]::Out.WriteLine(
        '{"type":"item","i":' +
        $i +
        ',"padding":"abcdefghijklmnopqrstuvwxyz0123456789"}'
    )
}

[Console]::Out.WriteLine(
    '{"type":"thread.started","thread_id":"01990000-0000-4000-8000-000000000001"}'
)

[Threading.Thread]::Sleep(2200)

[Console]::Out.WriteLine('{"type":"turn.completed"}')
[Console]::Out.Flush()
'@
    $heartbeatStdout = Join-Path $temp "heartbeat.jsonl"
    $heartbeatStderr = Join-Path $temp "heartbeat-errors.log"
    $heartbeatMessages = @(& {
        Invoke-Utf8Process -Command $currentPowerShell -Arguments (Get-TestPowerShellArguments $heartbeatScript) -InputText "heartbeat`n" `
            -StdoutPath $heartbeatStdout -StderrPath $heartbeatStderr -RunId "heartbeat-test" `
            -HeartbeatSeconds 1 -ResumeCommand "resume-exact"
    } 6>&1 | ForEach-Object { $_.ToString() })
    if (-not ($heartbeatMessages -match '^RUNNING: run_id=heartbeat-test, elapsed=.+, progress=.+, stdout_bytes=[0-9]+, stderr_bytes=[0-9]+')) {
        throw "heartbeat console message missing"
    }
    if (-not ($heartbeatMessages -match 'stdout_bytes=[1-9][0-9]{6,}.*event=(item|thread\.started)')) { throw "bounded tail did not summarize a complete event from the large JSONL: $($heartbeatMessages -join ' | ')" }
    $heartbeatRaw = [IO.File]::ReadAllText($heartbeatStdout, $strict)
    if ($heartbeatRaw.Contains('RUNNING:') -or -not $heartbeatRaw.Contains('"type":"turn.completed"')) {
        throw "heartbeat altered raw JSONL evidence"
    }
    Write-Host "PASS: heartbeat is console-only while JSONL remains byte-faithful"

    $cmd = Join-Path $temp "forbidden-shell-shim.cmd"
    [IO.File]::WriteAllText($cmd, "@echo off`r`nexit /b 0`r`n", [Text.Encoding]::ASCII)
    $shimRejected = $false
    try {
        [void](Invoke-Utf8Process -Command $cmd -Arguments @() -InputText "forbidden`n" -StdoutPath $stdout -StderrPath $stderr)
    } catch {
        $shimRejected = $_.Exception.Message -match "shell shims are forbidden"
    }
    if (-not $shimRejected) { throw "Invoke-Utf8Process accepted a .cmd shell shim" }
    Write-Host "PASS: process helper rejects .cmd/.bat shell shims"

    $validatorWorkingDirectory = [IO.Path]::GetFullPath((Split-Path -Parent $currentPowerShell)).Replace("'", "''")
    $utf8NoBom = New-Object Text.UTF8Encoding -ArgumentList $false
    $bomValidator = @'
[CmdletBinding()]
param(
    [string]$ResultPath,
    [string]$ExpectedRunId,
    [string]$ProjectRoot,
    [string]$ExpectedAttemptStartedAt
)
[Console]::Error.WriteLine(
    'REVIEW_PENDING [RESULT-UNSIGNED] bom-validator'
)
exit 5
'@
    $bomPreamble = (New-Object Text.UTF8Encoding -ArgumentList $true).GetPreamble()
    $bodyBytes = $utf8NoBom.GetBytes($bomValidator)
    $bomBytes = New-Object byte[] ($bomPreamble.Length + $bodyBytes.Length)
    [Buffer]::BlockCopy($bomPreamble, 0, $bomBytes, 0, $bomPreamble.Length)
    [Buffer]::BlockCopy($bodyBytes, 0, $bomBytes, $bomPreamble.Length, $bodyBytes.Length)
    $bomResult = Invoke-TrustedValidatorProcess `
        -PowerShellCommand $currentPowerShell `
        -TrustedValidatorBytes $bomBytes `
        -ResultPath (Join-Path $temp 'unused-bom.json') `
        -ExpectedRunId 'bom-validator-test' `
        -ProjectRoot $temp `
        -ExpectedAttemptStartedAt ([DateTimeOffset]::UtcNow.ToString('o'))
    if ($bomResult.ExitCode -ne 5 -or $bomResult.Text -notmatch 'REVIEW_PENDING \[RESULT-UNSIGNED\]' -or $bomResult.Text -notmatch 'bom-validator' -or $bomResult.Text -match 'ParseException|CLIXML') { throw "BOM validator did not execute with exit 5: $($bomResult.Text)" }
    Write-Host 'PASS: BOM-prefixed trusted validator executes with exact original-byte trust binding'

    $malformedBytes = $utf8NoBom.GetBytes('[CmdletBinding()] param(')
    $malformedResult = Invoke-TrustedValidatorProcess `
        -PowerShellCommand $currentPowerShell `
        -TrustedValidatorBytes $malformedBytes `
        -ResultPath (Join-Path $temp 'unused-malformed.json') `
        -ExpectedRunId 'malformed-validator-test' `
        -ProjectRoot $temp `
        -ExpectedAttemptStartedAt ([DateTimeOffset]::UtcNow.ToString('o'))
    if ($malformedResult.ExitCode -ne 6 -or $malformedResult.Text -notmatch 'FAIL \[TRUSTED-VALIDATOR-HOST\]' -or $malformedResult.Text -notmatch 'ParserError|Incomplete|Unexpected') { throw "malformed validator did not fail closed with exit 6: $($malformedResult.Text)" }
    Write-Host 'PASS: malformed trusted validator fails closed with exit 6'

    $unexpectedReturnBytes = $utf8NoBom.GetBytes('@("unexpected-return")')
    $unexpectedReturn = Invoke-TrustedValidatorProcess `
        -PowerShellCommand $currentPowerShell `
        -TrustedValidatorBytes $unexpectedReturnBytes `
        -ResultPath (Join-Path $temp 'unused-return.json') `
        -ExpectedRunId 'unexpected-return-test' `
        -ProjectRoot $temp `
        -ExpectedAttemptStartedAt ([DateTimeOffset]::UtcNow.ToString('o'))
    if ($unexpectedReturn.ExitCode -ne 6 -or $unexpectedReturn.Text -notmatch 'trusted validator returned without explicit process exit') { throw "unexpected validator return was not fail-closed: $($unexpectedReturn.Text)" }
    Write-Host 'PASS: trusted validator unexpected return fails closed with exit 6'

    $largeValidator = ("# trusted validator padding`n" * 4096) + @'
param([string]$ResultPath,[string]$ExpectedRunId,[string]$ProjectRoot,[string]$ExpectedAttemptStartedAt)
if ($ExpectedRunId -cne "large-validator-test") { exit 9 }
if (-not [StringComparer]::Ordinal.Equals([IO.Path]::GetFullPath([Environment]::CurrentDirectory), '__TRUSTED_EXECUTABLE_PARENT__')) { exit 10 }
exit 0
'@
    $largeValidator = $largeValidator.Replace("__TRUSTED_EXECUTABLE_PARENT__", $validatorWorkingDirectory)
    $largeBytes = (New-Object Text.UTF8Encoding -ArgumentList $false).GetBytes($largeValidator)
    if ($largeBytes.Length -le 32768) { throw "large trusted validator fixture is too small" }
    $validatorResult = Invoke-TrustedValidatorProcess -PowerShellCommand $currentPowerShell -TrustedValidatorBytes $largeBytes -ResultPath (Join-Path $temp "unused.json") -ExpectedRunId "large-validator-test" -ProjectRoot $temp -ExpectedAttemptStartedAt ([DateTimeOffset]::UtcNow.ToString("o"))
    if ($validatorResult.ExitCode -ne 0) { throw "large stdin validator failed: $($validatorResult.Text)" }
    Write-Host "PASS: validator larger than Windows command-line limit executes from preloaded stdin bytes"
} finally {
    [Console]::InputEncoding = $savedConsoleInputEncoding
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
