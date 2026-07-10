#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnose SQL Server connectivity before running Compare-SqlSchema.ps1.
.EXAMPLE
    .\Test-SqlSchemaConnection.ps1 -SqlInstance .
    .\Test-SqlSchemaConnection.ps1 -SqlInstance 192.168.10.200 -Port 1433
    .\Test-SqlSchemaConnection.ps1 -SqlInstance . -NetworkProtocol NamedPipes -Database ERP_System
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SqlInstance,
    [int]    $Port = 0,
    [string] $Database = 'master',
    [pscredential] $Credential,
    [ValidateSet('TcpIp','NamedPipes','SharedMemory','Tcp','Np')]
    [string] $NetworkProtocol = 'TcpIp',
    [switch] $TrustServerCertificate
)

$ErrorActionPreference = 'Continue'

function Write-Step { param($Msg, $Color = 'Gray') Write-Host $Msg -ForegroundColor $Color }

function Resolve-NetworkProtocol {
    param([string]$Protocol)
    switch ($Protocol) {
        'Tcp' { return 'TcpIp' }
        'Np'  { return 'NamedPipes' }
        default { return $Protocol }
    }
}

function Format-Address {
    param([string]$Instance, [int]$Port)
    if ($Port -le 0) { return $Instance }
    if ($Instance -match ',\s*\d+\s*$') { return $Instance }
    return "$Instance,$Port"
}

$protocol = Resolve-NetworkProtocol $NetworkProtocol
$resolved = Format-Address -Instance $SqlInstance -Port $Port
$trustCert = $TrustServerCertificate -or -not $PSBoundParameters.ContainsKey('TrustServerCertificate')

Write-Step "=== SQL Connection Diagnostic ===" Cyan
Write-Step "Instance  : $SqlInstance  ->  $resolved" Gray
Write-Step "Protocol  : $protocol" Gray
Write-Step "Database  : $Database" Gray
Write-Step "TrustCert : $trustCert" Gray
Write-Step "" Gray

# 1) Local SQL services
Write-Step "[1] SQL Server services on this machine:" Yellow
Get-Service -Name 'MSSQL*','SQLBrowser' -ErrorAction SilentlyContinue |
    Select-Object Name, Status, DisplayName |
    Format-Table -AutoSize | Out-String | Write-Host

# 2) Registered instances
Write-Step "[2] Installed instances (registry):" Yellow
$regPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
if (Test-Path $regPath) {
    Get-ItemProperty $regPath | Format-List | Out-String | Write-Host
} else {
    Write-Step "  (no instances found in registry on this machine)" DarkYellow
}

# 3) TCP port test (only meaningful for TcpIp)
$hostPart = ($SqlInstance -split '\\')[0] -replace ',\d+$', ''
if ($hostPart -in @('.', 'localhost', '(local)', '127.0.0.1', '')) { $hostPart = 'localhost' }
$testPort = if ($Port -gt 0) { $Port } elseif ($SqlInstance -match ',(\d+)\s*$') { [int]$Matches[1] } else { 1433 }

if ($protocol -eq 'TcpIp') {
    Write-Step "[3] TCP test ${hostPart}:$testPort ..." Yellow
    try {
        $tcp = Test-NetConnection -ComputerName $hostPart -Port $testPort -WarningAction SilentlyContinue
        if ($tcp.TcpTestSucceeded) {
            Write-Step "  TCP port $testPort is OPEN on $hostPart" Green
        } else {
            Write-Step "  TCP port $testPort is CLOSED or filtered on $hostPart" Red
            Write-Step "  -> Enable TCP/IP in SQL Server Configuration Manager and restart MSSQLSERVER" DarkYellow
            Write-Step "  -> OR retry with: -NetworkProtocol NamedPipes -SqlInstance ." DarkYellow
        }
    } catch {
        Write-Step "  TCP test skipped: $($_.Exception.Message)" DarkYellow
    }
} else {
    Write-Step "[3] TCP test skipped (using $protocol)" Gray
}

# 4) sqlcmd probe
Write-Step "[4] sqlcmd probe to '$resolved' ..." Yellow
if (Get-Command sqlcmd -ErrorAction SilentlyContinue) {
    # -C = trust server certificate (ODBC Driver 18+); -N = encrypt connection
    $sqlArgs = @('-S', $resolved, '-d', $Database, '-Q', 'SET NOCOUNT ON; SELECT @@SERVERNAME, DB_NAME()', '-W', '-h-1')
    if ($trustCert) { $sqlArgs += '-C' }
    if ($Credential) {
        $sqlArgs += @('-U', $Credential.UserName, '-P', $Credential.GetNetworkCredential().Password)
    } else {
        $sqlArgs += '-E'
    }
    $sqlOut = & sqlcmd @sqlArgs 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Step "  sqlcmd OK: $sqlOut" Green
    } else {
        Write-Step "  sqlcmd FAILED:" Red
        $sqlOut | ForEach-Object { Write-Step "    $_" Red }
        if ($sqlOut -match 'certificate|SSL|encryption') {
            Write-Step "  -> Retry is automatic with TrustServerCertificate (ODBC -C flag)" DarkYellow
        }
    }
} else {
    Write-Step "  sqlcmd not found on PATH (skipping)" DarkYellow
}

# 5) dbatools / SMO probe
Write-Step "[5] dbatools Connect-DbaInstance probe ($protocol) ..." Yellow
if (-not (Get-Module -ListAvailable -Name dbatools)) {
    Write-Step "  dbatools not installed. Run: Install-Module dbatools -Scope CurrentUser" Red
    exit 1
}
Import-Module dbatools -ErrorAction Stop | Out-Null
if (Get-Command Set-DbatoolsInsecureConnection -ErrorAction SilentlyContinue) {
    Set-DbatoolsInsecureConnection -SessionOnly | Out-Null
}

$splat = @{
    SqlInstance     = $resolved
    ErrorAction     = 'Stop'
    NetworkProtocol = $protocol
}
if ($Credential) { $splat.SqlCredential = $Credential }
$append = @('Connect Timeout=15', 'Encrypt=Optional')
if ($trustCert) { $append += 'TrustServerCertificate=True' }
$splat.AppendConnectionString = ($append -join ';')

$connected = $false
try {
    $srv = Connect-DbaInstance @splat
    $db  = Get-DbaDatabase -SqlInstance $srv -Database $Database -ErrorAction SilentlyContinue
    Write-Step "  Connected: $($srv.Name)  ($($srv.VersionString))" Green
    if ($db) { Write-Step "  Database '$Database' found." Green }
    else     { Write-Step "  Database '$Database' NOT found (connection OK)." DarkYellow }
    $connected = $true
} catch {
    Write-Step "  Connect-DbaInstance FAILED ($protocol):" Red
    Write-Step "  $($_.Exception.Message)" Red
}

# 6) Fallback: Named Pipes for local default instance when TcpIp fails
if (-not $connected -and $protocol -eq 'TcpIp' -and $SqlInstance -match '^(\.|localhost|\(local\)|127\.0\.0\.1)(\\MSSQLSERVER)?$') {
    Write-Step "[6] Fallback probe via NamedPipes ..." Yellow
    try {
        $splat.NetworkProtocol = 'NamedPipes'
        $splat.SqlInstance = '.'
        $srv = Connect-DbaInstance @splat
        Write-Step "  NamedPipes OK: $($srv.Name)  ($($srv.VersionString))" Green
        Write-Step "  Use for Compare-SqlSchema:  -SourceSqlInstance . -NetworkProtocol NamedPipes" Cyan
        $connected = $true
    } catch {
        Write-Step "  NamedPipes also failed: $($_.Exception.Message)" Red
    }
}

if (-not $connected) {
    Write-Step "" Gray
    Write-Step "Common fixes:" Cyan
    Write-Step "  * Local default instance:  -SqlInstance .  -NetworkProtocol NamedPipes" Gray
    Write-Step "  * Enable TCP/IP: SQL Server Configuration Manager -> restart MSSQLSERVER" Gray
    Write-Step "  * Remote IP:  -SqlInstance 192.168.10.200 -Port 1433 -NetworkProtocol TcpIp" Gray
    exit 1
}

Write-Step "" Gray
Write-Step "=== Diagnostic complete ===" Green
