# =============================================================================
# Module:   tools/Invoke-CompareForGui.ps1
# Purpose:  Bridge script invoked by the GUI to run the schema_compare PowerShell engine and emit structured results.
# Author:   Ravi Sharma
# Created:  2026-05-22
# Copyright (c) 2026 Ravi Sharma
# SPDX-License-Identifier: MIT
# =============================================================================

#Requires -Version 5.1
<#
.SYNOPSIS
  Bridge for the SqlOptima Schema Compare desktop app.
  Calls the existing schema_compare\Compare-SqlSchema.ps1 and writes result JSON.
  Does not modify the compare engine.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RequestPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Avoid VT/ANSI color sequences in GUI log parsing (PowerShell 7+).
if ($PSVersionTable.PSVersion.Major -ge 7) {
    try { $PSStyle.OutputRendering = 'PlainText' } catch { }
}

function Write-GuiLog([string]$Message) {
    # Plain text only — no Write-Host colors (keeps GUI log parser clean).
    Write-Output $Message
}

function Get-ObjectCount {
    param($InputObject)
    if ($null -eq $InputObject) { return 0 }
    if ($InputObject -is [string]) { return 1 }
    if ($InputObject -is [System.Collections.ICollection]) { return [int]$InputObject.Count }
    return @($InputObject).Count
}

if (-not (Test-Path -LiteralPath $RequestPath)) {
    throw "Request file not found: $RequestPath"
}

$req = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
$compareScript = [string]$req.CompareScript
if (-not (Test-Path -LiteralPath $compareScript)) {
    throw "Compare script not found: $compareScript"
}

$srcPwd = $env:SCHEMA_COMPARE_SRC_PWD
$tgtPwd = $env:SCHEMA_COMPARE_TGT_PWD
Remove-Item Env:SCHEMA_COMPARE_SRC_PWD -ErrorAction SilentlyContinue
Remove-Item Env:SCHEMA_COMPARE_TGT_PWD -ErrorAction SilentlyContinue

$splat = @{
    SourceSqlInstance = [string]$req.SourceSqlInstance
    TargetSqlInstance = [string]$req.TargetSqlInstance
    Database          = @([string]$req.SourceDatabase)
    NetworkProtocol   = [string]$req.NetworkProtocol
    ConnectionTimeout = [int]$req.ConnectionTimeout
    ReportFormat      = @('Html')
}

if ([int]$req.SourcePort -gt 0) { $splat.SourcePort = [int]$req.SourcePort }
if ([int]$req.TargetPort -gt 0) { $splat.TargetPort = [int]$req.TargetPort }
if ([bool]$req.TrustServerCertificate) { $splat.TrustServerCertificate = $true }
if ([bool]$req.GenerateSyncScript) { $splat.GenerateSyncScript = $true }
if ([bool]$req.IncludeDrops) { $splat.IncludeDrops = $true }
if ([bool]$req.Apply) { $splat.Apply = $true; $splat.Confirm = $false }
if ($req.OutputPath) { $splat.OutputPath = [string]$req.OutputPath }
if ($req.ExcludeSchema) { $splat.ExcludeSchema = @($req.ExcludeSchema) }

$tgtList = @()
if ($req.PSObject.Properties['TargetDatabases'] -and $req.TargetDatabases) {
    $tgtList = @($req.TargetDatabases | ForEach-Object { [string]$_ } | Where-Object { $_ })
}
$listFile = $null
if ($req.PSObject.Properties['TargetDatabaseListFile'] -and $req.TargetDatabaseListFile) {
    $listFile = [string]$req.TargetDatabaseListFile
}

$mode = [string]$req.Mode
if ($listFile) {
    $splat.TargetDatabaseListFile = $listFile
} elseif ((Get-ObjectCount $tgtList) -gt 0) {
    if ($mode -eq 'OneToMany' -or (Get-ObjectCount $tgtList) -gt 1) {
        $splat.TargetDatabase = $tgtList
    } elseif ($tgtList[0] -ne [string]$req.SourceDatabase) {
        $splat.TargetDatabase = @($tgtList[0])
    }
}

if ([string]$req.SourceAuth -eq 'Sql') {
    if (-not $srcPwd) { throw 'Source SQL auth requires password (SCHEMA_COMPARE_SRC_PWD).' }
    $sec = ConvertTo-SecureString $srcPwd -AsPlainText -Force
    $splat.SourceCredential = [pscredential]::new([string]$req.SourceUser, $sec)
}
if ([string]$req.TargetAuth -eq 'Sql') {
    if (-not $tgtPwd) { throw 'Target SQL auth requires password (SCHEMA_COMPARE_TGT_PWD).' }
    $sec = ConvertTo-SecureString $tgtPwd -AsPlainText -Force
    $splat.TargetCredential = [pscredential]::new([string]$req.TargetUser, $sec)
}

Write-GuiLog "Invoking Compare-SqlSchema.ps1 ..."
Write-GuiLog "Source: $($splat.SourceSqlInstance) / $($req.SourceDatabase)"
Write-GuiLog "Target: $($splat.TargetSqlInstance)"

# Always wrap: a single summary PSCustomObject must become a 1-element array.
# Filter to summary-shaped objects in case host noise reaches the pipeline.
$rawOutput = @(& $compareScript @splat)
$summaries = @(
    $rawOutput | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties['Database'] -and
        $_.PSObject.Properties['DifferenceCount']
    }
)

$payload = [ordered]@{
    Summaries    = @()
    ReportPath   = $null
    RunFolder    = $null
    ManifestPath = $null
}

foreach ($s in $summaries) {
    $diffs = @()
    if ($s.PSObject.Properties['Differences'] -and $null -ne $s.Differences) {
        foreach ($d in @($s.Differences)) {
            if ($null -eq $d) { continue }
            $diffs += [ordered]@{
                Database   = [string]$d.Database
                ObjectType = [string]$d.ObjectType
                ObjectName = [string]$d.ObjectName
                Status     = [string]$d.Status
                Details    = [string]$d.Details
            }
        }
    }

    $failed = @()
    if ($s.PSObject.Properties['FailedScripts'] -and $null -ne $s.FailedScripts) {
        foreach ($fs in @($s.FailedScripts)) {
            if ($null -eq $fs) { continue }
            $failed += [ordered]@{
                FileName = [string]$fs.FileName
                Error    = [string]$fs.Error
            }
        }
    }

    $entry = [ordered]@{
        Database        = [string]$s.Database
        TargetDatabase  = [string]$s.TargetDatabase
        DifferenceCount = [int](Get-ObjectCount $diffs)
        AutoScripts     = [int]$s.AutoScripts
        ManualScripts   = [int]$s.ManualScripts
        ScriptFolder    = if ($s.PSObject.Properties['ScriptFolder'] -and $s.ScriptFolder) { [string]$s.ScriptFolder } else { $null }
        ReportPath      = if ($s.PSObject.Properties['ReportPath'] -and $s.ReportPath) { [string]$s.ReportPath } else { $null }
        Differences     = $diffs
        Applied         = if ($s.PSObject.Properties['Applied']) { [bool]$s.Applied } else { $false }
        ApplyStatus     = if ($s.PSObject.Properties['ApplyStatus'] -and $s.ApplyStatus) { [string]$s.ApplyStatus } else { 'Skipped' }
        AppliedCount    = if ($s.PSObject.Properties['AppliedCount']) { [int]$s.AppliedCount } else { 0 }
        FailedCount     = if ($s.PSObject.Properties['FailedCount']) { [int]$s.FailedCount } else { 0 }
        FailedScripts   = $failed
        VerifyStatus    = if ($s.PSObject.Properties['VerifyStatus'] -and $s.VerifyStatus) { [string]$s.VerifyStatus } else { 'NotVerified' }
        RemainingDiffs  = if ($s.PSObject.Properties['RemainingDiffs']) { [int]$s.RemainingDiffs } else { -1 }
    }
    # Prefer engine-reported count when present (keeps parity if diffs were trimmed).
    if ($s.PSObject.Properties['DifferenceCount'] -and $null -ne $s.DifferenceCount) {
        $entry.DifferenceCount = [int]$s.DifferenceCount
    }
    $payload.Summaries += $entry

    if ($entry.ReportPath -and -not $payload.ReportPath) { $payload.ReportPath = $entry.ReportPath }
    if ($entry.ScriptFolder) {
        $folder = $entry.ScriptFolder
        $parent = Split-Path -Parent $folder
        if ((Split-Path -Leaf $parent) -like 'SchemaSync_*') {
            $payload.RunFolder = $parent
        } elseif (-not $payload.RunFolder) {
            $payload.RunFolder = $folder
        }
    }
}

# Zero-diff / empty return: still write a valid GUI payload (do not throw).
if ((Get-ObjectCount $payload.Summaries) -eq 0) {
    Write-GuiLog "No summary objects returned; writing zero-diff placeholder for source database."
    $srcDb = [string]$req.SourceDatabase
    $tgtDb = $srcDb
    if ((Get-ObjectCount $tgtList) -gt 0) { $tgtDb = [string]$tgtList[0] }
    $payload.Summaries += [ordered]@{
        Database        = $srcDb
        TargetDatabase  = $tgtDb
        DifferenceCount = 0
        AutoScripts     = 0
        ManualScripts   = 0
        ScriptFolder    = if ($req.OutputPath) { [string]$req.OutputPath } else { $null }
        ReportPath      = $null
        Differences     = @()
        Applied         = $false
        ApplyStatus     = 'Skipped'
        AppliedCount    = 0
        FailedCount     = 0
        FailedScripts   = @()
        VerifyStatus    = 'NotVerified'
        RemainingDiffs  = -1
    }
}

if ($payload.RunFolder) {
    $manifest = Join-Path $payload.RunFolder '_manifest.csv'
    if (Test-Path -LiteralPath $manifest) { $payload.ManifestPath = $manifest }
}

$resultPath = [string]$req.ResultJsonPath
$summaryList = @($payload.Summaries)

# Serialize with Summaries always as a JSON array (PS 5.1 unwraps single-element arrays).
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $sumParts = foreach ($item in $summaryList) { $item | ConvertTo-Json -Depth 8 }
    if ((Get-ObjectCount $sumParts) -eq 0) {
        $summariesJson = '[]'
    } elseif ((Get-ObjectCount $sumParts) -eq 1) {
        $summariesJson = '[' + $sumParts + ']'
    } else {
        $summariesJson = '[' + ($sumParts -join ",`r`n") + ']'
    }
    $reportJson = if ($payload.ReportPath) { $payload.ReportPath | ConvertTo-Json } else { 'null' }
    $runJson    = if ($payload.RunFolder) { $payload.RunFolder | ConvertTo-Json } else { 'null' }
    $manJson    = if ($payload.ManifestPath) { $payload.ManifestPath | ConvertTo-Json } else { 'null' }
    $json = @"
{
  "Summaries": $summariesJson,
  "ReportPath": $reportJson,
  "RunFolder": $runJson,
  "ManifestPath": $manJson
}
"@
} else {
    $payload.Summaries = @($summaryList)
    $json = $payload | ConvertTo-Json -Depth 8
}

$json | Set-Content -Path $resultPath -Encoding UTF8
Write-GuiLog "Wrote result JSON: $resultPath"
Write-GuiLog "Done. Databases compared: $(Get-ObjectCount $summaryList)"
