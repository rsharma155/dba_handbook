# Authenticode-sign DBA-Console.exe (optional — requires a code signing certificate).
#
# Set environment variables before running:
#   DBA_SIGN_PFX          Path to .pfx certificate file
#   DBA_SIGN_PFX_PASSWORD Certificate password
#
# Or use a certificate from the Windows store:
#   DBA_SIGN_THUMBPRINT   SHA1 thumbprint of cert in CurrentUser\My
#
# Example:
#   $env:DBA_SIGN_PFX = "C:\certs\sqoptima.pfx"
#   $env:DBA_SIGN_PFX_PASSWORD = "secret"
#   .\sign-windows.ps1 -ExePath ..\dist\DBA-Console.exe

param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ExePath)) {
    Write-Error "File not found: $ExePath"
}

$Signtool = Get-Command signtool.exe -ErrorAction SilentlyContinue
if (-not $Signtool) {
  $SdkSigntool = "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe"
  $Signtool = Get-Item $SdkSigntool -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
}
if (-not $Signtool) {
    Write-Error "signtool.exe not found. Install Windows SDK or Visual Studio Build Tools."
}

$Timestamp = "http://timestamp.digicert.com"

if ($env:DBA_SIGN_THUMBPRINT) {
    Write-Host "Signing with certificate thumbprint $env:DBA_SIGN_THUMBPRINT"
    & $Signtool.Source sign /sha1 $env:DBA_SIGN_THUMBPRINT /fd SHA256 /tr $Timestamp /td SHA256 $ExePath
}
elseif ($env:DBA_SIGN_PFX) {
    if (-not (Test-Path $env:DBA_SIGN_PFX)) {
        Write-Error "PFX not found: $env:DBA_SIGN_PFX"
    }
    $pass = $env:DBA_SIGN_PFX_PASSWORD
    if (-not $pass) {
        Write-Error "Set DBA_SIGN_PFX_PASSWORD"
    }
    Write-Host "Signing with PFX $env:DBA_SIGN_PFX"
    & $Signtool.Source sign /f $env:DBA_SIGN_PFX /p $pass /fd SHA256 /tr $Timestamp /td SHA256 $ExePath
}
else {
    Write-Host "Skipping code signing — set DBA_SIGN_PFX or DBA_SIGN_THUMBPRINT to sign."
    Write-Host "Unsigned builds may trigger SmartScreen on first run (click More info -> Run anyway)."
    exit 0
}

Write-Host "Verifying signature…"
& $Signtool.Source verify /pa $ExePath
Write-Host "Signed: $ExePath"
