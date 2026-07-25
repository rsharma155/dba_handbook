# =============================================================================
# Module:   tools/Test-CompareBridge.ps1
# Purpose:  Manual test harness for the GUI-to-PowerShell compare bridge.
# Author:   Ravi Sharma
# Created:  2026-05-22
# Copyright (c) 2026 Ravi Sharma
# SPDX-License-Identifier: MIT
# =============================================================================

#Requires -Version 5.1
<#
.SYNOPSIS
  Dry-run / regression checks for the GUI compare bridge Count bug.
  No SQL Server required.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$failed = 0
function Assert-True([bool]$Cond, [string]$Msg) {
    if ($Cond) {
        Write-Host "PASS: $Msg" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Msg" -ForegroundColor Red
        $script:failed++
    }
}

$guiRoot = Split-Path $PSScriptRoot -Parent
# Prefer the engine bundled with the GUI (zip layout); fall back to sibling repo folder.
$compare = Join-Path $guiRoot 'schema_compare\Compare-SqlSchema.ps1'
if (-not (Test-Path -LiteralPath $compare)) {
    $repoRoot = Split-Path $guiRoot -Parent
    $compare = Join-Path $repoRoot 'schema_compare\Compare-SqlSchema.ps1'
}
$bridge = Join-Path $PSScriptRoot 'Invoke-CompareForGui.ps1'

Write-Host "Bridge : $bridge"
Write-Host "Compare: $compare"

# --- 1) Syntax parse (UTF-8; Windows PowerShell defaults can misread em-dashes) ---
foreach ($path in @($bridge, $compare)) {
    $tokens = $null; $errors = $null
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "Parse OK: $(Split-Path $path -Leaf)"
    if ($errors.Count -gt 0) { $errors | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red } }
}

# --- 2) StrictMode null/foreach Count regression (root cause) ---
function Get-ObjectCount { param($InputObject) if ($null -eq $InputObject) { return 0 }; if ($InputObject -is [string]) { return 1 }; if ($InputObject -is [System.Collections.ICollection]) { return [int]$InputObject.Count }; return @($InputObject).Count }

$changeDetailRows = foreach ($x in @()) { $x }  # -> $null
try {
    $null = $changeDetailRows.Count
    Assert-True $false 'raw $null.Count should throw under StrictMode'
} catch {
    Assert-True ($_.Exception.Message -match 'Count') 'raw $null.Count throws (repro)'
}
Assert-True ((Get-ObjectCount $changeDetailRows) -eq 0) 'Get-ObjectCount($null) -eq 0'

$changeDetailRows2 = @(foreach ($x in @()) { $x })
Assert-True ($changeDetailRows2.Count -eq 0) '@(foreach empty).Count -eq 0'

# --- 3) Export-HtmlReport zero-diff path (inline, mirrors fixed logic) ---
$allResults = [System.Collections.Generic.List[pscustomobject]]::new()
$allResults.Add([pscustomobject]@{
    Database    = 'AdventureWorksDW2025'
    Differences = [System.Collections.Generic.List[pscustomobject]]::new()
    Changes     = [System.Collections.Generic.List[object]]::new()
})
$allDiffs = @(foreach ($r in $allResults) { foreach ($d in @($r.Differences)) { $d } })
$changeDetailRows = @(foreach ($r in $allResults) {
    if (-not ($r.PSObject.Properties['Changes'] -and $r.Changes)) { continue }
    foreach ($c in @($r.Changes)) { "row" }
})
$hasChangeDetails = (Get-ObjectCount $changeDetailRows) -gt 0
Assert-True ((Get-ObjectCount $allDiffs) -eq 0) 'zero-diff flatten count is 0'
Assert-True (-not $hasChangeDetails) 'zero-diff hasChangeDetails is false (no throw)'

# --- 4) Bridge JSON shape for zero-diff / single summary ---
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("SchemaCompareGuiTest_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
try {
    $mockParamBlock = @'
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]   $SourceSqlInstance,
    [string]   $TargetSqlInstance,
    [string[]] $Database,
    [string]   $NetworkProtocol,
    [int]      $ConnectionTimeout,
    [string[]] $ReportFormat,
    [int]      $SourcePort,
    [int]      $TargetPort,
    [switch]   $TrustServerCertificate,
    [switch]   $GenerateSyncScript,
    [switch]   $IncludeDrops,
    [switch]   $Apply,
    [string]   $OutputPath,
    [string[]] $ExcludeSchema,
    [string]   $TargetDatabaseListFile,
    [string[]] $TargetDatabase,
    [pscredential] $SourceCredential,
    [pscredential] $TargetCredential
)
'@

    $mockCompare = Join-Path $tempDir 'Mock-Compare.ps1'
    @"
$mockParamBlock
[pscustomobject]@{
    Database        = 'AdventureWorksDW2025'
    TargetDatabase  = 'AdventureWorksDW2025'
    DifferenceCount = 0
    AutoScripts     = 0
    ManualScripts   = 0
    ScriptFolder    = `$null
    ReportPath      = `$null
    Differences     = @()
}
"@ | Set-Content -Path $mockCompare -Encoding UTF8

    $resultJson = Join-Path $tempDir 'result.json'
    $request = [ordered]@{
        CompareScript       = $mockCompare
        SourceSqlInstance   = 'localhost'
        TargetSqlInstance   = 'localhost'
        SourcePort          = 0
        TargetPort          = 0
        SourceDatabase      = 'AdventureWorksDW2025'
        TargetDatabases     = @('AdventureWorksDW2025')
        TargetDatabaseListFile = $null
        Mode                = 'OneToOne'
        NetworkProtocol     = 'Tcp'
        ConnectionTimeout   = 15
        TrustServerCertificate = $true
        GenerateSyncScript  = $true
        IncludeDrops        = $false
        Apply               = $false
        ExcludeSchema       = @()
        OutputPath          = $tempDir
        ResultJsonPath      = $resultJson
        SourceAuth          = 'Windows'
        TargetAuth          = 'Windows'
        SourceUser          = ''
        TargetUser          = ''
    }
    $reqPath = Join-Path $tempDir 'request.json'
    ($request | ConvertTo-Json -Depth 5) | Set-Content -Path $reqPath -Encoding UTF8

    & $bridge -RequestPath $reqPath
    Assert-True (Test-Path -LiteralPath $resultJson) 'bridge wrote result JSON'

    $payload = Get-Content -LiteralPath $resultJson -Raw | ConvertFrom-Json
    # ConvertFrom-Json: single-element array may become one object on PS 5.1 — accept both if array forced
    $sums = @($payload.Summaries)
    Assert-True ((Get-ObjectCount $sums) -ge 1) 'payload has at least one summary'
    Assert-True ([int]$sums[0].DifferenceCount -eq 0) 'zero DifferenceCount'
    Assert-True (@($sums[0].Differences).Count -eq 0) 'empty Differences array'

    # Multi-target mock
    $mockMany = Join-Path $tempDir 'Mock-Compare-Many.ps1'
    @"
$mockParamBlock
@(
    [pscustomobject]@{ Database='Src'; TargetDatabase='T1'; DifferenceCount=0; AutoScripts=0; ManualScripts=0; ScriptFolder=`$null; ReportPath=`$null; Differences=@() }
    [pscustomobject]@{ Database='Src'; TargetDatabase='T2'; DifferenceCount=0; AutoScripts=0; ManualScripts=0; ScriptFolder=`$null; ReportPath=`$null; Differences=@() }
)
"@ | Set-Content -Path $mockMany -Encoding UTF8
    $resultJson2 = Join-Path $tempDir 'result2.json'
    $request.CompareScript = $mockMany
    $request.ResultJsonPath = $resultJson2
    $request.Mode = 'OneToMany'
    $request.TargetDatabases = @('T1', 'T2')
    $reqPath2 = Join-Path $tempDir 'request2.json'
    ($request | ConvertTo-Json -Depth 5) | Set-Content -Path $reqPath2 -Encoding UTF8
    & $bridge -RequestPath $reqPath2
    $payload2 = Get-Content -LiteralPath $resultJson2 -Raw | ConvertFrom-Json
    $sums2 = @($payload2.Summaries)
    Assert-True ((Get-ObjectCount $sums2) -eq 2) 'one-to-many preserves two summaries'
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 5) Compare script contains Get-ObjectCount helper (fixed path) ---
$compareText = Get-Content -LiteralPath $compare -Raw
Assert-True ($compareText -match 'function Get-ObjectCount') 'Compare-SqlSchema defines Get-ObjectCount'
Assert-True ($compareText -match 'Get-ObjectCount \$changeDetailRows' -or $compareText -match '\(Get-ObjectCount \$changeDetailRows\)') 'Export-HtmlReport uses safe count'
Assert-True ($compareText -notmatch '\$hasChangeDetails = \$changeDetailRows\.Count') 'unsafe \$changeDetailRows.Count removed'

if ($failed -gt 0) {
    Write-Host "`n$failed test(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll bridge/compare dry-run checks passed." -ForegroundColor Green
exit 0
