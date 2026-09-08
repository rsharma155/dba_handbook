<#
.SYNOPSIS
    Comprehensive DBA Assessment Report using dbatools
.DESCRIPTION
    Generates a detailed health assessment report for SQL Server instances
    covering all critical DBA areas with HTML output.
.PARAMETER ServerInstance
    SQL Server instance name or IP address
.PARAMETER Credential
    SQL Server login credential (typically SA)
.PARAMETER OutputPath
    Path where the HTML report will be saved
.PARAMETER DaysToAnalyze
    Number of days to analyze for historical data (default: 7)
.EXAMPLE
    .\Invoke-DbaAssessmentReport.ps1 -ServerInstance "192.168.1.100" -Credential (Get-Credential) -OutputPath "C:\Reports"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "SQL Server instance name or IP")]
    [string]$ServerInstance,
    
    [Parameter(Mandatory = $true, HelpMessage = "SQL Server credential")]
    [System.Management.Automation.PSCredential]$Credential,
    
    [Parameter(Mandatory = $false, HelpMessage = "Output directory for reports")]
    [string]$OutputPath = "$env:USERPROFILE\Desktop\DBA_Reports",
    
    [Parameter(Mandatory = $false, HelpMessage = "Days to analyze for historical data")]
    [int]$DaysToAnalyze = 7
)

#region ============================================================================
# INITIALIZATION AND PREREQUISITES
# =================================================================================

# Ensure dbatools module is available
if (-not (Get-Module -Name dbatools -ListAvailable)) {
    try {
        Write-Host "Installing dbatools module..." -ForegroundColor Yellow
        Install-Module -Name dbatools -Force -AllowClobber -Scope CurrentUser
    }
    catch {
        Write-Error "Failed to install dbatools module. Please install manually: Install-Module dbatools"
        exit 1
    }
}

Import-Module dbatools -Force

# Create output directory if it doesn't exist
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

# Generate timestamp for report
 $ReportTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
 $ReportFileName = "DBA_Assessment_$(($ServerInstance -replace '[\\:\/\*?"<>|]', '_'))_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
 $ReportFilePath = Join-Path -Path $OutputPath -ChildPath $ReportFileName

# Initialize result collections
 $CriticalIssues = [System.Collections.Generic.List[PSObject]]::new()
 $WarningIssues = [System.Collections.Generic.List[PSObject]]::new()
 $InformationalItems = [System.Collections.Generic.List[PSObject]]::new()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DBA Assessment Report Generator" -ForegroundColor Cyan
Write-Host " Target: $ServerInstance" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

#endregion

#region ============================================================================
# CONNECTION TEST
# =================================================================================

Write-Host "Testing connection to $ServerInstance..." -NoNewline
try {
    $TestConnection = Test-DbaConnection -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    if ($TestConnection.Connected) {
        Write-Host "SUCCESS" -ForegroundColor Green
    }
    else {
        Write-Host "FAILED" -ForegroundColor Red
        throw "Connection test returned false"
    }
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    Write-Error "Cannot connect to $ServerInstance. Please verify the server name, port, and credentials."
    exit 1
}

#endregion

#region ============================================================================
# DATA COLLECTION - SERVER/INSTANCE INVENTORY
# =================================================================================

Write-Host "Collecting server/instance inventory..." -NoNewline
try {
    $ServerInfo = Get-DbaSqlInstanceProperty -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    $InstanceDetail = Get-DbaInstanceProperty -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    $SpInfo = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query "SELECT SERVERPROPERTY('ServerName') AS ServerName, SERVERPROPERTY('ProductVersion') AS ProductVersion, SERVERPROPERTY('Edition') AS Edition, SERVERPROPERTY('ProductLevel') AS ProductLevel, SERVERPROPERTY('ProductUpdateLevel') AS ProductUpdateLevel, SERVERPROPERTY('EditionID') AS EditionID" -ErrorAction Stop
    
    $BuildNumber = $SpInfo.ProductVersion
    $MajorVersion = [int]($BuildNumber -split '\.')[0]
    
    # Get latest available build for version comparison
    try {
        $LatestBuilds = Get-DbaBuild -MajorVersion $MajorVersion -ErrorAction SilentlyContinue
        $LatestBuild = $LatestBuilds | Select-Object -First 1
        $IsLatestBuild = if ($LatestBuild) { $BuildNumber -ge $LatestBuild.Build } else { $null }
        $BuildLag = if ($LatestBuild) { $LatestBuild.Build } else { "Unknown" }
    }
    catch {
        $IsLatestBuild = $null
        $BuildLag = "Unknown"
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $ServerInfo = $null
    $SpInfo = [PSCustomObject]@{ ServerName = $ServerInstance; ProductVersion = "N/A"; Edition = "N/A"; ProductLevel = "N/A"; ProductUpdateLevel = "N/A" }
}

#endregion

#region ============================================================================
# DATA COLLECTION - SERVICE STATUS AND UPTIME
# =================================================================================

Write-Host "Collecting service status and uptime..." -NoNewline
try {
    $ServiceStatus = Get-DbaService -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    $SqlService = $ServiceStatus | Where-Object { $_.ServiceType -eq 'Engine' } | Select-Object -First 1
    $AgentService = $ServiceStatus | Where-Object { $_.ServiceType -eq 'Agent' } | Select-Object -First 1
    
    # Get uptime using dbatools
    $UptimeInfo = Get-DbaUptime -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    $CurrentUptime = $UptimeInfo.SinceLastRestart
    $LastRestart = $UptimeInfo.LastRestart
    
    # Check for excessive uptime (over 30 days)
    if ($CurrentUptime.TotalDays -gt 30) {
        $CriticalIssues.Add([PSCustomObject]@{
            Category = "Uptime"
            Item = "SQL Server Service Uptime"
            Detail = "Server has been running for $($CurrentUptime.Days) days without restart. Consider scheduled restart for patch application."
            Severity = "Warning"
        })
    }
    
    # Check SQL Agent status
    if ($AgentService -and $AgentService.State -ne 'Running') {
        $CriticalIssues.Add([PSCustomObject]@{
            Category = "Service"
            Item = "SQL Server Agent"
            Detail = "SQL Agent is not running. Jobs are not executing."
            Severity = "Critical"
        })
    }
    
    # Check SQL Server service status
    if ($SqlService -and $SqlService.State -ne 'Running') {
        $CriticalIssues.Add([PSCustomObject]@{
            Category = "Service"
            Item = "SQL Server Database Engine"
            Detail = "SQL Server service is not running."
            Severity = "Critical"
        })
    }
    
    # Check startup type
    if ($SqlService -and $SqlService.StartMode -ne 'Automatic') {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Service"
            Item = "SQL Server Startup Type"
            Detail = "SQL Server startup type is '$($SqlService.StartMode)'. Recommended: Automatic."
            Severity = "Warning"
        })
    }
    
    if ($AgentService -and $AgentService.StartMode -ne 'Automatic') {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Service"
            Item = "SQL Agent Startup Type"
            Detail = "SQL Agent startup type is '$($AgentService.StartMode)'. Recommended: Automatic."
            Severity = "Warning"
        })
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $ServiceStatus = $null
    $UptimeInfo = [PSCustomObject]@{ SinceLastRestart = [TimeSpan]::Zero; LastRestart = "N/A" }
}

#endregion

#region ============================================================================
# DATA COLLECTION - DATABASE INVENTORY
# =================================================================================

Write-Host "Collecting database inventory..." -NoNewline
try {
    $Databases = Get-DbaDatabase -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop | 
        Where-Object { $_.Name -notin ('master', 'msdb', 'model', 'tempdb') -or $_.Name -eq 'tempdb' }
    
    $UserDatabases = $Databases | Where-Object { $_.Name -notin ('master', 'msdb', 'model') }
    $SystemDatabases = $Databases | Where-Object { $_.Name -in ('master', 'msdb', 'model') }
    
    # Check database states
    foreach ($db in $Databases) {
        if ($db.Status -ne 'Normal' -and $db.Status -ne 'Online') {
            $CriticalIssues.Add([PSCustomObject]@{
                Category = "Database"
                Item = $db.Name
                Detail = "Database is in '$($db.Status)' state."
                Severity = "Critical"
            })
        }
        
        # Check for offline databases
        if ($db.IsOffline) {
            $CriticalIssues.Add([PSCustomObject]@{
                Category = "Database"
                Item = $db.Name
                Detail = "Database is offline."
                Severity = "Critical"
            })
        }
        
        # Check recovery model for user databases
        if ($db.Name -notin ('master', 'msdb', 'model', 'tempdb')) {
            if ($db.RecoveryModel -eq 'Simple' -and $db.CompatibilityLevel -ge 100) {
                $WarningIssues.Add([PSCustomObject]@{
                    Category = "Database Configuration"
                    Item = $db.Name
                    Detail = "Database using Simple recovery model. Point-in-time recovery not possible."
                    Severity = "Warning"
                })
            }
        }
        
        # Check for snapshot databases
        if ($db.IsDatabaseSnapshot) {
            $InformationalItems.Add([PSCustomObject]@{
                Category = "Database"
                Item = $db.Name
                Detail = "Database snapshot detected."
                Severity = "Info"
            })
        }
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $Databases = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - BACKUP STATUS
# =================================================================================

Write-Host "Collecting backup status..." -NoNewline
try {
    $BackupHistory = Get-DbaDbBackupHistory -SqlInstance $ServerInstance -SqlCredential $Credential -Last -ErrorAction Stop
    $BackupSummary = Get-DbaDbBackupHistory -SqlInstance $ServerInstance -SqlCredential $Credential -Last -ErrorAction Stop |
        Select-Object Database, Type, LastBackup, Duration, TotalSize, Path, DeviceType
    
    # Check for databases without recent backups
    foreach ($db in $UserDatabases) {
        $FullBackup = $BackupHistory | Where-Object { $_.Database -eq $db.Name -and $_.Type -eq 'Full' } | Select-Object -First 1
        $DiffBackup = $BackupHistory | Where-Object { $_.Database -eq $db.Name -and $_.Type -eq 'Differential' } | Select-Object -First 1
        $LogBackup = $BackupHistory | Where-Object { $_.Database -eq $db.Name -and $_.Type -eq 'Log' } | Select-Object -First 1
        
        # Full backup check
        if (-not $FullBackup -or ($FullBackup.LastBackup -and (Get-Date) - $FullBackup.LastBackup -gt [TimeSpan]::FromDays(7))) {
            $lastBackupDate = if ($FullBackup) { $FullBackup.LastBackup } else { "Never" }
            $CriticalIssues.Add([PSCustomObject]@{
                Category = "Backup"
                Item = $db.Name
                Detail = "No full backup in last 7 days. Last full backup: $lastBackupDate"
                Severity = "Critical"
            })
        }
        elseif ($FullBackup.LastBackup -and (Get-Date) - $FullBackup.LastBackup -gt [TimeSpan]::FromDays(3)) {
            $WarningIssues.Add([PSCustomObject]@{
                Category = "Backup"
                Item = $db.Name
                Detail = "Full backup is $([math]::Round(((Get-Date) - $FullBackup.LastBackup).TotalHours)) hours old."
                Severity = "Warning"
            })
        }
        
        # Log backup check for Full/Bulk-Logged recovery
        if ($db.RecoveryModel -ne 'Simple') {
            if (-not $LogBackup) {
                $CriticalIssues.Add([PSCustomObject]@{
                    Category = "Backup"
                    Item = $db.Name
                    Detail = "Database in $($db.RecoveryModel) recovery model but no log backups found."
                    Severity = "Critical"
                })
            }
            elseif ($LogBackup.LastBackup -and (Get-Date) - $LogBackup.LastBackup -gt [TimeSpan]::FromMinutes(30)) {
                $WarningIssues.Add([PSCustomObject]@{
                    Category = "Backup"
                    Item = $db.Name
                    Detail = "Log backup is $([math]::Round(((Get-Date) - $LogBackup.LastBackup).TotalMinutes)) minutes old. Risk of log growth."
                    Severity = "Warning"
                })
            }
        }
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $BackupHistory = @()
    $BackupSummary = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - SQL AGENT JOBS
# =================================================================================

Write-Host "Collecting SQL Agent job status..." -NoNewline
try {
    $AgentJobs = Get-DbaAgentJob -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    $JobHistory = Get-DbaAgentJobHistory -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    
    # Check for failed jobs
    $FailedJobs = $AgentJobs | Where-Object { $_.LastRunStatus -eq 'Failed' }
    foreach ($job in $FailedJobs) {
        $CriticalIssues.Add([PSCustomObject]@{
            Category = "Agent Job"
            Item = $job.Name
            Detail = "Job last run failed on $($job.LastRunDate). Category: $($job.Category)"
            Severity = "Critical"
        })
    }
    
    # Check for disabled jobs that should be enabled
    $DisabledJobs = $AgentJobs | Where-Object { $_.IsEnabled -eq $false }
    foreach ($job in $DisabledJobs) {
        $InformationalItems.Add([PSCustomObject]@{
            Category = "Agent Job"
            Item = $job.Name
            Detail = "Job is disabled."
            Severity = "Info"
        })
    }
    
    # Check for jobs without notification
    $JobsWithoutNotification = $AgentJobs | Where-Object { $_.NotifyLevelEmail -eq 0 -and $_.NotifyLevelPage -eq 0 -and $_.NotifyLevelNetSend -eq 0 }
    if ($JobsWithoutNotification.Count -gt 0) {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Agent Job"
            Item = "Notification Setup"
            Detail = "$($JobsWithoutNotification.Count) job(s) have no failure notifications configured."
            Severity = "Warning"
        })
    }
    
    # Get recent job execution details
    $RecentJobExecutions = $JobHistory | Where-Object { $_.RunDate -gt (Get-Date).AddDays(-$DaysToAnalyze) } |
        Sort-Object RunDate -Descending | Select-Object -First 50
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "PARTIAL" -ForegroundColor Yellow
    $AgentJobs = @()
    $JobHistory = @()
    $RecentJobExecutions = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - DISK SPACE
# =================================================================================

Write-Host "Collecting disk space information..." -NoNewline
try {
    $DiskSpace = Get-DbaDiskSpace -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    
    # Check for low disk space
    foreach ($disk in $DiskSpace) {
        $PercentFree = [math]::Round(($disk.FreeSpace / $disk.TotalSize) * 100, 2)
        
        if ($PercentFree -lt 5) {
            $CriticalIssues.Add([PSCustomObject]@{
                Category = "Disk Space"
                Item = $disk.Name
                Detail = "CRITICAL: Only $PercentFree% free ($([math]::Round($disk.FreeSpace/1GB, 2)) GB remaining) on drive $($disk.Name)."
                Severity = "Critical"
            })
        }
        elseif ($PercentFree -lt 15) {
            $WarningIssues.Add([PSCustomObject]@{
                Category = "Disk Space"
                Item = $disk.Name
                Detail = "Low disk space: $PercentFree% free ($([math]::Round($disk.FreeSpace/1GB, 2)) GB remaining) on drive $($disk.Name)."
                Severity = "Warning"
            })
        }
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $DiskSpace = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - DATABASE INTEGRITY
# =================================================================================

Write-Host "Collecting database integrity information..." -NoNewline
try {
    $DbccCheckResult = @()
    $LastGoodCheckDb = @()
    
    # Query for last DBCC CHECKDB from DBCC history
    $DbccHistoryQuery = @"
SELECT 
    db_name(database_id) AS DatabaseName,
    MAX(dbcc_last_known_good) AS LastGoodCheckDb,
    DATEDIFF(HOUR, MAX(dbcc_last_known_good), GETDATE()) AS HoursSinceLastCheck
FROM sys.dm_db_index_physical_stats (NULL, NULL, NULL, NULL, 'LIMITED') p
INNER JOIN sys.databases d ON p.database_id = d.database_id
WHERE dbcc_last_known_good IS NOT NULL
GROUP BY database_id
UNION ALL
SELECT 
    name AS DatabaseName,
    NULL AS LastGoodCheckDb,
    NULL AS HoursSinceLastCheck
FROM sys.databases
WHERE database_id NOT IN (
    SELECT DISTINCT database_id 
    FROM sys.dm_db_index_physical_stats (NULL, NULL, NULL, NULL, 'LIMITED') 
    WHERE dbcc_last_known_good IS NOT NULL
)
"@
    
    try {
        $DbccHistory = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query $DbccHistoryQuery -ErrorAction Stop
        $LastGoodCheckDb = $DbccHistory
        
        foreach ($dbCheck in $DbccHistory) {
            if ($dbCheck.DatabaseName -notin ('master', 'msdb', 'model', 'tempdb')) {
                if ($dbCheck.LastGoodCheckDb -eq $null -or $dbCheck.HoursSinceLastCheck -gt 168) { # 7 days
                    $lastCheck = if ($dbCheck.LastGoodCheckDb) { $dbCheck.LastGoodCheckDb } else { "Never" }
                    $hoursSince = if ($dbCheck.HoursSinceLastCheck) { $dbCheck.HoursSinceLastCheck } else { "N/A" }
                    $WarningIssues.Add([PSCustomObject]@{
                        Category = "Integrity"
                        Item = $dbCheck.DatabaseName
                        Detail = "DBCC CHECKDB not run in last 7 days. Last good check: $lastCheck ($hoursSince hours ago)"
                        Severity = "Warning"
                    })
                }
            }
        }
    }
    catch {
        # Fallback: just note that we couldn't get DBCC history
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Integrity"
            Item = "DBCC CHECKDB"
            Detail = "Unable to retrieve DBCC CHECKDB history. Verify maintenance jobs are running."
            Severity = "Warning"
        })
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $DbccCheckResult = @()
    $LastGoodCheckDb = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - ERROR LOG ANALYSIS
# =================================================================================

Write-Host "Analyzing error logs..." -NoNewline
try {
    $ErrorLogs = Get-DbaErrorLog -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    
    # Filter for critical errors
    $CriticalErrors = $ErrorLogs | Where-Object { 
        $_.Text -match 'Severity: 2[0-5]|Error: 823|Error: 824|Error: 825|Fatal|Corruption|consistent' 
    }
    
    foreach ($err in $CriticalErrors) {
        $CriticalIssues.Add([PSCustomObject]@{
            Category = "Error Log"
            Item = "Critical Error"
            Detail = "$($err.Text.Substring(0, [math]::Min(200, $err.Text.Length)))..."
            Severity = "Critical"
        })
    }
    
    # Check for specific error patterns
    $ErrorLogSummary = $ErrorLogs | Group-Object { 
        if ($_.Text -match 'Error:\s*(\d+)') { "Error $($Matches[1])" }
        elseif ($_.Text -match 'Severity:\s*(\d+)') { "Severity $($Matches[1])" }
        else { "Other" }
    } | Select-Object Name, Count | Sort-Object Count -Descending | Select-Object -First 20
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $ErrorLogs = @()
    $CriticalErrors = @()
    $ErrorLogSummary = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - WAIT STATISTICS
# =================================================================================

Write-Host "Collecting wait statistics..." -NoNewline
try {
    $WaitStats = Get-DbaWaitStatistic -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    
    # Identify high-severity waits
    $HighSeverityWaits = $WaitStats | Where-Object { 
        $_.WaitType -in @('PAGEIOLATCH_xx', 'PAGELATCH_xx', 'LCK_M_x', 'LCK_M_S', 'LCK_M_X', 
                          'LCK_M_IX', 'CXPACKET', 'CXCONSUMER', 'RESOURCE_SEMAPHORE', 
                          'THREADPOOL', 'LOGMGR_RESERVE_APPEND', 'WRITELOG', 'ASYNC_NETWORK_IO',
                          'CMEMALLOC', 'CMEMFREE', 'MEMORY_CLERK_SQLGENERAL')
    } | Select-Object -First 10
    
    $TotalWaitTime = ($WaitStats | Measure-Object -Property WaitTimeMs -Sum).Sum
    if ($TotalWaitTime -gt 0) {
        foreach ($wait in $HighSeverityWaits) {
            $PercentWait = [math]::Round(($wait.WaitTimeMs / $TotalWaitTime) * 100, 2)
            if ($PercentWait -gt 20) {
                $WarningIssues.Add([PSCustomObject]@{
                    Category = "Wait Statistics"
                    Item = $wait.WaitType
                    Detail = "High wait time: $PercentWait% of total waits ($([math]::Round($wait.WaitTimeMs/1000/60, 2)) minutes). May indicate resource contention."
                    Severity = "Warning"
                })
            }
        }
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $WaitStats = @()
    $HighSeverityWaits = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - BLOCKING SESSIONS
# =================================================================================

Write-Host "Checking for blocking sessions..." -NoNewline
try {
    $BlockingQuery = @"
SELECT 
    blocking.session_id AS BlockingSessionID,
    blocked.session_id AS BlockedSessionID,
    blocking_sql.text AS BlockingQuery,
    blocked_sql.text AS BlockedQuery,
    blocking.wait_type AS BlockingWaitType,
    blocking.wait_time AS BlockingWaitTime,
    blocking.wait_resource AS BlockingResource,
    DB_NAME(blocked.database_id) AS DatabaseName,
    blocking.login_name AS BlockingLogin,
    blocked.login_name AS BlockedLogin,
    blocking.program_name AS BlockingProgram,
    blocked.program_name AS BlockedProgram
FROM sys.dm_exec_sessions blocked
INNER JOIN sys.dm_exec_requests blocked_req ON blocked.session_id = blocked_req.session_id
CROSS APPLY sys.dm_exec_sql_text(blocked_req.sql_handle) blocked_sql
INNER JOIN sys.dm_exec_sessions blocking ON blocked_req.blocking_session_id = blocking.session_id
LEFT JOIN sys.dm_exec_requests blocking_req ON blocking.session_id = blocking_req.session_id
CROSS APPLY sys.dm_exec_sql_text(ISNULL(blocking_req.sql_handle, 0x0)) blocking_sql
WHERE blocked_req.blocking_session_id > 0
"@
    
    $BlockingSessions = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query $BlockingQuery -ErrorAction Stop
    
    if ($BlockingSessions.Count -gt 0) {
        foreach ($block in $BlockingSessions) {
            $CriticalIssues.Add([PSCustomObject]@{
                Category = "Blocking"
                Item = "Session $($block.BlockingSessionID) blocking $($block.BlockedSessionID)"
                Detail = "Database: $($block.DatabaseName), Wait Time: $([math]::Round($block.BlockingWaitTime/1000, 2))s, Resource: $($block.BlockingResource)"
                Severity = "Critical"
            })
        }
    }
    
    # Get long-running queries
    $LongRunningQuery = @"
SELECT TOP 10
    r.session_id,
    r.status,
    r.start_time,
    DB_NAME(r.database_id) AS database_name,
    r.total_elapsed_time / 1000 AS elapsed_seconds,
    r.cpu_time / 1000 AS cpu_seconds,
    r.logical_reads,
    r.reads,
    r.writes,
    t.text AS query_text,
    s.login_name,
    s.program_name
FROM sys.dm_exec_requests r
INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id > 50
AND r.total_elapsed_time > 300000  -- More than 5 minutes
ORDER BY r.total_elapsed_time DESC
"@
    
    $LongRunningQueries = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query $LongRunningQuery -ErrorAction SilentlyContinue
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "PARTIAL" -ForegroundColor Yellow
    $BlockingSessions = @()
    $LongRunningQueries = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - PERFORMANCE METRICS
# =================================================================================

Write-Host "Collecting performance metrics..." -NoNewline
try {
    # CPU Usage
    $CpuQuery = @"
SELECT 
    TOP(1)
    record_id,
    sqlserver_process_cpu_usage,
    system_idle_cpu_usage,
    100 - system_idle_cpu_usage AS total_system_cpu_usage,
    sqlserver_process_cpu_usage * 1.0 / 100 AS sql_cpu_percent
FROM (
    SELECT 
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS system_idle_cpu_usage,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS sqlserver_process_cpu_usage,
        record.value('(./Record/@id)[1]', 'int') AS record_id
    FROM (
        SELECT CAST(record AS XML) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
        AND record LIKE '%<SystemHealth>%'
    ) AS x
) AS y
ORDER BY record_id DESC
"@
    
    $CpuUsage = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query $CpuQuery -ErrorAction Stop
    
    if ($CpuUsage -and $CpuUsage.sql_cpu_percent -gt 80) {
        $CriticalIssues.Add([PSCustomObject]@{
            Category = "Performance"
            Item = "CPU Usage"
            Detail = "SQL Server CPU usage at $([math]::Round($CpuUsage.sql_cpu_percent * 100, 1))%. High CPU pressure detected."
            Severity = "Critical"
        })
    }
    elseif ($CpuUsage -and $CpuUsage.sql_cpu_percent -gt 60) {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Performance"
            Item = "CPU Usage"
            Detail = "SQL Server CPU usage at $([math]::Round($CpuUsage.sql_cpu_percent * 100, 1))%. Monitor for CPU pressure."
            Severity = "Warning"
        })
    }
    
    # Memory Pressure
    $MemoryQuery = @"
SELECT 
    physical_memory_in_use_kb / 1024 AS sql_memory_mb,
    total_physical_memory_kb / 1024 AS total_memory_mb,
    available_physical_memory_kb / 1024 AS available_memory_mb,
    system_memory_state_desc,
    (physical_memory_in_use_kb * 100.0 / total_physical_memory_kb) AS memory_usage_percent
FROM sys.dm_os_process_memory
CROSS JOIN sys.dm_os_sys_info
"@
    
    $MemoryUsage = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query $MemoryQuery -ErrorAction Stop
    
    if ($MemoryUsage -and $MemoryUsage.memory_usage_percent -gt 90) {
        $CriticalIssues.Add([PSCustomObject]@{
            Category = "Performance"
            Item = "Memory Usage"
            Detail = "Memory usage at $([math]::Round($MemoryUsage.memory_usage_percent, 1))%. Available: $([math]::Round($MemoryUsage.available_memory_mb, 0)) MB"
            Severity = "Critical"
        })
    }
    elseif ($MemoryUsage -and $MemoryUsage.memory_usage_percent -gt 80) {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Performance"
            Item = "Memory Usage"
            Detail = "Memory usage at $([math]::Round($MemoryUsage.memory_usage_percent, 1))%. Available: $([math]::Round($MemoryUsage.available_memory_mb, 0)) MB"
            Severity = "Warning"
        })
    }
    
    # Memory Clerk Analysis
    $MemoryClerkQuery = @"
SELECT TOP 10
    type AS clerk_type,
    name AS clerk_name,
    pages_kb / 1024 AS allocated_mb,
    virtual_memory_committed_kb / 1024 AS virtual_committed_mb
FROM sys.dm_os_memory_clerks
ORDER BY pages_kb DESC
"@
    
    $MemoryClerks = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query $MemoryClerkQuery -ErrorAction SilentlyContinue
    
    # I/O Pressure
    $IoQuery = @"
SELECT 
    DB_NAME(mf.database_id) AS database_name,
    mf.physical_name,
    io_stall_read_ms / 1000 AS total_read_stall_seconds,
    io_stall_write_ms / 1000 AS total_write_stall_seconds,
    num_of_reads,
    num_of_writes,
    CASE WHEN num_of_reads > 0 THEN io_stall_read_ms / num_of_reads ELSE 0 END AS avg_read_stall_ms,
    CASE WHEN num_of_writes > 0 THEN io_stall_write_ms / num_of_writes ELSE 0 END AS avg_write_stall_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
INNER JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
ORDER BY (io_stall_read_ms + io_stall_write_ms) DESC
"@
    
    $IoStats = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query $IoQuery -ErrorAction SilentlyContinue
    
    # Check for high I/O stalls
    foreach ($io in ($IoStats | Select-Object -First 5)) {
        if ($io.avg_read_stall_ms -gt 100 -or $io.avg_write_stall_ms -gt 100) {
            $WarningIssues.Add([PSCustomObject]@{
                Category = "I/O Performance"
                Item = $io.physical_name
                Detail = "Database: $($io.database_name), Avg Read Stall: $([math]::Round($io.avg_read_stall_ms, 2))ms, Avg Write Stall: $([math]::Round($io.avg_write_stall_ms, 2))ms"
                Severity = "Warning"
            })
        }
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "PARTIAL" -ForegroundColor Yellow
    $CpuUsage = $null
    $MemoryUsage = $null
    $MemoryClerks = @()
    $IoStats = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - TEMPDB HEALTH
# =================================================================================

Write-Host "Checking TempDB health..." -NoNewline
try {
    $TempDbConfig = Get-DbaDbFile -SqlInstance $ServerInstance -SqlCredential $Credential -Database tempdb -ErrorAction Stop
    
    # Check TempDB file count (recommended: equal to logical processors, min 4)
    $TempDbDataFiles = ($TempDbConfig | Where-Object { $_.Type -eq 'ROWS' }).Count
    
    # Get CPU count
    $CpuCount = (Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query "SELECT COUNT(*) AS CpuCount FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE'" -ErrorAction SilentlyContinue).CpuCount
    
    if ($TempDbDataFiles -lt 4) {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "TempDB"
            Item = "File Count"
            Detail = "TempDB has only $TempDbDataFiles data file(s). Recommended minimum: 4 files (optimal: $CpuCount files for this server)."
            Severity = "Warning"
        })
    }
    
    # Check for uneven file sizes
    $DataFileSizes = $TempDbConfig | Where-Object { $_.Type -eq 'ROWS' } | Select-Object -ExpandProperty Size
    if ($DataFileSizes.Count -gt 1) {
        $AvgSize = ($DataFileSizes | Measure-Object -Average).Average
        $SizeVariance = ($DataFileSizes | ForEach-Object { [math]::Abs($_ - $AvgSize) / $AvgSize * 100 } | Measure-Object -Maximum).Maximum
        if ($SizeVariance -gt 10) {
            $WarningIssues.Add([PSCustomObject]@{
                Category = "TempDB"
                Item = "File Size Variance"
                Detail = "TempDB data files have $([math]::Round($SizeVariance, 1))% size variance. Files should be equally sized."
                Severity = "Warning"
            })
        }
    }
    
    # Check TempDB space usage
    $TempDbSpaceQuery = @"
SELECT 
    SUM(user_object_reserved_page_count) * 8 / 1024 AS user_objects_mb,
    SUM(internal_object_reserved_page_count) * 8 / 1024 AS internal_objects_mb,
    SUM(version_store_reserved_page_count) * 8 / 1024 AS version_store_mb,
    SUM(total_space_reserved_page_count) * 8 / 1024 AS total_reserved_mb,
    SUM(total_space_used_page_count) * 8 / 1024 AS total_used_mb
FROM tempdb.sys.dm_db_file_space_usage
"@
    
    $TempDbSpace = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query $TempDbSpaceQuery -ErrorAction SilentlyContinue
    
    # Check for PAGELATCH_xx waits on TempDB
    $TempDbWaits = $WaitStats | Where-Object { $_.WaitType -match 'PAGELATCH' }
    if ($TempDbWaits -and ($TempDbWaits | Measure-Object -Property WaitTimeMs -Sum).Sum -gt 60000) {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "TempDB"
            Item = "PAGELATCH Contention"
            Detail = "High PAGELATCH waits detected on TempDB. Consider adding data files or optimizing queries."
            Severity = "Warning"
        })
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $TempDbConfig = @()
    $TempDbSpace = $null
}

#endregion

#region ============================================================================
# DATA COLLECTION - AUTO-GROWTH SETTINGS
# =================================================================================

Write-Host "Checking auto-growth settings..." -NoNewline
try {
    $AllDbFiles = @()
    foreach ($db in $Databases) {
        try {
            $files = Get-DbaDbFile -SqlInstance $ServerInstance -SqlCredential $Credential -Database $db.Name -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                $AllDbFiles += [PSCustomObject]@{
                    Database = $db.Name
                    LogicalName = $file.LogicalName
                    PhysicalName = $file.PhysicalName
                    Type = if ($file.Type -eq 'ROWS') { 'Data' } else { 'Log' }
                    Size = $file.Size
                    Growth = $file.Growth
                    GrowthType = $file.GrowthType
                    MaxSize = $file.MaxSize
                }
                
                # Check for percentage growth (should be fixed MB/GB)
                if ($file.GrowthType -eq 'Percent') {
                    $WarningIssues.Add([PSCustomObject]@{
                        Category = "Auto-Growth"
                        Item = "$($db.Name) - $($file.LogicalName)"
                        Detail = "Using percentage-based growth ($($file.Growth)%). Recommended: Fixed size growth (e.g., 256MB for data, 128MB for log)."
                        Severity = "Warning"
                    })
                }
                
                # Check for small growth values
                if ($file.GrowthType -eq 'Megabytes' -and $file.Growth -lt 64) {
                    $WarningIssues.Add([PSCustomObject]@{
                        Category = "Auto-Growth"
                        Item = "$($db.Name) - $($file.LogicalName)"
                        Detail = "Growth value is only $($file.Growth)MB. Recommended: Minimum 64MB for data files, 128MB for log files."
                        Severity = "Warning"
                    })
                }
                
                # Check for unrestricted growth
                if ($file.MaxSize -eq -1 -or $file.MaxSize -eq 268435456) {
                    $InformationalItems.Add([PSCustomObject]@{
                        Category = "Auto-Growth"
                        Item = "$($db.Name) - $($file.LogicalName)"
                        Detail = "File has unrestricted growth. Consider setting a maximum size to prevent disk exhaustion."
                        Severity = "Info"
                    })
                }
            }
        }
        catch { }
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $AllDbFiles = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - INDEX HEALTH
# =================================================================================

Write-Host "Analyzing index health..." -NoNewline
try {
    # Get fragmented indexes
    $FragmentedIndexes = @()
    $MissingIndexes = @()
    
    foreach ($db in ($UserDatabases | Select-Object -First 10)) {  # Limit to first 10 databases for performance
        try {
            # Fragmented indexes
            $fragQuery = @"
SELECT 
    DB_NAME() AS DatabaseName,
    OBJECT_NAME(s.object_id) AS TableName,
    i.name AS IndexName,
    s.avg_fragmentation_in_percent,
    s.page_count,
    i.type_desc AS IndexType
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') s
INNER JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.avg_fragmentation_in_percent > 10
AND s.page_count > 1000
ORDER BY s.avg_fragmentation_in_percent DESC
"@
            $frag = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Database $db.Name -Query $fragQuery -ErrorAction SilentlyContinue
            $FragmentedIndexes += $frag
            
            foreach ($f in ($frag | Where-Object { $_.avg_fragmentation_in_percent -gt 30 })) {
                $WarningIssues.Add([PSCustomObject]@{
                    Category = "Index Fragmentation"
                    Item = "$($db.Name) - $($f.TableName).$($f.IndexName)"
                    Detail = "Fragmentation: $([math]::Round($f.avg_fragmentation_in_percent, 1))%, Pages: $($f.page_count)"
                    Severity = "Warning"
                })
            }
            
            # Missing indexes
            $missingQuery = @"
SELECT TOP 5
    DB_NAME() AS DatabaseName,
    ROUND(migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans), 0) AS improvement_measure,
    mid.statement AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns
FROM sys.dm_db_missing_index_details mid
INNER JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle = mig.index_handle
INNER JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
ORDER BY improvement_measure DESC
"@
            $missing = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Database $db.Name -Query $missingQuery -ErrorAction SilentlyContinue
            $MissingIndexes += $missing
        }
        catch { }
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $FragmentedIndexes = @()
    $MissingIndexes = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - AVAILABILITY GROUPS / REPLICATION
# =================================================================================

Write-Host "Checking HA/DR status..." -NoNewline
try {
    $AGStatus = @()
    $ReplicationStatus = @()
    
    # Availability Groups
    try {
        $AGs = Get-DbaAvailabilityGroup -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
        if ($AGs) {
            foreach ($ag in $AGs) {
                $AGReplicas = Get-DbaAgReplica -SqlInstance $ServerInstance -SqlCredential $Credential -AvailabilityGroup $ag.Name -ErrorAction SilentlyContinue
                $AGDatabases = Get-DbaAgDatabase -SqlInstance $ServerInstance -SqlCredential $Credential -AvailabilityGroup $ag.Name -ErrorAction SilentlyContinue
                
                foreach ($agDb in $AGDatabases) {
                    if ($agDb.SynchronizationState -ne 'Synchronized' -and $agDb.SynchronizationState -ne 'Synchronizing') {
                        $CriticalIssues.Add([PSCustomObject]@{
                            Category = "Availability Group"
                            Item = "$($ag.Name) - $($agDb.DatabaseName)"
                            Detail = "Synchronization state: $($agDb.SynchronizationState)"
                            Severity = "Critical"
                        })
                    }
                }
                
                $AGStatus += [PSCustomObject]@{
                    AGName = $ag.Name
                    PrimaryReplica = $ag.PrimaryReplica
                    SecondaryReplicas = ($AGReplicas | Where-Object { $_.Role -ne 'Primary' }).Name -join ', '
                    Databases = ($AGDatabases | ForEach-Object { "$($_.DatabaseName): $($_.SynchronizationState)" }) -join '; '
                    Health = $ag.HealthState
                }
            }
        }
    }
    catch {
        # AG not configured or error - this is okay
    }
    
    # Replication
    try {
        $ReplInfo = Get-DbaReplication -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction SilentlyContinue
        if ($ReplInfo) {
            $ReplicationStatus = $ReplInfo
        }
    }
    catch {
        # Replication not configured - this is okay
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "PARTIAL" -ForegroundColor Yellow
}

#endregion

#region ============================================================================
# DATA COLLECTION - SECURITY ASSESSMENT
# =================================================================================

Write-Host "Performing security assessment..." -NoNewline
try {
    $SecurityFindings = [System.Collections.Generic.List[PSObject]]::new()
    
    # Get logins
    $Logins = Get-DbaLogin -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    
    # Check for SA login enabled
    $SaLogin = $Logins | Where-Object { $_.Name -eq 'sa' }
    if ($SaLogin -and $SaLogin.IsDisabled -eq $false) {
        $CriticalIssues.Add([PSCustomObject]@{
            Category = "Security"
            Item = "SA Login"
            Detail = "SA login is enabled. Consider disabling and using named admin accounts."
            Severity = "Critical"
        })
    }
    
    # Check for logins with sysadmin role
    $SysadminLogins = $Logins | Where-Object { $_.IsSysAdmin -eq $true -and $_.Name -notin ('sa', 'NT SERVICE\MSSQLSERVER', 'NT SERVICE\SQLSERVERAGENT', 'NT AUTHORITY\SYSTEM') }
    foreach ($login in $SysadminLogins) {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Security"
            Item = "Sysadmin: $($login.Name)"
            Detail = "Login has sysadmin privileges. Review if this level of access is required."
            Severity = "Warning"
        })
    }
    
    # Check for SQL authentication logins
    $SqlLogins = $Logins | Where-Object { $_.LoginType -eq 'SqlLogin' }
    if ($SqlLogins.Count -gt 0) {
        $InformationalItems.Add([PSCustomObject]@{
            Category = "Security"
            Item = "SQL Authentication"
            Detail = "$($SqlLogins.Count) SQL authenticated login(s) found. Consider Windows authentication where possible."
            Severity = "Info"
        })
    }
    
    # Check for disabled logins
    $DisabledLogins = $Logins | Where-Object { $_.IsDisabled -eq $true }
    $SecurityFindings.Add([PSCustomObject]@{ Item = "Disabled Logins"; Count = $DisabledLogins.Count; Detail = "Review and remove if no longer needed" })
    
    # Check for orphaned users
    foreach ($db in $UserDatabases | Select-Object -First 10) {
        try {
            $OrphanedUsers = Find-DbaOrphanedUser -SqlInstance $ServerInstance -SqlCredential $Credential -Database $db.Name -ErrorAction SilentlyContinue
            if ($OrphanedUsers) {
                foreach ($orphan in $OrphanedUsers) {
                    $WarningIssues.Add([PSCustomObject]@{
                        Category = "Security"
                        Item = "Orphaned User"
                        Detail = "Database: $($db.Name), User: $($orphan.User)"
                        Severity = "Warning"
                    })
                }
            }
        }
        catch { }
    }
    
    # Check authentication mode
    $AuthMode = Get-DbaSpConfigure -SqlInstance $ServerInstance -SqlCredential $Credential -Name 'LoginMode' -ErrorAction SilentlyContinue
    if ($AuthMode -and $AuthMode.ConfiguredValue -ne 1) {  # 1 = Windows only
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Security"
            Item = "Authentication Mode"
            Detail = "Mixed mode authentication enabled. Ensure strong password policy is enforced."
            Severity = "Warning"
        })
    }
    
    # Check for expired or weak passwords
    $PasswordPolicy = Get-DbaSpConfigure -SqlInstance $ServerInstance -SqlCredential $Credential -Name 'CheckExpiration' -ErrorAction SilentlyContinue
    $PasswordEnforcement = Get-DbaSpConfigure -SqlInstance $ServerInstance -SqlCredential $Credential -Name 'CheckPolicy' -ErrorAction SilentlyContinue
    
    if ($PasswordPolicy -and $PasswordPolicy.ConfiguredValue -eq 0) {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Security"
            Item = "Password Expiration"
            Detail = "Password expiration check is disabled for SQL logins."
            Severity = "Warning"
        })
    }
    
    if ($PasswordEnforcement -and $PasswordEnforcement.ConfiguredValue -eq 0) {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Security"
            Item = "Password Policy"
            Detail = "Windows password policy enforcement is disabled for SQL logins."
            Severity = "Warning"
        })
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $Logins = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - INSTANCE CONFIGURATION
# =================================================================================

Write-Host "Collecting instance configuration..." -NoNewline
try {
    $SpConfigures = Get-DbaSpConfigure -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction Stop
    
    # Check important configuration settings
    $ImportantConfigs = @(
        @{ Name = 'max degree of parallelism'; Recommended = '8 or less'; Check = { $_.ConfiguredValue -gt 8 -and $_.ConfiguredValue -ne 0 } },
        @{ Name = 'cost threshold for parallelism'; Recommended = '50'; Check = { $_.ConfiguredValue -lt 50 } },
        @{ Name = 'max server memory (MB)'; Recommended = '75-80% of total'; Check = { $_.ConfiguredValue -eq 2147483647 } },
        @{ Name = 'min server memory (MB)'; Recommended = 'Set appropriately'; Check = { $_.ConfiguredValue -eq 0 } },
        @{ Name = 'fill factor (%)'; Recommended = '90-100'; Check = { $_.ConfiguredValue -lt 80 } },
        @{ Name = 'remote admin connections'; Recommended = '1'; Check = { $_.ConfiguredValue -eq 0 } },
        @{ Name = 'default trace enabled'; Recommended = '1'; Check = { $_.ConfiguredValue -eq 0 } },
        @{ Name = 'Ole Automation Procedures'; Recommended = '0'; Check = { $_.ConfiguredValue -eq 1 } },
        @{ Name = 'xp_cmdshell'; Recommended = '0'; Check = { $_.ConfiguredValue -eq 1 } },
        @{ Name = 'ad hoc distributed queries'; Recommended = '0'; Check = { $_.ConfiguredValue -eq 1 } }
    )
    
    foreach ($config in $ImportantConfigs) {
        $currentConfig = $SpConfigures | Where-Object { $_.Name -eq $config.Name }
        if ($currentConfig -and (& $config.Check $currentConfig)) {
            $severity = if ($config.Name -in ('xp_cmdshell', 'Ole Automation Procedures', 'ad hoc distributed queries')) { "Critical" } else { "Warning" }
            $issuesCollection = if ($severity -eq "Critical") { $CriticalIssues } else { $WarningIssues }
            $issuesCollection.Add([PSCustomObject]@{
                Category = "Configuration"
                Item = $config.Name
                Detail = "Current: $($currentConfig.ConfiguredValue), Recommended: $($config.Recommended)"
                Severity = $severity
            })
        }
    }
    
    # Check max memory setting
    $MaxMemory = $SpConfigures | Where-Object { $_.Name -eq 'max server memory (MB)' }
    $TotalMemoryMB = if ($MemoryUsage) { $MemoryUsage.total_memory_mb } else { 0 }
    if ($MaxMemory -and $TotalMemoryMB -gt 0) {
        $MemoryPercent = [math]::Round(($MaxMemory.ConfiguredValue / $TotalMemoryMB) * 100, 1)
        if ($MaxMemory.ConfiguredValue -eq 2147483647) {
            $CriticalIssues.Add([PSCustomObject]@{
                Category = "Configuration"
                Item = "max server memory (MB)"
                Detail = "Not configured. SQL Server can consume all available memory ($([math]::Round($TotalMemoryMB/1024, 2)) GB)."
                Severity = "Critical"
            })
        }
        elseif ($MemoryPercent -gt 90) {
            $WarningIssues.Add([PSCustomObject]@{
                Category = "Configuration"
                Item = "max server memory (MB)"
                Detail = "Set to $MemoryPercent% of total memory. Consider reducing to 75-80%."
                Severity = "Warning"
            })
        }
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $SpConfigures = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - MAINTENANCE AND ALERTS
# =================================================================================

Write-Host "Checking maintenance and alerts..." -NoNewline
try {
    # Check for OLA/Hallengren maintenance solution
    $MaintenanceJobs = $AgentJobs | Where-Object { $_.Name -match 'DatabaseBackup|IndexOptimize|IntegrityCheck|CommandLog|sp_DeleteBackupHistory' }
    
    # Check for maintenance plan jobs
    $MaintenancePlanJobs = $AgentJobs | Where-Object { $_.Category -eq 'Database Maintenance' }
    
    if (-not $MaintenanceJobs -and -not $MaintenancePlanJobs) {
        $CriticalIssues.Add([PSCustomObject]@{
            Category = "Maintenance"
            Item = "Maintenance Solution"
            Detail = "No OLA/Hallengren or Maintenance Plan jobs detected. Database maintenance may not be configured."
            Severity = "Critical"
        })
    }
    
    # Check for database mail
    $DatabaseMail = Get-DbaDbMail -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction SilentlyContinue
    if (-not $DatabaseMail -or ($DatabaseMail | Measure-Object).Count -eq 0) {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Alerts"
            Item = "Database Mail"
            Detail = "Database Mail not configured. Email notifications will not work."
            Severity = "Warning"
        })
    }
    
    # Check for operators
    $Operators = Get-DbaAgentOperator -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction SilentlyContinue
    if (-not $Operators -or ($Operators | Measure-Object).Count -eq 0) {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Alerts"
            Item = "Operators"
            Detail = "No SQL Agent operators configured. Job failure notifications may not reach anyone."
            Severity = "Warning"
        })
    }
    
    # Check for alerts
    $Alerts = Get-DbaAgentAlert -SqlInstance $ServerInstance -SqlCredential $Credential -ErrorAction SilentlyContinue
    $SevereAlerts = $Alerts | Where-Object { $_.Severity -ge 19 -or $_.MessageId -in (823, 824, 825) }
    if (-not $SevereAlerts -or ($SevereAlerts | Measure-Object).Count -eq 0) {
        $WarningIssues.Add([PSCustomObject]@{
            Category = "Alerts"
            Item = "Critical Alerts"
            Detail = "No alerts configured for severe errors (Severity 19-25, Errors 823/824/825)."
            Severity = "Warning"
        })
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "PARTIAL" -ForegroundColor Yellow
}

#endregion

#region ============================================================================
# DATA COLLECTION - CAPACITY AND GROWTH TRENDS
# =================================================================================

Write-Host "Analyzing capacity trends..." -NoNewline
try {
    $GrowthTrends = @()
    
    # Get database size history from backup history
    $GrowthQuery = @"
SELECT 
    database_name AS DatabaseName,
    backup_type AS BackupType,
    MIN(backup_start_date) AS FirstBackup,
    MAX(backup_start_date) AS LastBackup,
    COUNT(*) AS BackupCount,
    MIN(backup_size) / 1024 / 1024 AS MinSizeMB,
    MAX(backup_size) / 1024 / 1024 AS MaxSizeMB,
    AVG(backup_size) / 1024 / 1024 AS AvgSizeMB,
    DATEDIFF(DAY, MIN(backup_start_date), MAX(backup_start_date)) AS DaysSpan
FROM msdb.dbo.backupset
WHERE database_name NOT IN ('master', 'msdb', 'model', 'tempdb')
AND backup_start_date > DATEADD(DAY, -$DaysToAnalyze, GETDATE())
GROUP BY database_name, backup_type
ORDER BY database_name, backup_type
"@
    
    $GrowthData = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query $GrowthQuery -ErrorAction SilentlyContinue
    
    if ($GrowthData) {
        foreach ($row in $GrowthData) {
            if ($row.BackupType -eq 'D' -and $row.DaysSpan -gt 0) {
                $GrowthMB = $row.MaxSizeMB - $row.MinSizeMB
                $GrowthRatePerDay = $GrowthMB / $row.DaysSpan
                $ProjectedGrowth90Days = $GrowthRatePerDay * 90
                $CurrentSizeMB = $row.MaxSizeMB
                
                $GrowthTrends += [PSCustomObject]@{
                    DatabaseName = $row.DatabaseName
                    CurrentSizeMB = [math]::Round($CurrentSizeMB, 2)
                    GrowthMB = [math]::Round($GrowthMB, 2)
                    DaysAnalyzed = $row.DaysSpan
                    GrowthRatePerDayMB = [math]::Round($GrowthRatePerDay, 2)
                    Projected90DayMB = [math]::Round($ProjectedGrowth90Days, 2)
                    Projected90DaySizeMB = [math]::Round($CurrentSizeMB + $ProjectedGrowth90Days, 2)
                }
                
                # Warn about high growth rates
                if ($GrowthRatePerDay -gt 100) {  # More than 100MB per day
                    $WarningIssues.Add([PSCustomObject]@{
                        Category = "Capacity"
                        Item = $row.DatabaseName
                        Detail = "Growing at $([math]::Round($GrowthRatePerDay, 2)) MB/day. Projected 90-day size: $([math]::Round(($CurrentSizeMB + $ProjectedGrowth90Days)/1024, 2)) GB"
                        Severity = "Warning"
                    })
                }
            }
        }
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "FAILED" -ForegroundColor Red
    $GrowthTrends = @()
}

#endregion

#region ============================================================================
# DATA COLLECTION - LAST RESTORE TEST
# =================================================================================

Write-Host "Checking restore test history..." -NoNewline
try {
    $RestoreTestQuery = @"
SELECT 
    database_name AS DatabaseName,
    MAX(restore_date) AS LastRestoreTestDate,
    DATEDIFF(DAY, MAX(restore_date), GETDATE()) AS DaysSinceRestoreTest
FROM msdb.dbo.restorehistory
WHERE restore_type = 'D'
GROUP BY database_name
HAVING MAX(restore_date) IS NOT NULL
"@
    
    $RestoreTests = Invoke-DbaQuery -SqlInstance $ServerInstance -SqlCredential $Credential -Query $RestoreTestQuery -ErrorAction SilentlyContinue
    
    foreach ($test in $RestoreTests) {
        if ($test.DaysSinceRestoreTest -gt 90 -or $test.DaysSinceRestoreTest -eq $null) {
            $WarningIssues.Add([PSCustomObject]@{
                Category = "Restore Test"
                Item = $test.DatabaseName
                Detail = "Last restore test: $($test.LastRestoreTestDate) ($($test.DaysSinceRestoreTest) days ago). Recommended: Monthly restore tests."
                Severity = "Warning"
            })
        }
    }
    
    Write-Host "DONE" -ForegroundColor Green
}
catch {
    Write-Host "PARTIAL" -ForegroundColor Yellow
    $RestoreTests = @()
}

#endregion

Write-Host ""
Write-Host "Generating HTML report..." -ForegroundColor Cyan

#region ============================================================================
# HTML REPORT GENERATION
# =================================================================================

function ConvertTo-HtmlTable {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Data,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Properties,
        
        [Parameter(Mandatory = $false)]
        [string]$TableId
    )
    
    if (-not $Data -or ($Data | Measure-Object).Count -eq 0) {
        return "<p class='no-data'>No data available</p>"
    }
    
    $props = if ($Properties) { $Properties } else { ($Data[0].PSObject.Properties | Select-Object -ExpandProperty Name) }
    
    $html = "<table id='$TableId' class='data-table'>`n<thead>`n<tr>"
    foreach ($prop in $props) {
        $displayName = $prop -replace '_', ' '
        $html += "<th>$displayName</th>"
    }
    $html += "</tr>`n</thead>`n<tbody>`n"
    
    foreach ($item in $Data) {
        $html += "<tr>"
        foreach ($prop in $props) {
            $value = $item.$prop
            if ($null -eq $value) { $value = "N/A" }
            elseif ($value -is [datetime]) { $value = $value.ToString("yyyy-MM-dd HH:mm:ss") }
            elseif ($value -is [timespan]) { $value = "$($value.Days)d $($value.Hours)h $($value.Minutes)m" }
            elseif ($value -is [long] -and $prop -match 'size|space|mb|gb') { 
                if ($prop -match 'gb') { $value = "$([math]::Round($value, 2)) GB" }
                elseif ($prop -match 'mb') { $value = "$([math]::Round($value, 2)) MB" }
                else { $value = "$([math]::Round($value/1MB, 2)) MB" }
            }
            $html += "<td>$value</td>"
        }
        $html += "</tr>`n"
    }
    
    $html += "</tbody>`n</table>"
    return $html
}

function Get-SeverityBadge {
    param([string]$Severity)
    
    switch ($Severity) {
        "Critical" { return "<span class='badge badge-critical'>CRITICAL</span>" }
        "Warning" { return "<span class='badge badge-warning'>WARNING</span>" }
        "Info" { return "<span class='badge badge-info'>INFO</span>" }
        default { return "<span class='badge'>$Severity</span>" }
    }
}

function Get-StatusIndicator {
    param([bool]$IsGood)
    
    if ($IsGood) {
        return "<span class='status-good'>●</span>"
    }
    else {
        return "<span class='status-bad'>●</span>"
    }
}

# Calculate overall health score
 $totalIssues = $CriticalIssues.Count + $WarningIssues.Count
 $healthScore = [math]::Max(0, 100 - ($CriticalIssues.Count * 15) - ($WarningIssues.Count * 5))
 $healthColor = if ($healthScore -ge 80) { "green" } elseif ($healthScore -ge 60) { "orange" } else { "red" }
 $healthLabel = if ($healthScore -ge 80) { "Healthy" } elseif ($healthScore -ge 60) { "Needs Attention" } else { "Critical" }

# Start building HTML
 $htmlReport = @"

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DBA Assessment Report - $ServerInstance</title>
    <style>
        :root {
            --primary-color: #2c3e50;
            --secondary-color: #3498db;
            --success-color: #27ae60;
            --warning-color: #f39c12;
            --danger-color: #e74c3c;
            --info-color: #3498db;
            --light-gray: #ecf0f1;
            --dark-gray: #7f8c8d;
            --white: #ffffff;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: var(--primary-color);
            background-color: #f5f6fa;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
            color: var(--white);
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }
        
        .header h1 {
            font-size: 28px;
            margin-bottom: 10px;
        }
        
        .header .meta {
            opacity: 0.9;
            font-size: 14px;
        }
        
        .health-score-container {
            display: flex;
            align-items: center;
            gap: 20px;
            margin-top: 20px;
            padding: 20px;
            background: rgba(255,255,255,0.1);
            border-radius: 8px;
        }
        
        .health-score-circle {
            width: 100px;
            height: 100px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 32px;
            font-weight: bold;
            color: var(--white);
            background: var(--$healthColor);
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
        }
        
        .health-score-details h3 {
            font-size: 20px;
            margin-bottom: 5px;
        }
        
        .health-score-details .stats {
            display: flex;
            gap: 20px;
            margin-top: 10px;
        }
        
        .health-score-details .stat {
            text-align: center;
        }
        
        .health-score-details .stat-value {
            font-size: 24px;
            font-weight: bold;
        }
        
        .health-score-details .stat-label {
            font-size: 12px;
            opacity: 0.8;
        }
        
        .section {
            background: var(--white);
            border-radius: 10px;
            padding: 25px;
            margin-bottom: 25px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.05);
        }
        
        .section h2 {
            font-size: 20px;
            color: var(--primary-color);
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid var(--light-gray);
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .section h2 .icon {
            font-size: 24px;
        }
        
        .section h3 {
            font-size: 16px;
            color: var(--dark-gray);
            margin: 20px 0 10px 0;
        }
        
        .data-table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
            font-size: 13px;
        }
        
        .data-table th {
            background-color: var(--primary-color);
            color: var(--white);
            padding: 12px 10px;
            text-align: left;
            font-weight: 600;
            white-space: nowrap;
        }
        
        .data-table td {
            padding: 10px;
            border-bottom: 1px solid var(--light-gray);
            word-wrap: break-word;
            max-width: 300px;
        }
        
        .data-table tr:nth-child(even) {
            background-color: #f8f9fa;
        }
        
        .data-table tr:hover {
            background-color: #e8f4fc;
        }
        
        .badge {
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
        }
        
        .badge-critical {
            background-color: var(--danger-color);
            color: var(--white);
        }
        
        .badge-warning {
            background-color: var(--warning-color);
            color: var(--white);
        }
        
        .badge-info {
            background-color: var(--info-color);
            color: var(--white);
        }
        
        .badge-success {
            background-color: var(--success-color);
            color: var(--white);
        }
        
        .status-good {
            color: var(--success-color);
            font-size: 18px;
        }
        
        .status-bad {
            color: var(--danger-color);
            font-size: 18px;
        }
        
        .issue-card {
            background: var(--white);
            border-left: 4px solid;
            padding: 15px;
            margin: 10px 0;
            border-radius: 0 8px 8px 0;
            box-shadow: 0 2px 5px rgba(0,0,0,0.05);
        }
        
        .issue-card.critical {
            border-left-color: var(--danger-color);
            background: linear-gradient(to right, #fff5f5, var(--white));
        }
        
        .issue-card.warning {
            border-left-color: var(--warning-color);
            background: linear-gradient(to right, #fffbf0, var(--white));
        }
        
        .issue-card.info {
            border-left-color: var(--info-color);
            background: linear-gradient(to right, #f0f8ff, var(--white));
        }
        
        .issue-card .issue-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 5px;
        }
        
        .issue-card .issue-category {
            font-weight: 600;
            color: var(--primary-color);
        }
        
        .issue-card .issue-item {
            font-weight: 600;
            margin-bottom: 5px;
        }
        
        .issue-card .issue-detail {
            color: var(--dark-gray);
            font-size: 14px;
        }
        
        .no-data {
            color: var(--dark-gray);
            font-style: italic;
            padding: 15px;
        }
        
        .grid-2 {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 25px;
        }
        
        .grid-3 {
            display: grid;
            grid-template-columns: 1fr 1fr 1fr;
            gap: 25px;
        }
        
        .info-card {
            background: var(--white);
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.05);
        }
        
        .info-card h4 {
            color: var(--dark-gray);
            font-size: 14px;
            margin-bottom: 5px;
        }
        
        .info-card .value {
            font-size: 24px;
            font-weight: bold;
            color: var(--primary-color);
        }
        
        .footer {
            text-align: center;
            padding: 20px;
            color: var(--dark-gray);
            font-size: 12px;
            margin-top: 30px;
        }
        
        @media print {
            body {
                background: white;
            }
            .section {
                break-inside: avoid;
                box-shadow: none;
                border: 1px solid #ddd;
            }
            .header {
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
        }
        
        @media (max-width: 768px) {
            .grid-2, .grid-3 {
                grid-template-columns: 1fr;
            }
            .health-score-container {
                flex-direction: column;
                text-align: center;
            }
            .health-score-details .stats {
                justify-content: center;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ SQL Server DBA Assessment Report</h1>
            <div class="meta">
                <strong>Server:</strong> $ServerInstance | 
                <strong>Generated:</strong> $ReportTimestamp |
                <strong>Analysis Period:</strong> Last $DaysToAnalyze days
            </div>
            
            <div class="health-score-container">
                <div class="health-score-circle">$healthScore</div>
                <div class="health-score-details">
                    <h3>Overall Health: $healthLabel</h3>
                    <div class="stats">
                        <div class="stat">
                            <div class="stat-value" style="color: #e74c3c;">$($CriticalIssues.Count)</div>
                            <div class="stat-label">Critical</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value" style="color: #f39c12;">$($WarningIssues.Count)</div>
                            <div class="stat-label">Warnings</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value" style="color: #3498db;">$($InformationalItems.Count)</div>
                            <div class="stat-label">Info</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

"@

# ============================================================================
# SECTION: CRITICAL ISSUES (What is broken now)
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">🔴</span> Critical Issues - What Is Broken Now</h2>
"@

if ($CriticalIssues.Count -gt 0) {
    foreach ($issue in $CriticalIssues) {
        $htmlReport += @"
            <div class="issue-card critical">
                <div class="issue-header">
                    <span class="issue-category">$($issue.Category)</span>
                    $(Get-SeverityBadge -Severity "Critical")
                </div>
                <div class="issue-item">$($issue.Item)</div>
                <div class="issue-detail">$($issue.Detail)</div>
            </div>
"@
    }
}
else {
    $htmlReport += "<p class='no-data'>✅ No critical issues found.</p>"
}

 $htmlReport += @"
        </div>

        <div class="section">
            <h2><span class="icon">🟡</span> Warnings - What Is At Risk Soon</h2>
"@

if ($WarningIssues.Count -gt 0) {
    foreach ($issue in ($WarningIssues | Select-Object -First 20)) {
        $htmlReport += @"
            <div class="issue-card warning">
                <div class="issue-header">
                    <span class="issue-category">$($issue.Category)</span>
                    $(Get-SeverityBadge -Severity "Warning")
                </div>
                <div class="issue-item">$($issue.Item)</div>
                <div class="issue-detail">$($issue.Detail)</div>
            </div>
"@
    }
    if ($WarningIssues.Count -gt 20) {
        $htmlReport += "<p class='no-data'>... and $($WarningIssues.Count - 20) more warnings. See full details below.</p>"
    }
}
else {
    $htmlReport += "<p class='no-data'>✅ No warnings found.</p>"
}

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: SERVER OVERVIEW
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">🖥️</span> Server & Instance Overview</h2>
            
            <div class="grid-3">
                <div class="info-card">
                    <h4>SQL Server Version</h4>
                    <div class="value">$($SpInfo.ProductVersion)</div>
                </div>
                <div class="info-card">
                    <h4>Edition</h4>
                    <div class="value">$($SpInfo.Edition)</div>
                </div>
                <div class="info-card">
                    <h4>Service Pack / CU</h4>
                    <div class="value">$($SpInfo.ProductLevel) $($SpInfo.ProductUpdateLevel)</div>
                </div>
                <div class="info-card">
                    <h4>Uptime</h4>
                    <div class="value">$($CurrentUptime.Days)d $($CurrentUptime.Hours)h</div>
                </div>
                <div class="info-card">
                    <h4>Last Restart</h4>
                    <div class="value" style="font-size: 16px;">$(if ($LastRestart) { $LastRestart.ToString("yyyy-MM-dd HH:mm") } else { "N/A" })</div>
                </div>
                <div class="info-card">
                    <h4>Build Status</h4>
                    <div class="value" style="font-size: 16px;">$(if ($IsLatestBuild -eq $true) { "✅ Latest" } elseif ($IsLatestBuild -eq $false) { "⚠️ Behind: $BuildLag" } else { "❓ Unknown" })</div>
                </div>
            </div>

            <h3>Service Status</h3>
"@

 $serviceData = $ServiceStatus | Select-Object ServiceType, Name, State, StartMode, @{N='Account';E={$_.ServiceAccount}} 
 $htmlReport += ConvertTo-HtmlTable -Data $serviceData -Properties @("ServiceType", "Name", "State", "StartMode", "Account") -TableId "serviceStatus"

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: DATABASE INVENTORY
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">🗄️</span> Database Inventory</h2>
"@

 $dbData = $Databases | Select-Object Name, Status, RecoveryModel, 
    @{N='SizeMB';E={[math]::Round($_.Size, 2)}},
    @{N='CompatibilityLevel';E={$_.CompatibilityLevel}},
    @{N='CreateDate';E={$_.CreateDate}},
    @{N='LastFullBackup';E={($_ | Get-DbaDbBackupHistory -SqlInstance $ServerInstance -SqlCredential $Credential -Last -ErrorAction SilentlyContinue | Where-Object {$_.Type -eq 'Full'} | Select-Object -First 1).LastBackup}},
    Owner,
    IsReadOnly,
    IsOffline

 $htmlReport += ConvertTo-HtmlTable -Data $dbData -Properties @("Name", "Status", "RecoveryModel", "SizeMB", "CompatibilityLevel", "Owner", "IsReadOnly", "LastFullBackup") -TableId "databaseInventory"

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: BACKUP STATUS
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">💾</span> Backup Status</h2>
"@

 $backupData = @()
foreach ($db in $UserDatabases) {
    $fullBackup = $BackupHistory | Where-Object { $_.Database -eq $db.Name -and $_.Type -eq 'Full' } | Select-Object -First 1
    $diffBackup = $BackupHistory | Where-Object { $_.Database -eq $db.Name -and $_.Type -eq 'Differential' } | Select-Object -First 1
    $logBackup = $BackupHistory | Where-Object { $_.Database -eq $db.Name -and $_.Type -eq 'Log' } | Select-Object -First 1
    
    $fullAge = if ($fullBackup.LastBackup) { [math]::Round(((Get-Date) - $fullBackup.LastBackup).TotalHours, 1) } else { "N/A" }
    $logAge = if ($logBackup.LastBackup) { [math]::Round(((Get-Date) - $logBackup.LastBackup).TotalMinutes, 1) } else { "N/A" }
    
    $backupData += [PSCustomObject]@{
        Database = $db.Name
        RecoveryModel = $db.RecoveryModel
        LastFullBackup = if ($fullBackup.LastBackup) { $fullBackup.LastBackup } else { "NEVER" }
        FullBackupAgeHours = $fullAge
        LastDiffBackup = if ($diffBackup.LastBackup) { $diffBackup.LastBackup } else { "N/A" }
        LastLogBackup = if ($logBackup.LastBackup) { $logBackup.LastBackup } else { "N/A" }
        LogBackupAgeMinutes = $logAge
        LastBackupSizeMB = if ($fullBackup.TotalSize) { [math]::Round($fullBackup.TotalSize/1MB, 2) } else { "N/A" }
    }
}

 $htmlReport += ConvertTo-HtmlTable -Data $backupData -Properties @("Database", "RecoveryModel", "LastFullBackup", "FullBackupAgeHours", "LastDiffBackup", "LastLogBackup", "LogBackupAgeMinutes", "LastBackupSizeMB") -TableId "backupStatus"

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: SQL AGENT JOBS
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">⚙️</span> SQL Agent Jobs</h2>
"@

 $jobData = $AgentJobs | Select-Object Name, Category, 
    @{N='Enabled';E={if($_.IsEnabled){"Yes"}else{"No"}}},
    @{N='LastRunDate';E={$_.LastRunDate}},
    @{N='LastRunStatus';E={$_.LastRunStatus}},
    @{N='NextRunDate';E={$_.NextRunDate}}

 $htmlReport += ConvertTo-HtmlTable -Data $jobData -Properties @("Name", "Category", "Enabled", "LastRunDate", "LastRunStatus", "NextRunDate") -TableId "agentJobs"

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: DISK SPACE
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">💿</span> Disk Space</h2>
"@

 $diskData = $DiskSpace | Select-Object Name, 
    @{N='Label';E={$_.Label}},
    @{N='TotalGB';E={[math]::Round($_.TotalSize/1GB, 2)}},
    @{N='UsedGB';E={[math]::Round(($_.TotalSize - $_.FreeSpace)/1GB, 2)}},
    @{N='FreeGB';E={[math]::Round($_.FreeSpace/1GB, 2)}},
    @{N='PercentFree';E={[math]::Round(($_.FreeSpace / $_.TotalSize) * 100, 2)}},
    @{N='FileSystem';E={$_.FileSystem}},
    @{N='BlockSize';E={$_.BlockSize}}

 $htmlReport += ConvertTo-HtmlTable -Data $diskData -Properties @("Name", "Label", "TotalGB", "UsedGB", "FreeGB", "PercentFree", "FileSystem") -TableId "diskSpace"

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: PERFORMANCE METRICS
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">📊</span> Performance Metrics</h2>
            
            <div class="grid-3">
                <div class="info-card">
                    <h4>SQL Server CPU %</h4>
                    <div class="value" style="color: $(if($CpuUsage -and $CpuUsage.sql_cpu_percent -gt 0.8){'#e74c3c'}elseif($CpuUsage -and $CpuUsage.sql_cpu_percent -gt 0.6){'#f39c12'}else{'#27ae60'});">
                        $(if($CpuUsage){[math]::Round($CpuUsage.sql_cpu_percent * 100, 1)}else{"N/A"})%
                    </div>
                </div>
                <div class="info-card">
                    <h4>Memory Usage %</h4>
                    <div class="value" style="color: $(if($MemoryUsage -and $MemoryUsage.memory_usage_percent -gt 90){'#e74c3c'}elseif($MemoryUsage -and $MemoryUsage.memory_usage_percent -gt 80){'#f39c12'}else{'#27ae60'});">
                        $(if($MemoryUsage){[math]::Round($MemoryUsage.memory_usage_percent, 1)}else{"N/A"})%
                    </div>
                </div>
                <div class="info-card">
                    <h4>Available Memory</h4>
                    <div class="value" style="font-size: 18px;">$(if($MemoryUsage){[math]::Round($MemoryUsage.available_memory_mb/1024, 2)}else{"N/A"}) GB</div>
                </div>
            </div>

            <h3>Top Wait Statistics</h3>
"@

 $waitData = $WaitStats | Select-Object -First 15 | Select-Object WaitType,
    @{N='WaitTimeMin';E={[math]::Round($_.WaitTimeMs/1000/60, 2)}},
    @{N='SignalWaitTimeMin';E={[math]::Round($_.SignalWaitTimeMs/1000/60, 2)}},
    WaitCount,
    @{N='AvgWaitMs';E={if($_.WaitCount -gt 0){[math]::Round($_.WaitTimeMs/$_.WaitCount, 2)}else{0}}}

 $htmlReport += ConvertTo-HtmlTable -Data $waitData -Properties @("WaitType", "WaitTimeMin", "SignalWaitTimeMin", "WaitCount", "AvgWaitMs") -TableId "waitStats"

 $htmlReport += @"
            
            <h3>I/O Performance by File</h3>
"@

 $ioData = $IoStats | Select-Object -First 10 | Select-Object database_name,
    @{N='FileName';E={$_.physical_name | Split-Path -Leaf}},
    @{N='AvgReadStallMs';E={[math]::Round($_.avg_read_stall_ms, 2)}},
    @{N='AvgWriteStallMs';E={[math]::Round($_.avg_write_stall_ms, 2)}},
    num_of_reads,
    num_of_writes

 $htmlReport += ConvertTo-HtmlTable -Data $ioData -Properties @("database_name", "FileName", "AvgReadStallMs", "AvgWriteStallMs", "num_of_reads", "num_of_writes") -TableId "ioStats"

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: TEMPDB
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">📁</span> TempDB Health</h2>
            
            <div class="grid-3">
                <div class="info-card">
                    <h4>Data Files</h4>
                    <div class="value">$TempDbDataFiles</div>
                </div>
                <div class="info-card">
                    <h4>Recommended Files</h4>
                    <div class="value">$CpuCount</div>
                </div>
                <div class="info-card">
                    <h4>Total Reserved</h4>
                    <div class="value" style="font-size: 18px;">$(if($TempDbSpace){[math]::Round($TempDbSpace.total_reserved_mb/1024, 2)}else{"N/A"}) GB</div>
                </div>
            </div>
"@

if ($TempDbSpace) {
    $htmlReport += @"
            <div class="grid-3" style="margin-top: 15px;">
                <div class="info-card">
                    <h4>User Objects</h4>
                    <div class="value" style="font-size: 16px;">$([math]::Round($TempDbSpace.user_objects_mb, 2)) MB</div>
                </div>
                <div class="info-card">
                    <h4>Internal Objects</h4>
                    <div class="value" style="font-size: 16px;">$([math]::Round($TempDbSpace.internal_objects_mb, 2)) MB</div>
                </div>
                <div class="info-card">
                    <h4>Version Store</h4>
                    <div class="value" style="font-size: 16px;">$([math]::Round($TempDbSpace.version_store_mb, 2)) MB</div>
                </div>
            </div>
"@

    $tempDbFileData = $TempDbConfig | Select-Object LogicalName,
        @{N='Type';E={if($_.Type -eq 'ROWS'){'Data'}else{'Log'}}},
        @{N='SizeMB';E={[math]::Round($_.Size, 2)}},
        @{N='Growth';E={"$($_.Growth) $($_.GrowthType)"}},
        @{N='PhysicalName';E={$_.PhysicalName | Split-Path -Leaf}}

    $htmlReport += "<h3>TempDB Files</h3>"
    $htmlReport += ConvertTo-HtmlTable -Data $tempDbFileData -Properties @("LogicalName", "Type", "SizeMB", "Growth", "PhysicalName") -TableId "tempdbFiles"
}

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: BLOCKING AND LONG-RUNNING QUERIES
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">🔒</span> Blocking & Long-Running Queries</h2>
            
            <h3>Current Blocking Sessions</h3>
"@

if ($BlockingSessions -and $BlockingSessions.Count -gt 0) {
    $blockData = $BlockingSessions | Select-Object BlockingSessionID, BlockedSessionID, DatabaseName, 
        @{N='BlockingLogin';E={$_.BlockingLogin}},
        @{N='BlockedLogin';E={$_.BlockedLogin}},
        @{N='WaitTimeSec';E={[math]::Round($_.BlockingWaitTime/1000, 2)}},
        @{N='BlockingQuery';E={$_.BlockingQuery.Substring(0, [math]::Min(100, $_.BlockingQuery.Length)) + "..."}}
    
    $htmlReport += ConvertTo-HtmlTable -Data $blockData -Properties @("BlockingSessionID", "BlockedSessionID", "DatabaseName", "BlockingLogin", "BlockedLogin", "WaitTimeSec", "BlockingQuery") -TableId "blockingSessions"
}
else {
    $htmlReport += "<p class='no-data'>✅ No blocking sessions detected at time of assessment.</p>"
}

 $htmlReport += @"
            <h3>Long-Running Queries (> 5 minutes)</h3>
"@

if ($LongRunningQueries -and $LongRunningQueries.Count -gt 0) {
    $longQueryData = $LongRunningQueries | Select-Object session_id, status, database_name, 
        @{N='ElapsedSec';E={[math]::Round($_.elapsed_seconds, 0)}},
        @{N='CpuSec';E={[math]::Round($_.cpu_seconds, 0)}},
        logical_reads,
        login_name,
        @{N='QueryText';E={$_.query_text.Substring(0, [math]::Min(150, $_.query_text.Length)) + "..."}}
    
    $htmlReport += ConvertTo-HtmlTable -Data $longQueryData -Properties @("session_id", "status", "database_name", "ElapsedSec", "CpuSec", "logical_reads", "login_name", "QueryText") -TableId "longRunningQueries"
}
else {
    $htmlReport += "<p class='no-data'>✅ No long-running queries detected at time of assessment.</p>"
}

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: DATABASE INTEGRITY
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">✅</span> Database Integrity (DBCC CHECKDB)</h2>
"@

if ($LastGoodCheckDb -and $LastGoodCheckDb.Count -gt 0) {
    $integrityData = $LastGoodCheckDb | Select-Object DatabaseName,
        @{N='LastGoodCheckDb';E={if($_.LastGoodCheckDb){$_.LastGoodCheckDb}else{"Never"}}},
        @{N='HoursSinceCheck';E={if($_.HoursSinceLastCheck){$_.HoursSinceLastCheck}else{"N/A"}}},
        @{N='Status';E={if($_.HoursSinceLastCheck -gt 168){"⚠️ Overdue"}elseif($_.LastGoodCheckDb){"✅ OK"}else{"❌ Never Run"}}}
    
    $htmlReport += ConvertTo-HtmlTable -Data $integrityData -Properties @("DatabaseName", "LastGoodCheckDb", "HoursSinceCheck", "Status") -TableId "dbccHistory"
}
else {
    $htmlReport += "<p class='no-data'>Unable to retrieve DBCC CHECKDB history.</p>"
}

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: INDEX HEALTH
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">📑</span> Index Health</h2>
            
            <h3>Fragmented Indexes (> 10% fragmentation, > 1000 pages)</h3>
"@

if ($FragmentedIndexes -and $FragmentedIndexes.Count -gt 0) {
    $fragData = $FragmentedIndexes | Select-Object DatabaseName, TableName, IndexName,
        @{N='FragmentationPct';E={[math]::Round($_.avg_fragmentation_in_percent, 1)}},
        @{N='PageCount';E={$_.page_count}},
        IndexType
    
    $htmlReport += ConvertTo-HtmlTable -Data ($fragData | Select-Object -First 20) -Properties @("DatabaseName", "TableName", "IndexName", "FragmentationPct", "PageCount", "IndexType") -TableId "fragmentedIndexes"
}
else {
    $htmlReport += "<p class='no-data'>✅ No significantly fragmented indexes found.</p>"
}

 $htmlReport += @"
            <h3>Top Missing Index Recommendations</h3>
"@

if ($MissingIndexes -and $MissingIndexes.Count -gt 0) {
    $missingData = $MissingIndexes | Select-Object -First 10 | Select-Object DatabaseName,
        @{N='ImprovementMeasure';E={[math]::Round($_.improvement_measure, 0)}},
        @{N='TableName';E={$_.table_name}},
        equality_columns,
        inequality_columns,
        included_columns
    
    $htmlReport += ConvertTo-HtmlTable -Data $missingData -Properties @("DatabaseName", "ImprovementMeasure", "TableName", "equality_columns", "inequality_columns", "included_columns") -TableId "missingIndexes"
}
else {
    $htmlReport += "<p class='no-data'>No missing index recommendations.</p>"
}

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: AVAILABILITY GROUPS
# ============================================================================

if ($AGStatus -and $AGStatus.Count -gt 0) {
    $htmlReport += @"
        <div class="section">
            <h2><span class="icon">🔄</span> Availability Groups</h2>
"@
    $htmlReport += ConvertTo-HtmlTable -Data $AGStatus -Properties @("AGName", "PrimaryReplica", "SecondaryReplicas", "Databases", "Health") -TableId "agStatus"
    $htmlReport += @"
        </div>
"@
}

# ============================================================================
# SECTION: SECURITY
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">🔐</span> Security Assessment</h2>
            
            <h3>Logins with Sysadmin Access</h3>
"@

 $sysadminData = $Logins | Where-Object { $_.IsSysAdmin } | Select-Object Name,
    @{N='LoginType';E={$_.LoginType}},
    @{N='Disabled';E={if($_.IsDisabled){"Yes"}else{"No"}}},
    @{N='HasPassword';E={if($_.HasPassword){"Yes"}else{"No"}}},
    @{N='DefaultDatabase';E={$_.DefaultDatabase}},
    @{N='CreateDate';E={$_.CreateDate}},
    @{N='LastLogin';E={$_.LastLogin}}

 $htmlReport += ConvertTo-HtmlTable -Data $sysadminData -Properties @("Name", "LoginType", "Disabled", "HasPassword", "DefaultDatabase", "LastLogin") -TableId "sysadminLogins"

 $htmlReport += @"
            <h3>SQL Authenticated Logins</h3>
"@

 $sqlLoginData = $SqlLogins | Select-Object Name,
    @{N='Disabled';E={if($_.IsDisabled){"Yes"}else{"No"}}},
    @{N='SysAdmin';E={if($_.IsSysAdmin){"Yes"}else{"No"}}},
    @{N='PasswordExpired';E={if($_.PasswordExpired){"Yes"}else{"No"}}},
    @{N='LastLogin';E={$_.LastLogin}}

 $htmlReport += ConvertTo-HtmlTable -Data $sqlLoginData -Properties @("Name", "Disabled", "SysAdmin", "PasswordExpired", "LastLogin") -TableId "sqlLogins"

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: INSTANCE CONFIGURATION
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">🔧</span> Key Instance Configurations</h2>
"@

 $importantConfigNames = @(
    'max server memory (MB)',
    'min server memory (MB)',
    'max degree of parallelism',
    'cost threshold for parallelism',
    'fill factor (%)',
    'remote admin connections',
    'default trace enabled',
    'xp_cmdshell',
    'Ole Automation Procedures',
    'ad hoc distributed queries',
    'clr enabled',
    'max worker threads',
    'recovery interval (min)',
    'nested triggers',
    'two digit year cutoff',
    'backup compression default',
    'optimize for ad hoc workloads'
)

 $configData = $SpConfigures | Where-Object { $_.Name -in $importantConfigNames } | Select-Object Name,
    @{N='RunningValue';E={$_.RunningValue}},
    @{N='ConfiguredValue';E={$_.ConfiguredValue}},
    @{N='DefaultValue';E={$_.DefaultValue}},
    @{N='IsAdvanced';E={if($_.IsAdvanced){"Yes"}else{"No"}}}

 $htmlReport += ConvertTo-HtmlTable -Data $configData -Properties @("Name", "ConfiguredValue", "RunningValue", "DefaultValue", "IsAdvanced") -TableId "spConfigures"

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: ERROR LOG SUMMARY
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">📋</span> Error Log Summary (Last 7 Days)</h2>
            
            <h3>Error Distribution</h3>
"@

 $htmlReport += ConvertTo-HtmlTable -Data $ErrorLogSummary -Properties @("Name", "Count") -TableId "errorLogSummary"

if ($CriticalErrors -and $CriticalErrors.Count -gt 0) {
    $htmlReport += @"
            <h3>Critical Errors Found</h3>
"@
    $criticalErrorData = $CriticalErrors | Select-Object -First 10 | Select-Object 
        @{N='LogDate';E={$_.LogDate}},
        @{N='Source';E={$_.Source}},
        @{N='Text';E={$_.Text.Substring(0, [math]::Min(200, $_.Text.Length)) + "..."}}
    
    $htmlReport += ConvertTo-HtmlTable -Data $criticalErrorData -Properties @("LogDate", "Source", "Text") -TableId "criticalErrors"
}

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: AUTO-GROWTH SETTINGS
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">📈</span> Auto-Growth Settings (Problematic)</h2>
"@

 $problematicGrowth = $AllDbFiles | Where-Object { $_.GrowthType -eq 'Percent' -or ($_.GrowthType -eq 'Megabytes' -and $_.Growth -lt 64) }

if ($problematicGrowth -and $problematicGrowth.Count -gt 0) {
    $growthData = $problematicGrowth | Select-Object Database, LogicalName, Type,
        @{N='SizeMB';E={[math]::Round($_.Size, 2)}},
        @{N='Growth';E={"$($_.Growth) $($_.GrowthType)"}},
        @{N='PhysicalName';E={$_.PhysicalName | Split-Path -Leaf}}
    
    $htmlReport += ConvertTo-HtmlTable -Data ($growthData | Select-Object -First 20) -Properties @("Database", "LogicalName", "Type", "SizeMB", "Growth", "PhysicalName") -TableId "autoGrowth"
}
else {
    $htmlReport += "<p class='no-data'>✅ All databases have appropriate auto-growth settings.</p>"
}

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: CAPACITY TRENDS
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">📉</span> Capacity & Growth Trends</h2>
"@

if ($GrowthTrends -and $GrowthTrends.Count -gt 0) {
    $trendData = $GrowthTrends | Select-Object DatabaseName,
        @{N='CurrentSizeMB';E={[math]::Round($_.CurrentSizeMB, 2)}},
        @{N='GrowthMB';E={[math]::Round($_.GrowthMB, 2)}},
        @{N='DaysAnalyzed';E={$_.DaysAnalyzed}},
        @{N='GrowthPerDayMB';E={[math]::Round($_.GrowthRatePerDayMB, 2)}},
        @{N='Projected90DayMB';E={[math]::Round($_.Projected90DaySizeMB, 2)}}
    
    $htmlReport += ConvertTo-HtmlTable -Data $trendData -Properties @("DatabaseName", "CurrentSizeMB", "GrowthMB", "DaysAnalyzed", "GrowthPerDayMB", "Projected90DayMB") -TableId "growthTrends"
}
else {
    $htmlReport += "<p class='no-data'>Insufficient backup history to calculate growth trends.</p>"
}

 $htmlReport += @"
        </div>
"@

# ============================================================================
# SECTION: MAINTENANCE & ALERTS
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">🔧</span> Maintenance & Alerting Status</h2>
            
            <div class="grid-2">
                <div>
                    <h3>Maintenance Solution</h3>
"@

if ($MaintenanceJobs) {
    $maintJobData = $MaintenanceJobs | Select-Object Name,
        @{N='Enabled';E={if($_.IsEnabled){"Yes"}else{"No"}}},
        @{N='LastRunStatus';E={$_.LastRunStatus}},
        @{N='LastRunDate';E={$_.LastRunDate}}
    
    $htmlReport += ConvertTo-HtmlTable -Data $maintJobData -Properties @("Name", "Enabled", "LastRunStatus", "LastRunDate") -TableId "maintenanceJobs"
}
else {
    $htmlReport += "<p class='no-data'>⚠️ No OLA/Hallengren maintenance jobs detected.</p>"
}

 $htmlReport += @"
                </div>
                <div>
                    <h3>Alerting Configuration</h3>
                    <table class='data-table'>
                        <tr><th>Component</th><th>Status</th></tr>
                        <tr>
                            <td>Database Mail</td>
                            <td>$(if($DatabaseMail){Get-StatusIndicator -IsGood $true; " Configured"}else{Get-StatusIndicator -IsGood $false; " Not Configured"})</td>
                        </tr>
                        <tr>
                            <td>Operators</td>
                            <td>$(if($Operators -and ($Operators|Measure-Object).Count -gt 0){"$($(Get-StatusIndicator -IsGood $true) $($Operators.Count) configured"}else{"$(Get-StatusIndicator -IsGood $false) None configured"})</td>
                        </tr>
                        <tr>
                            <td>Severe Error Alerts (19-25, 823-825)</td>
                            <td>$(if($SevereAlerts -and ($SevereAlerts|Measure-Object).Count -gt 0){"$($(Get-StatusIndicator -IsGood $true) $($SevereAlerts.Count) configured"}else{"$(Get-StatusIndicator -IsGood $false) None configured"})</td>
                        </tr>
                        <tr>
                            <td>Total Alerts</td>
                            <td>$(if($Alerts){$($Alerts.Count)}else{0})</td>
                        </tr>
                    </table>
                </div>
            </div>
        </div>
"@

# ============================================================================
# SECTION: RESTORE TEST HISTORY
# ============================================================================

 $htmlReport += @"
        <div class="section">
            <h2><span class="icon">🔄</span> Restore Test History</h2>
"@

if ($RestoreTests -and $RestoreTests.Count -gt 0) {
    $restoreData = $RestoreTests | Select-Object DatabaseName,
        @{N='LastRestoreTest';E={$_.LastRestoreTestDate}},
        @{N='DaysSinceTest';E={$_.DaysSinceRestoreTest}},
        @{N='Status';E={if($_.DaysSinceRestoreTest -gt 90){"⚠️ Overdue"}else{"✅ OK"}}}
    
    $htmlReport += ConvertTo-HtmlTable -Data $restoreData -Properties @("DatabaseName", "LastRestoreTest", "DaysSinceTest", "Status") -TableId "restoreTests"
}
else {
    $htmlReport += "<p class='no-data'>⚠️ No restore test history found. Recommend regular restore tests to validate backup integrity.</p>"
}

 $htmlReport += @"
        </div>
"@

# ============================================================================
# FOOTER
# ============================================================================

 $htmlReport += @"
        <div class="footer">
            <p>DBA Assessment Report generated by dbatools | $ReportTimestamp</p>
            <p>This report is a point-in-time assessment. Continuous monitoring is recommended for production environments.</p>
        </div>
    </div>
</body>
</html>
"@

#endregion

#region ============================================================================
# SAVE REPORT
# =================================================================================

try {
    $htmlReport | Out-File -FilePath $ReportFilePath -Encoding UTF8 -Force
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " Report Generated Successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " Location: $ReportFilePath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " Summary:" -ForegroundColor Yellow
    Write-Host "   - Health Score: $healthScore/100 ($healthLabel)" -ForegroundColor $(if($healthScore -ge 80){"Green"}elseif($healthScore -ge 60){"Yellow"}else{"Red"})
    Write-Host "   - Critical Issues: $($CriticalIssues.Count)" -ForegroundColor $(if($CriticalIssues.Count -gt 0){"Red"}else{"Green"})
    Write-Host "   - Warnings: $($WarningIssues.Count)" -ForegroundColor $(if($WarningIssues.Count -gt 0){"Yellow"}else{"Green"})
    Write-Host "   - Informational: $($InformationalItems.Count)" -ForegroundColor Cyan
    Write-Host ""
    
    # Auto-open report
    Invoke-Item -Path $ReportFilePath
}
catch {
    Write-Error "Failed to save report: $_"
}

#endregion