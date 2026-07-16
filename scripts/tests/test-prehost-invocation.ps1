[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RunnerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$powerShell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$root = Join-Path ([IO.Path]::GetTempPath()) ("yonlab-prehost-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $root | Out-Null

function New-HostFixture($Name, [bool]$Argv0Matches, [int]$ForbiddenSwitchCount = 0) {
    $fixture = [ordered]@{
        schema_version = "runner-policy-fixture.v1"
        case = "host-invocation"
        is_windows = $true
        process_path = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        expected_process_path = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        process_path_is_canonical = $true
        process_has_reparse = $false
        host_name = "powershell.exe"
        argv0_matches = $Argv0Matches
        argv0_is_bare_name = (-not $Argv0Matches)
        argv_prefix_matches = $true
        no_profile_count = 1
        non_interactive_count = 1
        file_count = 1
        forbidden_switch_count = $ForbiddenSwitchCount
        file_target_matches = $true
    }
    $path = Join-Path $root "$Name.json"
    [IO.File]::WriteAllText($path, ($fixture | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding -ArgumentList $false))
    return $path
}

function Invoke-Fixture([string]$FixturePath) {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& $powerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $RunnerPath -Mode PolicySelfTest -PolicyFixture $FixturePath 2>&1)
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

try {
    $canonical = Invoke-Fixture (New-HostFixture "canonical" $true)
    if ($canonical.ExitCode -ne 0 -or $canonical.Output -notmatch "PASS \[POLICY-HOST\]") {
        throw "canonical full-path host should pass: exit=$($canonical.ExitCode) output=$($canonical.Output)"
    }
    Write-Host "PASS: canonical full-path host invocation"

    $bareArgv0 = Invoke-Fixture (New-HostFixture "bare-argv0" $false)
    if ($bareArgv0.ExitCode -ne 0 -or $bareArgv0.Output -notmatch "PASS \[POLICY-HOST\]") {
        throw "bare powershell.exe argv[0] should pass: exit=$($bareArgv0.ExitCode) output=$($bareArgv0.Output)"
    }
    Write-Host "PASS: bare powershell.exe argv[0] invocation"

    $commandMode = Invoke-Fixture (New-HostFixture "command-mode" $false 1)
    if ($commandMode.ExitCode -eq 0 -or $commandMode.Output -notmatch "FAIL \[POLICY-HOST\]") {
        throw "command-mode host should fail closed: exit=$($commandMode.ExitCode) output=$($commandMode.Output)"
    }
    Write-Host "PASS: command-mode host rejected"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "PASS: PRE-HOST invocation fixtures"
