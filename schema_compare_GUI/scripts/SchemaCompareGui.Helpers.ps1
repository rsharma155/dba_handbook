# =============================================================================
# Module:   scripts/SchemaCompareGui.Helpers.ps1
# Purpose:  Helper functions shared by the Schema Compare GUI launcher scripts.
# Author:   Ravi Sharma
# Created:  2026-05-22
# Copyright (c) 2026 Ravi Sharma
# SPDX-License-Identifier: MIT
# =============================================================================

#Requires -Version 5.1
<#
.SYNOPSIS
  Shared helpers for the Schema Compare GUI (does not modify schema_compare scripts).
#>
Set-StrictMode -Version Latest

function Get-SchemaCompareGuiRoot {
    <#
      Resolves the install root (folder that contains tools/, schema_compare/, and the .sln).
      Works whether this helpers file lives in scripts/ or at the install root.
    #>
    param([string]$Start = $PSScriptRoot)
    $dir = Get-Item -LiteralPath $Start
    for ($i = 0; $i -lt 8 -and $null -ne $dir; $i++) {
        $bridge = Join-Path $dir.FullName 'tools\Invoke-CompareForGui.ps1'
        $bundled = Join-Path $dir.FullName 'schema_compare\Compare-SqlSchema.ps1'
        $sln = Join-Path $dir.FullName 'SqlOptima.SchemaCompare.sln'
        if ((Test-Path -LiteralPath $bridge) -and ((Test-Path -LiteralPath $bundled) -or (Test-Path -LiteralPath $sln))) {
            return $dir.FullName
        }
        $dir = $dir.Parent
    }
    throw "Cannot locate Schema Compare install root from: $Start"
}

function Get-SchemaCompareRoot {
    <#
      Prefers the engine bundled under the GUI root (schema_compare\).
      Falls back to a sibling folder next to schema_compare_GUI (legacy layout).
    #>
    param([string]$GuiRoot)
    if (-not $GuiRoot) { $GuiRoot = Get-SchemaCompareGuiRoot }

    $bundled = Join-Path $GuiRoot 'schema_compare'
    if (Test-Path (Join-Path $bundled 'Compare-SqlSchema.ps1')) {
        return (Resolve-Path $bundled).Path
    }

    $sibling = Join-Path (Split-Path -Parent $GuiRoot) 'schema_compare'
    if (Test-Path (Join-Path $sibling 'Compare-SqlSchema.ps1')) {
        return (Resolve-Path $sibling).Path
    }

    throw "Cannot find schema_compare\Compare-SqlSchema.ps1 under '$GuiRoot' or next to it."
}

function Get-GuiSettingsPath {
    param([string]$GuiRoot = $PSScriptRoot)
    $dir = Join-Path $GuiRoot 'settings'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return (Join-Path $dir 'last_session.json')
}

function Save-GuiSettings {
    param([hashtable]$Settings, [string]$Path)
    ($Settings | ConvertTo-Json -Depth 6) | Set-Content -Path $Path -Encoding UTF8
}

function Read-GuiSettings {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function New-SqlCredentialFromPlain {
    param([string]$UserName, [string]$Password)
    if ([string]::IsNullOrWhiteSpace($UserName)) { return $null }
    $sec = ConvertTo-SecureString -String $Password -AsPlainText -Force
    return [pscredential]::new($UserName, $sec)
}

function Get-UserDatabasesOnInstance {
    <#
      Lists online user databases via dbatools (same stack as Compare-SqlSchema).
    #>
    param(
        [Parameter(Mandatory)][string]$SqlInstance,
        [int]$Port = 0,
        [string]$NetworkProtocol = 'TcpIp',
        [pscredential]$Credential,
        [switch]$TrustServerCertificate
    )

    if (-not (Get-Module -ListAvailable -Name dbatools)) {
        throw "dbatools is required. Install-Module dbatools -Scope CurrentUser"
    }
    Import-Module dbatools -ErrorAction Stop | Out-Null
    if (Get-Command Set-DbatoolsInsecureConnection -ErrorAction SilentlyContinue) {
        Set-DbatoolsInsecureConnection -SessionOnly | Out-Null
    }

    $resolved = $SqlInstance
    if ($Port -gt 0 -and $SqlInstance -notmatch ',\s*\d+\s*$') {
        $resolved = "$SqlInstance,$Port"
    }

    $connParams = @{
        SqlInstance            = $resolved
        TrustServerCertificate = [bool]$TrustServerCertificate
        ErrorAction            = 'Stop'
    }
    if ($Credential) { $connParams.SqlCredential = $Credential }

    # Network protocol: supported on newer dbatools; ignore if parameter absent.
    $cmd = Get-Command Connect-DbaInstance -ErrorAction Stop
    if ($cmd.Parameters.ContainsKey('NetworkProtocol') -and $NetworkProtocol) {
        $proto = switch ($NetworkProtocol) {
            'Tcp' { 'TcpIp' }
            'Np'  { 'NamedPipes' }
            default { $NetworkProtocol }
        }
        $connParams.NetworkProtocol = $proto
    }

    $server = Connect-DbaInstance @connParams
    $q = @"
SELECT name
FROM sys.databases
WHERE database_id > 4
  AND state_desc = N'ONLINE'
  AND name NOT IN (N'distribution')
ORDER BY name;
"@
    $rows = @(Invoke-DbaQuery -SqlInstance $server -Database master -Query $q -EnableException)
    return @($rows | ForEach-Object { $_.name } | Where-Object { $_ })
}

function Invoke-SchemaCompareFromGui {
    <#
      Calls the existing Compare-SqlSchema.ps1 with a splat. Does not alter that script.
      Returns the script's summary objects. Caller should redirect host output separately if needed.
    #>
    param(
        [Parameter(Mandatory)][string]$CompareScriptPath,
        [Parameter(Mandatory)][hashtable]$Splat
    )
    if (-not (Test-Path -LiteralPath $CompareScriptPath)) {
        throw "Compare script not found: $CompareScriptPath"
    }
    & $CompareScriptPath @Splat
}

function Build-CompareSplatFromGui {
    param(
        [string]$SourceSqlInstance,
        [string]$TargetSqlInstance,
        [string[]]$Database,
        [string[]]$TargetDatabase,
        [string]$TargetDatabaseListFile,
        [pscredential]$SourceCredential,
        [pscredential]$TargetCredential,
        [int]$SourcePort = 0,
        [int]$TargetPort = 0,
        [string]$NetworkProtocol = 'TcpIp',
        [int]$ConnectionTimeout = 30,
        [bool]$TrustServerCertificate = $true,
        [bool]$GenerateSyncScript = $true,
        [bool]$IncludeDrops = $false,
        [bool]$Apply = $false,
        [string]$OutputPath,
        [string[]]$ExcludeSchema,
        [string[]]$IncludeObjectType
    )

    $splat = @{
        SourceSqlInstance      = $SourceSqlInstance
        TargetSqlInstance      = $TargetSqlInstance
        Database               = @($Database)
        NetworkProtocol        = $NetworkProtocol
        ConnectionTimeout      = $ConnectionTimeout
        ReportFormat           = @('Html')  # GUI shows its own log; avoid GridView
        Quiet                  = $false
    }

    if ($SourcePort -gt 0) { $splat.SourcePort = $SourcePort }
    if ($TargetPort -gt 0) { $splat.TargetPort = $TargetPort }
    if ($TrustServerCertificate) { $splat.TrustServerCertificate = $true }
    if ($SourceCredential) { $splat.SourceCredential = $SourceCredential }
    if ($TargetCredential) { $splat.TargetCredential = $TargetCredential }
    if ($GenerateSyncScript) { $splat.GenerateSyncScript = $true }
    if ($IncludeDrops) { $splat.IncludeDrops = $true }
    if ($Apply) {
        $splat.Apply = $true
        $splat.Confirm = $false   # GUI already confirmed
    }
    if ($OutputPath) { $splat.OutputPath = $OutputPath }
    if ($ExcludeSchema -and $ExcludeSchema.Count -gt 0) { $splat.ExcludeSchema = $ExcludeSchema }
    if ($IncludeObjectType -and $IncludeObjectType.Count -gt 0) { $splat.IncludeObjectType = $IncludeObjectType }

    if ($TargetDatabaseListFile) {
        $splat.TargetDatabaseListFile = $TargetDatabaseListFile
    } elseif ($TargetDatabase -and $TargetDatabase.Count -gt 0) {
        $splat.TargetDatabase = @($TargetDatabase)
    }

    return $splat
}
