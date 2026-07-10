#Requires -Version 5.1
<#
.SYNOPSIS
    Compares user-object schemas between two SQL Server databases and generates a
    T-SQL sync script to bring the Target in line with the Source.

.DESCRIPTION
    Connects to a designated Source and Target instance using dbatools/SMO, extracts
    metadata for all user objects (Schemas, User-Defined Data Types, User-Defined Table
    Types, Sequences, Synonyms, Tables (with columns, indexes, foreign keys, check
    constraints, and triggers), Views, Stored Procedures, User-Defined Functions and
    database-level DDL triggers), diffs them, and reports the structural differences.

    Optionally emits an ordered, reviewable T-SQL sync script that:
      * CREATEs objects missing in the Target,
      * ALTERs / DROP+CREATEs objects whose definition differs,
      * (optionally) DROPs objects that exist only in the Target.

    The generated script is dependency-ordered (schemas/types first, then tables, then
    programmable objects) and is *never* executed automatically unless you pass -Apply.

.PARAMETER SourceSqlInstance
    Source ("source of truth") SQL Server instance, e.g. SQL-DEV-01 or SQL-DEV-01\INST.

.PARAMETER TargetSqlInstance
    Target instance that will be synced toward the Source.

.PARAMETER Database
    One or more databases to compare. When -TargetDatabase is omitted the same name is
    assumed on the Target. Accepts an array: 'Sales','HR'.

.PARAMETER TargetDatabase
    Optional target database name(s) when they differ from the source names. Must be the
    same count/order as -Database when supplied.

.PARAMETER SourceCredential
    Optional PSCredential for SQL authentication against the Source. Windows auth is used
    when omitted.

.PARAMETER TargetCredential
    Optional PSCredential for SQL authentication against the Target.

.PARAMETER SourcePort
    TCP port for the source instance when not using the default 1433 (e.g. 51433). Appended
    as server,port unless the instance string already contains a port.

.PARAMETER TargetPort
    TCP port for the target instance (e.g. 1433 on 192.168.10.200).

.PARAMETER ConnectionTimeout
    Connection timeout in seconds (default 30).

.PARAMETER TrustServerCertificate
    Trust the server TLS certificate (useful for dev/lab instances without a trusted cert).

.PARAMETER NetworkProtocol
    Connection protocol: TcpIp (default, remote), NamedPipes (local), or SharedMemory (local only).

.PARAMETER IncludeObjectType
    Restrict the comparison to specific object types. Defaults to all supported types.
    Valid: Schemas, UserDefinedDataTypes, UserDefinedTableTypes, Sequences, Synonyms,
           Tables, Views, StoredProcedures, UserDefinedFunctions, DatabaseTriggers.

.PARAMETER ExcludeSchema
    Schema names to skip entirely (e.g. staging or temp schemas).

.PARAMETER GenerateSyncScript
    Emit a .sql sync script into -OutputPath.

.PARAMETER IncludeDrops
    Include DROP statements for objects/columns that exist only in the Target. OFF by
    default because drops are destructive.

.PARAMETER Apply
    Execute the generated sync script against the Target. Requires -GenerateSyncScript.
    Honors -WhatIf / -Confirm (defaults to prompting).

.PARAMETER OutputPath
    Directory for the sync script and HTML report. Defaults to .\output next to this script.

.PARAMETER ReportFormat
    One or more of: Console, GridView, Html, None. Default: Console, Html.

.PARAMETER Quiet
    Suppress progress/host chatter (findings + report path are still returned/emitted).

.OUTPUTS
    [pscustomobject] per database summarizing differences, script path and report path.
    The full difference list is attached under the .Differences property.

.EXAMPLE
    .\Compare-SqlSchema.ps1 -SourceSqlInstance SQL-DEV-01 -TargetSqlInstance SQL-UAT-01 `
        -Database Sales -GenerateSyncScript

.EXAMPLE
    # Compare several DBs, include drops, and apply after review prompt
    .\Compare-SqlSchema.ps1 -SourceSqlInstance SQL-DEV-01 -TargetSqlInstance SQL-UAT-01 `
        -Database Sales,HR -GenerateSyncScript -IncludeDrops -Apply

.NOTES
    Requires the dbatools module (Install-Module dbatools -Scope CurrentUser).
    Table structural changes are emitted as ALTER statements where safely expressible;
    anything that would require a data-moving rebuild is flagged for manual review rather
    than silently dropping/recreating a table.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)] [string]   $SourceSqlInstance,
    [Parameter(Mandatory)] [string]   $TargetSqlInstance,
    [Parameter(Mandatory)] [string[]] $Database,
    [string[]]      $TargetDatabase,
    [pscredential]  $SourceCredential,
    [pscredential]  $TargetCredential,
    [int]           $SourcePort = 0,
    [int]           $TargetPort = 0,
    [int]           $ConnectionTimeout = 30,
    [switch]        $TrustServerCertificate,
    [ValidateSet('TcpIp','NamedPipes','SharedMemory','Tcp','Np')]
    [string]        $NetworkProtocol = 'TcpIp',

    [ValidateSet('Schemas','UserDefinedDataTypes','UserDefinedTableTypes','Sequences',
                 'Synonyms','Tables','Views','StoredProcedures','UserDefinedFunctions',
                 'DatabaseTriggers')]
    [string[]]      $IncludeObjectType,
    [string[]]      $ExcludeSchema = @('sys','INFORMATION_SCHEMA','guest'),

    [switch]        $GenerateSyncScript,
    [switch]        $IncludeDrops,
    [switch]        $Apply,

    [string]        $OutputPath,
    [ValidateSet('Console','GridView','Html','None')]
    [string[]]      $ReportFormat = @('Console','Html'),
    [switch]        $Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Ordered list of the object types we support. Order matters for scripting so
# that dependencies (schemas, types, tables) are created before the objects
# that reference them.
# ---------------------------------------------------------------------------
$script:ObjectTypeOrder = @(
    'Schemas'
    'UserDefinedDataTypes'
    'UserDefinedTableTypes'
    'Sequences'
    'Tables'
    'Views'
    'UserDefinedFunctions'
    'StoredProcedures'
    'Synonyms'
    'DatabaseTriggers'
)

# ---------------------------------------------------------------------------
# Purpose taxonomy. The numeric Order controls the sequence in which generated
# "auto_" scripts must be executed so that dependencies are satisfied
# (schemas/types first, then tables, then columns, indexes, constraints, and
# finally programmable objects). Manual purposes are excluded from auto-apply.
# ---------------------------------------------------------------------------
$script:PurposeOrder = [ordered]@{
    'schema'           = 10
    'type'             = 20
    'sequence'         = 30
    'synonym'          = 40
    'table_create'     = 50
    'column_add'       = 60
    'column_update'    = 70
    'index'            = 80
    'constraints'      = 90
    'trigger'          = 100
    'view'             = 110
    'function'         = 120
    'stored_procedure' = 130
    'db_trigger'       = 140
    # Manual-only purposes (still ordered for readability)
    'pk_change'        = 200
    'column_remove'    = 210
    'table_rebuild'    = 220
    'cleanup_drop'     = 230
}

# ===========================================================================
#  Helpers
# ===========================================================================
function Write-Log {
    param([string]$Message, [string]$Color = 'Gray', [switch]$Force)
    if (-not $Quiet -or $Force) { Write-Host $Message -ForegroundColor $Color }
}

function Test-Prerequisite {
    if (-not (Get-Module -ListAvailable -Name dbatools)) {
        throw "The 'dbatools' module is required. Install it with: Install-Module dbatools -Scope CurrentUser -Force"
    }
    Import-Module dbatools -ErrorAction Stop | Out-Null
    # Newer dbatools defaults to mandatory encryption; relax it for this session so
    # lab/dev instances without trusted certs still connect. Safe if the cmdlet is absent.
    if (Get-Command Set-DbatoolsInsecureConnection -ErrorAction SilentlyContinue) {
        Set-DbatoolsInsecureConnection -SessionOnly | Out-Null
    }
}

function Resolve-NetworkProtocol {
    param([string]$Protocol)
    switch ($Protocol) {
        'Tcp' { return 'TcpIp' }
        'Np'  { return 'NamedPipes' }
        default { return $Protocol }
    }
}

function Format-SqlInstanceAddress {
    <# Append TCP port when supplied and not already present in the instance string. #>
    param([string]$Instance, [int]$Port = 0)
    if ($Port -le 0) { return $Instance }
    if ($Instance -match ',\s*\d+\s*$') { return $Instance }
    return "$Instance,$Port"
}

function Get-SqlConnectionHints {
    param([string]$Instance, [string]$Role, [int]$Port = 0)
    $lines = [System.Collections.Generic.List[string]]::new()
    $hostPart = ($Instance -split '\\')[0] -replace ',\d+$', ''
    $isLocal  = ($hostPart -in @('.', 'localhost', '(local)', '127.0.0.1')) -or
                ($hostPart -eq $env:COMPUTERNAME)

    $lines.Add("Troubleshooting [$Role] connection to '$Instance':")
    if ($isLocal) {
        $lines.Add('  * This looks like the LOCAL machine. Try one of these instead of the PC name:')
        $lines.Add('      -SourceSqlInstance .                    # default instance, local')
        $lines.Add('      -SourceSqlInstance localhost')
        $lines.Add('      -SourceSqlInstance .\SQLEXPRESS         # if using Express')
        $lines.Add("      -SourceSqlInstance $env:COMPUTERNAME\INSTANCENAME  # named instance")
    }
    if ($hostPart -match '^\d+\.\d+\.\d+\.\d+$') {
        $lines.Add("  * Remote IP host. Ensure SQL listens on TCP and firewall allows the port.")
        if ($Port -le 0) { $lines.Add('      Add -TargetPort 1433  (or your instance''s static port)') }
    }
    $lines.Add('  * Verify SQL Server service is running:  Get-Service MSSQL*')
    $lines.Add('  * List installed instances:  Get-ItemProperty ''HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL''')
    $lines.Add('  * Quick test:  sqlcmd -S "' + $Instance + '" -E -Q "SELECT @@VERSION"')
    $lines.Add('  * Enable TCP/IP: SQL Server Configuration Manager -> SQL Server Network Configuration -> Protocols for MSSQLSERVER -> TCP/IP -> Enabled -> restart SQL service')
    $lines.Add('  * If TCP/1433 is closed locally, try named pipes:  -NetworkProtocol NamedPipes -SourceSqlInstance .')
    $lines.Add('  * ODBC Driver 18 cert errors: add -TrustServerCertificate (enabled by default in this tool)')
    $lines.Add('  * Run diagnostics:  .\Test-SqlSchemaConnection.ps1 -SqlInstance "' + $Instance + '"')
    return ($lines -join [Environment]::NewLine)
}

function Connect-Instance {
    param(
        [string]$Instance,
        [pscredential]$Credential,
        [int]$Port = 0,
        [int]$TimeoutSec = 30,
        [switch]$TrustServerCertificate,
        [string]$NetworkProtocol = 'TcpIp',
        [string]$Role = 'Server'
    )
    $resolved = Format-SqlInstanceAddress -Instance $Instance -Port $Port
    $protocol = Resolve-NetworkProtocol $NetworkProtocol
    $splat  = @{
        SqlInstance     = $resolved
        ErrorAction     = 'Stop'
        NetworkProtocol = $protocol
    }
    if ($Credential) { $splat.SqlCredential = $Credential }

    $appendParts = @("Connect Timeout=$TimeoutSec")
    # ODBC Driver 18+ encrypts by default; trust cert unless explicitly disabled.
    if ($TrustServerCertificate -or -not $PSBoundParameters.ContainsKey('TrustServerCertificate')) {
        $appendParts += 'TrustServerCertificate=True'
    }
    $appendParts += 'Encrypt=Optional'
    $splat.AppendConnectionString = ($appendParts -join ';')

    try {
        $srv = Connect-DbaInstance @splat
    } catch {
        $detail = if ($_.Exception.Message) { $_.Exception.Message } else { $_.ToString() }
        $hints  = Get-SqlConnectionHints -Instance $resolved -Role $Role -Port $Port
        throw "Failed to connect to $Role [$resolved].`n$detail`n`n$hints"
    }
    try {
        Initialize-SmoServer -Server $srv
    } catch {
        Write-Log "  Warning: SMO performance init skipped ($($_.Exception.Message))" 'DarkYellow'
    }
    return $srv
}

function Set-SmoInitFields {
    <#
        Set which SMO properties load during enumeration. Uses the single-field
        SetDefaultInitFields(Type, String) overload in a loop to avoid PowerShell's
        ambiguous overload resolution with SetDefaultInitFields(Type, String[]).
    #>
    param($Server, [Type]$SmoType, [string[]]$Fields)
    $Server.SetDefaultInitFields($SmoType, $false)
    foreach ($field in $Fields) {
        $Server.SetDefaultInitFields($SmoType, $field)
    }
}

function Initialize-SmoServer {
    <#
        Restrict SMO's default property payload during collection enumeration. Child
        objects (Columns, Indexes, etc.) still lazy-load on first access, but listing
        thousands of tables/procs no longer pulls every property over the wire up front.
    #>
    param($Server)
    $enumOnly   = 'Name', 'Schema', 'IsSystemObject'
    $schemaOnly = 'Name'
    $dbOnly     = 'Name'

    Set-SmoInitFields -Server $Server -SmoType ([Microsoft.SqlServer.Management.Smo.Table])               -Fields $enumOnly
    Set-SmoInitFields -Server $Server -SmoType ([Microsoft.SqlServer.Management.Smo.View])                -Fields $enumOnly
    Set-SmoInitFields -Server $Server -SmoType ([Microsoft.SqlServer.Management.Smo.StoredProcedure])      -Fields $enumOnly
    Set-SmoInitFields -Server $Server -SmoType ([Microsoft.SqlServer.Management.Smo.UserDefinedFunction])  -Fields $enumOnly
    Set-SmoInitFields -Server $Server -SmoType ([Microsoft.SqlServer.Management.Smo.Schema])               -Fields $schemaOnly
    Set-SmoInitFields -Server $Server -SmoType ([Microsoft.SqlServer.Management.Smo.UserDefinedDataType])  -Fields $enumOnly
    Set-SmoInitFields -Server $Server -SmoType ([Microsoft.SqlServer.Management.Smo.UserDefinedTableType]) -Fields $enumOnly
    Set-SmoInitFields -Server $Server -SmoType ([Microsoft.SqlServer.Management.Smo.Sequence])             -Fields $enumOnly
    Set-SmoInitFields -Server $Server -SmoType ([Microsoft.SqlServer.Management.Smo.Synonym])              -Fields $enumOnly
    Set-SmoInitFields -Server $Server -SmoType ([Microsoft.SqlServer.Management.Smo.Database])             -Fields $dbOnly
    Set-SmoInitFields -Server $Server -SmoType ([Microsoft.SqlServer.Management.Smo.Trigger])              -Fields $enumOnly
}

function Get-CollectionFor {
    <# Return the SMO collection on a Database object for a given logical type. #>
    param($Db, [string]$Type)
    switch ($Type) {
        'Schemas'               { return $Db.Schemas }
        'UserDefinedDataTypes'  { return $Db.UserDefinedDataTypes }
        'UserDefinedTableTypes' { return $Db.UserDefinedTableTypes }
        'Sequences'             { return $Db.Sequences }
        'Synonyms'              { return $Db.Synonyms }
        'Tables'                { return $Db.Tables }
        'Views'                 { return $Db.Views }
        'StoredProcedures'      { return $Db.StoredProcedures }
        'UserDefinedFunctions'  { return $Db.UserDefinedFunctions }
        'DatabaseTriggers'      { return $Db.Triggers }
        default                 { return @() }
    }
}

function Test-IsSystemObject {
    param($Obj)
    # Not every SMO type exposes IsSystemObject (e.g. Schema). Probe defensively.
    $prop = $Obj.PSObject.Properties['IsSystemObject']
    if ($prop) { return [bool]$prop.Value }
    # Schemas: treat the well-known built-ins as system.
    if ($Obj.PSObject.Properties['Name']) {
        return @('sys','INFORMATION_SCHEMA','guest','db_owner','db_accessadmin',
                 'db_securityadmin','db_ddladmin','db_backupoperator','db_datareader',
                 'db_datawriter','db_denydatareader','db_denydatawriter') -contains $Obj.Name
    }
    return $false
}

function Get-ObjectSchema {
    param($Obj)
    if ($Obj.PSObject.Properties['Schema']) { return [string]$Obj.Schema }
    return ''  # Schemas / DatabaseTriggers have no owning schema
}

function Get-ObjectKey {
    param($Obj, [string]$Type)
    $sch = Get-ObjectSchema $Obj
    if ([string]::IsNullOrEmpty($sch)) { return $Obj.Name }
    return "$sch.$($Obj.Name)"
}

function Get-DisplayName {
    param($Obj, [string]$Type)
    $sch = Get-ObjectSchema $Obj
    if ([string]::IsNullOrEmpty($sch)) { return "[$($Obj.Name)]" }
    return "[$sch].[$($Obj.Name)]"
}

function New-ScriptingOption {
    <# Canonical scripting options used both for diffing and generation. #>
    param([switch]$ForDrop, [switch]$WithDependencies, [switch]$NoForeignKeys)
    $o = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
    $o.ScriptDrops            = [bool]$ForDrop
    $o.WithDependencies       = [bool]$WithDependencies
    $o.SchemaQualify          = $true
    $o.IncludeIfNotExists     = $false
    $o.Indexes                = $true
    $o.ClusteredIndexes       = $true
    $o.NonClusteredIndexes    = $true
    $o.DriAll                 = $true          # all declarative referential integrity
    $o.Triggers               = $true
    $o.FullTextIndexes        = $false
    $o.NoCollation            = $false
    $o.Default                = $true
    $o.ExtendedProperties     = $true
    $o.EnforceScriptingOptions = $true
    $o.AnsiPadding            = $true
    $o.IncludeHeaders         = $false
    $o.ScriptBatchTerminator  = $false
    $o.NoCommandTerminator    = $false
    if ($NoForeignKeys) { $o.DriForeignKeys = $false }
    return $o
}

function Remove-SqlComments {
    <#
        Strip T-SQL comments for drift comparison. Removes block comments and whole-line
        -- comments. Inline -- comments are stripped when not inside a string literal.
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    # Block comments (non-greedy, multiline).
    $t = [regex]::Replace($Text, '(?is)/\*.*?\*/', '')

    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($ln in ($t -split "`r?`n")) {
        $line = $ln.TrimEnd()
        if ($line -match '^\s*--') { continue }   # whole-line comment

        # Strip inline -- outside of single-quoted string literals.
        $sb = [System.Text.StringBuilder]::new()
        $inQuote = $false
        for ($i = 0; $i -lt $line.Length; $i++) {
            $ch = $line[$i]
            if ($ch -eq "'" -and -not $inQuote) { $inQuote = $true; $sb.Append($ch) | Out-Null; continue }
            if ($ch -eq "'" -and $inQuote) {
                if ($i + 1 -lt $line.Length -and $line[$i + 1] -eq "'") {
                    $sb.Append("''") | Out-Null; $i++; continue
                }
                $inQuote = $false; $sb.Append($ch) | Out-Null; continue
            }
            if (-not $inQuote -and $ch -eq '-' -and $i + 1 -lt $line.Length -and $line[$i + 1] -eq '-') { break }
            $sb.Append($ch) | Out-Null
        }
        $cleaned = $sb.ToString().TrimEnd()
        if ($cleaned -match '^\s*$') { continue }
        $out.Add($cleaned)
    }
    return ($out -join "`n")
}

function Normalize-SqlScriptText {
    <#
        Normalize scripted DDL/DML for comparison: strip comments, SET/GO noise, and
        collapse insignificant whitespace so cosmetic drift does not false-positive.
    #>
    param([string]$Text)
    $noComments = Remove-SqlComments $Text
    $clean = foreach ($ln in ($noComments -split "`r?`n")) {
        $t = $ln.TrimEnd()
        if ($t -match '^\s*$') { continue }
        if ($t -match '(?i)^\s*GO\s*$') { continue }
        if ($t -match '(?i)^\s*SET\s+(ANSI_NULLS|QUOTED_IDENTIFIER|ANSI_PADDING)\b') { continue }
        # Collapse internal runs of whitespace for stable comparison.
        ($t -replace '\s+', ' ').Trim()
    }
    return (($clean -join "`n").Trim())
}

function Get-CanonicalScript {
    <#
        Produce a normalized, comparable representation of an object's definition so
        cosmetic differences (blank lines, trailing spaces, batch separators, comments)
        do not register as false-positive drift.
    #>
    param($Obj, [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$Options)
    try {
        $lines = $Obj.Script($Options)
    } catch {
        return "<<UNSCRIPTABLE: $($_.Exception.Message)>>"
    }
    return (Normalize-SqlScriptText (($lines -join "`n")))
}

# ---------------------------------------------------------------------------
#  Column / DDL helpers
# ---------------------------------------------------------------------------
function Get-ColumnTypeString {
    <# T-SQL data-type clause only (no nullability/identity/default). #>
    param($Column)
    $dt   = $Column.DataType
    $name = $dt.Name.ToLower()
    $type = "[$($dt.Name)]"
    switch -Regex ($name) {
        '^(n?char|n?varchar|binary|varbinary)$' {
            $len = if ($dt.MaximumLength -eq -1) { 'max' } else { $dt.MaximumLength }
            $type += "($len)"
        }
        '^(decimal|numeric)$'                 { $type += "($($dt.NumericPrecision),$($dt.NumericScale))" }
        '^(datetime2|datetimeoffset|time)$'   {
            if ($dt.NumericScale -ge 0 -and $dt.NumericScale -le 7) { $type += "($($dt.NumericScale))" }
        }
        default { }
    }
    return $type
}

function Get-DefaultConstraint {
    param($Column)
    if ($Column.PSObject.Properties['DefaultConstraint'] -and $Column.DefaultConstraint) {
        return $Column.DefaultConstraint
    }
    return $null
}

function Get-ColumnDefinition {
    <# Full column definition for ALTER TABLE ADD (type + identity + null + inline default). #>
    param($Column, [string]$TableName)
    if ($Column.Computed) {
        return "AS $($Column.ComputedText)" + $(if ($Column.IsPersisted) { ' PERSISTED' } else { '' })
    }
    $parts = @(Get-ColumnTypeString $Column)
    if ($Column.Identity) { $parts += "IDENTITY($($Column.IdentitySeed),$($Column.IdentityIncrement))" }
    $parts += if ($Column.Nullable) { 'NULL' } else { 'NOT NULL' }
    $def = Get-DefaultConstraint $Column
    if ($def) {
        $dfName = if ($def.Name) { $def.Name } else { "DF_${TableName}_$($Column.Name)" }
        $parts += "CONSTRAINT [$dfName] DEFAULT $($def.Text)"
    }
    return ($parts -join ' ')
}

function Test-ColumnChangeSafe {
    <#
        Classify a column definition change as an in-place ('Auto') ALTER COLUMN or a
        change that needs a careful ('Manual') review (data-loss, tightening, rebuild).
        Returns @{ Mode = 'Auto'|'Manual'; Reason = '...' }.
    #>
    param($Src, $Tgt)

    if ($Src.Computed -or $Tgt.Computed) {
        return @{ Mode = 'Manual'; Reason = 'computed column change requires drop/recreate' }
    }
    if ($Src.Identity -or $Tgt.Identity) {
        if ($Src.Identity -ne $Tgt.Identity -or
            $Src.IdentitySeed -ne $Tgt.IdentitySeed -or
            $Src.IdentityIncrement -ne $Tgt.IdentityIncrement) {
            return @{ Mode = 'Manual'; Reason = 'IDENTITY property/seed/increment change requires data-moving table rebuild' }
        }
    }
    # Nullability tightening (NULL -> NOT NULL) may fail on existing NULL data.
    if ($Tgt.Nullable -and -not $Src.Nullable) {
        return @{ Mode = 'Manual'; Reason = 'NULL -> NOT NULL may fail on existing NULL rows' }
    }
    $sdt = $Src.DataType; $tdt = $Tgt.DataType
    if ($sdt.Name -ne $tdt.Name) {
        return @{ Mode = 'Manual'; Reason = "data type change $($tdt.Name) -> $($sdt.Name) risks conversion/data loss" }
    }
    $n = $sdt.Name.ToLower()
    if ($n -match '^(n?char|n?varchar|binary|varbinary)$') {
        $sLen = $sdt.MaximumLength; $tLen = $tdt.MaximumLength
        if ($sLen -ne -1 -and ($tLen -eq -1 -or $sLen -lt $tLen)) {
            return @{ Mode = 'Manual'; Reason = "length shrink ($tLen -> $sLen) risks truncation" }
        }
    }
    if ($n -match '^(decimal|numeric)$') {
        if ($sdt.NumericPrecision -lt $tdt.NumericPrecision -or $sdt.NumericScale -lt $tdt.NumericScale) {
            return @{ Mode = 'Manual'; Reason = 'precision/scale reduction risks data loss' }
        }
    }
    return @{ Mode = 'Auto'; Reason = 'safe in-place widening / nullability loosen' }
}

function Get-CleanDdl {
    <# Single DDL statement from an SMO object's Script() (no GO/SET/comment noise). #>
    param($Obj)
    $opt = New-ScriptingOption
    $raw = (@($Obj.Script($opt)) -join "`n")
    return (Normalize-SqlScriptText $raw).TrimEnd(';')
}

function ConvertTo-SqlLiteralChunks {
    <#
        Split a large T-SQL body into escaped N'...' literal chunks (default 3000 chars)
        so assignment via SET @var = @var + N'...' never hits the implicit nvarchar(4000)
        parse-time limit for a single literal token.
    #>
    param([string]$SqlBody, [int]$ChunkSize = 3000)
    $escaped = $SqlBody -replace "'", "''"
    $chunks  = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $escaped.Length; $i += $ChunkSize) {
        $len = [Math]::Min($ChunkSize, $escaped.Length - $i)
        $chunks.Add($escaped.Substring($i, $len))
    }
    if ($chunks.Count -eq 0) { $chunks.Add('') }
    return $chunks
}

function ConvertTo-ChunkedNvarcharMaxAssignment {
  param([string]$VariableName, [string]$SqlBody)
  $chunks = ConvertTo-SqlLiteralChunks -SqlBody $SqlBody
  $lines  = [System.Collections.Generic.List[string]]::new()
  $lines.Add("DECLARE $VariableName nvarchar(max) = N'';")
  foreach ($c in $chunks) { $lines.Add("SET $VariableName = $VariableName + N'$c';") }
  return ($lines -join "`r`n")
}

function New-Change {
    <# Factory for a single change record. #>
    param(
        [string]$Display, [string]$KeySafe, [string]$Category,
        [ValidateSet('Auto','Manual')][string]$Mode,
        [string]$Summary, [string]$Sql, [string]$RiskNote = ''
    )
    $order = if ($script:PurposeOrder.Contains($Category)) { $script:PurposeOrder[$Category] } else { 999 }
    [pscustomobject]@{
        ObjectDisplay = $Display
        ObjectKeySafe = ($KeySafe -replace '[^\w.-]', '_')
        Category      = $Category
        Order         = $order
        Mode          = $Mode
        Summary       = $Summary
        Sql           = $Sql
        RiskNote      = $RiskNote
    }
}

# ---------------------------------------------------------------------------
#  Table-level structural diff -> categorized change records
# ---------------------------------------------------------------------------
function Get-TableChangeSet {
    <#
        Compare two existing SMO tables and return a list of change records
        (New-Change objects) covering columns, PK, indexes, constraints and triggers.
    #>
    param($SrcTable, $TgtTable, [switch]$IncludeDrops)

    $disp = "[$($SrcTable.Schema)].[$($SrcTable.Name)]"
    $key  = "$($SrcTable.Schema).$($SrcTable.Name)"
    $objId = "N'$disp'"
    $changes = [System.Collections.Generic.List[object]]::new()

    $srcCols = @{}; foreach ($c in $SrcTable.Columns) { $srcCols[$c.Name] = $c }
    $tgtCols = @{}; foreach ($c in $TgtTable.Columns) { $tgtCols[$c.Name] = $c }

    # ---- Column additions ---------------------------------------------------
    foreach ($name in $srcCols.Keys) {
        if ($tgtCols.ContainsKey($name)) { continue }
        $col = $srcCols[$name]
        $def = Get-ColumnDefinition $col -TableName $SrcTable.Name
        $hasDefault = [bool](Get-DefaultConstraint $col)
        $needsDefault = (-not $col.Nullable) -and (-not $col.Computed) -and (-not $col.Identity) -and (-not $hasDefault)

        if ($needsDefault) {
            $sql = "IF COL_LENGTH($objId, N'$name') IS NULL`r`n" +
                   "    ALTER TABLE $disp ADD [$name] $def;  -- NOT NULL with no default: supply a default or backfill first"
            $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'column_add' -Mode 'Manual' `
                -Summary "Add NOT NULL column [$name] $(Get-ColumnTypeString $col)" -Sql $sql `
                -RiskNote "Adding NOT NULL column [$name] with no default will fail on populated tables. Add as NULL, backfill, then SET NOT NULL, or add a DEFAULT."))
        } else {
            $sql = "IF COL_LENGTH($objId, N'$name') IS NULL`r`n" +
                   "    ALTER TABLE $disp ADD [$name] $def;"
            $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'column_add' -Mode 'Auto' `
                -Summary "Add column [$name] $(Get-ColumnTypeString $col)$(if($hasDefault){' (with default)'})" -Sql $sql))
        }
    }

    # ---- Column updates (type / nullability / default) ----------------------
    foreach ($name in $srcCols.Keys) {
        if (-not $tgtCols.ContainsKey($name)) { continue }
        $s = $srcCols[$name]; $t = $tgtCols[$name]

        $sTypeNull = "$(Get-ColumnTypeString $s) $(if($s.Nullable){'NULL'}else{'NOT NULL'})"
        $tTypeNull = "$(Get-ColumnTypeString $t) $(if($t.Nullable){'NULL'}else{'NOT NULL'})"
        $identityDrift = ($s.Identity -or $t.Identity) -and (
            $s.Identity -ne $t.Identity -or $s.IdentitySeed -ne $t.IdentitySeed -or $s.IdentityIncrement -ne $t.IdentityIncrement)
        if ($sTypeNull -ne $tTypeNull -or $s.Computed -ne $t.Computed -or $identityDrift) {
            $verdict = Test-ColumnChangeSafe -Src $s -Tgt $t
            if ($verdict.Mode -eq 'Auto') {
                $sql = "IF COL_LENGTH($objId, N'$name') IS NOT NULL`r`n" +
                       "    ALTER TABLE $disp ALTER COLUMN [$name] $sTypeNull;"
                $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'column_update' -Mode 'Auto' `
                    -Summary "Alter column [$name]: $tTypeNull -> $sTypeNull" -Sql $sql))
            } else {
                $sql = "-- Target: $tTypeNull`r`n-- Source: $sTypeNull`r`n" +
                       "ALTER TABLE $disp ALTER COLUMN [$name] $sTypeNull;"
                $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'column_update' -Mode 'Manual' `
                    -Summary "Alter column [$name]: $tTypeNull -> $sTypeNull" -Sql $sql -RiskNote $verdict.Reason))
            }
        }

        # Default constraint difference on an existing column.
        $sDef = Get-DefaultConstraint $s; $tDef = Get-DefaultConstraint $t
        $sTxt = if ($sDef) { $sDef.Text } else { $null }
        $tTxt = if ($tDef) { $tDef.Text } else { $null }
        if ($sTxt -ne $tTxt) {
            $stmts = @()
            if ($tDef) { $stmts += "IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'$($tDef.Name)' AND parent_object_id = OBJECT_ID($objId))`r`n    ALTER TABLE $disp DROP CONSTRAINT [$($tDef.Name)];" }
            if ($sDef) {
                $dfName = if ($sDef.Name) { $sDef.Name } else { "DF_$($SrcTable.Name)_$name" }
                $stmts += "IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'$dfName' AND parent_object_id = OBJECT_ID($objId))`r`n    ALTER TABLE $disp ADD CONSTRAINT [$dfName] DEFAULT $($sDef.Text) FOR [$name];"
            }
            $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'constraints' -Mode 'Auto' `
                -Summary "Default on [$name]: $(if($tTxt){$tTxt}else{'<none>'}) -> $(if($sTxt){$sTxt}else{'<none>'})" -Sql ($stmts -join "`r`n")))
        }
    }

    # ---- Column removals (destructive -> manual) ----------------------------
    foreach ($name in $tgtCols.Keys) {
        if ($srcCols.ContainsKey($name)) { continue }
        $sql = "-- Column [$name] exists only in target and is not present in source.`r`n" +
               "IF COL_LENGTH($objId, N'$name') IS NOT NULL`r`n    ALTER TABLE $disp DROP COLUMN [$name];"
        $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'column_remove' -Mode 'Manual' `
            -Summary "Drop column [$name] (target-only)" -Sql $sql `
            -RiskNote "Dropping a column is irreversible and destroys its data. Confirm it is truly obsolete."))
    }

    # ---- Primary key --------------------------------------------------------
    $srcPk = $SrcTable.Indexes | Where-Object { $_.IndexKeyType.ToString() -eq 'DriPrimaryKey' } | Select-Object -First 1
    $tgtPk = $TgtTable.Indexes | Where-Object { $_.IndexKeyType.ToString() -eq 'DriPrimaryKey' } | Select-Object -First 1
    $srcPkScript = if ($srcPk) { Get-CanonicalScript $srcPk (New-ScriptingOption) } else { '' }
    $tgtPkScript = if ($tgtPk) { Get-CanonicalScript $tgtPk (New-ScriptingOption) } else { '' }
    if ($srcPkScript -ne $tgtPkScript) {
        $stmts = @('-- Primary key differs between source and target.')
        if ($tgtPk) { $stmts += "-- 1) Drop any FKs that reference this PK first, then:`r`nALTER TABLE $disp DROP CONSTRAINT [$($tgtPk.Name)];" }
        if ($srcPk) { $stmts += "-- 2) Recreate the primary key from source:`r`n$(Get-CleanDdl $srcPk);" }
        $summary = if (-not $tgtPk) { "Add primary key [$($srcPk.Name)]" }
                   elseif (-not $srcPk) { "Remove primary key [$($tgtPk.Name)]" }
                   else { "Change primary key [$($tgtPk.Name)] -> [$($srcPk.Name)]" }
        $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'pk_change' -Mode 'Manual' `
            -Summary $summary -Sql ($stmts -join "`r`n") `
            -RiskNote "Primary key changes can require dropping dependent FKs, deduplicating data and rebuilding the clustered index. Review carefully."))
    }

    # ---- Indexes (non-PK / non-unique-constraint) ---------------------------
    $srcIx = @{}; foreach ($x in $SrcTable.Indexes) { $srcIx[$x.Name] = $x }
    $tgtIx = @{}; foreach ($x in $TgtTable.Indexes) { $tgtIx[$x.Name] = $x }
    foreach ($iname in $srcIx.Keys) {
        $ix = $srcIx[$iname]
        $kind = $ix.IndexKeyType.ToString()
        if ($kind -eq 'DriPrimaryKey') { continue }             # handled above
        if ($kind -eq 'DriUniqueKey') {                          # unique constraint -> manual
            if (-not $tgtIx.ContainsKey($iname) -or (Get-CanonicalScript $ix (New-ScriptingOption)) -ne (Get-CanonicalScript $tgtIx[$iname] (New-ScriptingOption))) {
                $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'constraints' -Mode 'Manual' `
                    -Summary "Unique constraint [$iname] add/rebuild" -Sql "$(Get-CleanDdl $ix);" `
                    -RiskNote "Adding/altering a UNIQUE constraint fails if duplicate data exists. Deduplicate first."))
            }
            continue
        }
        # Regular index
        $guardExists = "EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'$iname' AND object_id = OBJECT_ID($objId))"
        if (-not $tgtIx.ContainsKey($iname)) {
            $sql = "IF NOT $guardExists`r`n$(Get-CleanDdl $ix);"
            $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'index' -Mode 'Auto' `
                -Summary "Create index [$iname]" -Sql $sql))
        } elseif ((Get-CanonicalScript $ix (New-ScriptingOption)) -ne (Get-CanonicalScript $tgtIx[$iname] (New-ScriptingOption))) {
            $sql = "IF $guardExists`r`n    DROP INDEX [$iname] ON $disp;`r`n$(Get-CleanDdl $ix);"
            $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'index' -Mode 'Auto' `
                -Summary "Rebuild index [$iname] (definition changed)" -Sql $sql))
        }
    }
    foreach ($iname in $tgtIx.Keys) {
        if ($srcIx.ContainsKey($iname)) { continue }
        $ix = $tgtIx[$iname]
        if ($ix.IndexKeyType.ToString() -ne 'None') { continue }  # PK/unique handled elsewhere
        if ($IncludeDrops) {
            $sql = "IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'$iname' AND object_id = OBJECT_ID($objId))`r`n    DROP INDEX [$iname] ON $disp;"
            $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'index' -Mode 'Auto' `
                -Summary "Drop index [$iname] (target-only)" -Sql $sql))
        }
    }

    # ---- Foreign keys & check constraints -----------------------------------
    $constraintSets = @(
        @{ Prop = 'ForeignKeys'; Catalog = 'sys.foreign_keys';     Label = 'FK'    }
        @{ Prop = 'Checks';      Catalog = 'sys.check_constraints'; Label = 'CHECK' }
    )
    foreach ($set in $constraintSets) {
        $prop = $set.Prop
        if (-not $SrcTable.PSObject.Properties[$prop]) { continue }
        $srcC = @{}; foreach ($x in $SrcTable.$prop) { $srcC[$x.Name] = $x }
        $tgtC = @{}; foreach ($x in $TgtTable.$prop) { $tgtC[$x.Name] = $x }
        foreach ($cn in $srcC.Keys) {
            $c = $srcC[$cn]
            $guard = "EXISTS (SELECT 1 FROM $($set.Catalog) WHERE name = N'$cn' AND parent_object_id = OBJECT_ID($objId))"
            if (-not $tgtC.ContainsKey($cn)) {
                $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'constraints' -Mode 'Auto' `
                    -Summary "Add $($set.Label) [$cn]" -Sql "IF NOT $guard`r`n$(Get-CleanDdl $c);"))
            } elseif ((Get-CanonicalScript $c (New-ScriptingOption)) -ne (Get-CanonicalScript $tgtC[$cn] (New-ScriptingOption))) {
                $sql = "IF $guard`r`n    ALTER TABLE $disp DROP CONSTRAINT [$cn];`r`n$(Get-CleanDdl $c);"
                $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'constraints' -Mode 'Auto' `
                    -Summary "Rebuild $($set.Label) [$cn] (definition changed)" -Sql $sql))
            }
        }
        foreach ($cn in $tgtC.Keys) {
            if ($srcC.ContainsKey($cn) -or -not $IncludeDrops) { continue }
            $sql = "IF EXISTS (SELECT 1 FROM $($set.Catalog) WHERE name = N'$cn' AND parent_object_id = OBJECT_ID($objId))`r`n    ALTER TABLE $disp DROP CONSTRAINT [$cn];"
            $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'constraints' -Mode 'Auto' `
                -Summary "Drop $($set.Label) [$cn] (target-only)" -Sql $sql))
        }
    }

    # ---- Table (DML) triggers ------------------------------------------------
    if ($SrcTable.PSObject.Properties['Triggers']) {
        $srcT = @{}; foreach ($x in $SrcTable.Triggers) { $srcT[$x.Name] = $x }
        $tgtT = @{}; foreach ($x in $TgtTable.Triggers) { $tgtT[$x.Name] = $x }
        foreach ($tn in $srcT.Keys) {
            $trg = $srcT[$tn]
            if (-not $tgtT.ContainsKey($tn) -or (Get-CanonicalScript $trg (New-ScriptingOption)) -ne (Get-CanonicalScript $tgtT[$tn] (New-ScriptingOption))) {
                $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'trigger' -Mode 'Auto' `
                    -Summary "Create/alter trigger [$tn]" -Sql (ConvertTo-CreateOrAlter (Get-CleanDdl $trg))))
            }
        }
        foreach ($tn in $tgtT.Keys) {
            if ($srcT.ContainsKey($tn) -or -not $IncludeDrops) { continue }
            $changes.Add((New-Change -Display $disp -KeySafe $key -Category 'trigger' -Mode 'Auto' `
                -Summary "Drop trigger [$tn] (target-only)" -Sql "IF OBJECT_ID(N'[$($SrcTable.Schema)].[$tn]', N'TR') IS NOT NULL`r`n    DROP TRIGGER [$($SrcTable.Schema)].[$tn];"))
        }
    }

    return $changes
}

function ConvertTo-CreateOrAlter {
    <# Rewrite a leading CREATE <PROC|VIEW|FUNCTION|TRIGGER> as CREATE OR ALTER so the
       generated script is idempotent and safe to run at once (SQL 2016 SP1+). #>
    param([string]$Ddl)
    return ($Ddl -replace '(?is)^\s*CREATE\s+(PROCEDURE|PROC|VIEW|FUNCTION|TRIGGER)\b', 'CREATE OR ALTER $1')
}

# ---------------------------------------------------------------------------
#  Core per-database comparison
# ---------------------------------------------------------------------------
function Compare-Database {
    param($SrcServer, $TgtServer, [string]$SrcDbName, [string]$TgtDbName)

    $srcDb = $SrcServer.Databases[$SrcDbName]
    $tgtDb = $TgtServer.Databases[$TgtDbName]
    if (-not $srcDb) { throw "Source database '$SrcDbName' not found on $($SrcServer.Name)." }
    if (-not $tgtDb) { throw "Target database '$TgtDbName' not found on $($TgtServer.Name)." }

    $types = if ($IncludeObjectType) {
        $script:ObjectTypeOrder | Where-Object { $_ -in $IncludeObjectType }
    } else { $script:ObjectTypeOrder }

    $diffs   = [System.Collections.Generic.List[pscustomobject]]::new()
    $changes = [System.Collections.Generic.List[object]]::new()

    # Map an object-type collection to its purpose + generation style.
    $purposeMap = @{
        'Schemas'               = @{ Purpose = 'schema';           Programmable = $false }
        'UserDefinedDataTypes'  = @{ Purpose = 'type';             Programmable = $false }
        'UserDefinedTableTypes' = @{ Purpose = 'type';             Programmable = $false }
        'Sequences'             = @{ Purpose = 'sequence';         Programmable = $false }
        'Synonyms'              = @{ Purpose = 'synonym';          Programmable = $false }
        'Views'                 = @{ Purpose = 'view';             Programmable = $true  }
        'UserDefinedFunctions'  = @{ Purpose = 'function';         Programmable = $true  }
        'StoredProcedures'      = @{ Purpose = 'stored_procedure'; Programmable = $true  }
        'DatabaseTriggers'      = @{ Purpose = 'db_trigger';       Programmable = $true  }
    }

    foreach ($type in $types) {
        Write-Log "  Comparing $type ..." 'Yellow'

        $srcObjs = @(Get-CollectionFor $srcDb $type | Where-Object {
            -not (Test-IsSystemObject $_) -and (Get-ObjectSchema $_) -notin $ExcludeSchema })
        $tgtObjs = @(Get-CollectionFor $tgtDb $type | Where-Object {
            -not (Test-IsSystemObject $_) -and (Get-ObjectSchema $_) -notin $ExcludeSchema })

        $tgtIndex = @{}; foreach ($o in $tgtObjs) { $tgtIndex[(Get-ObjectKey $o $type)] = $o }
        $srcIndex = @{}; foreach ($o in $srcObjs) { $srcIndex[(Get-ObjectKey $o $type)] = $o }

        foreach ($srcObj in $srcObjs) {
            $key    = Get-ObjectKey $srcObj $type
            $disp   = Get-DisplayName $srcObj $type
            $tgtObj = $tgtIndex[$key]
            $safeKey = ($key -replace '[^\w.-]', '_')

            if (-not $tgtObj) {
                $diffs.Add([pscustomobject]@{ Database=$SrcDbName; ObjectType=$type; ObjectName=$disp; Status='Missing in Target'; Details="Absent on $($TgtServer.Name)" })

                if ($type -eq 'Tables') {
                    $changes.Add((New-Change -Display $disp -KeySafe $safeKey -Category 'table_create' -Mode 'Auto' `
                        -Summary "Create table $disp" -Sql $(if ($GenerateSyncScript) { Get-TableCreateSql $srcObj } else { '' })))
                    if ($srcObj.PSObject.Properties['ForeignKeys']) {
                        foreach ($fk in $srcObj.ForeignKeys) {
                            $g = "EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'$($fk.Name)' AND parent_object_id = OBJECT_ID(N'$disp'))"
                            $changes.Add((New-Change -Display $disp -KeySafe $safeKey -Category 'constraints' -Mode 'Auto' `
                                -Summary "Add FK [$($fk.Name)]" -Sql $(if ($GenerateSyncScript) { "IF NOT $g`r`n$(Get-CleanDdl $fk);" } else { '' })))
                        }
                    }
                } else {
                    $changes.Add((New-ObjectCreateChange -Obj $srcObj -Type $type -Disp $disp -KeySafe $safeKey -Meta $purposeMap[$type] -IsNew))
                }
                continue
            }

            if ((Get-CanonicalScript $srcObj (New-ScriptingOption)) -eq (Get-CanonicalScript $tgtObj (New-ScriptingOption))) { continue }

            $diffs.Add([pscustomobject]@{ Database=$SrcDbName; ObjectType=$type; ObjectName=$disp; Status='Definition Mismatch'; Details='Structure or code differs' })

            if ($type -eq 'Tables') {
                foreach ($c in (Get-TableChangeSet -SrcTable $srcObj -TgtTable $tgtObj -IncludeDrops:$IncludeDrops)) {
                    if (-not $GenerateSyncScript) { $c | Add-Member -NotePropertyName Sql -NotePropertyValue '' -Force }
                    $changes.Add($c)
                }
            } else {
                $changes.Add((New-ObjectCreateChange -Obj $srcObj -Type $type -Disp $disp -KeySafe $safeKey -Meta $purposeMap[$type]))
            }
        }

        # Extra in target (exists only on target)
        foreach ($tgtObj in $tgtObjs) {
            $key = Get-ObjectKey $tgtObj $type
            if ($srcIndex.ContainsKey($key)) { continue }
            $disp = Get-DisplayName $tgtObj $type
            $safeKey = ($key -replace '[^\w.-]', '_')
            $diffs.Add([pscustomobject]@{ Database=$SrcDbName; ObjectType=$type; ObjectName=$disp; Status='Extra in Target'; Details="Only on $($TgtServer.Name)" })

            if ($type -eq 'Tables') {
                # Dropping a table destroys data -> always manual.
                $changes.Add((New-Change -Display $disp -KeySafe $safeKey -Category 'cleanup_drop' -Mode 'Manual' `
                    -Summary "Drop table $disp (target-only)" `
                    -Sql "IF OBJECT_ID(N'$disp', N'U') IS NOT NULL`r`n    DROP TABLE $disp;" `
                    -RiskNote "Dropping a table permanently destroys its data. Confirm it is obsolete and backed up."))
            } elseif ($IncludeDrops) {
                $changes.Add((New-ObjectDropChange -Obj $tgtObj -Type $type -Disp $disp -KeySafe $safeKey))
            }
        }
    }

    return [pscustomobject]@{
        Database    = $SrcDbName
        Differences = $diffs
        Changes     = $changes
    }
}

function Get-TableCreateSql {
    <#
        Idempotent CREATE TABLE (without FKs). Uses chunked nvarchar(max) assignment so
        wide tables with long inline defaults never hit the implicit 4000-char literal cap.
    #>
    param($Table)
    $opt   = New-ScriptingOption -NoForeignKeys
    $raw   = (@($Table.Script($opt)) -join "`n")
    $body  = (Normalize-SqlScriptText $raw).TrimEnd(';')
    $disp  = "[$($Table.Schema)].[$($Table.Name)]"
    $assign = ConvertTo-ChunkedNvarcharMaxAssignment -VariableName '@sql_create' -SqlBody $body
    return @"
IF OBJECT_ID(N'$disp', N'U') IS NULL
BEGIN
    $assign
    EXEC sys.sp_executesql @sql_create;
END
"@
}

function New-ObjectCreateChange {
    <# Build a create/alter change for a non-table object (programmable or metadata). #>
    param($Obj, [string]$Type, [string]$Disp, [string]$KeySafe, $Meta, [switch]$IsNew)
    $purpose = $Meta.Purpose
    $verb    = if ($IsNew) { 'Create' } else { 'Alter' }

    if ($Meta.Programmable) {
        $sql = ConvertTo-CreateOrAlter (Get-CleanDdl $Obj)
        return (New-Change -Display $Disp -KeySafe $KeySafe -Category $purpose -Mode 'Auto' `
            -Summary "$verb $purpose $Disp" -Sql $sql)
    }
    switch ($purpose) {
        'schema' {
            $sql = "IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'$($Obj.Name)')`r`n    EXEC (N'CREATE SCHEMA [$($Obj.Name)]');"
            return (New-Change -Display $Disp -KeySafe $KeySafe -Category 'schema' -Mode 'Auto' -Summary "Create schema [$($Obj.Name)]" -Sql $sql)
        }
        'type' {
            if ($IsNew) {
                $sql = "IF TYPE_ID(N'$Disp') IS NULL`r`nBEGIN`r`n    $(Get-CleanDdl $Obj);`r`nEND"
                return (New-Change -Display $Disp -KeySafe $KeySafe -Category 'type' -Mode 'Auto' -Summary "Create type $Disp" -Sql $sql)
            }
            return (New-Change -Display $Disp -KeySafe $KeySafe -Category 'type' -Mode 'Manual' `
                -Summary "Type $Disp differs (rebuild)" -Sql "-- Types in use cannot be altered; drop dependents, DROP TYPE, then:`r`n$(Get-CleanDdl $Obj);" `
                -RiskNote "A user-defined type cannot be altered and cannot be dropped while columns/params use it. Rebuild manually.")
        }
        'sequence' {
            $g = "OBJECT_ID(N'$Disp') IS"
            if ($IsNew) { $sql = "IF $g NULL`r`n    $(Get-CleanDdl $Obj);" }
            else        { $sql = "IF $g NOT NULL`r`n    DROP SEQUENCE $Disp;`r`n$(Get-CleanDdl $Obj);" }
            return (New-Change -Display $Disp -KeySafe $KeySafe -Category 'sequence' -Mode 'Auto' -Summary "$verb sequence $Disp" -Sql $sql)
        }
        'synonym' {
            $g = "OBJECT_ID(N'$Disp') IS"
            if ($IsNew) { $sql = "IF $g NULL`r`n    $(Get-CleanDdl $Obj);" }
            else        { $sql = "IF $g NOT NULL`r`n    DROP SYNONYM $Disp;`r`n$(Get-CleanDdl $Obj);" }
            return (New-Change -Display $Disp -KeySafe $KeySafe -Category 'synonym' -Mode 'Auto' -Summary "$verb synonym $Disp" -Sql $sql)
        }
    }
}

function New-ObjectDropChange {
    <# Build a (safe) drop change for a target-only non-table object. #>
    param($Obj, [string]$Type, [string]$Disp, [string]$KeySafe)
    $sql = switch ($Type) {
        'Views'                { "IF OBJECT_ID(N'$Disp', N'V')  IS NOT NULL DROP VIEW $Disp;" }
        'StoredProcedures'     { "IF OBJECT_ID(N'$Disp', N'P')  IS NOT NULL DROP PROCEDURE $Disp;" }
        'UserDefinedFunctions' { "IF OBJECT_ID(N'$Disp') IS NOT NULL DROP FUNCTION $Disp;" }
        'Synonyms'             { "IF OBJECT_ID(N'$Disp', N'SN') IS NOT NULL DROP SYNONYM $Disp;" }
        'Sequences'            { "IF OBJECT_ID(N'$Disp', N'SO') IS NOT NULL DROP SEQUENCE $Disp;" }
        'DatabaseTriggers'     { "IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = N'$($Obj.Name)' AND parent_class = 0) DROP TRIGGER [$($Obj.Name)] ON DATABASE;" }
        default                { "-- Manual drop required for $Type $Disp" }
    }
    return (New-Change -Display $Disp -KeySafe $KeySafe -Category 'cleanup_drop' -Mode 'Auto' -Summary "Drop $Type $Disp (target-only)" -Sql $sql)
}

# ---------------------------------------------------------------------------
#  Per-purpose script file writer
# ---------------------------------------------------------------------------
function Write-ChangeScripts {
    <#
        Group change records by (object, purpose, mode) and write one .sql file each,
        named  <auto|manual>_<db>__<object>__<purpose>.sql , with a metadata header and
        built-in validation. Returns manifest entries describing every file written.
    #>
    param($Changes, [string]$SrcInstance, [string]$SrcDbName, [string]$TgtInstance, [string]$TgtDbName, [string]$OutDir)

    # Categories whose statements must each be their own batch (CREATE OR ALTER etc.).
    $batchStyle = @('view','function','stored_procedure','db_trigger','trigger')
    $manifest   = [System.Collections.Generic.List[pscustomobject]]::new()

    $groups = $Changes | Group-Object -Property { "$($_.Mode)|$($_.ObjectKeySafe)|$($_.Category)" }
    foreach ($grp in $groups) {
        $items    = @($grp.Group)
        $first    = $items[0]
        $mode     = $first.Mode
        $category = $first.Category
        $order    = $first.Order
        $prefix   = if ($mode -eq 'Manual') { 'manual' } else { 'auto' }
        $dbSafe   = ($TgtDbName -replace '[^\w.-]', '_')
        $fileName = "${prefix}_${dbSafe}__$($first.ObjectKeySafe)__${category}.sql"
        $path     = Join-Path $OutDir $fileName

        # ---- Metadata header ----
        $head = [System.Collections.Generic.List[string]]::new()
        $head.Add("/* ============================================================")
        $head.Add(" *  $($mode.ToUpper()) schema change script")
        $head.Add(" *  Database : $TgtDbName")
        $head.Add(" *  Object   : $($first.ObjectDisplay)")
        $head.Add(" *  Purpose  : $category")
        $head.Add(" *  Source   : $SrcInstance / $SrcDbName")
        $head.Add(" *  Target   : $TgtInstance / $TgtDbName")
        $head.Add(" *  Generated: $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) UTC")
        $head.Add(" *  Run order: $order  (apply auto_ scripts in ascending run-order)")
        $head.Add(" *")
        $head.Add(" *  Changes ($($items.Count)):")
        foreach ($it in $items) { $head.Add(" *    - $($it.Summary)") }
        if ($mode -eq 'Manual') {
            $head.Add(" *")
            $head.Add(" *  !! MANUAL ACTION REQUIRED - review each item before running !!")
            foreach ($it in $items) { if ($it.RiskNote) { $head.Add(" *    RISK [$($it.Summary)]: $($it.RiskNote)") } }
        }
        foreach ($hl in (Get-SqlRunHeaderLines -ScriptFileName $fileName -TgtDbName $TgtDbName -TgtInstance $TgtInstance -RunFolder $OutDir -Kind 'Single')) {
            $head.Add($hl)
        }
        $head.Add(" * ============================================================ */")
        $head.Add("")
        $head.Add("USE [$TgtDbName];")
        $head.Add("GO")
        $head.Add("")

        $bodyLines = [System.Collections.Generic.List[string]]::new()

        if ($category -in $batchStyle -and $mode -eq 'Auto') {
            # Batch style: each statement in its own GO-separated batch, no wrapper.
            foreach ($it in $items) {
                $bodyLines.Add("-- $($it.Summary)")
                $bodyLines.Add($it.Sql)
                $bodyLines.Add("GO")
                $bodyLines.Add("")
            }
        } else {
            # Transactional style: single atomic batch with validation + rollback.
            $bodyLines.Add("SET XACT_ABORT ON;")
            $bodyLines.Add("SET NOCOUNT ON;")
            $bodyLines.Add("BEGIN TRY")
            $bodyLines.Add("    BEGIN TRANSACTION;")
            $bodyLines.Add("")
            foreach ($it in $items) {
                $bodyLines.Add("    -- $($it.Summary)")
                if ($mode -eq 'Manual' -and $it.RiskNote) { $bodyLines.Add("    -- RISK: $($it.RiskNote)") }
                foreach ($ln in ($it.Sql -split "`r?`n")) { $bodyLines.Add("    $ln") }
                $bodyLines.Add("")
            }
            $bodyLines.Add("    COMMIT TRANSACTION;")
            $bodyLines.Add("    PRINT 'SUCCESS: [$TgtDbName] $($first.ObjectDisplay) $category applied.';")
            $bodyLines.Add("END TRY")
            $bodyLines.Add("BEGIN CATCH")
            $bodyLines.Add("    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;")
            $bodyLines.Add("    PRINT 'FAILED: [$TgtDbName] $($first.ObjectDisplay) $category -> ' + ERROR_MESSAGE();")
            $bodyLines.Add("    THROW;")
            $bodyLines.Add("END CATCH")
            $bodyLines.Add("GO")
        }

        $content = (@($head) + @($bodyLines)) -join [Environment]::NewLine
        Set-Content -Path $path -Value $content -Encoding UTF8

        $manifest.Add([pscustomobject]@{
            Database    = $TgtDbName
            Object      = $first.ObjectDisplay
            Purpose     = $category
            Mode        = $mode
            Order       = $order
            ChangeCount = $items.Count
            FileName    = $fileName
            FilePath    = $path
        })
    }
    return $manifest
}

function Get-ScriptPhase {
    param([int]$Order, [string]$Mode, [string]$Purpose)
    if ($Mode -eq 'Manual') {
        switch ($Purpose) {
            'pk_change'      { return 'Manual: Primary Keys' }
            'column_remove'  { return 'Manual: Column Drops' }
            'table_rebuild'  { return 'Manual: Table Rebuild' }
            'cleanup_drop'   { return 'Manual: Object Cleanup' }
            default          { return 'Manual: Structural Review' }
        }
    }
    if ($Order -le 40)  { return '1 - Infrastructure' }
    if ($Order -le 70)  { return '2 - Tables & Columns' }
    if ($Order -le 100) { return '3 - Indexes & Constraints' }
    if ($Order -le 140) { return '4 - Programmable Objects' }
    return '5 - Other'
}

function Enrich-ManifestEntries {
    <#
        Add Phase, Blockers and Prerequisites so operators know which manual scripts
        must complete before a given auto step can succeed.
    #>
    param($Manifest)

    $manual = @($Manifest | Where-Object { $_.Mode -eq 'Manual' })
    $enriched = foreach ($entry in $Manifest) {
        $phase = Get-ScriptPhase -Order $entry.Order -Mode $entry.Mode -Purpose $entry.Purpose

        # Manual scripts that must run before this entry (same DB; lower order; same object
        # or a global blocker like a type rebuild).
        $blockers = @($manual | Where-Object {
            $_.Database -eq $entry.Database -and $_.Order -lt $entry.Order -and (
                $_.Object -eq $entry.Object -or
                $_.Purpose -eq 'type' -or
                ($_.Purpose -eq 'pk_change' -and $entry.Purpose -in @('index','constraints'))
            )
        } | Select-Object -ExpandProperty FileName -Unique)

        # Auto scripts on the same object that should already be applied before a manual step.
        $prereqs = if ($entry.Mode -eq 'Manual') {
            @($Manifest | Where-Object {
                $_.Mode -eq 'Auto' -and $_.Database -eq $entry.Database -and
                $_.Object -eq $entry.Object -and $_.Order -lt $entry.Order
            } | Select-Object -ExpandProperty FileName)
        } else { @() }

        [pscustomobject]@{
            Phase          = $phase
            Mode           = $entry.Mode
            Order          = $entry.Order
            Database       = $entry.Database
            Object         = $entry.Object
            Purpose        = $entry.Purpose
            ChangeCount    = $entry.ChangeCount
            FileName       = $entry.FileName
            FilePath       = $entry.FilePath
            Blockers       = ($blockers -join '; ')
            Prerequisites  = ($prereqs -join '; ')
            RequiresReview = [bool]($entry.Mode -eq 'Manual')
        }
    }
    return @($enriched)
}

function Get-SqlRunHeaderLines {
    <# Emit copy-paste run instructions for generated SQL on the TARGET server. #>
    param(
        [string]$ScriptFileName,
        [string]$TgtDbName,
        [string]$TgtInstance,
        [string]$RunFolder,
        [ValidateSet('Master','AutoOnly','Single')]
        [string]$Kind = 'Single'
    )
    $lines  = [System.Collections.Generic.List[string]]::new()
    $lines.Add(' *')
    $lines.Add(' *  WHERE TO RUN: TARGET server only (never on source).')
    $lines.Add(" *  TARGET     : $TgtInstance")
    $lines.Add(" *  DATABASE   : $TgtDbName")
    $lines.Add(" *  RUN FOLDER : $RunFolder")
    $lines.Add(' *')
    switch ($Kind) {
        'AutoOnly' {
            $lines.Add(' *  WHICH FILE : _master_auto_only.sql  <-- use this for one-shot auto apply')
            $lines.Add(' *  PURPOSE    : Applies all auto_ scripts in order (safe changes only).')
            $lines.Add(' *               Does NOT run manual_ scripts. Use when no manual_ files exist,')
            $lines.Add(' *               or after you have already executed every manual_ script.')
        }
        'Master' {
            $lines.Add(' *  WHICH FILE : _master_migration.sql  <-- use this for guided promotion')
            $lines.Add(' *  PURPOSE    : Full runbook: auto_ phases + MANUAL ACTION checkpoints.')
            $lines.Add(' *               Stop at each checkpoint, run listed manual_ files, then continue.')
            $lines.Add(' *               Prefer this for UAT/Prod when manual_ scripts exist.')
        }
        'Single' {
            $lines.Add(" *  FILE       : $ScriptFileName")
            $lines.Add(' *  PURPOSE    : Single object/purpose change. Run after lower run-order scripts.')
            $lines.Add(' *               Or use _master_auto_only.sql / _master_migration.sql instead.')
        }
    }
    $lines.Add(' *')
    $lines.Add(' *  PREREQUISITE: cd to the run folder so :r includes resolve (master files only).')
    $lines.Add(' *')
    $lines.Add(' *  --- Copy/paste: PowerShell (run from any machine that reaches TARGET SQL) ---')
    $lines.Add(' *')
    $lines.Add(" *  cd `"$RunFolder`"")
    $lines.Add(' *')
    $lines.Add(' *  # SQL login (replace user/password):')
    $lines.Add(" *  sqlcmd -S $TgtInstance -d $TgtDbName -U YourSqlLogin -P `"YourPassword`" -C -i `".\$ScriptFileName`"")
    $lines.Add(' *')
    $lines.Add(' *  # Windows auth (if TARGET trusts your Windows account):')
    $lines.Add(" *  sqlcmd -S $TgtInstance -d $TgtDbName -E -C -i `".\$ScriptFileName`"")
    $lines.Add(' *')
    $lines.Add(' *  --- SSMS alternative (single .sql file, not master :r runner) ---')
    $lines.Add(' *  Open the .sql file in SSMS -> connect to TARGET -> execute.')
    $lines.Add(' *  For _master_*.sql, sqlcmd is required (:r includes). SSMS: enable Query -> SQLCMD Mode.')
    return $lines
}

function Write-MasterMigrationCatalog {
    <#
        Emit a unified migration catalog that sequences auto_ scripts in run-order and
        inserts /* MANUAL ACTION REQUIRED */ checkpoints wherever manual blockers exist.
        Intended for sqlcmd (:r includes) or as an operator runbook in SSMS.
    #>
    param($EnrichedManifest, [string]$TgtDbName, [string]$OutDir, [string]$SrcInstance, [string]$TgtInstance)

    $sorted = @($EnrichedManifest | Sort-Object Order, Mode, FileName)
    $auto   = @($sorted | Where-Object { $_.Mode -eq 'Auto' })
    $manual = @($sorted | Where-Object { $_.Mode -eq 'Manual' })

    $phaseOrder = @(
        '1 - Infrastructure', '2 - Tables & Columns', '3 - Indexes & Constraints',
        '4 - Programmable Objects', '5 - Other'
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('/* ============================================================')
    $lines.Add(' *  MASTER MIGRATION CATALOG  (_master_migration.sql)')
    $lines.Add(" *  Database : $TgtDbName")
    $lines.Add(" *  Source   : $SrcInstance  (reference only — do not run scripts there)")
    $lines.Add(" *  Target   : $TgtInstance  (run all scripts here)")
    $lines.Add(" *  Generated: $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) UTC")
    $lines.Add(" *  Auto scripts  : $($auto.Count)")
    $lines.Add(" *  Manual scripts: $($manual.Count)")
    foreach ($hl in (Get-SqlRunHeaderLines -ScriptFileName '_master_migration.sql' -TgtDbName $TgtDbName -TgtInstance $TgtInstance -RunFolder $OutDir -Kind 'Master')) {
        $lines.Add($hl)
    }
    $lines.Add(' * ============================================================ */')
    $lines.Add('')
    $lines.Add("USE [$TgtDbName];")
    $lines.Add('GO')
    $lines.Add('')

    foreach ($phase in $phaseOrder) {
        $phaseAuto = @($auto | Where-Object { $_.Phase -eq $phase })
        if ($phaseAuto.Count -eq 0) { continue }

        # Checkpoint: list manual scripts that block any auto step in this phase.
        $blockingNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($f in $phaseAuto) {
            if (-not $f.Blockers) { continue }
            foreach ($bn in ($f.Blockers -split ';')) {
                $name = $bn.Trim()
                if ($name) { [void]$blockingNames.Add($name) }
            }
        }
        if ($blockingNames.Count -gt 0) {
            $lines.Add('/* ============================================================')
            $lines.Add(' *  MANUAL ACTION REQUIRED - complete before this phase')
            foreach ($b in ($manual | Where-Object { $blockingNames.Contains($_.FileName) })) {
                $lines.Add(" *    $($b.FileName)  [$($b.Purpose)]  $($b.Object)")
                if ($b.Prerequisites) { $lines.Add(" *      prerequisites: $($b.Prerequisites)") }
            }
            $lines.Add(' * ============================================================ */')
            $lines.Add('')
        }

        $lines.Add("/* === PHASE: $phase === */")
        foreach ($f in $phaseAuto) {
            $lines.Add("-- $($f.FileName)  ($($f.Object) / $($f.Purpose))")
            $lines.Add(":r $($f.FileName)")
            $lines.Add('GO')
            $lines.Add('')
        }
    }

    if ($manual.Count -gt 0) {
        $lines.Add('/* ============================================================')
        $lines.Add(' *  FINAL MANUAL ACTIONS (not included in auto sequence)')
        $lines.Add(' *  Review each script; run only after all auto phases succeed.')
        $lines.Add(' * ============================================================ */')
        foreach ($m in $manual) {
            $lines.Add("-- MANUAL: $($m.FileName)")
            $lines.Add("--   Object  : $($m.Object)")
            $lines.Add("--   Purpose : $($m.Purpose)")
            if ($m.Prerequisites) { $lines.Add("--   Run after: $($m.Prerequisites)") }
            $lines.Add("-- :r $($m.FileName)")
            $lines.Add('')
        }
    }

    $masterPath = Join-Path $OutDir '_master_migration.sql'
    Set-Content -Path $masterPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8

    # Operator quick-reference (plain text, same folder).
    $readme = @(
        "SCHEMA SYNC — RUN ON TARGET SERVER ONLY"
        "========================================"
        "Target instance : $TgtInstance"
        "Target database : $TgtDbName"
        "Source (ref)    : $SrcInstance"
        "Generated (UTC) : $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss'))"
        "Run folder      : $OutDir"
        ""
        "WHICH FILE TO RUN ON TARGET?"
        ""
        "  _master_auto_only.sql"
        "    -> One-shot apply of ALL auto_ scripts (safe changes only)."
        "    -> Use when NO manual_ scripts exist, OR manual_ scripts are already done."
        "    -> Best for CI / dev->uat when everything is auto-safe."
        ""
        "  _master_migration.sql"
        "    -> Guided runbook with MANUAL ACTION checkpoints between phases."
        "    -> Use for UAT/Prod when manual_*.sql files exist (PK changes, etc.)."
        "    -> Stop at each checkpoint, run listed manual_ files, then continue."
        ""
        "COPY/PASTE (PowerShell — cd to this folder first):"
        ""
        "  cd `"$OutDir`""
        ""
        "  sqlcmd -S $TgtInstance -d $TgtDbName -U YourSqlLogin -P `"YourPassword`" -C -i `".\_master_auto_only.sql`""
        ""
        "  sqlcmd -S $TgtInstance -d $TgtDbName -E -C -i `".\_master_auto_only.sql`""
        ""
        "See _manifest.csv for run order. Never run on source."
    ) -join [Environment]::NewLine
    Set-Content -Path (Join-Path $OutDir '_README_RUN_ON_TARGET.txt') -Value $readme -Encoding UTF8

    # Compact auto-only runner (no manual checkpoints) for -Apply / CI.
    $autoOnly = [System.Collections.Generic.List[string]]::new()
    $autoOnly.Add('/* ============================================================')
    $autoOnly.Add(' *  AUTO-ONLY RUNNER  (_master_auto_only.sql)')
    $autoOnly.Add(" *  Database : $TgtDbName")
    $autoOnly.Add(" *  Source   : $SrcInstance  (reference only — do not run scripts there)")
    $autoOnly.Add(" *  Target   : $TgtInstance  (run all scripts here)")
    $autoOnly.Add(" *  Generated: $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) UTC")
    $autoOnly.Add(" *  Auto scripts included: $($auto.Count)")
    if ($manual.Count -gt 0) {
        $autoOnly.Add(" *  WARNING: $($manual.Count) manual_ script(s) exist and are NOT in this file.")
        $autoOnly.Add(' *           Run them separately before/after — see _master_migration.sql.')
    }
    foreach ($hl in (Get-SqlRunHeaderLines -ScriptFileName '_master_auto_only.sql' -TgtDbName $TgtDbName -TgtInstance $TgtInstance -RunFolder $OutDir -Kind 'AutoOnly')) {
        $autoOnly.Add($hl)
    }
    $autoOnly.Add(' * ============================================================ */')
    $autoOnly.Add('')
    $autoOnly.Add("USE [$TgtDbName];"); $autoOnly.Add('GO'); $autoOnly.Add('')
    foreach ($f in $auto) {
        $autoOnly.Add(":r $($f.FileName)"); $autoOnly.Add('GO'); $autoOnly.Add('')
    }
    $autoPath = Join-Path $OutDir '_master_auto_only.sql'
    Set-Content -Path $autoPath -Value ($autoOnly -join [Environment]::NewLine) -Encoding UTF8

    return @{ Master = $masterPath; AutoOnly = $autoPath }
}

function Export-HtmlReport {
    param(
        $AllResults,
        [string]$SrcInstance,
        [string]$TgtInstance,
        $SrcServer,
        $TgtServer,
        $DatabasePairs,
        [string]$Path
    )

    $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
    $nowLocal = Get-Date
    $nowUtc   = [DateTime]::UtcNow

    $allDiffs = foreach ($r in $AllResults) { $r.Differences }
    $total    = @($allDiffs).Count

    $added   = @($allDiffs | Where-Object { $_.Status -eq 'Missing in Target' })
    $changed = @($allDiffs | Where-Object { $_.Status -eq 'Definition Mismatch' })
    $extra   = @($allDiffs | Where-Object { $_.Status -eq 'Extra in Target' })

    $newTables     = @($added   | Where-Object { $_.ObjectType -eq 'Tables' })
    $changedTables = @($changed | Where-Object { $_.ObjectType -eq 'Tables' })
    $extraTables   = @($extra   | Where-Object { $_.ObjectType -eq 'Tables' })

    $byType = $allDiffs | Group-Object ObjectType | Sort-Object Name

    $actionLabel = {
        param($Status)
        switch ($Status) {
            'Missing in Target'   { return 'Add to Target' }
            'Definition Mismatch' { return 'Update on Target' }
            'Extra in Target'     { return 'Extra on Target' }
            default               { return $Status }
        }
    }

    $detailRows = foreach ($d in $allDiffs) {
        $cls = switch ($d.Status) {
            'Missing in Target'   { 'miss' }
            'Extra in Target'     { 'extra' }
            'Definition Mismatch' { 'diff' }
            default               { '' }
        }
        $action = & $actionLabel $d.Status
        "<tr class='$cls'>" +
        "<td>$(& $enc $d.Database)</td>" +
        "<td>$(& $enc $d.ObjectType)</td>" +
        "<td>$(& $enc $d.ObjectName)</td>" +
        "<td><span class='badge $cls'>$(& $enc $action)</span></td>" +
        "<td>$(& $enc $d.Status)</td>" +
        "<td>$(& $enc $d.Details)</td></tr>"
    }

    $typeBreakdownRows = foreach ($g in $byType) {
        $tAdded   = @($g.Group | Where-Object { $_.Status -eq 'Missing in Target' }).Count
        $tChanged = @($g.Group | Where-Object { $_.Status -eq 'Definition Mismatch' }).Count
        $tExtra   = @($g.Group | Where-Object { $_.Status -eq 'Extra in Target' }).Count
        "<tr><td>$(& $enc $g.Name)</td><td class='num'>$tAdded</td><td class='num'>$tChanged</td>" +
        "<td class='num'>$tExtra</td><td class='num'>$($g.Count)</td></tr>"
    }

    $dbRows = foreach ($pair in $DatabasePairs) {
        $srcDb = $pair.Source; $tgtDb = $pair.Target
        $dbDiffs = @($allDiffs | Where-Object { $_.Database -eq $srcDb })
        $r = $AllResults | Where-Object { $_.Database -eq $srcDb } | Select-Object -First 1
        $chgCount = if ($r -and $r.Changes) { $r.Changes.Count } else { 0 }
        "<tr><td>$(& $enc $srcDb)</td><td>$(& $enc $tgtDb)</td>" +
        "<td class='num'>$($dbDiffs.Count)</td><td class='num'>$chgCount</td></tr>"
    }

    # Summaries from generated change records (column adds, index rebuilds, etc.)
    $changeDetailRows = foreach ($r in $AllResults) {
        if (-not $r.Changes) { continue }
        foreach ($c in $r.Changes) {
            $modeCls = if ($c.Mode -eq 'Manual') { 'manual' } else { 'auto' }
            "<tr class='$modeCls'><td>$(& $enc $r.Database)</td><td>$(& $enc $c.ObjectDisplay)</td>" +
            "<td>$(& $enc $c.Category)</td><td>$(& $enc $c.Mode)</td>" +
            "<td>$(& $enc $c.Summary)</td></tr>"
        }
    }
    $hasChangeDetails = $changeDetailRows.Count -gt 0

    $srcVer = if ($SrcServer) { $SrcServer.VersionString } else { 'n/a' }
    $tgtVer = if ($TgtServer) { $TgtServer.VersionString } else { 'n/a' }
    $srcName = if ($SrcServer) { $SrcServer.Name } else { $SrcInstance }
    $tgtName = if ($TgtServer) { $TgtServer.Name } else { $TgtInstance }

    $addedList = if ($added.Count -gt 0) {
        ($added | ForEach-Object { "<li><b>$(& $enc $_.ObjectType)</b> $(& $enc $_.ObjectName)</li>" }) -join "`n"
    } else { '<li class="none">None</li>' }

    $changedList = if ($changed.Count -gt 0) {
        ($changed | Select-Object -First 50 | ForEach-Object { "<li><b>$(& $enc $_.ObjectType)</b> $(& $enc $_.ObjectName)</li>" }) -join "`n" +
        $(if ($changed.Count -gt 50) { "<li><em>… and $($changed.Count - 50) more (see detail table)</em></li>" } else { '' })
    } else { '<li class="none">None</li>' }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Schema Comparison Report</title>
<style>
:root{--bg:#f6f8fa;--card:#fff;--border:#d0d7de;--text:#1b1f23;--muted:#57606a;--miss:#fff8e1;--extra:#ffebee;--diff:#e8f4fd;--ok:#1a7f37}
*{box-sizing:border-box}
body{font-family:Segoe UI,Arial,sans-serif;margin:0;padding:24px;color:var(--text);background:var(--bg);line-height:1.45}
h1{font-size:22px;margin:0 0 8px}
h2{font-size:16px;margin:28px 0 12px;border-bottom:1px solid var(--border);padding-bottom:6px}
.meta{color:var(--muted);font-size:13px;margin-bottom:20px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin:16px 0}
.card{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:14px 16px;box-shadow:0 1px 2px rgba(0,0,0,.06)}
.card .label{font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted)}
.card .value{font-size:26px;font-weight:600;margin-top:4px}
.card .sub{font-size:12px;color:var(--muted);margin-top:4px}
.servers{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin:16px 0}
@media(max-width:700px){.servers{grid-template-columns:1fr}}
.server{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:14px 16px}
.server h3{margin:0 0 8px;font-size:14px}
.server dl{margin:0;font-size:13px}
.server dt{float:left;clear:left;width:110px;color:var(--muted)}
.server dd{margin:0 0 4px 120px}
table{border-collapse:collapse;width:100%;background:var(--card);box-shadow:0 1px 3px rgba(0,0,0,.08);font-size:13px}
th,td{border:1px solid var(--border);padding:8px 10px;text-align:left;vertical-align:top}
th{background:#24292f;color:#fff;position:sticky;top:0;z-index:1}
tr.miss td{background:var(--miss)}
tr.extra td{background:var(--extra)}
tr.diff td{background:var(--diff)}
tr.manual td{background:#fce4ec}
td.num{text-align:right;font-variant-numeric:tabular-nums}
.badge{display:inline-block;padding:2px 8px;border-radius:4px;font-size:11px;font-weight:600}
.badge.miss{background:#f9a825;color:#3e2723}
.badge.diff{background:#039be5;color:#fff}
.badge.extra{background:#e53935;color:#fff}
.cols2{display:grid;grid-template-columns:1fr 1fr;gap:16px}
@media(max-width:800px){.cols2{grid-template-columns:1fr}}
ul.compact{margin:8px 0;padding-left:20px;font-size:13px;max-height:280px;overflow-y:auto}
ul.compact li.none{color:var(--muted);list-style:none;margin-left:-20px}
.ok{color:var(--ok);font-weight:600;padding:16px;background:var(--card);border-radius:8px;border:1px solid var(--border)}
.footer{margin-top:32px;font-size:11px;color:var(--muted)}
</style>
</head>
<body>
<h1>Schema Comparison Report</h1>
<div class="meta">
  Comparison run: <b>$($nowLocal.ToString('yyyy-MM-dd HH:mm:ss'))</b> (local)
  &middot; <b>$($nowUtc.ToString('yyyy-MM-dd HH:mm:ss'))</b> UTC
  &middot; Report ID: <b>SchemaCompare_$($nowLocal.ToString('yyyyMMdd_HHmmss'))</b>
</div>

<div class="servers">
  <div class="server source">
    <h3>Source (source of truth)</h3>
    <dl>
      <dt>Connection</dt><dd>$(& $enc $SrcInstance)</dd>
      <dt>Server name</dt><dd>$(& $enc $srcName)</dd>
      <dt>Version</dt><dd>$(& $enc $srcVer)</dd>
    </dl>
  </div>
  <div class="server target">
    <h3>Target (to be synced)</h3>
    <dl>
      <dt>Connection</dt><dd>$(& $enc $TgtInstance)</dd>
      <dt>Server name</dt><dd>$(& $enc $tgtName)</dd>
      <dt>Version</dt><dd>$(& $enc $tgtVer)</dd>
    </dl>
  </div>
</div>

<h2>Databases compared</h2>
<table>
<thead><tr><th>Source database</th><th>Target database</th><th>Differences</th><th>Sync change records</th></tr></thead>
<tbody>
$dbRows
</tbody>
</table>

<h2>Executive summary</h2>
<div class="grid">
  <div class="card"><div class="label">Total differences</div><div class="value">$total</div></div>
  <div class="card"><div class="label">To add on target</div><div class="value">$($added.Count)</div><div class="sub">Missing in target</div></div>
  <div class="card"><div class="label">To update on target</div><div class="value">$($changed.Count)</div><div class="sub">Definition mismatch</div></div>
  <div class="card"><div class="label">Extra on target only</div><div class="value">$($extra.Count)</div><div class="sub">Not in source</div></div>
  <div class="card"><div class="label">New tables</div><div class="value">$($newTables.Count)</div><div class="sub">Tables to create</div></div>
  <div class="card"><div class="label">Changed tables</div><div class="value">$($changedTables.Count)</div><div class="sub">Structural drift</div></div>
  <div class="card"><div class="label">Extra tables</div><div class="value">$($extraTables.Count)</div><div class="sub">Target-only tables</div></div>
</div>

<h2>Breakdown by object type</h2>
<table>
<thead><tr><th>Object type</th><th class="num">Add</th><th class="num">Update</th><th class="num">Extra</th><th class="num">Total</th></tr></thead>
<tbody>
$($typeBreakdownRows -join "`n")
</tbody>
</table>

<div class="cols2">
  <div>
    <h2>Objects to add on target ($($added.Count))</h2>
    <ul class="compact">$addedList</ul>
  </div>
  <div>
    <h2>Objects to update on target ($($changed.Count))</h2>
    <ul class="compact">$changedList</ul>
  </div>
</div>
"@

    if ($total -eq 0) {
        $html += '<p class="ok">No differences found — schemas match across the compared object types.</p>'
    } else {
        if ($hasChangeDetails) {
            $html += @"
<h2>Detailed change breakdown (columns, indexes, constraints)</h2>
<table>
<thead><tr><th>Database</th><th>Object</th><th>Purpose</th><th>Mode</th><th>Change summary</th></tr></thead>
<tbody>
$($changeDetailRows -join "`n")
</tbody>
</table>
"@
        }
        $html += @"
<h2>Full difference detail</h2>
<table>
<thead><tr><th>Database</th><th>Object type</th><th>Object</th><th>Action</th><th>Status</th><th>Details</th></tr></thead>
<tbody>
$($detailRows -join "`n")
</tbody>
</table>
"@
    }

    $html += @"
<div class="footer">
  Generated by Compare-SqlSchema.ps1 &middot; Direction: Source &rarr; Target (target is updated to match source)
</div>
</body></html>
"@

    Set-Content -Path $Path -Value $html -Encoding UTF8
    return $Path
}

# ===========================================================================
#  Main
# ===========================================================================
Test-Prerequisite

if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'output' }
if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

if ($TargetDatabase -and $TargetDatabase.Count -ne $Database.Count) {
    throw "-TargetDatabase count ($($TargetDatabase.Count)) must match -Database count ($($Database.Count))."
}
if ($Apply -and -not $GenerateSyncScript) {
    throw "-Apply requires -GenerateSyncScript."
}

Write-Log "Connecting to Source [$SourceSqlInstance] and Target [$TargetSqlInstance] ..." 'Cyan'
$srcServer = Connect-Instance -Instance $SourceSqlInstance -Credential $SourceCredential `
    -Port $SourcePort -TimeoutSec $ConnectionTimeout -TrustServerCertificate:$TrustServerCertificate `
    -NetworkProtocol $NetworkProtocol -Role 'Source'
$tgtServer = Connect-Instance -Instance $TargetSqlInstance -Credential $TargetCredential `
    -Port $TargetPort -TimeoutSec $ConnectionTimeout -TrustServerCertificate:$TrustServerCertificate `
    -NetworkProtocol $NetworkProtocol -Role 'Target'
Write-Log "  Source: $($srcServer.Name) ($($srcServer.VersionString))" 'Gray'
Write-Log "  Target: $($tgtServer.Name) ($($tgtServer.VersionString))" 'Gray'

$stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir     = $null
if ($GenerateSyncScript) {
    $runDir = Join-Path $OutputPath "SchemaSync_$stamp"
    if (-not (Test-Path $runDir)) { New-Item -ItemType Directory -Path $runDir -Force | Out-Null }
}
$allResults   = [System.Collections.Generic.List[pscustomobject]]::new()
$summaries    = [System.Collections.Generic.List[pscustomobject]]::new()
$manifest     = [System.Collections.Generic.List[pscustomobject]]::new()
$databasePairs = [System.Collections.Generic.List[pscustomobject]]::new()

for ($i = 0; $i -lt $Database.Count; $i++) {
    $srcDbName = $Database[$i]
    $tgtDbName = if ($TargetDatabase) { $TargetDatabase[$i] } else { $srcDbName }
    $databasePairs.Add([pscustomobject]@{ Source = $srcDbName; Target = $tgtDbName })

    Write-Log "`n=== Comparing [$srcDbName] -> [$tgtDbName] ===" 'Cyan'
    $result = Compare-Database -SrcServer $srcServer -TgtServer $tgtServer -SrcDbName $srcDbName -TgtDbName $tgtDbName
    $allResults.Add($result)

    $dbManifest = @()
    if ($GenerateSyncScript -and $result.Changes.Count -gt 0) {
        $dbManifest = @(Write-ChangeScripts -Changes $result.Changes -SrcInstance $SourceSqlInstance -SrcDbName $srcDbName `
            -TgtInstance $TargetSqlInstance -TgtDbName $tgtDbName -OutDir $runDir)
        foreach ($m in $dbManifest) { $manifest.Add($m) }
        $autoN   = @($dbManifest | Where-Object { $_.Mode -eq 'Auto' }).Count
        $manualN = @($dbManifest | Where-Object { $_.Mode -eq 'Manual' }).Count
        Write-Log "  Wrote $($dbManifest.Count) script(s): $autoN auto_, $manualN manual_  -> $runDir" 'Green'
    } elseif ($GenerateSyncScript) {
        Write-Log "  No changes to script for [$tgtDbName]." 'Green'
    }

    # Apply the auto_ scripts, in ascending run-order, on the target.
    if ($Apply -and $GenerateSyncScript) {
        $autoFiles = @($dbManifest | Where-Object { $_.Mode -eq 'Auto' } | Sort-Object Order, FileName)
        if ($autoFiles.Count -gt 0 -and $PSCmdlet.ShouldProcess("$TargetSqlInstance/$tgtDbName", "Apply $($autoFiles.Count) auto_ script(s)")) {
            foreach ($f in $autoFiles) {
                Write-Log "  Applying [$($f.FileName)] ..." 'Magenta'
                Invoke-DbaQuery -SqlInstance $tgtServer -Database $tgtDbName -File $f.FilePath -EnableException | Out-Null
            }
            Write-Log "  Applied $($autoFiles.Count) auto_ script(s). Manual scripts (if any) still require review." 'Green'
        }
    }

    $summaries.Add([pscustomobject]@{
        Database        = $srcDbName
        TargetDatabase  = $tgtDbName
        DifferenceCount = $result.Differences.Count
        AutoScripts     = @($dbManifest | Where-Object { $_.Mode -eq 'Auto' }).Count
        ManualScripts   = @($dbManifest | Where-Object { $_.Mode -eq 'Manual' }).Count
        ScriptFolder    = $runDir
        Manifest        = $dbManifest
        Differences     = $result.Differences
    })
}

# Write enriched manifest + master migration catalog.
if ($GenerateSyncScript -and $manifest.Count -gt 0) {
    $enriched     = Enrich-ManifestEntries -Manifest $manifest
    $manifestPath = Join-Path $runDir '_manifest.csv'
    $enriched | Sort-Object Order, Mode, FileName |
        Select-Object Phase, Mode, Order, Database, Object, Purpose, ChangeCount, FileName, Blockers, Prerequisites, RequiresReview |
        Export-Csv -Path $manifestPath -NoTypeInformation -Encoding UTF8
    Write-Log "Manifest: $manifestPath" 'Green'

    $masterPaths = @()
    foreach ($db in ($enriched | Select-Object -ExpandProperty Database -Unique)) {
        $dbEntries = @($enriched | Where-Object { $_.Database -eq $db })
        $paths = Write-MasterMigrationCatalog -EnrichedManifest $dbEntries -TgtDbName $db -OutDir $runDir `
            -SrcInstance $SourceSqlInstance -TgtInstance $TargetSqlInstance
        $masterPaths += $paths
        Write-Log "  Master catalog [$db]: $($paths.Master)" 'Green'
        Write-Log "  Auto-only runner [$db]: $($paths.AutoOnly)" 'Gray'
    }
}

# --- Reporting ---
$reportPath = $null
if ($ReportFormat -contains 'Html') {
    $reportDir  = if ($runDir) { $runDir } else { $OutputPath }
    $reportPath = Join-Path $reportDir "SchemaCompare_$stamp.html"
    Export-HtmlReport -AllResults $allResults -SrcInstance $SourceSqlInstance -TgtInstance $TargetSqlInstance `
        -SrcServer $srcServer -TgtServer $tgtServer -DatabasePairs $databasePairs -Path $reportPath | Out-Null
    Write-Log "`nHTML report: $reportPath" 'Green'
}

$flatDiffs = foreach ($r in $allResults) { $r.Differences }

if ($ReportFormat -contains 'GridView' -and $flatDiffs) {
    $flatDiffs | Out-GridView -Title "Schema Differences: $SourceSqlInstance vs $TargetSqlInstance"
}

if ($ReportFormat -contains 'Console') {
    Write-Log "`n--- SCHEMA COMPARISON SUMMARY ---" 'Green' -Force
    if (-not $flatDiffs) {
        Write-Log "Schemas match across the compared object types." 'Green' -Force
    } else {
        $flatDiffs | Format-Table Database, ObjectType, ObjectName, Status, Details -AutoSize | Out-String -Width 4096 | Write-Host
    }
}

# Attach report path onto the returned summaries for pipeline callers.
foreach ($s in $summaries) { $s | Add-Member -NotePropertyName ReportPath -NotePropertyValue $reportPath -Force }
$summaries
