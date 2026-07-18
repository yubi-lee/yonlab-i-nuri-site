[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\Views\yonlab-inuri-site",
    [string]$ReleaseTrustPath = "C:\ProgramData\YOnLab\release-trust.json",
    [ValidateSet("Implement", "VerifyCandidate", "VerifyAccepted", "PolicySelfTest")][string]$Mode = "Implement",
    [string]$AttestationBundlePath = "",
    [string]$PolicyFixture = "",
    [switch]$DryRun,
    [string]$ResumeRun,
    [string]$ReleaseId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }

$ExpectedRoot = "D:\Views\yonlab-inuri-site"
$ExpectedBranch = "feat/ai-training-platform-v1"
$ExpectedRemote = "https://github.com/yubi-lee/yonlab-i-nuri-site.git"
$ExpectedRepo = "yubi-lee/yonlab-i-nuri-site"
$ExpectedReleaseTrustPath = "C:\ProgramData\YOnLab\release-trust.json"
$CanonicalRunnerHost = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$CanonicalRunnerPath = "D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1"
$ProtectedHooksPath = "C:\ProgramData\YOnLab\empty-git-hooks"
$ProtectedTrustRoot = "C:\ProgramData\YOnLab"
$ProtectedGpgHome = "C:\ProgramData\YOnLab\gnupg"
$PlanningRelative = "docs/planning/ai-training-platform-v1"
$BaselineRelative = "$PlanningRelative/design-baseline.json"
$PromptRelative = "$PlanningRelative/11-codex-one-shot-implementation-prompt.md"
$OutputSchemaRelative = "$PlanningRelative/codex-output.schema.json"
$StrictSchemaRelative = "$PlanningRelative/codex-final-result.schema.json"
$DeliverableContractRelative = "$PlanningRelative/14-final-document-deliverables.md"
$FinalDocumentInventoryRelative = "$PlanningRelative/final-document-inventory.json"
$ValidatorRelative = "scripts/validate-codex-final-result.ps1"
$ArtifactRelative = ".artifacts/codex"
$RequiredCiChecks = @("design-package-linux", "design-package-windows", "security-and-schema", "release-signatures")
$AcceptanceDueWindowHours = 168
$EvidenceFreshnessWindowHours = 720
$MaxJsonBytes = 8388608
$MaxJsonlBytes = 268435456
$MaxJsonlLineBytes = 1048576
$MaxNativeCaptureBytes = 67108864
$MaxNativeSeconds = 120
$MaxCodexSeconds = 21600
$MaxWorktreeSnapshotBytes = 268435456
$MaxWorktreeFileBytes = 67108864
$MaxWorktreeFiles = 20000
$MaxIgnoredWorktreeSnapshotBytes = 2147483648L
$MaxIgnoredWorktreeFiles = 200000
$TrustedProtectionOwnerSids = @(
    "S-1-5-18", # LOCAL SYSTEM
    "S-1-5-32-544", # BUILTIN\Administrators
    "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464" # TrustedInstaller
)
$script:ActiveRunId = $null
$script:ActiveReleaseId = $null
$script:ResumeAvailable = $false
$script:GitHubCredentialHelper = $null

function Assert-GuardedReleaseId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )
    if ($Value -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+-(?:rc|RC)[0-9]+$') {
        Stop-Launcher 'RELEASE-IDENTITY' 'Implement requires an explicit safe RC SemVer release ID' 6
    }
    return $Value
}
function ConvertTo-UtcRfc3339Z {
    param(
        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$Value
    )
    return $Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'", [Globalization.CultureInfo]::InvariantCulture)
}
function Get-ResumeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        [Parameter(Mandatory = $true)]
        [string]$ReleaseId
    )
    return "& '$CanonicalRunnerHost' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File '$CanonicalRunnerPath' -Mode Implement -ReleaseId '$ReleaseId' -ResumeRun '$RunId'"
}
function Stop-Launcher([string]$Code, [string]$Message, [int]$ExitCode = 2) {
    [Console]::Error.WriteLine("FAIL [$Code]: $Message")
    if ($null -ne $script:ActiveRunId) {
        if ($script:ResumeAvailable) { [Console]::Error.WriteLine("RESUME: $(Get-ResumeCommand -RunId $script:ActiveRunId -ReleaseId $script:ActiveReleaseId)") }
        else { [Console]::Error.WriteLine("RESUME-UNAVAILABLE: no single validated thread.started UUID/state receipt; --last is forbidden") }
    }
    exit $ExitCode
}

function New-CodexRuntimeEnvelope {
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$AttemptId,
        [Parameter(Mandatory = $true)][string]$AttemptStartedAt,
        [Parameter(Mandatory = $true)][string]$InitialHead,
        [Parameter(Mandatory = $true)][string]$ReleaseId,
        [Parameter(Mandatory = $true)][string]$ModeName,
        [Parameter(Mandatory = $true)][string]$ResumeCommand
    )
    if ($RunId -notmatch '^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$') {
        Stop-Launcher 'RUNTIME-IDENTITY' 'invalid guarded runtime run ID' 6
    }
    [void](Assert-GuardedReleaseId $ReleaseId)
    return @"
[GUARDED RUNTIME IDENTITY — LAUNCHER SUPPLIED]

The following values are authoritative and must not be guessed, renamed,
reformatted, or replaced:

run_id=$RunId
release_id=$ReleaseId
attempt_id=$AttemptId
attempt_started_at=$AttemptStartedAt
initial_head=$InitialHead
mode=$ModeName
resume_command=$ResumeCommand

Final JSON requirements:

- run_id MUST equal exactly $RunId.
- release_id MUST equal exactly $ReleaseId.
- Do not invent, increment, normalize, or replace release_id.
- Do not append branch, date, status, blocked, readonly, or build metadata to release_id.
- Use the same release_id for generated document path expansion.
- When reporting IMPLEMENTATION_BLOCKED, preserve the same release_id.
- When resuming, preserve the original release_id.
- Do not generate a value beginning with run-.
- Do not derive run_id from date, branch, task, candidate phase, or release ID.
- repository.baseline_commit MUST equal exactly $InitialHead.
- When reporting a blocked result, preserve the same exact run_id.
- When resuming, preserve the original run_id and thread identity.
- If these values cannot be honored, produce no substitute identity.

[END GUARDED RUNTIME IDENTITY]
"@
}

function New-RuntimeCodexOutputSchemaText {
    param(
        [Parameter(Mandatory = $true)][string]$TrustedSchemaText,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$ReleaseId
    )
    if ($RunId -notmatch '^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$') {
        Stop-Launcher 'RUNTIME-SCHEMA' 'invalid guarded run ID for runtime schema' 6
    }
    [void](Assert-GuardedReleaseId $ReleaseId)
    $schema = ConvertFrom-StrictJsonText $TrustedSchemaText 'trusted model-facing output schema'
    if ($null -eq $schema.properties -or $null -eq $schema.properties.PSObject.Properties['run_id']) {
        Stop-Launcher 'RUNTIME-SCHEMA' 'trusted schema has no run_id property' 6
    }
    if ($null -eq $schema.properties.PSObject.Properties['release_id']) {
        Stop-Launcher 'RUNTIME-SCHEMA' 'trusted schema has no release_id property' 6
    }
    # properties.release_id exact enum binding
    $releaseProperty = $schema.properties.PSObject.Properties['release_id'].Value
    if ([string]$releaseProperty.type -cne 'string') {
        Stop-Launcher 'RUNTIME-SCHEMA' 'trusted schema release_id is not a string' 6
    }
    if ($null -ne $releaseProperty.PSObject.Properties['enum']) {
        Stop-Launcher 'RUNTIME-SCHEMA' 'trusted base schema unexpectedly fixes release_id' 6
    }
    $runProperty = $schema.properties.PSObject.Properties['run_id'].Value
    if ([string]$runProperty.type -cne 'string') {
        Stop-Launcher 'RUNTIME-SCHEMA' 'trusted schema run_id is not a string' 6
    }
    if ($null -ne $runProperty.PSObject.Properties['enum']) {
        Stop-Launcher 'RUNTIME-SCHEMA' 'trusted base schema unexpectedly fixes run_id' 6
    }
    $runProperty | Add-Member -NotePropertyName enum -NotePropertyValue ([object[]]@($RunId))
    $releaseProperty | Add-Member -NotePropertyName enum -NotePropertyValue ([object[]]@($ReleaseId))
    return ($schema | ConvertTo-Json -Depth 100 -Compress)
}

function Assert-RuntimeCodexOutputSchemaBinding {
    param(
        [Parameter(Mandatory = $true)][string]$SchemaPath,
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$ReleaseId,
        [Parameter(Mandatory = $true)][string]$AttemptId,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )
    $expectedPath = [IO.Path]::GetFullPath((Join-Path $RunDirectory "runtime-output-schema-$AttemptId.json"))
    $actualPath = [IO.Path]::GetFullPath($SchemaPath)
    if ($actualPath -cne $expectedPath -or -not $actualPath.StartsWith([IO.Path]::GetFullPath($RunDirectory) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        Stop-Launcher "RUNTIME-SCHEMA" "runtime output schema path is not the exact active-attempt path" 6
    }
    Assert-NoReparseComponent $actualPath "RUNTIME-SCHEMA"
    [void](Assert-BoundedFile $actualPath $MaxJsonBytes "RUNTIME-SCHEMA-SIZE" "runtime output schema")
    $actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $actualPath).Hash.ToLowerInvariant()
    if ($actualSha256 -cne $ExpectedSha256) { Stop-Launcher "RUNTIME-SCHEMA" "runtime output schema hash changed" 6 }
    $schemaText = Read-Utf8NoBomText $actualPath $MaxJsonBytes "runtime output schema"
    $schema = ConvertFrom-StrictJsonText $schemaText "runtime output schema"
    if ($null -eq $schema.properties -or $null -eq $schema.properties.PSObject.Properties['run_id']) {
        Stop-Launcher "RUNTIME-SCHEMA" "runtime output schema has no run_id property" 6
    }
    $runProperty = $schema.properties.PSObject.Properties['run_id'].Value
    if ([string]$runProperty.type -cne 'string' -or $null -eq $runProperty.PSObject.Properties['enum']) {
        Stop-Launcher "RUNTIME-SCHEMA" "runtime output schema run_id binding is incomplete" 6
    }
    $enumValues = @($runProperty.enum)
    if ($enumValues.Count -ne 1 -or [string]$enumValues[0] -cne $RunId) {
        Stop-Launcher "RUNTIME-SCHEMA" "runtime output schema run_id enum is not the exact active guarded run" 6
    }
    if ($null -eq $schema.properties.PSObject.Properties['release_id']) {
        Stop-Launcher "RUNTIME-SCHEMA" "runtime output schema has no release_id property" 6
    }
    $releaseProperty = $schema.properties.PSObject.Properties['release_id'].Value
    if ([string]$releaseProperty.type -cne 'string' -or $null -eq $releaseProperty.PSObject.Properties['enum']) {
        Stop-Launcher "RUNTIME-SCHEMA" "runtime output schema release_id binding is incomplete" 6
    }
    $releaseEnumValues = @($releaseProperty.enum)
    if ($releaseEnumValues.Count -ne 1 -or [string]$releaseEnumValues[0] -cne $ReleaseId -or [string]$ReleaseId -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+-(?:rc|RC)[0-9]+$') {
        Stop-Launcher "RUNTIME-SCHEMA" "runtime output schema release_id enum is not the exact active guarded release" 6
    }
    return $schema
}
function Write-Pass([string]$Message) { Write-Host "PASS: $Message" }
function Canonical([string]$Path) { return [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\','/')) }
function Get-WindowsPowerShellModulePathPolicy([string]$Edition, [string]$PsHomePath, [string]$WindowsDirectory, [string[]]$CurrentEntries) {
    $current = @($CurrentEntries | ForEach-Object { [string]$_ })
    if ($Edition -cne "Desktop") {
        return [pscustomobject]@{
            should_normalize=$false; safe_paths=@(); normalized_entries=$current; removed_entries=@()
            normalized_path=($current -join [IO.Path]::PathSeparator)
        }
    }
    $safeCandidates=@(
        (Join-Path $PsHomePath "Modules")
        (Join-Path $WindowsDirectory "system32\WindowsPowerShell\v1.0\Modules")
    )
    $safeLookup=New-Object 'Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    $safePaths=New-Object 'Collections.Generic.List[string]'
    foreach ($candidate in $safeCandidates) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        $canonical=Canonical ([string]$candidate)
        if ($safeLookup.Add($canonical)) { [void]$safePaths.Add($canonical) }
    }
    $normalizedEntries=@($safePaths.ToArray())
    $removedEntries=@($current | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_) -or -not $safeLookup.Contains((Canonical ([string]$_)))
    })
    return [pscustomobject]@{
        should_normalize=$true; safe_paths=$normalizedEntries; normalized_entries=$normalizedEntries; removed_entries=$removedEntries
        normalized_path=($normalizedEntries -join [IO.Path]::PathSeparator)
    }
}
function Initialize-WindowsPowerShellModulePath {
    if ($PSEdition -cne "Desktop") { return }
    $currentEntries=@()
    if (-not [string]::IsNullOrEmpty([string]$env:PSModulePath)) {
        $separator=[regex]::Escape([string][IO.Path]::PathSeparator)
        $currentEntries=@([string]$env:PSModulePath -split $separator)
    }
    try {
        $policy=Get-WindowsPowerShellModulePathPolicy $PSEdition $PSHOME $env:WINDIR $currentEntries
    } catch {
        Stop-Launcher "PRE-ENV" "Windows PowerShell module path normalization failed" 6
    }
    $env:PSModulePath=[string]$policy.normalized_path
}
function Get-ForbiddenExecutionEnvironmentNames {
    return @(
        "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_SYSTEM", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM",
        "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_INDEX_FILE", "GIT_NAMESPACE", "GIT_REPLACE_REF_BASE", "GIT_EXEC_PATH", "GIT_TEMPLATE_DIR", "GIT_EXTERNAL_DIFF", "GIT_DIFF_OPTS", "GIT_PAGER", "GIT_ASKPASS", "GIT_EDITOR", "GIT_SEQUENCE_EDITOR",
        "GIT_ATTR_NOSYSTEM", "GIT_CEILING_DIRECTORIES", "GIT_DISCOVERY_ACROSS_FILESYSTEM", "GIT_TERMINAL_PROMPT",
        "GCM_INTERACTIVE", "SSH_ASKPASS", "SSH_ASKPASS_REQUIRE", "GNUPGHOME", "GPG_TTY", "GPG_AGENT_INFO", "GH_HOST", "GH_CONFIG_DIR"
    )
}
function Assert-NoExecutionEnvironmentOverrides {
    $exact = New-Object 'Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in (Get-ForbiddenExecutionEnvironmentNames)) { [void]$exact.Add($name) }
    $prefixes = @("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_", "GIT_SSH")
    foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
        $name = [string]$entry.Key; $value = [string]$entry.Value
        if ([string]::IsNullOrEmpty($value)) { continue }
        $prefixMatch = $false
        foreach ($prefix in $prefixes) { if ($name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $prefixMatch = $true; break } }
        if ($exact.Contains($name) -or $prefixMatch) { Stop-Launcher "PRE-ENV" "execution-affecting environment override must be unset: $name" }
    }
}
function Set-SafeProcessEnvironment($ProcessStartInfo) {
    # The parent process must be clean before the first Git call. The child
    # environment is independently fail-closed so system/global Git config,
    # indexed config injection, attributes, and pager controls cannot leak in.
    $environment = $ProcessStartInfo.EnvironmentVariables
    foreach ($existingName in @($environment.Keys)) {
        if ([string]$existingName -match '^(?:GIT_CONFIG_COUNT|GIT_CONFIG_PARAMETERS|GIT_CONFIG_KEY_.*|GIT_CONFIG_VALUE_.*|GIT_CONFIG_SYSTEM|GIT_CONFIG_GLOBAL|GIT_CONFIG_NOSYSTEM|GIT_ATTR_NOSYSTEM)$') { [void]$environment.Remove([string]$existingName) }
    }
    [void]$environment.Remove("GIT_PAGER")
    $environment["GIT_CONFIG_NOSYSTEM"] = "1"
    $environment["GIT_CONFIG_GLOBAL"] = "NUL"
    $environment["GIT_CONFIG_SYSTEM"] = "NUL"
    $environment["GIT_ATTR_NOSYSTEM"] = "1"
    $environment["GIT_TERMINAL_PROMPT"] = "0"
    $environment["GCM_INTERACTIVE"] = "Never"
    $environment["GIT_OPTIONAL_LOCKS"] = "0"
    $environment["PAGER"] = "cat"
    $environment["GNUPGHOME"] = $ProtectedGpgHome
    if (-not [string]::IsNullOrWhiteSpace([string]$script:GitHubCredentialHelper)) {
        # The only injected config is a runner-built, absolute-path gh helper
        # for github.com HTTPS credentials. Ambient indexed config is rejected.
        $environment["GIT_CONFIG_COUNT"] = "1"
        $environment["GIT_CONFIG_KEY_0"] = "credential.https://github.com.helper"
        $environment["GIT_CONFIG_VALUE_0"] = [string]$script:GitHubCredentialHelper
    }
}
function Get-TrustedExecutableWorkingDirectory([string]$Command) {
    if ([string]::IsNullOrWhiteSpace($Command) -or -not [IO.Path]::IsPathRooted($Command)) { throw "trusted process command must be an absolute executable path" }
    try { $resolvedCommand=Canonical (Resolve-Path -LiteralPath $Command -ErrorAction Stop).Path } catch { throw "trusted process command cannot be resolved: $Command" }
    if (-not (Test-Path -LiteralPath $resolvedCommand -PathType Leaf)) { throw "trusted process command is not a file: $resolvedCommand" }
    $parent=[IO.Path]::GetDirectoryName($resolvedCommand)
    if ([string]::IsNullOrWhiteSpace($parent) -or -not (Test-Path -LiteralPath $parent -PathType Container)) { throw "trusted executable parent directory cannot be resolved: $resolvedCommand" }
    return Canonical $parent
}
function Assert-HostInvocationObservation($Observation, [string]$Code = "POLICY-HOST") {
    $hostStartupArgumentsValid=$true
    if ($null -ne $Observation.PSObject.Properties["host_startup_arguments_valid"]) { $hostStartupArgumentsValid=[bool]$Observation.host_startup_arguments_valid }
    $argv0IsBareName=$false
    if ($null -ne $Observation.PSObject.Properties["argv0_is_bare_name"]) { $argv0IsBareName=[bool]$Observation.argv0_is_bare_name }
    if ($Observation.is_windows -ne $true -or $Observation.process_path_is_canonical -ne $true -or $Observation.process_has_reparse -ne $false -or -not $hostStartupArgumentsValid -or (($Observation.argv0_matches -ne $true) -and -not $argv0IsBareName) -or $Observation.argv_prefix_matches -ne $true -or
        [string]$Observation.host_name -cne "powershell.exe" -or -not [StringComparer]::OrdinalIgnoreCase.Equals([string]$Observation.process_path,[string]$Observation.expected_process_path) -or
        [string]$Observation.expected_process_path -notmatch '^[A-Za-z]:\\Windows\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe$' -or [int]$Observation.no_profile_count -ne 1 -or
        [int]$Observation.non_interactive_count -ne 1 -or [int]$Observation.file_count -ne 1 -or [int]$Observation.forbidden_switch_count -ne 0 -or
        $Observation.file_target_matches -ne $true) {
        Stop-Launcher $Code "production runner requires one canonical direct Windows PowerShell host with exact -NoProfile -NonInteractive -File startup and no command-mode switches" 6
    }
}

function Assert-CanonicalProductionHostInvocation([string]$SelectedMode, [string]$RunnerPath) {
    if ($SelectedMode -ceq "PolicySelfTest") { return } # explicit cross-platform executable-fixture exception
    if ($env:OS -cne "Windows_NT") { Stop-Launcher "PRE-HOST" "production modes require a canonical Windows PowerShell host" }
    try {
        $processPath=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $processFull=[IO.Path]::GetFullPath($processPath)
        $processResolved=Canonical (Resolve-Path -LiteralPath $processPath -ErrorAction Stop).Path
        $expectedProcessPath=Canonical (Resolve-Path -LiteralPath (Join-Path ([Environment]::SystemDirectory) "WindowsPowerShell\v1.0\powershell.exe") -ErrorAction Stop).Path
    } catch { Stop-Launcher "PRE-HOST" "active PowerShell host path cannot be resolved" }
    Assert-NoReparseComponent $processResolved "PRE-HOST"
    Assert-NoReparseComponent $expectedProcessPath "PRE-HOST"
    $arguments=@([Environment]::GetCommandLineArgs())
    $noProfile=@($arguments | Where-Object { [string]$_ -ieq "-NoProfile" }).Count
    $nonInteractive=@($arguments | Where-Object { [string]$_ -ieq "-NonInteractive" }).Count
    $fileIndexes=@(for($index=0;$index -lt $arguments.Count;$index+=1){if([string]$arguments[$index] -ieq "-File"){$index}})
    $forbiddenTokens=@("-Command","-CommandWithArgs","-EncodedCommand","-EncodedArguments","-NoExit","-Interactive","-WorkingDirectory","-PSConsoleFile","-Version")
    $forbidden=@($arguments | Where-Object { $forbiddenTokens -icontains [string]$_ }).Count
    $fileTargetMatches=$false
    $resolvedRunnerPath=$null
    if ($fileIndexes.Count -eq 1 -and $fileIndexes[0] + 1 -lt $arguments.Count) {
        $fileArgument=[string]$arguments[$fileIndexes[0] + 1]
        if ([IO.Path]::IsPathRooted($fileArgument)) {
            try { $resolvedRunnerPath=Canonical (Resolve-Path -LiteralPath $RunnerPath -ErrorAction Stop).Path; $fileTargetMatches=[StringComparer]::OrdinalIgnoreCase.Equals((Canonical (Resolve-Path -LiteralPath $fileArgument -ErrorAction Stop).Path),$resolvedRunnerPath) } catch { $fileTargetMatches=$false }
        }
    }
    $hostStartupArgumentsValid=$false
    if ($fileIndexes.Count -eq 1 -and $fileIndexes[0] -gt 0 -and $fileIndexes[0] + 1 -lt $arguments.Count) {
        $hostStartupArgumentsValid=$true
        $fileIndex=[int]$fileIndexes[0]
        $startupNoLogo=0
        $startupNoProfile=0
        $startupNonInteractive=0
        $startupExecutionPolicy=0
        for ($index=1; $index -lt $fileIndex; $index+=1) {
            $token=[string]$arguments[$index]
            if ($token -ieq "-NoLogo") {
                $startupNoLogo+=1
                if ($startupNoLogo -gt 1) { $hostStartupArgumentsValid=$false }
            } elseif ($token -ieq "-NoProfile") {
                $startupNoProfile+=1
            } elseif ($token -ieq "-NonInteractive") {
                $startupNonInteractive+=1
            } elseif ($token -ieq "-ExecutionPolicy") {
                $startupExecutionPolicy+=1
                if ($startupExecutionPolicy -gt 1 -or $index + 1 -ge $fileIndex -or [string]$arguments[$index + 1] -cne "Bypass") {
                    $hostStartupArgumentsValid=$false
                } else {
                    $index+=1
                }
            } else {
                $hostStartupArgumentsValid=$false
            }
        }
        if ($startupNoProfile -ne 1 -or $startupNonInteractive -ne 1 -or $startupNoLogo -gt 1 -or $startupExecutionPolicy -gt 1) {
            $hostStartupArgumentsValid=$false
        }
    }
    $argv0Matches=$false
    $argv0IsBareName=$false
    if ($arguments.Count -gt 0) {
        $argv0=[string]$arguments[0]
        if ([StringComparer]::OrdinalIgnoreCase.Equals($argv0,[IO.Path]::GetFileName($expectedProcessPath))) {
            $argv0IsBareName=$true
        } elseif ([IO.Path]::IsPathRooted($argv0)) {
            try { $argv0Matches=[StringComparer]::OrdinalIgnoreCase.Equals((Canonical (Resolve-Path -LiteralPath $argv0 -ErrorAction Stop).Path),$processResolved) } catch { $argv0Matches=$false }
        }
    }
    $argvPrefixMatches=$hostStartupArgumentsValid -and $fileTargetMatches
    $observation=[pscustomobject]@{
        is_windows=$true;process_path=$processResolved;expected_process_path=$expectedProcessPath;process_path_is_canonical=([IO.Path]::IsPathRooted($processPath) -and [StringComparer]::OrdinalIgnoreCase.Equals($processFull.TrimEnd([char[]]@('\','/')),$processResolved))
        process_has_reparse=$false;host_name=[IO.Path]::GetFileName($processResolved);argv0_matches=$argv0Matches;argv0_is_bare_name=$argv0IsBareName;argv_prefix_matches=$argvPrefixMatches
        no_profile_count=$noProfile;non_interactive_count=$nonInteractive;file_count=$fileIndexes.Count;forbidden_switch_count=$forbidden;file_target_matches=$fileTargetMatches;host_startup_arguments_valid=$hostStartupArgumentsValid
    }
    Assert-HostInvocationObservation $observation "PRE-HOST"
    Write-Pass "PRE-HOST canonical direct no-profile non-interactive PowerShell file invocation"
}
function Native([string]$Command, [string[]]$Arguments = @()) {
    $captured = Invoke-NativeCaptureBytes $Command $Arguments $MaxNativeCaptureBytes
    $strictUtf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
    try { $stdoutText = $strictUtf8.GetString($captured.Bytes) } catch { throw "native stdout is not strict UTF-8" }
    $combined = $(if ([string]::IsNullOrWhiteSpace($captured.ErrorText)) { $stdoutText } elseif ([string]::IsNullOrWhiteSpace($stdoutText)) { $captured.ErrorText } else { $stdoutText.TrimEnd([char[]]@([char]13,[char]10)) + "`n" + $captured.ErrorText })
    return [pscustomobject]@{ ExitCode=$captured.ExitCode; Text=$combined.Trim() }
}
function Native-ReadOnly([string]$Command, [string[]]$Arguments = @()) {
    $captured = Invoke-NativeCaptureBytes -Command $Command -Arguments $Arguments -MaximumBytes $MaxNativeCaptureBytes -IsolationMode "BestEffortReadOnly" -ReadOnlyProbe
    $strictUtf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
    try { $stdoutText = $strictUtf8.GetString($captured.Bytes) } catch { throw "native stdout is not strict UTF-8" }
    $combined = $(if ([string]::IsNullOrWhiteSpace($captured.ErrorText)) { $stdoutText } elseif ([string]::IsNullOrWhiteSpace($stdoutText)) { $captured.ErrorText } else { $stdoutText.TrimEnd([char[]]@([char]13,[char]10)) + "`n" + $captured.ErrorText })
    return [pscustomobject]@{ ExitCode=$captured.ExitCode; Text=$combined.Trim() }
}
function Native-OK($Result, [string]$Code, [string]$Operation) { if ($Result.ExitCode -ne 0) { Stop-Launcher $Code "$Operation failed ($($Result.ExitCode)): $($Result.Text)" } }
function Get-SafeGitArguments([string[]]$Arguments) { return @("--no-replace-objects", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=$ProtectedHooksPath", "-c", "core.pager=cat", "-c", "pager.branch=false", "-c", "pager.log=false") + @($Arguments) }
function SafeGit([string]$GitCommand, [string[]]$Arguments = @()) { return Native-ReadOnly $GitCommand (Get-SafeGitArguments $Arguments) }
function TrustedGpg([string]$GpgCommand, [string[]]$Arguments = @()) {
    $gpgSnapshotBefore=Get-ProtectedRootSnapshot $ProtectedGpgHome $ProtectedGpgHome "PRE-GPG" "protected GnuPG home"
    $result=Native-ReadOnly $GpgCommand (@("--homedir", $ProtectedGpgHome, "--no-options", "--no-auto-key-retrieve", "--no-auto-check-trustdb", "--no-autostart", "--lock-never", "--batch", "--no-tty") + @($Arguments))
    Assert-ProtectedGpgHomeUnchanged $gpgSnapshotBefore $ProtectedGpgHome "POST-GPG"
    return $result
}
function Get-GitGpgProgramSpec([string]$GpgCommand, [string]$GpgHome) {
    if (-not (Test-SafeTrustedExecutablePathSyntax $GpgCommand) -or $GpgHome -notmatch '^[A-Za-z]:\\[^"''$`%!;&|<>\x00-\x1f]+$') { Stop-Launcher "PRE-TRUST" "Git GPG program/home paths contain an unsafe shell metacharacter" }
    return '"' + $GpgCommand.Replace('\', '/') + '"'
}
function Get-GitHubCredentialHelperSpec([string]$GhCommand) {
    if (-not (Test-SafeTrustedExecutablePathSyntax $GhCommand)) { Stop-Launcher "PRE-GH" "Git credential helper path contains an unsafe shell metacharacter" }
    return '!"' + $GhCommand.Replace('\', '/') + '" auth git-credential'
}
function String-Sha256([string]$Value) { $sha = [Security.Cryptography.SHA256]::Create(); try { $bytes = (New-Object Text.UTF8Encoding -ArgumentList $false).GetBytes($Value); return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() } }
function Bytes-Sha256([byte[]]$Value) { $sha = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash($Value))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() } }

function Assert-BoundedFile([string]$Path, [long]$MaximumBytes, [string]$Code, [string]$Context) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-Launcher $Code "$Context is missing: $Path" 6 }
    $length = [long](Get-Item -LiteralPath $Path -Force).Length
    if ($length -le 0 -or $length -gt $MaximumBytes) { Stop-Launcher $Code "$Context size $length is outside 1..$MaximumBytes bytes" 6 }
    return $length
}

function Assert-StrictJsonLexical([string]$Text, [string]$Context) {
    # Dependency-free RFC 8259/I-JSON lexical and grammar pass. This is needed
    # because Windows PowerShell 5.1 neither packages JSON.NET for direct use
    # nor rejects comments, NaN, leading-zero numbers, and trailing commas.
    function Read-StrictStringToken([int]$Start) {
        $cursor = $Start + 1
        while ($cursor -lt $Text.Length) {
            $code = [int][char]$Text[$cursor]
            if ($code -eq 0x22) {
                $end = $cursor + 1; $literal = $Text.Substring($Start, $end - $Start)
                try { $decoded = [string]($literal | ConvertFrom-Json) } catch { throw "$Context contains an invalid JSON string" }
                return [pscustomobject]@{End=$end;Decoded=$decoded}
            }
            if ($code -lt 0x20) { throw "$Context contains an unescaped control character" }
            if ($code -eq 0x5c) {
                $cursor += 1
                if ($cursor -ge $Text.Length) { throw "$Context contains an incomplete JSON escape" }
                $escape = $Text[$cursor]
                if ('"\/bfnrt'.IndexOf($escape) -ge 0) { $cursor += 1; continue }
                if ($escape -cne 'u' -or $cursor + 4 -ge $Text.Length) { throw "$Context contains an invalid JSON escape" }
                $hex = $Text.Substring($cursor + 1, 4)
                if ($hex -notmatch '^[0-9A-Fa-f]{4}$') { throw "$Context contains an invalid Unicode escape" }
                $unit = [Convert]::ToInt32($hex, 16); $cursor += 5
                if ($unit -ge 0xD800 -and $unit -le 0xDBFF) {
                    if ($cursor + 5 -ge $Text.Length -or $Text[$cursor] -cne '\' -or $Text[$cursor + 1] -cne 'u') { throw "$Context contains an unpaired high surrogate" }
                    $lowHex = $Text.Substring($cursor + 2, 4)
                    if ($lowHex -notmatch '^[0-9A-Fa-f]{4}$') { throw "$Context contains an invalid low surrogate" }
                    $low = [Convert]::ToInt32($lowHex, 16)
                    if ($low -lt 0xDC00 -or $low -gt 0xDFFF) { throw "$Context contains an unpaired high surrogate" }
                    $cursor += 6
                } elseif ($unit -ge 0xDC00 -and $unit -le 0xDFFF) { throw "$Context contains an unpaired low surrogate" }
                continue
            }
            if ($code -ge 0xD800 -and $code -le 0xDBFF) {
                if ($cursor + 1 -ge $Text.Length -or [int][char]$Text[$cursor + 1] -lt 0xDC00 -or [int][char]$Text[$cursor + 1] -gt 0xDFFF) { throw "$Context contains an unpaired raw high surrogate" }
                $cursor += 2; continue
            }
            if ($code -ge 0xDC00 -and $code -le 0xDFFF) { throw "$Context contains an unpaired raw low surrogate" }
            $cursor += 1
        }
        throw "$Context contains an unterminated JSON string"
    }
    function Read-StrictValueToken([int]$Start) {
        if ($Start -ge $Text.Length) { throw "$Context is missing a JSON value" }
        $character = $Text[$Start]
        if ($character -ceq '{') { return [pscustomobject]@{End=$Start+1;Container='object'} }
        if ($character -ceq '[') { return [pscustomobject]@{End=$Start+1;Container='array'} }
        if ($character -ceq '"') { $token = Read-StrictStringToken $Start; return [pscustomobject]@{End=$token.End;Container=$null} }
        foreach ($literal in @('true','false','null')) { if ($Text.Substring($Start).StartsWith($literal, [StringComparison]::Ordinal)) { return [pscustomobject]@{End=$Start+$literal.Length;Container=$null} } }
        $number = [regex]::Match($Text.Substring($Start), '^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?')
        if ($number.Success) { return [pscustomobject]@{End=$Start+$number.Length;Container=$null} }
        throw "$Context contains an invalid JSON value at offset $Start"
    }
    $containers = New-Object Collections.Stack; $index = 0; $rootState = 'value'
    while ($true) {
        while ($index -lt $Text.Length -and " `t`r`n".IndexOf($Text[$index]) -ge 0) { $index += 1 }
        if ($containers.Count -eq 0) {
            if ($rootState -ceq 'done') { if ($index -ne $Text.Length) { throw "$Context has data after the root value" }; break }
            $rootState = 'done'; $token = Read-StrictValueToken $index; $index = $token.End
            if ($null -ne $token.Container) { $state = $(if ($token.Container -ceq 'object') {'key-or-end'} else {'value-or-end'}); $containers.Push([pscustomobject]@{kind=$token.Container;state=$state;names=$(if ($token.Container -ceq 'object') { New-Object 'Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase) } else { $null })}) }
            continue
        }
        $frame = $containers.Peek()
        if ($frame.kind -ceq 'object') {
            if ($frame.state -ceq 'key-or-end' -and $index -lt $Text.Length -and $Text[$index] -ceq '}') { [void]$containers.Pop(); $index += 1; continue }
            if ($frame.state -ceq 'key-or-end' -or $frame.state -ceq 'key') {
                if ($index -ge $Text.Length -or $Text[$index] -cne '"') { throw "$Context object requires a property string" }
                $key = Read-StrictStringToken $index; $index = $key.End
                if (-not $frame.names.Add($key.Decoded)) { throw "$Context contains a duplicate/ambiguous JSON property: $($key.Decoded)" }
                $frame.state = 'colon'; continue
            }
            if ($frame.state -ceq 'colon') { if ($index -ge $Text.Length -or $Text[$index] -cne ':') { throw "$Context object property requires a colon" }; $frame.state='value'; $index += 1; continue }
            if ($frame.state -ceq 'value') { $frame.state='comma-or-end'; $token=Read-StrictValueToken $index; $index=$token.End; if ($null -ne $token.Container) { $state=$(if ($token.Container -ceq 'object') {'key-or-end'} else {'value-or-end'}); $containers.Push([pscustomobject]@{kind=$token.Container;state=$state;names=$(if ($token.Container -ceq 'object') { New-Object 'Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase) } else { $null })}) }; continue }
            if ($frame.state -ceq 'comma-or-end') { if ($index -lt $Text.Length -and $Text[$index] -ceq ',') { $frame.state='key'; $index += 1; continue }; if ($index -lt $Text.Length -and $Text[$index] -ceq '}') { [void]$containers.Pop(); $index += 1; continue }; throw "$Context object requires comma or end" }
        } else {
            if ($frame.state -ceq 'value-or-end' -and $index -lt $Text.Length -and $Text[$index] -ceq ']') { [void]$containers.Pop(); $index += 1; continue }
            if ($frame.state -ceq 'value-or-end' -or $frame.state -ceq 'value') { $frame.state='comma-or-end'; $token=Read-StrictValueToken $index; $index=$token.End; if ($null -ne $token.Container) { $state=$(if ($token.Container -ceq 'object') {'key-or-end'} else {'value-or-end'}); $containers.Push([pscustomobject]@{kind=$token.Container;state=$state;names=$(if ($token.Container -ceq 'object') { New-Object 'Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase) } else { $null })}) }; continue }
            if ($frame.state -ceq 'comma-or-end') { if ($index -lt $Text.Length -and $Text[$index] -ceq ',') { $frame.state='value'; $index += 1; continue }; if ($index -lt $Text.Length -and $Text[$index] -ceq ']') { [void]$containers.Pop(); $index += 1; continue }; throw "$Context array requires comma or end" }
        }
        throw "$Context parser entered an invalid state"
    }
}

function ConvertFrom-StrictJsonText([string]$Text, [string]$Context, [switch]$ThrowOnError) {
    try { Assert-StrictJsonLexical $Text $Context } catch {
        $message = "$Context is not strict JSON: $($_.Exception.Message)"
        if ($ThrowOnError) { throw $message }
        Stop-Launcher "STRICT-JSON" $message 6
    }
    try {
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey("DateKind")) { return $Text | ConvertFrom-Json -DateKind String }
        return $Text | ConvertFrom-Json
    } catch {
        $message = "$Context conversion failed: $($_.Exception.Message)"
        if ($ThrowOnError) { throw $message }
        Stop-Launcher "STRICT-JSON" $message 6
    }
}

function ConvertFrom-StrictJsonFile([string]$Path, [string]$Context, [long]$MaximumBytes = $MaxJsonBytes) {
    [void](Assert-BoundedFile $Path $MaximumBytes "STRICT-JSON-SIZE" $Context)
    $strictUtf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
    try { $text = [IO.File]::ReadAllText($Path, $strictUtf8) } catch { Stop-Launcher "STRICT-JSON" "$Context is not strict UTF-8: $($_.Exception.Message)" 6 }
    return ConvertFrom-StrictJsonText $text $Context
}

function Get-ProtectedContentWriteMask {
    return [int64]([Security.AccessControl.FileSystemRights]::WriteData -bor [Security.AccessControl.FileSystemRights]::CreateFiles -bor
        [Security.AccessControl.FileSystemRights]::AppendData -bor [Security.AccessControl.FileSystemRights]::CreateDirectories -bor
        [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership)
}


function Assert-ProtectedPathChainObservation($Observation, [string]$Code = "POLICY-PROTECTED-PATH", [string]$Label = "protected path") {
    $expectedOwners=@($TrustedProtectionOwnerSids)
    $observedOwners=@($Observation.trusted_owner_sids)
    if ($observedOwners.Count -ne $expectedOwners.Count -or @(Compare-Object -ReferenceObject $expectedOwners -DifferenceObject $observedOwners).Count -ne 0) {
        Stop-Launcher $Code "$Label trusted owner set differs from SYSTEM/Administrators/TrustedInstaller" 6
    }
    $protectedRoot=[string]$Observation.protected_root
    $nodes=@($Observation.nodes)
    if ([string]::IsNullOrWhiteSpace($protectedRoot) -or $nodes.Count -lt 1) { Stop-Launcher $Code "$Label path chain must include the protected object and YOnLab anchor" 6 }
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals([string]$nodes[$nodes.Count - 1].path, $protectedRoot)) { Stop-Launcher $Code "$Label path chain extends beyond the YOnLab anchor" 6 }
    foreach ($node in $nodes) {
        if ([string]::IsNullOrWhiteSpace([string]$node.path) -or [string]$node.scope -cne "PROTECTED_CONTENT") { Stop-Launcher $Code "$Label path-chain node is outside the protected YOnLab anchor" 6 }
        if ($node.has_reparse_point -ne $false) { Stop-Launcher $Code "$Label contains a reparse-point component: $($node.path)" 6 }
        if ($expectedOwners -cnotcontains [string]$node.owner_sid) { Stop-Launcher $Code "$Label has an untrusted ACL owner: $($node.owner_sid) ($($node.path))" 6 }
        $forbiddenMask=Get-ProtectedContentWriteMask
        foreach ($ace in @($node.allow_aces)) {
            if ($ace.inherit_only -eq $true -or (([int64]$ace.rights -band $forbiddenMask) -eq 0)) { continue }
            if ($expectedOwners -cnotcontains [string]$ace.sid) { Stop-Launcher $Code "$Label grants write/delete-child/replacement/control to an untrusted principal: $($ace.sid) ($($node.path))" 6 }
        }
    }
}

function Get-ProtectedPathChainObservation([string]$Path, [string]$ProtectedRoot, [string]$Code, [string]$Label) {
    if ($env:OS -cne "Windows_NT") { Stop-Launcher $Code "$Label ACL verification requires Windows" }
    try {
        $resolved=Canonical (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
        $resolvedRoot=Canonical (Resolve-Path -LiteralPath $ProtectedTrustRoot -ErrorAction Stop).Path
    } catch { Stop-Launcher $Code "$Label path cannot be resolved: $($_.Exception.Message)" }
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($resolved,$resolvedRoot) -and -not $resolved.StartsWith($resolvedRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        Stop-Launcher $Code "$Label target escapes its protected root" 6
    }
    $nodes=New-Object Collections.Generic.List[object]
    $current=$resolved; $reachedProtectedRoot=$false
    while ($true) {
        Assert-NoReparseComponent $current $Code
        try { $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop; $acl=Get-Acl -LiteralPath $current -ErrorAction Stop } catch { Stop-Launcher $Code "$Label path/ACL cannot be read: $current" }
        $hasReparse=(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
        try { $ownerSid=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { Stop-Launcher $Code "$Label ACL owner cannot be resolved: $current" }
        $allowAces=New-Object Collections.Generic.List[object]
        foreach ($rule in @($acl.Access)) {
            if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { continue }
            try { $sid=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { Stop-Launcher $Code "$Label ACL contains an unresolvable principal: $current" }
            $allowAces.Add([pscustomobject]@{sid=$sid;rights=[int64]$rule.FileSystemRights;inherit_only=(($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0)})
        }
        $nodes.Add([pscustomobject]@{path=$current;scope="PROTECTED_CONTENT";has_reparse_point=$hasReparse;owner_sid=$ownerSid;allow_aces=$allowAces.ToArray()})
        if ([StringComparer]::OrdinalIgnoreCase.Equals($current,$resolvedRoot)) { $reachedProtectedRoot=$true; break }
        $parent=[IO.Directory]::GetParent($current)
        if ($null -eq $parent) { Stop-Launcher $Code "$Label path chain did not reach the protected YOnLab anchor" 6 }
        $current=$parent.FullName
    }
    if (-not $reachedProtectedRoot) { Stop-Launcher $Code "$Label protected YOnLab anchor was not encountered in its path chain" 6 }
    return [pscustomobject]@{protected_root=$resolvedRoot;trusted_owner_sids=@($TrustedProtectionOwnerSids);nodes=$nodes.ToArray()}
}

function Assert-ProtectedRootPathChain([string]$Path, [string]$ProtectedRoot, [string]$Code, [string]$Label) {
    $observation=Get-ProtectedPathChainObservation $Path $ProtectedRoot $Code $Label
    Assert-ProtectedPathChainObservation $observation $Code $Label
}

function Assert-ProtectedPathAcl([string]$Path, [string]$Code, [string]$Label) {
    # Compatibility wrapper; callers that own a subtree pass its actual root to
    # Assert-ProtectedRootPathChain so all intermediate children are content-scoped.
    Assert-ProtectedRootPathChain $Path $Path $Code $Label
}
function Assert-ReleaseTrustAcl([string]$Path) { Assert-ProtectedRootPathChain $Path (Split-Path -Parent $Path) "PRE-TRUST" "release trust" }

function Get-ProtectedRootSnapshot([string]$Path, [string]$ProtectedRoot, [string]$Code, [string]$Label) {
    Assert-ProtectedRootPathChain $Path $ProtectedRoot $Code $Label
    $resolved=Canonical (Resolve-Path -LiteralPath $Path).Path
    $root=Canonical (Resolve-Path -LiteralPath $ProtectedRoot).Path
    $entries=@($resolved)
    if ((Get-Item -LiteralPath $resolved -Force).PSIsContainer) { $entries += @(Get-NoFollowTreeEntries $resolved $Code $Label) }
    if ($entries.Count -gt $MaxWorktreeFiles) { Stop-Launcher $Code "$Label exceeds protected snapshot file-count limit" 6 }
    $records=New-Object Collections.Generic.List[object]; $total=0L
    foreach ($entry in @($entries | Sort-Object -Unique)) {
        Assert-ProtectedRootPathChain $entry $root $Code $Label
        $item=Get-Item -LiteralPath $entry -Force
        try { $acl=Get-Acl -LiteralPath $entry -ErrorAction Stop; $sddl=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Group -bor [Security.AccessControl.AccessControlSections]::Access) } catch { Stop-Launcher $Code "$Label security descriptor cannot be snapshotted: $entry" 6 }
        $relative=$(if([StringComparer]::OrdinalIgnoreCase.Equals($entry,$resolved)){"."}else{$entry.Substring($resolved.Length).TrimStart([char[]]@('\','/')).Replace('\','/')})
        if ($item.PSIsContainer) { $records.Add([pscustomobject]@{path=$relative;kind="directory";sddl=$sddl;length=0;sha256=""}) }
        else {
            $length=[long]$item.Length; $total += $length
            if ($length -le 0 -or $length -gt $MaxWorktreeFileBytes -or $total -gt $MaxWorktreeSnapshotBytes) { Stop-Launcher $Code "$Label protected file/tree exceeds bounded size: $entry" 6 }
            $records.Add([pscustomobject]@{path=$relative;kind="file";sddl=$sddl;length=$length;sha256=(Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash.ToLowerInvariant()})
        }
    }
    $chain=Get-ProtectedPathChainObservation $root $root $Code "$Label root chain"
    return String-Sha256 (([ordered]@{root=$root;chain=$chain;entries=$records.ToArray()} | ConvertTo-Json -Depth 12 -Compress))
}

function Get-ProtectedTrustRootsSnapshot([string]$TrustPath, [string]$HooksPath, [string]$GpgHome, [string]$AttestationRoot) {
    return [pscustomobject][ordered]@{
        release_trust=Get-ProtectedRootSnapshot $TrustPath $TrustPath "PRE-TRUST" "release trust"
        git_hooks=Get-ProtectedRootSnapshot $HooksPath $HooksPath "PRE-GIT-CONTROL" "protected Git hooks"
        gpg_home=Get-ProtectedRootSnapshot $GpgHome $GpgHome "PRE-TRUST" "protected GnuPG home"
        attestations=Get-ProtectedRootSnapshot $AttestationRoot $AttestationRoot "PRE-TRUST" "protected attestation root"
    }
}

function Assert-ProtectedRootSnapshotObservation($Expected, $Actual, [string]$Code = "POLICY-PROTECTED-SNAPSHOT") {
    $names=@("release_trust","git_hooks","gpg_home","attestations")
    Assert-ExactObjectProperties $Expected $names "expected protected root snapshot"
    Assert-ExactObjectProperties $Actual $names "actual protected root snapshot"
    foreach ($name in $names) {
        $expectedValue=[string]$Expected.PSObject.Properties[$name].Value
        $actualValue=[string]$Actual.PSObject.Properties[$name].Value
        if ($expectedValue -notmatch '^[0-9a-f]{64}$' -or $actualValue -cne $expectedValue) { Stop-Launcher $Code "protected trust roots changed during execution: byte/SDDL snapshot differs for $name" 6 }
    }
}

function Assert-ProtectedTrustRootsUnchanged($Expected, [string]$TrustPath, [string]$HooksPath, [string]$GpgHome, [string]$AttestationRoot) {
    $actual=Get-ProtectedTrustRootsSnapshot $TrustPath $HooksPath $GpgHome $AttestationRoot
    Assert-ProtectedRootSnapshotObservation $Expected $actual "POST-TRUST"
    Write-Pass "POST-TRUST protected release trust, hooks, GPG, and attestation roots unchanged"
}

function Test-SafeTrustedExecutablePathSyntax([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or
        $Path.IndexOf(':', 2) -ge 0 -or $Path -match '["''$`%!;&|<>\x00-\x1f]' -or $Path -match '(^|[\\/])\.\.?(?:[\\/]|$)' -or
        [IO.Path]::GetExtension($Path) -ine ".exe") { return $false }
    if ($env:OS -cne "Windows_NT") { return $true }
    try { return [StringComparer]::OrdinalIgnoreCase.Equals((Canonical $Path), $Path.TrimEnd([char[]]@('\','/'))) } catch { return $false }
}

function Get-TrustedExecutableAllowedRoots {
    $roots=New-Object Collections.Generic.List[string]
    $candidates=@($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)})
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) { $candidates += (Join-Path $env:ProgramData "YOnLab\bin") }
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { $roots.Add((Canonical ([string]$candidate))) }
    }
    return @($roots | Sort-Object -Unique)
}

function Assert-NonBroadWritablePathChain([string]$Path, [string]$Label) {
    $resolved=Canonical (Resolve-Path -LiteralPath $Path).Path
    $allowedRoot=$null
    foreach ($root in (Get-TrustedExecutableAllowedRoots)) {
        if ([StringComparer]::OrdinalIgnoreCase.Equals($resolved,$root) -or $resolved.StartsWith($root + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
            if ($null -eq $allowedRoot -or $root.Length -gt $allowedRoot.Length) { $allowedRoot=$root }
        }
    }
    if ($null -eq $allowedRoot) { Stop-Launcher "PRE-TOOL-TRUST" "$Label is outside Windows/System32, Program Files, or hardened ProgramData YOnLab bin" }
    $trustedWriteSids=@("S-1-5-18","S-1-5-32-544","S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464") # SYSTEM, Administrators, TrustedInstaller
    $writeMask=[int64](Get-ProtectedContentWriteMask)
    $replacementMask=[int64]([Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership)
    $current=$resolved
    $insideAllowedRoot=$true
    $volumeRoot=[IO.Path]::GetPathRoot($resolved)
    if ([string]::IsNullOrWhiteSpace($volumeRoot)) { Stop-Launcher "PRE-TOOL-TRUST" "$Label has no trusted volume root" }
    while ($true) {
        Assert-NoReparseComponent $current "PRE-TOOL-TRUST"
        try { $acl=Get-Acl -LiteralPath $current -ErrorAction Stop } catch { Stop-Launcher "PRE-TOOL-TRUST" "$Label ACL cannot be read: $current" }
        try { $ownerSid=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { Stop-Launcher "PRE-TOOL-TRUST" "$Label ACL owner cannot be resolved: $current" }
        if ($trustedWriteSids -notcontains $ownerSid) { Stop-Launcher "PRE-TOOL-TRUST" "$Label or ancestor has an untrusted ACL owner: $ownerSid ($current)" }
        $effectiveMask=$(if ($insideAllowedRoot) { $writeMask } else { $replacementMask })
        foreach ($rule in @($acl.Access)) {
            if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
                (($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0) -or
                (([int64]$rule.FileSystemRights -band [int64]$effectiveMask) -eq 0)) { continue }
            try { $sid=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { Stop-Launcher "PRE-TOOL-TRUST" "$Label ACL contains an unresolvable writer" }
            if ($trustedWriteSids -notcontains $sid) { Stop-Launcher "PRE-TOOL-TRUST" "$Label or ancestor grants write/modify/delete/control to an untrusted principal: $sid ($current)" }
        }
        if ([StringComparer]::OrdinalIgnoreCase.Equals($current,$volumeRoot)) { break }
        if ([StringComparer]::OrdinalIgnoreCase.Equals($current,$allowedRoot)) { $insideAllowedRoot=$false }
        $parent=[IO.Directory]::GetParent($current)
        if ($null -eq $parent) { Stop-Launcher "PRE-TOOL-TRUST" "$Label path chain did not terminate at its volume root" }
        $current=$parent.FullName
    }
}

function Get-TrustedExecutableInventory($TrustedTools, [string]$WorkspaceRoot) {
    $requiredNames = @("powershell", "python", "git", "gh", "docker", "codex", "gpg")
    Assert-ExactObjectProperties $TrustedTools $requiredNames "release trust trusted_tools"
    $inventory = [ordered]@{}
    foreach ($name in $requiredNames) {
        $spec = $TrustedTools.PSObject.Properties[$name].Value
        Assert-ExactObjectProperties $spec @("path", "sha256", "authenticode_required", "authenticode_signer_thumbprint") "trusted tool $name"
        $path = [string]$spec.path
        if (-not (Test-SafeTrustedExecutablePathSyntax $path) -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or $path.StartsWith($WorkspaceRoot + "\", [StringComparison]::OrdinalIgnoreCase) -or [string]$spec.sha256 -notmatch '^[0-9a-f]{64}$' -or $spec.authenticode_required -isnot [bool]) { Stop-Launcher "PRE-TOOL-TRUST" "$name must be an existing canonical safe .exe with exact hash outside the workspace" }
        Assert-NoReparseComponent $path "PRE-TOOL-TRUST"
        Assert-NonBroadWritablePathChain $path "trusted tool $name"
        $observedHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        try { $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop } catch { Stop-Launcher "PRE-TOOL-TRUST" "$name Authenticode verification failed: $($_.Exception.Message)" }
        $observedThumbprint = $(if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Thumbprint } else { "" })
        $expectedThumbprint=$(if ($null -eq $spec.authenticode_signer_thumbprint) { "" } else { ([string]$spec.authenticode_signer_thumbprint).ToUpperInvariant() })
        if ($spec.authenticode_required -eq $true) {
            if ($expectedThumbprint -notmatch '^[0-9A-F]{40,64}$' -or [string]$signature.Status -cne "Valid" -or $observedThumbprint.ToUpperInvariant() -cne $expectedThumbprint) { Stop-Launcher "PRE-TOOL-TRUST" "$name requires an exact valid Authenticode signer" }
        } elseif ($null -ne $spec.authenticode_signer_thumbprint) { Stop-Launcher "PRE-TOOL-TRUST" "$name optional Authenticode policy must use null thumbprint" }
        $observation = [pscustomobject]@{
            workspace_root=$WorkspaceRoot; path=$path; expected_sha256=([string]$spec.sha256).ToLowerInvariant(); observed_sha256=$observedHash
            authenticode_required=[bool]$spec.authenticode_required; authenticode_status=[string]$signature.Status; expected_signer_thumbprint=$expectedThumbprint
            observed_signer_thumbprint=$observedThumbprint.ToUpperInvariant(); has_reparse_component=$false; broad_write_acl=$false
        }
        Assert-TrustedToolObservation $observation
        $inventory[$name] = [ordered]@{path=$path;sha256=$observedHash;authenticode_required=[bool]$spec.authenticode_required;authenticode_status=[string]$signature.Status;authenticode_signer_thumbprint=$observedThumbprint.ToUpperInvariant()}
    }
    return $inventory
}

function Assert-TrustedExecutableInventoryUnchanged($Expected, $TrustedTools, [string]$WorkspaceRoot) {
    $actual = Get-TrustedExecutableInventory $TrustedTools $WorkspaceRoot
    if (-not [StringComparer]::Ordinal.Equals(($Expected | ConvertTo-Json -Depth 6 -Compress), ($actual | ConvertTo-Json -Depth 6 -Compress))) { Stop-Launcher "POST-TOOL-TRUST" "trusted executable path/hash/signer inventory changed during execution" 6 }
    Write-Pass "POST-TOOL-TRUST exact protected tool bytes/signers unchanged"
}

function Assert-ProtectedEmptyHooksDirectory([string]$Path, [string]$Root) {
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals((Canonical $Path), (Canonical $ProtectedHooksPath)) -or -not (Test-Path -LiteralPath $Path -PathType Container)) { Stop-Launcher "PRE-GIT-CONTROL" "protected hooks directory must be the literal existing directory '$ProtectedHooksPath'" }
    Assert-NoReparseComponent $Path "PRE-GIT-CONTROL"
    $resolved = Canonical (Resolve-Path -LiteralPath $Path).Path
    if ($resolved.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { Stop-Launcher "PRE-GIT-CONTROL" "protected hooks directory must be outside the Codex workspace" }
    Assert-ProtectedRootPathChain $resolved $resolved "PRE-GIT-CONTROL" "empty Git hooks directory"
    if ([IO.Directory]::GetFileSystemEntries($resolved).Length -ne 0) { Stop-Launcher "PRE-GIT-CONTROL" "protected Git hooks directory must remain empty" }
}

function Assert-GpgVerificationConfigurationObservation($Observation, [string]$Code = "POLICY-GPG") {
    if ([string]$Observation.gpg_conf_relative_path -cne "gpg.conf" -or $Observation.gpg_conf_utf8_no_bom -ne $true -or
        [string]$Observation.gpg_conf_text -cne "no-auto-check-trustdb`n" -or [string]$Observation.trustdb_relative_path -cne "trustdb.gpg" -or
        $Observation.trustdb_is_file -ne $true -or [int64]$Observation.trustdb_length -le 0 -or [int64]$Observation.trustdb_length -gt $MaxWorktreeFileBytes -or
        [string]$Observation.snapshot_before -notmatch '^[0-9a-f]{64}$' -or [string]$Observation.snapshot_after -cne [string]$Observation.snapshot_before) {
        Stop-Launcher $Code "protected GnuPG home requires exact no-auto-check-trustdb gpg.conf, a preprovisioned trustdb.gpg, and an unchanged byte/ACL snapshot" 6
    }
}

function Get-ProtectedGpgVerificationConfigurationObservation([string]$Path, [string]$SnapshotBefore, [string]$SnapshotAfter, [string]$Code) {
    $configPath=Join-Path $Path "gpg.conf"; $trustdbPath=Join-Path $Path "trustdb.gpg"
    foreach ($requiredPath in @($configPath,$trustdbPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { Stop-Launcher $Code "protected GnuPG verification file is missing: $requiredPath" 6 }
        Assert-NoReparseComponent $requiredPath $Code
        Assert-ProtectedRootPathChain $requiredPath $Path $Code "protected GnuPG verification file"
    }
    $configBytes=[IO.File]::ReadAllBytes($configPath)
    $hasBom=$configBytes.Length -ge 3 -and $configBytes[0] -eq 0xEF -and $configBytes[1] -eq 0xBB -and $configBytes[2] -eq 0xBF
    try { $configText=(New-Object Text.UTF8Encoding -ArgumentList $false,$true).GetString($configBytes) } catch { Stop-Launcher $Code "protected GnuPG gpg.conf is not strict UTF-8" 6 }
    $trustdbLength=[long](Get-Item -LiteralPath $trustdbPath -Force).Length
    return [pscustomobject]@{
        gpg_conf_relative_path="gpg.conf";gpg_conf_utf8_no_bom=(-not $hasBom);gpg_conf_text=$configText
        trustdb_relative_path="trustdb.gpg";trustdb_is_file=$true;trustdb_length=$trustdbLength
        snapshot_before=$SnapshotBefore;snapshot_after=$SnapshotAfter
    }
}

function Assert-ProtectedGpgVerificationConfiguration([string]$Path) {
    $snapshot=Get-ProtectedRootSnapshot $Path $Path "PRE-GPG" "protected GnuPG home"
    $observation=Get-ProtectedGpgVerificationConfigurationObservation $Path $snapshot $snapshot "PRE-GPG"
    Assert-GpgVerificationConfigurationObservation $observation "PRE-GPG"
}

function Assert-ProtectedGpgHomeUnchanged([string]$ExpectedSnapshot, [string]$Path, [string]$Code) {
    $actualSnapshot=Get-ProtectedRootSnapshot $Path $Path $Code "protected GnuPG home"
    $observation=Get-ProtectedGpgVerificationConfigurationObservation $Path $ExpectedSnapshot $actualSnapshot $Code
    Assert-GpgVerificationConfigurationObservation $observation $Code
}

function Assert-ProtectedPublicOnlyGpgHome([string]$Path, [string]$Root) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { Stop-Launcher "PRE-TRUST" "protected GnuPG home is missing: $Path" }
    Assert-NoReparseComponent $Path "PRE-TRUST"
    $resolved = Canonical (Resolve-Path -LiteralPath $Path).Path
    if ($resolved.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { Stop-Launcher "PRE-TRUST" "protected GnuPG home must be outside the Codex workspace" }
    Assert-ProtectedRootPathChain $resolved $resolved "PRE-TRUST" "protected GnuPG home"
    foreach ($privateDirectory in @("private-keys-v1.d", "openpgp-revocs.d")) {
        if (Test-Path -LiteralPath (Join-Path $resolved $privateDirectory)) { Stop-Launcher "PRE-TRUST" "verification-only GnuPG home must not contain private-key material: $privateDirectory" }
    }
    $entries = @(Get-NoFollowTreeEntries $resolved "PRE-TRUST" "protected GnuPG home")
    $total = 0L
    foreach ($entry in $entries) {
        $item = Get-Item -LiteralPath $entry -Force
        Assert-ProtectedRootPathChain $entry $resolved "PRE-TRUST" "protected GnuPG child"
        if (-not $item.PSIsContainer) {
            if ([long]$item.Length -gt $MaxWorktreeFileBytes) { Stop-Launcher "PRE-TRUST" "protected GnuPG file exceeds bounded size" 6 }
            $total += [long]$item.Length
            if ($total -gt $MaxWorktreeSnapshotBytes) { Stop-Launcher "PRE-TRUST" "protected GnuPG home exceeds bounded total size" 6 }
        }
    }
    Assert-ProtectedGpgVerificationConfiguration $resolved
    return $resolved
}

function Test-UnsafeGitConfigName([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }
    $normalized = $Name.ToLowerInvariant()
    return $normalized -match '^(?:alias\.|include\.|includeif\.|submodule\.|filter\..*\.(?:clean|smudge|process|required)$|diff\..*\.(?:command|textconv)$|merge\..*\.driver$|credential(?:\..*)?\.(?:helper|username|usehttppath)$|remote\..*\.(?:uploadpack|receivepack|proxy|pushurl)$|url\..*\.(?:insteadof|pushinsteadof)$|gpg(?:\..*)?\.program$|pager\.|http(?:\..*)?\.(?:proxy|extraheader|sslverify|sslcert|sslkey|sslcertpasswordprotected|cookiefile|savecookies|useragent)$|protocol\.ext\.allow$|core\.(?:alternaterefscommand|askpass|attributesfile|editor|excludesfile|fsmonitor|gitproxy|hookspath|pager|sshcommand|worktree)$|interactive\.difffilter$|sequence\.editor$|ssh\.variant$)'
}

function Assert-SafeGitConfigScopeNameFields([string[]]$Fields) {
    $fields = @($Fields)
    if (($fields.Count % 2) -ne 0) { Stop-Launcher "PRE-GIT-CONFIG" "Git configuration scope/name inventory is malformed" }
    $allowedCommandNames = @("core.fsmonitor", "core.hookspath", "core.pager", "pager.branch", "pager.log", "credential.https://github.com.helper")
    $commandNames = New-Object Collections.Generic.List[string]
    for ($index = 0; $index -lt $fields.Count; $index += 2) {
        $scope = [string]$fields[$index]; $name = ([string]$fields[$index + 1]).ToLowerInvariant()
        if ($scope -ceq "command") {
            if ($allowedCommandNames -cnotcontains $name) { Stop-Launcher "PRE-GIT-CONFIG" "unrecognized command-scope Git config is forbidden: $name" }
            $commandNames.Add($name)
            continue
        }
        if (@("system", "global", "local", "worktree") -cnotcontains $scope) { Stop-Launcher "PRE-GIT-CONFIG" "unrecognized Git config scope is forbidden: $scope" }
        if (Test-UnsafeGitConfigName $name) { Stop-Launcher "PRE-GIT-CONFIG" "executable, redirecting, or externally loaded Git config is forbidden in $scope scope: $name" }
    }
    $actualCommands = @($commandNames.ToArray() | Sort-Object)
    $expectedCommands = @($allowedCommandNames | Sort-Object)
    if ($actualCommands.Count -ne $expectedCommands.Count -or @(Compare-Object -ReferenceObject $expectedCommands -DifferenceObject $actualCommands).Count -ne 0) { Stop-Launcher "PRE-GIT-CONFIG" "runner command-scope Git config set is not exact" }
}

function Split-NulDelimitedText([string]$Text) {
    $textValue=[string]$Text
    return @($textValue.Split([char[]]@([char]0), [StringSplitOptions]::RemoveEmptyEntries))
}

function Assert-NoExecutableGitConfiguration([string]$GitCommand, [string]$Root) {
    # Listing names parses configuration but does not run the configured
    # helpers. Includes are themselves forbidden, so no external config may
    # silently extend the execution surface used by later Git commands.
    $inventory = SafeGit $GitCommand @("-C", $Root, "config", "--null", "--name-only", "--show-scope", "--list")
    Native-OK $inventory "PRE-GIT-CONFIG" "Git configuration name inventory"
    $fields = @(Split-NulDelimitedText $inventory.Text)
    Assert-SafeGitConfigScopeNameFields $fields
    Write-Pass "PRE-GIT-CONFIG no executable/redirect/include/submodule Git configuration"
}

function Assert-NoTrackedSubmoduleMetadata([string]$GitCommand, [string]$Root) {
    $tracked = SafeGit $GitCommand @("-C", $Root, "ls-files", "--error-unmatch", "--", ".gitmodules")
    if ($tracked.ExitCode -eq 0) { Stop-Launcher "GIT-SUBMODULE" "tracked .gitmodules is forbidden; this release baseline does not use submodules" 6 }
    if ($tracked.ExitCode -ne 1) { Stop-Launcher "GIT-SUBMODULE" "could not prove tracked .gitmodules absence: $($tracked.Text)" 6 }
}

function New-KillOnCloseJob($Process, [ValidateSet("Required", "BestEffortReadOnly", "DisabledForPolicySelfTest")][string]$IsolationMode = "Required") {
    if ($env:OS -cne "Windows_NT") { return [IntPtr]::Zero }
    if ($IsolationMode -ceq "DisabledForPolicySelfTest") { return [IntPtr]::Zero }
    if ($null -eq ("YOnLab.NativeJob" -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace YOnLab {
  public static class NativeJob {
    [StructLayout(LayoutKind.Sequential)] public struct BasicLimit {
      public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
      public uint LimitFlags;
      public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
      public uint ActiveProcessLimit;
      public UIntPtr Affinity;
      public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)] public struct IoCounters {
      public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }
    [StructLayout(LayoutKind.Sequential)] public struct ExtendedLimit {
      public BasicLimit BasicLimitInformation;
      public IoCounters IoInfo;
      public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr handle);
  }
}
'@
    }
    $inJob = $false
    if (-not [YOnLab.NativeJob]::IsProcessInJob([Diagnostics.Process]::GetCurrentProcess().Handle, [IntPtr]::Zero, [ref]$inJob)) { throw "IsProcessInJob failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    $job = [YOnLab.NativeJob]::CreateJobObject([IntPtr]::Zero, $null)
    if ($job -eq [IntPtr]::Zero) { throw "CreateJobObject failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    $limit = New-Object YOnLab.NativeJob+ExtendedLimit
    $limit.BasicLimitInformation.LimitFlags = 0x00002000
    $size = [Runtime.InteropServices.Marshal]::SizeOf($limit)
    $pointer = [Runtime.InteropServices.Marshal]::AllocHGlobal($size)
    try {
        [Runtime.InteropServices.Marshal]::StructureToPtr($limit, $pointer, $false)
        if (-not [YOnLab.NativeJob]::SetInformationJobObject($job, 9, $pointer, [uint32]$size)) { throw "SetInformationJobObject failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
        if (-not [YOnLab.NativeJob]::AssignProcessToJobObject($job, $Process.Handle)) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if ($IsolationMode -ceq "BestEffortReadOnly" -and $errorCode -eq 5) { [void][YOnLab.NativeJob]::CloseHandle($job); return [IntPtr]::Zero }
            $message = "AssignProcessToJobObject failed: $errorCode"
            if ($errorCode -eq 5) { $message += " (Access Denied: nested Job Object; current process in job=$inJob; launch from an independent shell)" }
            throw $message
        }
        return $job
    } catch {
        [void][YOnLab.NativeJob]::CloseHandle($job)
        throw
    } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($pointer) }
}

function Close-KillOnCloseJob([IntPtr]$Job) { if ($Job -ne [IntPtr]::Zero) { [void][YOnLab.NativeJob]::CloseHandle($Job) } }
function Stop-NativeProcessTree($Process) {
    if ($null -eq $Process) { return }
    if (-not $Process.HasExited) {
        $treeKill = $Process.GetType().GetMethod("Kill", [type[]]@([bool]))
        if ($null -ne $treeKill) { [void]$treeKill.Invoke($Process, @($true)); return }
        if ($env:OS -ceq "Windows_NT") {
            $taskkill = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) "taskkill.exe"
            if (-not (Test-Path -LiteralPath $taskkill -PathType Leaf)) { throw "WinPS5 process-tree fallback taskkill.exe is unavailable" }
            $killed = Native $taskkill @("/PID", [string]$Process.Id, "/T", "/F")
            if ($killed.ExitCode -ne 0 -and -not $Process.HasExited) { throw "taskkill process-tree fallback failed: $($killed.Text)" }
            return
        }
        $Process.Kill()
    }
}

function Get-TrustedInputHashes([string]$Root, [string[]]$RelativePaths) {
    $hashes = [ordered]@{}
    foreach ($relative in $RelativePaths) {
        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '^[A-Za-z]:' -or $relative -match '[\x00:]|(^|[\\/])\.\.?(?:[\\/]|$)') { Stop-Launcher "TRUSTED-INPUT" "unsafe trusted input path: $relative" }
        $full = [IO.Path]::GetFullPath((Join-Path $Root $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
        if (-not $full.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { Stop-Launcher "TRUSTED-INPUT" "trusted input missing/outside root: $relative" }
        Assert-NoReparseComponent $full "TRUSTED-INPUT"
        $hashes[$relative.Replace('\', '/')] = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $hashes
}

function New-BoundedCaptureStream([IO.Stream]$Inner, [long]$MaximumBytes, $SharedBudget = $null) {
    if ($null -eq ("YOnLab.BoundedWriteStream" -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
namespace YOnLab {
  public sealed class CaptureBudget {
    private long remaining;
    public CaptureBudget(long maximum) { if (maximum < 0) throw new ArgumentOutOfRangeException("maximum"); remaining = maximum; }
    public void Reserve(int count) {
      long after = Interlocked.Add(ref remaining, -count);
      if (after < 0) { Interlocked.Add(ref remaining, count); throw new IOException("bounded capture byte limit exceeded"); }
    }
  }
  public sealed class BoundedWriteStream : Stream {
    private readonly Stream inner; private readonly CaptureBudget budget;
    public BoundedWriteStream(Stream inner, CaptureBudget budget) { this.inner = inner; this.budget = budget; }
    public override bool CanRead { get { return false; } }
    public override bool CanSeek { get { return false; } }
    public override bool CanWrite { get { return true; } }
    public override long Length { get { return inner.Length; } }
    public override long Position { get { return inner.Position; } set { throw new NotSupportedException(); } }
    public override void Flush() { inner.Flush(); }
    public override Task FlushAsync(CancellationToken token) { return inner.FlushAsync(token); }
    public override int Read(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
    public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
    public override void SetLength(long value) { throw new NotSupportedException(); }
    public override void Write(byte[] buffer, int offset, int count) { budget.Reserve(count); inner.Write(buffer, offset, count); }
    public override Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken token) { budget.Reserve(count); return inner.WriteAsync(buffer, offset, count, token); }
    protected override void Dispose(bool disposing) { if (disposing) inner.Dispose(); base.Dispose(disposing); }
  }
}
'@
    }
    $budget = $(if ($null -eq $SharedBudget) { New-Object YOnLab.CaptureBudget -ArgumentList $MaximumBytes } else { $SharedBudget })
    return [pscustomobject]@{ Stream=(New-Object YOnLab.BoundedWriteStream -ArgumentList $Inner,$budget); Budget=$budget }
}

function Invoke-NativeCaptureBytes([string]$Command, [string[]]$Arguments, [long]$MaximumBytes = $MaxNativeCaptureBytes, [int]$TimeoutSeconds = $MaxNativeSeconds, [ValidateSet("Required", "BestEffortReadOnly", "DisabledForPolicySelfTest")][string]$IsolationMode = "Required", [switch]$ReadOnlyProbe) {
    if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 21600) { throw "native command timeout must be 1..21600 seconds" }
    if ($IsolationMode -ceq "BestEffortReadOnly" -and -not $ReadOnlyProbe) { throw "BestEffortReadOnly requires an allowlisted read-only probe" }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.FileName = $Command; $psi.Arguments = (($Arguments | ForEach-Object { Quote-WindowsArgument $_ }) -join ' ')
    $psi.WorkingDirectory = Get-TrustedExecutableWorkingDirectory $Command
    Set-SafeProcessEnvironment $psi
    $process = New-Object Diagnostics.Process; $process.StartInfo = $psi; $started = $false; $job = [IntPtr]::Zero; $stdoutTask = $null; $stderrTask = $null
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ("yonlab-native-capture-" + [Guid]::NewGuid().ToString("N") + ".bin")
    $errorTemporary = "$temporary.stderr"
    $capture = $null; $errorCapture = $null; $boundedCapture = $null; $boundedErrorCapture = $null
    try {
        $capture = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $errorCapture = [IO.File]::Open($errorTemporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        if (-not $process.Start()) { throw "native capture process did not start" }; $started = $true; $job = New-KillOnCloseJob $process $IsolationMode
        $wrapped = New-BoundedCaptureStream $capture $MaximumBytes; $boundedCapture = $wrapped.Stream
        $wrappedError = New-BoundedCaptureStream $errorCapture $MaximumBytes $wrapped.Budget; $boundedErrorCapture = $wrappedError.Stream
        $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($boundedCapture)
        $stderrTask = $process.StandardError.BaseStream.CopyToAsync($boundedErrorCapture)
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
        while (-not $process.WaitForExit(100)) {
            if ($stdoutTask.IsFaulted -or $stderrTask.IsFaulted) { throw "native stdout/stderr exceeds bounded total capture limit $MaximumBytes bytes" }
            if ([DateTimeOffset]::UtcNow -ge $deadline) { throw "native command exceeded hard timeout $TimeoutSeconds seconds" }
        }
        if ($job -ne [IntPtr]::Zero) { Close-KillOnCloseJob $job; $job = [IntPtr]::Zero }
        try { $stdoutDone = $stdoutTask.Wait(30000); $stderrDone = $stderrTask.Wait(30000) } catch { throw "native stdout/stderr exceeds bounded total capture limit $MaximumBytes bytes" }
        if (-not $stdoutDone -or -not $stderrDone) { throw "native capture stream drain timed out after process-tree termination" }
        try { [void]$stdoutTask.GetAwaiter().GetResult(); [void]$stderrTask.GetAwaiter().GetResult() } catch { throw "native stdout/stderr exceeds bounded total capture limit $MaximumBytes bytes" }
        $capture.Flush(); $errorCapture.Flush(); $capture.Dispose(); $errorCapture.Dispose(); $capture = $null; $errorCapture = $null
        $length = [long](Get-Item -LiteralPath $temporary -Force).Length; $errorLength = [long](Get-Item -LiteralPath $errorTemporary -Force).Length
        if ($length -gt $MaximumBytes -or $errorLength -gt $MaximumBytes -or ($length + $errorLength) -gt $MaximumBytes) { throw "native stdout/stderr exceeds bounded total capture limit $MaximumBytes bytes" }
        $strictUtf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
        try { $errorText = $strictUtf8.GetString([IO.File]::ReadAllBytes($errorTemporary)) } catch { throw "native stderr is not strict UTF-8" }
        return [pscustomobject]@{ ExitCode=$process.ExitCode; Bytes=[IO.File]::ReadAllBytes($temporary); ErrorText=$errorText }
    } catch {
        if ($job -ne [IntPtr]::Zero) { Close-KillOnCloseJob $job; $job = [IntPtr]::Zero }
        if ($started -and -not $process.HasExited) { try { Stop-NativeProcessTree $process } catch { }; try { $process.WaitForExit() } catch { } }
        throw
    } finally {
        if ($job -ne [IntPtr]::Zero) { Close-KillOnCloseJob $job; $job = [IntPtr]::Zero }
        if ($started -and -not $process.HasExited) { try { Stop-NativeProcessTree $process } catch { }; try { $process.WaitForExit() } catch { } }
        if ($null -ne $boundedCapture) { $boundedCapture.Dispose() } elseif ($null -ne $capture) { $capture.Dispose() }
        if ($null -ne $boundedErrorCapture) { $boundedErrorCapture.Dispose() } elseif ($null -ne $errorCapture) { $errorCapture.Dispose() }
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $errorTemporary) { Remove-Item -LiteralPath $errorTemporary -Force -ErrorAction SilentlyContinue }
        $process.Dispose()
    }
}

function Invoke-SafeGitCaptureBytes([string]$GitCommand, [string[]]$Arguments, [long]$MaximumBytes = $MaxNativeCaptureBytes) {
    return Invoke-NativeCaptureBytes -Command $GitCommand -Arguments (Get-SafeGitArguments $Arguments) -MaximumBytes $MaximumBytes -IsolationMode "BestEffortReadOnly" -ReadOnlyProbe
}

function Get-BoundedFileInventory {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string[]]$RelativePaths,
        [Parameter(Mandatory = $true)][string]$Label,
        [long]$MaximumBytes = $MaxWorktreeSnapshotBytes,
        [int]$MaximumFiles = $MaxWorktreeFiles,
        [switch]$Compact
    )
    $paths = @($RelativePaths)
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    if ($paths.Count -gt $MaximumFiles) { Stop-Launcher "WORKTREE-SNAPSHOT" "too many $Label files" 6 }
    $seen = New-Object 'Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    $files = New-Object Collections.Generic.List[object]
    $total = 0L
    $utf8 = New-Object Text.UTF8Encoding -ArgumentList $false
    $digest = [Security.Cryptography.SHA256]::Create()
    try {
        foreach ($relativeValue in $paths) {
            $relative = ([string]$relativeValue).Replace('\', '/').Normalize([Text.NormalizationForm]::FormC)
            if ([string]::IsNullOrWhiteSpace($relative) -or -not $seen.Add($relative) -or $relative -match '[\x00:]|(^|[\\/])\.\.?(?:[\\/]|$)' -or [IO.Path]::IsPathRooted($relative)) { Stop-Launcher "WORKTREE-SNAPSHOT" "unsafe or duplicate $Label path: $relative" }
            $full = [IO.Path]::GetFullPath((Join-Path $Root $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
            if (-not $full.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { Stop-Launcher "WORKTREE-SNAPSHOT" "$Label file changed during snapshot: $relative" }
            Assert-NoReparseComponent $full "WORKTREE-SNAPSHOT"
            $item = Get-Item -LiteralPath $full -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or [long]$item.Length -gt $MaxWorktreeFileBytes) { Stop-Launcher "WORKTREE-SNAPSHOT" "$Label file is a reparse point or exceeds $MaxWorktreeFileBytes bytes: $relative" 6 }
            $total += [long]$item.Length
            if ($total -gt $MaximumBytes) { Stop-Launcher "WORKTREE-SNAPSHOT" "$Label file inventory exceeds $MaximumBytes bytes" 6 }
            $record = [ordered]@{path=$relative;length=[long]$item.Length;sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()}
            $recordBytes = $utf8.GetBytes(($record | ConvertTo-Json -Depth 4 -Compress) + "`n")
            $null = $digest.TransformBlock($recordBytes, 0, $recordBytes.Length, $recordBytes, 0)
            if (-not $Compact) { $files.Add($record) }
        }
        $null = $digest.TransformFinalBlock([byte[]]@(), 0, 0)
        $inventoryHash = ([BitConverter]::ToString($digest.Hash)).Replace('-', '').ToLowerInvariant()
    } finally {
        $digest.Dispose()
    }
    $fileOutput = if ($Compact) { @() } else { @($files.ToArray()) }
    return [ordered]@{total_bytes=$total;file_count=$paths.Count;inventory_sha256=$inventoryHash;files=$fileOutput}
}

function Test-VolatileIgnoredPath([string]$RelativePath) {
    $normalized = ([string]$RelativePath).Replace('\', '/')
    switch -Regex ($normalized) {
        '^(?:\.pytest_cache|\.ruff_cache)/' { return $true }
        '(^|/)__pycache__/' { return $true }
        '\.pyc$' { return $true }
        '^frontend/(?:dist|playwright-report|test-results)/' { return $true }
        '^frontend/tsconfig\.tsbuildinfo$' { return $true }
        '^backend/[^/]+\.egg-info/' { return $true }
        '^docs/qa/screenshots/[^/]+\.png$' { return $true }
        default { return $false }
    }
}

function Get-WorktreeSnapshot([string]$GitCommand, [string]$Root, [string]$ExcludedRunRelative) {
    if ($ExcludedRunRelative -notmatch '^\.artifacts/codex/[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$') { Stop-Launcher "WORKTREE-SNAPSHOT" "exact active run exclusion is invalid" 6 }
    $statusArguments = @("-C", $Root, "status", "--porcelain=v1", "--untracked-files=all", "-z")
    $statusBefore = Invoke-SafeGitCaptureBytes $GitCommand $statusArguments
    $trackedDiff = Invoke-SafeGitCaptureBytes $GitCommand @("-C", $Root, "diff", "--no-ext-diff", "--no-textconv", "--binary", "--no-color")
    $stagedDiff = Invoke-SafeGitCaptureBytes $GitCommand @("-C", $Root, "diff", "--cached", "--no-ext-diff", "--no-textconv", "--binary", "--no-color")
    $indexState = Invoke-SafeGitCaptureBytes $GitCommand @("-C", $Root, "ls-files", "-s", "-z")
    $untrackedResult = Invoke-SafeGitCaptureBytes $GitCommand @("-C", $Root, "ls-files", "--others", "--exclude-standard", "-z")
    $ignoredResult = Invoke-SafeGitCaptureBytes $GitCommand @("-C", $Root, "ls-files", "--others", "--ignored", "--exclude-standard", "-z", "--", ".", ":(exclude)$ExcludedRunRelative/**")
    $statusAfter = Invoke-SafeGitCaptureBytes $GitCommand $statusArguments
    foreach ($capture in @($statusBefore, $trackedDiff, $stagedDiff, $indexState, $untrackedResult, $ignoredResult, $statusAfter)) { if ($capture.ExitCode -ne 0) { Stop-Launcher "WORKTREE-SNAPSHOT" "binary-safe Git snapshot command failed: $($capture.ErrorText)" } }
    $captureTotal = [long](($statusBefore.Bytes.Length + $trackedDiff.Bytes.Length + $stagedDiff.Bytes.Length + $indexState.Bytes.Length + $untrackedResult.Bytes.Length + $ignoredResult.Bytes.Length + $statusAfter.Bytes.Length))
    if ($captureTotal -gt $MaxWorktreeSnapshotBytes) { Stop-Launcher "WORKTREE-SNAPSHOT" "Git snapshot capture exceeds $MaxWorktreeSnapshotBytes bytes" 6 }
    if ((Bytes-Sha256 $statusBefore.Bytes) -cne (Bytes-Sha256 $statusAfter.Bytes)) { Stop-Launcher "WORKTREE-SNAPSHOT" "worktree changed while its snapshot was being captured" }
    $strictUtf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
    try { $untrackedText = $strictUtf8.GetString($untrackedResult.Bytes); $ignoredText = $strictUtf8.GetString($ignoredResult.Bytes) } catch { Stop-Launcher "WORKTREE-SNAPSHOT" "Git path inventory is not strict UTF-8" 6 }
    $untrackedPaths = @(
        Split-NulDelimitedText $untrackedText
    )
    $ignoredPaths = @(
        Split-NulDelimitedText $ignoredText
    )
    $untrackedInventory = Get-BoundedFileInventory $Root $untrackedPaths "untracked"
    $volatileIgnoredPaths = @($ignoredPaths | Where-Object { Test-VolatileIgnoredPath $_ })
    $protectedIgnoredPaths = @($ignoredPaths | Where-Object { -not (Test-VolatileIgnoredPath $_) })
    $ignoredInventory = Get-BoundedFileInventory $Root $protectedIgnoredPaths "protected ignored" -MaximumBytes $MaxIgnoredWorktreeSnapshotBytes -MaximumFiles $MaxIgnoredWorktreeFiles -Compact
    $volatileInventory = Get-BoundedFileInventory $Root $volatileIgnoredPaths "volatile ignored" -MaximumBytes $MaxIgnoredWorktreeSnapshotBytes -MaximumFiles $MaxIgnoredWorktreeFiles -Compact
    $volatileIgnoredPaths = @($volatileIgnoredPaths)
    [Array]::Sort($volatileIgnoredPaths, [StringComparer]::Ordinal)
    $volatilePathDigest = String-Sha256 ($volatileIgnoredPaths -join "`0")
    return [ordered]@{
        status_sha256 = Bytes-Sha256 $statusBefore.Bytes
        tracked_diff_sha256 = Bytes-Sha256 $trackedDiff.Bytes
        staged_diff_sha256 = Bytes-Sha256 $stagedDiff.Bytes
        index_state_sha256 = Bytes-Sha256 $indexState.Bytes
        untracked_path_list_sha256 = Bytes-Sha256 $untrackedResult.Bytes
        ignored_path_list_sha256 = Bytes-Sha256 $ignoredResult.Bytes
        untracked_inventory_sha256 = $untrackedInventory.inventory_sha256
        ignored_inventory_sha256 = $ignoredInventory.inventory_sha256
        ignored_file_count = [int]$ignoredInventory.file_count + [int]$volatileInventory.file_count
        ignored_total_bytes = [long]$ignoredInventory.total_bytes + [long]$volatileInventory.total_bytes
        protected_ignored_file_count = [int]$ignoredInventory.file_count
        protected_ignored_total_bytes = [long]$ignoredInventory.total_bytes
        protected_ignored_inventory_sha256 = [string]$ignoredInventory.inventory_sha256
        volatile_ignored_file_count = [int]$volatileInventory.file_count
        volatile_ignored_path_list_sha256 = $volatilePathDigest
        untracked = @($untrackedInventory.files)
        ignored = @($ignoredInventory.files)
    }
}

function Snapshot-Digest($Snapshot) { return String-Sha256 ($Snapshot | ConvertTo-Json -Depth 8 -Compress) }

function Assert-TrustedRuntimeInputs([string]$GitCommand, [string]$Root, [string]$InitialHead, $ExpectedHashes, [string[]]$RelativePaths) {
    $actual = Get-TrustedInputHashes $Root $RelativePaths
    $expectedNames = $(if ($ExpectedHashes -is [Collections.IDictionary]) { @($ExpectedHashes.Keys) } else { @($ExpectedHashes.PSObject.Properties.Name) })
    if ($expectedNames.Count -ne $RelativePaths.Count) { Stop-Launcher "POST-TRUST" "trusted input manifest count drift" 6 }
    foreach ($relative in $RelativePaths) {
        $key = $relative.Replace('\', '/')
        $hasKey = $(if ($ExpectedHashes -is [Collections.IDictionary]) { $ExpectedHashes.Contains($key) } else { $null -ne $ExpectedHashes.PSObject.Properties[$key] })
        $expectedValue = $(if ($ExpectedHashes -is [Collections.IDictionary]) { $ExpectedHashes[$key] } else { $ExpectedHashes.PSObject.Properties[$key].Value })
        if (-not $hasKey -or [string]$expectedValue -cne [string]$actual[$key]) { Stop-Launcher "POST-TRUST" "trusted input changed after Codex: $key" 6 }
    }
    $diffArguments = @("-C", $Root, "diff", "--name-only", "$InitialHead..HEAD", "--") + @($RelativePaths)
    $changed = SafeGit $GitCommand $diffArguments
    Native-OK $changed "POST-TRUST" "trusted input commit-range check"
    if (-not [string]::IsNullOrWhiteSpace($changed.Text)) { Stop-Launcher "POST-TRUST" "Codex commit range modifies trusted runner/planning/validator input: $($changed.Text)" 6 }
    Write-Pass "POST-TRUST trusted input hashes and commit range"
}

function Invoke-TrustedValidatorProcess([string]$PowerShellCommand, [byte[]]$TrustedValidatorBytes, [string]$ResultPath, [string]$ExpectedRunId, [string]$ProjectRoot, [string]$ExpectedAttemptStartedAt, [string]$ExpectedReleaseId = "") {
    $utf8 = New-Object Text.UTF8Encoding -ArgumentList $false
    $payload = [ordered]@{
        validator_base64 = [Convert]::ToBase64String($TrustedValidatorBytes)
        parameters = [ordered]@{ResultPath=$ResultPath;ExpectedRunId=$ExpectedRunId;ExpectedReleaseId=$ExpectedReleaseId;ProjectRoot=$ProjectRoot;ExpectedAttemptStartedAt=$ExpectedAttemptStartedAt}
    } | ConvertTo-Json -Depth 4 -Compress
    # Only this small constant wrapper appears on the command line. The exact
    # pre-Codex validator bytes cross an anonymous stdin pipe to avoid the
    # Windows command-line limit and any post-Codex target-file execution.
    $wrapper = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $validatorBytes = [Convert]::FromBase64String([string]$payload.validator_base64)
    if ($validatorBytes.Length -ge 3 -and $validatorBytes[0] -eq 0xEF -and $validatorBytes[1] -eq 0xBB -and $validatorBytes[2] -eq 0xBF) {
        $normalizedBytes = New-Object byte[] ($validatorBytes.Length - 3)
        if ($normalizedBytes.Length -gt 0) { [Buffer]::BlockCopy($validatorBytes, 3, $normalizedBytes, 0, $normalizedBytes.Length) }
    } else {
        $normalizedBytes = $validatorBytes
    }
    $strictUtf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
    $validatorText = $strictUtf8.GetString($normalizedBytes)
    $validator = [scriptblock]::Create($validatorText)
    $parameters = $payload.parameters
    if ([string]::IsNullOrWhiteSpace([string]$parameters.ExpectedReleaseId)) {
        & $validator -ResultPath $parameters.ResultPath -ExpectedRunId $parameters.ExpectedRunId -ProjectRoot $parameters.ProjectRoot -ExpectedAttemptStartedAt $parameters.ExpectedAttemptStartedAt
    } else {
        & $validator -ResultPath $parameters.ResultPath -ExpectedRunId $parameters.ExpectedRunId -ExpectedReleaseId $parameters.ExpectedReleaseId -ProjectRoot $parameters.ProjectRoot -ExpectedAttemptStartedAt $parameters.ExpectedAttemptStartedAt
    }
    throw 'trusted validator returned without explicit process exit'
} catch {
    $hostMessage = 'ParserError: ' + [string]$_.Exception.Message
    [Console]::Error.WriteLine('FAIL [TRUSTED-VALIDATOR-HOST]: ' + $hostMessage)
    exit 6
}
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapper))
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.FileName = $PowerShellCommand; $psi.Arguments = "-NoLogo -NoProfile -EncodedCommand $encoded"
    $psi.WorkingDirectory = Get-TrustedExecutableWorkingDirectory $PowerShellCommand
    Set-SafeProcessEnvironment $psi
    $process = New-Object Diagnostics.Process; $process.StartInfo = $psi; $started = $false; $job = [IntPtr]::Zero; $stdoutTask = $null; $stderrTask = $null
    try {
        if (-not $process.Start()) { throw "trusted validator process did not start" }; $started = $true; $job = New-KillOnCloseJob $process "Required"
        $stdoutTask = $process.StandardOutput.ReadToEndAsync(); $stderrTask = $process.StandardError.ReadToEndAsync()
        $payloadBytes = $utf8.GetBytes($payload)
        $process.StandardInput.BaseStream.Write($payloadBytes, 0, $payloadBytes.Length); $process.StandardInput.Close()
        if (-not $process.WaitForExit(300000)) { throw "trusted validator timed out" }
        if ($job -ne [IntPtr]::Zero) { Close-KillOnCloseJob $job; $job = [IntPtr]::Zero }
        if (-not $stdoutTask.Wait(30000) -or -not $stderrTask.Wait(30000)) { throw "trusted validator stream drain timed out after process-tree termination" }
        $stdout = $stdoutTask.GetAwaiter().GetResult(); $stderr = $stderrTask.GetAwaiter().GetResult()
        return [pscustomobject]@{ ExitCode=$process.ExitCode; Text=(($stdout + "`n" + $stderr).Trim()) }
    } catch {
        if ($job -ne [IntPtr]::Zero) { Close-KillOnCloseJob $job; $job = [IntPtr]::Zero }
        if ($started -and -not $process.HasExited) { try { Stop-NativeProcessTree $process } catch { }; try { $process.WaitForExit() } catch { } }
        throw
    } finally {
        try { $process.StandardInput.Close() } catch { }
        if ($job -ne [IntPtr]::Zero) { Close-KillOnCloseJob $job; $job = [IntPtr]::Zero }
        if ($started -and -not $process.HasExited) { try { Stop-NativeProcessTree $process } catch { }; try { $process.WaitForExit() } catch { } }
        try { if ($null -ne $stdoutTask -and -not $stdoutTask.IsCompleted) { [void]$stdoutTask.Wait(5000) } } catch { }
        try { if ($null -ne $stderrTask -and -not $stderrTask.IsCompleted) { [void]$stderrTask.Wait(5000) } } catch { }
        $process.Dispose()
    }
}

function Write-AtomicUtf8Text([string]$Path, [string]$Value, [switch]$Replace) {
    $temporary = "$Path.tmp-$([Guid]::NewGuid().ToString('N'))"
    $utf8NoBom = New-Object Text.UTF8Encoding -ArgumentList $false
    try {
        [IO.File]::WriteAllText($temporary, $Value, $utf8NoBom)
        if (Test-Path -LiteralPath $Path) {
            if (-not $Replace) { throw "atomic receipt destination already exists" }
            [IO.File]::Replace($temporary, $Path, $null); $temporary = $null
        } else { [IO.File]::Move($temporary, $Path); $temporary = $null }
    } finally { if ($null -ne $temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Read-Utf8NoBomText([string]$Path, [long]$MaximumBytes, [string]$Context) {
    [void](Assert-BoundedFile $Path $MaximumBytes "UTF8-SIZE" $Context)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { Stop-Launcher "UTF8-BOM" "$Context must be UTF-8 without BOM" 6 }
    try { return (New-Object Text.UTF8Encoding -ArgumentList $false, $true).GetString($bytes) } catch { Stop-Launcher "UTF8" "$Context is not strict UTF-8: $($_.Exception.Message)" 6 }
}

function Try-PersistThreadReceipt([string]$JsonlPath, [string]$ReceiptPath, [string]$ExpectedThreadId = "") {
    if (Test-Path -LiteralPath $ReceiptPath -PathType Leaf) {
        $persisted = (Read-Utf8NoBomText $ReceiptPath 128 "session receipt").Trim()
        if ($persisted -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') { throw "persisted session receipt is invalid" }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedThreadId) -and $persisted -cne $ExpectedThreadId) { throw "persisted session receipt differs from expected thread" }
        return $persisted
    }
    if (-not (Test-Path -LiteralPath $JsonlPath -PathType Leaf)) { return $null }
    $ids = New-Object 'Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::Ordinal)
    $strictUtf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
    $stream = [IO.File]::Open($JsonlPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $maximumEarlyBytes = 1048576
        $length = [int][Math]::Min([long]$maximumEarlyBytes, $stream.Length)
        $buffer = New-Object byte[] $length; $read = 0
        while ($read -lt $buffer.Length) { $count = $stream.Read($buffer, $read, $buffer.Length - $read); if ($count -eq 0) { break }; $read += $count }
        $start = 0
        for ($index = 0; $index -lt $read; $index += 1) {
            if ($buffer[$index] -ne 0x0A) { if (($index - $start) -gt $MaxJsonlLineBytes) { throw "early Codex JSONL line exceeds $MaxJsonlLineBytes bytes" }; continue }
            $count = $index - $start; if ($count -gt 0 -and $buffer[$index - 1] -eq 0x0D) { $count -= 1 }
            if ($count -gt 0) {
                try {
                    $line = $strictUtf8.GetString($buffer, $start, $count)
                    $event = ConvertFrom-StrictJsonText $line "early Codex JSONL" -ThrowOnError
                    if ($event.type -is [string] -and [string]$event.type -ceq "thread.started" -and @($event.PSObject.Properties.Name).Count -eq 2 -and $event.PSObject.Properties.Name -contains "thread_id" -and $event.thread_id -is [string]) {
                        $candidate = [string]$event.thread_id
                        if ($candidate -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') { [void]$ids.Add($candidate) }
                    }
                } catch { }
            }
            $start = $index + 1
        }
    } finally { $stream.Dispose() }
    if ($ids.Count -eq 0) { return $null }
    if ($ids.Count -ne 1) { throw "multiple Codex thread IDs observed before completion" }
    $id = @($ids)[0]
    if (-not [string]::IsNullOrWhiteSpace($ExpectedThreadId) -and $id -cne $ExpectedThreadId) { throw "Codex thread ID differs from expected resume thread" }
    Write-AtomicUtf8Text $ReceiptPath $id
    return $id
}

function Assert-NoReparseComponent([string]$Path, [string]$Code) {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    $tail = $full.Substring($root.Length)
    foreach ($segment in ($tail -split '[\\/]+' | Where-Object { $_ })) {
        $current = Join-Path $current $segment
        if (Test-Path -LiteralPath $current) {
            if ((((Get-Item -LiteralPath $current -Force).Attributes) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-Launcher $Code "reparse-point component forbidden: $current" }
        }
    }
}

function Get-NoFollowTreeEntries([string]$Root, [string]$Code, [string]$Label, [int]$MaximumEntries = $MaxWorktreeFiles) {
    $resolved=Canonical $Root
    if (-not [IO.Directory]::Exists($resolved)) { Stop-Launcher $Code "$Label root is missing: $resolved" 6 }
    Assert-NoReparseComponent $resolved $Code
    $rootItem=Get-Item -LiteralPath $resolved -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-Launcher $Code "$Label root is a reparse point" 6 }
    $queue=New-Object Collections.Generic.Queue[string]
    $queue.Enqueue($resolved)
    $result=New-Object Collections.Generic.List[string]
    while ($queue.Count -gt 0) {
        $directory=$queue.Dequeue()
        $directoryItem=Get-Item -LiteralPath $directory -Force
        if (($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or -not $directoryItem.PSIsContainer) { Stop-Launcher $Code "$Label traversal reached a reparse or non-directory node: $directory" 6 }
        try { $children=@([IO.Directory]::EnumerateFileSystemEntries($directory,"*",[IO.SearchOption]::TopDirectoryOnly)) } catch { Stop-Launcher $Code "$Label directory cannot be enumerated without following links: $directory" 6 }
        [Array]::Sort($children,[StringComparer]::OrdinalIgnoreCase)
        foreach ($child in $children) {
            $item=Get-Item -LiteralPath $child -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-Launcher $Code "$Label contains a forbidden reparse point: $child" 6 }
            $result.Add([IO.Path]::GetFullPath($child))
            if ($result.Count -gt $MaximumEntries) { Stop-Launcher $Code "$Label has too many entries" 6 }
            if ($item.PSIsContainer) { $queue.Enqueue([IO.Path]::GetFullPath($child)) }
        }
    }
    return $result.ToArray()
}

function Get-GitControlPlaneSnapshot([string]$GitDirectory, [string]$CommonDirectory, [string]$DotGitPath) {
    # This function is deliberately direct .NET filesystem I/O. It must remain
    # safe to call before any post-Codex Git process can evaluate repository
    # config, hooks, fsmonitor, attributes, excludes, alternates, or replace refs.
    $gitDir = Canonical $GitDirectory; $commonDir = Canonical $CommonDirectory; $dotGit = Canonical $DotGitPath
    $worktreeRoot = Canonical (Split-Path -Parent $dotGit)
    $worktreeGitmodules = Join-Path $worktreeRoot ".gitmodules"
    $commonModules = Join-Path $commonDir "modules"
    if ([IO.File]::Exists($worktreeGitmodules) -or [IO.Directory]::Exists($worktreeGitmodules) -or [IO.File]::Exists($commonModules) -or [IO.Directory]::Exists($commonModules)) { Stop-Launcher "GIT-SUBMODULE" "submodules are outside the approved single-repository control plane; .gitmodules and common .git/modules must be absent" 6 }
    foreach ($rootPath in @($gitDir, $commonDir, $dotGit)) { Assert-NoReparseComponent $rootPath "GIT-CONTROL" }
    $candidates = New-Object Collections.Generic.List[object]
    function Add-ControlCandidate([string]$Label, [string]$Path, [bool]$Recursive) {
        $candidates.Add([pscustomobject]@{label=$Label;path=[IO.Path]::GetFullPath($Path);recursive=$Recursive})
    }
    if ([IO.File]::Exists($dotGit)) { Add-ControlCandidate "dot-git-pointer" $dotGit $false }
    foreach ($pair in @(
        @("worktree/.gitmodules", $worktreeGitmodules),
        @("common/modules", $commonModules),
        @("common/config", (Join-Path $commonDir "config")),
        @("common/config.worktree", (Join-Path $commonDir "config.worktree")),
        @("gitdir/config.worktree", (Join-Path $gitDir "config.worktree")),
        @("common/info/exclude", (Join-Path $commonDir "info/exclude")),
        @("common/info/attributes", (Join-Path $commonDir "info/attributes")),
        @("common/info/sparse-checkout", (Join-Path $commonDir "info/sparse-checkout")),
        @("common/info/grafts", (Join-Path $commonDir "info/grafts")),
        @("gitdir/info/exclude", (Join-Path $gitDir "info/exclude")),
        @("gitdir/info/attributes", (Join-Path $gitDir "info/attributes")),
        @("gitdir/info/sparse-checkout", (Join-Path $gitDir "info/sparse-checkout")),
        @("common/objects/info/alternates", (Join-Path $commonDir "objects/info/alternates")),
        @("common/objects/info/http-alternates", (Join-Path $commonDir "objects/info/http-alternates")),
        @("gitdir/objects/info/alternates", (Join-Path $gitDir "objects/info/alternates")),
        @("gitdir/objects/info/http-alternates", (Join-Path $gitDir "objects/info/http-alternates")),
        @("common/shallow", (Join-Path $commonDir "shallow")),
        @("gitdir/shallow", (Join-Path $gitDir "shallow")),
        @("gitdir/commondir", (Join-Path $gitDir "commondir")),
        @("gitdir/gitdir", (Join-Path $gitDir "gitdir"))
    )) { Add-ControlCandidate $pair[0] $pair[1] $false }
    foreach ($pair in @(
        @("common/hooks", (Join-Path $commonDir "hooks")),
        @("gitdir/hooks", (Join-Path $gitDir "hooks")),
        @("common/refs/replace", (Join-Path $commonDir "refs/replace")),
        @("gitdir/refs/replace", (Join-Path $gitDir "refs/replace"))
    )) { Add-ControlCandidate $pair[0] $pair[1] $true }

    $entries = New-Object Collections.Generic.List[object]
    $seenPhysical = New-Object 'Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in @($candidates | Sort-Object label)) {
        $path = [string]$candidate.path
        if (-not $seenPhysical.Add($path)) { continue }
        $label = [string]$candidate.label
        if ([IO.File]::Exists($path)) {
            Assert-NoReparseComponent $path "GIT-CONTROL"
            $bytes = [IO.File]::ReadAllBytes($path)
            if ($bytes.LongLength -gt $MaxJsonBytes) { Stop-Launcher "GIT-CONTROL" "Git control file exceeds $MaxJsonBytes bytes: $label" 6 }
            $entries.Add([ordered]@{label=$label;kind="file";relative="";length=[long]$bytes.LongLength;sha256=(Bytes-Sha256 $bytes)})
            continue
        }
        if ([IO.Directory]::Exists($path)) {
            Assert-NoReparseComponent $path "GIT-CONTROL"
            $entries.Add([ordered]@{label=$label;kind="directory";relative="";length=0;sha256=$null})
            if ($candidate.recursive) {
                $children = @(Get-NoFollowTreeEntries $path "GIT-CONTROL" "Git control tree $label")
                foreach ($child in $children) {
                    $relative = $child.Substring($path.Length).TrimStart([char[]]@('\','/')).Replace('\','/')
                    $item = Get-Item -LiteralPath $child -Force
                    if ($item.PSIsContainer) { $entries.Add([ordered]@{label=$label;kind="directory";relative=$relative;length=0;sha256=$null}); continue }
                    $bytes = [IO.File]::ReadAllBytes($child)
                    if ($bytes.LongLength -gt $MaxJsonBytes) { Stop-Launcher "GIT-CONTROL" "Git control file exceeds $MaxJsonBytes bytes: $label/$relative" 6 }
                    $entries.Add([ordered]@{label=$label;kind="file";relative=$relative;length=[long]$bytes.LongLength;sha256=(Bytes-Sha256 $bytes)})
                }
            }
            continue
        }
        $entries.Add([ordered]@{label=$label;kind="missing";relative="";length=0;sha256=$null})
    }
    return [ordered]@{schema_version="git-control-plane-snapshot.v1";git_dir=$gitDir;common_dir=$commonDir;dot_git_path=$dotGit;entries=$entries.ToArray()}
}

function Compare-GitControlPlaneSnapshot($Expected, $Actual) {
    if ($null -eq $Expected -or $null -eq $Actual) { return $false }
    return [StringComparer]::Ordinal.Equals(($Expected | ConvertTo-Json -Depth 8 -Compress), ($Actual | ConvertTo-Json -Depth 8 -Compress))
}

function Assert-GitControlPlaneSnapshot($Expected) {
    $actual = Get-GitControlPlaneSnapshot ([string]$Expected.git_dir) ([string]$Expected.common_dir) ([string]$Expected.dot_git_path)
    if (-not (Compare-GitControlPlaneSnapshot $Expected $actual)) { Stop-Launcher "POST-GIT-CONTROL" "Git metadata/config/hooks/excludes/attributes/alternates/replace refs/submodule controls changed during Codex execution; no post-Codex Git command was executed" 6 }
    Write-Pass "POST-GIT-CONTROL direct .NET byte snapshot unchanged before Git re-entry"
}

function Get-GitReferenceSnapshot([string]$GitDirectory, [string]$CommonDirectory) {
    $gitDir=Canonical $GitDirectory; $commonDir=Canonical $CommonDirectory
    $candidates=New-Object Collections.Generic.List[object]
    foreach ($pair in @(
        @("gitdir/HEAD",(Join-Path $gitDir "HEAD"),$false),
        @("gitdir/index",(Join-Path $gitDir "index"),$false),
        @("common/index",(Join-Path $commonDir "index"),$false),
        @("gitdir/packed-refs",(Join-Path $gitDir "packed-refs"),$false),
        @("common/packed-refs",(Join-Path $commonDir "packed-refs"),$false),
        @("gitdir/refs/heads",(Join-Path $gitDir "refs/heads"),$true),
        @("gitdir/refs/tags",(Join-Path $gitDir "refs/tags"),$true),
        @("common/refs/heads",(Join-Path $commonDir "refs/heads"),$true),
        @("common/refs/tags",(Join-Path $commonDir "refs/tags"),$true)
    )) { $candidates.Add([pscustomobject]@{label=$pair[0];path=[IO.Path]::GetFullPath($pair[1]);recursive=[bool]$pair[2]}) }
    $entries=New-Object Collections.Generic.List[object]
    $seenPhysical=New-Object 'Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in @($candidates | Sort-Object label)) {
        $path=[string]$candidate.path
        if (-not $seenPhysical.Add($path)) { continue }
        Assert-NoReparseComponent $path "GIT-REFS"
        if ([IO.File]::Exists($path)) {
            $bytes=[IO.File]::ReadAllBytes($path)
            if ($bytes.LongLength -gt $MaxJsonBytes) { Stop-Launcher "GIT-REFS" "Git reference file exceeds bounded size: $($candidate.label)" 6 }
            $entries.Add([ordered]@{label=[string]$candidate.label;kind="file";relative="";length=[long]$bytes.LongLength;sha256=(Bytes-Sha256 $bytes)})
            continue
        }
        if ([IO.Directory]::Exists($path)) {
            $entries.Add([ordered]@{label=[string]$candidate.label;kind="directory";relative="";length=0;sha256=$null})
            $children=@(Get-NoFollowTreeEntries $path "GIT-REFS" "Git reference tree $($candidate.label)")
            foreach ($child in $children) {
                $relative=$child.Substring($path.Length).TrimStart([char[]]@('\','/')).Replace('\','/')
                $item=Get-Item -LiteralPath $child -Force
                if ($item.PSIsContainer) { $entries.Add([ordered]@{label=[string]$candidate.label;kind="directory";relative=$relative;length=0;sha256=$null}); continue }
                $bytes=[IO.File]::ReadAllBytes($child)
                if ($bytes.LongLength -gt $MaxJsonBytes) { Stop-Launcher "GIT-REFS" "Git reference file exceeds bounded size: $($candidate.label)/$relative" 6 }
                $entries.Add([ordered]@{label=[string]$candidate.label;kind="file";relative=$relative;length=[long]$bytes.LongLength;sha256=(Bytes-Sha256 $bytes)})
            }
            continue
        }
        $entries.Add([ordered]@{label=[string]$candidate.label;kind="missing";relative="";length=0;sha256=$null})
    }
    return [ordered]@{schema_version="git-reference-snapshot.v1";git_dir=$gitDir;common_dir=$commonDir;entries=$entries.ToArray()}
}

function Compare-GitReferenceSnapshot($Expected,$Actual) {
    if ($null -eq $Expected -or $null -eq $Actual) { return $false }
    return [StringComparer]::Ordinal.Equals(($Expected | ConvertTo-Json -Depth 8 -Compress),($Actual | ConvertTo-Json -Depth 8 -Compress))
}

function ConvertTo-JcsString([string]$Value) {
    $builder = New-Object Text.StringBuilder; [void]$builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        $code = [int][char]$character
        if ($code -eq 0x22) { [void]$builder.Append('\"') }
        elseif ($code -eq 0x5C) { [void]$builder.Append('\\') }
        elseif ($code -eq 0x08) { [void]$builder.Append('\b') }
        elseif ($code -eq 0x09) { [void]$builder.Append('\t') }
        elseif ($code -eq 0x0A) { [void]$builder.Append('\n') }
        elseif ($code -eq 0x0C) { [void]$builder.Append('\f') }
        elseif ($code -eq 0x0D) { [void]$builder.Append('\r') }
        elseif ($code -lt 0x20) { [void]$builder.Append(('\u{0:x4}' -f $code)) }
        else { [void]$builder.Append($character) }
    }
    [void]$builder.Append('"'); return $builder.ToString()
}

function Get-SourceTreeHash([string]$GitCommand, [string]$Root, [string]$Commit, $Inventory) {
    $tree = SafeGit $GitCommand @("-C", $Root, "rev-parse", "$Commit^{tree}"); Native-OK $tree "POST-SOURCE-TREE" "source tree object"
    $listing = Invoke-SafeGitCaptureBytes $GitCommand @("-C", $Root, "ls-tree", "-r", "-z", "--full-tree", $Commit) $MaxWorktreeSnapshotBytes
    if ($listing.ExitCode -ne 0) { Stop-Launcher "POST-SOURCE-TREE" "tracked source tree listing failed: $($listing.ErrorText)" 6 }
    $strictUtf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
    try { $text = $strictUtf8.GetString($listing.Bytes) } catch { Stop-Launcher "POST-SOURCE-TREE" "tracked source tree has non-UTF-8 paths" 6 }
    $excludedRoots = @($Inventory.roots.PSObject.Properties | ForEach-Object { ([string]$_.Value).TrimStart('/') })
    $records = New-Object Collections.Generic.List[object]; $seen = @{}; $total = 0L
    foreach ($line in @($text.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))) {
        if ($line -notmatch '^(?<mode>[0-9]{6}) (?<type>[a-z]+) (?<oid>[0-9a-f]{40,64})\t(?<path>.+)$') { Stop-Launcher "POST-SOURCE-TREE" "unparseable tracked tree row" 6 }
        $mode = $Matches.mode; $type = $Matches.type; $path = $Matches.path.Normalize([Text.NormalizationForm]::FormC).Replace('\','/')
        if (@($excludedRoots | Where-Object { $path.StartsWith($_, [StringComparison]::Ordinal) }).Count -gt 0) { continue }
        if ($mode -notin @("100644","100755") -or $type -cne "blob") { Stop-Launcher "POST-SOURCE-TREE" "source tree contains symlink/submodule/non-regular entry: $path ($mode/$type)" 6 }
        if ([string]::IsNullOrWhiteSpace($path) -or $path -match '[\x00-\x1f\x7f\\:%]|(^|/)\.\.?(/|$)' -or [IO.Path]::IsPathRooted($path) -or $seen.ContainsKey($path)) { Stop-Launcher "POST-SOURCE-TREE" "unsafe/duplicate normalized tracked path: $path" 6 }
        $seen[$path] = $true
        $blob = Invoke-SafeGitCaptureBytes $GitCommand @("-C", $Root, "cat-file", "blob", "$Commit`:$path") $MaxWorktreeFileBytes
        if ($blob.ExitCode -ne 0) { Stop-Launcher "POST-SOURCE-TREE" "cannot read tracked blob: $path" 6 }
        $total += [long]$blob.Bytes.Length
        if ($total -gt $MaxWorktreeSnapshotBytes -or $records.Count -ge $MaxWorktreeFiles) { Stop-Launcher "POST-SOURCE-TREE" "source tree exceeds bounded files/bytes policy" 6 }
        $sortKey = ([BitConverter]::ToString($strictUtf8.GetBytes($path))).Replace("-", "")
        $records.Add([pscustomobject]@{path=$path;mode=$mode;length=[long]$blob.Bytes.Length;content_sha256=(Bytes-Sha256 $blob.Bytes);sort_key=$sortKey})
    }
    $parts = New-Object Collections.Generic.List[string]
    foreach ($record in @($records | Sort-Object sort_key)) {
        $parts.Add('{"content_sha256":' + (ConvertTo-JcsString $record.content_sha256) + ',"mode":' + (ConvertTo-JcsString $record.mode) + ',"path":' + (ConvertTo-JcsString $record.path) + ',"size_bytes":' + $record.length.ToString([Globalization.CultureInfo]::InvariantCulture) + '}')
    }
    $canonical = '{"files":[' + ($parts -join ',') + '],"schema":"source-tree-manifest.v1"}'
    return [ordered]@{tree_object=$tree.Text;source_tree_sha256=(String-Sha256 $canonical);file_count=$records.Count;total_bytes=$total}
}

function ConvertFrom-RequiredUtc([string]$Value, [string]$Context) {
    if ($Value -notmatch 'Z$') { Stop-Launcher "POST-TIME" "$Context must use canonical UTC Z" 6 }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, ([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal), [ref]$parsed)) { Stop-Launcher "POST-TIME" "$Context is not a valid UTC timestamp" 6 }
    return $parsed
}

function Assert-ExactStringArray($Actual, $Expected, [string]$Context) {
    $actualValues = @($Actual); $expectedValues = @($Expected)
    if ($actualValues.Count -ne $expectedValues.Count) { Stop-Launcher "POST-EVIDENCE" "$Context count mismatch" 6 }
    for ($index = 0; $index -lt $expectedValues.Count; $index += 1) {
        if ($actualValues[$index] -isnot [string] -or [string]$actualValues[$index] -cne [string]$expectedValues[$index]) { Stop-Launcher "POST-EVIDENCE" "$Context exact ordered value mismatch at $index" 6 }
    }
}

function Assert-ExactRequiredCiInventory($CheckInventory, [string[]]$RequiredChecks) {
    $checks = @($CheckInventory.check_runs)
    if ([int]$CheckInventory.total_count -ne $RequiredChecks.Count -or $checks.Count -ne $RequiredChecks.Count) { Stop-Launcher "POST-PR" "final HEAD must have exactly the four required CI check runs and no extras" 6 }
    $actualNames = @($checks | ForEach-Object { [string]$_.name } | Sort-Object)
    $expectedNames = @($RequiredChecks | Sort-Object)
    if (@(Compare-Object -ReferenceObject $expectedNames -DifferenceObject $actualNames).Count -ne 0 -or @($actualNames | Sort-Object -Unique).Count -ne $RequiredChecks.Count) { Stop-Launcher "POST-PR" "final HEAD CI check-name set must exactly equal the four required unique checks" 6 }
    return $checks
}

function Assert-TrackedRepositoryFile([string]$GitCommand, [string]$Root, [string]$Relative, [string]$Context) {
    $tracked = SafeGit $GitCommand @("-C", $Root, "ls-files", "--error-unmatch", "--", $Relative)
    if ($tracked.ExitCode -ne 0 -or [string]$tracked.Text -cne $Relative.Replace('\','/')) { Stop-Launcher "POST-TRACKED" "$Context must be an exact tracked candidate file, never ignored/untracked: $Relative" 6 }
}

function Quote-WindowsArgument([string]$Value) {
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"'); $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes += 1; continue }
        if ($character -eq '"') { [void]$builder.Append(('\' * ($slashes * 2 + 1))); [void]$builder.Append('"'); $slashes = 0; continue }
        if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)); $slashes = 0 }
        [void]$builder.Append($character)
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * ($slashes * 2))) }
    [void]$builder.Append('"'); return $builder.ToString()
}

function Invoke-Utf8Process(
    [string]$Command,
    [string[]]$Arguments,
    [string]$InputText,
    [string]$StdoutPath,
    [string]$StderrPath,
    [string]$RunId = "unknown",
    [ValidateRange(1, 3600)][int]$HeartbeatSeconds = 5,
    [string]$ResumeCommand = "",
    [string]$SessionReceiptPath = "",
    [string]$ExpectedThreadId = "",
    [long]$MaximumStdoutBytes = $MaxJsonlBytes,
    [long]$MaximumStderrBytes = $MaxNativeCaptureBytes,
    [ValidateRange(1, 21600)][int]$TimeoutSeconds = $MaxCodexSeconds
) {
    # ProcessStartInfo + concurrent raw CopyToAsync makes UTF-8 stdin and both
    # output streams byte-faithful and deadlock-safe on Windows PowerShell 5.1/PS7.
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $argumentLine = (($Arguments | ForEach-Object { Quote-WindowsArgument $_ }) -join ' ')
    if ([IO.Path]::GetExtension($Command) -match '^\.(cmd|bat)$') { throw "shell shims are forbidden; trusted tools must be direct executable files" }
    $psi.FileName = $Command; $psi.Arguments = $argumentLine
    $psi.WorkingDirectory = Get-TrustedExecutableWorkingDirectory $Command
    Set-SafeProcessEnvironment $psi
    $process = New-Object Diagnostics.Process; $process.StartInfo = $psi
    $stdout = [IO.File]::Open($StdoutPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $stderr = [IO.File]::Open($StderrPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $started = $false; $stdoutTask = $null; $stderrTask = $null; $job = [IntPtr]::Zero; $boundedStdout = $null; $boundedStderr = $null
    try {
        if (-not $process.Start()) { throw "native process did not start" }
        $started = $true; $job = New-KillOnCloseJob $process "Required"
        $boundedStdout = (New-BoundedCaptureStream $stdout $MaximumStdoutBytes).Stream
        $boundedStderr = (New-BoundedCaptureStream $stderr $MaximumStderrBytes).Stream
        $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($boundedStdout)
        $stderrTask = $process.StandardError.BaseStream.CopyToAsync($boundedStderr)
        $utf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
        $bytes = $utf8.GetBytes($InputText)
        $inputTask = $process.StandardInput.BaseStream.WriteAsync($bytes, 0, $bytes.Length)
        if (-not $inputTask.Wait([Math]::Min(60000, $TimeoutSeconds * 1000))) { throw "Codex stdin write exceeded hard timeout" }
        [void]$inputTask.GetAwaiter().GetResult(); $process.StandardInput.Close()
        $startedAt = [DateTimeOffset]::UtcNow
        $deadline = $startedAt.AddSeconds($TimeoutSeconds)
        $nextHeartbeat = $startedAt.AddSeconds($HeartbeatSeconds)
        while (-not $process.WaitForExit(250)) {
            if ($stdoutTask.IsFaulted -or $stderrTask.IsFaulted) { throw "Codex output exceeded bounded capture limits stdout=$MaximumStdoutBytes stderr=$MaximumStderrBytes" }
            if ([DateTimeOffset]::UtcNow -ge $deadline) { throw "Codex process exceeded hard timeout $TimeoutSeconds seconds" }
            if ([DateTimeOffset]::UtcNow -lt $nextHeartbeat) { continue }
            $nextHeartbeat = [DateTimeOffset]::UtcNow.AddSeconds($HeartbeatSeconds)
            # Read-only progress reporting. Never append summaries or heartbeat
            # text to the raw stdout/stderr evidence files.
            $stdoutBytes = 0L; $stderrBytes = 0L; $eventSummary = "pending"
            try { $stdoutBytes = (Get-Item -LiteralPath $StdoutPath -Force).Length } catch { $stdoutBytes = 0L }
            try { $stderrBytes = (Get-Item -LiteralPath $StderrPath -Force).Length } catch { $stderrBytes = 0L }
            if ($stdoutBytes -gt $MaximumStdoutBytes -or $stderrBytes -gt $MaximumStderrBytes) { throw "Codex output exceeded bounded capture limits stdout=$MaximumStdoutBytes stderr=$MaximumStderrBytes" }
            try {
                $readerStream = [IO.File]::Open($StdoutPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                try {
                    $MaxTailBytes = 131072
                    $tailBytes = [Math]::Min([long]$MaxTailBytes, $readerStream.Length)
                    [void]$readerStream.Seek(-$tailBytes, [IO.SeekOrigin]::End)
                    $buffer = New-Object byte[] ([int]$tailBytes); $read = 0
                    while ($read -lt $buffer.Length) { $count = $readerStream.Read($buffer, $read, $buffer.Length - $read); if ($count -eq 0) { break }; $read += $count }
                    $tailText = (New-Object Text.UTF8Encoding -ArgumentList $false, $true).GetString($buffer, 0, $read)
                    if ($readerStream.Length -gt $MaxTailBytes) {
                        $firstNewline = $tailText.IndexOf("`n")
                        $tailText = $(if ($firstNewline -ge 0) { $tailText.Substring($firstNewline + 1) } else { "" })
                    }
                    $lastNewline = $tailText.LastIndexOf("`n")
                    if ($lastNewline -ge 0) {
                        $completedLines = @($tailText.Substring(0, $lastNewline) -split "`n" | Where-Object { $_.Trim().Length -gt 0 })
                        if ($completedLines.Count -gt 0) {
                            $lastComplete = $completedLines[-1].TrimEnd([char]13) | ConvertFrom-Json
                            if ($lastComplete.PSObject.Properties.Name -contains "type") { $eventSummary = [string]$lastComplete.type }
                        }
                    }
                } finally { $readerStream.Dispose() }
            } catch { $eventSummary = "partial-jsonl" }
            if (-not [string]::IsNullOrWhiteSpace($SessionReceiptPath)) {
                $receipt = Try-PersistThreadReceipt $StdoutPath $SessionReceiptPath $ExpectedThreadId
                if ($null -ne $receipt) { $eventSummary = "thread.started:$receipt" }
            }
            $elapsed = [DateTimeOffset]::UtcNow - $startedAt
            Write-Host ("RUNNING: run_id={0}, elapsed={1:hh\:mm\:ss}, progress={2}, stdout_bytes={3}, stderr_bytes={4}, event={5}" -f $RunId, $elapsed, $StdoutPath, $stdoutBytes, $stderrBytes, $eventSummary)
        }
        if ($job -ne [IntPtr]::Zero) { Close-KillOnCloseJob $job; $job = [IntPtr]::Zero }
        try { $stdoutDone = $stdoutTask.Wait(30000); $stderrDone = $stderrTask.Wait(30000) } catch { throw "Codex output exceeded bounded capture limits stdout=$MaximumStdoutBytes stderr=$MaximumStderrBytes" }
        if (-not $stdoutDone -or -not $stderrDone) { throw "Codex stream drain timed out after process-tree termination" }
        try { [void]$stdoutTask.GetAwaiter().GetResult(); [void]$stderrTask.GetAwaiter().GetResult() } catch { throw "Codex output exceeded bounded capture limits stdout=$MaximumStdoutBytes stderr=$MaximumStderrBytes" }
        if ($stdout.Length -gt $MaximumStdoutBytes -or $stderr.Length -gt $MaximumStderrBytes) { throw "Codex output exceeded bounded capture limits after stream drain" }
        if (-not [string]::IsNullOrWhiteSpace($SessionReceiptPath)) { [void](Try-PersistThreadReceipt $StdoutPath $SessionReceiptPath $ExpectedThreadId) }
        return $process.ExitCode
    } catch {
        if ($job -ne [IntPtr]::Zero) { Close-KillOnCloseJob $job; $job = [IntPtr]::Zero }
        if ($started -and -not $process.HasExited) {
            try { Stop-NativeProcessTree $process } catch { }
            try { $process.WaitForExit() } catch { }
        }
        throw
    } finally {
        try { $process.StandardInput.Close() } catch { }
        if ($job -ne [IntPtr]::Zero) { Close-KillOnCloseJob $job; $job = [IntPtr]::Zero }
        if ($started -and -not $process.HasExited) {
            try { Stop-NativeProcessTree $process } catch { }
            try { $process.WaitForExit() } catch { }
        }
        if (($null -ne $stdoutTask -and -not $stdoutTask.IsCompleted) -or ($null -ne $stderrTask -and -not $stderrTask.IsCompleted)) { $stdout.Dispose(); $stderr.Dispose() }
        try { if ($null -ne $stdoutTask) { [void]$stdoutTask.Wait(5000) } } catch { }
        try { if ($null -ne $stderrTask) { [void]$stderrTask.Wait(5000) } } catch { }
        if ($null -ne $boundedStdout) { $boundedStdout.Dispose() } else { $stdout.Dispose() }
        if ($null -ne $boundedStderr) { $boundedStderr.Dispose() } else { $stderr.Dispose() }
        $process.Dispose()
    }
}

function Assert-CodexEventSemantics($Event, [int]$LineNumber) {
    if ($null -eq $Event -or $Event -isnot [psobject] -or $Event -is [Array]) { throw "Codex JSONL line $LineNumber must be an object" }
    if ($Event.PSObject.Properties.Name -notcontains "type" -or $Event.type -isnot [string]) { throw "Codex JSONL line $LineNumber type must be a scalar exact string" }
    $type = [string]$Event.type
    $contracts = @{
        "thread.started"=@("type","thread_id"); "turn.started"=@("type"); "turn.completed"=@("type","usage");
        "turn.failed"=@("type","error"); "item.started"=@("type","item"); "item.updated"=@("type","item");
        "item.completed"=@("type","item"); "error"=@("type","message")
    }
    if (-not $contracts.ContainsKey($type)) { throw "Codex JSONL line $LineNumber has an unrecognized event type: $type" }
    $actual = @($Event.PSObject.Properties.Name | Sort-Object); $expected = @($contracts[$type] | Sort-Object)
    if ($actual.Count -ne $expected.Count -or @(Compare-Object -ReferenceObject $expected -DifferenceObject $actual).Count -ne 0) { throw "Codex JSONL line $LineNumber violates the closed $type event property set" }
    if ($type -ceq "thread.started" -and ($Event.thread_id -isnot [string] -or [string]$Event.thread_id -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$')) { throw "Codex JSONL line $LineNumber has an invalid thread UUID" }
    if ($type -like "item.*" -and ($null -eq $Event.item -or $Event.item -isnot [psobject] -or $Event.item -is [Array])) { throw "Codex JSONL line $LineNumber item must be an object" }
    if ($type -ceq "turn.completed" -and ($null -eq $Event.usage -or $Event.usage -isnot [psobject] -or $Event.usage -is [Array])) { throw "Codex JSONL line $LineNumber usage must be an object" }
    if ($type -ceq "error" -and $Event.message -isnot [string]) { throw "Codex JSONL line $LineNumber error message must be a string" }
}

function Read-CodexEvents([string]$Path) {
    $events = New-Object Collections.ArrayList; $lineNumber = 0; $parseError = $null
    [void](Assert-BoundedFile $Path $MaxJsonlBytes "PROGRESS-JSONL-SIZE" "Codex JSONL")
    $strictUtf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $lineBytes = New-Object IO.MemoryStream
    try {
        $buffer = New-Object byte[] 65536
        $stopReading = $false
        while (-not $stopReading -and ($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            for ($index = 0; $index -lt $count; $index += 1) {
                $octet = $buffer[$index]
                if ($octet -ne 0x0A) {
                    $lineBytes.WriteByte($octet)
                    if ($lineBytes.Length -gt $MaxJsonlLineBytes) { $parseError = "line $($lineNumber + 1) exceeds $MaxJsonlLineBytes bytes"; $stopReading = $true; break }
                    continue
                }
                $lineNumber += 1
                $bytes = $lineBytes.ToArray(); $lineBytes.SetLength(0)
                if ($bytes.Length -gt 0 -and $bytes[$bytes.Length - 1] -eq 0x0D) { $bytes = $(if ($bytes.Length -eq 1) { New-Object byte[] 0 } else { $bytes[0..($bytes.Length - 2)] }) }
                if ($bytes.Length -eq 0) { continue }
                try {
                    $line = $strictUtf8.GetString($bytes)
                    $event = ConvertFrom-StrictJsonText $line "Codex JSONL line $lineNumber" -ThrowOnError
                    Assert-CodexEventSemantics $event $lineNumber
                    if ([string]$event.type -ceq "thread.started") { [void]$events.Add($event) }
                } catch { $parseError = $_.Exception.Message; $stopReading = $true; break }
            }
        }
        if ($null -eq $parseError -and $lineBytes.Length -gt 0) {
            $lineNumber += 1; $bytes = $lineBytes.ToArray()
            if ($bytes.Length -gt 0 -and $bytes[$bytes.Length - 1] -eq 0x0D) { $bytes = $(if ($bytes.Length -eq 1) { New-Object byte[] 0 } else { $bytes[0..($bytes.Length - 2)] }) }
            try {
                $line = $strictUtf8.GetString($bytes); $event = ConvertFrom-StrictJsonText $line "Codex JSONL line $lineNumber" -ThrowOnError
                Assert-CodexEventSemantics $event $lineNumber
                if ([string]$event.type -ceq "thread.started") { [void]$events.Add($event) }
            } catch { $parseError = $_.Exception.Message }
        }
    } finally { $lineBytes.Dispose(); $stream.Dispose() }
    if ($events.Count -eq 0 -and $null -eq $parseError) { $parseError = "no Codex thread.started event" }
    return [pscustomobject]@{ Events=$events.ToArray(); ParseError=$parseError }
}

function Get-ThreadId($Events) {
    $started = @($Events | Where-Object { $_.type -ceq "thread.started" -and $_.PSObject.Properties.Name -contains "thread_id" })
    $ids = @($started | ForEach-Object { [string]$_.thread_id } | Where-Object { $_ -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' } | Sort-Object -Unique)
    if ($started.Count -ne 1 -or $ids.Count -ne 1) { Stop-Launcher "SESSION-ID" "expected exactly one valid thread.started/thread_id UUID" 3 }
    return $ids[0]
}

function Assert-SafeCodexArguments([string[]]$Arguments) { foreach ($flag in @("--dangerously-bypass-approvals-and-sandbox", "--yolo", "--full-auto", "--last")) { if ($Arguments -contains $flag) { Stop-Launcher "PRE-UNSAFE" "forbidden Codex flag: $flag" } }; Write-Pass "PRE-UNSAFE Codex argument policy" }

function Get-FinalDocumentInventoryPaths($Inventory, [string]$ReleaseId) {
    if ($ReleaseId -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+-(rc|RC)[0-9]+$') { Stop-Launcher "POST-DOCS" "unsafe release ID for document inventory" 6 }
    if ($Inventory.schema_version -cne "final-document-inventory.v1" -or $Inventory.baseline_id -cne "YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1") { Stop-Launcher "POST-DOCS" "final-document inventory identity mismatch" 6 }
    if ($Inventory.dynamic_segment_contract.only_placeholder -cne '${release_id}' -or $ReleaseId -notmatch ([string]$Inventory.release_id_pattern)) { Stop-Launcher "POST-DOCS" "final-document release placeholder contract mismatch" 6 }
    $allowedGates = @("GATE-DESIGN-INTEGRITY", "GATE-CODE-QUALITY", "GATE-SECURITY-PRIVACY", "GATE-AI-KPI", "GATE-DOCUMENT-KPI", "GATE-UX-ACCESSIBILITY", "GATE-OPERATIONS-RECOVERY", "GATE-PILOT-ACCEPTANCE")
    $expectedRoots = @{final_design="docs/design/ai-training-platform/";operations="docs/operations/ai-training-platform/";quality_assurance="docs/qa/ai-training-platform/";manuals="docs/manuals/ai-training-platform/";releases="docs/releases/ai-training-platform/";distribution_docs="dist/docs/"}
    $rootProperties = @($Inventory.roots.PSObject.Properties); $rootMap = @{}
    if ($rootProperties.Count -ne $expectedRoots.Count) { Stop-Launcher "POST-DOCS" "final-document root set mismatch" 6 }
    foreach ($rootProperty in $rootProperties) {
        $rootPath = [string]$rootProperty.Value
        if (-not $expectedRoots.ContainsKey($rootProperty.Name) -or $rootPath -cne $expectedRoots[$rootProperty.Name] -or [string]::IsNullOrWhiteSpace($rootPath) -or -not $rootPath.EndsWith("/") -or $rootPath -match '[\\:]|(^|/)\.\.?(?:/|$)' -or [IO.Path]::IsPathRooted($rootPath)) { Stop-Launcher "POST-DOCS" "unsafe inventory root: $($rootProperty.Name)" 6 }
        $rootMap[$rootProperty.Name] = $rootPath
    }
    $artifacts = @($Inventory.artifacts)
    if ([int]$Inventory.expected_counts.total -ne $artifacts.Count -or $artifacts.Count -eq 0) { Stop-Launcher "POST-DOCS" "final-document inventory total mismatch" 6 }
    foreach ($countProperty in @($Inventory.expected_counts.PSObject.Properties | Where-Object { $_.Name -cne "total" })) {
        if (@($artifacts | Where-Object { [string]$_.group -ceq $countProperty.Name }).Count -ne [int]$countProperty.Value) { Stop-Launcher "POST-DOCS" "final-document group count mismatch: $($countProperty.Name)" 6 }
    }
    $seenIds = @{}; $seenPaths = @{}; $paths = @()
    foreach ($artifact in $artifacts) {
        $artifactId = [string]$artifact.artifact_id; $rootId = [string]$artifact.root_id; $template = [string]$artifact.relative_path_template
        if ([string]::IsNullOrWhiteSpace($artifactId) -or $seenIds.ContainsKey($artifactId) -or -not $rootMap.ContainsKey($rootId) -or [string]$artifact.root_path -cne $rootMap[$rootId] -or $artifact.required -ne $true) { Stop-Launcher "POST-DOCS" "invalid/duplicate inventory artifact: $artifactId" 6 }
        $seenIds[$artifactId] = $true
        if (@($artifact.owner_ids).Count -eq 0 -or @($artifact.gate_ids).Count -eq 0 -or @($artifact.gate_ids | Where-Object { $allowedGates -cnotcontains [string]$_ }).Count -gt 0) { Stop-Launcher "POST-DOCS" "inventory owner/gate contract missing: $artifactId" 6 }
        $expandedTemplate = $template.Replace('${release_id}', $ReleaseId)
        $unexpectedTokens = $template.Replace('${release_id}', '')
        if ([string]::IsNullOrWhiteSpace($template) -or $unexpectedTokens -match '[\$%{}\\:]' -or $expandedTemplate -match '[\\:]|(^|/)\.\.?(?:/|$)' -or [IO.Path]::IsPathRooted($expandedTemplate)) { Stop-Launcher "POST-DOCS" "unsafe inventory path template: $artifactId" 6 }
        $relative = ($rootMap[$rootId] + $expandedTemplate).TrimStart('/')
        if ($relative -match '[\\:]|(^|/)\.\.?(?:/|$)' -or $seenPaths.ContainsKey($relative)) { Stop-Launcher "POST-DOCS" "unsafe/duplicate expanded inventory path: $artifactId" 6 }
        $seenPaths[$relative] = $true; $paths += $relative
    }
    return @($paths)
}

function Assert-ExactObjectProperties($Object, [string[]]$Expected, [string]$Context) {
    if ($null -eq $Object -or $Object -isnot [psobject]) { Stop-Launcher "POST-ATTESTATION" "$Context must be an object" 6 }
    $actual = @($Object.PSObject.Properties.Name | Sort-Object)
    $wanted = @($Expected | Sort-Object)
    if ($actual.Count -ne $wanted.Count -or @(Compare-Object -ReferenceObject $wanted -DifferenceObject $actual).Count -ne 0) { Stop-Launcher "POST-ATTESTATION" "$Context property set mismatch" 6 }
}

function Resolve-RootRelativeFile([string]$Root, [string]$Relative, [string]$Context) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '^[A-Za-z]:' -or $Relative -match '[\x00:]|(^|[\\/])\.\.?(?:[\\/]|$)') { Stop-Launcher "POST-ATTESTATION" "$Context has an unsafe path: $Relative" 6 }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    if (-not $full.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf) -or (Get-Item -LiteralPath $full -Force).Length -le 0) { Stop-Launcher "POST-ATTESTATION" "$Context file is missing, empty, or outside root: $Relative" 6 }
    Assert-NoReparseComponent $full "POST-ATTESTATION"
    return $full
}

function Get-ValidSignatureStatus([string]$StatusText, [string]$Context) {
    $matches = @([regex]::Matches($StatusText, '(?m)^\[GNUPG:\] VALIDSIG ([0-9A-Fa-f]{40,64}) \S+ \S+ \S+ \S+ \S+ ([0-9]+) ([0-9]+) \S+(?: \S+)?\r?$'))
    if ($matches.Count -ne 1) { Stop-Launcher "POST-ATTESTATION" "$Context must contain exactly one complete GnuPG VALIDSIG status" 6 }
    return [pscustomobject]@{
        fingerprint = $matches[0].Groups[1].Value.ToUpperInvariant()
        public_key_algorithm = [int]$matches[0].Groups[2].Value
        hash_algorithm = [int]$matches[0].Groups[3].Value
    }
}

function Assert-ValidSignaturePolicy([string]$StatusText, [string]$ExpectedFingerprint, [string]$Context) {
    $status = Get-ValidSignatureStatus $StatusText $Context
    if ($status.fingerprint -cne $ExpectedFingerprint.ToUpperInvariant() -or $status.public_key_algorithm -ne 22 -or $status.hash_algorithm -ne 8) { Stop-Launcher "POST-ATTESTATION" "$Context signer must be the trusted EdDSA/Ed25519 key using SHA-256 (GnuPG algorithms 22/8)" 6 }
    return $status
}

function Assert-DetachedSignature([string]$GpgCommand, [string]$SignatureFull, [string]$SubjectFull, [string]$ExpectedFingerprint, [string]$Context) {
    $verified = TrustedGpg $GpgCommand @("--status-fd=1", "--verify", $SignatureFull, $SubjectFull)
    Native-OK $verified "POST-ATTESTATION" "$Context detached signature"
    [void](Assert-ValidSignaturePolicy $verified.Text $ExpectedFingerprint $Context)
}

function Assert-ArtifactManifestAndChecksums($Artifact, [string]$ExpectedScope, [string]$ExpectedRootRelative, [string]$ExpectedHead, $CandidateTree, [int64]$CommitEpoch, [string]$ReleaseId, [string]$ArtifactReleaseState, [string]$Root, [string]$GitCommand, $Baseline, [string]$BaselineHash, [string]$ExpectedSignerFingerprint, [string]$ReleaseManifestSha256 = "") {
    Assert-ExactObjectProperties $Artifact @("manifest_path", "checksums_path") "$ExpectedScope tracked artifact paths"
    $manifestFull = Resolve-RootRelativeFile $Root ([string]$Artifact.manifest_path) "$ExpectedScope artifact manifest"
    $checksumsFull = Resolve-RootRelativeFile $Root ([string]$Artifact.checksums_path) "$ExpectedScope checksums"
    foreach ($relative in @([string]$Artifact.manifest_path,[string]$Artifact.checksums_path)) { Assert-TrackedRepositoryFile $GitCommand $Root $relative "$ExpectedScope integrity artifact" }
    $manifest = ConvertFrom-StrictJsonFile $manifestFull "$ExpectedScope artifact manifest"
    Assert-ExactObjectProperties $manifest @("schema_version","release","release_state","scope","source_release_manifest_sha256","source_commit","source_tree_object_format","source_tree","source_tree_sha256","baseline_id","baseline_version","baseline_sha256","builder_image_digest","source_date_epoch","tool_versions","files","integrity_exclusions","generated_at_utc","signing_policy") "$ExpectedScope artifact manifest"
    $expectedObjectFormat = $(if ([string]$CandidateTree.tree_object -match '^[0-9a-f]{40}$') { "sha1" } else { "sha256" })
    $expectedSourceRelease = $(if ($ExpectedScope -ceq "RELEASE") { $null } else { $ReleaseManifestSha256 })
    if ([string]$manifest.schema_version -cne "artifact-manifest.v1" -or [string]$manifest.release -cne $ReleaseId -or [string]$manifest.release_state -cne $ArtifactReleaseState -or [string]$manifest.scope -cne $ExpectedScope -or [string]$manifest.source_commit -cne $ExpectedHead -or [string]$manifest.source_tree_object_format -cne $expectedObjectFormat -or [string]$manifest.source_tree -cne [string]$CandidateTree.tree_object -or [string]$manifest.source_tree_sha256 -cne [string]$CandidateTree.source_tree_sha256 -or [string]$manifest.baseline_id -cne [string]$Baseline.baseline_id -or [string]$manifest.baseline_version -cne [string]$Baseline.baseline_version -or [string]$manifest.baseline_sha256 -cne $BaselineHash -or [string]$manifest.builder_image_digest -notmatch '^sha256:[0-9a-f]{64}$' -or [int64]$manifest.source_date_epoch -ne $CommitEpoch) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope artifact manifest candidate/provenance binding mismatch" 6 }
    if (($ExpectedScope -ceq "RELEASE" -and $null -ne $manifest.source_release_manifest_sha256) -or ($ExpectedScope -ceq "DISTRIBUTION" -and [string]$manifest.source_release_manifest_sha256 -cne $expectedSourceRelease)) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope source release manifest provenance mismatch" 6 }
    $generated = ConvertFrom-RequiredUtc ([string]$manifest.generated_at_utc) "$ExpectedScope manifest generated_at_utc"
    if ($generated.ToUnixTimeSeconds() -ne $CommitEpoch) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope manifest timestamp must equal SOURCE_DATE_EPOCH" 6 }
    Assert-ExactObjectProperties $manifest.signing_policy @("algorithm","key_id") "$ExpectedScope signing policy"
    if ([string]$manifest.signing_policy.algorithm -cne "Ed25519" -or ([string]$manifest.signing_policy.key_id).ToUpperInvariant() -cne $ExpectedSignerFingerprint.ToUpperInvariant()) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope signing policy is not the trusted OWN-QA Ed25519 key" 6 }
    if (@($manifest.tool_versions.PSObject.Properties).Count -eq 0 -or @($manifest.tool_versions.PSObject.Properties | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Value) }).Count -gt 0) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope tool_versions must be a nonempty string map" 6 }

    # Detached signatures are external protected attestations.  The tracked
    # snapshot therefore excludes only the two self-describing integrity files.
    $excluded = @("artifact-manifest.json","SHA256SUMS.txt")
    $exclusions = @($manifest.integrity_exclusions)
    if ($exclusions.Count -ne 2) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope integrity exclusions must contain exactly two tracked integrity entries" 6 }
    foreach ($name in $excluded) {
        $matches = @($exclusions | Where-Object { [string]$_.path -ceq $name })
        if ($matches.Count -ne 1) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope exclusion set mismatch: $name" 6 }
        Assert-ExactObjectProperties $matches[0] @("path","reason") "$ExpectedScope exclusion"
        if ([string]::IsNullOrWhiteSpace([string]$matches[0].reason)) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope exclusion reason is empty" 6 }
    }

    $artifactRoot = [IO.Path]::GetFullPath((Join-Path $Root $ExpectedRootRelative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    if (-not (Test-Path -LiteralPath $artifactRoot -PathType Container)) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope artifact root is missing" 6 }
    Assert-NoReparseComponent $artifactRoot "POST-ARTIFACT"
    $actualContent = @{}; $totalBytes = 0L
    $allRootFiles = @(Get-NoFollowTreeEntries $artifactRoot "POST-ARTIFACT" "$ExpectedScope artifact root" | Where-Object { -not (Get-Item -LiteralPath $_ -Force).PSIsContainer })
    foreach ($full in $allRootFiles) {
        $relative = $full.Substring($artifactRoot.Length).TrimStart([char[]]@('\','/')).Replace('\','/').Normalize([Text.NormalizationForm]::FormC)
        $repoRelative = ($ExpectedRootRelative.TrimEnd('/') + "/" + $relative)
        Assert-TrackedRepositoryFile $GitCommand $Root $repoRelative "$ExpectedScope artifact content"
        $item = Get-Item -LiteralPath $full -Force; $totalBytes += [long]$item.Length
        if ($item.Length -le 0 -or $item.Length -gt $MaxWorktreeFileBytes -or $totalBytes -gt $MaxWorktreeSnapshotBytes) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope artifact file/root exceeds bounded nonempty policy: $relative" 6 }
        if ($excluded -notcontains $relative) { $actualContent[$relative] = [ordered]@{full=$full;length=[long]$item.Length;sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()} }
    }
    $files = @($manifest.files); $manifestPaths = @{}
    foreach ($file in $files) {
        Assert-ExactObjectProperties $file @("path","media_type","size_bytes","sha256","owner_ids","gate_ids","source_paths") "$ExpectedScope manifest file"
        $path = [string]$file.path
        if ([string]::IsNullOrWhiteSpace($path) -or $path -cne $path.Normalize([Text.NormalizationForm]::FormC) -or $path -match '[\x00-\x1f\x7f\\:%]|(^|/)\.\.?(/|$)' -or [IO.Path]::IsPathRooted($path) -or $manifestPaths.ContainsKey($path) -or -not $actualContent.ContainsKey($path)) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope manifest has unsafe/duplicate/uncovered path: $path" 6 }
        $manifestPaths[$path] = $true; $actual = $actualContent[$path]
        if ([string]::IsNullOrWhiteSpace([string]$file.media_type) -or [int64]$file.size_bytes -ne [int64]$actual.length -or [string]$file.sha256 -cne [string]$actual.sha256) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope file bytes/hash/media mismatch: $path" 6 }
        foreach ($owner in @($file.owner_ids)) { if ($owner -isnot [string] -or [string]$owner -notmatch '^OWN-[A-Z]+$') { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope file owner ID is invalid" 6 } }
        foreach ($gate in @($file.gate_ids)) { if (@($Baseline.release_gates | Where-Object { [string]$_.id -ceq [string]$gate }).Count -ne 1) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope file gate ID is not canonical: $gate" 6 } }
        if (@($file.owner_ids).Count -eq 0 -or @($file.owner_ids | Sort-Object -Unique).Count -ne @($file.owner_ids).Count -or @($file.gate_ids).Count -eq 0 -or @($file.gate_ids | Sort-Object -Unique).Count -ne @($file.gate_ids).Count -or @($file.source_paths).Count -eq 0 -or @($file.source_paths | Sort-Object -Unique).Count -ne @($file.source_paths).Count) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope file owner/gate/source arrays must be nonempty unique" 6 }
        foreach ($sourcePath in @($file.source_paths)) { $source = Resolve-RootRelativeFile $Root ([string]$sourcePath) "$ExpectedScope source path"; Assert-TrackedRepositoryFile $GitCommand $Root ([string]$sourcePath) "$ExpectedScope source path"; [void](Assert-BoundedFile $source $MaxWorktreeFileBytes "POST-ARTIFACT" "$ExpectedScope source path") }
    }
    if ($manifestPaths.Count -ne $actualContent.Count) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope manifest files do not exactly cover artifact root content" 6 }

    $checksumRows = New-Object Collections.Generic.List[object]
    foreach ($path in $actualContent.Keys) { $checksumRows.Add([pscustomobject]@{path=$path;sha256=$actualContent[$path].sha256;sort_key=([BitConverter]::ToString((New-Object Text.UTF8Encoding -ArgumentList $false).GetBytes($path))).Replace("-","")}) }
    foreach ($integrity in @(@{path="artifact-manifest.json";full=$manifestFull})) { $checksumRows.Add([pscustomobject]@{path=$integrity.path;sha256=(Get-FileHash -LiteralPath $integrity.full -Algorithm SHA256).Hash.ToLowerInvariant();sort_key=([BitConverter]::ToString((New-Object Text.UTF8Encoding -ArgumentList $false).GetBytes($integrity.path))).Replace("-","")}) }
    $expectedChecksums = ((@($checksumRows | Sort-Object sort_key) | ForEach-Object { "$($_.sha256)  $($_.path)`n" }) -join '')
    $actualChecksumBytes = [IO.File]::ReadAllBytes($checksumsFull)
    if ($actualChecksumBytes.Length -gt $MaxJsonBytes -or [Convert]::ToBase64String($actualChecksumBytes) -cne [Convert]::ToBase64String((New-Object Text.UTF8Encoding -ArgumentList $false).GetBytes($expectedChecksums))) { Stop-Launcher "POST-ARTIFACT" "$ExpectedScope SHA256SUMS exact coverage/order/UTF-8 bytes mismatch" 6 }
    return (Get-FileHash -LiteralPath $manifestFull -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ExactOrdinalArray($Actual, $Expected) {
    $left = @($Actual); $right = @($Expected)
    if ($left.Count -ne $right.Count) { return $false }
    for ($index = 0; $index -lt $left.Count; $index += 1) {
        if ($left[$index] -isnot [string] -or $right[$index] -isnot [string] -or [string]$left[$index] -cne [string]$right[$index]) { return $false }
    }
    return $true
}

function Assert-ReleaseIdentityObservation($Observation) {
    $hex40 = '^[0-9a-f]{40}$'; $hex64 = '^[0-9a-f]{64}$'
    if ([string]$Observation.implementation_commit -notmatch $hex40 -or [string]$Observation.release_snapshot_commit -notmatch $hex40 -or [string]$Observation.implementation_tree -notmatch $hex40 -or [string]$Observation.implementation_tree_sha256 -notmatch $hex64 -or
        [string]$Observation.implementation_commit -ceq [string]$Observation.release_snapshot_commit -or [string]$Observation.release_parent_commit -cne [string]$Observation.implementation_commit -or
        [string]$Observation.artifact_source_commit -cne [string]$Observation.implementation_commit -or [string]$Observation.evidence_source_commit -cne [string]$Observation.implementation_commit -or
        $Observation.initial_is_ancestor_of_implementation -ne $true -or $Observation.implementation_is_first_parent_of_release -ne $true) {
        Stop-Launcher "POLICY-IDENTITY" "release must be a non-self-referential S -> R first-parent snapshot whose artifacts/evidence bind S" 6
    }
    foreach ($path in @($Observation.release_diff_paths)) {
        if ($path -isnot [string] -or [string]::IsNullOrWhiteSpace($path) -or $path -match '[\\:]|(^|/)\.\.?(/|$)' -or
            -not ($path.StartsWith("docs/design/ai-training-platform/", [StringComparison]::Ordinal) -or $path.StartsWith("docs/operations/ai-training-platform/", [StringComparison]::Ordinal) -or
                $path.StartsWith("docs/qa/ai-training-platform/", [StringComparison]::Ordinal) -or $path.StartsWith("docs/manuals/ai-training-platform/", [StringComparison]::Ordinal) -or
                $path.StartsWith("docs/releases/ai-training-platform/", [StringComparison]::Ordinal) -or $path.StartsWith("dist/docs/", [StringComparison]::Ordinal))) {
            Stop-Launcher "POLICY-IDENTITY" "R may contain only final design, operations, QA, manual, release, and distribution snapshot artifacts" 6
        }
    }
}

function Assert-TrustedToolObservation($Observation) {
    $path = [string]$Observation.path; $workspace = [string]$Observation.workspace_root
    $authenticodeValid = $(if ($Observation.authenticode_required -eq $true) {
        [string]$Observation.authenticode_status -ceq "Valid" -and [string]$Observation.expected_signer_thumbprint -match '^[0-9A-F]{40,64}$' -and [string]$Observation.observed_signer_thumbprint -ceq [string]$Observation.expected_signer_thumbprint
    } else { [string]::IsNullOrEmpty([string]$Observation.expected_signer_thumbprint) })
    if (-not (Test-SafeTrustedExecutablePathSyntax $path) -or $path.StartsWith($workspace + "\", [StringComparison]::OrdinalIgnoreCase) -or
        [string]$Observation.expected_sha256 -notmatch '^[0-9a-f]{64}$' -or [string]$Observation.observed_sha256 -cne [string]$Observation.expected_sha256 -or
        -not $authenticodeValid -or $Observation.has_reparse_component -ne $false -or $Observation.broad_write_acl -ne $false) {
        Stop-Launcher "POLICY-TOOL" "trusted tool requires a canonical safe .exe, exact hash, protected non-writable path chain, and exact signer when explicitly required" 6
    }
}

function Assert-CiBindingObservation($Observation) {
    $actualLabels = @($Observation.runner_labels | Sort-Object); $expectedLabels = @($Observation.required_runner_labels | Sort-Object)
    if ([string]$Observation.repository -cne $ExpectedRepo -or [string]$Observation.release_snapshot_commit -notmatch '^[0-9a-f]{40}$' -or [int64]$Observation.pull_request_number -le 0 -or
        @($Observation.run_pull_request_numbers).Count -ne 1 -or [int64]$Observation.run_pull_request_numbers[0] -ne [int64]$Observation.pull_request_number -or
        @($Observation.check_pull_request_numbers).Count -ne 1 -or [int64]$Observation.check_pull_request_numbers[0] -ne [int64]$Observation.pull_request_number -or
        [string]$Observation.pull_request_base_sha -notmatch '^[0-9a-f]{40}$' -or [string]$Observation.run_pull_request_base_sha -cne [string]$Observation.pull_request_base_sha -or
        [string]$Observation.check_pull_request_base_sha -cne [string]$Observation.pull_request_base_sha -or [string]$Observation.run_pull_request_head_sha -cne [string]$Observation.release_snapshot_commit -or
        [string]$Observation.check_pull_request_head_sha -cne [string]$Observation.release_snapshot_commit -or
        [int64]$Observation.workflow_id -ne [int64]$Observation.expected_workflow_id -or [string]$Observation.workflow_path -cne [string]$Observation.expected_workflow_path -or
        [string]$Observation.base_workflow_sha256 -cne [string]$Observation.expected_workflow_sha256 -or [string]$Observation.release_workflow_sha256 -cne [string]$Observation.expected_workflow_sha256 -or
        [string]$Observation.base_workflow_sha256 -notmatch '^[0-9a-f]{64}$' -or [string]$Observation.release_workflow_sha256 -notmatch '^[0-9a-f]{64}$' -or
        @($Observation.allowed_actors) -cnotcontains [string]$Observation.actor -or [string]$Observation.event -cne "pull_request" -or [string]$Observation.status -cne "completed" -or
        [string]$Observation.conclusion -cne "success" -or [string]$Observation.check_name -cne [string]$Observation.expected_check_name -or
        $actualLabels.Count -ne $expectedLabels.Count -or @(Compare-Object -ReferenceObject $expectedLabels -DifferenceObject $actualLabels).Count -ne 0 -or
        (([string]$Observation.check_name -ceq "design-package-windows" -or [string]$Observation.check_name -ceq "release-signatures") -and $expectedLabels -cnotcontains "Windows")) {
        Stop-Launcher "POLICY-CI" "CI fact must bind exact PR/R/base, independently fetched base/R workflow bytes, trusted workflow id/path, allowed actor, named check, and required runner labels" 6
    }
}

function Assert-EvidenceBindingObservation($Observation) {
    $registry = @($Observation.registry); $records = @($Observation.records); $registryById = @{}; $recordById = @{}
    foreach ($item in $registry) { $id=[string]$item.evidence_id; if ([string]::IsNullOrWhiteSpace($id) -or $registryById.ContainsKey($id)) { Stop-Launcher "POLICY-EVIDENCE" "registry evidence IDs must be unique" 6 }; $registryById[$id]=$item }
    foreach ($item in $records) { $id=[string]$item.evidence_id; if ([string]::IsNullOrWhiteSpace($id) -or $recordById.ContainsKey($id)) { Stop-Launcher "POLICY-EVIDENCE" "record evidence IDs must be unique" 6 }; $recordById[$id]=$item }
    if ($registryById.Count -eq 0 -or $registryById.Count -ne $recordById.Count) { Stop-Launcher "POLICY-EVIDENCE" "record evidence ID set must exactly equal the trusted registry" 6 }
    foreach ($id in $registryById.Keys) {
        if (-not $recordById.ContainsKey($id)) { Stop-Launcher "POLICY-EVIDENCE" "missing registered evidence: $id" 6 }
        $expected=$registryById[$id]; $actual=$recordById[$id]
        if ([string]$actual.test_id -cne [string]$expected.test_id -or -not (Test-ExactOrdinalArray $actual.gate_ids $expected.gate_ids) -or
            -not (Test-ExactOrdinalArray $actual.kpi_ids $expected.kpi_ids) -or -not (Test-ExactOrdinalArray $actual.command_ids $expected.command_ids)) {
            Stop-Launcher "POLICY-EVIDENCE" "evidence consumer relationships must exactly match registry: $id" 6
        }
    }
}

function Assert-ResumeBindingObservation($Observation) {
    $ids=@([string]$Observation.run_id,[string]$Observation.requested_run_id,[string]$Observation.manifest_run_id,[string]$Observation.state_run_id)
    if (@($ids | Select-Object -Unique).Count -ne 1 -or $ids[0] -notmatch '^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$' -or
        [string]$Observation.canonical_run_directory -cne [string]$Observation.observed_run_directory -or [string]$Observation.manifest_sha256 -cne [string]$Observation.state_manifest_sha256 -or
        [string]$Observation.before_inventory_sha256 -cne [string]$Observation.execution_boundary_inventory_sha256 -or $Observation.exact_property_set -ne $true -or $Observation.exclusive_lock_held -ne $true) {
        Stop-Launcher "POLICY-RESUME" "resume must bind one run/schema/path/manifest and a locked execution-boundary inventory" 6
    }
}

function Assert-ReleaseStateTransition($Observation) {
    $valid = $false
    if ([string]$Observation.mode -ceq "Implement") { $valid = [string]$Observation.release_state -ceq "NOT_READY" -and [string]$Observation.candidate_phase -ceq "UNSIGNED_CANDIDATE / REVIEW PENDING" -and [int]$Observation.technical_signatures -eq 0 -and $Observation.acceptance_signature -eq $false -and $Observation.signed_tag -eq $false }
    elseif ([string]$Observation.mode -ceq "VerifyCandidate") { $valid = [string]$Observation.release_state -ceq "CODE_COMPLETE / ACCEPTANCE DATA PENDING" -and [int]$Observation.technical_signatures -eq 7 -and $Observation.acceptance_signature -eq $false -and $Observation.signed_tag -eq $false }
    elseif ([string]$Observation.mode -ceq "VerifyAccepted") { $valid = [string]$Observation.release_state -ceq "ACCEPTED" -and [int]$Observation.technical_signatures -eq 7 -and $Observation.acceptance_signature -eq $true -and $Observation.signed_tag -eq $true }
    if (-not $valid) { Stop-Launcher "POLICY-STATE" "release state is not reachable from the selected mode and external approvals" 6 }
}

function Assert-RemoteTagLookupObservation($Observation) {
    if ([string]$Observation.expectation -ceq "ABSENT") {
        if ([int]$Observation.exit_code -eq 0 -or [int]$Observation.http_status -ne 404) { Stop-Launcher "POLICY-TAG-LOOKUP" "remote tag absence requires an authenticated exact HTTP 404, never an arbitrary gh failure" 6 }
        return
    }
    if ([string]$Observation.expectation -ceq "PRESENT") {
        if ([int]$Observation.exit_code -ne 0 -or [int]$Observation.http_status -ne 200) { Stop-Launcher "POLICY-TAG-LOOKUP" "remote tag presence requires exact HTTP 200 and successful gh exit" 6 }
        return
    }
    Stop-Launcher "POLICY-TAG-LOOKUP" "unknown remote tag lookup expectation" 6
}

function Assert-WindowsPowerShellModulePathObservation($Observation) {
    $actual=Get-WindowsPowerShellModulePathPolicy ([string]$Observation.edition) ([string]$Observation.ps_home) ([string]$Observation.windows_directory) @($Observation.current_entries)
    $expectedSafePaths=@($Observation.expected_safe_paths)
    $expectedNormalizedEntries=@($Observation.expected_normalized_entries)
    $expectedRemovedEntries=@($Observation.expected_removed_entries)
    if ($actual.should_normalize -ne [bool]$Observation.should_normalize -or
        -not (Test-ExactOrdinalArray $actual.safe_paths $expectedSafePaths) -or
        -not (Test-ExactOrdinalArray $actual.normalized_entries $expectedNormalizedEntries) -or
        -not (Test-ExactOrdinalArray $actual.removed_entries $expectedRemovedEntries) -or
        [string]$actual.normalized_path -cne ($expectedNormalizedEntries -join [IO.Path]::PathSeparator)) {
        Stop-Launcher "POLICY-MODULE-PATH" "Windows PowerShell module path policy normalization mismatch" 6
    }
}
function Assert-GitConfigIsolationObservation($Observation) {
    $expectedHooksPath = "C:\ProgramData\YOnLab\empty-git-hooks"
    if ($Observation.raw_system_textconv_present -ne $true -or $Observation.safe_system_scope_ignored -ne $true -or $Observation.safe_global_scope_ignored -ne $true -or $Observation.safe_local_config_readable -ne $true -or $Observation.safe_git_pager_unset -ne $true -or $Observation.safe_attr_nosystem -ne $true -or [string]$Observation.safe_hooks_path -cne $expectedHooksPath -or $Observation.unsafe_config_without_safe_env_rejected -ne $true -or $Observation.local_executable_config_rejected -ne $true) {
        Stop-Launcher "POLICY-GIT-CONFIG" "Git system/global config isolation, local config preservation, pager/attribute controls, or executable-config rejection mismatch" 6
    }
}
function Assert-StreamBoundsObservation($Observation) {
    if ([int64]$Observation.stdout_bytes -lt 0 -or [int64]$Observation.stderr_bytes -lt 0 -or [int64]$Observation.total_bytes -ne ([int64]$Observation.stdout_bytes + [int64]$Observation.stderr_bytes) -or
        [int64]$Observation.total_bytes -gt [int64]$Observation.maximum_bytes -or [int64]$Observation.elapsed_milliseconds -ge [int64]$Observation.timeout_milliseconds) {
        Stop-Launcher "POLICY-BOUNDS" "native command exceeded exact byte or elapsed-time boundary" 6
    }
}

function Assert-JobIsolationObservation($Observation) {
    $mode=[string]$Observation.isolation_mode; $validModes=@("Required","BestEffortReadOnly","DisabledForPolicySelfTest")
    if ($validModes -notcontains $mode) { Stop-Launcher "POLICY-JOB" "unknown native isolation mode" 6 }
    $errorCode=[int]$Observation.access_denied_error_code; $assignmentFailed=($Observation.assignment_failed -eq $true); $assignmentAttempted=($Observation.native_job_assignment_attempted -eq $true)
    $fallback=($Observation.fallback_used -eq $true); $currentInJob=($Observation.current_process_in_job -eq $true); $message=[string]$Observation.error_message
    if ($mode -ceq "Required") {
        if (-not $currentInJob -or -not $assignmentAttempted -or -not $assignmentFailed -or $errorCode -ne 5 -or $fallback) { Stop-Launcher "POLICY-JOB" "Required isolation must fail closed on nested job assignment" 6 }
        if ($message -notmatch "Access Denied" -or $message -notmatch "nested Job Object" -or $message -notmatch "independent shell") { Stop-Launcher "POLICY-JOB" "Access Denied diagnostics must name nested Job Object and independent shell recovery" 6 }
        return
    }
    if ($mode -ceq "BestEffortReadOnly") {
        if (-not $currentInJob -or -not $assignmentAttempted -or -not $assignmentFailed -or $errorCode -ne 5 -or -not $fallback) { Stop-Launcher "POLICY-JOB" "BestEffortReadOnly may fallback only after access-denied assignment failure" 6 }
        if ([string]$Observation.command_kind -cne "ReadOnlyProbe" -or [string]$Observation.command -cne [string]$Observation.readonly_probe_command -or -not (Test-ExactOrdinalArray $Observation.arguments $Observation.readonly_probe_arguments)) { Stop-Launcher "POLICY-JOB" "BestEffortReadOnly fallback requires the exact allowlisted read-only probe" 6 }
        return
    }
    if ($assignmentAttempted -or $fallback -or [string]$Observation.command_kind -cne "PolicySelfTest") { Stop-Launcher "POLICY-JOB" "PolicySelfTest must not assign a native Job Object" 6 }
}

function Test-BytesContain([byte[]]$Haystack, [byte[]]$Needle) {
    if ($Needle.Length -eq 0 -or $Haystack.Length -lt $Needle.Length) { return $false }
    for ($offset = 0; $offset -le $Haystack.Length - $Needle.Length; $offset += 1) {
        $equal = $true
        for ($index = 0; $index -lt $Needle.Length; $index += 1) {
            if ($Haystack[$offset + $index] -ne $Needle[$index]) { $equal = $false; break }
        }
        if ($equal) { return $true }
    }
    return $false
}

function Resolve-ProtectedAttestationFile([string]$AttestationRoot, [string]$Relative, [string]$Context) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '^[A-Za-z]:' -or
        $Relative -match '[\x00-\x1f\x7f:]|(^|[\\/])\.\.?(?:[\\/]|$)' -or $Relative -cne $Relative.Normalize([Text.NormalizationForm]::FormC)) {
        Stop-Launcher "EXTERNAL-ATTESTATION" "$Context has an unsafe protected-root-relative path" 6
    }
    $full = [IO.Path]::GetFullPath((Join-Path $AttestationRoot $Relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    if (-not $full.StartsWith($AttestationRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $full -PathType Leaf)) { Stop-Launcher "EXTERNAL-ATTESTATION" "$Context is missing or escapes the protected attestation root" 6 }
    Assert-NoReparseComponent $full "EXTERNAL-ATTESTATION"
    Assert-ProtectedRootPathChain $full $AttestationRoot "EXTERNAL-ATTESTATION" $Context
    [void](Assert-BoundedFile $full $MaxJsonBytes "EXTERNAL-ATTESTATION" $Context)
    return $full
}

function Get-GitHubApiResponseWithStatus([string]$GhCommand,[string]$Endpoint,[string]$Context) {
    $response=Native-ReadOnly $GhCommand @("api","--include","--method","GET","-H","Accept: application/vnd.github+json",$Endpoint)
    $matches=@([regex]::Matches([string]$response.Text,'(?m)^HTTP/\S+\s+([0-9]{3})(?:\s|$)'))
    if ($matches.Count -ne 1) { Stop-Launcher "POST-TAG" "$Context did not return exactly one authenticated HTTP status line" 6 }
    $bodyMatch=[regex]::Match([string]$response.Text,'(?s)\r?\n\r?\n(.*)$')
    $body=$(if($bodyMatch.Success){$bodyMatch.Groups[1].Value.Trim()}else{""})
    return [pscustomobject]@{ExitCode=[int]$response.ExitCode;StatusCode=[int]$matches[0].Groups[1].Value;Body=$body}
}

function Get-ReleaseCandidateIdentity([string]$GitCommand, [string]$Root, [string]$BaselineCommit, [string]$ReleaseId, $Inventory, [string]$ExpectedImplementationCommit = "", [string]$ExpectedReleaseSnapshotCommit = "") {
    if ($BaselineCommit -notmatch '^[0-9a-f]{40}$' -or $ReleaseId -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+-(?:rc|RC)[0-9]+$') { Stop-Launcher "POST-IDENTITY" "baseline/release identity is invalid" 6 }
    $head = SafeGit $GitCommand @("-C", $Root, "rev-parse", "HEAD"); Native-OK $head "POST-IDENTITY" "release snapshot HEAD"
    $releaseSnapshot = [string]$head.Text
    $parentLine = SafeGit $GitCommand @("-C", $Root, "rev-list", "--parents", "-n", "1", $releaseSnapshot); Native-OK $parentLine "POST-IDENTITY" "release snapshot parent"
    $parentParts = @($parentLine.Text -split '\s+')
    if ($parentParts.Count -ne 2 -or $parentParts[0] -cne $releaseSnapshot -or $parentParts[1] -notmatch '^[0-9a-f]{40}$') { Stop-Launcher "POST-IDENTITY" "R must have exactly one parent S" 6 }
    $implementationCommit = [string]$parentParts[1]
    if ((-not [string]::IsNullOrWhiteSpace($ExpectedImplementationCommit) -and $implementationCommit -cne $ExpectedImplementationCommit) -or
        (-not [string]::IsNullOrWhiteSpace($ExpectedReleaseSnapshotCommit) -and $releaseSnapshot -cne $ExpectedReleaseSnapshotCommit)) { Stop-Launcher "POST-IDENTITY" "reported/bundled S or R differs from Git" 6 }
    $ancestor = SafeGit $GitCommand @("-C", $Root, "merge-base", "--is-ancestor", $BaselineCommit, $implementationCommit)
    if ($ancestor.ExitCode -ne 0) { Stop-Launcher "POST-IDENTITY" "baseline commit is not an ancestor of S" 6 }
    $firstParent = SafeGit $GitCommand @("-C", $Root, "rev-parse", "$releaseSnapshot^1"); Native-OK $firstParent "POST-IDENTITY" "R first parent"
    if ($firstParent.Text -cne $implementationCommit) { Stop-Launcher "POST-IDENTITY" "S is not the first parent of R" 6 }
    $diff = SafeGit $GitCommand @("-C", $Root, "diff-tree", "--no-commit-id", "--name-only", "-r", $releaseSnapshot); Native-OK $diff "POST-IDENTITY" "R snapshot path inventory"
    $diffPaths = @($diff.Text -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($diffPaths.Count -eq 0 -or @($diffPaths | Sort-Object -Unique).Count -ne $diffPaths.Count) { Stop-Launcher "POST-IDENTITY" "R must be a nonempty final-artifact-only snapshot" 6 }
    $tree = Get-SourceTreeHash $GitCommand $Root $implementationCommit $Inventory
    $releaseManifestPath = Join-Path $Root "docs/releases/ai-training-platform/$ReleaseId/artifact-manifest.json"
    $evidenceIndexPath = Join-Path $Root "docs/qa/ai-training-platform/evidence-index.json"
    $releaseManifest = ConvertFrom-StrictJsonFile $releaseManifestPath "release artifact manifest"
    $evidenceIndex = ConvertFrom-StrictJsonFile $evidenceIndexPath "canonical evidence index"
    $observation = [ordered]@{
        implementation_commit=$implementationCommit; release_snapshot_commit=$releaseSnapshot; release_parent_commit=$firstParent.Text
        implementation_tree=[string]$tree.tree_object; implementation_tree_sha256=[string]$tree.source_tree_sha256
        artifact_source_commit=[string]$releaseManifest.source_commit; evidence_source_commit=[string]$evidenceIndex.source_commit
        initial_is_ancestor_of_implementation=$true; implementation_is_first_parent_of_release=$true; release_diff_paths=$diffPaths
    }
    Assert-ReleaseIdentityObservation $observation

    # R cannot contain its own OID or tracked Actions run URLs.  This makes the
    # S -> R construction reproducible instead of a fixed-point claim.
    $oidBytes = [Text.Encoding]::ASCII.GetBytes($releaseSnapshot)
    $runUrlBytes = [Text.Encoding]::ASCII.GetBytes("https://github.com/$ExpectedRepo/actions/runs/")
    foreach ($path in $diffPaths) {
        $blob = Invoke-SafeGitCaptureBytes $GitCommand @("-C", $Root, "cat-file", "blob", "$releaseSnapshot`:$path") $MaxWorktreeFileBytes
        if ($blob.ExitCode -ne 0) { Stop-Launcher "POST-IDENTITY" "cannot inspect R artifact bytes: $path" 6 }
        if ((Test-BytesContain $blob.Bytes $oidBytes) -or (Test-BytesContain $blob.Bytes $runUrlBytes)) { Stop-Launcher "POST-IDENTITY" "R contains a prohibited self-reference OID or tracked Actions run URL: $path" 6 }
    }
    return [pscustomobject]@{ baseline_commit=$BaselineCommit; implementation_commit=$implementationCommit; release_snapshot_commit=$releaseSnapshot; tree=$tree; diff_paths=$diffPaths; release_manifest=$releaseManifest; evidence_index=$evidenceIndex }
}

function Get-GitHubRepositoryFileSha256AtCommit([string]$GhCommand,[string]$Commit,[string]$RepositoryPath,[string]$Context) {
    if ($Commit -notmatch '^[0-9a-f]{40}$' -or $RepositoryPath -notmatch '^\.github/workflows/[A-Za-z0-9._/-]+\.ya?ml$') { Stop-Launcher "POST-CI" "$Context commit/path is not an immutable workflow identity" 6 }
    $response=Native-ReadOnly $GhCommand @("api","--method","GET","-H","Accept: application/vnd.github+json","repos/$ExpectedRepo/contents/$RepositoryPath`?ref=$Commit")
    Native-OK $response "POST-CI" "$Context workflow content"
    $object=ConvertFrom-StrictJsonText $response.Text "$Context workflow content response"
    if ([string]$object.path -cne $RepositoryPath -or [string]$object.type -cne "file" -or [string]$object.encoding -cne "base64" -or [string]$object.sha -notmatch '^[0-9a-f]{40}$') { Stop-Launcher "POST-CI" "$Context workflow content response identity mismatch" 6 }
    $encoded=([string]$object.content).Replace("`r","").Replace("`n","")
    if ([string]::IsNullOrWhiteSpace($encoded) -or $encoded -notmatch '^[A-Za-z0-9+/]+={0,2}$') { Stop-Launcher "POST-CI" "$Context workflow content is not canonical base64" 6 }
    try { $bytes=[Convert]::FromBase64String($encoded) } catch { Stop-Launcher "POST-CI" "$Context workflow content cannot be decoded" 6 }
    if ($bytes.LongLength -le 0 -or $bytes.LongLength -gt $MaxWorktreeFileBytes) { Stop-Launcher "POST-CI" "$Context workflow bytes are empty or exceed the bounded file limit" 6 }
    return Bytes-Sha256 $bytes
}

function Get-AndAssertGitHubCandidateFacts([string]$GhCommand, [string]$ReleaseSnapshotCommit, $TrustedWorkflowByCheck, $AllowedActors) {
    $remoteHeadResponse = Native-ReadOnly $GhCommand @("api", "--method", "GET", "-H", "Accept: application/vnd.github+json", "repos/$ExpectedRepo/git/ref/heads/$ExpectedBranch"); Native-OK $remoteHeadResponse "POST-CI" "GitHub feature branch ref"
    $remoteHead = ConvertFrom-StrictJsonText $remoteHeadResponse.Text "GitHub feature branch ref"
    if ([string]$remoteHead.ref -cne "refs/heads/$ExpectedBranch" -or [string]$remoteHead.object.type -cne "commit" -or [string]$remoteHead.object.sha -cne $ReleaseSnapshotCommit) { Stop-Launcher "POST-CI" "remote feature branch differs from R" 6 }
    $prResponse = Native-ReadOnly $GhCommand @("api", "--method", "GET", "-H", "Accept: application/vnd.github+json", "repos/$ExpectedRepo/pulls?state=open&head=yubi-lee:$ExpectedBranch&base=main&per_page=100"); Native-OK $prResponse "POST-CI" "GitHub pull request inventory"
    $pullRequests = @(ConvertFrom-StrictJsonText $prResponse.Text "GitHub PR response")
    if ($pullRequests.Count -ne 1) { Stop-Launcher "POST-CI" "exactly one open same-repository feature-to-main PR is required" 6 }
    $pr = $pullRequests[0]
    $pullRequestBaseSha=[string]$pr.base.sha
    if ([string]$pr.state -cne "open" -or [string]$pr.head.ref -cne $ExpectedBranch -or [string]$pr.head.sha -cne $ReleaseSnapshotCommit -or [string]$pr.head.repo.full_name -cne $ExpectedRepo -or $pr.head.repo.fork -ne $false -or [string]$pr.base.ref -cne "main" -or [string]$pr.base.repo.full_name -cne $ExpectedRepo -or $pullRequestBaseSha -notmatch '^[0-9a-f]{40}$') { Stop-Launcher "POST-CI" "PR identity/head/base/fork policy mismatch" 6 }
    $checksResponse = Native-ReadOnly $GhCommand @("api", "--method", "GET", "-H", "Accept: application/vnd.github+json", "repos/$ExpectedRepo/commits/$ReleaseSnapshotCommit/check-runs?per_page=100"); Native-OK $checksResponse "POST-CI" "GitHub check runs"
    $checks = @(Assert-ExactRequiredCiInventory (ConvertFrom-StrictJsonText $checksResponse.Text "GitHub check-runs response") $RequiredCiChecks)
    $checkByName=@{}; $baseWorkflowHashes=@{}; $releaseWorkflowHashes=@{}
    foreach ($check in $checks) {
        $name=[string]$check.name
        if (-not $TrustedWorkflowByCheck.ContainsKey($name)) { Stop-Launcher "POST-CI" "untrusted CI check: $name" 6 }
        $policy=$TrustedWorkflowByCheck[$name]
        if ([string]$check.status -cne "completed" -or [string]$check.conclusion -cne "success" -or [int64]$check.app.id -ne 15368 -or [string]$check.app.slug -cne "github-actions" -or [string]$check.check_suite.head_sha -cne $ReleaseSnapshotCommit) { Stop-Launcher "POST-CI" "check is not a successful GitHub Actions check at R: $name" 6 }
        $details=[string]$check.details_url
        if ($details -notmatch '^https://github\.com/yubi-lee/yonlab-i-nuri-site/actions/runs/([0-9]+)/job/([0-9]+)$') { Stop-Launcher "POST-CI" "check must bind an exact Actions run and job: $name" 6 }
        $actionsRunId=[int64]$Matches[1]; $actionsJobId=[int64]$Matches[2]
        $runResponse=Native-ReadOnly $GhCommand @("api","--method","GET","-H","Accept: application/vnd.github+json","repos/$ExpectedRepo/actions/runs/$actionsRunId"); Native-OK $runResponse "POST-CI" "GitHub Actions run"
        $run=ConvertFrom-StrictJsonText $runResponse.Text "GitHub Actions run response"
        $runPullRequests=@($run.pull_requests); $runPrNumbers=@($runPullRequests | ForEach-Object { [int64]$_.number })
        if ([int64]$run.id -ne $actionsRunId -or [int64]$run.workflow_id -ne [int64]$policy.workflow_id -or [string]$run.path -cne [string]$policy.workflow_path -or [string]$run.head_sha -cne $ReleaseSnapshotCommit -or [string]$run.repository.full_name -cne $ExpectedRepo -or [string]$run.head_repository.full_name -cne $ExpectedRepo -or [string]$run.actor.login -notin @($AllowedActors) -or [string]$run.event -cne "pull_request" -or [string]$run.status -cne "completed" -or [string]$run.conclusion -cne "success") { Stop-Launcher "POST-CI" "workflow run identity/path/actor/status mismatch: $name" 6 }
        $jobsResponse=Native-ReadOnly $GhCommand @("api","--method","GET","-H","Accept: application/vnd.github+json","repos/$ExpectedRepo/actions/runs/$actionsRunId/jobs?per_page=100"); Native-OK $jobsResponse "POST-CI" "GitHub Actions jobs"
        $jobsObject=ConvertFrom-StrictJsonText $jobsResponse.Text "GitHub Actions jobs response"
        $jobs=@($jobsObject.jobs | Where-Object { [int64]$_.id -eq $actionsJobId })
        if ($jobs.Count -ne 1) { Stop-Launcher "POST-CI" "check job ID is absent or duplicated: $name" 6 }
        $job=$jobs[0]
        if ([string]$job.name -cne $name -or [string]$job.status -cne "completed" -or [string]$job.conclusion -cne "success" -or [string]::IsNullOrWhiteSpace([string]$job.runner_name)) { Stop-Launcher "POST-CI" "job name/status/runner binding mismatch: $name" 6 }
        $checkPullRequests=@($check.pull_requests); $checkPrNumbers=@($checkPullRequests | ForEach-Object { [int64]$_.number })
        if ($runPullRequests.Count -ne 1 -or $checkPullRequests.Count -ne 1) { Stop-Launcher "POST-CI" "run and check must each bind exactly one pull request: $name" 6 }
        $workflowPath=[string]$policy.workflow_path
        if (-not $baseWorkflowHashes.ContainsKey($workflowPath)) { $baseWorkflowHashes[$workflowPath]=Get-GitHubRepositoryFileSha256AtCommit $GhCommand $pullRequestBaseSha $workflowPath "PR base" }
        if (-not $releaseWorkflowHashes.ContainsKey($workflowPath)) { $releaseWorkflowHashes[$workflowPath]=Get-GitHubRepositoryFileSha256AtCommit $GhCommand $ReleaseSnapshotCommit $workflowPath "release snapshot" }
        $observation=[ordered]@{
            repository=$ExpectedRepo;release_snapshot_commit=$ReleaseSnapshotCommit;pull_request_number=[int64]$pr.number
            pull_request_base_sha=$pullRequestBaseSha;run_pull_request_numbers=$runPrNumbers;check_pull_request_numbers=$checkPrNumbers
            run_pull_request_base_sha=[string]$runPullRequests[0].base.sha;check_pull_request_base_sha=[string]$checkPullRequests[0].base.sha
            run_pull_request_head_sha=[string]$runPullRequests[0].head.sha;check_pull_request_head_sha=[string]$checkPullRequests[0].head.sha
            workflow_id=[int64]$run.workflow_id;expected_workflow_id=[int64]$policy.workflow_id;workflow_path=[string]$run.path;expected_workflow_path=$workflowPath
            base_workflow_sha256=[string]$baseWorkflowHashes[$workflowPath];release_workflow_sha256=[string]$releaseWorkflowHashes[$workflowPath];expected_workflow_sha256=[string]$policy.workflow_sha256
            allowed_actors=@($AllowedActors);actor=[string]$run.actor.login;event=[string]$run.event;status=[string]$run.status;conclusion=[string]$run.conclusion
            check_name=$name;expected_check_name=[string]$policy.check_name;runner_labels=@($job.labels);required_runner_labels=@($policy.required_runner_labels)
        }
        Assert-CiBindingObservation $observation
        $checkByName[$name]=$check
    }
    return [pscustomobject]@{ pull_request=$pr; checks=$checkByName; remote_head=$remoteHead }
}

function Assert-ExternalApproval($Approval, [string]$ExpectedOwner, [string]$ExpectedScope, [string]$ExpectedDecision, [string]$ReleaseId, [string]$ImplementationCommit, [string]$ReleaseSnapshotCommit, [string]$CandidateResultSha256, [string]$AttestationRoot, [string]$GpgCommand, [string]$ExpectedFingerprint, [hashtable]$SeenPaths) {
    Assert-ExactObjectProperties $Approval @("owner_id","scope_id","decision","subject_path","signature_path") "$ExpectedOwner external approval"
    if ([string]$Approval.owner_id -cne $ExpectedOwner -or [string]$Approval.scope_id -cne $ExpectedScope -or [string]$Approval.decision -cne $ExpectedDecision) { Stop-Launcher "EXTERNAL-ATTESTATION" "$ExpectedOwner approval identity/scope/decision mismatch" 6 }
    foreach ($property in @("subject_path","signature_path")) { $relative=[string]$Approval.$property; if ($SeenPaths.ContainsKey($relative)) { Stop-Launcher "EXTERNAL-ATTESTATION" "external attestation paths must be unique" 6 }; $SeenPaths[$relative]=$true }
    $subject=Resolve-ProtectedAttestationFile $AttestationRoot ([string]$Approval.subject_path) "$ExpectedOwner approval subject"
    $signature=Resolve-ProtectedAttestationFile $AttestationRoot ([string]$Approval.signature_path) "$ExpectedOwner approval signature"
    $subjectSha256=(Get-FileHash -LiteralPath $subject -Algorithm SHA256).Hash.ToLowerInvariant()
    $signatureSha256=(Get-FileHash -LiteralPath $signature -Algorithm SHA256).Hash.ToLowerInvariant()
    $subjectObject=ConvertFrom-StrictJsonFile $subject "$ExpectedOwner approval subject"
    Assert-ExactObjectProperties $subjectObject @("schema_version","release_id","repository","owner_id","scope_id","decision","implementation_commit","release_snapshot_commit","candidate_result_sha256") "$ExpectedOwner approval subject"
    if ([string]$subjectObject.schema_version -cne "release-approval-subject.v2" -or [string]$subjectObject.release_id -cne $ReleaseId -or [string]$subjectObject.repository -cne $ExpectedRepo -or [string]$subjectObject.owner_id -cne $ExpectedOwner -or [string]$subjectObject.scope_id -cne $ExpectedScope -or [string]$subjectObject.decision -cne $ExpectedDecision -or [string]$subjectObject.implementation_commit -cne $ImplementationCommit -or [string]$subjectObject.release_snapshot_commit -cne $ReleaseSnapshotCommit -or [string]$subjectObject.candidate_result_sha256 -cne $CandidateResultSha256) { Stop-Launcher "EXTERNAL-ATTESTATION" "$ExpectedOwner signed subject is not bound to exact S/R/result" 6 }
    Assert-DetachedSignature $GpgCommand $signature $subject $ExpectedFingerprint "$ExpectedOwner external approval"
    Assert-ProtectedRootPathChain $subject $AttestationRoot "EXTERNAL-ATTESTATION" "$ExpectedOwner approval subject post-use"
    Assert-ProtectedRootPathChain $signature $AttestationRoot "EXTERNAL-ATTESTATION" "$ExpectedOwner approval signature post-use"
    if ((Get-FileHash -LiteralPath $subject -Algorithm SHA256).Hash.ToLowerInvariant() -cne $subjectSha256 -or (Get-FileHash -LiteralPath $signature -Algorithm SHA256).Hash.ToLowerInvariant() -cne $signatureSha256) { Stop-Launcher "EXTERNAL-ATTESTATION" "$ExpectedOwner approval bytes changed while being verified" 6 }
}

function Assert-ExternalArtifactSignatures($ArtifactSignatures, [string]$ReleaseId, [string]$Root, [string]$AttestationRoot, [string]$GitCommand, [string]$GpgCommand, [string]$ExpectedFingerprint, [hashtable]$SeenPaths) {
    $expected=[ordered]@{
        "RELEASE-MANIFEST"="docs/releases/ai-training-platform/$ReleaseId/artifact-manifest.json"
        "RELEASE-CHECKSUMS"="docs/releases/ai-training-platform/$ReleaseId/SHA256SUMS.txt"
        "DISTRIBUTION-MANIFEST"="dist/docs/$ReleaseId/artifact-manifest.json"
        "DISTRIBUTION-CHECKSUMS"="dist/docs/$ReleaseId/SHA256SUMS.txt"
    }
    $items=@($ArtifactSignatures); if ($items.Count -ne $expected.Count) { Stop-Launcher "EXTERNAL-ATTESTATION" "exactly four external artifact signatures are required" 6 }
    $seenScopes=@{}
    foreach ($item in $items) {
        Assert-ExactObjectProperties $item @("scope_id","subject_path","signature_path") "external artifact signature"
        $scope=[string]$item.scope_id
        if (-not $expected.Contains($scope) -or $seenScopes.ContainsKey($scope) -or [string]$item.subject_path -cne [string]$expected[$scope]) { Stop-Launcher "EXTERNAL-ATTESTATION" "artifact signature subject/scope set mismatch" 6 }
        $seenScopes[$scope]=$true
        $subject=Resolve-RootRelativeFile $Root ([string]$item.subject_path) "$scope tracked artifact subject"; Assert-TrackedRepositoryFile $GitCommand $Root ([string]$item.subject_path) "$scope tracked artifact subject"
        $signatureRelative=[string]$item.signature_path
        if ($SeenPaths.ContainsKey($signatureRelative)) { Stop-Launcher "EXTERNAL-ATTESTATION" "artifact signature path duplicates another attestation" 6 }; $SeenPaths[$signatureRelative]=$true
        $signature=Resolve-ProtectedAttestationFile $AttestationRoot $signatureRelative "$scope external signature"
        $subjectSha256=(Get-FileHash -LiteralPath $subject -Algorithm SHA256).Hash.ToLowerInvariant()
        $signatureSha256=(Get-FileHash -LiteralPath $signature -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-DetachedSignature $GpgCommand $signature $subject $ExpectedFingerprint "$scope artifact"
        Assert-ProtectedRootPathChain $signature $AttestationRoot "EXTERNAL-ATTESTATION" "$scope external signature post-use"
        if ((Get-FileHash -LiteralPath $subject -Algorithm SHA256).Hash.ToLowerInvariant() -cne $subjectSha256 -or (Get-FileHash -LiteralPath $signature -Algorithm SHA256).Hash.ToLowerInvariant() -cne $signatureSha256) { Stop-Launcher "EXTERNAL-ATTESTATION" "$scope subject/signature bytes changed while being verified" 6 }
    }
}

function Assert-ExactEvidencePackage($Result, $Identity, $Registry, $Baseline, [string]$Root, [string]$GitCommand) {
    $index=$Identity.evidence_index
    Assert-ExactObjectProperties $index @("schema_version","release","source_commit","generated_at_utc","overall_status","evidence") "evidence index"
    if ([string]$index.schema_version -cne "evidence-index.v1" -or [string]$index.release -cne [string]$Result.release_id -or [string]$index.source_commit -cne [string]$Identity.implementation_commit -or @("PASS","REQUIRES_ACCEPTANCE_DATA") -cnotcontains [string]$index.overall_status) { Stop-Launcher "POST-EVIDENCE" "evidence index identity/status mismatch" 6 }
    $sEpochResult=SafeGit $GitCommand @("-C",$Root,"show","-s","--format=%ct",[string]$Identity.implementation_commit); Native-OK $sEpochResult "POST-EVIDENCE" "S commit time"
    $sTime=[DateTimeOffset]::FromUnixTimeSeconds([int64]$sEpochResult.Text); $now=[DateTimeOffset]::UtcNow
    $generated=ConvertFrom-RequiredUtc ([string]$index.generated_at_utc) "evidence index generated_at_utc"
    if ($generated -lt $sTime -or $generated -gt $now.AddMinutes(5)) { Stop-Launcher "POST-EVIDENCE" "evidence index time is outside S..verification window" 6 }
    $registryByEvidence=@{}; $expectedObservation=@(); $gateToKpis=@{}
    foreach ($gate in @($Baseline.release_gates)) { $gateToKpis[[string]$gate.id]=@($gate.kpi_ids) }
    foreach ($test in @($Registry.tests)) {
        $id=[string]$test.evidence_id
        if ([string]::IsNullOrWhiteSpace($id) -or $registryByEvidence.ContainsKey($id)) { Stop-Launcher "POST-EVIDENCE" "trusted registry evidence IDs must be unique" 6 }
        $registryByEvidence[$id]=$test
        $expectedKpis=@($test.gate_ids | ForEach-Object { @($gateToKpis[[string]$_]) } | Sort-Object -Unique)
        $expectedObservation += [pscustomobject]@{evidence_id=$id;test_id=[string]$test.test_id;gate_ids=@($test.gate_ids);kpi_ids=$expectedKpis;command_ids=@([string]$test.command_contract_id)}
    }
    $records=@($index.evidence); $recordByEvidence=@{}; $actualObservation=@(); $pathToRecord=@{}
    foreach ($record in $records) {
        Assert-ExactObjectProperties $record @("evidence_id","requirement_ids","test_ids","gate_ids","status","freshness","artifact_path","artifact_sha256","source_commit","executed_at_utc","expires_at_utc","owner_ids","candidate_bound","dependency_fingerprint") "evidence record"
        $id=[string]$record.evidence_id; $relative=[string]$record.artifact_path
        if (-not $registryByEvidence.ContainsKey($id) -or $recordByEvidence.ContainsKey($id) -or $pathToRecord.ContainsKey($relative)) { Stop-Launcher "POST-EVIDENCE" "evidence ID/path is missing, duplicate, or unregistered" 6 }
        $test=$registryByEvidence[$id]; $recordByEvidence[$id]=$record; $pathToRecord[$relative]=$record
        Assert-ExactStringArray $record.requirement_ids $test.requirement_ids "$id requirement_ids"; Assert-ExactStringArray $record.test_ids @([string]$test.test_id) "$id test_ids"; Assert-ExactStringArray $record.gate_ids $test.gate_ids "$id gate_ids"; Assert-ExactStringArray $record.owner_ids $test.owner_ids "$id owner_ids"
        if ($record.candidate_bound -ne $true -or [string]$record.dependency_fingerprint -cne [string]$test.semantic_case_sha256 -or [string]$record.source_commit -cne [string]$Identity.implementation_commit -or [string]$record.freshness -cne "FRESH" -or @("PASS","REQUIRES_ACCEPTANCE_DATA") -cnotcontains [string]$record.status) { Stop-Launcher "POST-EVIDENCE" "evidence candidate/dependency/status/freshness binding mismatch: $id" 6 }
        $executed=ConvertFrom-RequiredUtc ([string]$record.executed_at_utc) "$id executed_at_utc"; $expires=ConvertFrom-RequiredUtc ([string]$record.expires_at_utc) "$id expires_at_utc"
        if ($executed -lt $sTime -or $executed -gt $generated -or $expires -le $now -or $expires -le $executed -or $expires -gt $executed.AddHours($EvidenceFreshnessWindowHours)) { Stop-Launcher "POST-EVIDENCE" "evidence time/freshness window mismatch: $id" 6 }
        $path=Resolve-RootRelativeFile $Root $relative "evidence artifact"; Assert-TrackedRepositoryFile $GitCommand $Root $relative "evidence artifact"
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne ([string]$record.artifact_sha256).ToLowerInvariant()) { Stop-Launcher "POST-EVIDENCE" "evidence artifact digest mismatch: $id" 6 }
        $expectedKpis=@($test.gate_ids | ForEach-Object { @($gateToKpis[[string]$_]) } | Sort-Object -Unique)
        $actualObservation += [pscustomobject]@{evidence_id=$id;test_id=[string]$record.test_ids[0];gate_ids=@($record.gate_ids);kpi_ids=$expectedKpis;command_ids=@([string]$test.command_contract_id)}
    }
    Assert-EvidenceBindingObservation ([pscustomobject]@{registry=$expectedObservation;records=$actualObservation})

    # Consumers are closed: each gate/KPI/command references exactly the
    # registry-derived evidence set and every reference status matches its record.
    foreach ($gate in @($Result.gates.PSObject.Properties)) {
        $expectedPaths=@($Registry.tests | Where-Object { @($_.gate_ids) -ccontains [string]$gate.Name } | ForEach-Object { [string]$recordByEvidence[[string]$_.evidence_id].artifact_path } | Sort-Object -Unique)
        $actualPaths=@($gate.Value.evidence_paths | Sort-Object -Unique)
        if (-not (Test-ExactOrdinalArray $actualPaths $expectedPaths)) { Stop-Launcher "POST-EVIDENCE" "gate evidence consumer set mismatch: $($gate.Name)" 6 }
    }
    foreach ($kpi in @($Result.kpi_results.PSObject.Properties)) {
        $gateIds=@($Baseline.release_gates | Where-Object { @($_.kpi_ids) -ccontains [string]$kpi.Name } | ForEach-Object { [string]$_.id })
        $expectedPaths=@($Registry.tests | Where-Object { $testGates=@($_.gate_ids); @($gateIds | Where-Object { $testGates -ccontains $_ }).Count -gt 0 } | ForEach-Object { [string]$recordByEvidence[[string]$_.evidence_id].artifact_path } | Sort-Object -Unique)
        $actualPaths=@($kpi.Value.evidence_paths | Sort-Object -Unique)
        if (-not (Test-ExactOrdinalArray $actualPaths $expectedPaths)) { Stop-Launcher "POST-EVIDENCE" "KPI evidence consumer set mismatch: $($kpi.Name)" 6 }
    }
    $commands=@($Result.verification_commands)
    if ($commands.Count -ne @($Registry.tests).Count) { Stop-Launcher "POST-EVIDENCE" "verification command set must be one-to-one with trusted registry tests" 6 }
    $seenCommandEvidence=@{}
    foreach ($command in $commands) {
        $path=[string]$command.evidence_path
        if (-not $pathToRecord.ContainsKey($path) -or $seenCommandEvidence.ContainsKey($path)) { Stop-Launcher "POST-EVIDENCE" "verification command evidence path must be unique and registered" 6 }
        $seenCommandEvidence[$path]=$true; $record=$pathToRecord[$path]; $test=$registryByEvidence[[string]$record.evidence_id]
        if ([string]$command.command -cne (@($test.command) -join ' ') -or [string]$command.status -cne [string]$record.status) { Stop-Launcher "POST-EVIDENCE" "verification command bytes/status differ from trusted registry: $($record.evidence_id)" 6 }
    }
    Write-Pass "POST-EVIDENCE exact registry set, hashes, freshness, and consumers"
}

function Assert-TrackedReleaseArtifacts($Identity, [string]$ReleaseId, $Baseline, [string]$BaselineHash, $Inventory, [string]$Root, [string]$GitCommand, [string]$ExpectedSignerFingerprint) {
    $sEpochResult=SafeGit $GitCommand @("-C",$Root,"show","-s","--format=%ct",[string]$Identity.implementation_commit); Native-OK $sEpochResult "POST-ARTIFACT" "S commit epoch"
    $sEpoch=[int64]$sEpochResult.Text
    $releasePaths=[pscustomobject]@{manifest_path="docs/releases/ai-training-platform/$ReleaseId/artifact-manifest.json";checksums_path="docs/releases/ai-training-platform/$ReleaseId/SHA256SUMS.txt"}
    $distributionPaths=[pscustomobject]@{manifest_path="dist/docs/$ReleaseId/artifact-manifest.json";checksums_path="dist/docs/$ReleaseId/SHA256SUMS.txt"}
    $artifactState="NOT_READY"
    $releaseHash=Assert-ArtifactManifestAndChecksums $releasePaths "RELEASE" "docs/releases/ai-training-platform/$ReleaseId" ([string]$Identity.implementation_commit) $Identity.tree $sEpoch $ReleaseId $artifactState $Root $GitCommand $Baseline $BaselineHash $ExpectedSignerFingerprint
    [void](Assert-ArtifactManifestAndChecksums $distributionPaths "DISTRIBUTION" "dist/docs/$ReleaseId" ([string]$Identity.implementation_commit) $Identity.tree $sEpoch $ReleaseId $artifactState $Root $GitCommand $Baseline $BaselineHash $ExpectedSignerFingerprint $releaseHash)
    Write-Pass "POST-ARTIFACT tracked manifests/checksums bind S without tracked signatures"
}

function Assert-ReleaseDocuments($Result, $Inventory, [string]$Root, [string]$GitCommand) {
    $expected=@(Get-FinalDocumentInventoryPaths $Inventory ([string]$Result.release_id) | Sort-Object -Unique)
    $reported=@($Result.generated_documents | Sort-Object -Unique)
    if (-not (Test-ExactOrdinalArray $reported $expected)) { Stop-Launcher "POST-DOCS" "generated_documents must equal the normative final document inventory" 6 }
    foreach ($relative in $expected) { $path=Resolve-RootRelativeFile $Root $relative "final document"; Assert-TrackedRepositoryFile $GitCommand $Root $relative "final document"; [void](Assert-BoundedFile $path $MaxWorktreeFileBytes "POST-DOCS" "final document") }
    Write-Pass "POST-DOCS exact final document inventory"
}

function Invoke-ReadOnlyReleaseVerification([string]$SelectedMode, [string]$BundlePath, [string]$Root, [string]$AttestationRoot, [string]$TrustPath, $ExpectedProtectedTrustRoots, [string]$GitCommand, [string]$GhCommand, [string]$GpgCommand, [string]$TrustedPowerShellCommand, [byte[]]$TrustedValidatorBytes, $TrustedWorkflowByCheck, $AllowedActors, $TrustedFingerprints, $TrustedToolInventory, $ReleaseTrustTools, $ExpectedGitControlPlane, $ExpectedGitReferences, $Baseline, [string]$BaselineHash, $Inventory, $Registry) {
    if ([string]::IsNullOrWhiteSpace($BundlePath)) { Stop-Launcher "EXTERNAL-ATTESTATION" "$SelectedMode requires -AttestationBundlePath" 6 }
    $literal=[IO.Path]::GetFullPath($BundlePath)
    if (-not $literal.StartsWith($AttestationRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { Stop-Launcher "EXTERNAL-ATTESTATION" "bundle must be under protected attestation root" 6 }
    Assert-NoReparseComponent $literal "EXTERNAL-ATTESTATION"; Assert-ProtectedPathAcl $literal "EXTERNAL-ATTESTATION" "attestation bundle"; Assert-ProtectedRootPathChain $literal $AttestationRoot "EXTERNAL-ATTESTATION" "attestation bundle"
    $bundleSha256=(Get-FileHash -LiteralPath $literal -Algorithm SHA256).Hash.ToLowerInvariant()
    $bundle=ConvertFrom-StrictJsonFile $literal "external attestation bundle"
    Assert-ExactObjectProperties $bundle @("schema_version","release_id","repository","baseline_commit","implementation_commit","release_snapshot_commit","candidate_result_path","candidate_result_sha256","technical_approvals","artifact_signatures","acceptance_approval") "external attestation bundle"
    if ([string]$bundle.schema_version -cne "release-attestation-bundle.v2" -or [string]$bundle.repository -cne $ExpectedRepo -or [string]$bundle.candidate_result_sha256 -notmatch '^[0-9a-f]{64}$') { Stop-Launcher "EXTERNAL-ATTESTATION" "bundle identity/result digest mismatch" 6 }
    $readOnlyExclusion=".artifacts/codex/00000000T000000Z-00000000"
    Assert-GitControlPlaneSnapshot $ExpectedGitControlPlane
    $refsBefore=Get-GitReferenceSnapshot ([string]$ExpectedGitReferences.git_dir) ([string]$ExpectedGitReferences.common_dir)
    if (-not (Compare-GitReferenceSnapshot $ExpectedGitReferences $refsBefore)) { Stop-Launcher "READ-ONLY" "$SelectedMode Git refs/tags/packed-refs differ from the preflight snapshot" 6 }
    $before=Get-WorktreeSnapshot $GitCommand $Root $readOnlyExclusion
    $identity=Get-ReleaseCandidateIdentity $GitCommand $Root ([string]$bundle.baseline_commit) ([string]$bundle.release_id) $Inventory ([string]$bundle.implementation_commit) ([string]$bundle.release_snapshot_commit)
    $resultPath=Resolve-ProtectedAttestationFile $AttestationRoot ([string]$bundle.candidate_result_path) "external candidate result"
    if ((Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$bundle.candidate_result_sha256) { Stop-Launcher "EXTERNAL-ATTESTATION" "candidate result digest differs from bundle" 6 }
    $validator=Invoke-TrustedValidatorProcess -PowerShellCommand $TrustedPowerShellCommand -TrustedValidatorBytes $TrustedValidatorBytes -ResultPath $resultPath -ExpectedReleaseId ([string]$bundle.release_id) -ProjectRoot $Root
    if ($validator.ExitCode -ne 5 -or $validator.Text -notmatch 'REVIEW_PENDING') { Stop-Launcher "EXTERNAL-ATTESTATION" "external candidate result does not validate as unsigned review-pending" 6 }
    $result=ConvertFrom-StrictJsonFile $resultPath "external unsigned candidate result"
    $resultSha256=(Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$result.release_state -cne "NOT_READY" -or [string]$result.candidate_phase -cne "UNSIGNED_CANDIDATE / REVIEW PENDING" -or [string]$result.repository.implementation_commit -cne [string]$identity.implementation_commit -or [string]$result.repository.release_snapshot_commit -cne [string]$identity.release_snapshot_commit -or [string]$result.repository.implementation_tree -cne [string]$identity.tree.tree_object -or [string]$result.repository.implementation_tree_sha256 -cne [string]$identity.tree.source_tree_sha256) { Stop-Launcher "POST-IDENTITY" "external unsigned result does not bind exact S/R/tree" 6 }
    $ci=Get-AndAssertGitHubCandidateFacts $GhCommand ([string]$identity.release_snapshot_commit) $TrustedWorkflowByCheck $AllowedActors
    if ([string]$result.repository.pull_request_url -cne [string]$ci.pull_request.html_url) { Stop-Launcher "POST-CI" "tracked result PR differs from independent exact PR" 6 }
    Assert-ExactEvidencePackage $result $identity $Registry $Baseline $Root $GitCommand
    Assert-TrackedReleaseArtifacts $identity ([string]$bundle.release_id) $Baseline $BaselineHash $Inventory $Root $GitCommand ([string]$TrustedFingerprints["OWN-QA"])
    Assert-ReleaseDocuments $result $Inventory $Root $GitCommand
    $scopeByOwner=[ordered]@{"OWN-ARCH"="ARCHITECTURE";"OWN-UX"="UX-ACCESSIBILITY";"OWN-AI"="AI";"OWN-DOC"="DOCUMENT-AI";"OWN-SEC"="SECURITY-PRIVACY";"OWN-OPS"="OPERATIONS";"OWN-QA"="QUALITY"}
    $approvals=@($bundle.technical_approvals); if ($approvals.Count -ne 7) { Stop-Launcher "EXTERNAL-ATTESTATION" "exactly seven technical approvals are required" 6 }
    $approvalByOwner=@{}; foreach ($approval in $approvals) { $owner=[string]$approval.owner_id; if ($approvalByOwner.ContainsKey($owner)) { Stop-Launcher "EXTERNAL-ATTESTATION" "duplicate technical owner" 6 }; $approvalByOwner[$owner]=$approval }
    $seenPaths=@{}
    foreach ($owner in $scopeByOwner.Keys) { if (-not $approvalByOwner.ContainsKey($owner)) { Stop-Launcher "EXTERNAL-ATTESTATION" "missing technical approval: $owner" 6 }; Assert-ExternalApproval $approvalByOwner[$owner] $owner $scopeByOwner[$owner] "APPROVED" ([string]$bundle.release_id) ([string]$identity.implementation_commit) ([string]$identity.release_snapshot_commit) ([string]$bundle.candidate_result_sha256) $AttestationRoot $GpgCommand ([string]$TrustedFingerprints[$owner]) $seenPaths }
    Assert-ExternalArtifactSignatures $bundle.artifact_signatures ([string]$bundle.release_id) $Root $AttestationRoot $GitCommand $GpgCommand ([string]$TrustedFingerprints["OWN-QA"]) $seenPaths
    $localTag=SafeGit $GitCommand @("-C",$Root,"show-ref","--verify","--quiet","refs/tags/$([string]$bundle.release_id)")
    $remoteTag=Get-GitHubApiResponseWithStatus $GhCommand "repos/$ExpectedRepo/git/ref/tags/$([string]$bundle.release_id)" "remote release tag lookup"
    if ($SelectedMode -ceq "VerifyCandidate") {
        Assert-RemoteTagLookupObservation ([pscustomobject]@{expectation="ABSENT";exit_code=[int]$remoteTag.ExitCode;http_status=[int]$remoteTag.StatusCode})
        if ($null -ne $bundle.acceptance_approval -or $localTag.ExitCode -ne 1) { Stop-Launcher "EXTERNAL-ATTESTATION" "candidate verification requires no acceptance signature and no local/remote tag" 6 }
        Assert-ReleaseStateTransition ([pscustomobject]@{mode=$SelectedMode;release_state="CODE_COMPLETE / ACCEPTANCE DATA PENDING";technical_signatures=7;acceptance_signature=$false;signed_tag=$false})
        $finalState="CODE_COMPLETE / ACCEPTANCE DATA PENDING"
    } else {
        Assert-RemoteTagLookupObservation ([pscustomobject]@{expectation="PRESENT";exit_code=[int]$remoteTag.ExitCode;http_status=[int]$remoteTag.StatusCode})
        if ($null -eq $bundle.acceptance_approval -or $localTag.ExitCode -ne 0) { Stop-Launcher "EXTERNAL-ATTESTATION" "accepted verification requires external OWN-ACC approval and local annotated tag" 6 }
        Assert-ExternalApproval $bundle.acceptance_approval "OWN-ACC" "FINAL-ACCEPTANCE" "ACCEPTED" ([string]$bundle.release_id) ([string]$identity.implementation_commit) ([string]$identity.release_snapshot_commit) ([string]$bundle.candidate_result_sha256) $AttestationRoot $GpgCommand ([string]$TrustedFingerprints["OWN-ACC"]) $seenPaths
        $tagRef=SafeGit $GitCommand @("-C",$Root,"for-each-ref","--format=%(objecttype)%09%(objectname)","refs/tags/$([string]$bundle.release_id)"); Native-OK $tagRef "POST-TAG" "local annotated tag"
        $parts=@($tagRef.Text -split "`t"); if ($parts.Count -ne 2 -or $parts[0] -cne "tag") { Stop-Launcher "POST-TAG" "release tag must be annotated" 6 }
        $peeled=SafeGit $GitCommand @("-C",$Root,"rev-parse","$([string]$bundle.release_id)^{}"); Native-OK $peeled "POST-TAG" "tag target"
        if ($peeled.Text -cne [string]$identity.release_snapshot_commit) { Stop-Launcher "POST-TAG" "tag target differs from R" 6 }
        $gpgProgram=Get-GitGpgProgramSpec $GpgCommand $ProtectedGpgHome
        $tagGpgSnapshot=Get-ProtectedRootSnapshot $ProtectedGpgHome $ProtectedGpgHome "PRE-TAG-GPG" "protected GnuPG home"
        $tagVerification=SafeGit $GitCommand @("-c","gpg.format=openpgp","-c","gpg.program=$gpgProgram","-C",$Root,"verify-tag","--raw",[string]$bundle.release_id)
        Assert-ProtectedGpgHomeUnchanged $tagGpgSnapshot $ProtectedGpgHome "POST-TAG-GPG"
        Native-OK $tagVerification "POST-TAG" "signed annotated tag"
        [void](Assert-ValidSignaturePolicy $tagVerification.Text ([string]$TrustedFingerprints["OWN-QA"]) "annotated tag")
        $remoteObject=ConvertFrom-StrictJsonText $remoteTag.Body "remote tag ref"
        if ([string]$remoteObject.ref -cne "refs/tags/$([string]$bundle.release_id)" -or [string]$remoteObject.object.type -cne "tag" -or [string]$remoteObject.object.sha -cne $parts[1]) { Stop-Launcher "POST-TAG" "remote annotated tag object mismatch" 6 }
        $remoteTagObjectResponse=Native-ReadOnly $GhCommand @("api","--method","GET","-H","Accept: application/vnd.github+json","repos/$ExpectedRepo/git/tags/$([string]$remoteObject.object.sha)"); Native-OK $remoteTagObjectResponse "POST-TAG" "remote tag object"
        $remoteTagObject=ConvertFrom-StrictJsonText $remoteTagObjectResponse.Text "remote tag object"
        if ([string]$remoteTagObject.object.type -cne "commit" -or [string]$remoteTagObject.object.sha -cne [string]$identity.release_snapshot_commit -or $remoteTagObject.verification.verified -ne $true) { Stop-Launcher "POST-TAG" "remote tag target/signature verification mismatch" 6 }
        Assert-ReleaseStateTransition ([pscustomobject]@{mode=$SelectedMode;release_state="ACCEPTED";technical_signatures=7;acceptance_signature=$true;signed_tag=$true})
        $finalState="ACCEPTED"
    }
    Assert-TrustedExecutableInventoryUnchanged $TrustedToolInventory $ReleaseTrustTools $Root
    Assert-ProtectedRootPathChain $literal $AttestationRoot "EXTERNAL-ATTESTATION" "attestation bundle post-use"
    Assert-ProtectedRootPathChain $resultPath $AttestationRoot "EXTERNAL-ATTESTATION" "candidate result post-use"
    if ((Get-FileHash -LiteralPath $literal -Algorithm SHA256).Hash.ToLowerInvariant() -cne $bundleSha256 -or (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $resultSha256) { Stop-Launcher "EXTERNAL-ATTESTATION" "bundle or candidate result changed while being verified" 6 }
    Assert-ProtectedTrustRootsUnchanged $ExpectedProtectedTrustRoots $TrustPath $ProtectedHooksPath $ProtectedGpgHome $AttestationRoot
    $after=Get-WorktreeSnapshot $GitCommand $Root $readOnlyExclusion
    if ((Snapshot-Digest $before) -cne (Snapshot-Digest $after)) { Stop-Launcher "READ-ONLY" "$SelectedMode modified the repository worktree" 6 }
    Assert-GitControlPlaneSnapshot $ExpectedGitControlPlane
    $refsAfter=Get-GitReferenceSnapshot ([string]$ExpectedGitReferences.git_dir) ([string]$ExpectedGitReferences.common_dir)
    if (-not (Compare-GitReferenceSnapshot $refsBefore $refsAfter)) { Stop-Launcher "READ-ONLY" "$SelectedMode modified the index, HEAD, refs/heads, refs/tags, or packed-refs" 6 }
    Write-Pass "$SelectedMode external signatures, exact CI, and worktree/control-plane/ref read-only closure"
    Write-Host "RESULT: $finalState"; exit 0
}

function Invoke-PolicySelfTest([string]$FixturePath) {
    if ([string]::IsNullOrWhiteSpace($FixturePath) -or -not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) { Stop-Launcher "POLICY-FIXTURE" "PolicySelfTest requires an existing fixture file" 6 }
    $fixture = ConvertFrom-StrictJsonFile ([IO.Path]::GetFullPath($FixturePath)) "runner policy fixture"
    if ([string]$fixture.schema_version -cne "runner-policy-fixture.v1" -or $fixture.case -isnot [string]) { Stop-Launcher "POLICY-FIXTURE" "fixture identity is invalid" 6 }
    switch ([string]$fixture.case) {
        "release-identity" {
            Assert-ReleaseIdentityObservation $fixture
            Write-Host "PASS [POLICY-IDENTITY]: constructible S/R identity"; return
        }
        "trusted-tool" {
            Assert-TrustedToolObservation $fixture
            Write-Host "PASS [POLICY-TOOL]: trusted executable contract"; return
        }
        "protected-path-chain" {
            Assert-ProtectedPathChainObservation $fixture
            Write-Host "PASS [POLICY-PROTECTED-PATH]: protected root path chain"; return
        }
        "protected-root-snapshot" {
            Assert-ProtectedRootSnapshotObservation $fixture.expected $fixture.actual
            Write-Host "PASS [POLICY-PROTECTED-SNAPSHOT]: protected root byte/SDDL snapshot"; return
        }
        "host-invocation" {
            Assert-HostInvocationObservation $fixture
            Write-Host "PASS [POLICY-HOST]: canonical production host invocation"; return
        }
        "gpg-verification-configuration" {
            Assert-GpgVerificationConfigurationObservation $fixture
            Write-Host "PASS [POLICY-GPG]: exact read-only GnuPG verification configuration"; return
        }
        "ci-binding" {
            Assert-CiBindingObservation $fixture
            Write-Host "PASS [POLICY-CI]: exact PR/workflow/runner binding"; return
        }
        "evidence-binding" {
            Assert-EvidenceBindingObservation $fixture
            Write-Host "PASS [POLICY-EVIDENCE]: exact registry and consumers"; return
        }
        "resume-binding" {
            Assert-ResumeBindingObservation $fixture
            Write-Host "PASS [POLICY-RESUME]: exact resume identity"; return
        }
        "git-config-name" {
            if ((-not (Test-UnsafeGitConfigName ([string]$fixture.name))) -ne [bool]$fixture.should_be_safe) { Stop-Launcher "POLICY-GIT-CONFIG" "Git config classifier mismatch" 6 }
            Write-Host "PASS [POLICY-GIT-CONFIG]: sensitive Git config classified"; return
        }
        "state-transition" {
            Assert-ReleaseStateTransition $fixture
            Write-Host "PASS [POLICY-STATE]: mode/state boundary"; return
        }
        "remote-tag-lookup" {
            Assert-RemoteTagLookupObservation $fixture
            Write-Host "PASS [POLICY-TAG-LOOKUP]: exact authenticated tag HTTP status"; return
        }
        "job-isolation" {
            Assert-JobIsolationObservation $fixture
            Write-Host "PASS [POLICY-JOB]: explicit native isolation mode contract"; return
        }
        "windows-powershell-module-path" {
            Assert-WindowsPowerShellModulePathObservation $fixture
            Write-Host "PASS [POLICY-MODULE-PATH]: Windows PowerShell 5.1 module path policy"; return
        }
        "git-config-isolation" {
            Assert-GitConfigIsolationObservation $fixture
            Write-Host "PASS [POLICY-GIT-CONFIG]: process-level system/global Git config isolation"; return
        }
        "stream-bounds" {
            Assert-StreamBoundsObservation $fixture
            Write-Host "PASS [POLICY-BOUNDS]: byte/time limits"; return
        }
        default { Stop-Launcher "POLICY-FIXTURE" "unknown policy fixture case" 6 }
    }
}

if ($Mode -ceq "PolicySelfTest") { Invoke-PolicySelfTest $PolicyFixture; exit 0 }

$guardedReleaseId = $null
if ($Mode -ceq "Implement") {
    $guardedReleaseId = Assert-GuardedReleaseId $ReleaseId
    $script:ActiveReleaseId = $guardedReleaseId
}

Assert-CanonicalProductionHostInvocation $Mode $PSCommandPath
Initialize-WindowsPowerShellModulePath
$literalProjectRoot = $ProjectRoot.TrimEnd([char[]]@('\','/'))
if ($ProjectRoot.IndexOf(':', 2) -ge 0 -or $ProjectRoot -match '(^|[\\/])\.\.?(?:[\\/]|$)' -or -not [StringComparer]::OrdinalIgnoreCase.Equals($literalProjectRoot, $ExpectedRoot)) { Stop-Launcher "PRE-ROOT" "project root must be the literal canonical path '$ExpectedRoot' without ADS or dot segments" }
if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) { Stop-Launcher "PRE-ROOT" "target repository does not exist: $ProjectRoot" }
Assert-NoReparseComponent $ProjectRoot "PRE-ROOT"
$resolvedRoot = Canonical (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not [StringComparer]::OrdinalIgnoreCase.Equals($resolvedRoot, (Canonical $ExpectedRoot))) { Stop-Launcher "PRE-ROOT" "repository root must be exactly '$ExpectedRoot'" }
Assert-NoReparseComponent $resolvedRoot "PRE-ROOT"
Assert-NoExecutionEnvironmentOverrides
$strictUtf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
$literalTrustPath = $ReleaseTrustPath.TrimEnd([char[]]@('\','/'))
if ($ReleaseTrustPath.IndexOf(':', 2) -ge 0 -or $ReleaseTrustPath -match '(^|[\/])\.\.?(?:[\/]|$)' -or -not [StringComparer]::OrdinalIgnoreCase.Equals($literalTrustPath, $ExpectedReleaseTrustPath) -or -not (Test-Path -LiteralPath $ReleaseTrustPath -PathType Leaf)) { Stop-Launcher "PRE-TRUST" "release trust store must be the literal protected file '$ExpectedReleaseTrustPath'" }
Assert-NoReparseComponent $ReleaseTrustPath "PRE-TRUST"
$resolvedTrustPath = Canonical (Resolve-Path -LiteralPath $ReleaseTrustPath).Path
if ($resolvedTrustPath.StartsWith($resolvedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { Stop-Launcher "PRE-TRUST" "release trust store must be outside the Codex workspace" }
Assert-ProtectedRootPathChain $resolvedTrustPath (Split-Path -Parent $resolvedTrustPath) "PRE-TRUST" "release trust"
Assert-ReleaseTrustAcl $resolvedTrustPath
$releaseTrustBytes = [IO.File]::ReadAllBytes($resolvedTrustPath); $releaseTrustSha256 = Bytes-Sha256 $releaseTrustBytes
try { $releaseTrustText = $strictUtf8.GetString($releaseTrustBytes) } catch { Stop-Launcher "PRE-TRUST" "release trust must be strict UTF-8" }
$releaseTrust = ConvertFrom-StrictJsonText $releaseTrustText "release trust store"
Assert-ExactObjectProperties $releaseTrust @("schema_version", "repository", "attestation_root", "owner_fingerprints", "tag_signer_fingerprint", "trusted_tools", "github_policy") "release trust store"
if ([string]$releaseTrust.schema_version -cne "release-trust.v2" -or [string]$releaseTrust.repository -cne $ExpectedRepo -or [string]$releaseTrust.attestation_root -cne "C:\ProgramData\YOnLab\attestations") { Stop-Launcher "PRE-TRUST" "release trust v2 identity/attestation root mismatch" }
$resolvedAttestationRoot = [string]$releaseTrust.attestation_root
if (-not (Test-Path -LiteralPath $resolvedAttestationRoot -PathType Container)) { Stop-Launcher "PRE-TRUST" "protected external attestation root is not provisioned" }
Assert-NoReparseComponent $resolvedAttestationRoot "PRE-TRUST"; Assert-ProtectedPathAcl $resolvedAttestationRoot "PRE-TRUST" "attestation root"; Assert-ProtectedRootPathChain $resolvedAttestationRoot $resolvedAttestationRoot "PRE-TRUST" "attestation root"
$requiredTrustOwners = @("OWN-ARCH", "OWN-UX", "OWN-AI", "OWN-DOC", "OWN-SEC", "OWN-OPS", "OWN-QA", "OWN-ACC")
Assert-ExactObjectProperties $releaseTrust.owner_fingerprints $requiredTrustOwners "release trust store owner_fingerprints"
$trustedFingerprints = @{}
foreach ($owner in $requiredTrustOwners) { $fingerprint = ([string]$releaseTrust.owner_fingerprints.PSObject.Properties[$owner].Value).ToUpperInvariant(); if ($fingerprint -notmatch '^[0-9A-F]{40}([0-9A-F]{24})?$' -or $trustedFingerprints.Values -contains $fingerprint) { Stop-Launcher "PRE-TRUST" "owner fingerprints must be unique 40/64-hex values: $owner" }; $trustedFingerprints[$owner]=$fingerprint }
if (([string]$releaseTrust.tag_signer_fingerprint).ToUpperInvariant() -cne [string]$trustedFingerprints["OWN-QA"]) { Stop-Launcher "PRE-TRUST" "tag signer must be the trusted OWN-QA key" }
Assert-ExactObjectProperties $releaseTrust.github_policy @("allowed_actor_logins", "workflows") "release trust github_policy"
$allowedGithubActors = @($releaseTrust.github_policy.allowed_actor_logins)
if ($allowedGithubActors.Count -eq 0 -or @($allowedGithubActors | Where-Object { $_ -isnot [string] -or [string]$_ -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$' -or [string]$_ -like 'REPLACE_*' }).Count -gt 0 -or @($allowedGithubActors | Sort-Object -Unique).Count -ne $allowedGithubActors.Count) { Stop-Launcher "PRE-TRUST" "GitHub actor allowlist must contain unique concrete logins" }
$trustedWorkflowByCheck = @{}
foreach ($workflow in @($releaseTrust.github_policy.workflows)) {
    Assert-ExactObjectProperties $workflow @("check_name", "workflow_id", "workflow_path", "workflow_sha256", "required_runner_labels") "trusted workflow"
    $checkName=[string]$workflow.check_name
    if ($RequiredCiChecks -cnotcontains $checkName -or $trustedWorkflowByCheck.ContainsKey($checkName) -or [int64]$workflow.workflow_id -le 0 -or [string]$workflow.workflow_path -notmatch '^\.github/workflows/[A-Za-z0-9._/-]+\.ya?ml$' -or [string]$workflow.workflow_sha256 -notmatch '^[0-9a-f]{64}$' -or @($workflow.required_runner_labels).Count -eq 0) { Stop-Launcher "PRE-TRUST" "trusted workflow policy is invalid: $checkName" }
    $trustedWorkflowByCheck[$checkName]=$workflow
}
if ($trustedWorkflowByCheck.Count -ne $RequiredCiChecks.Count) { Stop-Launcher "PRE-TRUST" "trusted workflow check set must be exact" }
$trustedToolInventory = Get-TrustedExecutableInventory $releaseTrust.trusted_tools $resolvedRoot
$trustedPowerShellCommand = [string]$trustedToolInventory.powershell.path
$currentPowerShellCommand = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if (-not [StringComparer]::OrdinalIgnoreCase.Equals((Canonical $currentPowerShellCommand), (Canonical $trustedPowerShellCommand))) { Stop-Launcher "PRE-TOOL-TRUST" "runner must itself execute under the pinned protected PowerShell executable" }
$gitCommand=[string]$trustedToolInventory.git.path; $ghCommand=[string]$trustedToolInventory.gh.path; $dockerCommand=[string]$trustedToolInventory.docker.path; $codexCommand=[string]$trustedToolInventory.codex.path; $gpgCommand=[string]$trustedToolInventory.gpg.path
$script:GitHubCredentialHelper = Get-GitHubCredentialHelperSpec $ghCommand
Assert-ProtectedEmptyHooksDirectory $ProtectedHooksPath $resolvedRoot
Assert-NoExecutableGitConfiguration $gitCommand $resolvedRoot
$top = SafeGit $gitCommand @("-C", $resolvedRoot, "rev-parse", "--show-toplevel"); Native-OK $top "PRE-ROOT" "Git root"
if (-not [StringComparer]::OrdinalIgnoreCase.Equals((Canonical $top.Text), $resolvedRoot)) { Stop-Launcher "PRE-ROOT" "Git top level mismatch" }
$absoluteGitDir = SafeGit $gitCommand @("-C", $resolvedRoot, "rev-parse", "--absolute-git-dir"); Native-OK $absoluteGitDir "PRE-GIT-CONTROL" "absolute Git directory"
$commonGitDir = SafeGit $gitCommand @("-C", $resolvedRoot, "rev-parse", "--git-common-dir"); Native-OK $commonGitDir "PRE-GIT-CONTROL" "common Git directory"
$resolvedGitDir = Canonical $absoluteGitDir.Text
$resolvedCommonGitDir = $(if ([IO.Path]::IsPathRooted($commonGitDir.Text)) { Canonical $commonGitDir.Text } else { Canonical (Join-Path $resolvedRoot $commonGitDir.Text) })
$dotGitPath = Join-Path $resolvedRoot ".git"
foreach ($gitMetadataPath in @($resolvedGitDir, $resolvedCommonGitDir, $dotGitPath)) { Assert-NoReparseComponent $gitMetadataPath "PRE-GIT-CONTROL" }
$gitControlPlaneSnapshot = Get-GitControlPlaneSnapshot $resolvedGitDir $resolvedCommonGitDir $dotGitPath
$gitReferenceSnapshot = Get-GitReferenceSnapshot $resolvedGitDir $resolvedCommonGitDir
Assert-NoTrackedSubmoduleMetadata $gitCommand $resolvedRoot
$branch = SafeGit $gitCommand @("-C", $resolvedRoot, "rev-parse", "--abbrev-ref", "HEAD"); Native-OK $branch "PRE-BRANCH" "branch"
if ($branch.Text -cne $ExpectedBranch) { Stop-Launcher "PRE-BRANCH" "expected $ExpectedBranch; launcher never switches branches" }
$remote = SafeGit $gitCommand @("-C", $resolvedRoot, "remote", "get-url", "origin"); Native-OK $remote "PRE-REMOTE" "origin"
if ($remote.Text -cne $ExpectedRemote) { Stop-Launcher "PRE-REMOTE" "origin mismatch" }
$preUpstream = SafeGit $gitCommand @("-C", $resolvedRoot, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"); Native-OK $preUpstream "PRE-UPSTREAM" "upstream"
if ($preUpstream.Text -cne "origin/$ExpectedBranch") { Stop-Launcher "PRE-UPSTREAM" "exact upstream origin/$ExpectedBranch is required before Codex; the runner never uses push -u" }
$preSync = SafeGit $gitCommand @("-C", $resolvedRoot, "rev-list", "--left-right", "--count", "HEAD...@{u}"); Native-OK $preSync "PRE-UPSTREAM" "upstream synchronization"
if ($preSync.Text -notmatch '^0\s+0$') { Stop-Launcher "PRE-UPSTREAM" "initial branch must be exactly synchronized with its existing upstream" }
$worktree = SafeGit $gitCommand @("-C", $resolvedRoot, "status", "--porcelain=v1", "--untracked-files=normal"); Native-OK $worktree "PRE-CLEAN" "worktree"
if ([string]::IsNullOrWhiteSpace($ResumeRun) -and -not [string]::IsNullOrWhiteSpace($worktree.Text)) { Stop-Launcher "PRE-CLEAN" "initial run requires clean worktree:`n$($worktree.Text)" }
Write-Pass "PRE-ROOT/PRE-BRANCH/PRE-REMOTE/PRE-CLEAN repository identity"

$required = @(
    "README.md", "design-baseline.json", "codex-output.schema.json", "codex-final-result.schema.json",
    "document-graph.schema.json", "artifact-manifest.schema.json", "evidence-index.schema.json",
    "ai-gateway-request.schema.json", "hwp-conversion-boundary-contract.json", "entity-catalog.json", "diagnosis-scoring-golden-vectors.json",
    "requirements-test-registry.json", "screen-route-contracts.json", "final-document-inventory.json",
    "release-trust.example.json",
    "verify-machine-contracts.py", "test-machine-contracts.sh",
    "fixtures/ai-gateway-request.valid.json", "fixtures/ai-gateway-request.invalid.json",
    "fixtures/artifact-manifest.valid.json", "fixtures/artifact-manifest.invalid-duplicate-path.json", "fixtures/artifact-manifest.invalid-source-path.json",
    "fixtures/document-graph.valid.json", "fixtures/document-graph.invalid-topology.json", "fixtures/document-graph.invalid-uuid.json", "fixtures/document-graph.invalid-range.json",
    "fixtures/document-graph.invalid-cell-gap.json", "fixtures/document-graph.invalid-cell-overlap.json", "fixtures/document-graph.invalid-nested-cycle.json", "fixtures/document-graph.invalid-nested-dangling.json",
    "fixtures/evidence-index.valid.json", "fixtures/evidence-index.invalid.json",
    "00-source-decision-baseline.md", "01-requirements-traceability.md", "02-functional-screen-design.md", "03-system-architecture-cdd-cdr.md",
    "04-ai-diagnosis-persona-recommendation.md", "05-document-ai-hwp-rag.md", "06-ai-gateway-model-selection.md", "07-data-api-interface-design.md",
    "08-security-privacy-operations.md", "09-test-procedure-acceptance.md", "10-delivery-implementation-plan.md", "11-codex-one-shot-implementation-prompt.md",
    "12-ui-ux-visual-system.md", "13-one-command-execution.md", "14-final-document-deliverables.md", "15-normative-policy-and-interface-contracts.md"
)
foreach ($name in $required) { $path = Join-Path $resolvedRoot (Join-Path $PlanningRelative $name); if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Launcher "PRE-DESIGN" "missing $name" }; Assert-NoReparseComponent $path "PRE-DESIGN" }
$baselinePath = Join-Path $resolvedRoot $BaselineRelative; $promptPath = Join-Path $resolvedRoot $PromptRelative; $outputSchemaPath = Join-Path $resolvedRoot $OutputSchemaRelative; $strictSchemaPath = Join-Path $resolvedRoot $StrictSchemaRelative; $contractPath = Join-Path $resolvedRoot $DeliverableContractRelative; $inventoryPath = Join-Path $resolvedRoot $FinalDocumentInventoryRelative; $validatorPath = Join-Path $resolvedRoot $ValidatorRelative; $requirementsRegistryPath = Join-Path $resolvedRoot (Join-Path $PlanningRelative "requirements-test-registry.json")
foreach ($path in @($baselinePath, $promptPath, $outputSchemaPath, $strictSchemaPath, $contractPath, $inventoryPath, $validatorPath, $requirementsRegistryPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Launcher "PRE-DESIGN" "missing runtime input: $path" }; Assert-NoReparseComponent $path "PRE-DESIGN" }
$trackedPlanningResult = SafeGit $gitCommand @("-C", $resolvedRoot, "ls-files", "--", "$PlanningRelative/*"); Native-OK $trackedPlanningResult "PRE-DESIGN" "tracked planning inventory"
$trustedRelativePaths = @($trackedPlanningResult.Text -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) + @($ValidatorRelative, "scripts/invoke-ai-training-platform-v1.ps1")
$trustedRelativePaths = @($trustedRelativePaths | Select-Object -Unique)
[Array]::Sort($trustedRelativePaths, [StringComparer]::Ordinal)
$trustedInputHashes = Get-TrustedInputHashes $resolvedRoot $trustedRelativePaths
$trustedValidatorBytes = [IO.File]::ReadAllBytes($validatorPath)
$trustedValidatorSha256 = Bytes-Sha256 $trustedValidatorBytes
if ($trustedInputHashes[$ValidatorRelative] -cne $trustedValidatorSha256) { Stop-Launcher "PRE-DESIGN" "trusted validator byte/hash mismatch" }
$baseline = ConvertFrom-StrictJsonFile $baselinePath "design baseline"
if ($baseline.baseline_id -cne "YONLAB-AI-TRAINING-PLATFORM-DESIGN-v1.1" -or $baseline.repository.windows_root -cne $ExpectedRoot -or $baseline.repository.remote -cne $ExpectedRemote -or $baseline.repository.work_branch -cne $ExpectedBranch) { Stop-Launcher "PRE-DESIGN" "baseline identity mismatch" }
$trustedInventory = ConvertFrom-StrictJsonFile $inventoryPath "final document inventory"
$trustedRequirementsRegistry = ConvertFrom-StrictJsonFile $requirementsRegistryPath "requirements/test registry"
$resolvedGpgHome = Assert-ProtectedPublicOnlyGpgHome $ProtectedGpgHome $resolvedRoot
$protectedTrustRootsSnapshot=Get-ProtectedTrustRootsSnapshot $resolvedTrustPath $ProtectedHooksPath $resolvedGpgHome $resolvedAttestationRoot
$ignored = SafeGit $gitCommand @("-C", $resolvedRoot, "check-ignore", "-q", "--no-index", "$ArtifactRelative/.probe"); if ($ignored.ExitCode -ne 0) { Stop-Launcher "PRE-ARTIFACT" ".artifacts must be ignored" }

$codexVersion=$null; $codexHelpDigest=$null; $dockerServer=$null; $composeVersion=$null
if ($Mode -ceq "Implement") {
    $codexVersion = Native-ReadOnly $codexCommand @("--version"); Native-OK $codexVersion "PRE-CODEX" "Codex version"
    $codexLogin = Native-ReadOnly $codexCommand @("login", "status"); Native-OK $codexLogin "PRE-CODEX" "Codex login"
    $codexGlobalHelp = Native-ReadOnly $codexCommand @("--help"); $codexExecHelp = Native-ReadOnly $codexCommand @("exec", "--help"); $codexResumeHelp = Native-ReadOnly $codexCommand @("exec", "resume", "--help")
    foreach ($probe in @($codexGlobalHelp, $codexExecHelp, $codexResumeHelp)) { Native-OK $probe "PRE-CODEX" "Codex CLI feature help" }
    foreach ($token in @("--ask-for-approval", "--sandbox", "--cd")) { if (-not $codexGlobalHelp.Text.Contains($token)) { Stop-Launcher "PRE-CODEX" "global CLI feature missing: $token" } }
    foreach ($token in @("--json", "--output-schema", "--output-last-message", "--ignore-user-config", "--ignore-rules", "--strict-config")) { if (-not $codexExecHelp.Text.Contains($token) -or -not $codexResumeHelp.Text.Contains($token)) { Stop-Launcher "PRE-CODEX" "exec/resume feature missing: $token" } }
    if (-not $codexResumeHelp.Text.Contains("SESSION_ID")) { Stop-Launcher "PRE-CODEX" "resume SESSION_ID contract missing" }
    $codexHelpDigest = String-Sha256 ($codexGlobalHelp.Text + "`n---exec---`n" + $codexExecHelp.Text + "`n---resume---`n" + $codexResumeHelp.Text)
    $dockerServer = Native-ReadOnly $dockerCommand @("version", "--format", "{{.Server.Version}}"); Native-OK $dockerServer "PRE-DOCKER" "Docker"
    $composeVersion = Native-ReadOnly $dockerCommand @("compose", "version", "--short"); Native-OK $composeVersion "PRE-DOCKER" "Compose"
}
$ghAuth = Native-ReadOnly $ghCommand @("auth", "status"); Native-OK $ghAuth "PRE-GH" "gh auth status"
$ghActorResponse = Native-ReadOnly $ghCommand @("api", "--method", "GET", "-H", "Accept: application/vnd.github+json", "user"); Native-OK $ghActorResponse "PRE-GH" "authenticated GitHub actor"
$ghActor = ConvertFrom-StrictJsonText $ghActorResponse.Text "GitHub actor response"
if ($allowedGithubActors -cnotcontains [string]$ghActor.login) { Stop-Launcher "PRE-GH" "authenticated GitHub actor is not in protected allowlist" }
$gpgVersion = TrustedGpg $gpgCommand @("--version"); Native-OK $gpgVersion "PRE-TRUST" "GnuPG detached-signature verifier"
$gpgKeyInventory = TrustedGpg $gpgCommand @("--with-colons", "--fingerprint", "--list-keys"); Native-OK $gpgKeyInventory "PRE-TRUST" "protected GnuPG key inventory"
$gpgSecretInventory = TrustedGpg $gpgCommand @("--with-colons", "--list-secret-keys"); Native-OK $gpgSecretInventory "PRE-TRUST" "protected GnuPG secret-key absence"
if (@($gpgSecretInventory.Text -split "`n" | Where-Object { $_.StartsWith("sec:", [StringComparison]::Ordinal) }).Count -ne 0) { Stop-Launcher "PRE-TRUST" "verification-only protected GnuPG home must not contain secret keys" }
$availableGpgFingerprints = @($gpgKeyInventory.Text -split "`n" | Where-Object { $_.StartsWith("fpr:", [StringComparison]::Ordinal) } | ForEach-Object { $fields = $_ -split ':'; if ($fields.Count -gt 9) { $fields[9].ToUpperInvariant() } } | Where-Object { $_ } | Sort-Object -Unique)
foreach ($fingerprint in $trustedFingerprints.Values) { if ($availableGpgFingerprints -cnotcontains ([string]$fingerprint).ToUpperInvariant()) { Stop-Launcher "PRE-TRUST" "protected keyring lacks trusted signer fingerprint: $fingerprint" } }
$ghRepo = Native-ReadOnly $ghCommand @("repo", "view", $ExpectedRepo, "--json", "nameWithOwner"); Native-OK $ghRepo "PRE-GH" "gh repo view"
if (((ConvertFrom-StrictJsonText $ghRepo.Text "gh repo response").nameWithOwner) -cne $ExpectedRepo) { Stop-Launcher "PRE-GH" "GitHub repository mismatch" }
foreach ($trustedWorkflow in @($trustedWorkflowByCheck.Values)) {
    $workflowPath=[string]$trustedWorkflow.workflow_path
    $workflowResponse = Native-ReadOnly $ghCommand @("api", "--method", "GET", "-H", "Accept: application/vnd.github+json", "repos/$ExpectedRepo/contents/$workflowPath`?ref=main"); Native-OK $workflowResponse "PRE-GH" "trusted workflow content on main"
    $workflowObject = ConvertFrom-StrictJsonText $workflowResponse.Text "trusted workflow content"
    if ([string]$workflowObject.path -cne $workflowPath -or [string]$workflowObject.type -cne "file" -or [string]$workflowObject.encoding -cne "base64") { Stop-Launcher "PRE-GH" "trusted workflow content response mismatch" }
    try { $workflowBytes=[Convert]::FromBase64String(([string]$workflowObject.content).Replace("`n", "")) } catch { Stop-Launcher "PRE-GH" "trusted workflow content is not canonical base64" }
    if ((Bytes-Sha256 $workflowBytes) -cne [string]$trustedWorkflow.workflow_sha256) { Stop-Launcher "PRE-GH" "trusted workflow on main differs from protected hash: $workflowPath" }
}
foreach ($workflow in $trustedWorkflowByCheck.Values) {
    $workflowMetadataResponse = Native-ReadOnly $ghCommand @("api", "--method", "GET", "-H", "Accept: application/vnd.github+json", "repos/$ExpectedRepo/actions/workflows/$([int64]$workflow.workflow_id)"); Native-OK $workflowMetadataResponse "PRE-GH" "trusted workflow metadata"
    $workflowMetadata = ConvertFrom-StrictJsonText $workflowMetadataResponse.Text "trusted workflow metadata"
    if ([int64]$workflowMetadata.id -ne [int64]$workflow.workflow_id -or [string]$workflowMetadata.path -cne [string]$workflow.workflow_path -or [string]$workflowMetadata.state -cne "active") { Stop-Launcher "PRE-GH" "trusted workflow id/path/state mismatch" }
}
$preHead = SafeGit $gitCommand @("-C", $resolvedRoot, "rev-parse", "HEAD"); Native-OK $preHead "PRE-GH" "preflight HEAD"
$preRemoteRef = Native-ReadOnly $ghCommand @("api", "--method", "GET", "-H", "Accept: application/vnd.github+json", "repos/$ExpectedRepo/git/ref/heads/$ExpectedBranch"); Native-OK $preRemoteRef "PRE-GH" "GitHub branch ref"
$preRemoteRefObject = ConvertFrom-StrictJsonText $preRemoteRef.Text "GitHub branch ref response"
if ([string]$preRemoteRefObject.ref -cne "refs/heads/$ExpectedBranch" -or [string]$preRemoteRefObject.object.type -cne "commit" -or [string]$preRemoteRefObject.object.sha -cne $preHead.Text) { Stop-Launcher "PRE-UPSTREAM" "GitHub branch ref must equal local HEAD before Codex" }
if ($Mode -ceq "Implement") {
    $pushProbe = SafeGit $gitCommand @("-C", $resolvedRoot, "push", "--dry-run", "origin", "HEAD:refs/heads/$ExpectedBranch"); Native-OK $pushProbe "PRE-GH" "GitHub push permission/refspec dry-run"
}
Write-Pass "PRE-TRUST/PRE-GH guarded tool, keyring, workflow, and authentication preflight"

$baselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $baselinePath).Hash.ToLowerInvariant()
if ($Mode -ceq "VerifyCandidate" -or $Mode -ceq "VerifyAccepted") {
    if (-not [string]::IsNullOrWhiteSpace($ResumeRun)) { Stop-Launcher "MODE" "read-only verification modes do not accept -ResumeRun" 6 }
    Invoke-ReadOnlyReleaseVerification $Mode $AttestationBundlePath $resolvedRoot $resolvedAttestationRoot $resolvedTrustPath $protectedTrustRootsSnapshot $gitCommand $ghCommand $gpgCommand $trustedPowerShellCommand $trustedValidatorBytes $trustedWorkflowByCheck $allowedGithubActors $trustedFingerprints $trustedToolInventory $releaseTrust.trusted_tools $gitControlPlaneSnapshot $gitReferenceSnapshot $baseline $baselineHash $trustedInventory $trustedRequirementsRegistry
}

if ($DryRun) {
    $dryRunSyntheticRunId = '00000000T000000Z-00000000'
    $dryRunAttemptId = '00000000T000000Z-000000000000'
    $dryRunResumeCommand = Get-ResumeCommand -RunId $dryRunSyntheticRunId -ReleaseId $guardedReleaseId
    $dryRunEnvelope = New-CodexRuntimeEnvelope $dryRunSyntheticRunId $dryRunAttemptId '2000-01-01T00:00:00.0000000Z' $preHead.Text $guardedReleaseId 'initial' $dryRunResumeCommand
    $dryRunBaseSchemaText = Read-Utf8NoBomText $outputSchemaPath $MaxJsonBytes 'trusted model-facing output schema'
    $dryRunSchemaText = New-RuntimeCodexOutputSchemaText $dryRunBaseSchemaText $dryRunSyntheticRunId $guardedReleaseId
    $dryRunSchema = ConvertFrom-StrictJsonText $dryRunSchemaText 'runtime output schema'
    $dryRunRunProperty = $dryRunSchema.properties.PSObject.Properties['run_id'].Value
    $dryRunReleaseProperty = $dryRunSchema.properties.PSObject.Properties['release_id'].Value
    if (-not $dryRunEnvelope.Contains("run_id=$dryRunSyntheticRunId") -or -not $dryRunEnvelope.Contains("release_id=$guardedReleaseId") -or -not $dryRunEnvelope.Contains("attempt_started_at=2000-01-01T00:00:00.0000000Z") -or $dryRunEnvelope.Contains("attempt_started_at=2000-01-01T00:00:00.0000000+00:00") -or @($dryRunRunProperty.enum).Count -ne 1 -or [string]@($dryRunRunProperty.enum)[0] -cne $dryRunSyntheticRunId -or @($dryRunReleaseProperty.enum).Count -ne 1 -or [string]@($dryRunReleaseProperty.enum)[0] -cne $guardedReleaseId -or (String-Sha256 $dryRunSchemaText) -notmatch '^[0-9a-f]{64}$') {
        Stop-Launcher "RUNTIME-IDENTITY" "dry-run runtime prompt/schema binding is not exact" 6
    }
    $dryRunExclusion = '.artifacts/codex/00000000T000000Z-00000000'
    $dryRunSnapshot = Get-WorktreeSnapshot $gitCommand $resolvedRoot $dryRunExclusion
    if ([string]$dryRunSnapshot.protected_ignored_inventory_sha256 -notmatch '^[0-9a-f]{64}$') { Stop-Launcher "WORKTREE-SNAPSHOT" "protected ignored inventory digest is invalid" 6 }
    Write-Host "PROTECTED_IGNORED_INVENTORY_SHA256: $($dryRunSnapshot.protected_ignored_inventory_sha256)"
    Write-Pass "PRE-WORKTREE-SNAPSHOT protected ignored dependency and workspace inventory"
    Write-Pass "PRE-RELEASE-IDENTITY exact guarded RC release binding"
    Write-Pass "PRE-RUNTIME-IDENTITY exact guarded run prompt and schema binding"
    Write-Host "DRY-RUN: all preflight checks passed; Codex not invoked."
    exit 0
}

$isResume = -not [string]::IsNullOrWhiteSpace($ResumeRun)
if ($isResume -and $ResumeRun -notmatch '^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$') { Stop-Launcher "RESUME-ID" "invalid run id" }
$runId = $(if ($isResume) { $ResumeRun } else { "{0}-{1}" -f ([DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")), ([Guid]::NewGuid().ToString("N").Substring(0, 8)) })
$script:ActiveRunId = $runId
$runDirectory = Join-Path $resolvedRoot (Join-Path $ArtifactRelative $runId)
if ($isResume) { if (-not (Test-Path -LiteralPath $runDirectory -PathType Container)) { Stop-Launcher "RESUME-ID" "run evidence missing" } } else { New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null }
Assert-NoReparseComponent $runDirectory "PRE-ARTIFACT"
$runManifest = Join-Path $runDirectory "run-manifest.json"; $runManifestHash = Join-Path $runDirectory "run-manifest.sha256"; $sessionPath = Join-Path $runDirectory "session-id.txt"; $resumeStatePath = Join-Path $runDirectory "resume-state.json"; $runLockPath=Join-Path $runDirectory "run.lock"
try { $runLock=[IO.File]::Open($runLockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) } catch { Stop-Launcher "RUN-LOCK" "another process owns this exact run or the lock cannot be opened" 6 }
$attemptId = "{0}-{1}" -f ([DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")), ([Guid]::NewGuid().ToString("N").Substring(0, 12))
$attemptStartedAt = [DateTimeOffset]::UtcNow
$attemptStartedAtText = ConvertTo-UtcRfc3339Z $attemptStartedAt
$attemptTimestampPattern = '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{7}Z$'
if ($attemptStartedAtText -notmatch $attemptTimestampPattern) {
    Stop-Launcher 'ATTEMPT-TIMESTAMP' 'attempt timestamp is not canonical UTC RFC3339 Z' 6
}
$finalResult = Join-Path $runDirectory "final-result-$attemptId.json"
$progressLog = Join-Path $runDirectory "progress-$attemptId.jsonl"; $errorLog = Join-Path $runDirectory "errors-$attemptId.log"; $postEvidence = Join-Path $runDirectory "post-run-evidence-$attemptId.json"; $docEvidence = Join-Path $runDirectory "final-document-verification-$attemptId.json"
foreach ($attemptPath in @($finalResult, $progressLog, $errorLog, $postEvidence, $docEvidence)) { if (Test-Path -LiteralPath $attemptPath) { Stop-Launcher "ATTEMPT-IDENTITY" "attempt artifact already exists: $attemptPath" } }
$runtimeOutputSchema = Join-Path $runDirectory "runtime-output-schema-$attemptId.json"
if (Test-Path -LiteralPath $runtimeOutputSchema) { Stop-Launcher "ATTEMPT-IDENTITY" "runtime output schema already exists: $runtimeOutputSchema" }

$promptHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $promptPath).Hash.ToLowerInvariant(); $outputSchemaHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputSchemaPath).Hash.ToLowerInvariant(); $strictSchemaHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $strictSchemaPath).Hash.ToLowerInvariant(); $contractHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $contractPath).Hash.ToLowerInvariant(); $inventoryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $inventoryPath).Hash.ToLowerInvariant()
$head = SafeGit $gitCommand @("-C", $resolvedRoot, "rev-parse", "HEAD"); Native-OK $head "PRE-GIT" "HEAD"
$activeRunRelative = "$ArtifactRelative/$runId"
$runtimeBaseSchemaText = Read-Utf8NoBomText $outputSchemaPath $MaxJsonBytes "trusted model-facing output schema"
$runtimeSchemaText = New-RuntimeCodexOutputSchemaText $runtimeBaseSchemaText $runId $guardedReleaseId
Write-AtomicUtf8Text $runtimeOutputSchema $runtimeSchemaText
$runtimeOutputSchemaSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeOutputSchema).Hash.ToLowerInvariant()
Assert-RuntimeCodexOutputSchemaBinding $runtimeOutputSchema $runDirectory $runId $guardedReleaseId $attemptId $runtimeOutputSchemaSha256 | Out-Null
$initialWorktreeSnapshot = Get-WorktreeSnapshot $gitCommand $resolvedRoot $activeRunRelative
if (-not $isResume) {
    # manifest release_id and state release_id are exact guarded values.
    $manifest = [ordered]@{ manifest_version="codex-run-manifest.v8"; baseline_id=$baseline.baseline_id; run_id=$runId; release_id=$guardedReleaseId; mode="Implement"; created_at=[DateTime]::UtcNow.ToString("o"); repository=[ordered]@{root=$resolvedRoot;branch=$ExpectedBranch;remote=$ExpectedRemote;initial_head=$head.Text;worktree_snapshot=$initialWorktreeSnapshot;git_control_plane=$gitControlPlaneSnapshot}; inputs=[ordered]@{baseline_sha256=$baselineHash;prompt_sha256=$promptHash;output_schema_sha256=$outputSchemaHash;runtime_output_schema_sha256=$runtimeOutputSchemaSha256;strict_schema_sha256=$strictSchemaHash;deliverable_contract_sha256=$contractHash;final_document_inventory_sha256=$inventoryHash;trusted_validator_sha256=$trustedValidatorSha256;trusted_input_sha256=$trustedInputHashes;release_trust_sha256=$releaseTrustSha256}; tools=[ordered]@{trusted_executable_inventory=$trustedToolInventory;codex_version=$codexVersion.Text;codex_help_contract_sha256=$codexHelpDigest;docker_version=$dockerServer.Text;compose_version=$composeVersion.Text;git_credential_helper_sha256=(String-Sha256 $script:GitHubCredentialHelper);gpg_home=$resolvedGpgHome;gpg_version=($gpgVersion.Text -split "`n")[0]}; policy=[ordered]@{sandbox="workspace-write";approval="on-request";json_events=$true;ignore_user_config=$true;ignore_rules=$true;strict_config=$true;pinned_github_credential_helper=$true} }
    Write-AtomicUtf8Text $runManifest ($manifest | ConvertTo-Json -Depth 10)
    $digest = (Get-FileHash -Algorithm SHA256 -LiteralPath $runManifest).Hash.ToLowerInvariant(); Set-Content -Encoding ASCII -LiteralPath $runManifestHash -Value "$digest  run-manifest.json"
} else {
    foreach ($path in @($runManifest, $runManifestHash, $sessionPath, $resumeStatePath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Launcher "RESUME-IDENTITY" "missing $path" }; Assert-NoReparseComponent $path "RESUME-IDENTITY" }
    $digest = (Get-FileHash -Algorithm SHA256 -LiteralPath $runManifest).Hash.ToLowerInvariant(); $recordedDigest = ((Get-Content -Raw -LiteralPath $runManifestHash).Trim() -split '\s+')[0]
    if ($digest -cne $recordedDigest) { Stop-Launcher "RESUME-IDENTITY" "manifest digest mismatch" }
    $manifest = ConvertFrom-StrictJsonFile $runManifest "run manifest"; $state = ConvertFrom-StrictJsonFile $resumeStatePath "resume state"
    Assert-ExactObjectProperties $manifest @("manifest_version","baseline_id","run_id","release_id","mode","created_at","repository","inputs","tools","policy") "run manifest"
    Assert-ExactObjectProperties $manifest.repository @("root","branch","remote","initial_head","worktree_snapshot","git_control_plane") "run manifest repository"
    Assert-ExactObjectProperties $manifest.inputs @("baseline_sha256","prompt_sha256","output_schema_sha256","runtime_output_schema_sha256","strict_schema_sha256","deliverable_contract_sha256","final_document_inventory_sha256","trusted_validator_sha256","trusted_input_sha256","release_trust_sha256") "run manifest inputs"
    Assert-ExactObjectProperties $manifest.tools @("trusted_executable_inventory","codex_version","codex_help_contract_sha256","docker_version","compose_version","git_credential_helper_sha256","gpg_home","gpg_version") "run manifest tools"
    Assert-ExactObjectProperties $manifest.policy @("sandbox","approval","json_events","ignore_user_config","ignore_rules","strict_config","pinned_github_credential_helper") "run manifest policy"
    Assert-ExactObjectProperties $state @("run_id","release_id","attempt_id","attempt_started_at","final_result_path","thread_id","head","worktree_snapshot","manifest_sha256","baseline_sha256","prompt_sha256","output_schema_sha256","runtime_output_schema_sha256","strict_schema_sha256","final_document_inventory_sha256","trusted_validator_sha256","release_trust_sha256","updated_at") "resume state"
    $persistedSessionId = (Read-Utf8NoBomText $sessionPath 128 "session receipt").Trim()
    if ($persistedSessionId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' -or [string]$state.thread_id -cne $persistedSessionId) { Stop-Launcher "RESUME-IDENTITY" "session receipt/state UUID mismatch" }
    if ($manifest.manifest_version -cne "codex-run-manifest.v8" -or [string]$manifest.run_id -cne $runId -or [string]$manifest.release_id -cne $guardedReleaseId -or [string]$state.release_id -cne $guardedReleaseId -or [string]$manifest.mode -cne "Implement" -or [string]$state.run_id -cne $runId -or $manifest.inputs.baseline_sha256 -cne $baselineHash -or $manifest.inputs.prompt_sha256 -cne $promptHash -or $manifest.inputs.output_schema_sha256 -cne $outputSchemaHash -or $manifest.inputs.runtime_output_schema_sha256 -cne $runtimeOutputSchemaSha256 -or $manifest.inputs.strict_schema_sha256 -cne $strictSchemaHash -or $manifest.inputs.deliverable_contract_sha256 -cne $contractHash -or $manifest.inputs.final_document_inventory_sha256 -cne $inventoryHash -or $manifest.inputs.trusted_validator_sha256 -cne $trustedValidatorSha256 -or $manifest.inputs.release_trust_sha256 -cne $releaseTrustSha256 -or $manifest.tools.codex_help_contract_sha256 -cne $codexHelpDigest -or ($manifest.tools.trusted_executable_inventory | ConvertTo-Json -Depth 8 -Compress) -cne ($trustedToolInventory | ConvertTo-Json -Depth 8 -Compress) -or $manifest.tools.git_credential_helper_sha256 -cne (String-Sha256 $script:GitHubCredentialHelper) -or $manifest.tools.gpg_home -cne $resolvedGpgHome -or $state.manifest_sha256 -cne $digest -or $state.head -cne $head.Text -or $state.baseline_sha256 -cne $baselineHash -or $state.prompt_sha256 -cne $promptHash -or $state.output_schema_sha256 -cne $outputSchemaHash -or $state.runtime_output_schema_sha256 -cne $runtimeOutputSchemaSha256 -or $state.strict_schema_sha256 -cne $strictSchemaHash -or $state.final_document_inventory_sha256 -cne $inventoryHash -or $state.trusted_validator_sha256 -cne $trustedValidatorSha256 -or $state.release_trust_sha256 -cne $releaseTrustSha256) { Stop-Launcher "RESUME-IDENTITY" "run/HEAD/manifest/input/CLI/trust contract changed" }
    if (-not (Compare-GitControlPlaneSnapshot $manifest.repository.git_control_plane $gitControlPlaneSnapshot)) { Stop-Launcher "RESUME-IDENTITY" "Git control-plane differs from the original attempt" }
    Assert-TrustedRuntimeInputs $gitCommand $resolvedRoot ([string]$manifest.repository.initial_head) $manifest.inputs.trusted_input_sha256 $trustedRelativePaths
    if ((Snapshot-Digest $initialWorktreeSnapshot) -cne (Snapshot-Digest $state.worktree_snapshot)) { Stop-Launcher "RESUME-IDENTITY" "worktree snapshot differs from the interrupted attempt receipt" }
    $expectedPriorResult=[IO.Path]::GetFullPath([string]$state.final_result_path)
    if (-not $expectedPriorResult.StartsWith($runDirectory + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($expectedPriorResult) -notmatch '^final-result-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}\.json$') { Stop-Launcher "RESUME-IDENTITY" "resume state final result path is cross-run or malformed" }
    $script:ResumeAvailable = $true
}

$resumeCommand = Get-ResumeCommand -RunId $runId -ReleaseId $guardedReleaseId
$runtimeEnvelope = New-CodexRuntimeEnvelope $runId $attemptId $attemptStartedAtText ([string]$manifest.repository.initial_head) $guardedReleaseId $(if ($isResume) { "resume" } else { "initial" }) $resumeCommand
$basePromptText = $(if ($isResume) { "Resume the interrupted implementation using the exact plan and preserve verified work. Produce the required final JSON." } else { Get-Content -Raw -Encoding UTF8 -LiteralPath $promptPath })
$promptText = "$runtimeEnvelope`n`n$basePromptText"
$CodexArguments = $(if ($isResume) { $sessionId = $persistedSessionId; @("-C", $resolvedRoot, "--sandbox", "workspace-write", "--ask-for-approval", "on-request", "exec", "resume", $sessionId, "--ignore-user-config", "--ignore-rules", "--strict-config", "--json", "--output-last-message", $finalResult, "--output-schema", $runtimeOutputSchema, "-") } else { @("-C", $resolvedRoot, "--sandbox", "workspace-write", "--ask-for-approval", "on-request", "exec", "--ignore-user-config", "--ignore-rules", "--strict-config", "--json", "--output-last-message", $finalResult, "--output-schema", $runtimeOutputSchema, "-") })
Assert-SafeCodexArguments $CodexArguments
Write-Host "RUN: run_id=$runId, mode=$(if ($isResume) { 'resume' } else { 'initial' })"
Write-Host "EVIDENCE: $runDirectory"
Write-Host "RESUME: $resumeCommand (available after exact thread.started UUID validation)"
$expectedThreadId = $(if ($isResume) { $sessionId } else { "" })
$executionBoundarySnapshot=Get-WorktreeSnapshot $gitCommand $resolvedRoot $activeRunRelative
$boundaryDigest=Snapshot-Digest $executionBoundarySnapshot; $expectedBoundaryDigest=Snapshot-Digest $initialWorktreeSnapshot
Assert-ResumeBindingObservation ([pscustomobject]@{run_id=$runId;requested_run_id=$(if($isResume){$ResumeRun}else{$runId});manifest_run_id=[string]$manifest.run_id;state_run_id=$(if($isResume){[string]$state.run_id}else{$runId});canonical_run_directory=[IO.Path]::GetFullPath((Join-Path $resolvedRoot (Join-Path $ArtifactRelative $runId)));observed_run_directory=[IO.Path]::GetFullPath($runDirectory);manifest_sha256=$digest;state_manifest_sha256=$(if($isResume){[string]$state.manifest_sha256}else{$digest});before_inventory_sha256=$expectedBoundaryDigest;execution_boundary_inventory_sha256=$boundaryDigest;exact_property_set=$true;exclusive_lock_held=(-not $runLock.SafeFileHandle.IsClosed)})
$codexExit = Invoke-Utf8Process -Command $codexCommand -Arguments $CodexArguments -InputText $promptText -StdoutPath $progressLog -StderrPath $errorLog -RunId $runId -HeartbeatSeconds 5 -ResumeCommand $resumeCommand -SessionReceiptPath $sessionPath -ExpectedThreadId $expectedThreadId
Assert-RuntimeCodexOutputSchemaBinding $runtimeOutputSchema $runDirectory $runId $guardedReleaseId $attemptId $runtimeOutputSchemaSha256 | Out-Null
Assert-TrustedExecutableInventoryUnchanged $trustedToolInventory $releaseTrust.trusted_tools $resolvedRoot
Assert-GitControlPlaneSnapshot $gitControlPlaneSnapshot
Assert-ProtectedTrustRootsUnchanged $protectedTrustRootsSnapshot $resolvedTrustPath $ProtectedHooksPath $ProtectedGpgHome $resolvedAttestationRoot
Assert-TrustedRuntimeInputs $gitCommand $resolvedRoot ([string]$manifest.repository.initial_head) $manifest.inputs.trusted_input_sha256 $trustedRelativePaths
if ((Bytes-Sha256 $trustedValidatorBytes) -cne [string]$manifest.inputs.trusted_validator_sha256) { Stop-Launcher "POST-TRUST" "in-memory trusted validator digest changed" 6 }
if ((Get-FileHash -LiteralPath $resolvedTrustPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$manifest.inputs.release_trust_sha256) { Stop-Launcher "POST-TRUST" "protected release trust store changed during Codex execution" 6 }
$parsedEvents = Read-CodexEvents $progressLog; $events = @($parsedEvents.Events)
$observedSessionId = Get-ThreadId $events
if ($isResume) {
    if ($observedSessionId -cne $sessionId) { Stop-Launcher "SESSION-ID" "resume JSONL thread UUID differs from persisted session ID" 3 }
} else {
    $sessionId = $observedSessionId
    if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) { Write-AtomicUtf8Text $sessionPath $sessionId }
}
$receiptSessionId = (Read-Utf8NoBomText $sessionPath 128 "session receipt").Trim()
if ($receiptSessionId -cne $sessionId) { Stop-Launcher "SESSION-ID" "early session receipt differs from completed JSONL" 3 }
$afterHead = SafeGit $gitCommand @("-C", $resolvedRoot, "rev-parse", "HEAD"); Native-OK $afterHead "POST-GIT" "post-run HEAD"
$attemptWorktreeSnapshot = Get-WorktreeSnapshot $gitCommand $resolvedRoot $activeRunRelative
if ([string]$attemptWorktreeSnapshot.ignored_inventory_sha256 -cne [string]$initialWorktreeSnapshot.ignored_inventory_sha256) { Stop-Launcher "POST-IGNORED" "ignored files outside the isolated run evidence directory changed during Codex execution" 6 }
$stateObject = [ordered]@{ run_id=$runId; release_id=$guardedReleaseId; attempt_id=$attemptId; attempt_started_at=$attemptStartedAtText; final_result_path=$finalResult; thread_id=$sessionId; head=$afterHead.Text; worktree_snapshot=$attemptWorktreeSnapshot; manifest_sha256=$digest; baseline_sha256=$baselineHash; prompt_sha256=$promptHash; output_schema_sha256=$outputSchemaHash; runtime_output_schema_sha256=$runtimeOutputSchemaSha256; strict_schema_sha256=$strictSchemaHash; final_document_inventory_sha256=$inventoryHash; trusted_validator_sha256=$trustedValidatorSha256; release_trust_sha256=$releaseTrustSha256; updated_at=[DateTime]::UtcNow.ToString("o") }; Write-AtomicUtf8Text $resumeStatePath ($stateObject | ConvertTo-Json -Depth 10) -Replace
$script:ResumeAvailable = $true
if ($null -ne $parsedEvents.ParseError) { Stop-Launcher "PROGRESS-JSONL" ([string]$parsedEvents.ParseError) 3 }
if ($codexExit -ne 0) { [Console]::Error.WriteLine("FAIL [CODEX-EXEC]: exit $codexExit"); [Console]::Error.WriteLine("RESUME: $resumeCommand"); exit $codexExit }
if (-not (Test-Path -LiteralPath $finalResult -PathType Leaf)) { Stop-Launcher "RESULT-MISSING" "final result missing" 3 }
Assert-NoReparseComponent $finalResult "RESULT-PATH"
[void](Assert-BoundedFile $finalResult $MaxJsonBytes "RESULT-SIZE" "Codex final JSON")
$finalResultItem = Get-Item -LiteralPath $finalResult -Force
if ($finalResultItem.Length -le 0 -or $finalResultItem.LastWriteTimeUtc -lt $attemptStartedAt.UtcDateTime) { Stop-Launcher "RESULT-FRESHNESS" "final result is empty or predates the current attempt" 3 }
$validatorResult = Invoke-TrustedValidatorProcess -PowerShellCommand $trustedPowerShellCommand -TrustedValidatorBytes $trustedValidatorBytes -ResultPath $finalResult -ExpectedRunId $runId -ExpectedReleaseId $guardedReleaseId -ProjectRoot $resolvedRoot -ExpectedAttemptStartedAt $attemptStartedAtText
if ($validatorResult.ExitCode -ne 5) {
    if (-not [string]::IsNullOrWhiteSpace($validatorResult.Text)) { [Console]::Error.WriteLine($validatorResult.Text) }
    if ($validatorResult.ExitCode -eq 0) { Stop-Launcher "RESULT-STATE" "Implement validator must return the fail-closed NOT_READY exit 5" 6 }
    exit $validatorResult.ExitCode
}
if (-not [string]::IsNullOrWhiteSpace($validatorResult.Text)) { [Console]::Error.WriteLine($validatorResult.Text) }
$result = ConvertFrom-StrictJsonFile $finalResult "Codex final result"
if ([string]$result.release_state -cne "NOT_READY") { Stop-Launcher "RESULT-STATE" "Implement may not claim a signed release state" 6 }
if ([string]$result.candidate_phase -ceq "IMPLEMENTATION_BLOCKED") {
    Write-Host "RESULT: NOT_READY / IMPLEMENTATION_BLOCKED"
    Write-Host "RUN: $runDirectory"
    exit 5
}
if ([string]$result.candidate_phase -cne "UNSIGNED_CANDIDATE / REVIEW PENDING") { Stop-Launcher "RESULT-STATE" "unknown Implement candidate phase" 6 }

Assert-TrustedExecutableInventoryUnchanged $trustedToolInventory $releaseTrust.trusted_tools $resolvedRoot
Assert-GitControlPlaneSnapshot $gitControlPlaneSnapshot
Assert-ProtectedTrustRootsUnchanged $protectedTrustRootsSnapshot $resolvedTrustPath $ProtectedHooksPath $ProtectedGpgHome $resolvedAttestationRoot
Assert-TrustedRuntimeInputs $gitCommand $resolvedRoot ([string]$manifest.repository.initial_head) $manifest.inputs.trusted_input_sha256 $trustedRelativePaths
if ((Bytes-Sha256 $trustedValidatorBytes) -cne [string]$manifest.inputs.trusted_validator_sha256 -or (Get-FileHash -LiteralPath $resolvedTrustPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$manifest.inputs.release_trust_sha256) { Stop-Launcher "POST-TRUST" "trusted validator or release trust changed during Codex" 6 }

$postBranch=SafeGit $gitCommand @("-C",$resolvedRoot,"rev-parse","--abbrev-ref","HEAD")
$postRemote=SafeGit $gitCommand @("-C",$resolvedRoot,"remote","get-url","origin")
$postStatus=SafeGit $gitCommand @("-C",$resolvedRoot,"status","--porcelain=v1","--untracked-files=normal")
$postUpstream=SafeGit $gitCommand @("-C",$resolvedRoot,"rev-parse","--abbrev-ref","--symbolic-full-name","@{u}")
$postSync=SafeGit $gitCommand @("-C",$resolvedRoot,"rev-list","--left-right","--count","HEAD...@{u}")
foreach ($fact in @($postBranch,$postRemote,$postStatus,$postUpstream,$postSync)) { if ($fact.ExitCode -ne 0) { Stop-Launcher "POST-GIT" "repository handoff fact failed" 6 } }
if ($postBranch.Text -cne $ExpectedBranch -or $postRemote.Text -cne $ExpectedRemote -or -not [string]::IsNullOrWhiteSpace($postStatus.Text) -or $postUpstream.Text -cne "origin/$ExpectedBranch" -or $postSync.Text -notmatch '^[0] +[0]$') { Stop-Launcher "POST-GIT" "branch/origin/clean/upstream/pushed closure failed" 6 }

$identity=Get-ReleaseCandidateIdentity $gitCommand $resolvedRoot ([string]$manifest.repository.initial_head) ([string]$result.release_id) $trustedInventory ([string]$result.repository.implementation_commit) ([string]$result.repository.release_snapshot_commit)
$ci=Get-AndAssertGitHubCandidateFacts $ghCommand ([string]$identity.release_snapshot_commit) $trustedWorkflowByCheck $allowedGithubActors
if ([string]$result.repository.root -cne $ExpectedRoot -or [string]$result.repository.remote -cne $ExpectedRemote -or [string]$result.repository.branch -cne $ExpectedBranch -or
    [string]$result.repository.baseline_commit -cne [string]$manifest.repository.initial_head -or [string]$result.repository.implementation_tree -cne [string]$identity.tree.tree_object -or
    [string]$result.repository.implementation_tree_sha256 -cne [string]$identity.tree.source_tree_sha256 -or $result.repository.worktree_clean -ne $true -or
    [string]$result.repository.push_status -cne "PUSHED" -or [string]$result.repository.pull_request_url -cne [string]$ci.pull_request.html_url) {
    Stop-Launcher "POST-IDENTITY" "Codex result differs from independent repository/S/R/tree/PR facts" 6
}

$commitLog=SafeGit $gitCommand @("-C",$resolvedRoot,"log","--no-ext-diff","--no-textconv","--reverse","--format=%H%x09%s","$([string]$manifest.repository.initial_head)..$([string]$identity.release_snapshot_commit)"); Native-OK $commitLog "POST-COMMITS" "implementation/release commit range"
$actualCommits=@($commitLog.Text -split ([char]10) | Where-Object { $_ } | ForEach-Object { $parts=$_.TrimEnd([char]13) -split ([char]9),2; [pscustomobject]@{hash=$parts[0];subject=$parts[1]} })
if ($actualCommits.Count -lt 2 -or @($result.commits).Count -ne $actualCommits.Count -or $actualCommits[-2].hash -cne [string]$identity.implementation_commit -or $actualCommits[-1].hash -cne [string]$identity.release_snapshot_commit) { Stop-Launcher "POST-COMMITS" "commit list must end with exact S then R" 6 }
for ($index=0; $index -lt $actualCommits.Count; $index+=1) { if ([string]$result.commits[$index].hash -cne [string]$actualCommits[$index].hash -or [string]$result.commits[$index].subject -cne [string]$actualCommits[$index].subject) { Stop-Launcher "POST-COMMITS" "reported commit list/order mismatch" 6 } }

$now=[DateTimeOffset]::UtcNow
foreach ($acceptance in @($result.acceptance_data)) {
    $due=ConvertFrom-RequiredUtc ([string]$acceptance.due_at_utc) "acceptance due_at_utc"
    if ([string]$acceptance.candidate_commit -cne [string]$identity.implementation_commit -or [string]$acceptance.candidate_source_tree_sha256 -cne [string]$identity.tree.source_tree_sha256 -or $due -le $now -or $due -gt $now.AddHours($AcceptanceDueWindowHours)) { Stop-Launcher "POST-ACCEPTANCE" "acceptance work must bind S/tree and a bounded future due date" 6 }
}

Assert-ExactEvidencePackage $result $identity $trustedRequirementsRegistry $baseline $resolvedRoot $gitCommand
Assert-TrackedReleaseArtifacts $identity ([string]$result.release_id) $baseline $baselineHash $trustedInventory $resolvedRoot $gitCommand ([string]$trustedFingerprints["OWN-QA"])
Assert-ReleaseDocuments $result $trustedInventory $resolvedRoot $gitCommand
Assert-ReleaseStateTransition ([pscustomobject]@{mode="Implement";release_state="NOT_READY";candidate_phase="UNSIGNED_CANDIDATE / REVIEW PENDING";technical_signatures=0;acceptance_signature=$false;signed_tag=$false})

$localTag=SafeGit $gitCommand @("-C",$resolvedRoot,"show-ref","--verify","--quiet","refs/tags/$([string]$result.release_id)")
$remoteTag=Get-GitHubApiResponseWithStatus $ghCommand "repos/$ExpectedRepo/git/ref/tags/$([string]$result.release_id)" "unsigned Implement tag lookup"
Assert-RemoteTagLookupObservation ([pscustomobject]@{expectation="ABSENT";exit_code=[int]$remoteTag.ExitCode;http_status=[int]$remoteTag.StatusCode})
if ($localTag.ExitCode -ne 1) { Stop-Launcher "POST-TAG" "unsigned Implement handoff must not create a local or remote release tag" 6 }

Assert-TrustedExecutableInventoryUnchanged $trustedToolInventory $releaseTrust.trusted_tools $resolvedRoot
Assert-ProtectedTrustRootsUnchanged $protectedTrustRootsSnapshot $resolvedTrustPath $ProtectedHooksPath $ProtectedGpgHome $resolvedAttestationRoot
$closingHead=SafeGit $gitCommand @("-C",$resolvedRoot,"rev-parse","HEAD"); Native-OK $closingHead "POST-FINAL" "closing HEAD"
$closingStatus=SafeGit $gitCommand @("-C",$resolvedRoot,"status","--porcelain=v1","--untracked-files=normal"); Native-OK $closingStatus "POST-FINAL" "closing worktree"
$closingRemote=Native-ReadOnly $ghCommand @("api","--method","GET","-H","Accept: application/vnd.github+json","repos/$ExpectedRepo/git/ref/heads/$ExpectedBranch"); Native-OK $closingRemote "POST-FINAL" "closing remote ref"
$closingRemoteObject=ConvertFrom-StrictJsonText $closingRemote.Text "closing remote ref"
Assert-GitControlPlaneSnapshot $gitControlPlaneSnapshot
if ($closingHead.Text -cne [string]$identity.release_snapshot_commit -or -not [string]::IsNullOrWhiteSpace($closingStatus.Text) -or [string]$closingRemoteObject.object.sha -cne [string]$identity.release_snapshot_commit) { Stop-Launcher "POST-FINAL" "R/worktree/remote changed during guarded verification" 6 }

$resultSha256=(Get-FileHash -LiteralPath $finalResult -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Pass "Implement produced independently verified, unsigned S -> R handoff"
Write-Host "RESULT: NOT_READY"
Write-Host "CANDIDATE_PHASE: UNSIGNED_CANDIDATE / REVIEW PENDING"
Write-Host "RUN: $runDirectory"
Write-Host "CANDIDATE_RESULT: $finalResult"
Write-Host "CANDIDATE_RESULT_SHA256: $resultSha256"
Write-Host "NEXT: copy the result to the protected attestation root, collect external signatures, then run -Mode VerifyCandidate"
exit 5

