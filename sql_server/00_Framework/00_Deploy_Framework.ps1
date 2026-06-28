<#
.SYNOPSIS
    Deploy all DBA framework objects from 00_Framework to a SQL Server database.
.DESCRIPTION
    Runs every .sql file in 00_Framework in sorted order using sqlcmd.
    No xp_cmdshell required.
.PARAMETER ServerInstance
    Target SQL Server instance (default: .\)
.PARAMETER Database
    Target database name (default: master)
.PARAMETER FrameworkDir
    Path to the 00_Framework directory
.EXAMPLE
    .\00_Deploy_Framework.ps1
    .\00_Deploy_Framework.ps1 -ServerInstance "SQL2019" -Database "DBAAdmin"
#>

param(
    [string]$ServerInstance = ".",
    [string]$Database       = "master",
    [string]$FrameworkDir   = "C:\Users\Admin\Documents\dba_essential_scripts\dba_essential_scripts\00_Framework"
)

$ErrorActionPreference = "Stop"
$exclude = @("00_Install_Framework.sql", "00_Deploy_Framework.sql", "00_Deploy_Framework.ps1", "README.md")

Write-Host "=== Deploying 00_Framework to [$ServerInstance].[$Database] ===" -ForegroundColor Cyan

Get-ChildItem -Path $FrameworkDir -Filter "*.sql" | Where-Object {
    $_.Name -notin $exclude
} | Sort-Object Name | ForEach-Object {
    Write-Host "  Deploying: $($_.Name) ... " -NoNewline
    try {
        $output = sqlcmd -S $ServerInstance -E -d $Database -i $_.FullName -b 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host "FAILED" -ForegroundColor Red
            Write-Host $output -ForegroundColor Red
        }
    } catch {
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host $_ -ForegroundColor Red
    }
}

Write-Host "=== Deployment complete ===" -ForegroundColor Cyan
