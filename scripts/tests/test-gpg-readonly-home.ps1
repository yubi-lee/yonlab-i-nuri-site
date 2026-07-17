[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RunnerPath,
    [Parameter(Mandatory = $true)][string]$GpgPath,
    [Parameter(Mandatory = $true)][string]$SourceGpgHome
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-HomeSnapshot([string]$GpgDirectory) {
    $root = [IO.Path]::GetFullPath($GpgDirectory).TrimEnd('\')
    $entries = @(
        Get-ChildItem -LiteralPath $root -File -Recurse -Force |
            Sort-Object FullName |
            ForEach-Object {
                [ordered]@{
                    path = $_.FullName.Substring($root.Length).TrimStart('\')
                    length = $_.Length
                    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
                }
            }
    )
    return ($entries | ConvertTo-Json -Compress)
}

function Invoke-ReadOnlyGpg([string[]]$Arguments, [string]$Description) {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $GpgPath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "$Description failed, exit=$exitCode output=$($output -join ' | ')"
    }
}

$runnerText = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $RunnerPath))
$expectedPrefix = '@("--homedir", $ProtectedGpgHome, "--no-options", "--no-auto-key-retrieve", "--no-auto-check-trustdb", "--no-autostart", "--lock-never", "--batch", "--no-tty")'
if (-not $runnerText.Contains($expectedPrefix)) {
    throw "TrustedGpg must prevent automatic GnuPG agent state for the immutable verification-only home"
}

if (-not (Test-Path -LiteralPath $GpgPath -PathType Leaf)) {
    throw "GPG executable does not exist: $GpgPath"
}
foreach ($name in @("gpg.conf", "pubring.kbx", "trustdb.gpg")) {
    $source = Join-Path $SourceGpgHome $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required public-only GPG fixture is missing: $source"
    }
}

$testHome = Join-Path ([IO.Path]::GetTempPath()) ("yonlab-gpg-readonly-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testHome | Out-Null
try {
    foreach ($name in @("gpg.conf", "pubring.kbx", "trustdb.gpg")) {
        Copy-Item -LiteralPath (Join-Path $SourceGpgHome $name) -Destination (Join-Path $testHome $name)
    }

    $before = Get-HomeSnapshot $testHome
    $prefix = @(
        "--homedir", $testHome,
        "--no-options",
        "--no-auto-key-retrieve",
        "--no-auto-check-trustdb",
        "--no-autostart",
        "--lock-never",
        "--batch",
        "--no-tty"
    )
    Invoke-ReadOnlyGpg ($prefix + @("--version")) "GnuPG version probe"
    Invoke-ReadOnlyGpg ($prefix + @("--with-colons", "--fingerprint", "--list-keys")) "GnuPG public-key inventory"
    Invoke-ReadOnlyGpg ($prefix + @("--with-colons", "--list-secret-keys")) "GnuPG secret-key absence probe"

    $locks = @(Get-ChildItem -LiteralPath $testHome -Filter "*.lock" -File -Recurse -Force)
    if ($locks.Count -ne 0) {
        throw "Read-only GPG probes created lock files"
    }
    $after = Get-HomeSnapshot $testHome
    if ($before -cne $after) {
        throw "Read-only GPG probes mutated the disposable public-only home"
    }
    Write-Host "PASS: immutable public-only GPG home remains byte-for-byte unchanged"
} finally {
    Remove-Item -LiteralPath $testHome -Recurse -Force -ErrorAction SilentlyContinue
}
