#Requires -Version 5.1
<#
.SYNOPSIS
    Orchestrates schema comparison / sync across a Dev -> UAT -> Prod promotion pipeline
    defined in a JSON config, calling Compare-SqlSchema.ps1 for each hop.

.DESCRIPTION
    Reads config\environments.json (or a custom path), then for each promotion hop
    (Source -> Target) runs the schema comparison, generates a reviewable sync script,
    and optionally applies it. Designed for CI/CD or scheduled promotion:

        Dev  --(compare + script)-->  UAT
        UAT  --(compare + script)-->  Prod

    One-to-many fan-out is also supported: set a single source database and point the
    target environment at DestinationDatabaseListFile (txt/json/yml) or a longer
    Databases array. Compare-SqlSchema.ps1 then syncs the same source schema to each
    destination database on the target server.

    By default nothing is applied automatically; scripts are produced for review. Set a
    hop's "AutoApply": true in the config (or pass -Apply) to execute against the target.

.PARAMETER ConfigPath
    Path to the environments JSON. Defaults to .\config\environments.json.

.PARAMETER Only
    Run only the promotions whose Target matches one of these names (e.g. -Only Uat).

.PARAMETER Apply
    Force-apply every hop regardless of the config's per-hop AutoApply flag. Honors
    -WhatIf / -Confirm.

.PARAMETER WhatIfScriptsOnly
    Generate scripts and report but never apply, even if AutoApply is true in the config.

.PARAMETER Credential
    Optional PSCredential used for any environment whose Auth is 'Sql'.

.PARAMETER OutputPath
    Directory for scripts/reports. Defaults to .\output.

.EXAMPLE
    .\Invoke-SchemaSyncPipeline.ps1
    # Compares Dev->Uat and Uat->Prod, writes review scripts, applies nothing.

.EXAMPLE
    .\Invoke-SchemaSyncPipeline.ps1 -Only Uat -Apply
    # Compares Dev->Uat and applies the sync to UAT after confirmation.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]       $ConfigPath,
    [string[]]     $Only,
    [switch]       $Apply,
    [switch]       $WhatIfScriptsOnly,
    [pscredential] $Credential,
    [string]       $OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $ConfigPath)  { $ConfigPath  = Join-Path $PSScriptRoot 'config\environments.json' }
if (-not $OutputPath)  { $OutputPath  = Join-Path $PSScriptRoot 'output' }
$compareScript = Join-Path $PSScriptRoot 'Compare-SqlSchema.ps1'

if (-not (Test-Path $ConfigPath))    { throw "Config not found: $ConfigPath" }
if (-not (Test-Path $compareScript)) { throw "Compare-SqlSchema.ps1 not found next to this script." }
if (-not (Test-Path $OutputPath))    { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

$cfg = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.Environments -or -not $cfg.Promotions) {
    throw "Config must define 'Environments' and 'Promotions'."
}

function Get-Env {
    param([string]$Name)
    $prop = $cfg.Environments.PSObject.Properties[$Name]
    if (-not $prop) { throw "Environment '$Name' is not defined in $ConfigPath." }
    return $prop.Value
}

function Resolve-ListFilePath {
    param([string]$PathHint, [string]$ConfigFile)
    if ([string]::IsNullOrWhiteSpace($PathHint)) { return $null }
    if ([System.IO.Path]::IsPathRooted($PathHint) -and (Test-Path -LiteralPath $PathHint)) {
        return (Resolve-Path -LiteralPath $PathHint).Path
    }
    $fromConfigDir = Join-Path (Split-Path -Parent $ConfigFile) $PathHint
    if (Test-Path -LiteralPath $fromConfigDir) {
        return (Resolve-Path -LiteralPath $fromConfigDir).Path
    }
    $fromScriptRoot = Join-Path $PSScriptRoot $PathHint
    if (Test-Path -LiteralPath $fromScriptRoot) {
        return (Resolve-Path -LiteralPath $fromScriptRoot).Path
    }
    throw "DestinationDatabaseListFile not found: $PathHint (tried relative to config and script root)."
}

$hasOptions    = [bool]$cfg.PSObject.Properties['Options']
$excludeSchema = if ($hasOptions -and $cfg.Options.PSObject.Properties['ExcludeSchema']) { @($cfg.Options.ExcludeSchema) } else { @('sys','INFORMATION_SCHEMA','guest') }
$includeTypes  = if ($hasOptions -and $cfg.Options.PSObject.Properties['IncludeObjectType']) { @($cfg.Options.IncludeObjectType) } else { @() }

Write-Host "=== Schema Sync Pipeline ===" -ForegroundColor Cyan
Write-Host "Config: $ConfigPath" -ForegroundColor Gray

$pipelineResults = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($hop in $cfg.Promotions) {
    if ($Only -and ($hop.Target -notin $Only)) { continue }

    $srcEnv = Get-Env $hop.Source
    $tgtEnv = Get-Env $hop.Target

    $srcDbs = @($srcEnv.Databases)
    $tgtListFile = $null
    if ($tgtEnv.PSObject.Properties['DestinationDatabaseListFile'] -and $tgtEnv.DestinationDatabaseListFile) {
        $tgtListFile = Resolve-ListFilePath -PathHint ([string]$tgtEnv.DestinationDatabaseListFile) -ConfigFile $ConfigPath
    } elseif ($hop.PSObject.Properties['DestinationDatabaseListFile'] -and $hop.DestinationDatabaseListFile) {
        $tgtListFile = Resolve-ListFilePath -PathHint ([string]$hop.DestinationDatabaseListFile) -ConfigFile $ConfigPath
    }

    $tgtDbs = if ($tgtEnv.PSObject.Properties['Databases']) { @($tgtEnv.Databases) } else { $srcDbs }

    Write-Host "`n--- Promotion: $($hop.Source) [$($srcEnv.SqlInstance)] -> $($hop.Target) [$($tgtEnv.SqlInstance)] ---" -ForegroundColor Yellow
    if ($tgtListFile) {
        Write-Host "    One-to-many: source DB(s) $($srcDbs -join ', ') -> destinations from $tgtListFile" -ForegroundColor Gray
    } else {
        Write-Host "    Databases: $($srcDbs -join ', ')" -ForegroundColor Gray
    }

    $hopApply = $false
    if (-not $WhatIfScriptsOnly) {
        $hopApply = [bool]$Apply -or ($hop.PSObject.Properties['AutoApply'] -and [bool]$hop.AutoApply)
    }

    $splat = @{
        SourceSqlInstance  = $srcEnv.SqlInstance
        TargetSqlInstance  = $tgtEnv.SqlInstance
        Database           = $srcDbs
        GenerateSyncScript = $true
        OutputPath         = $OutputPath
        ExcludeSchema      = $excludeSchema
        ReportFormat       = @('Console','Html')
    }
    if ($tgtListFile) {
        $splat.TargetDatabaseListFile = $tgtListFile
    } elseif ($tgtDbs -and ($tgtDbs -join ',') -ne ($srcDbs -join ',')) {
        $splat.TargetDatabase = $tgtDbs
    }
    if ($includeTypes.Count -gt 0) { $splat.IncludeObjectType = $includeTypes }
    if ($hop.PSObject.Properties['IncludeDrops'] -and [bool]$hop.IncludeDrops) { $splat.IncludeDrops = $true }

    # SQL auth for either side.
    $srcAuth = if ($srcEnv.PSObject.Properties['Auth']) { $srcEnv.Auth } else { 'Windows' }
    $tgtAuth = if ($tgtEnv.PSObject.Properties['Auth']) { $tgtEnv.Auth } else { 'Windows' }
    if ($srcAuth -eq 'Sql') { if (-not $Credential) { throw "Environment '$($hop.Source)' uses SQL auth; pass -Credential." }; $splat.SourceCredential = $Credential }
    if ($tgtAuth -eq 'Sql') { if (-not $Credential) { throw "Environment '$($hop.Target)' uses SQL auth; pass -Credential." }; $splat.TargetCredential = $Credential }

    if ($hopApply) {
        $applyLabel = if ($tgtListFile) { "destinations from list file" } else { ($srcDbs -join ', ') }
        if ($PSCmdlet.ShouldProcess("$($tgtEnv.SqlInstance)", "Apply schema sync for $applyLabel")) {
            $splat.Apply = $true
        }
    }

    $result = & $compareScript @splat
    foreach ($r in $result) {
        $pipelineResults.Add([pscustomobject]@{
            Hop             = "$($hop.Source) -> $($hop.Target)"
            Database        = $r.Database
            TargetDatabase  = $r.TargetDatabase
            DifferenceCount = $r.DifferenceCount
            AutoScripts     = $r.AutoScripts
            ManualScripts   = $r.ManualScripts
            Applied         = [bool]$hopApply
            ScriptFolder    = $r.ScriptFolder
            ReportPath      = $r.ReportPath
        })
    }
}

Write-Host "`n=== Pipeline Summary ===" -ForegroundColor Cyan
$pipelineResults | Format-Table Hop, Database, TargetDatabase, DifferenceCount, AutoScripts, ManualScripts, Applied -AutoSize | Out-String -Width 4096 | Write-Host
if ($pipelineResults.Count -gt 0) {
    $folders = $pipelineResults | Where-Object ScriptFolder | Select-Object -ExpandProperty ScriptFolder -Unique
    foreach ($f in $folders) { Write-Host "Scripts: $f" -ForegroundColor Gray }
}
$pipelineResults
