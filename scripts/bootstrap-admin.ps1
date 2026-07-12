param(
    [string]$Email = $env:PRODUCTION_ADMIN_EMAIL,
    [string]$Name = $env:PRODUCTION_ADMIN_NAME,
    [string]$Password = $env:PRODUCTION_ADMIN_INITIAL_PASSWORD,
    [string]$DatabaseUrl = $env:DATABASE_URL
)

$ErrorActionPreference = "Stop"

$pythonPath = ".\.venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $pythonPath)) {
    Write-Host "FAIL: Python virtualenv not found at .\.venv\Scripts\python.exe"
    exit 1
}
$python = (Resolve-Path -LiteralPath $pythonPath).Path

if ([string]::IsNullOrWhiteSpace($Email)) {
    $Email = Read-Host "Production admin email"
}
if ([string]::IsNullOrWhiteSpace($Name)) {
    $Name = "Production Administrator"
}
if ([string]::IsNullOrWhiteSpace($Password)) {
    $secure = Read-Host "Production admin initial password" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

$oldEmail = $env:PRODUCTION_ADMIN_EMAIL
$oldPassword = $env:PRODUCTION_ADMIN_INITIAL_PASSWORD
$oldName = $env:PRODUCTION_ADMIN_NAME
$oldDatabase = $env:DATABASE_URL

try {
    $env:PRODUCTION_ADMIN_EMAIL = $Email
    $env:PRODUCTION_ADMIN_INITIAL_PASSWORD = $Password
    $env:PRODUCTION_ADMIN_NAME = $Name
    if (-not [string]::IsNullOrWhiteSpace($DatabaseUrl)) {
        $env:DATABASE_URL = $DatabaseUrl
    }

    Push-Location backend
    try {
        & $python -m app.admin_bootstrap
        exit $LASTEXITCODE
    } finally {
        Pop-Location
    }
} finally {
    $env:PRODUCTION_ADMIN_EMAIL = $oldEmail
    $env:PRODUCTION_ADMIN_INITIAL_PASSWORD = $oldPassword
    $env:PRODUCTION_ADMIN_NAME = $oldName
    $env:DATABASE_URL = $oldDatabase
    $Password = $null
}
