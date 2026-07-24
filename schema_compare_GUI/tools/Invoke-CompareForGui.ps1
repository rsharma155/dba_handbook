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

function Write-GuiLog([string]$Message) {
    Write-Output $Message
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
} elseif ($tgtList.Count -gt 0) {
    if ($mode -eq 'OneToMany' -or $tgtList.Count -gt 1) {
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

$summaries = @(& $compareScript @splat)

$payload = [ordered]@{
    Summaries    = @()
    ReportPath   = $null
    RunFolder    = $null
    ManifestPath = $null
}

foreach ($s in @($summaries)) {
    $diffs = @()
    if ($s.PSObject.Properties['Differences'] -and $s.Differences) {
        foreach ($d in @($s.Differences)) {
            $diffs += [ordered]@{
                Database   = [string]$d.Database
                ObjectType = [string]$d.ObjectType
                ObjectName = [string]$d.ObjectName
                Status     = [string]$d.Status
                Details    = [string]$d.Details
            }
        }
    }

    $entry = [ordered]@{
        Database        = [string]$s.Database
        TargetDatabase  = [string]$s.TargetDatabase
        DifferenceCount = [int]$s.DifferenceCount
        AutoScripts     = [int]$s.AutoScripts
        ManualScripts   = [int]$s.ManualScripts
        ScriptFolder    = if ($s.ScriptFolder) { [string]$s.ScriptFolder } else { $null }
        ReportPath      = if ($s.ReportPath) { [string]$s.ReportPath } else { $null }
        Differences     = $diffs
    }
    $payload.Summaries += $entry

    if ($s.ReportPath -and -not $payload.ReportPath) { $payload.ReportPath = [string]$s.ReportPath }
    if ($s.ScriptFolder) {
        $folder = [string]$s.ScriptFolder
        $parent = Split-Path -Parent $folder
        if ((Split-Path -Leaf $parent) -like 'SchemaSync_*') {
            $payload.RunFolder = $parent
        } elseif (-not $payload.RunFolder) {
            $payload.RunFolder = $folder
        }
    }
}

if ($payload.RunFolder) {
    $manifest = Join-Path $payload.RunFolder '_manifest.csv'
    if (Test-Path -LiteralPath $manifest) { $payload.ManifestPath = $manifest }
}

$resultPath = [string]$req.ResultJsonPath
($payload | ConvertTo-Json -Depth 8) | Set-Content -Path $resultPath -Encoding UTF8
Write-GuiLog "Wrote result JSON: $resultPath"
Write-GuiLog "Done. Databases compared: $($payload.Summaries.Count)"
