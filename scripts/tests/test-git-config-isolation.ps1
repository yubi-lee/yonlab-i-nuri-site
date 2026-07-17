[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Stop-Launcher([string]$Code, [string]$Message, [int]$ExitCode = 2) { throw ($Code + "/" + $ExitCode + ": " + $Message) }

$runner = Join-Path (Split-Path -Parent $PSScriptRoot) "invoke-ai-training-platform-v1.ps1"
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw "runner parse failed" }

foreach ($name in @("Quote-WindowsArgument", "Set-SafeProcessEnvironment", "Get-SafeGitArguments", "Get-ForbiddenExecutionEnvironmentNames", "Assert-NoExecutionEnvironmentOverrides", "Test-UnsafeGitConfigName", "Assert-SafeGitConfigScopeNameFields")) {
    $functionAst = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name }, $true)
    if ($null -eq $functionAst) { throw "missing function $name" }
    . ([scriptblock]::Create($functionAst.Extent.Text))
}

$ProtectedGpgHome = "C:\ProgramData\YOnLab\gnupg"
$ProtectedHooksPath = "C:\ProgramData\YOnLab\empty-git-hooks"
$script:GitHubCredentialHelper = '!"C:/Program Files/GitHub CLI/gh.exe" auth git-credential'
$root = "D:\Views\yonlab-inuri-site"
$git = "C:\Program Files\Git\cmd\git.exe"
if (-not (Test-Path -LiteralPath $git -PathType Leaf)) { throw "trusted Git fixture executable is missing" }

$gitArguments = @(Get-SafeGitArguments @("-C", $root, "config", "--null", "--name-only", "--show-scope", "--list"))
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $git
$psi.Arguments = (($gitArguments | ForEach-Object { Quote-WindowsArgument ([string]$_) }) -join " ")
$psi.WorkingDirectory = "C:\Program Files\Git\cmd"
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables["GIT_PAGER"] = "attacker-pager"
$psi.EnvironmentVariables["GIT_CONFIG_SYSTEM"] = "attacker-system"
$psi.EnvironmentVariables["GIT_CONFIG_GLOBAL"] = "attacker-global"
$psi.EnvironmentVariables["GIT_CONFIG_NOSYSTEM"] = "0"
$psi.EnvironmentVariables["GIT_ATTR_NOSYSTEM"] = "0"
$psi.EnvironmentVariables["GIT_CONFIG_COUNT"] = "7"
$psi.EnvironmentVariables["GIT_CONFIG_KEY_99"] = "attacker-key"
$psi.EnvironmentVariables["GIT_CONFIG_VALUE_99"] = "attacker-value"
Set-SafeProcessEnvironment $psi
if ($psi.EnvironmentVariables["GIT_PAGER"] -ne $null -or
    $psi.EnvironmentVariables["GIT_CONFIG_NOSYSTEM"] -cne "1" -or
    $psi.EnvironmentVariables["GIT_CONFIG_GLOBAL"] -cne "NUL" -or
    $psi.EnvironmentVariables["GIT_CONFIG_SYSTEM"] -cne "NUL" -or
    $psi.EnvironmentVariables["GIT_ATTR_NOSYSTEM"] -cne "1" -or
    $psi.EnvironmentVariables["GIT_CONFIG_COUNT"] -cne "1" -or
    $psi.EnvironmentVariables["GIT_CONFIG_KEY_99"] -ne $null -or
    $psi.EnvironmentVariables["GIT_CONFIG_VALUE_99"] -ne $null) { throw "child Git environment was not isolated" }

$process = New-Object Diagnostics.Process
$process.StartInfo = $psi
if (-not $process.Start()) { throw "Git isolation probe did not start" }
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw "Git isolation probe failed with exit code $($process.ExitCode)" }
$fields = @(([string]$stdout) -split [char]0 | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$pairs = @()
for ($index = 0; $index -lt $fields.Count; $index += 2) {
    if ($index + 1 -ge $fields.Count) { throw "Git isolation probe returned malformed name inventory" }
    $pairs += ([string]$fields[$index] + ":" + [string]$fields[$index + 1])
}
if (@($pairs | Where-Object { $_ -like "system:*" }).Count -ne 0 -or @($pairs | Where-Object { $_ -like "global:*" }).Count -ne 0) { throw "safe Git environment exposed system/global config" }
if ($pairs -contains "system:diff.astextplain.textconv" -or $pairs -notcontains "local:core.repositoryformatversion") { throw "safe Git environment did not hide system textconv while retaining local config" }
if ($gitArguments -notcontains "core.hooksPath=C:\ProgramData\YOnLab\empty-git-hooks") { throw "safe Git arguments did not pin empty hooks path" }
Assert-SafeGitConfigScopeNameFields $fields
$unsafeSystemRejected = $false
try { Assert-SafeGitConfigScopeNameFields (@("system", "diff.astextplain.textconv") + $fields) } catch { $unsafeSystemRejected = $true }
if (-not $unsafeSystemRejected) { throw "raw system textconv fixture was accepted without isolation" }
$unsafeLocalRejected = $false
try { Assert-SafeGitConfigScopeNameFields (@("local", "filter.evil.process") + $fields) } catch { $unsafeLocalRejected = $true }
if (-not $unsafeLocalRejected) { throw "local executable filter fixture was accepted" }

$savedPager = $env:GIT_PAGER
try {
    $env:GIT_PAGER = "attacker-pager"
    $pagerRejected = $false
    try { Assert-NoExecutionEnvironmentOverrides } catch { $pagerRejected = $true }
    if (-not $pagerRejected) { throw "ambient GIT_PAGER fixture was accepted" }
} finally {
    $env:GIT_PAGER = $savedPager
}

Write-Host "PASS: Git system/global isolation hides textconv, preserves local config, fixes hooks, and rejects executable fixtures"
