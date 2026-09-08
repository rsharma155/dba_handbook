<#
.SYNOPSIS
    Generates a point-in-time SQL Server DBA assessment report using dbatools.

.DESCRIPTION
    Connects with a SQL login (normally sa), collects operational, configuration,
    performance, HA/DR, security, maintenance, and capacity evidence, and writes a
    self-contained HTML report. The report leads with "What is broken now" and
    "What is at risk soon".

    Every run also writes a timestamped audit log (DBA_Assessment_<server>_<timestamp>.log)
    beside the report. It records start/finish, the connection result, and every
    collector/analysis/export error (with exception type and SQL error number/state
    when available). Credentials are never written to the log.

    SQL authentication cannot read the Windows event log remotely. Supply the
    optional WindowsCredential parameter to include critical System/Application
    events. SQL Server and SQL Agent service state is collected through
    sys.dm_server_services, so it works with SQL authentication.

.PARAMETER ServerIP
    SQL Server host/IP, optionally including instance or port.
.PARAMETER Credential
    SQL Server PSCredential, normally the sa login.
.PARAMETER WindowsCredential
    Optional Windows credential for remote Windows event log collection.
.PARAMETER OutputPath
    Output directory. Defaults to the output folder beside this script.
.PARAMETER DaysToAnalyze
    Historical lookback window in days.
.PARAMETER FullBackupSlaHours
    Maximum acceptable full-backup age.
.PARAMETER LogBackupSlaMinutes
    Maximum acceptable log-backup age for FULL/BULK_LOGGED databases.
.PARAMETER DeepIndexCheck
    Adds LIMITED physical-fragmentation scans for indexes with at least 1,000
    pages. Statistics freshness, index usage/status, and duplicate/unused index
    review remain enabled without this switch. Run deep checks in a low-activity
    period because physical stats scans can add load.
.PARAMETER ExportExcel
    Also exports the assessment to an .xlsx workbook beside the HTML report.
    Requires the ImportExcel module (Install-Module ImportExcel -Scope CurrentUser).
    The HTML report is always generated regardless of Excel export success.
.PARAMETER OpenReport
    Opens the generated report in the default browser.

.EXAMPLE
    $sqlCredential = Get-Credential -UserName sa
    .\Invoke-DbaAssessmentReport.ps1 -ServerIP 10.10.1.25 -Credential $sqlCredential

.EXAMPLE
    $sqlCredential = Get-Credential -UserName sa
    $windowsCredential = Get-Credential -Message 'Windows credential for event logs'
    .\Invoke-DbaAssessmentReport.ps1 -ServerIP '10.10.1.25,1433' `
        -Credential $sqlCredential -WindowsCredential $windowsCredential -OpenReport

.EXAMPLE
    $sqlCredential = Get-Credential -UserName sa
    .\Invoke-DbaAssessmentReport.ps1 -ServerIP 10.10.1.25 -Credential $sqlCredential -ExportExcel
    # Also writes DBA_Assessment_<server>_<timestamp>.xlsx (requires the ImportExcel module).
#>

#Requires -Version 5.1
#Requires -Modules dbatools

[CmdletBinding()]
param(
    [Parameter(Mandatory, HelpMessage = 'SQL Server IP, instance, or IP,port')]
    [Alias('ServerInstance', 'SqlInstance')]
    [ValidateNotNullOrEmpty()]
    [string]$ServerIP,

    [Parameter(Mandatory, HelpMessage = 'SQL Server login credential (normally sa)')]
    [Alias('SqlCredential')]
    [ValidateNotNull()]
    [PSCredential]$Credential,

    [Parameter()]
    [PSCredential]$WindowsCredential,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path $PSScriptRoot 'output'),

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$DaysToAnalyze = 30,

    [Parameter()]
    [ValidateRange(1, 720)]
    [int]$FullBackupSlaHours = 24,

    [Parameter()]
    [ValidateRange(1, 1440)]
    [int]$LogBackupSlaMinutes = 30,

    [Parameter()]
    [switch]$DeepIndexCheck,

    [Parameter()]
    [switch]$ExportExcel,

    [Parameter()]
    [switch]$OpenReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ============================================================================
# INITIALIZATION, HELPERS, AND CONNECTION
# =================================================================================

$ScriptVersion = '2.1'

Import-Module dbatools -ErrorAction Stop
$DbatoolsVersion = try { (Get-Module dbatools | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString() } catch { 'unknown' }

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$ReportTimestamp = Get-Date
$SafeServerName = $ServerIP -replace '[\\/:*?"<>|,]', '_'
$ReportBaseName = 'DBA_Assessment_{0}_{1}' -f $SafeServerName, $ReportTimestamp.ToString('yyyyMMdd_HHmmss')
$ReportFilePath = Join-Path $OutputPath ($ReportBaseName + '.html')
# The log shares the report base name so the .html/.xlsx/.log triplet correlates.
$LogFilePath = Join-Path $OutputPath ($ReportBaseName + '.log')

function Write-AssessmentLog {
    # Appends a structured audit line to the assessment log. Logging failures are
    # swallowed so an unwritable log never aborts the assessment.
    [CmdletBinding()]
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Severity = 'INFO',
        [string]$Section = '',
        [string]$Database = '',
        [string]$Message = '',
        [AllowNull()][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [switch]$EchoToHost,
        [System.ConsoleColor]$HostColor = [System.ConsoleColor]::Gray
    )

    try {
        $detail = $Message
        if ($null -ne $ErrorRecord) {
            $exception = $ErrorRecord.Exception
            $exceptionText = if ($null -ne $exception) { $exception.Message } else { [string]$ErrorRecord }
            $detail = if ([string]::IsNullOrWhiteSpace($Message)) { $exceptionText } else { "$Message :: $exceptionText" }

            $metadata = [System.Collections.Generic.List[string]]::new()
            if ($null -ne $exception) {
                $metadata.Add("ExceptionType=$($exception.GetType().FullName)")
                # Unwrap nested exceptions to surface SQL error number/state when present.
                $sqlException = $exception
                while ($null -ne $sqlException -and $sqlException.GetType().Name -ne 'SqlException') {
                    $sqlException = $sqlException.InnerException
                }
                if ($null -ne $sqlException) {
                    if ($sqlException.PSObject.Properties['Number']) { $metadata.Add("SqlErrorNumber=$($sqlException.Number)") }
                    if ($sqlException.PSObject.Properties['State']) { $metadata.Add("SqlState=$($sqlException.State)") }
                    if ($sqlException.PSObject.Properties['Class']) { $metadata.Add("SqlSeverity=$($sqlException.Class)") }
                }
            }
            if ($metadata.Count -gt 0) { $detail = "$detail [$($metadata -join '; ')]" }
        }

        # Keep each entry on a single line for easy grep/review.
        $detail = ($detail -replace '[\r\n]+', ' ').Trim()
        $line = '{0} | {1} | {2} | {3} | {4}' -f `
            (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), $Severity.PadRight(5), $Section, $Database, $detail
        Add-Content -LiteralPath $LogFilePath -Value $line -Encoding UTF8
    }
    catch {
        Write-Verbose ("Assessment log write skipped: {0}" -f $_.Exception.Message)
    }

    if ($EchoToHost) { Write-Host $Message -ForegroundColor $HostColor }
}

# Credential values are never logged; the parameter summary redacts them explicitly.
$ParameterSummary = (@(
        "OutputPath=$OutputPath",
        "DaysToAnalyze=$DaysToAnalyze",
        "FullBackupSlaHours=$FullBackupSlaHours",
        "LogBackupSlaMinutes=$LogBackupSlaMinutes",
        "DeepIndexCheck=$([bool]$DeepIndexCheck)",
        "ExportExcel=$([bool]$ExportExcel)",
        "OpenReport=$([bool]$OpenReport)",
        "WindowsCredential=$(if ($WindowsCredential) { 'provided' } else { 'not provided' })",
        'Credential=[redacted]'
    ) -join ', ')

try {
    $logHeader = @(
        '============================================================',
        ' SQL Server DBA Assessment - execution log',
        '============================================================',
        ('Script version : {0}' -f $ScriptVersion),
        ('Target server  : {0}' -f $ServerIP),
        ('Start time     : {0}' -f $ReportTimestamp.ToString('yyyy-MM-dd HH:mm:ss')),
        ('PowerShell     : {0}' -f $PSVersionTable.PSVersion.ToString()),
        ('dbatools       : {0}' -f $DbatoolsVersion),
        ('Parameters     : {0}' -f $ParameterSummary),
        ('Report file    : {0}' -f $ReportFilePath),
        'Entry format   : TIMESTAMP | SEVERITY | SECTION | DATABASE | MESSAGE',
        '------------------------------------------------------------'
    )
    Set-Content -LiteralPath $LogFilePath -Value $logHeader -Encoding UTF8
}
catch {
    Write-Warning ("Could not initialize log file '{0}': {1}" -f $LogFilePath, $_.Exception.Message)
}
Write-AssessmentLog -Severity INFO -Section 'Startup' -Message 'Assessment run started.'

$CriticalIssues = [System.Collections.Generic.List[object]]::new()
$WarningIssues = [System.Collections.Generic.List[object]]::new()
$InformationItems = [System.Collections.Generic.List[object]]::new()
$CollectionErrors = [System.Collections.Generic.List[object]]::new()
$Sections = [ordered]@{}

$AssessmentSqlFiles = [ordered]@{
    InventoryQuery               = '01_inventory_configuration/server_instance_inventory.sql'
    ServiceQuery                 = '01_inventory_configuration/sql_services.sql'
    DatabaseQuery                = '01_inventory_configuration/database_inventory.sql'
    BackupQuery                  = '02_backup_jobs_maintenance/backup_status.sql'
    JobQuery                     = '02_backup_jobs_maintenance/sql_agent_jobs.sql'
    RecentFailuresQuery          = '02_backup_jobs_maintenance/recent_job_failures.sql'
    BackupVolumeQuery            = '02_backup_jobs_maintenance/backup_destinations.sql'
    MaintenanceQuery             = '02_backup_jobs_maintenance/maintenance_jobs.sql'
    AlertQuery                   = '02_backup_jobs_maintenance/alerts_notifications.sql'
    DiskQuery                    = '03_storage_integrity/sql_file_volumes.sql'
    IntegrityQuery               = '03_storage_integrity/database_integrity_history.sql'
    BlockingQuery                = '04_performance_waits_queries/current_blocking.sql'
    LongQuery                    = '04_performance_waits_queries/active_long_running_queries.sql'
    WaitQuery                    = '04_performance_waits_queries/wait_statistics.sql'
    PerformanceQuery             = '04_performance_waits_queries/cpu_memory_pressure.sql'
    IoQuery                      = '04_performance_waits_queries/file_io_latency.sql'
    TopQuery                     = '04_performance_waits_queries/top_resource_consumers.sql'
    ProcedurePerformanceQuery    = '04_performance_waits_queries/stored_procedure_performance.sql'
    TempDbQuery                  = '05_tempdb_growth/tempdb_health.sql'
    FileGrowthQuery              = '05_tempdb_growth/database_file_growth.sql'
    GrowthEventsQuery            = '05_tempdb_growth/recent_autogrowth_events.sql'
    HaQuery                      = '06_ha_dr_replication/availability_group_status.sql'
    ReplicationQuery             = '06_ha_dr_replication/replication_status.sql'
    MirroringQuery               = '06_ha_dr_replication/database_mirroring_status.sql'
    SecurityQuery                = '07_security_permissions/server_security.sql'
    ServerPermissionsQuery       = '07_security_permissions/server_permissions.sql'
    StatisticsHealthQuery        = '08_statistics_indexes/table_statistics_health.sql'
    IndexStatusQuery             = '08_statistics_indexes/index_status_usage.sql'
    DuplicateIndexQuery          = '08_statistics_indexes/duplicate_overlapping_indexes.sql'
    MissingIndexQuery            = '08_statistics_indexes/missing_index_indicators.sql'
    MemorySnapshotQuery          = '09_memory/memory_pressure_snapshot.sql'
    MemoryClerksQuery            = '09_memory/memory_clerks.sql'
    MemoryGrantsQuery            = '09_memory/active_memory_grants.sql'
    BufferCacheQuery             = '09_memory/buffer_cache_by_database.sql'
    ResourceSemaphoreQuery       = '09_memory/resource_semaphore_waits.sql'
    MemoryQueryConsumersQuery    = '09_memory/top_cached_query_memory_grants.sql'
    ConfigQuery                  = '10_capacity_changes/instance_configuration.sql'
    ConfigurationChangesQuery    = '10_capacity_changes/recent_configuration_changes.sql'
    GrowthTrendQuery             = '10_capacity_changes/capacity_growth_trends.sql'
    OrphanedUsersQuery           = '07_security_permissions/orphaned_database_users.sql'
    FragmentationQuery           = '08_statistics_indexes/index_fragmentation_limited.sql'
}

function Get-AssessmentSql {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [hashtable]$Tokens = @{}
    )

    if (-not $AssessmentSqlFiles.Contains($Name)) {
        throw "Unknown assessment SQL dependency '$Name'."
    }
    $sqlPath = Join-Path (Join-Path $PSScriptRoot 'sql_scripts') $AssessmentSqlFiles[$Name]
    if (-not (Test-Path -LiteralPath $sqlPath -PathType Leaf)) {
        throw "Required assessment SQL file is missing: '$sqlPath'. Keep Invoke-DbaAssessmentReport.ps1 and sql_scripts together."
    }
    $sql = Get-Content -Raw -LiteralPath $sqlPath
    if ([string]::IsNullOrWhiteSpace($sql)) {
        throw "Required assessment SQL file is empty: '$sqlPath'."
    }
    foreach ($tokenName in $Tokens.Keys) {
        $tokenValue = $Tokens[$tokenName]
        if ($tokenValue -isnot [byte] -and $tokenValue -isnot [int16] -and
            $tokenValue -isnot [int32] -and $tokenValue -isnot [int64]) {
            throw "SQL token '$tokenName' must be a validated integer."
        }
        $sql = $sql.Replace('{{' + $tokenName + '}}', [string]$tokenValue)
    }
    if ($sql -match '\{\{[A-Za-z0-9_]+\}\}') {
        throw "Unresolved token in assessment SQL '$Name'."
    }
    return $sql
}

foreach ($sqlDependency in $AssessmentSqlFiles.Keys) {
    $dependencyTokens = @{}
    if ($sqlDependency -in @('RecentFailuresQuery','GrowthEventsQuery','ConfigurationChangesQuery','GrowthTrendQuery')) {
        $dependencyTokens = @{ DaysToAnalyze = $DaysToAnalyze }
    }
    [void](Get-AssessmentSql -Name $sqlDependency -Tokens $dependencyTokens)
}

function Add-Finding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Critical', 'Warning', 'Info')][string]$Severity,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory)][string]$Detail,
        [string]$Recommendation = ''
    )

    $finding = [PSCustomObject]@{
        Severity       = $Severity
        Category       = $Category
        Item           = $Item
        Detail         = $Detail
        Recommendation = $Recommendation
    }
    switch ($Severity) {
        'Critical' { $CriticalIssues.Add($finding) }
        'Warning'  { $WarningIssues.Add($finding) }
        'Info'     { $InformationItems.Add($finding) }
    }
}

function Test-HasValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [System.DBNull]) { return $false }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $true
}

function Test-HasNumericValue {
    param([AllowNull()][object]$Value)

    if (-not (Test-HasValue $Value)) { return $false }
    $parsed = 0.0
    return [double]::TryParse([string]$Value, [ref]$parsed)
}

function Compare-Numeric {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][ValidateSet('gt', 'lt', 'ge', 'le', 'eq')][string]$Operator,
        [Parameter(Mandatory)][double]$Threshold,
        [switch]$TreatNullAsFailure
    )

    if (-not (Test-HasNumericValue $Value)) {
        return [bool]$TreatNullAsFailure
    }

    $number = [double]$Value
    switch ($Operator) {
        'gt' { return $number -gt $Threshold }
        'lt' { return $number -lt $Threshold }
        'ge' { return $number -ge $Threshold }
        'le' { return $number -le $Threshold }
        'eq' { return $number -eq $Threshold }
    }

    return $false
}

function Invoke-AssessmentQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Query,
        [string]$Database = 'master'
    )

    Write-Host ("Collecting {0}..." -f $Name) -NoNewline
    try {
        # -As PSObject returns clean PSCustomObjects (query columns only) instead of
        # DataRow objects whose internals (RowError, RowState, Table, ItemArray,
        # HasErrors) would otherwise leak into the HTML tables.
        $result = @(Invoke-DbaQuery -SqlInstance $SqlServer `
            -Database $Database -Query $Query -QueryTimeout 120 -As PSObject -EnableException)
        $Sections[$Name] = $result
        Write-Host 'DONE' -ForegroundColor Green
        return $result
    }
    catch {
        $message = $_.Exception.Message
        $Sections[$Name] = @()
        $CollectionErrors.Add([PSCustomObject]@{ Section = $Name; Error = $message })
        Write-AssessmentLog -Severity ERROR -Section $Name -Message 'Collector query failed.' -ErrorRecord $_
        Write-Host 'FAILED' -ForegroundColor Yellow
        return @()
    }
}

function Invoke-PerDatabaseAssessmentQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DatabaseNames,
        [int]$QueryTimeout = 120
    )

    Write-Host ("Collecting {0}..." -f $Name) -NoNewline
    $collected = [System.Collections.Generic.List[object]]::new()
    foreach ($databaseName in $DatabaseNames) {
        try {
            $rows = @(Invoke-DbaQuery -SqlInstance $SqlServer -Database $databaseName `
                -Query $Query -QueryTimeout $QueryTimeout -As PSObject -EnableException)
            foreach ($row in $rows) { $collected.Add($row) }
        }
        catch {
            # A single inaccessible or problematic database must not suppress results
            # from the rest of the instance.
            $CollectionErrors.Add([PSCustomObject]@{
                Section = "$Name - $databaseName"
                Error   = $_.Exception.Message
            })
            Write-AssessmentLog -Severity ERROR -Section $Name -Database $databaseName `
                -Message 'Per-database collector failed.' -ErrorRecord $_
        }
    }

    $result = @($collected)
    $Sections[$Name] = $result
    Write-Host 'DONE' -ForegroundColor Green
    return $result
}

function Invoke-AssessmentAnalysis {
    # Runs a findings-analysis block so that an unexpected error (for example a
    # DBNull value in an unanticipated column) is recorded as a collection error
    # instead of terminating the whole assessment ($ErrorActionPreference = 'Stop').
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )

    try {
        . $ScriptBlock
    }
    catch {
        $CollectionErrors.Add([PSCustomObject]@{ Section = $Name; Error = $_.Exception.Message })
        Write-AssessmentLog -Severity ERROR -Section $Name -Message 'Findings analysis failed.' -ErrorRecord $_
        Write-Host ("Analysis '{0}' failed: {1}" -f $Name, $_.Exception.Message) -ForegroundColor Yellow
    }
}

function ConvertTo-HtmlEncoded {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or $Value -is [System.DBNull]) { return 'N/A' }
    if ($Value -is [datetime]) { $Value = $Value.ToString('yyyy-MM-dd HH:mm:ss') }
    elseif ($Value -is [timespan]) { $Value = '{0}d {1}h {2}m' -f $Value.Days, $Value.Hours, $Value.Minutes }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-HtmlTable {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Data,
        [string[]]$Properties,
        [string]$TableId = ''
    )

    $rows = @(@($Data) | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) { return "<p class='no-data'>No data available.</p>" }
    if (-not $Properties) {
        if ($rows[0] -is [System.Data.DataRow]) {
            # Use the query's column names; PSObject.Properties on a DataRow also
            # returns DataRow internals (RowError, RowState, Table, ItemArray, HasErrors).
            $Properties = @($rows[0].Table.Columns | ForEach-Object { $_.ColumnName })
        }
        else {
            $Properties = @($rows[0].PSObject.Properties | ForEach-Object { $_.Name })
        }
    }
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append("<div class='table-wrap'><table id='$(ConvertTo-HtmlEncoded $TableId)' class='data-table'><thead><tr>")
    foreach ($property in $Properties) {
        [void]$builder.Append("<th>$(ConvertTo-HtmlEncoded ($property -replace '_', ' '))</th>")
    }
    [void]$builder.Append('</tr></thead><tbody>')
    foreach ($row in $rows) {
        [void]$builder.Append('<tr>')
        foreach ($property in $Properties) {
            $cellValue = $row.$property
            if ($property -eq 'LastGoodCheckDb' -and $cellValue -is [datetime] -and $cellValue.Year -le 1900) {
                $cellValue = 'Never'
            }
            $cellClass = ''
            if ($property -eq 'Assessment') {
                # Color-code latency verdict cells (green/amber/red).
                $cellClass = switch -Wildcard ([string]$cellValue) {
                    'Good*'     { " class='cell-good'" }
                    'Marginal*' { " class='cell-warn'" }
                    'Poor*'     { " class='cell-bad'" }
                    default     { '' }
                }
            }
            [void]$builder.Append("<td$cellClass>$(ConvertTo-HtmlEncoded $cellValue)</td>")
        }
        [void]$builder.Append('</tr>')
    }
    [void]$builder.Append('</tbody></table></div>')
    return $builder.ToString()
}

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' SQL Server DBA Assessment' -ForegroundColor Cyan
Write-Host " Target: $ServerIP" -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

Write-Host "Connecting to $ServerIP..." -NoNewline
try {
    # TrustServerCertificate: dbatools 2.x defaults to encrypted connections, which fail
    # against instances using self-signed certificates (the common case for internal
    # assessments driven by IP + sa credential).
    # -ErrorAction Stop instead of -EnableException: Connect-DbaInstance in dbatools 2.8.x
    # no longer exposes -EnableException, and -ErrorAction Stop makes failures terminating
    # so the catch block below still fires.
    $SqlServer = Connect-DbaInstance -SqlInstance $ServerIP -SqlCredential $Credential `
        -TrustServerCertificate -ErrorAction Stop
    Write-Host 'SUCCESS' -ForegroundColor Green
    Write-AssessmentLog -Severity INFO -Section 'Connection' -Message ("Connected to '{0}'." -f $ServerIP)
}
catch {
    Write-AssessmentLog -Severity ERROR -Section 'Connection' `
        -Message ("Connection to '{0}' failed." -f $ServerIP) -ErrorRecord $_
    throw "Cannot connect to '$ServerIP'. Verify TCP/IP, port/instance, firewall, and SQL credentials. $($_.Exception.Message)"
}

#endregion

#region ============================================================================
# DATA COLLECTION
# =================================================================================

$InventoryQuery = Get-AssessmentSql -Name 'InventoryQuery'
$Inventory = @(Invoke-AssessmentQuery -Name 'Server and Instance Inventory' -Query $InventoryQuery)

$ServiceQuery = Get-AssessmentSql -Name 'ServiceQuery'
$Services = @(Invoke-AssessmentQuery -Name 'SQL Services' -Query $ServiceQuery)
Invoke-AssessmentAnalysis -Name 'SQL Services analysis' -ScriptBlock {
    foreach ($service in $Services) {
        if ($service.Status -ne 'Running') {
            Add-Finding -Severity Critical -Category 'Service' -Item $service.ServiceName `
                -Detail "Service status is $($service.Status)." -Recommendation 'Start the service and investigate the cause.'
        }
        if ($service.ServiceName -match 'SQL Server Agent' -and $service.StartupType -notmatch 'Automatic') {
            Add-Finding -Severity Warning -Category 'Service' -Item $service.ServiceName `
                -Detail "Startup type is $($service.StartupType)." -Recommendation 'Use Automatic startup where Agent jobs are required.'
        }
    }
}

$DatabaseQuery = Get-AssessmentSql -Name 'DatabaseQuery'
$Databases = @(Invoke-AssessmentQuery -Name 'Database Inventory and Configuration' -Query $DatabaseQuery)
$UserDatabaseNames = @($Databases | Where-Object {
        $_.Status -eq 'ONLINE' -and
        $_.DatabaseName -notin @('master','model','msdb','tempdb') -and
        -not (Test-HasValue $_.SourceDatabaseId) -and
        ([int]$_.HasDbAccess -eq 1)
    } | Select-Object -ExpandProperty DatabaseName)
Invoke-AssessmentAnalysis -Name 'Database configuration analysis' -ScriptBlock {
    foreach ($database in $Databases) {
        if ($database.Status -ne 'ONLINE') {
            Add-Finding -Severity Critical -Category 'Database' -Item $database.DatabaseName `
                -Detail "Database state is $($database.Status)." -Recommendation 'Confirm whether this state is planned; recover or restore if not.'
        }
        if ($database.AutoClose -eq $true -or $database.AutoShrink -eq $true) {
            Add-Finding -Severity Warning -Category 'Database Configuration' -Item $database.DatabaseName `
                -Detail "AUTO_CLOSE=$($database.AutoClose), AUTO_SHRINK=$($database.AutoShrink)." `
                -Recommendation 'Disable AUTO_CLOSE and AUTO_SHRINK for production databases.'
        }
        if ($database.PageVerify -ne 'CHECKSUM') {
            Add-Finding -Severity Warning -Category 'Database Configuration' -Item $database.DatabaseName `
                -Detail "PAGE_VERIFY is $($database.PageVerify)." -Recommendation 'Set PAGE_VERIFY CHECKSUM after validating application requirements.'
        }
    }
}

$BackupQuery = Get-AssessmentSql -Name 'BackupQuery'
$Backups = @(Invoke-AssessmentQuery -Name 'Backup Status' -Query $BackupQuery -Database 'msdb')
Invoke-AssessmentAnalysis -Name 'Backup status analysis' -ScriptBlock {
    foreach ($backup in $Backups) {
        $fullBackupMissing = -not (Test-HasValue $backup.LastFullBackup)
        $fullBackupOverdue = Compare-Numeric -Value $backup.FullAgeHours -Operator gt -Threshold $FullBackupSlaHours
        if ($fullBackupMissing -or $fullBackupOverdue) {
            $fullAgeLabel = if (Test-HasNumericValue $backup.FullAgeHours) { $backup.FullAgeHours } else { 'N/A' }
            Add-Finding -Severity Critical -Category 'Backup' -Item $backup.DatabaseName `
                -Detail "Full backup is missing or older than $FullBackupSlaHours hours (age: $fullAgeLabel)." `
                -Recommendation 'Run and verify a full backup immediately.'
        }

        $logBackupMissing = -not (Test-HasValue $backup.LastLogBackup)
        $logBackupOverdue = Compare-Numeric -Value $backup.LogAgeMinutes -Operator gt -Threshold $LogBackupSlaMinutes
        if ($backup.RecoveryModel -ne 'SIMPLE' -and ($logBackupMissing -or $logBackupOverdue)) {
            $logAgeLabel = if (Test-HasNumericValue $backup.LogAgeMinutes) { $backup.LogAgeMinutes } else { 'N/A' }
            Add-Finding -Severity Critical -Category 'Backup' -Item $backup.DatabaseName `
                -Detail "Log backup is missing or older than $LogBackupSlaMinutes minutes (age: $logAgeLabel)." `
                -Recommendation 'Restore the log-backup chain and verify the log backup job.'
        }
    }
}

$JobQuery = Get-AssessmentSql -Name 'JobQuery'
$Jobs = @(Invoke-AssessmentQuery -Name 'SQL Agent Jobs' -Query $JobQuery -Database 'msdb')
Invoke-AssessmentAnalysis -Name 'SQL Agent job analysis' -ScriptBlock {
    foreach ($job in $Jobs) {
        if ($job.Enabled -and $job.LastRunStatus -in @('Failed','Canceled')) {
            Add-Finding -Severity Critical -Category 'SQL Agent Job' -Item $job.JobName `
                -Detail "Last run status: $($job.LastRunStatus). $($job.LastMessage)" -Recommendation 'Review job history and rerun after correcting the failure.'
        }
    }
    $jobsWithoutNotification = @($Jobs | Where-Object { $_.Enabled -and $_.EmailNotification -eq 'No' })
    if ($jobsWithoutNotification.Count -gt 0) {
        Add-Finding -Severity Warning -Category 'Alerting' -Item 'Job failure notifications' `
            -Detail "$($jobsWithoutNotification.Count) enabled SQL Agent job(s) have no email notification configured." `
            -Recommendation 'Configure notification on failure to an active operator.'
    }
}

$RecentFailuresQuery = Get-AssessmentSql -Name 'RecentFailuresQuery' -Tokens @{ DaysToAnalyze = $DaysToAnalyze }
$RecentJobFailures = @(Invoke-AssessmentQuery -Name 'Recent Job Failures' -Query $RecentFailuresQuery -Database 'msdb')

$DiskQuery = Get-AssessmentSql -Name 'DiskQuery'
$Disks = @(Invoke-AssessmentQuery -Name 'SQL Data Log and TempDB Volumes' -Query $DiskQuery)
Invoke-AssessmentAnalysis -Name 'Disk space analysis' -ScriptBlock {
    foreach ($disk in $Disks) {
        $diskCritical = (Compare-Numeric -Value $disk.FreePercent -Operator lt -Threshold 5) -or
            (Compare-Numeric -Value $disk.FreeGB -Operator lt -Threshold 5)
        $diskWarning = (Compare-Numeric -Value $disk.FreePercent -Operator lt -Threshold 15) -or
            (Compare-Numeric -Value $disk.FreeGB -Operator lt -Threshold 20)

        if ($diskCritical) {
            Add-Finding -Severity Critical -Category 'Disk Space' -Item $disk.Volume `
                -Detail "$($disk.FreeGB) GB ($($disk.FreePercent)%) free; contains $($disk.SqlFileTypes)." -Recommendation 'Free or add capacity before SQL files cannot grow.'
        }
        elseif ($diskWarning) {
            Add-Finding -Severity Warning -Category 'Disk Space' -Item $disk.Volume `
                -Detail "$($disk.FreeGB) GB ($($disk.FreePercent)%) free; contains $($disk.SqlFileTypes)." -Recommendation 'Review growth and provision capacity.'
        }
    }
}

$BackupVolumeQuery = Get-AssessmentSql -Name 'BackupVolumeQuery'
$BackupVolumes = @(Invoke-AssessmentQuery -Name 'Backup Destinations and Free Space' -Query $BackupVolumeQuery -Database 'msdb')
Invoke-AssessmentAnalysis -Name 'Backup volume analysis' -ScriptBlock {
    foreach ($volume in ($BackupVolumes | Where-Object { Compare-Numeric -Value $_.FreeGB -Operator lt -Threshold 20 })) {
        Add-Finding -Severity Warning -Category 'Backup Disk Space' -Item $volume.BackupDestination `
            -Detail "Backup drive $($volume.Drive): has $($volume.FreeGB) GB free." `
            -Recommendation 'Validate backup retention and provision backup capacity.'
    }
}

$IntegrityQuery = Get-AssessmentSql -Name 'IntegrityQuery'
$Integrity = @(Invoke-AssessmentQuery -Name 'Database Integrity History' -Query $IntegrityQuery)
Invoke-AssessmentAnalysis -Name 'Integrity check analysis' -ScriptBlock {
    foreach ($check in $Integrity) {
        # Defensive: also treat the 1900-01-01 sentinel as "never ran" if it slips
        # through as a datetime value.
        $lastGoodCheck = $check.LastGoodCheckDb
        $neverChecked = (-not (Test-HasValue $lastGoodCheck)) -or
            (($lastGoodCheck -is [datetime]) -and $lastGoodCheck.Year -le 1900)
        if ($neverChecked) {
            Add-Finding -Severity Critical -Category 'Integrity' -Item $check.DatabaseName `
                -Detail 'No successful DBCC CHECKDB timestamp is available.' -Recommendation 'Run DBCC CHECKDB and review all output.'
        }
        elseif (Compare-Numeric -Value $check.DaysSinceCheck -Operator gt -Threshold 7) {
            Add-Finding -Severity Warning -Category 'Integrity' -Item $check.DatabaseName `
                -Detail "Last successful CHECKDB was $($check.DaysSinceCheck) days ago." -Recommendation 'Schedule CHECKDB at least weekly, or per approved policy.'
        }
    }
}

Write-Host 'Collecting SQL error log issues...' -NoNewline
try {
    $ErrorLog = @(Get-DbaErrorLog -SqlInstance $SqlServer `
        -After (Get-Date).AddDays(-$DaysToAnalyze) -EnableException |
        Where-Object { $_.Text -match '(?i)error: 82[345]|severity:\s*(2[0-5])|corrupt|stack dump|failed|I/O requests taking longer|non-yielding|deadlock|backup.*(fail|error)' } |
        Select-Object -First 200 LogDate, Source, Text)
    $Sections['SQL Error Log Issues'] = $ErrorLog
    foreach ($entry in ($ErrorLog | Where-Object { $_.Text -match '(?i)error: 82[345]|severity:\s*(2[0-5])|corrupt|stack dump|non-yielding' } | Select-Object -First 20)) {
        Add-Finding -Severity Critical -Category 'SQL Error Log' -Item $entry.Source `
            -Detail ([string]$entry.Text) -Recommendation 'Investigate immediately and correlate with storage and Windows events.'
    }
    Write-Host 'DONE' -ForegroundColor Green
}
catch {
    $ErrorLog = @()
    $Sections['SQL Error Log Issues'] = @()
    $CollectionErrors.Add([PSCustomObject]@{ Section='SQL Error Log Issues'; Error=$_.Exception.Message })
    Write-AssessmentLog -Severity ERROR -Section 'SQL Error Log Issues' -Message 'Error-log collection failed.' -ErrorRecord $_
    Write-Host 'FAILED' -ForegroundColor Yellow
}

Write-Host 'Collecting Windows event log issues...' -NoNewline
if ($WindowsCredential) {
    try {
        $computer = ($ServerIP -split '[\\,]')[0]
        $WindowsEvents = @(Get-WinEvent -ComputerName $computer -Credential $WindowsCredential -FilterHashtable @{
                LogName=@('System','Application'); Level=@(1,2); StartTime=(Get-Date).AddDays(-$DaysToAnalyze)
            } -ErrorAction Stop | Select-Object -First 200 TimeCreated, LogName, ProviderName, Id, LevelDisplayName, Message)
        $Sections['Windows Critical Events'] = $WindowsEvents
        Write-Host 'DONE' -ForegroundColor Green
    }
    catch {
        $WindowsEvents = @()
        $Sections['Windows Critical Events'] = @()
        $CollectionErrors.Add([PSCustomObject]@{ Section='Windows Critical Events'; Error=$_.Exception.Message })
        Write-AssessmentLog -Severity ERROR -Section 'Windows Critical Events' -Message 'Windows event-log collection failed.' -ErrorRecord $_
        Write-Host 'FAILED' -ForegroundColor Yellow
    }
}
else {
    $WindowsEvents = @()
    $Sections['Windows Critical Events'] = @()
    Add-Finding -Severity Info -Category 'Collection Scope' -Item 'Windows event logs' `
        -Detail 'Not collected because SQL (sa) credentials cannot read Windows event logs.' `
        -Recommendation 'Supply -WindowsCredential to include remote System and Application critical events.'
    Write-AssessmentLog -Severity INFO -Section 'Windows Critical Events' -Message 'Skipped: no -WindowsCredential supplied.'
    Write-Host 'SKIPPED' -ForegroundColor DarkYellow
}

$BlockingQuery = Get-AssessmentSql -Name 'BlockingQuery'
$Blocking = @(Invoke-AssessmentQuery -Name 'Current Blocking' -Query $BlockingQuery)
Invoke-AssessmentAnalysis -Name 'Blocking analysis' -ScriptBlock {
    foreach ($block in $Blocking) {
        Add-Finding -Severity Critical -Category 'Blocking' -Item "Session $($block.BlockingSessionId) blocking $($block.BlockedSessionId)" `
            -Detail "$($block.DatabaseName), wait $($block.WaitSeconds)s on $($block.WaitType)." `
            -Recommendation 'Identify the head blocker; tune or safely end it after impact review.'
    }
}

$LongQuery = Get-AssessmentSql -Name 'LongQuery'
$LongRunning = @(Invoke-AssessmentQuery -Name 'Active and Long Running Queries' -Query $LongQuery)

$WaitQuery = Get-AssessmentSql -Name 'WaitQuery'
$Waits = @(Invoke-AssessmentQuery -Name 'Wait Statistics' -Query $WaitQuery)
Invoke-AssessmentAnalysis -Name 'Wait statistics analysis' -ScriptBlock {
    foreach ($wait in ($Waits | Where-Object { (Compare-Numeric -Value $_.WaitPercent -Operator ge -Threshold 15) -and $_.Category -ne 'Other' })) {
        Add-Finding -Severity Warning -Category 'Wait Statistics' -Item $wait.WaitType `
            -Detail "$($wait.WaitPercent)% of non-idle waits; category $($wait.Category)." `
            -Recommendation 'Correlate with current workload and baseline before tuning.'
    }
}

$PerformanceQuery = Get-AssessmentSql -Name 'PerformanceQuery'
$Performance = @(Invoke-AssessmentQuery -Name 'CPU and Memory Pressure' -Query $PerformanceQuery)
Invoke-AssessmentAnalysis -Name 'CPU and memory analysis' -ScriptBlock {
    if ($Performance.Count -gt 0) {
        $perf = $Performance[0]
        if (Compare-Numeric -Value $perf.SqlCpuPercent -Operator ge -Threshold 80) {
            Add-Finding -Severity Critical -Category 'Performance' -Item 'SQL CPU' -Detail "Recent SQL CPU is $($perf.SqlCpuPercent)%." -Recommendation 'Inspect top CPU queries and runnable task pressure.'
        }
        elseif (Compare-Numeric -Value $perf.SqlCpuPercent -Operator ge -Threshold 60) {
            Add-Finding -Severity Warning -Category 'Performance' -Item 'SQL CPU' -Detail "Recent SQL CPU is $($perf.SqlCpuPercent)%." -Recommendation 'Compare with baseline and inspect top CPU queries.'
        }
        $physicalMemoryLow = (Test-HasValue $perf.ProcessPhysicalMemoryLow) -and [bool]$perf.ProcessPhysicalMemoryLow
        if ((Compare-Numeric -Value $perf.MemoryGrantsPending -Operator gt -Threshold 0) -or $physicalMemoryLow) {
            Add-Finding -Severity Critical -Category 'Performance' -Item 'Memory Pressure' `
                -Detail "Memory grants pending=$($perf.MemoryGrantsPending), physical memory low=$($perf.ProcessPhysicalMemoryLow)." `
                -Recommendation 'Review max memory, query grants, and host memory pressure.'
        }
    }
}

$IoQuery = Get-AssessmentSql -Name 'IoQuery'
$Io = @(Invoke-AssessmentQuery -Name 'File IO Latency' -Query $IoQuery)
Invoke-AssessmentAnalysis -Name 'File IO latency analysis' -ScriptBlock {
    # Warning threshold (>100 ms) matches the 'Poor' verdict in the Assessment column.
    foreach ($file in ($Io | Where-Object {
            (Compare-Numeric -Value $_.AvgReadLatencyMs -Operator gt -Threshold 100) -or
            (Compare-Numeric -Value $_.AvgWriteLatencyMs -Operator gt -Threshold 100)
        } | Select-Object -First 10)) {
        Add-Finding -Severity Warning -Category 'I/O Performance' -Item $file.PhysicalName `
            -Detail "Average read=$($file.AvgReadLatencyMs)ms, write=$($file.AvgWriteLatencyMs)ms (>100 ms is poor; <=20 ms is good)." `
            -Recommendation 'Correlate with storage metrics, queue depth, and workload.'
    }
}

$TopQuery = Get-AssessmentSql -Name 'TopQuery'
$TopQueries = @(Invoke-AssessmentQuery -Name 'Top Resource Consumers' -Query $TopQuery)

$TempDbQuery = Get-AssessmentSql -Name 'TempDbQuery'
$TempDb = @(Invoke-AssessmentQuery -Name 'TempDB Health' -Query $TempDbQuery -Database 'tempdb')
Invoke-AssessmentAnalysis -Name 'TempDB analysis' -ScriptBlock {
    $tempDataFiles = @($TempDb | Where-Object { $_.FileType -eq 'ROWS' })
    $logicalCpuCount = if ($Inventory.Count -gt 0 -and (Test-HasNumericValue $Inventory[0].LogicalCpuCount)) {
        [int]$Inventory[0].LogicalCpuCount
    } else { 0 }
    if ($tempDataFiles.Count -lt 2 -and $logicalCpuCount -gt 1) {
        Add-Finding -Severity Warning -Category 'TempDB' -Item 'Data file count' `
            -Detail "TempDB has $($tempDataFiles.Count) data file(s) for $logicalCpuCount logical CPUs." `
            -Recommendation 'Start with up to 4 or 8 equally sized data files; validate contention before adding more.'
    }
    if (@($tempDataFiles | Select-Object -ExpandProperty SizeMB -Unique).Count -gt 1) {
        Add-Finding -Severity Warning -Category 'TempDB' -Item 'Unequal data files' `
            -Detail 'TempDB data files are not equally sized.' -Recommendation 'Pre-size data files equally with equal fixed growth.'
    }
}

$FileGrowthQuery = Get-AssessmentSql -Name 'FileGrowthQuery'
$Files = @(Invoke-AssessmentQuery -Name 'Database File Growth Settings' -Query $FileGrowthQuery)
Invoke-AssessmentAnalysis -Name 'File growth settings analysis' -ScriptBlock {
    foreach ($file in $Files) {
        if ((Test-HasValue $file.IsPercentGrowth) -and [bool]$file.IsPercentGrowth) {
            Add-Finding -Severity Warning -Category 'Auto-growth' -Item "$($file.DatabaseName).$($file.LogicalName)" `
                -Detail "Percentage growth configured: $($file.GrowthSetting)." -Recommendation 'Use a tested fixed-MB growth increment.'
        }
    }
}

$GrowthEventsQuery = Get-AssessmentSql -Name 'GrowthEventsQuery' -Tokens @{ DaysToAnalyze = $DaysToAnalyze }
$GrowthEvents = @(Invoke-AssessmentQuery -Name 'Recent Auto-growth Events' -Query $GrowthEventsQuery)
Invoke-AssessmentAnalysis -Name 'Auto-growth events analysis' -ScriptBlock {
    if ($GrowthEvents.Count -ge 10) {
        Add-Finding -Severity Warning -Category 'Auto-growth' -Item 'Frequent growth events' `
            -Detail "$($GrowthEvents.Count) growth events found in the last $DaysToAnalyze days (result capped at 200)." `
            -Recommendation 'Pre-size files and investigate unexpected data/log growth.'
    }
}

$ConfigQuery = Get-AssessmentSql -Name 'ConfigQuery'
$Configurations = @(Invoke-AssessmentQuery -Name 'Instance Configuration' -Query $ConfigQuery)
Invoke-AssessmentAnalysis -Name 'Instance configuration analysis' -ScriptBlock {
    foreach ($config in $Configurations) {
        switch ($config.ConfigurationName) {
            'max server memory (MB)' {
                if (Compare-Numeric -Value $config.RunningValue -Operator eq -Threshold 2147483647) { Add-Finding -Severity Critical -Category 'Configuration' -Item $config.ConfigurationName -Detail 'Maximum server memory is unlimited.' -Recommendation 'Set max server memory while reserving memory for Windows and other processes.' }
            }
            'cost threshold for parallelism' {
                if (Compare-Numeric -Value $config.RunningValue -Operator le -Threshold 5) { Add-Finding -Severity Warning -Category 'Configuration' -Item $config.ConfigurationName -Detail "Running value is $($config.RunningValue)." -Recommendation 'Establish a workload-based value; 5 is usually too low for modern systems.' }
            }
            'xp_cmdshell' {
                if (Compare-Numeric -Value $config.RunningValue -Operator eq -Threshold 1) { Add-Finding -Severity Warning -Category 'Security' -Item $config.ConfigurationName -Detail 'xp_cmdshell is enabled.' -Recommendation 'Disable unless there is a documented, controlled requirement.' }
            }
            'Ole Automation Procedures' {
                if (Compare-Numeric -Value $config.RunningValue -Operator eq -Threshold 1) { Add-Finding -Severity Warning -Category 'Security' -Item $config.ConfigurationName -Detail 'OLE Automation is enabled.' -Recommendation 'Disable unless there is a documented requirement.' }
            }
            'backup compression default' {
                if (Compare-Numeric -Value $config.RunningValue -Operator eq -Threshold 0) { Add-Finding -Severity Warning -Category 'Configuration' -Item $config.ConfigurationName -Detail 'Backup compression is not the instance default.' -Recommendation 'Enable where supported after CPU/throughput validation.' }
            }
        }
    }
}

$ConfigurationChangesQuery = Get-AssessmentSql -Name 'ConfigurationChangesQuery' -Tokens @{ DaysToAnalyze = $DaysToAnalyze }
$ConfigurationChanges = @(Invoke-AssessmentQuery -Name 'Recent Configuration and Object Changes' -Query $ConfigurationChangesQuery)

$HaQuery = Get-AssessmentSql -Name 'HaQuery'
$AvailabilityGroups = @(Invoke-AssessmentQuery -Name 'Availability Group Status' -Query $HaQuery)
Invoke-AssessmentAnalysis -Name 'Availability group analysis' -ScriptBlock {
    foreach ($row in ($AvailabilityGroups | Where-Object {
            $_.ConnectedState -eq 'DISCONNECTED' -or
            ((Test-HasValue $_.IsSuspended) -and [bool]$_.IsSuspended) -or
            $_.DatabaseHealth -eq 'NOT_HEALTHY'
        })) {
        Add-Finding -Severity Critical -Category 'Availability Group' -Item "$($row.AvailabilityGroup)/$($row.DatabaseName)" `
            -Detail "Replica $($row.Replica): connected=$($row.ConnectedState), state=$($row.SynchronizationState), suspended=$($row.IsSuspended)." `
            -Recommendation 'Investigate endpoint connectivity, suspension reason, queues, and SQL error logs.'
    }
}

$ReplicationQuery = Get-AssessmentSql -Name 'ReplicationQuery'
$Replication = @(Invoke-AssessmentQuery -Name 'Replication Status' -Query $ReplicationQuery)

$MirroringQuery = Get-AssessmentSql -Name 'MirroringQuery'
$Mirroring = @(Invoke-AssessmentQuery -Name 'Database Mirroring Status' -Query $MirroringQuery)
Invoke-AssessmentAnalysis -Name 'Database mirroring analysis' -ScriptBlock {
    foreach ($mirror in ($Mirroring | Where-Object { $_.State -notin @('SYNCHRONIZED','SYNCHRONIZING') })) {
        Add-Finding -Severity Critical -Category 'Database Mirroring' -Item $mirror.DatabaseName `
            -Detail "Mirroring state is $($mirror.State)." -Recommendation 'Investigate partner connectivity and mirroring state.'
    }
}

$SecurityQuery = Get-AssessmentSql -Name 'SecurityQuery'
$Logins = @(Invoke-AssessmentQuery -Name 'Server Security and Permissions' -Query $SecurityQuery)
Invoke-AssessmentAnalysis -Name 'Security and login analysis' -ScriptBlock {
    foreach ($login in ($Logins | Where-Object { $_.IsSysadmin -eq 'Yes' -and $_.IsDisabled -eq $false })) {
        Add-Finding -Severity Warning -Category 'Security' -Item "Sysadmin: $($login.LoginName)" `
            -Detail 'Enabled login has unrestricted sysadmin privileges.' -Recommendation 'Validate business need and remove excess privilege.'
    }
    if (@($Logins | Where-Object { $_.LoginName -eq 'sa' -and $_.IsDisabled -eq $false }).Count -gt 0) {
        Add-Finding -Severity Warning -Category 'Security' -Item 'sa login enabled' `
            -Detail 'The built-in sa login is enabled.' -Recommendation 'Prefer named administrative accounts; disable sa where operationally feasible.'
    }
}

$ServerPermissionsQuery = Get-AssessmentSql -Name 'ServerPermissionsQuery'
$ServerPermissions = @(Invoke-AssessmentQuery -Name 'Server Role and Permission Grants' -Query $ServerPermissionsQuery)

$OrphanedUsersQuery = Get-AssessmentSql -Name 'OrphanedUsersQuery'
$OrphanedUsers = @(Invoke-PerDatabaseAssessmentQuery -Name 'Orphaned Database Users' `
    -Query $OrphanedUsersQuery -DatabaseNames $UserDatabaseNames -QueryTimeout 30)
Invoke-AssessmentAnalysis -Name 'Orphaned user analysis' -ScriptBlock {
    foreach ($orphan in $OrphanedUsers) {
        Add-Finding -Severity Warning -Category 'Security' -Item "$($orphan.DatabaseName).$($orphan.UserName)" `
            -Detail 'Database user is not mapped to a server login.' -Recommendation 'Map to the intended login or remove the unused user.'
    }
}

$MaintenanceQuery = Get-AssessmentSql -Name 'MaintenanceQuery'
$Maintenance = @(Invoke-AssessmentQuery -Name 'Maintenance Jobs' -Query $MaintenanceQuery -Database 'msdb')
Invoke-AssessmentAnalysis -Name 'Maintenance job analysis' -ScriptBlock {
    foreach ($type in @('Backup','Integrity','Index/Statistics')) {
        if (@($Maintenance | Where-Object { $_.MaintenanceType -eq $type -and $_.Enabled }).Count -eq 0) {
            Add-Finding -Severity Warning -Category 'Maintenance' -Item "$type maintenance" `
                -Detail "No enabled $type maintenance job was detected by name/category." `
                -Recommendation 'Confirm that equivalent maintenance is scheduled and monitored.'
        }
    }
}

$AlertQuery = Get-AssessmentSql -Name 'AlertQuery'
$Alerts = @(Invoke-AssessmentQuery -Name 'Alerts and Notification Setup' -Query $AlertQuery -Database 'msdb')
Invoke-AssessmentAnalysis -Name 'Alerting setup analysis' -ScriptBlock {
    foreach ($alert in ($Alerts | Where-Object { Compare-Numeric -Value $_.ConfiguredCount -Operator eq -Threshold 0 })) {
        Add-Finding -Severity Warning -Category 'Alerting' -Item $alert.Component `
            -Detail 'No enabled/configured item was found.' -Recommendation 'Configure and test production alert routing.'
    }
}

$GrowthTrendQuery = Get-AssessmentSql -Name 'GrowthTrendQuery' -Tokens @{ DaysToAnalyze = $DaysToAnalyze }
$GrowthTrends = @(Invoke-AssessmentQuery -Name 'Capacity and Growth Trends' -Query $GrowthTrendQuery -Database 'msdb')
Invoke-AssessmentAnalysis -Name 'Capacity trend analysis' -ScriptBlock {
    foreach ($trend in ($GrowthTrends | Where-Object { Compare-Numeric -Value $_.GrowthMBPerDay -Operator gt -Threshold 100 })) {
        Add-Finding -Severity Warning -Category 'Capacity' -Item $trend.DatabaseName `
            -Detail "Estimated growth is $($trend.GrowthMBPerDay) MB/day; projected 90-day backup size $($trend.Projected90DayMB) MB." `
            -Recommendation 'Validate the trend against file size history and reserve storage capacity.'
    }
}

# Adapted from the repository index/statistics diagnostics. Catalog and usage
# collectors are lightweight and always run; physical fragmentation remains gated
# by -DeepIndexCheck below.
$StatisticsHealthQuery = Get-AssessmentSql -Name 'StatisticsHealthQuery'
$StatisticsHealth = @(Invoke-PerDatabaseAssessmentQuery -Name 'Table Statistics Health' `
    -Query $StatisticsHealthQuery -DatabaseNames $UserDatabaseNames)
Invoke-AssessmentAnalysis -Name 'Table statistics analysis' -ScriptBlock {
    foreach ($stat in $StatisticsHealth) {
        $rows = if (Test-HasNumericValue $stat.Rows) { [double]$stat.Rows } else { 0 }
        $days = if (Test-HasNumericValue $stat.DaysSinceUpdate) { [double]$stat.DaysSinceUpdate } else { $null }
        $modPct = if (Test-HasNumericValue $stat.ModificationPercent) { [double]$stat.ModificationPercent } else { 0 }
        $samplePct = if (Test-HasNumericValue $stat.SamplePercent) { [double]$stat.SamplePercent } else { $null }
        $item = "$($stat.DatabaseName).$($stat.SchemaName).$($stat.TableName).$($stat.StatisticsName)"
        if ($rows -ge 1000 -and (($null -eq $days) -or ($days -gt 30 -and $modPct -ge 20))) {
            Add-Finding -Severity Warning -Category 'Statistics' -Item $item `
                -Detail "Statistics are missing an update timestamp or are $days day(s) old with $modPct% modifications." `
                -Recommendation 'Review workload and update statistics with an appropriate sample during a controlled window; validate plan changes.'
        }
        elseif ($rows -ge 100000 -and $null -ne $samplePct -and $samplePct -lt 10 -and $modPct -ge 10) {
            Add-Finding -Severity Warning -Category 'Statistics' -Item $item `
                -Detail "Large-table statistics sampled $samplePct% with $modPct% modifications." `
                -Recommendation 'Investigate estimate quality before choosing a higher sample rate; avoid assuming FULLSCAN is always required.'
        }
    }
}

$IndexStatusQuery = Get-AssessmentSql -Name 'IndexStatusQuery'
$IndexStatus = @(Invoke-PerDatabaseAssessmentQuery -Name 'Index Status and Usage' `
    -Query $IndexStatusQuery -DatabaseNames $UserDatabaseNames)
Invoke-AssessmentAnalysis -Name 'Index status analysis' -ScriptBlock {
    foreach ($index in $IndexStatus) {
        if ([bool]$index.IsDisabled -or [bool]$index.IsHypothetical) {
            Add-Finding -Severity Warning -Category 'Index Status' `
                -Item "$($index.DatabaseName).$($index.SchemaName).$($index.TableName).$($index.IndexName)" `
                -Detail "Disabled=$($index.IsDisabled), hypothetical=$($index.IsHypothetical), pages=$($index.PageCount)." `
                -Recommendation 'Confirm intent and dependency history; enable/rebuild or remove only after plan and change-window validation.'
        }
    }
}

$UnusedIndexes = @($IndexStatus | Where-Object {
        -not [bool]$_.IsPrimaryKey -and -not [bool]$_.IsUniqueConstraint -and
        -not [bool]$_.IsDisabled -and -not [bool]$_.IsHypothetical -and
        (([long]$_.Seeks + [long]$_.Scans + [long]$_.Lookups) -eq 0) -and
        ([long]$_.Updates -gt 0)
    } | ForEach-Object {
        $lastRead = @(@($_.LastUserSeek,$_.LastUserScan,$_.LastUserLookup) |
                Where-Object { Test-HasValue $_ } | Sort-Object -Descending |
                Select-Object -First 1)
        [PSCustomObject]@{
            DatabaseName = $_.DatabaseName; SchemaName = $_.SchemaName; TableName = $_.TableName
            IndexName = $_.IndexName; PageCount = $_.PageCount
            SizeMB = [math]::Round(([double]$_.PageCount * 8 / 1024),2)
            Reads = ([long]$_.Seeks + [long]$_.Scans + [long]$_.Lookups); Writes = $_.Updates
            LastRead = if ($lastRead.Count -gt 0) { $lastRead[0] } else { $null }
            LastWrite = $_.LastUserUpdate
            ReviewRationale = 'No reads but write maintenance since usage DMVs last reset; review across a representative business cycle before any change.'
        }
    })
$Sections['Unused Index Candidates'] = $UnusedIndexes
if ($UnusedIndexes.Count -gt 0) {
    Add-Finding -Severity Warning -Category 'Index Review' -Item 'Unused index candidates' `
        -Detail "$($UnusedIndexes.Count) non-constraint index(es) had writes but no reads since SQL Server restart/DMV reset." `
        -Recommendation 'Treat as review candidates only; compare Query Store, workload cycles, restart time, and dependencies. Never drop automatically.'
}

$DuplicateIndexQuery = Get-AssessmentSql -Name 'DuplicateIndexQuery'
$DuplicateIndexes = @(Invoke-PerDatabaseAssessmentQuery -Name 'Duplicate and Overlapping Indexes' `
    -Query $DuplicateIndexQuery -DatabaseNames $UserDatabaseNames)
if ($DuplicateIndexes.Count -gt 0) {
    Add-Finding -Severity Warning -Category 'Index Review' -Item 'Duplicate or overlapping indexes' `
        -Detail "$($DuplicateIndexes.Count) same-key index pair(s) require consolidation review." `
        -Recommendation 'Compare ordered keys, INCLUDE coverage, filters, uniqueness, usage, and plans. These are review candidates, not automatic DROP actions.'
}

$ProcedurePerformanceQuery = Get-AssessmentSql -Name 'ProcedurePerformanceQuery'
$ProcedurePerformance = @(Invoke-PerDatabaseAssessmentQuery -Name 'Stored Procedure Performance Audit' `
    -Query $ProcedurePerformanceQuery -DatabaseNames $UserDatabaseNames)
Invoke-AssessmentAnalysis -Name 'Stored procedure performance analysis' -ScriptBlock {
    # Find relative outliers per database (5x the median of at least three cached
    # procedures) instead of pretending one universal threshold fits every workload.
    $candidateKeys = [System.Collections.Generic.HashSet[string]]::new()
    $procedureCandidates = [System.Collections.Generic.List[object]]::new()
    foreach ($databaseGroup in ($ProcedurePerformance | Group-Object -Property DatabaseName)) {
        foreach ($metric in @('AvgCpuMs','AvgElapsedMs','AvgLogicalReads')) {
            $ranked = @($databaseGroup.Group | Where-Object {
                    Test-HasNumericValue $_.$metric
                } | Sort-Object -Property $metric)
            if ($ranked.Count -lt 3) { continue }
            $middle = [math]::Floor($ranked.Count / 2)
            $median = if (($ranked.Count % 2) -eq 1) {
                [double]$ranked[$middle].$metric
            }
            else {
                ([double]$ranked[$middle - 1].$metric + [double]$ranked[$middle].$metric) / 2
            }
            $procedure = $ranked[-1]
            $topValue = [double]$procedure.$metric
            $isOutlier = ($median -gt 0 -and $topValue -ge ($median * 5)) -or
                ($median -eq 0 -and $topValue -gt 0)
            if ($isOutlier) {
                $key = "$($procedure.DatabaseName)|$($procedure.SchemaName)|$($procedure.ProcedureName)"
                if ($candidateKeys.Add($key)) { $procedureCandidates.Add($procedure) }
            }
        }
    }
    foreach ($procedure in $procedureCandidates) {
        Add-Finding -Severity Warning -Category 'Stored Procedure Performance' `
            -Item "$($procedure.DatabaseName).$($procedure.SchemaName).$($procedure.ProcedureName)" `
            -Detail "Top cached average-cost candidate: executions=$($procedure.ExecutionCount), avg CPU=$($procedure.AvgCpuMs)ms, avg elapsed=$($procedure.AvgElapsedMs)ms, avg reads=$($procedure.AvgLogicalReads)." `
            -Recommendation 'Investigate against workload baselines and execution plans; cached DMV data resets on restart, recompile, and cache eviction.'
    }
}

# Adapted from memory_bottleneck_deep_dive.sql into concise, report-friendly
# result sets. No binary plan handles or XML plans are exposed.
$MemorySnapshotQuery = Get-AssessmentSql -Name 'MemorySnapshotQuery'
$MemorySnapshot = @(Invoke-AssessmentQuery -Name 'Memory Pressure Snapshot' -Query $MemorySnapshotQuery)

$MemoryClerksQuery = Get-AssessmentSql -Name 'MemoryClerksQuery'
$MemoryClerks = @(Invoke-AssessmentQuery -Name 'Memory Clerk Consumers' -Query $MemoryClerksQuery)

$MemoryGrantsQuery = Get-AssessmentSql -Name 'MemoryGrantsQuery'
$MemoryGrants = @(Invoke-AssessmentQuery -Name 'Active Memory Grants' -Query $MemoryGrantsQuery)

$BufferCacheQuery = Get-AssessmentSql -Name 'BufferCacheQuery'
$BufferCache = @(Invoke-AssessmentQuery -Name 'Buffer Cache by Database' -Query $BufferCacheQuery)

$ResourceSemaphoreQuery = Get-AssessmentSql -Name 'ResourceSemaphoreQuery'
$ResourceSemaphore = @(Invoke-AssessmentQuery -Name 'Resource Semaphore Waits' -Query $ResourceSemaphoreQuery)

$MemoryQueryConsumersQuery = Get-AssessmentSql -Name 'MemoryQueryConsumersQuery'
$MemoryQueryConsumers = @(Invoke-AssessmentQuery -Name 'Top Cached Query Memory Grants' -Query $MemoryQueryConsumersQuery)

Invoke-AssessmentAnalysis -Name 'Memory bottleneck analysis' -ScriptBlock {
    if ($MemorySnapshot.Count -gt 0) {
        $memory = $MemorySnapshot[0]
        if ((Compare-Numeric $memory.MemoryGrantsPending gt 0)) {
            Add-Finding -Severity Critical -Category 'Memory Pressure' -Item 'Memory grants pending' `
                -Detail "$($memory.MemoryGrantsPending) query memory grant(s) are pending now." `
                -Recommendation 'Inspect Active Memory Grants and high-grant cached queries; tune sorts/hashes, cardinality, and DOP before adding memory.'
        }
        if (((Test-HasValue $memory.ProcessPhysicalMemoryLow) -and [bool]$memory.ProcessPhysicalMemoryLow) -or
            ((Test-HasValue $memory.ProcessVirtualMemoryLow) -and [bool]$memory.ProcessVirtualMemoryLow)) {
            Add-Finding -Severity Critical -Category 'Memory Pressure' -Item 'SQL process low-memory signal' `
                -Detail "Physical low=$($memory.ProcessPhysicalMemoryLow), virtual low=$($memory.ProcessVirtualMemoryLow)." `
                -Recommendation 'Correlate SQL max memory, OS available memory, other processes, grants, and clerks immediately.'
        }
        if (Compare-Numeric $memory.ResourceSemaphoreWaitPercent ge 10) {
            Add-Finding -Severity Warning -Category 'Memory Pressure' -Item 'RESOURCE_SEMAPHORE wait share' `
                -Detail "RESOURCE_SEMAPHORE represents $($memory.ResourceSemaphoreWaitPercent)% of accumulated wait time." `
                -Recommendation 'This is cumulative evidence, not proof of current pressure; correlate with pending grants and peak workload.'
        }
        if ((Test-HasNumericValue $memory.TargetServerMemoryMB) -and
            (Test-HasNumericValue $memory.TotalServerMemoryMB) -and
            [double]$memory.TargetServerMemoryMB -gt 0 -and
            [double]$memory.TotalServerMemoryMB -lt ([double]$memory.TargetServerMemoryMB * 0.8)) {
            Add-Finding -Severity Warning -Category 'Memory Pressure' -Item 'Target versus total server memory gap' `
                -Detail "Total=$($memory.TotalServerMemoryMB) MB, target=$($memory.TargetServerMemoryMB) MB." `
                -Recommendation 'A gap can be normal after restart or workload changes; correlate with uptime, PLE, grants, and OS pressure before action.'
        }
        if ((Test-HasNumericValue $memory.PageLifeExpectancySeconds) -and
            (Test-HasNumericValue $memory.TotalServerMemoryMB) -and
            [double]$memory.TotalServerMemoryMB -gt 0) {
            $pleThreshold = ([double]$memory.TotalServerMemoryMB / 1024 / 4) * 150
            if ([double]$memory.PageLifeExpectancySeconds -lt $pleThreshold) {
                Add-Finding -Severity Warning -Category 'Memory Pressure' -Item 'Page life expectancy below scaled guideline' `
                    -Detail "PLE=$($memory.PageLifeExpectancySeconds)s; memory-scaled investigation guideline=$([math]::Round($pleThreshold))s." `
                    -Recommendation 'PLE is workload-dependent; correlate sustained drops with page reads, grants, and OS memory before changing capacity.'
            }
        }
    }
    foreach ($grant in ($MemoryGrants | Where-Object { $_.GrantStatus -eq 'Waiting' })) {
        Add-Finding -Severity Critical -Category 'Memory Pressure' -Item "Waiting grant session $($grant.SessionId)" `
            -Detail "Requested=$($grant.RequestedMB) MB, wait=$($grant.WaitTimeMs) ms, DOP=$($grant.DOP)." `
            -Recommendation 'Investigate the query plan, estimates, concurrency, and DOP; avoid killing sessions without impact review.'
    }
}

$FragmentedIndexes = @()
$MissingIndexQuery = Get-AssessmentSql -Name 'MissingIndexQuery'
$MissingIndexes = @(Invoke-AssessmentQuery -Name 'Missing Index Indicators' -Query $MissingIndexQuery)
$FragmentationQuery = Get-AssessmentSql -Name 'FragmentationQuery'
if ($DeepIndexCheck) {
    Write-Host 'Collecting deep index health...' -NoNewline
    foreach ($databaseName in $UserDatabaseNames) {
        try {
            $frag = @(Invoke-DbaQuery -SqlInstance $SqlServer -Database $databaseName -Query $FragmentationQuery -QueryTimeout 180 -As PSObject -EnableException)
            $FragmentedIndexes += $frag
        }
        catch {
            $CollectionErrors.Add([PSCustomObject]@{ Section="Index fragmentation - $databaseName"; Error=$_.Exception.Message })
        }
    }
    Write-Host 'DONE' -ForegroundColor Green
    Invoke-AssessmentAnalysis -Name 'Index fragmentation analysis' -ScriptBlock {
        foreach ($index in $FragmentedIndexes) {
            $statusRow = $IndexStatus | Where-Object {
                $_.DatabaseName -eq $index.DatabaseName -and
                $_.SchemaName -eq $index.SchemaName -and
                $_.TableName -eq $index.TableName -and
                $_.IndexName -eq $index.IndexName
            } | Select-Object -First 1
            if ($statusRow) { $statusRow.FragmentationPercent = $index.FragmentationPercent }
            Add-Finding -Severity Warning -Category 'Index Fragmentation' `
                -Item "$($index.DatabaseName).$($index.SchemaName).$($index.TableName).$($index.IndexName)" `
                -Detail "$($index.FragmentationPercent)% fragmented across $($index.PageCount) pages (LIMITED scan; minimum 1,000 pages)." `
                -Recommendation 'Validate scan patterns, page density, write load, and maintenance window before reorganize/rebuild; fragmentation alone is not an automatic rebuild instruction.'
        }
    }
}
else {
    Add-Finding -Severity Info -Category 'Collection Scope' -Item 'Deep index health' `
        -Detail 'Skipped by default because physical index scans can be expensive.' `
        -Recommendation 'Run again with -DeepIndexCheck during a low-activity period.'
}
$Sections['Fragmented Indexes'] = @($FragmentedIndexes)

#endregion

#region ============================================================================
# HTML REPORT
# =================================================================================

$healthScore = [math]::Max(0, 100 - ($CriticalIssues.Count * 12) - ($WarningIssues.Count * 3))
$healthLabel = if ($healthScore -ge 85) { 'Healthy' } elseif ($healthScore -ge 65) { 'Needs Attention' } else { 'Critical' }
$healthClass = if ($healthScore -ge 85) { 'good' } elseif ($healthScore -ge 65) { 'warn' } else { 'bad' }

function ConvertTo-IssueCards {
    param([object[]]$Issues, [string]$CssClass)
    if (@($Issues).Count -eq 0) { return "<p class='no-data good-text'>No issues found in this category.</p>" }
    $cards = foreach ($issue in $Issues) {
        "<article class='issue $CssClass'><div class='issue-head'><strong>$(ConvertTo-HtmlEncoded $issue.Category)</strong><span class='badge $CssClass'>$(ConvertTo-HtmlEncoded $issue.Severity)</span></div><h3>$(ConvertTo-HtmlEncoded $issue.Item)</h3><p>$(ConvertTo-HtmlEncoded $issue.Detail)</p><p class='recommend'><strong>Recommended:</strong> $(ConvertTo-HtmlEncoded $issue.Recommendation)</p></article>"
    }
    return ($cards -join [Environment]::NewLine)
}

$InventoryCards = if ($Inventory.Count) {
    $i = $Inventory[0]
    @"
<div class='metrics'>
 <div class='metric'><span>Version</span><strong>$(ConvertTo-HtmlEncoded $i.ProductVersion)</strong></div>
 <div class='metric'><span>Edition</span><strong>$(ConvertTo-HtmlEncoded $i.Edition)</strong></div>
 <div class='metric'><span>Patch</span><strong>$(ConvertTo-HtmlEncoded ("$($i.ProductLevel) $($i.ProductUpdateLevel)"))</strong></div>
 <div class='metric'><span>Uptime</span><strong>$(if (Test-HasNumericValue $i.UptimeMinutes) { [math]::Floor($i.UptimeMinutes/1440) } else { 'N/A' }) days</strong></div>
 <div class='metric'><span>CPU</span><strong>$(ConvertTo-HtmlEncoded $i.LogicalCpuCount) logical</strong></div>
 <div class='metric'><span>Memory</span><strong>$(if (Test-HasNumericValue $i.PhysicalMemoryMB) { [math]::Round($i.PhysicalMemoryMB/1024,1) } else { 'N/A' }) GB</strong></div>
</div>
"@
} else { "<p class='no-data'>Inventory unavailable.</p>" }

$sectionOrder = @(
    'SQL Services','Database Inventory and Configuration','Backup Status','SQL Agent Jobs','Recent Job Failures',
    'SQL Data Log and TempDB Volumes','Backup Destinations and Free Space','Database Integrity History','SQL Error Log Issues','Windows Critical Events',
    'Current Blocking','Active and Long Running Queries','Wait Statistics','CPU and Memory Pressure','File IO Latency',
    'Top Resource Consumers','TempDB Health','Database File Growth Settings','Recent Auto-growth Events',
    'Instance Configuration','Recent Configuration and Object Changes','Availability Group Status','Replication Status','Database Mirroring Status',
    'Server Security and Permissions','Server Role and Permission Grants','Orphaned Database Users','Maintenance Jobs','Alerts and Notification Setup',
    'Capacity and Growth Trends','Table Statistics Health','Index Status and Usage','Unused Index Candidates',
    'Duplicate and Overlapping Indexes','Fragmented Indexes','Missing Index Indicators',
    'Stored Procedure Performance Audit','Memory Pressure Snapshot','Memory Clerk Consumers',
    'Active Memory Grants','Buffer Cache by Database','Resource Semaphore Waits','Top Cached Query Memory Grants'
)
$PopulatedSectionCount = @($sectionOrder | Where-Object {
        @(@($Sections[$_]) | Where-Object { $null -ne $_ }).Count -gt 0
    }).Count
$DatabaseFilterNames = @($Sections.Values | ForEach-Object {
        foreach ($row in @($_)) {
            if ($null -eq $row) { continue }
            $databaseProperty = $row.PSObject.Properties['DatabaseName']
            if ($databaseProperty -and (Test-HasValue $databaseProperty.Value) -and
                [string]$databaseProperty.Value -ne 'Resource/Free Pages') {
                [string]$databaseProperty.Value
            }
        }
    } | Sort-Object -Unique)
$DatabaseFilterOptions = @("<option value=''>All Databases</option>")
$DatabaseFilterOptions += @($DatabaseFilterNames | ForEach-Object {
        $encodedName = ConvertTo-HtmlEncoded $_
        "<option value='$encodedName'>$encodedName</option>"
    })
# Each report section becomes a panel; the fixed left sidebar shows one panel at a
# time ('Summary of Findings' is the default landing panel).
$AllFindingsOrdered = @($CriticalIssues) + @($WarningIssues) + @($InformationItems)

# Severity doughnut (pure CSS conic-gradient, no external chart library).
$sevCritical = $CriticalIssues.Count
$sevWarning = $WarningIssues.Count
$sevInfo = $InformationItems.Count
$sevTotal = $sevCritical + $sevWarning + $sevInfo
$donutStyle = 'background:#e2e8f0'
if ($sevTotal -gt 0) {
    $degCritical = [math]::Round(360.0 * $sevCritical / $sevTotal, 1)
    $degWarning = [math]::Round(360.0 * ($sevCritical + $sevWarning) / $sevTotal, 1)
    $donutStyle = "background:conic-gradient(var(--bad) 0deg ${degCritical}deg,var(--warn) ${degCritical}deg ${degWarning}deg,var(--blue) ${degWarning}deg 360deg)"
}

# Horizontal category bars for actionable (Critical + Warning) findings.
$CategoryGroups = @(@($CriticalIssues) + @($WarningIssues) | Group-Object -Property Category | Sort-Object -Property Count -Descending)
$categoryBarsHtml = if ($CategoryGroups.Count -eq 0) {
    "<p class='no-data good-text'>No critical or warning findings.</p>"
}
else {
    $maxCategoryCount = ($CategoryGroups | Measure-Object -Property Count -Maximum).Maximum
    $bars = foreach ($group in ($CategoryGroups | Select-Object -First 12)) {
        $widthPercent = [math]::Max(2, [math]::Round(100.0 * $group.Count / $maxCategoryCount, 1))
        $criticalInGroup = @($group.Group | Where-Object { $_.Severity -eq 'Critical' }).Count
        $fillClass = if ($criticalInGroup -gt 0) { 'bad' } else { 'warn' }
        "<div class='cat-row'><span class='cat-name' title='$(ConvertTo-HtmlEncoded $group.Name)'>$(ConvertTo-HtmlEncoded $group.Name)</span><div class='cat-bar'><div class='cat-fill $fillClass' style='width:${widthPercent}%'></div></div><span class='cat-count'>$($group.Count)</span></div>"
    }
    $bars -join [Environment]::NewLine
}

# Prioritized findings table: Critical, then Warning, then Info.
$findingsTableHtml = if ($AllFindingsOrdered.Count -eq 0) {
    "<p class='no-data good-text'>No findings were recorded.</p>"
}
else {
    $rowsHtml = foreach ($finding in $AllFindingsOrdered) {
        $sevClass = switch ($finding.Severity) { 'Critical' { 'bad' } 'Warning' { 'warn' } default { 'info' } }
        "<tr><td><span class='badge $sevClass'>$(ConvertTo-HtmlEncoded $finding.Severity)</span></td><td>$(ConvertTo-HtmlEncoded $finding.Category)</td><td>$(ConvertTo-HtmlEncoded $finding.Item)</td><td>$(ConvertTo-HtmlEncoded $finding.Detail)</td><td>$(ConvertTo-HtmlEncoded $finding.Recommendation)</td></tr>"
    }
    "<div class='table-wrap'><table id='allFindings' class='data-table'><thead><tr><th>Severity</th><th>Category</th><th>Item</th><th>Detail</th><th>Recommendation</th></tr></thead><tbody>$($rowsHtml -join '')</tbody></table></div>"
}

$SummaryContent = @"
<header class='header'>
 <h1>SQL Server DBA Assessment Report</h1>
 <div class='meta'>Server: $(ConvertTo-HtmlEncoded $ServerIP) &nbsp;|&nbsp; Generated: $($ReportTimestamp.ToString('yyyy-MM-dd HH:mm:ss')) &nbsp;|&nbsp; Lookback: $DaysToAnalyze days</div>
 <div class='score-row'><div class='score $healthClass'>$healthScore</div><div><h2>Overall health: $healthLabel</h2><div>Critical: $sevCritical &nbsp; Warnings: $sevWarning &nbsp; Collection notes: $sevInfo</div></div></div>
 $InventoryCards
</header>
<section class='section'><h2>Key Indicators</h2>
 <div class='kpi-row'>
  <div class='kpi'><span>Health Score</span><strong class='$healthClass-text'>$healthScore / 100</strong><small>$healthLabel</small></div>
  <div class='kpi'><span>Critical</span><strong class='bad-text'>$sevCritical</strong><small>broken now</small></div>
  <div class='kpi'><span>Warnings</span><strong class='warn-text'>$sevWarning</strong><small>at risk soon</small></div>
  <div class='kpi'><span>Info</span><strong class='info-text'>$sevInfo</strong><small>scope notes</small></div>
  <div class='kpi'><span>Collection Errors</span><strong class='$(if ($CollectionErrors.Count -gt 0) { 'bad-text' } else { 'good-text' })'>$($CollectionErrors.Count)</strong><small>failed collectors</small></div>
 </div>
</section>
<section class='section'><h2>Findings Overview</h2>
 <div class='charts-row'>
  <div class='chart-card'>
   <h3>Findings by Severity</h3>
   <div class='donut-wrap'>
    <div class='donut' style='$donutStyle'><div class='donut-hole'><strong>$sevTotal</strong><span>findings</span></div></div>
    <div class='legend'>
     <div><i class='swatch' style='background:var(--bad)'></i>Critical: $sevCritical</div>
     <div><i class='swatch' style='background:var(--warn)'></i>Warning: $sevWarning</div>
     <div><i class='swatch' style='background:var(--blue)'></i>Info: $sevInfo</div>
    </div>
   </div>
  </div>
  <div class='chart-card'>
   <h3>Critical and Warning Findings by Category</h3>
   $categoryBarsHtml
  </div>
 </div>
</section>
<section class='section'><h2>All Findings (Prioritized)</h2>
 <p class='note'>Ordered by severity: Critical first, then Warning, then Info. Use <strong>What Is Broken Now</strong> and <strong>What Is At Risk Soon</strong> in the left menu for the full card view with recommendations.</p>
 $findingsTableHtml
</section>
"@

$ScopeContent = @"
<section class='section'><h2>Assessment Scope and Collection Notes</h2>
 <p class='note'>This is a point-in-time assessment. DMV counters generally reset when SQL Server restarts. Live session collectors exclude this collector and dbatools PowerShell sessions. Cached query/procedure DMVs do not retain client program names: cached-query reports exclude the assessment SQL marker, while stored-procedure results exclude MS-shipped procedures but remain workload-wide. Capacity projections use full-backup size history as an estimate and should be validated against retained file-size monitoring.</p>
 $(ConvertTo-HtmlTable -Data @($InformationItems) -Properties @('Category','Item','Detail','Recommendation') -TableId 'collectionNotes')
</section>
"@

$PanelDefinitions = [System.Collections.Generic.List[object]]::new()
$PanelDefinitions.Add([PSCustomObject]@{
    Id = 'panel_summary'; Title = 'Summary of Findings'; Group = 'Summary'; BadgeCount = 0; BadgeClass = ''
    Content = $SummaryContent
})
$PanelDefinitions.Add([PSCustomObject]@{
    Id = 'panel_broken_now'; Title = 'What Is Broken Now'; Group = 'Summary'; BadgeCount = $CriticalIssues.Count; BadgeClass = 'bad'
    Content = "<section class='section priority bad'><h2>What Is Broken Now</h2>$(ConvertTo-IssueCards -Issues @($CriticalIssues) -CssClass 'bad')</section>"
})
$PanelDefinitions.Add([PSCustomObject]@{
    Id = 'panel_at_risk'; Title = 'What Is At Risk Soon'; Group = 'Summary'; BadgeCount = $WarningIssues.Count; BadgeClass = 'warn'
    Content = "<section class='section priority warn'><h2>What Is At Risk Soon</h2>$(ConvertTo-IssueCards -Issues @($WarningIssues) -CssClass 'warn')</section>"
})
$PanelDefinitions.Add([PSCustomObject]@{
    Id = 'panel_scope_notes'; Title = 'Scope and Collection Notes'; Group = 'Summary'; BadgeCount = 0; BadgeClass = ''
    Content = $ScopeContent
})
foreach ($sectionName in $sectionOrder) {
    $data = @(@($Sections[$sectionName]) | Where-Object { $null -ne $_ })
    if ($data.Count -eq 0) { continue }
    $panelId = 'panel_' + ($sectionName -replace '\W', '_')
    $content = "<section class='section'><h2>$(ConvertTo-HtmlEncoded $sectionName)</h2>" +
        (ConvertTo-HtmlTable -Data $data -TableId ($sectionName -replace '\W', '_')) + '</section>'
    $PanelDefinitions.Add([PSCustomObject]@{
        Id = $panelId; Title = $sectionName; Group = 'Evidence'; BadgeCount = 0; BadgeClass = ''
        Content = $content
    })
}
if ($CollectionErrors.Count -gt 0) {
    $PanelDefinitions.Add([PSCustomObject]@{
        Id = 'panel_collection_errors'; Title = 'Collection Errors'; Group = 'Diagnostics'; BadgeCount = $CollectionErrors.Count; BadgeClass = 'bad'
        Content = "<section class='section'><h2>Collection Errors</h2>$(ConvertTo-HtmlTable -Data @($CollectionErrors) -Properties @('Section','Error') -TableId 'collectionErrors')</section>"
    })
}

$navHtml = [System.Text.StringBuilder]::new()
$panelHtml = [System.Text.StringBuilder]::new()
$currentGroup = ''
foreach ($panel in $PanelDefinitions) {
    if ($panel.Group -ne $currentGroup) {
        $currentGroup = $panel.Group
        [void]$navHtml.Append("<div class='nav-group'>$(ConvertTo-HtmlEncoded $currentGroup)</div>")
    }
    $activeClass = if ($panel.Id -eq 'panel_summary') { ' active' } else { '' }
    $badgeHtml = if ($panel.BadgeCount -gt 0) { "<span class='nav-badge $($panel.BadgeClass)'>$($panel.BadgeCount)</span>" } else { '' }
    [void]$navHtml.Append("<a href='#' class='nav-item$activeClass' data-target='$($panel.Id)'><span class='nav-label'>$(ConvertTo-HtmlEncoded $panel.Title)</span>$badgeHtml</a>")
    [void]$panelHtml.Append("<div class='panel$activeClass' id='$($panel.Id)'>$($panel.Content)</div>")
}

$HtmlReport = @"
<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>DBA Assessment - $(ConvertTo-HtmlEncoded $ServerIP)</title>
<style>
:root{--navy:#17243a;--blue:#2563eb;--bg:#f3f6fa;--card:#fff;--text:#243047;--muted:#64748b;--bad:#b91c1c;--warn:#b45309;--good:#15803d;--line:#dce3ed;--sidebar-w:290px}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:Segoe UI,Arial,sans-serif;line-height:1.45}
.sidebar{position:fixed;top:0;left:0;bottom:0;width:var(--sidebar-w);background:var(--navy);overflow-y:auto;padding:0 0 20px;z-index:10}
.sidebar-title{color:#fff;font-weight:700;font-size:16px;padding:16px 18px 14px;border-bottom:1px solid #ffffff22}
.sidebar-title small{display:block;color:#93b4e8;font-weight:400;font-size:11px;margin-top:3px;word-break:break-all}
.db-filter{padding:12px 18px;border-bottom:1px solid #ffffff22}.db-filter label{display:block;color:#dbeafe;font-size:11px;font-weight:600;margin-bottom:5px}.db-filter select{width:100%;padding:7px;border:1px solid #6683ad;border-radius:5px;background:#fff;color:var(--navy)}.filter-active{display:none;color:#bfdbfe;font-size:10px;margin-top:5px}.filter-active.active{display:block}
.nav-group{padding:14px 18px 4px;font-size:10px;letter-spacing:1.2px;text-transform:uppercase;color:#7f9cc9}
.nav-item{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:7px 18px;color:#dbeafe;text-decoration:none;font-size:13px;border-left:3px solid transparent}
.nav-item:hover{background:#ffffff14;color:#fff}
.nav-item.active{background:#ffffff1f;border-left-color:#60a5fa;color:#fff;font-weight:600}
.nav-label{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.nav-badge{border-radius:999px;padding:1px 8px;font-size:11px;font-weight:700;color:#fff;flex:none}.nav-badge.bad{background:var(--bad)}.nav-badge.warn{background:var(--warn)}
.main{margin-left:var(--sidebar-w);padding:22px;max-width:1500px}
.panel{display:none}.panel.active{display:block}
.header{background:linear-gradient(130deg,var(--navy),#284c81);color:white;padding:28px;border-radius:14px;box-shadow:0 5px 20px #17243a33}
.header h1{margin:0 0 6px}.meta{color:#dbeafe}.score-row{display:flex;gap:18px;align-items:center;margin-top:20px}
.score{width:92px;height:92px;border-radius:50%;display:grid;place-items:center;font-size:29px;font-weight:700;background:#ffffff20;border:7px solid white}.score.bad{border-color:#fca5a5}.score.warn{border-color:#fcd34d}.score.good{border-color:#86efac}
.metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px;margin-top:18px}.metric{background:#ffffff14;padding:13px;border-radius:9px}.metric span{display:block;color:#dbeafe;font-size:12px}.metric strong{font-size:17px}
.section{background:var(--card);margin-top:20px;padding:20px;border-radius:12px;box-shadow:0 2px 9px #17243a12}.section:first-child{margin-top:0}.section h2{margin:0 0 15px;font-size:20px;border-bottom:2px solid var(--line);padding-bottom:9px}
.priority{border-top:6px solid}.priority.bad{border-color:var(--bad)}.priority.warn{border-color:var(--warn)}
.issue{padding:14px;margin:10px 0;border-left:5px solid;border-radius:6px;background:#fafafa}.issue.bad{border-color:var(--bad);background:#fff5f5}.issue.warn{border-color:var(--warn);background:#fffaf0}.issue h3{margin:5px 0}.issue p{margin:4px 0}.issue-head{display:flex;justify-content:space-between}.recommend{color:var(--muted)}
.badge{border-radius:999px;padding:3px 9px;color:white;font-size:11px;text-transform:uppercase}.badge.bad{background:var(--bad)}.badge.warn{background:var(--warn)}.badge.info{background:var(--blue)}
.bad-text{color:var(--bad)}.warn-text{color:var(--warn)}.info-text{color:var(--blue)}
.kpi-row{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px}
.kpi{background:#f8fafc;border:1px solid var(--line);border-radius:10px;padding:14px;text-align:center}
.kpi span{display:block;font-size:12px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px}
.kpi strong{display:block;font-size:26px;margin:4px 0}
.kpi small{color:var(--muted)}
.charts-row{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px}
.chart-card{background:#f8fafc;border:1px solid var(--line);border-radius:10px;padding:16px}
.chart-card h3{margin:0 0 14px;font-size:14px;color:var(--navy)}
.donut-wrap{display:flex;gap:22px;align-items:center;flex-wrap:wrap}
.donut{width:150px;height:150px;border-radius:50%;display:grid;place-items:center;flex:none}
.donut-hole{width:96px;height:96px;border-radius:50%;background:#f8fafc;display:grid;place-items:center;text-align:center}
.donut-hole strong{font-size:24px;display:block}.donut-hole span{font-size:11px;color:var(--muted)}
.legend div{display:flex;align-items:center;gap:8px;margin:5px 0;font-size:13px}
.swatch{width:12px;height:12px;border-radius:3px;display:inline-block;flex:none}
.cat-row{display:flex;align-items:center;gap:10px;margin:7px 0}
.cat-name{flex:0 0 170px;font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-align:right}
.cat-bar{flex:1;background:#e2e8f0;border-radius:5px;height:16px;overflow:hidden}
.cat-fill{height:100%;border-radius:5px}.cat-fill.bad{background:var(--bad)}.cat-fill.warn{background:var(--warn)}
.cat-count{flex:0 0 30px;font-size:12px;font-weight:600}
.table-wrap{width:100%;overflow:auto;max-height:72vh}.data-table{border-collapse:collapse;width:100%;font-size:12px}.data-table th{position:sticky;top:0;background:var(--navy);color:white;text-align:left;padding:9px;white-space:nowrap;cursor:pointer;user-select:none;z-index:1}.data-table th:hover,.data-table th:focus{background:#22345a;outline:2px solid #93c5fd;outline-offset:-2px}.data-table td{padding:8px;border-bottom:1px solid var(--line);max-width:520px;word-break:break-word}.data-table tr:nth-child(even){background:#f8fafc}
.data-table th.sort-asc::after{content:' \25B2';font-size:9px}.data-table th.sort-desc::after{content:' \25BC';font-size:9px}
.pagination-controls{position:sticky;left:0;display:flex;align-items:center;gap:8px;flex-wrap:wrap;padding:10px 0;background:var(--card)}.pagination-controls[hidden]{display:none}.pagination-controls button,.pagination-controls select{border:1px solid #b8c4d6;border-radius:5px;background:#fff;color:var(--navy);padding:5px 9px}.pagination-controls button:disabled{opacity:.45;cursor:not-allowed}.page-status{font-size:12px;color:var(--muted);min-width:130px}.page-size-label{font-size:12px;color:var(--muted)}.table-empty-state{color:var(--muted);font-style:italic;margin:12px 0}.table-empty-state[hidden]{display:none}
.cell-good{background:#dcfce7;color:#14532d;font-weight:600}.cell-warn{background:#fef3c7;color:#92400e;font-weight:600}.cell-bad{background:#fee2e2;color:#991b1b;font-weight:600}
.no-data{color:var(--muted);font-style:italic}.good-text{color:var(--good)}.note{background:#eff6ff;border-left:4px solid var(--blue);padding:12px;margin:0}.footer{text-align:center;color:var(--muted);padding:28px}
.export-btn{position:fixed;top:14px;right:22px;z-index:30;display:inline-flex;align-items:center;gap:7px;background:linear-gradient(130deg,var(--blue),#1e40af);color:#fff;border:1px solid #1e3a8a;border-radius:8px;padding:9px 16px;font-weight:600;font-size:13px;font-family:inherit;cursor:pointer;box-shadow:0 3px 10px #17243a44}
.export-btn:hover{background:linear-gradient(130deg,#1d4ed8,#1e3a8a)}.export-btn:focus{outline:2px solid #93c5fd;outline-offset:2px}.export-btn:disabled{opacity:.5;cursor:not-allowed}
@media(max-width:900px){.sidebar{position:static;width:auto;bottom:auto}.main{margin-left:0;padding:10px}.score-row{align-items:flex-start;flex-direction:column}.header{padding:18px}.export-btn{position:static;margin:10px}}
@media print{body{background:white}.sidebar{display:none}.main{margin-left:0;max-width:none}.panel{display:block}.section,.header{box-shadow:none;break-inside:avoid}.table-wrap{max-height:none;overflow:visible}.pagination-controls{display:none!important}.export-btn{display:none!important}.data-table{font-size:9px}}
</style>
</head>
<body>
<button type='button' id='exportExcelButton' class='export-btn'
 title='Download every report section as a multi-sheet Excel workbook (.xls, SpreadsheetML). Always exports all rows of every section, regardless of the database filter or table pagination.'
 aria-label='Export the full report to Excel'>&#x2B07; Export to Excel</button>
<nav class='sidebar' id='sidebar'>
 <div class='sidebar-title'>SQL Server DBA Assessment<small>$(ConvertTo-HtmlEncoded $ServerIP) &middot; $($ReportTimestamp.ToString('yyyy-MM-dd HH:mm'))</small></div>
 <div class='db-filter'>
  <label for='databaseFilter'>Filter evidence by database</label>
  <select id='databaseFilter' aria-label='Filter report tables by database'>$($DatabaseFilterOptions -join '')</select>
  <span id='databaseFilterActive' class='filter-active' aria-live='polite'>Database filter active</span>
 </div>
 $($navHtml.ToString())
</nav>
<main class='main' id='main'>
$($panelHtml.ToString())
<footer class='footer'>Generated with dbatools. Review findings with workload owners before changing production configuration.</footer>
</main>
<script>
(function () {
    var links = document.querySelectorAll('.nav-item');
    var panels = document.querySelectorAll('.panel');
    function show(id) {
        panels.forEach(function (p) { p.classList.toggle('active', p.id === id); });
        links.forEach(function (l) { l.classList.toggle('active', l.getAttribute('data-target') === id); });
        window.scrollTo(0, 0);
    }
    links.forEach(function (link) {
        link.addEventListener('click', function (event) {
            event.preventDefault();
            show(link.getAttribute('data-target'));
        });
    });

    // Filter -> sort -> paginate controller for every data table.
    var DATE_RE = /^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}(:\d{2})?)?$/;
    var NUM_RE = /^-?\d+(\.\d+)?\s*(%|ms|mb|gb|kb|days?)?$/i;
    var databaseFilter = document.getElementById('databaseFilter');
    var filterIndicator = document.getElementById('databaseFilterActive');
    var controllers = [];
    function isBlank(t) { return t === '' || t === 'N/A'; }
    function cellText(row, index) {
        return row.cells[index] ? row.cells[index].textContent.trim() : '';
    }

    function TableController(table) {
        this.table = table;
        this.tbody = table.tBodies[0];
        this.headers = table.tHead && table.tHead.rows.length ? table.tHead.rows[0].cells : [];
        this.rows = this.tbody ? Array.prototype.slice.call(this.tbody.rows) : [];
        this.page = 1;
        this.pageSize = 25;
        this.sortColumn = null;
        this.sortDirection = 'asc';
        this.printing = false;
        this.databaseColumn = -1;
        for (var h = 0; h < this.headers.length; h++) {
            if (this.headers[h].textContent.trim().replace(/\s+/g, '').toLowerCase() === 'databasename') {
                this.databaseColumn = h;
            }
        }
        this.buildControls();
        this.bindSorting();
        this.render();
    }

    TableController.prototype.buildControls = function () {
        var self = this;
        this.emptyState = document.createElement('p');
        this.emptyState.className = 'table-empty-state';
        this.emptyState.textContent = 'No rows for selected database.';
        this.emptyState.hidden = true;
        this.table.parentNode.appendChild(this.emptyState);

        this.controls = document.createElement('div');
        this.controls.className = 'pagination-controls';
        this.controls.hidden = true;
        this.previous = document.createElement('button');
        this.previous.type = 'button';
        this.previous.textContent = 'Previous';
        this.previous.setAttribute('aria-label', 'Show previous table page');
        this.next = document.createElement('button');
        this.next.type = 'button';
        this.next.textContent = 'Next';
        this.next.setAttribute('aria-label', 'Show next table page');
        this.status = document.createElement('span');
        this.status.className = 'page-status';
        this.status.setAttribute('aria-live', 'polite');
        var sizeLabel = document.createElement('label');
        sizeLabel.className = 'page-size-label';
        sizeLabel.textContent = 'Rows per page ';
        this.size = document.createElement('select');
        this.size.setAttribute('aria-label', 'Rows per page');
        [20, 25, 30, 50].forEach(function (value) {
            var option = document.createElement('option');
            option.value = String(value);
            option.textContent = String(value);
            if (value === 25) { option.selected = true; }
            self.size.appendChild(option);
        });
        sizeLabel.appendChild(this.size);
        this.controls.appendChild(this.previous);
        this.controls.appendChild(this.next);
        this.controls.appendChild(this.status);
        this.controls.appendChild(sizeLabel);
        this.table.parentNode.appendChild(this.controls);
        this.previous.addEventListener('click', function () {
            if (self.page > 1) { self.page--; self.render(); }
        });
        this.next.addEventListener('click', function () {
            self.page++; self.render();
        });
        this.size.addEventListener('change', function () {
            self.pageSize = parseInt(self.size.value, 10);
            self.page = 1;
            self.render();
        });
    };

    TableController.prototype.bindSorting = function () {
        var self = this;
        for (var i = 0; i < this.headers.length; i++) {
            (function (th, index) {
                th.title = 'Click to sort';
                th.tabIndex = 0;
                th.setAttribute('role', 'button');
                th.setAttribute('aria-sort', 'none');
                function activate() {
                    self.sortDirection = self.sortColumn === index && self.sortDirection === 'asc' ? 'desc' : 'asc';
                    self.sortColumn = index;
                    self.page = 1;
                    self.render();
                }
                th.addEventListener('click', activate);
                th.addEventListener('keydown', function (event) {
                    if (event.key === 'Enter' || event.key === ' ') {
                        event.preventDefault();
                        activate();
                    }
                });
            })(this.headers[i], i);
        }
    };

    TableController.prototype.filteredRows = function () {
        var selected = databaseFilter ? databaseFilter.value : '';
        if (!selected || this.databaseColumn < 0) { return this.rows.slice(); }
        var dbColumn = this.databaseColumn;
        return this.rows.filter(function (row) {
            return cellText(row, dbColumn).toLowerCase() === selected.toLowerCase();
        });
    };

    TableController.prototype.sortedRows = function (rows) {
        if (this.sortColumn === null) { return rows; }
        var index = this.sortColumn, direction = this.sortDirection;
        var isDate = true, isNumeric = true, seen = false;
        rows.forEach(function (row) {
            var text = cellText(row, index);
            if (isBlank(text)) { return; }
            seen = true;
            if (!DATE_RE.test(text)) { isDate = false; }
            if (!NUM_RE.test(text.replace(/,/g, ''))) { isNumeric = false; }
        });
        if (!seen) { isDate = false; isNumeric = false; }
        function key(row) {
            var text = cellText(row, index);
            if (isBlank(text)) { return null; }
            if (isDate) { return Date.parse(text.replace(' ', 'T')); }
            if (isNumeric) { return parseFloat(text.replace(/,/g, '')); }
            return text.toLowerCase();
        }
        var multiplier = direction === 'asc' ? 1 : -1;
        return rows.map(function (row, originalIndex) {
            return { row: row, key: key(row), originalIndex: originalIndex };
        }).sort(function (a, b) {
            if (a.key === null && b.key === null) { return a.originalIndex - b.originalIndex; }
            if (a.key === null) { return -1 * multiplier; }
            if (b.key === null) { return 1 * multiplier; }
            if (a.key < b.key) { return -1 * multiplier; }
            if (a.key > b.key) { return 1 * multiplier; }
            return a.originalIndex - b.originalIndex;
        }).map(function (item) { return item.row; });
    };

    TableController.prototype.render = function () {
        var self = this;
        var rows = this.sortedRows(this.filteredRows());
        this.rows.forEach(function (row) { row.style.display = 'none'; });
        for (var i = 0; i < this.headers.length; i++) {
            var active = i === this.sortColumn;
            this.headers[i].classList.toggle('sort-asc', active && this.sortDirection === 'asc');
            this.headers[i].classList.toggle('sort-desc', active && this.sortDirection === 'desc');
            this.headers[i].setAttribute('aria-sort', active ?
                (this.sortDirection === 'asc' ? 'ascending' : 'descending') : 'none');
        }
        var total = rows.length;
        var paginate = total > 50 && !this.printing;
        var pageCount = Math.max(1, Math.ceil(total / this.pageSize));
        this.page = Math.min(Math.max(1, this.page), pageCount);
        var start = paginate ? (this.page - 1) * this.pageSize : 0;
        var end = paginate ? Math.min(start + this.pageSize, total) : total;
        for (var r = start; r < end; r++) {
            this.tbody.appendChild(rows[r]);
            rows[r].style.display = '';
        }
        this.table.style.display = total === 0 ? 'none' : '';
        this.emptyState.hidden = !(total === 0 && this.databaseColumn >= 0 && databaseFilter && databaseFilter.value);
        this.controls.hidden = !paginate;
        this.status.textContent = 'Page ' + this.page + ' of ' + pageCount + ' \u00b7 ' + total + ' rows';
        this.previous.disabled = this.page <= 1;
        this.next.disabled = this.page >= pageCount;
        this.previous.setAttribute('aria-disabled', String(this.previous.disabled));
        this.next.setAttribute('aria-disabled', String(this.next.disabled));
    };

    // ----- Client-side Excel export (SpreadsheetML 2003; no external libraries) -----
    // Tables are snapshotted here, BEFORE the pagination controllers reorder rows,
    // so the export always contains every row of every section in original order,
    // regardless of the current sort, page, or database filter.
    var exportSheets = [];
    (function snapshotTablesForExport() {
        var usedNames = {};
        function toSheetName(raw) {
            var clean = raw.replace(/[\[\]:*?\/\\']/g, ' ').replace(/\s+/g, ' ').trim() || 'Sheet';
            if (clean.length > 31) { clean = clean.substring(0, 31).trim(); }
            var candidate = clean, suffix = 2;
            while (usedNames[candidate.toLowerCase()]) {
                var tail = '_' + suffix;
                candidate = clean.substring(0, Math.min(clean.length, 31 - tail.length)) + tail;
                suffix++;
            }
            usedNames[candidate.toLowerCase()] = true;
            return candidate;
        }
        document.querySelectorAll('.data-table').forEach(function (table) {
            if (!table.tHead || !table.tHead.rows.length || !table.tBodies.length) { return; }
            var title = table.id === 'allFindings' ? 'Findings Summary' : '';
            if (!title) {
                var section = table.closest('section');
                var heading = section ? section.querySelector('h2') : null;
                title = heading ? heading.textContent.trim() : (table.id || 'Sheet');
            }
            exportSheets.push({
                name: toSheetName(title),
                headers: Array.prototype.map.call(table.tHead.rows[0].cells, function (cell) {
                    return cell.textContent.trim();
                }),
                rows: Array.prototype.map.call(table.tBodies[0].rows, function (row) {
                    return Array.prototype.map.call(row.cells, function (cell) {
                        return cell.textContent.trim();
                    });
                })
            });
        });
    })();

    function xmlEscape(text) {
        return String(text)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
            .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');
    }
    var STRICT_NUM_RE = /^-?\d{1,15}(\.\d+)?$/;
    function buildWorkbookXml() {
        var parts = [];
        parts.push('<?xml version="1.0"?>');
        parts.push('<?mso-application progid="Excel.Sheet"?>');
        parts.push('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"' +
            ' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"' +
            ' xmlns:x="urn:schemas-microsoft-com:office:excel">');
        // Header style mirrors the report/Excel theme: light sky-blue fill, dark-blue bold text.
        parts.push('<Styles>' +
            '<Style ss:ID="hdr"><Font ss:Bold="1" ss:Color="#17243A"/>' +
            '<Interior ss:Color="#87CEFA" ss:Pattern="Solid"/></Style>' +
            '<Style ss:ID="cell"><Alignment ss:Vertical="Top"/></Style>' +
            '</Styles>');
        exportSheets.forEach(function (sheet) {
            parts.push('<Worksheet ss:Name="' + xmlEscape(sheet.name) + '"><Table>');
            parts.push('<Row>');
            sheet.headers.forEach(function (header) {
                parts.push('<Cell ss:StyleID="hdr"><Data ss:Type="String">' + xmlEscape(header) + '</Data></Cell>');
            });
            parts.push('</Row>');
            sheet.rows.forEach(function (row) {
                parts.push('<Row>');
                row.forEach(function (value) {
                    var numeric = value.replace(/,/g, '');
                    if (value !== '' && STRICT_NUM_RE.test(numeric)) {
                        parts.push('<Cell ss:StyleID="cell"><Data ss:Type="Number">' + numeric + '</Data></Cell>');
                    } else {
                        parts.push('<Cell ss:StyleID="cell"><Data ss:Type="String">' + xmlEscape(value) + '</Data></Cell>');
                    }
                });
                parts.push('</Row>');
            });
            parts.push('</Table>' +
                '<WorksheetOptions xmlns="urn:schemas-microsoft-com:office:excel">' +
                '<FreezePanes/><SplitHorizontal>1</SplitHorizontal>' +
                '<TopRowBottomPane>1</TopRowBottomPane><ActivePane>2</ActivePane>' +
                '</WorksheetOptions></Worksheet>');
        });
        parts.push('</Workbook>');
        return parts.join('');
    }
    var exportButton = document.getElementById('exportExcelButton');
    if (exportButton) {
        if (!exportSheets.length) { exportButton.disabled = true; }
        exportButton.addEventListener('click', function () {
            var blob = new Blob([buildWorkbookXml()], { type: 'application/vnd.ms-excel' });
            var url = URL.createObjectURL(blob);
            var anchor = document.createElement('a');
            anchor.href = url;
            anchor.download = '$ReportBaseName.xls';
            document.body.appendChild(anchor);
            anchor.click();
            document.body.removeChild(anchor);
            setTimeout(function () { URL.revokeObjectURL(url); }, 2000);
        });
    }

    document.querySelectorAll('.data-table').forEach(function (table) {
        if (table.tHead && table.tHead.rows.length && table.tBodies.length) {
            controllers.push(new TableController(table));
        }
    });
    if (databaseFilter) {
        databaseFilter.addEventListener('change', function () {
            controllers.forEach(function (controller) {
                if (controller.databaseColumn >= 0) {
                    controller.page = 1;
                    controller.render();
                }
            });
            filterIndicator.classList.toggle('active', databaseFilter.value !== '');
            filterIndicator.textContent = databaseFilter.value ?
                'Database filter active: ' + databaseFilter.value : 'Database filter inactive';
        });
    }
    window.addEventListener('beforeprint', function () {
        controllers.forEach(function (controller) {
            controller.printing = true;
            controller.render();
        });
    });
    window.addEventListener('afterprint', function () {
        controllers.forEach(function (controller) {
            controller.printing = false;
            controller.render();
        });
    });
})();
</script>
</body></html>
"@

$HtmlReport | Set-Content -LiteralPath $ReportFilePath -Encoding UTF8
Write-AssessmentLog -Severity INFO -Section 'HTML Report' -Message ("HTML report written to '{0}'." -f $ReportFilePath)

#endregion

#region ============================================================================
# OPTIONAL EXCEL EXPORT (ImportExcel module, no Microsoft Excel/COM required)
# =================================================================================

$ExcelReportPath = $null

function ConvertTo-ExportObject {
    # Normalizes rows to plain PSCustomObjects: DataRows are reduced to their query
    # columns and DBNull values become $null, so Excel cells stay clean.
    param([AllowNull()][object[]]$Data)

    foreach ($row in @($Data)) {
        if ($null -eq $row) { continue }
        $item = [ordered]@{}
        if ($row -is [System.Data.DataRow]) {
            foreach ($column in $row.Table.Columns) {
                $value = $row[$column]
                $item[$column.ColumnName] = if ($value -is [System.DBNull]) { $null } else { $value }
            }
        }
        else {
            foreach ($property in $row.PSObject.Properties) {
                $item[$property.Name] = if ($property.Value -is [System.DBNull]) { $null } else { $property.Value }
            }
        }
        [PSCustomObject]$item
    }
}

function Get-SafeWorksheetName {
    # Excel worksheet names: max 31 chars, no : \ / ? * [ ] ', unique per workbook.
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$UsedNames
    )

    $clean = ($Name -replace "[:\\/\?\*\[\]']", ' ') -replace '\s+', ' '
    $clean = $clean.Trim()
    if (-not $clean) { $clean = 'Sheet' }
    if ($clean.Length -gt 31) { $clean = $clean.Substring(0, 31).Trim() }
    $candidate = $clean
    $suffix = 2
    while ($UsedNames.ContainsKey($candidate.ToLowerInvariant())) {
        $tail = "_$suffix"
        $candidate = $clean.Substring(0, [Math]::Min($clean.Length, 31 - $tail.Length)) + $tail
        $suffix++
    }
    $UsedNames[$candidate.ToLowerInvariant()] = $true
    return $candidate
}

function Set-ExcelChartColors {
    # Best effort: EPPlus 4 (bundled with ImportExcel) does not expose series/point
    # fill colors, so inject DrawingML solidFill nodes into the chart XML. A failure
    # only means the chart keeps the default palette.
    param(
        [Parameter(Mandatory)][object]$Chart,
        [string[]]$PointColors,
        [string]$SeriesColor
    )

    try {
        $chartXml = $Chart.ChartXml
        $nsChart = 'http://schemas.openxmlformats.org/drawingml/2006/chart'
        $nsDraw = 'http://schemas.openxmlformats.org/drawingml/2006/main'
        $nsm = New-Object System.Xml.XmlNamespaceManager($chartXml.NameTable)
        $nsm.AddNamespace('c', $nsChart)
        $nsm.AddNamespace('a', $nsDraw)
        $series = $chartXml.SelectSingleNode('//c:ser', $nsm)
        if ($null -eq $series) { return }

        if ($SeriesColor) {
            $spPr = $chartXml.CreateElement('c', 'spPr', $nsChart)
            $fill = $chartXml.CreateElement('a', 'solidFill', $nsDraw)
            $color = $chartXml.CreateElement('a', 'srgbClr', $nsDraw)
            $color.SetAttribute('val', $SeriesColor.TrimStart('#'))
            [void]$fill.AppendChild($color)
            [void]$spPr.AppendChild($fill)
            $anchor = $series.SelectSingleNode('c:tx', $nsm)
            if ($null -eq $anchor) { $anchor = $series.SelectSingleNode('c:order', $nsm) }
            if ($anchor) { [void]$series.InsertAfter($spPr, $anchor) } else { [void]$series.PrependChild($spPr) }
        }

        if ($PointColors) {
            # Valid CT_DPt child order: idx, bubble3D, spPr. Data points must appear
            # before the c:cat/c:val nodes inside c:ser.
            $insertBefore = $series.SelectSingleNode('c:cat', $nsm)
            if ($null -eq $insertBefore) { $insertBefore = $series.SelectSingleNode('c:val', $nsm) }
            for ($pointIndex = 0; $pointIndex -lt $PointColors.Count; $pointIndex++) {
                $dPt = $chartXml.CreateElement('c', 'dPt', $nsChart)
                $idx = $chartXml.CreateElement('c', 'idx', $nsChart)
                $idx.SetAttribute('val', [string]$pointIndex)
                [void]$dPt.AppendChild($idx)
                $bubble = $chartXml.CreateElement('c', 'bubble3D', $nsChart)
                $bubble.SetAttribute('val', '0')
                [void]$dPt.AppendChild($bubble)
                $spPr = $chartXml.CreateElement('c', 'spPr', $nsChart)
                $fill = $chartXml.CreateElement('a', 'solidFill', $nsDraw)
                $color = $chartXml.CreateElement('a', 'srgbClr', $nsDraw)
                $color.SetAttribute('val', $PointColors[$pointIndex].TrimStart('#'))
                [void]$fill.AppendChild($color)
                [void]$spPr.AppendChild($fill)
                [void]$dPt.AppendChild($spPr)
                if ($insertBefore) { [void]$series.InsertBefore($dPt, $insertBefore) } else { [void]$series.AppendChild($dPt) }
            }
        }
    }
    catch {
        Write-Verbose ("Chart color styling skipped: {0}" -f $_.Exception.Message)
    }
}

if ($ExportExcel) {
    Write-Host 'Exporting Excel workbook...' -NoNewline
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Host 'SKIPPED' -ForegroundColor Yellow
        Write-AssessmentLog -Severity WARN -Section 'Excel Export' `
            -Message 'Skipped: ImportExcel module not installed (Install-Module ImportExcel -Scope CurrentUser). HTML report was still generated.'
        Write-Warning ("Excel export skipped: the ImportExcel module is not installed. " +
            "Run: Install-Module ImportExcel -Scope CurrentUser. " +
            "The HTML report was still generated at '{0}'." -f $ReportFilePath)
    }
    else {
        $excel = $null
        try {
            Import-Module ImportExcel -ErrorAction Stop
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

            $excelPath = [System.IO.Path]::ChangeExtension($ReportFilePath, 'xlsx')
            if (Test-Path -LiteralPath $excelPath) { Remove-Item -LiteralPath $excelPath -Force }

            # Light sky-blue theme.
            $skyBlue = [System.Drawing.ColorTranslator]::FromHtml('#87CEFA')
            $paleBlue = [System.Drawing.ColorTranslator]::FromHtml('#E6F4FD')
            $darkBlue = [System.Drawing.ColorTranslator]::FromHtml('#17243A')
            $criticalColor = [System.Drawing.ColorTranslator]::FromHtml('#B91C1C')
            $warningColor = [System.Drawing.ColorTranslator]::FromHtml('#B45309')
            $goodColor = [System.Drawing.ColorTranslator]::FromHtml('#15803D')
            $thinBorder = [OfficeOpenXml.Style.ExcelBorderStyle]::Thin

            $usedSheetNames = @{}
            [void](Get-SafeWorksheetName -Name 'Summary' -UsedNames $usedSheetNames)
            [void](Get-SafeWorksheetName -Name 'ChartData' -UsedNames $usedSheetNames)

            $excel = Open-ExcelPackage -Path $excelPath -Create
            $summarySheet = Add-Worksheet -ExcelPackage $excel -WorksheetName 'Summary'

            # ----- Summary: title and KPI block -----
            $summarySheet.Cells['A1'].Value = 'SQL Server DBA Assessment'
            Set-ExcelRange -Worksheet $summarySheet -Range 'A1:E1' -Merge -Bold -FontSize 18 `
                -FontColor $darkBlue -BackgroundColor $skyBlue -HorizontalAlignment Left
            $summarySheet.Row(1).Height = 30

            $kpiRows = @(
                @('Server', [string]$ServerIP),
                @('Generated', $ReportTimestamp.ToString('yyyy-MM-dd HH:mm:ss')),
                @('Lookback (days)', $DaysToAnalyze),
                @('Health Score', "$healthScore / 100"),
                @('Health Status', $healthLabel),
                @('Critical Findings', $CriticalIssues.Count),
                @('Warnings', $WarningIssues.Count),
                @('Info Notes', $InformationItems.Count),
                @('Collection Errors', $CollectionErrors.Count),
                @('Assessment Sections', $PopulatedSectionCount)
            )
            $rowIndex = 3
            foreach ($kpi in $kpiRows) {
                $summarySheet.Cells[$rowIndex, 1].Value = $kpi[0]
                $summarySheet.Cells[$rowIndex, 2].Value = $kpi[1]
                $rowIndex++
            }
            $kpiEndRow = $rowIndex - 1
            Set-ExcelRange -Worksheet $summarySheet -Range "A3:A$kpiEndRow" -Bold -FontColor $darkBlue -BackgroundColor $paleBlue
            $kpiRange = $summarySheet.Cells["A3:B$kpiEndRow"]
            foreach ($side in 'Top', 'Bottom', 'Left', 'Right') { $kpiRange.Style.Border.$side.Style = $thinBorder }
            $healthColor = switch ($healthClass) { 'good' { $goodColor } 'warn' { $warningColor } default { $criticalColor } }
            Set-ExcelRange -Worksheet $summarySheet -Range 'B6:B7' -Bold -FontColor $healthColor
            if ($CriticalIssues.Count -gt 0) { Set-ExcelRange -Worksheet $summarySheet -Range 'B8' -Bold -FontColor $criticalColor }
            if ($WarningIssues.Count -gt 0) { Set-ExcelRange -Worksheet $summarySheet -Range 'B9' -Bold -FontColor $warningColor }
            if ($CollectionErrors.Count -gt 0) { Set-ExcelRange -Worksheet $summarySheet -Range 'B11' -Bold -FontColor $criticalColor }
            $summarySheet.Column(1).Width = 22
            $summarySheet.Column(2).Width = 30

            # ----- Summary: prioritized findings table -----
            $findingsTitleRow = $kpiEndRow + 2
            $summarySheet.Cells[$findingsTitleRow, 1].Value = 'All Findings (Critical, then Warning, then Info)'
            Set-ExcelRange -Worksheet $summarySheet -Range "A${findingsTitleRow}:E${findingsTitleRow}" -Merge -Bold `
                -FontSize 13 -FontColor $darkBlue -BackgroundColor $skyBlue
            $findingRows = @(ConvertTo-ExportObject -Data $AllFindingsOrdered |
                Select-Object Severity, Category, Item, Detail, Recommendation)
            if ($findingRows.Count -gt 0) {
                $excel = $findingRows | Export-Excel -ExcelPackage $excel -WorksheetName 'Summary' `
                    -StartRow ($findingsTitleRow + 1) -TableName 'Findings' -TableStyle 'Medium2' -PassThru
                $summarySheet.Column(3).Width = 34
                $summarySheet.Column(4).Width = 70
                $summarySheet.Column(4).Style.WrapText = $true
                $summarySheet.Column(5).Width = 55
                $summarySheet.Column(5).Style.WrapText = $true
                $findingsRange = $summarySheet.Cells[($findingsTitleRow + 1), 1, ($findingsTitleRow + 1 + $findingRows.Count), 5]
                foreach ($side in 'Top', 'Bottom', 'Left', 'Right') { $findingsRange.Style.Border.$side.Style = $thinBorder }
            }
            else {
                $summarySheet.Cells[($findingsTitleRow + 1), 1].Value = 'No findings were recorded.'
            }

            # ----- ChartData sheet: stable, maintainable chart sources -----
            $chartSheet = Add-Worksheet -ExcelPackage $excel -WorksheetName 'ChartData'
            $chartSheet.Cells['A1'].Value = 'Severity'
            $chartSheet.Cells['B1'].Value = 'Count'
            $chartSheet.Cells['A2'].Value = 'Critical'; $chartSheet.Cells['B2'].Value = $CriticalIssues.Count
            $chartSheet.Cells['A3'].Value = 'Warning';  $chartSheet.Cells['B3'].Value = $WarningIssues.Count
            $chartSheet.Cells['A4'].Value = 'Info';     $chartSheet.Cells['B4'].Value = $InformationItems.Count

            # Written in ascending count order so the horizontal bar chart shows the
            # largest category at the top.
            $chartSheet.Cells['D1'].Value = 'Category'
            $chartSheet.Cells['E1'].Value = 'Count'
            $categoryForChart = @($CategoryGroups | Select-Object -First 12 | Sort-Object -Property Count)
            $rowIndex = 2
            foreach ($group in $categoryForChart) {
                $chartSheet.Cells[$rowIndex, 4].Value = $group.Name
                $chartSheet.Cells[$rowIndex, 5].Value = $group.Count
                $rowIndex++
            }
            $categoryEndRow = $rowIndex - 1

            $diskForChart = @($Disks | Where-Object { (Test-HasValue $_.Volume) -and (Test-HasNumericValue $_.FreePercent) })
            $chartSheet.Cells['G1'].Value = 'Volume'
            $chartSheet.Cells['H1'].Value = 'FreePercent'
            $rowIndex = 2
            foreach ($disk in $diskForChart) {
                $chartSheet.Cells[$rowIndex, 7].Value = [string]$disk.Volume
                $chartSheet.Cells[$rowIndex, 8].Value = [double]$disk.FreePercent
                $rowIndex++
            }
            $diskEndRow = $rowIndex - 1

            $waitsForChart = @($Waits | Where-Object { (Test-HasValue $_.WaitType) -and (Test-HasNumericValue $_.WaitPercent) } |
                Select-Object -First 10 | Sort-Object -Property { [double]$_.WaitPercent })
            $chartSheet.Cells['J1'].Value = 'WaitType'
            $chartSheet.Cells['K1'].Value = 'WaitPercent'
            $rowIndex = 2
            foreach ($wait in $waitsForChart) {
                $chartSheet.Cells[$rowIndex, 10].Value = [string]$wait.WaitType
                $chartSheet.Cells[$rowIndex, 11].Value = [double]$wait.WaitPercent
                $rowIndex++
            }
            $waitsEndRow = $rowIndex - 1
            Set-ExcelRange -Worksheet $chartSheet -Range 'A1:K1' -Bold -FontColor $darkBlue -BackgroundColor $paleBlue
            $chartSheet.Hidden = [OfficeOpenXml.eWorkSheetHidden]::Hidden

            # ----- Summary charts (only when backing data exists) -----
            if (($CriticalIssues.Count + $WarningIssues.Count + $InformationItems.Count) -gt 0) {
                $severityChart = Add-ExcelChart -Worksheet $summarySheet -Title 'Findings by Severity' `
                    -ChartType Doughnut -XRange 'ChartData!A2:A4' -YRange 'ChartData!B2:B4' `
                    -Row 1 -Column 6 -Width 360 -Height 250 -LegendPosition Right -PassThru
                Set-ExcelChartColors -Chart $severityChart -PointColors @('B91C1C', 'B45309', '2563EB')
            }
            if ($categoryForChart.Count -gt 0) {
                $categoryChart = Add-ExcelChart -Worksheet $summarySheet -Title 'Critical + Warning Findings by Category' `
                    -ChartType BarClustered -XRange "ChartData!D2:D$categoryEndRow" -YRange "ChartData!E2:E$categoryEndRow" `
                    -Row 1 -Column 12 -Width 420 -Height 250 -NoLegend -PassThru
                Set-ExcelChartColors -Chart $categoryChart -SeriesColor '17243A'
            }
            if ($diskForChart.Count -gt 0) {
                $diskChart = Add-ExcelChart -Worksheet $summarySheet -Title 'Disk Free % by Volume (warning below 15%)' `
                    -ChartType ColumnClustered -XRange "ChartData!G2:G$diskEndRow" -YRange "ChartData!H2:H$diskEndRow" `
                    -Row 15 -Column 6 -Width 360 -Height 250 -NoLegend -PassThru
                Set-ExcelChartColors -Chart $diskChart -SeriesColor '2563EB'
            }
            if ($waitsForChart.Count -gt 0) {
                $waitChart = Add-ExcelChart -Worksheet $summarySheet -Title 'Top Wait Types (% of non-idle waits)' `
                    -ChartType BarClustered -XRange "ChartData!J2:J$waitsEndRow" -YRange "ChartData!K2:K$waitsEndRow" `
                    -Row 15 -Column 12 -Width 420 -Height 250 -NoLegend -PassThru
                Set-ExcelChartColors -Chart $waitChart -SeriesColor '0369A1'
            }

            # ----- One sheet per evidence section -----
            foreach ($sectionName in $sectionOrder) {
                $rows = @(ConvertTo-ExportObject -Data $Sections[$sectionName])
                if ($rows.Count -eq 0) { continue }
                $sheetName = Get-SafeWorksheetName -Name $sectionName -UsedNames $usedSheetNames
                $tableName = 'tbl_' + ($sectionName -replace '\W', '_')
                $excel = $rows | Export-Excel -ExcelPackage $excel -WorksheetName $sheetName `
                    -StartRow 3 -TableName $tableName -TableStyle 'Medium2' -PassThru
                $sectionSheet = $excel.Workbook.Worksheets[$sheetName]
                $sectionSheet.Cells[1, 1].Value = $sectionName
                $lastColumn = $sectionSheet.Dimension.End.Column
                Set-ExcelRange -Worksheet $sectionSheet -Range ($sectionSheet.Cells[1, 1, 1, [Math]::Max($lastColumn, 4)].Address) `
                    -Merge -Bold -FontSize 13 -FontColor $darkBlue -BackgroundColor $skyBlue
                $sectionSheet.View.FreezePanes(4, 1)
                $sectionSheet.Cells[$sectionSheet.Dimension.Address].AutoFitColumns(10, 55)
                for ($columnIndex = 1; $columnIndex -le $lastColumn; $columnIndex++) {
                    if ($sectionSheet.Column($columnIndex).Width -ge 54.5) {
                        $sectionSheet.Column($columnIndex).Style.WrapText = $true
                    }
                }
                if ($sectionName -eq 'File IO Latency') {
                    $assessmentColumn = 0
                    for ($columnIndex = 1; $columnIndex -le $lastColumn; $columnIndex++) {
                        if ($sectionSheet.Cells[3, $columnIndex].Value -eq 'Assessment') {
                            $assessmentColumn = $columnIndex
                            break
                        }
                    }
                    if ($assessmentColumn -gt 0) {
                        for ($rowIndex = 4; $rowIndex -le $sectionSheet.Dimension.End.Row; $rowIndex++) {
                            $cell = $sectionSheet.Cells[$rowIndex, $assessmentColumn]
                            $verdict = [string]$cell.Value
                            $cell.Style.Font.Bold = $true
                            if ($verdict -like 'Good*') {
                                $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                                $cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml('#DCFCE7'))
                                $cell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#14532D'))
                            }
                            elseif ($verdict -like 'Marginal*') {
                                $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                                $cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FEF3C7'))
                                $cell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#92400E'))
                            }
                            elseif ($verdict -like 'Poor*') {
                                $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                                $cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FEE2E2'))
                                $cell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#991B1B'))
                            }
                        }
                    }
                }
                $dataRange = $sectionSheet.Cells[3, 1, $sectionSheet.Dimension.End.Row, $lastColumn]
                foreach ($side in 'Top', 'Bottom', 'Left', 'Right') { $dataRange.Style.Border.$side.Style = $thinBorder }
            }

            # ----- Collection Errors sheet -----
            $errorRows = @(ConvertTo-ExportObject -Data @($CollectionErrors))
            if ($errorRows.Count -gt 0) {
                $errorSheetName = Get-SafeWorksheetName -Name 'Collection Errors' -UsedNames $usedSheetNames
                $excel = $errorRows | Export-Excel -ExcelPackage $excel -WorksheetName $errorSheetName `
                    -StartRow 3 -TableName 'tbl_Collection_Errors' -TableStyle 'Medium2' -PassThru
                $errorSheet = $excel.Workbook.Worksheets[$errorSheetName]
                $errorSheet.Cells[1, 1].Value = 'Collection Errors'
                Set-ExcelRange -Worksheet $errorSheet -Range 'A1:B1' -Merge -Bold -FontSize 13 `
                    -FontColor $darkBlue -BackgroundColor $skyBlue
                $errorSheet.View.FreezePanes(4, 1)
                $errorSheet.Column(1).Width = 40
                $errorSheet.Column(2).Width = 90
                $errorSheet.Column(2).Style.WrapText = $true
            }

            Close-ExcelPackage $excel
            $excel = $null
            $ExcelReportPath = $excelPath
            Write-AssessmentLog -Severity INFO -Section 'Excel Export' -Message ("Excel workbook written to '{0}'." -f $excelPath)
            Write-Host 'DONE' -ForegroundColor Green
        }
        catch {
            Write-Host 'FAILED' -ForegroundColor Yellow
            Write-AssessmentLog -Severity ERROR -Section 'Excel Export' `
                -Message 'Excel export failed; HTML report was still generated.' -ErrorRecord $_
            Write-Warning ("Excel export failed: {0} The HTML report was still generated at '{1}'." -f $_.Exception.Message, $ReportFilePath)
            if ($excel) {
                try { Close-ExcelPackage $excel -NoSave } catch { Write-Verbose 'Excel package cleanup failed.' }
            }
        }
    }
}

#endregion

#region ============================================================================
# COMPLETION
# =================================================================================

Write-AssessmentLog -Severity INFO -Section 'Completion' -Message (
    "Assessment finished. Health={0}/100 ({1}); Critical={2}; Warning={3}; Info={4}; CollectionErrors={5}; Excel='{6}'." -f `
        $healthScore, $healthLabel, $CriticalIssues.Count, $WarningIssues.Count, $InformationItems.Count,
        $CollectionErrors.Count, $(if ($ExcelReportPath) { $ExcelReportPath } else { 'not exported' }))

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
Write-Host ' Assessment completed' -ForegroundColor Green
Write-Host " Report: $ReportFilePath" -ForegroundColor Cyan
if ($ExcelReportPath) { Write-Host " Excel:  $ExcelReportPath" -ForegroundColor Cyan }
Write-Host " Log:    $LogFilePath" -ForegroundColor Cyan
Write-Host " Health: $healthScore/100 ($healthLabel)" -ForegroundColor Cyan
Write-Host " Critical: $($CriticalIssues.Count), Warnings: $($WarningIssues.Count), Collection errors: $($CollectionErrors.Count)" -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Green

if ($OpenReport) { Invoke-Item -LiteralPath $ReportFilePath }

[PSCustomObject]@{
    Server           = $ServerIP
    ReportPath       = $ReportFilePath
    ExcelReportPath  = $ExcelReportPath
    LogFilePath      = $LogFilePath
    HealthScore      = $healthScore
    CriticalIssues   = $CriticalIssues.Count
    WarningIssues    = $WarningIssues.Count
    CollectionErrors = $CollectionErrors.Count
}

#endregion
