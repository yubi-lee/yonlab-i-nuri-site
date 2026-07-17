[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RunnerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$powerShell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$root = Join-Path ([IO.Path]::GetTempPath()) ("yonlab-runner-policy-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $root | Out-Null

function Write-Fixture([string]$Name, $Payload) {
    $path = Join-Path $root "$Name.json"
    [IO.File]::WriteAllText($path, ($Payload | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding -ArgumentList $false))
    return $path
}

function Copy-Fixture($Payload) {
    return ($Payload | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
}

function Invoke-Policy([string]$Name, $Payload, [bool]$ShouldPass, [string]$ExpectedCode) {
    $fixture = Write-Fixture $Name $Payload
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
    $output = @(& $powerShell -NoLogo -NoProfile -File $RunnerPath -Mode PolicySelfTest -PolicyFixture $fixture 2>&1 | ForEach-Object { $_.ToString() })
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $exitCode = $LASTEXITCODE
    if ($ShouldPass) {
        if ($exitCode -ne 0 -or ($output -join "`n") -notmatch "PASS \[$ExpectedCode\]") {
            throw "$Name should pass ($ExpectedCode), exit=$exitCode output=$($output -join ' | ')"
        }
    } else {
        if ($exitCode -eq 0 -or ($output -join "`n") -notmatch "FAIL \[$ExpectedCode\]") {
            throw "$Name should fail closed ($ExpectedCode), exit=$exitCode output=$($output -join ' | ')"
        }
    }
    Write-Host "PASS: $Name"
}

try {
    $s = "1" * 40; $r = "2" * 40; $tree = "3" * 40; $digest = "4" * 64
    $identity = [ordered]@{
        schema_version = "runner-policy-fixture.v1"; case = "release-identity"
        implementation_commit = $s; implementation_tree = $tree; implementation_tree_sha256 = $digest
        release_snapshot_commit = $r; release_parent_commit = $s; artifact_source_commit = $s
        evidence_source_commit = $s; initial_is_ancestor_of_implementation = $true
        implementation_is_first_parent_of_release = $true
        release_diff_paths = @("docs/releases/ai-training-platform/v1/artifact-manifest.json", "dist/docs/v1/SHA256SUMS.txt")
    }
    Invoke-Policy "constructible-two-identity" $identity $true "POLICY-IDENTITY"
    $badIdentity = Copy-Fixture $identity; $badIdentity.artifact_source_commit = $r
    Invoke-Policy "reject-self-referential-artifact" $badIdentity $false "POLICY-IDENTITY"

    $tool = [ordered]@{
        schema_version="runner-policy-fixture.v1"; case="trusted-tool"
        workspace_root="D:\Views\yonlab-inuri-site"; path="C:\Program Files\Git\cmd\git.exe"
        expected_sha256=$digest; observed_sha256=$digest; authenticode_required=$true; authenticode_status="Valid"
        expected_signer_thumbprint=("A" * 40); observed_signer_thumbprint=("A" * 40)
        has_reparse_component=$false; broad_write_acl=$false
    }
    Invoke-Policy "trusted-tool-exact" $tool $true "POLICY-TOOL"
    $badTool = Copy-Fixture $tool; $badTool.path='C:\Program Files\Git\$(calc).exe'
    Invoke-Policy "reject-tool-metachar" $badTool $false "POLICY-TOOL"
    $optionalTool = Copy-Fixture $tool; $optionalTool.path="C:\Program Files (x86)\GnuPG\bin\gpg.exe"; $optionalTool.authenticode_required=$false; $optionalTool.authenticode_status="NotSigned"; $optionalTool.expected_signer_thumbprint=""; $optionalTool.observed_signer_thumbprint=""
    Invoke-Policy "trusted-tool-optional-authenticode" $optionalTool $true "POLICY-TOOL"

    $hostInvocation=[ordered]@{
        schema_version="runner-policy-fixture.v1";case="host-invocation";is_windows=$true
        process_path="C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";expected_process_path="C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        process_path_is_canonical=$true;process_has_reparse=$false;host_name="powershell.exe";argv0_matches=$true;argv_prefix_matches=$true
        no_profile_count=1;non_interactive_count=1;file_count=1;forbidden_switch_count=0;file_target_matches=$true
    }
    Invoke-Policy "canonical-production-host" $hostInvocation $true "POLICY-HOST"
    $missingNoProfile=Copy-Fixture $hostInvocation; $missingNoProfile.no_profile_count=0
    Invoke-Policy "reject-profile-enabled-host" $missingNoProfile $false "POLICY-HOST"
    $encodedCommandHost=Copy-Fixture $hostInvocation; $encodedCommandHost.forbidden_switch_count=1
    Invoke-Policy "reject-command-mode-host" $encodedCommandHost $false "POLICY-HOST"
    $wrongFileTarget=Copy-Fixture $hostInvocation; $wrongFileTarget.file_target_matches=$false
    Invoke-Policy "reject-wrong-runner-file-target" $wrongFileTarget $false "POLICY-HOST"
    $wrongArgv0=Copy-Fixture $hostInvocation; $wrongArgv0.argv0_matches=$false
    Invoke-Policy "reject-host-argv0-mismatch" $wrongArgv0 $false "POLICY-HOST"
    $userPwsh=Copy-Fixture $hostInvocation; $userPwsh.process_path="C:\Users\me\pwsh.exe"; $userPwsh.host_name="pwsh.exe"
    Invoke-Policy "reject-user-controlled-absolute-pwsh" $userPwsh $false "POLICY-HOST"
    $unknownPreFile=Copy-Fixture $hostInvocation; $unknownPreFile.argv_prefix_matches=$false
    Invoke-Policy "reject-unknown-prefile-host-option" $unknownPreFile $false "POLICY-HOST"

    $modulePath=[ordered]@{
        schema_version="runner-policy-fixture.v1"; case="windows-powershell-module-path"
        edition="Desktop"; ps_home="C:\Windows\System32\WindowsPowerShell\v1.0"; windows_directory="C:\Windows"
        current_entries=@(
            "C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.3.0_x64__8wekyb3d8bbwe\Modules",
            "C:\Users\me\Documents\PowerShell\Modules",
            "C:\Users\me\Documents\WindowsPowerShell\Modules",
            "C:\Windows\System32\WindowsPowerShell\v1.0\Modules"
        )
        should_normalize=$true
        expected_safe_paths=@("C:\Windows\System32\WindowsPowerShell\v1.0\Modules")
        expected_normalized_entries=@("C:\Windows\System32\WindowsPowerShell\v1.0\Modules")
        expected_removed_entries=@(
            "C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.3.0_x64__8wekyb3d8bbwe\Modules",
            "C:\Users\me\Documents\PowerShell\Modules",
            "C:\Users\me\Documents\WindowsPowerShell\Modules"
        )
    }
    Invoke-Policy "normalize-desktop-powershell-module-path" $modulePath $true "POLICY-MODULE-PATH"
    $coreModulePath=Copy-Fixture $modulePath; $coreModulePath.edition="Core"; $coreModulePath.should_normalize=$false
    $coreModulePath.expected_safe_paths=@(); $coreModulePath.expected_normalized_entries=$coreModulePath.current_entries; $coreModulePath.expected_removed_entries=@()
    Invoke-Policy "leave-core-powershell-module-path-unhandled" $coreModulePath $true "POLICY-MODULE-PATH"

    $gitConfigIsolation=[ordered]@{
        schema_version="runner-policy-fixture.v1"; case="git-config-isolation"
        raw_system_textconv_present=$true
        safe_system_scope_ignored=$true; safe_global_scope_ignored=$true; safe_local_config_readable=$true
        safe_git_pager_unset=$true; safe_attr_nosystem=$true
        safe_hooks_path="C:\ProgramData\YOnLab\empty-git-hooks"
        unsafe_config_without_safe_env_rejected=$true
        local_executable_config_rejected=$true
    }
    Invoke-Policy "git-config-isolation-safe-system-textconv" $gitConfigIsolation $true "POLICY-GIT-CONFIG"
    $badGitIsolation=Copy-Fixture $gitConfigIsolation; $badGitIsolation.safe_system_scope_ignored=$false
    Invoke-Policy "reject-unisolated-system-config-observation" $badGitIsolation $false "POLICY-GIT-CONFIG"
    $badGitIsolation=Copy-Fixture $gitConfigIsolation; $badGitIsolation.safe_local_config_readable=$false
    Invoke-Policy "reject-local-config-loss" $badGitIsolation $false "POLICY-GIT-CONFIG"
    $badGitIsolation=Copy-Fixture $gitConfigIsolation; $badGitIsolation.safe_hooks_path="C:\attacker\hooks"
    Invoke-Policy "reject-untrusted-hooks-path" $badGitIsolation $false "POLICY-GIT-CONFIG"
    $badGitIsolation=Copy-Fixture $gitConfigIsolation; $badGitIsolation.local_executable_config_rejected=$false
    Invoke-Policy "reject-local-executable-config-acceptance" $badGitIsolation $false "POLICY-GIT-CONFIG"

    $gpgVerification=[ordered]@{
        schema_version="runner-policy-fixture.v1";case="gpg-verification-configuration"
        gpg_conf_relative_path="gpg.conf";gpg_conf_utf8_no_bom=$true;gpg_conf_text="no-auto-check-trustdb`n"
        trustdb_relative_path="trustdb.gpg";trustdb_is_file=$true;trustdb_length=128
        snapshot_before=("a" * 64);snapshot_after=("a" * 64)
    }
    Invoke-Policy "canonical-read-only-gpg-home" $gpgVerification $true "POLICY-GPG"
    $gpgExtraOption=Copy-Fixture $gpgVerification; $gpgExtraOption.gpg_conf_text="no-auto-check-trustdb`nauto-key-retrieve`n"
    Invoke-Policy "reject-extra-gpg-option" $gpgExtraOption $false "POLICY-GPG"
    $gpgMissingTrustdb=Copy-Fixture $gpgVerification; $gpgMissingTrustdb.trustdb_is_file=$false
    Invoke-Policy "reject-missing-preprovisioned-trustdb" $gpgMissingTrustdb $false "POLICY-GPG"
    $gpgMutation=Copy-Fixture $gpgVerification; $gpgMutation.snapshot_after=("b" * 64)
    Invoke-Policy "reject-gpg-home-mutation" $gpgMutation $false "POLICY-GPG"

    $trustedOwners = @("S-1-5-18", "S-1-5-32-544", "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464")
    $protectedPath = [ordered]@{
        schema_version="runner-policy-fixture.v1"; case="protected-path-chain"
        protected_root="C:\ProgramData\YOnLab"
        trusted_owner_sids=$trustedOwners
        nodes=@(
            [ordered]@{path="C:\ProgramData\YOnLab\release-trust.json";scope="PROTECTED_CONTENT";has_reparse_point=$false;owner_sid="S-1-5-32-544";allow_aces=@()},
            [ordered]@{path="C:\ProgramData\YOnLab";scope="PROTECTED_CONTENT";has_reparse_point=$false;owner_sid="S-1-5-18";allow_aces=@()}
        )
    }
    Invoke-Policy "protected-root-chain-exact" $protectedPath $true "POLICY-PROTECTED-PATH"
    $readOnlyRights = [ordered]@{
        "read-data" = 1
        "read-execute" = 1179817
        "synchronize" = 1048576
    }
    foreach ($entry in $readOnlyRights.GetEnumerator()) {
        $readOnlyAce = Copy-Fixture $protectedPath
        $readOnlyAce.nodes[0].allow_aces=@([ordered]@{sid="S-1-5-11";rights=[int64]$entry.Value;inherit_only=$false})
        Invoke-Policy ("allow-untrusted-" + $entry.Key) $readOnlyAce $true "POLICY-PROTECTED-PATH"
    }
    $mutationRights = [ordered]@{
        "write-data" = 2
        "append-data" = 4
        "write-extended-attributes" = 16
        "write-attributes" = 256
        "delete" = 65536
        "delete-child" = 64
        "change-permissions" = 262144
        "take-ownership" = 524288
    }
    foreach ($entry in $mutationRights.GetEnumerator()) {
        $mutationAce = Copy-Fixture $protectedPath
        $mutationAce.nodes[0].allow_aces=@([ordered]@{sid="S-1-5-11";rights=[int64]$entry.Value;inherit_only=$false})
        Invoke-Policy ("reject-untrusted-" + $entry.Key) $mutationAce $false "POLICY-PROTECTED-PATH"
    }
    $badAboveAnchor = Copy-Fixture $protectedPath
    $badAboveAnchor.nodes=@($badAboveAnchor.nodes + [ordered]@{path="C:\ProgramData";scope="PROTECTED_CONTENT";has_reparse_point=$false;owner_sid="S-1-5-18";allow_aces=@()})
    Invoke-Policy "reject-path-above-YOnLab-anchor" $badAboveAnchor $false "POLICY-PROTECTED-PATH"
    $badOwner = Copy-Fixture $protectedPath; $badOwner.nodes[0].owner_sid="S-1-5-21-1000"
    Invoke-Policy "reject-self-owned-protected-leaf" $badOwner $false "POLICY-PROTECTED-PATH"
    $badDeleteChild = Copy-Fixture $protectedPath
    $badDeleteChild.nodes[1].allow_aces=@([ordered]@{sid="S-1-5-21-1000";rights=64;inherit_only=$false})
    Invoke-Policy "reject-anchor-delete-child-write" $badDeleteChild $false "POLICY-PROTECTED-PATH"
    $badLeafWrite = Copy-Fixture $protectedPath
    $badLeafWrite.nodes[0].allow_aces=@([ordered]@{sid="S-1-5-11";rights=2;inherit_only=$false})
    Invoke-Policy "reject-broad-leaf-write" $badLeafWrite $false "POLICY-PROTECTED-PATH"
    $badReparse = Copy-Fixture $protectedPath; $badReparse.nodes[1].has_reparse_point=$true
    Invoke-Policy "reject-protected-root-reparse" $badReparse $false "POLICY-PROTECTED-PATH"
    $inheritedOnly = Copy-Fixture $protectedPath
    $inheritedOnly.nodes[1].allow_aces=@([ordered]@{sid="S-1-5-21-1000";rights=64;inherit_only=$true})
    Invoke-Policy "allow-inherit-only-anchor-ace" $inheritedOnly $true "POLICY-PROTECTED-PATH"
    $badIntermediate = Copy-Fixture $protectedPath
    $badIntermediate.nodes[1].allow_aces=@([ordered]@{sid="S-1-5-11";rights=2;inherit_only=$false})
    Invoke-Policy "reject-intermediate-broad-write" $badIntermediate $false "POLICY-PROTECTED-PATH"

    $protectedSnapshots=[ordered]@{
        schema_version="runner-policy-fixture.v1";case="protected-root-snapshot"
        expected=[ordered]@{release_trust=$digest;git_hooks=$digest;gpg_home=$digest;attestations=$digest}
        actual=[ordered]@{release_trust=$digest;git_hooks=$digest;gpg_home=$digest;attestations=$digest}
    }
    Invoke-Policy "protected-root-snapshot-exact" $protectedSnapshots $true "POLICY-PROTECTED-SNAPSHOT"
    $badTreeBytes=Copy-Fixture $protectedSnapshots; $badTreeBytes.actual.gpg_home=("5" * 64)
    Invoke-Policy "reject-protected-tree-byte-or-sddl-mutation" $badTreeBytes $false "POLICY-PROTECTED-SNAPSHOT"

    $ci = [ordered]@{
        schema_version="runner-policy-fixture.v1"; case="ci-binding"; repository="yubi-lee/yonlab-i-nuri-site"
        release_snapshot_commit=$r; pull_request_number=42; pull_request_base_sha=$s
        run_pull_request_numbers=@(42); check_pull_request_numbers=@(42)
        run_pull_request_base_sha=$s; check_pull_request_base_sha=$s; run_pull_request_head_sha=$r; check_pull_request_head_sha=$r
        workflow_id=9876; expected_workflow_id=9876; workflow_path=".github/workflows/release.yml"
        expected_workflow_path=".github/workflows/release.yml"; base_workflow_sha256=$digest; release_workflow_sha256=$digest; expected_workflow_sha256=$digest
        actor="yonlab-release-bot"; allowed_actors=@("yonlab-release-bot"); event="pull_request"
        status="completed"; conclusion="success"; check_name="design-package-windows"
        expected_check_name="design-package-windows"; runner_labels=@("self-hosted", "Windows", "X64")
        required_runner_labels=@("self-hosted", "Windows", "X64")
    }
    Invoke-Policy "ci-exact-pr-workflow-windows" $ci $true "POLICY-CI"
    $badCi = Copy-Fixture $ci; $badCi.run_pull_request_numbers=@(41)
    Invoke-Policy "reject-ci-from-other-pr" $badCi $false "POLICY-CI"
    $badCiWorkflow = Copy-Fixture $ci; $badCiWorkflow.release_workflow_sha256=("b" * 64)
    Invoke-Policy "reject-ci-workflow-policy-self-claim" $badCiWorkflow $false "POLICY-CI"

    $evidence = [ordered]@{
        schema_version="runner-policy-fixture.v1"; case="evidence-binding"
        registry=@(
            [ordered]@{evidence_id="E1";test_id="T1";gate_ids=@("G1");kpi_ids=@("K1");command_ids=@("C1")},
            [ordered]@{evidence_id="E2";test_id="T2";gate_ids=@("G2");kpi_ids=@("K2");command_ids=@("C2")}
        )
        records=@(
            [ordered]@{evidence_id="E1";test_id="T1";gate_ids=@("G1");kpi_ids=@("K1");command_ids=@("C1")},
            [ordered]@{evidence_id="E2";test_id="T2";gate_ids=@("G2");kpi_ids=@("K2");command_ids=@("C2")}
        )
    }
    Invoke-Policy "evidence-exact-registry" $evidence $true "POLICY-EVIDENCE"
    $badEvidence = Copy-Fixture $evidence; $badEvidence.records=@($evidence.records[0])
    Invoke-Policy "reject-incomplete-evidence" $badEvidence $false "POLICY-EVIDENCE"

    $resume = [ordered]@{
        schema_version="runner-policy-fixture.v1"; case="resume-binding"; run_id="20260714T000000Z-1234abcd"
        requested_run_id="20260714T000000Z-1234abcd"; manifest_run_id="20260714T000000Z-1234abcd"
        state_run_id="20260714T000000Z-1234abcd"; canonical_run_directory="D:\Views\yonlab-inuri-site\.artifacts\codex\20260714T000000Z-1234abcd"
        observed_run_directory="D:\Views\yonlab-inuri-site\.artifacts\codex\20260714T000000Z-1234abcd"
        manifest_sha256=$digest; state_manifest_sha256=$digest; before_inventory_sha256=$digest
        execution_boundary_inventory_sha256=$digest; exact_property_set=$true; exclusive_lock_held=$true
    }
    Invoke-Policy "resume-exact-run-boundary" $resume $true "POLICY-RESUME"
    $badResume = Copy-Fixture $resume; $badResume.manifest_run_id="20260714T000001Z-deadbeef"
    Invoke-Policy "reject-cross-run-resume" $badResume $false "POLICY-RESUME"

    foreach ($name in @("http.extraHeader", "http.sslVerify", "http.sslCert", "http.sslKey", "http.cookieFile", "credential.username")) {
        Invoke-Policy ("reject-git-config-" + $name.Replace('.', '-')) ([ordered]@{schema_version="runner-policy-fixture.v1";case="git-config-name";name=$name;should_be_safe=$false}) $true "POLICY-GIT-CONFIG"
    }

    $state = [ordered]@{schema_version="runner-policy-fixture.v1";case="state-transition";mode="Implement";release_state="NOT_READY";candidate_phase="UNSIGNED_CANDIDATE / REVIEW PENDING";technical_signatures=0;acceptance_signature=$false;signed_tag=$false}
    Invoke-Policy "implement-stops-unsigned" $state $true "POLICY-STATE"
    $badState = Copy-Fixture $state; $badState.release_state="ACCEPTED"
    Invoke-Policy "reject-implement-accepted" $badState $false "POLICY-STATE"

    $tagAbsent = [ordered]@{schema_version="runner-policy-fixture.v1";case="remote-tag-lookup";expectation="ABSENT";exit_code=1;http_status=404}
    Invoke-Policy "remote-tag-exact-404-absence" $tagAbsent $true "POLICY-TAG-LOOKUP"
    $tagNetworkFailure = Copy-Fixture $tagAbsent; $tagNetworkFailure.http_status=503
    Invoke-Policy "reject-remote-tag-network-failure-as-absence" $tagNetworkFailure $false "POLICY-TAG-LOOKUP"
    $tagAuthFailure = Copy-Fixture $tagAbsent; $tagAuthFailure.http_status=401
    Invoke-Policy "reject-remote-tag-auth-failure-as-absence" $tagAuthFailure $false "POLICY-TAG-LOOKUP"

    $bounds = [ordered]@{schema_version="runner-policy-fixture.v1";case="stream-bounds";stdout_bytes=1024;stderr_bytes=1024;total_bytes=2048;maximum_bytes=2048;elapsed_milliseconds=999;timeout_milliseconds=1000}
    $jobIsolation = [ordered]@{
        schema_version="runner-policy-fixture.v1"; case="job-isolation"; access_denied_error_code=5; current_process_in_job=$true
        required_mode="Required"; readonly_mode="BestEffortReadOnly"; disabled_mode="DisabledForPolicySelfTest"
        readonly_probe_command="C:\Program Files\Git\cmd\git.exe"; readonly_probe_arguments=@("--version")
        codex_probe_command="C:\ProgramData\YOnLab\bin\codex.exe"; codex_probe_arguments=@("--version")
        isolation_mode="Required"; command_kind="Implement"; command="C:\ProgramData\YOnLab\bin\codex.exe"; arguments=@("--version")
        assignment_failed=$true; native_job_assignment_attempted=$true; fallback_used=$false
        error_message="AssignProcessToJobObject failed: 5 (Access Denied; nested Job Object; launch from an independent shell)"
    }
    Invoke-Policy "job-isolation-required-fails-closed" $jobIsolation $true "POLICY-JOB"
    $readOnlyJob = Copy-Fixture $jobIsolation
    $readOnlyJob.isolation_mode="BestEffortReadOnly"; $readOnlyJob.command_kind="ReadOnlyProbe"; $readOnlyJob.command=$readOnlyJob.readonly_probe_command; $readOnlyJob.arguments=$readOnlyJob.readonly_probe_arguments; $readOnlyJob.fallback_used=$true
    Invoke-Policy "job-isolation-readonly-allowlisted-fallback" $readOnlyJob $true "POLICY-JOB"
    $unallowlistedReadOnlyJob = Copy-Fixture $readOnlyJob; $unallowlistedReadOnlyJob.command="C:\Program Files\Git\cmd\git.exe"; $unallowlistedReadOnlyJob.arguments=@("push","origin","HEAD")
    Invoke-Policy "job-isolation-readonly-unallowlisted-command-rejected" $unallowlistedReadOnlyJob $false "POLICY-JOB"
    $codexFallbackJob = Copy-Fixture $readOnlyJob; $codexFallbackJob.command_kind="CodexImplement"; $codexFallbackJob.command=$codexFallbackJob.codex_probe_command; $codexFallbackJob.arguments=$codexFallbackJob.codex_probe_arguments
    Invoke-Policy "job-isolation-codex-fallback-rejected" $codexFallbackJob $false "POLICY-JOB"
    $policySelfTestJob = Copy-Fixture $jobIsolation; $policySelfTestJob.isolation_mode="DisabledForPolicySelfTest"; $policySelfTestJob.command_kind="PolicySelfTest"; $policySelfTestJob.command=""; $policySelfTestJob.arguments=@(); $policySelfTestJob.assignment_failed=$false; $policySelfTestJob.native_job_assignment_attempted=$false
    Invoke-Policy "job-isolation-policy-self-test-does-not-assign" $policySelfTestJob $true "POLICY-JOB"
    Invoke-Policy "stream-bound-at-limit" $bounds $true "POLICY-BOUNDS"
    $badBounds = Copy-Fixture $bounds; $badBounds.total_bytes=2049
    Invoke-Policy "reject-stream-overflow" $badBounds $false "POLICY-BOUNDS"
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "PASS: executable adversarial runner policy fixtures"
