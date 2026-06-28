<#
.SYNOPSIS
    SQL Optima DBA Assessment Framework - Main entry point.

.DESCRIPTION
    Connects to a SQL Server instance, runs health checks and diagnostic sections,
    and generates an HTML report with findings, severity scores, and recommendations.

    This is the primary command for running assessments. It supports Quick, Standard,
    and Deep profiles for different use cases.

.PARAMETER SqlInstance
    SQL Server instance name (required).

.PARAMETER Profile
    Assessment profile: Quick (30-90s), Standard (3-8min), Deep (10-30+min).
    Default: Quick.

.PARAMETER OutputPath
    Directory for the HTML report. Default: ..\output

.PARAMETER DatabaseList
    Comma-separated list of databases to assess. NULL = all user databases.

.PARAMETER BackupHoursSLA
    Backup SLA in hours. Default: 24.

.PARAMETER ConfigPath
    Path to custom assessment.config.json.

.PARAMETER Credential
    PSCredential for SQL authentication (Windows auth used if not specified).

.PARAMETER Persist
    Save results to DBARepository history tables.

.PARAMETER OutputJson
    Also export results as JSON alongside HTML.

.EXAMPLE
    .\Invoke-SqlOptimaAssessment.ps1 -SqlInstance PROD-SQL01 -Profile Quick

.EXAMPLE
    .\Invoke-SqlOptimaAssessment.ps1 -SqlInstance PROD-SQL01 -Profile Standard -OutputPath C:\Reports

.EXAMPLE
    .\Invoke-SqlOptimaAssessment.ps1 -SqlInstance PROD-SQL01 -DatabaseList 'SalesDB,HRDB'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SqlInstance,

    [ValidateSet('Quick', 'Standard', 'Deep')]
    [string]$Profile = 'Quick',

    [string]$OutputPath = (Join-Path (Join-Path $PSScriptRoot '..') 'output'),

    [string]$DatabaseList,

    [int]$BackupHoursSLA = 24,

    [string]$ConfigPath,

    [PSCredential]$Credential,

    [switch]$Persist,

    [switch]$OutputJson
)

#Requires -Modules dbatools, PSWriteHTML
#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot

# Load private functions
. (Join-Path (Join-Path $scriptRoot 'Private') 'Get-AssessmentConfig.ps1')
. (Join-Path (Join-Path $scriptRoot 'Private') 'Invoke-SectionCollector.ps1')
. (Join-Path (Join-Path $scriptRoot 'Private') 'Export-AssessmentHtml.ps1')

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "  SQL Optima DBA Assessment Framework" -ForegroundColor Cyan
Write-Host "  Server: $SqlInstance" -ForegroundColor Cyan
Write-Host "  Profile: $Profile" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

# ── Load Configuration ──────────────────────────────────────────────────────
$config = Get-AssessmentConfig -ConfigPath $ConfigPath -Profile $Profile
if ($DatabaseList) { $config.DatabaseList = $DatabaseList }
if ($BackupHoursSLA) { $config.BackupHoursSLA = $BackupHoursSLA }

Write-Host "`n[Config] Profile=$($config.Profile), BackupSLA=$($config.BackupHoursSLA)h" -ForegroundColor Yellow

# ── Connect to Instance ─────────────────────────────────────────────────────
Write-Host "`n[Connect] Connecting to $SqlInstance..." -ForegroundColor Green

try {
    $connectParams = @{ SqlInstance = $SqlInstance; TrustServerCertificate = $true }
    if ($Credential) { $connectParams.Credential = $Credential }
    $server = Connect-DbaInstance @connectParams
    Write-Host "  Connected: $($server.Edition) v$($server.VersionString)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to $SqlInstance : $_"
    exit 1
}

# ── Section A: Server Inventory ──────────────────────────────────────────────
Write-Host "`n[Section A] Collecting server inventory..." -ForegroundColor Green

$inventory = @{}
try {
    $inventory.SQLVersion = $server.VersionString
    $inventory.Edition = $server.Edition
    $inventory.ServerName = $server.Name

    $invResult = Invoke-DbaQuery -SqlInstance $server -Database 'master' -Query "
        SELECT SERVERPROPERTY('ProductLevel') AS ProductLevel,
               SERVERPROPERTY('Edition') AS Edition;
    "
    if ($invResult) {
        $inventory.ProductLevel = $invResult.ProductLevel
    }

    Write-Host "  Inventory collected: $($inventory.Edition) v$($inventory.SQLVersion)" -ForegroundColor Green
}
catch {
    Write-Warning "Inventory collection partial: $_"
}

# ── Section B: Health Check (T-SQL) ─────────────────────────────────────────
Write-Host "`n[Section B] Running health check..." -ForegroundColor Green

$deepDive = if ($config.IncludeDeepDive) { 1 } else { 0 }
$hcQuery = "EXEC dbo.sp_DBA_HealthCheck @DeepDive = $deepDive, @BackupHoursSLA = $($config.BackupHoursSLA)"
if ($config.DatabaseList) {
    $hcQuery += ", @DatabaseList = N'$($config.DatabaseList)'"
}

$healthCheck = Invoke-SectionCollector -SqlInstance $server `
    -DatabaseName 'DBARepository' `
    -Query $hcQuery `
    -SectionName 'HealthCheck'

# Parse dashboard and findings from result sets
$dashboard = @{}
$findings = @()

if ($healthCheck.DataSet -and $healthCheck.DataSet.Tables.Count -ge 2) {
    $dashTable = $healthCheck.DataSet.Tables[1]
    if ($dashTable.Rows.Count -gt 0) {
        $dashRow = $dashTable.Rows[0]
        $dashboard = @{
            SQL_CPU_Pct        = $dashRow.SQL_CPU_Pct
            Signal_Wait_Pct    = $dashRow.Signal_Wait_Pct
            PLE_Seconds        = $dashRow.Min_PLE_s
            Total_Memory_GB    = [math]::Round($dashRow.Total_Mem_MB / 1024, 2)
            Instance_Start_Time = $dashRow.Instance_Start_Time
            Health_Score       = $dashRow.Health_Score
        }
    }

    $findTable = $healthCheck.DataSet.Tables[0]
    if ($findTable.Rows.Count -gt 0) {
        $findings = $findTable.Rows | ForEach-Object {
            [PSCustomObject]@{
                CheckId        = $_.CheckId
                Severity       = $_.Status
                Area           = $_.Area
                Finding        = $_.Finding
                Impact         = $_.Impact
                Recommendation = $_.Recommendation
                NextStepCommand = $_.NextStepCommand
            }
        }
    }
}

# ── Section C: Waits (if Standard/Deep) ─────────────────────────────────────
$sectionResults = @()

if ($config.Profile -ne 'Quick' -and $config.Sections.Waits) {
    Write-Host "[Section C] Collecting wait statistics..." -ForegroundColor Green

    $waitQuery = @"
SELECT TOP (20)
    w.wait_type,
    w.wait_time_ms / 1000.0 AS wait_time_s,
    w.signal_wait_time_ms / 1000.0 AS signal_wait_s,
    CAST(w.wait_time_ms * 100.0 / NULLIF(SUM(w.wait_time_ms) OVER(), 0) AS DECIMAL(5,2)) AS pct_of_top20,
    CASE
        WHEN w.wait_type LIKE 'LCK%' THEN 'Blocking'
        WHEN w.wait_type LIKE 'PAGEIOLATCH%' THEN 'Disk I/O'
        WHEN w.wait_type LIKE 'PAGELATCH%' THEN 'TempDB'
        WHEN w.wait_type LIKE 'CXPACKET%' THEN 'Parallelism'
        WHEN w.wait_type LIKE 'RESOURCE_SEMAPHORE%' THEN 'Memory'
        WHEN w.wait_type LIKE 'SOS_SCHEDULER_YIELD%' THEN 'CPU'
        WHEN w.wait_type LIKE 'ASYNC_NETWORK_IO' THEN 'Client/Network'
        WHEN w.wait_type LIKE 'WRITELOG%' THEN 'Log I/O'
        WHEN w.wait_type LIKE 'HADR_SYNC_COMMIT%' THEN 'AG Sync'
        ELSE 'Other'
    END AS category
FROM sys.dm_os_wait_stats w
WHERE w.wait_type NOT IN (SELECT wait_type FROM DBARepository.dbo.fn_DBA_ExcludedWaitTypes())
  AND w.wait_time_ms > 0
ORDER BY w.wait_time_ms DESC;
"@

    $waits = Invoke-SectionCollector -SqlInstance $server `
        -DatabaseName 'master' `
        -Query $waitQuery `
        -SectionName 'WaitStatistics'

    $sectionResults += $waits
}

# ── Section D: Backup Status (if Standard/Deep) ─────────────────────────────
if ($config.Profile -ne 'Quick' -and $config.Sections.Backup) {
    Write-Host "[Section D] Checking backup status..." -ForegroundColor Green

    $backupQuery = @"
SELECT
    d.name AS database_name,
    d.recovery_model_desc,
    MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END) AS last_full_backup,
    MAX(CASE WHEN bs.type = 'I' THEN bs.backup_finish_date END) AS last_diff_backup,
    MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END) AS last_log_backup,
    DATEDIFF(HOUR, MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END), GETDATE()) AS hours_since_full
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset bs ON bs.database_name = d.name AND bs.is_copy_only = 0
WHERE d.database_id > 4 AND d.state = 0
GROUP BY d.name, d.recovery_model_desc
ORDER BY hours_since_full DESC;
"@

    $backups = Invoke-SectionCollector -SqlInstance $server `
        -DatabaseName 'msdb' `
        -Query $backupQuery `
        -SectionName 'BackupStatus'

    $sectionResults += $backups
}

# ── Section E: Configuration Audit (if Standard/Deep) ───────────────────────
if ($config.Profile -ne 'Quick' -and $config.Sections.Config) {
    Write-Host "[Section E] Auditing configuration..." -ForegroundColor Green

    $configQuery = @"
SELECT
    name AS config_name,
    value_in_use,
    value AS configured_value,
    CASE
        WHEN name = 'max degree of parallelism' AND value_in_use = 0 THEN 'WARNING: Unlimited parallelism'
        WHEN name = 'cost threshold for parallelism' AND value_in_use < 25 THEN 'WARNING: Low CTFP'
        WHEN name = 'max server memory (MB)' AND value_in_use >= 2147483647 THEN 'WARNING: Not configured'
        WHEN name = 'backup compression default' AND value_in_use = 0 THEN 'INFO: Compression disabled'
        WHEN name = 'remote admin connections' AND value_in_use = 0 THEN 'INFO: DAC disabled'
        ELSE 'OK'
    END AS status
FROM sys.configurations
WHERE name IN (
    'max degree of parallelism',
    'cost threshold for parallelism',
    'max server memory (MB)',
    'min server memory (MB)',
    'backup compression default',
    'remote admin connections',
    'clr enabled',
    'xp_cmdshell',
    'Database Mail XPs',
    'Agent XPs'
)
ORDER BY name;
"@

    $configs = Invoke-SectionCollector -SqlInstance $server `
        -DatabaseName 'master' `
        -Query $configQuery `
        -SectionName 'ConfigurationAudit'

    $sectionResults += $configs
}

# ── Section F: Security (if Standard/Deep) ──────────────────────────────────
if ($config.Profile -ne 'Quick' -and $config.Sections.Security) {
    Write-Host "[Section F] Auditing security..." -ForegroundColor Green

    $securityQuery = @"
-- Sysadmin members
SELECT
    p.name AS login_name,
    p.type_desc,
    p.create_date,
    p.is_disabled,
    'sysadmin' AS role_name
FROM sys.server_role_members rm
JOIN sys.server_principals p ON p.principal_id = rm.member_principal_id
WHERE rm.role_principal_id = SUSER_SID('sysadmin')
ORDER BY p.name;
"@

    $security = Invoke-SectionCollector -SqlInstance $server `
        -DatabaseName 'master' `
        -Query $securityQuery `
        -SectionName 'SecurityAudit'

    $sectionResults += $security
}

# ── Section G: Query Store (if enabled) ─────────────────────────────────────
if ($config.Sections.QueryStore -and $config.Profile -ne 'Quick') {
    Write-Host "[Section G] Checking Query Store regressions..." -ForegroundColor Green

    $qsQuery = @"
IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id > 4 AND state = 0
           AND is_query_store_on = 1)
BEGIN
    EXEC DBARepository.dbo.sp_DBA_QueryStoreRegressions
        @RegressionPctThreshold = $($config.RegressionPctThreshold),
        @TopPerDatabase = 5;
END
ELSE
BEGIN
    SELECT 'No Query Store enabled databases' AS Message;
END
"@

    $qs = Invoke-SectionCollector -SqlInstance $server `
        -DatabaseName 'master' `
        -Query $qsQuery `
        -SectionName 'QueryStoreRegressions'

    $sectionResults += $qs
}

# ── Generate HTML Report ────────────────────────────────────────────────────
Write-Host "`n[Report] Generating HTML report..." -ForegroundColor Green

$healthScore = if ($dashboard.ContainsKey('Health_Score')) { $dashboard.Health_Score } else { 0 }
$trafficLight = if ($healthScore -ge 85) { 'GREEN' } elseif ($healthScore -ge 70) { 'YELLOW' } else { 'RED' }

$htmlPath = Export-AssessmentHtml -ServerName $SqlInstance `
    -HealthScore $healthScore `
    -TrafficLight $trafficLight `
    -Dashboard $dashboard `
    -Findings $findings `
    -Sections $sectionResults `
    -OutputPath $OutputPath

Write-Host "  HTML report: $htmlPath" -ForegroundColor Green

# ── Optional JSON Export ─────────────────────────────────────────────────────
if ($OutputJson) {
    $jsonPath = $htmlPath -replace '\.html$', '.json'
    $jsonOutput = @{
        ServerName = $SqlInstance
        Profile = $config.Profile
        GeneratedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Dashboard = $dashboard
        Findings = $findings
        Sections = $sectionResults | ForEach-Object {
            @{
                Section = $_.Section
                CollectedUtc = $_.CollectedUtc
                RowCount = $_.Rows.Count
                Error = $_.Error
            }
        }
    }
    $jsonOutput | ConvertTo-Json -Depth 10 | Set-Content $jsonPath -Encoding UTF8
    Write-Host "  JSON export: $jsonPath" -ForegroundColor Green
}

# ── Persist to Repository (if enabled) ──────────────────────────────────────
if ($Persist -and $config.PersistToRepository) {
    Write-Host "`n[Persist] Saving to DBARepository..." -ForegroundColor Green

    $runId = Invoke-DbaQuery -SqlInstance $server `
        -Database 'DBARepository' `
        -Query "INSERT INTO dba.AssessmentRun (ServerName, Profile, HealthScore, SqlVersion)
                VALUES ('$($SqlInstance -replace "'","''")', '$Profile', $healthScore, '$($inventory.SQLVersion)');
                SELECT SCOPE_IDENTITY();" `
        -As Scalar

    foreach ($f in $findings) {
        Invoke-DbaQuery -SqlInstance $server `
            -Database 'DBARepository' `
            -Query "INSERT INTO dba.AssessmentFinding (RunId, CheckId, Severity, Area, Finding, Impact, Recommendation, NextStepCommand)
                    VALUES ($runId, $($f.CheckId), '$($f.Severity)', '$($f.Area)', '$($f.Finding -replace "'","''")', '$($f.Impact -replace "'","''")', '$($f.Recommendation -replace "'","''")', '$($f.NextStepCommand -replace "'","''")')"
    }

    Write-Host "  Run #$runId persisted." -ForegroundColor Green
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "  Assessment Complete" -ForegroundColor Cyan
Write-Host "  Server: $SqlInstance" -ForegroundColor Cyan
Write-Host "  Profile: $Profile" -ForegroundColor Cyan
Write-Host "  Health Score: $healthScore / 100 ($trafficLight)" -ForegroundColor $(switch ($trafficLight) {
    'GREEN' { 'Green' }
    'YELLOW' { 'Yellow' }
    'RED' { 'Red' }
    default { 'White' }
})
Write-Host "  Findings: $($findings.Count) total" -ForegroundColor Cyan
Write-Host "  Report: $htmlPath" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
