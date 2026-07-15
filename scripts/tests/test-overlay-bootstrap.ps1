[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$StarterPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$starter = [IO.Path]::GetFullPath($StarterPath)
if (-not (Test-Path -LiteralPath $starter -PathType Leaf)) {
    throw "starter does not exist: $starter"
}

$hostExecutable = $(if ($PSVersionTable.PSEdition -eq "Core") {
    Join-Path $PSHOME "pwsh"
} else {
    Join-Path $PSHOME "powershell.exe"
})
if (-not (Test-Path -LiteralPath $hostExecutable -PathType Leaf)) {
    throw "cannot locate the current PowerShell host executable: $hostExecutable"
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("yonlab-overlay-policy-" + [Guid]::NewGuid().ToString("N"))
$outside = Join-Path ([IO.Path]::GetTempPath()) ("yonlab-overlay-outside-" + [Guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path (Join-Path $root "regular/child") -Force | Out-Null
    New-Item -ItemType Directory -Path $outside -Force | Out-Null

    & $hostExecutable -NoLogo -NoProfile -ExecutionPolicy Bypass -File $starter -PolicySelfTest -PolicyFixturePath (Join-Path $root "regular/child") 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "regular path policy fixture was rejected" }

    $validJson = Join-Path $root "valid.json"
    $duplicateJson = Join-Path $root "duplicate.json"
    [IO.File]::WriteAllText($validJson, '{"schema":"valid"}', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($duplicateJson, '{"owner":"trusted","OWNER":"shadow"}', [Text.UTF8Encoding]::new($false))
    $validOutput = @(& $hostExecutable -NoLogo -NoProfile -ExecutionPolicy Bypass -File $starter -PolicySelfTest -PolicyFixturePath $validJson 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0 -or ($validOutput -join "`n") -notmatch 'PASS \[POLICY-STRICT-JSON\]') { throw "valid strict JSON fixture was rejected" }
    $duplicateOutput = @(& $hostExecutable -NoLogo -NoProfile -ExecutionPolicy Bypass -File $starter -PolicySelfTest -PolicyFixturePath $duplicateJson 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -eq 0 -or ($duplicateOutput -join "`n") -notmatch 'FAIL \[PRE-TRUST-JSON\]') { throw "duplicate/case-ambiguous JSON property was not rejected" }

    $redirect = Join-Path $root "redirect"
    if ($PSVersionTable.PSEdition -eq "Desktop" -or [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        New-Item -ItemType Junction -Path $redirect -Target $outside | Out-Null
    } else {
        New-Item -ItemType SymbolicLink -Path $redirect -Target $outside | Out-Null
    }
    $output = @(& $hostExecutable -NoLogo -NoProfile -ExecutionPolicy Bypass -File $starter -PolicySelfTest -PolicyFixturePath (Join-Path $redirect "escaped") 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -eq 0 -or ($output -join "`n") -notmatch 'FAIL \[POLICY-REPARSE\]') {
        throw "junction/symlink policy fixture was not rejected with POLICY-REPARSE"
    }

    Write-Host "PASS: overlay bootstrap rejects a reparse ancestor and duplicate trust JSON before backup/receipt writes"
    Write-Host "RESULT: PASS"
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outside -Recurse -Force -ErrorAction SilentlyContinue
}
