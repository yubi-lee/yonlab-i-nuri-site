[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RunnerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$source = Get-Content -LiteralPath $RunnerPath -Raw

foreach ($required in @(
    '$hostStartupArgumentsValid'
    '-NoLogo'
    '-NoProfile'
    '-NonInteractive'
    '-ExecutionPolicy'
    'Bypass'
    '-File'
    '-PSConsoleFile'
    '-Version'
)) {
    if ($source -notlike "*$required*") {
        throw "PRE-HOST command-shape contract missing: $required"
    }
}

if ($source -like '*$expectedPrefix=@($expectedProcessPath,*') {
    throw "PRE-HOST still requires a fixed argv prefix instead of parsing allowed startup switches"
}

Write-Host "PASS: PRE-HOST command-shape contract"
