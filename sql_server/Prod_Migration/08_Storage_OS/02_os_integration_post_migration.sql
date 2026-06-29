/*
================================================================================
OS Integration Checks After Migration (IFI, LPIM, AV, AD)
================================================================================
Purpose:
    External/OS factors that cause high elapsed time with minimal SQL CPU.
    Especially relevant when:
    - PREEMPTIVE_OS_* waits appear
    - SSMS metadata is slow (AD token resolution)
    - File growth is slow (IFI disabled)
    - Same VM local execution still slow

SQL-side checks:
    (1) Instant File Initialization
    (2) SQL memory model (Lock Pages In Memory)
    (3) PREEMPTIVE wait breakdown
    (4) Service account and startup type

Manual OS checklist (document for ops team):
    [ ] Exclude SQL data/log/backup paths from antivirus real-time scan
    [ ] Verify SQL service account has Perform Volume Maintenance Tasks (IFI)
    [ ] Verify Lock Pages in Memory if server is dedicated
    [ ] Test SQL authentication vs Windows auth (isolates AD latency)
    [ ] Check VM storage driver (paravirtual vs IDE)
    [ ] Review Windows Event Log for disk warnings after migration

Criticality: High for PREEMPTIVE waits and SSMS slowness
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

PRINT '=== SQL SERVER SERVICE (IFI) ===';
IF COL_LENGTH(N'sys.dm_server_services', N'instant_file_initialization_enabled') IS NOT NULL
BEGIN
    SELECT
        servicename,
        service_account,
        startup_type_desc,
        status_desc,
        instant_file_initialization_enabled,
        CASE instant_file_initialization_enabled
            WHEN N'Y' THEN N'OK'
            ELSE N'ACTION: Grant Perform volume maintenance tasks; restart SQL'
        END AS [IFI_Action]
    FROM sys.dm_server_services
    WHERE servicename LIKE N'SQL Server (%' OR servicename = N'MSSQLSERVER';
END;

PRINT '=== MEMORY MODEL ===';
IF COL_LENGTH(N'sys.dm_os_sys_info', N'sql_memory_model_desc') IS NOT NULL
    SELECT sql_memory_model_desc,
           CASE sql_memory_model_desc
               WHEN N'LOCK_PAGES' THEN N'LPIM enabled'
               ELSE N'Consider LPIM on dedicated production server if paging observed'
           END AS [Note]
    FROM sys.dm_os_sys_info;

PRINT '=== PREEMPTIVE_OS WAIT BREAKDOWN (OS calls inside SQL) ===';
SELECT TOP (20)
    wait_type,
    waiting_tasks_count,
    wait_time_ms / 1000.0 AS [Total_Wait_Sec],
    CAST(wait_time_ms * 1.0 / NULLIF(waiting_tasks_count, 0) AS DECIMAL(18,2)) AS [Avg_Wait_ms],
    CASE
        WHEN wait_type LIKE N'%WRITEFILEGATHER%' THEN N'IFI disabled — zero-fill on file growth'
        WHEN wait_type LIKE N'%AUTHENTICATION%' OR wait_type LIKE N'%LOGON%' THEN N'AD/Windows auth — test SQL login'
        WHEN wait_type LIKE N'%DEVOPS%' OR wait_type LIKE N'%FILE%' THEN N'Filesystem/AV filter driver'
        WHEN wait_type LIKE N'%GETPROCADDRESS%' THEN N'Loaded DLL call — sometimes AV'
        ELSE N'Capture call stack with XE if recurring'
    END AS [Likely_Cause]
FROM sys.dm_os_wait_stats
WHERE wait_type LIKE N'PREEMPTIVE%'
  AND waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;

PRINT '=== OS MEMORY PRESSURE (SQL view) ===';
SELECT
    physical_memory_in_use_kb / 1024 AS [SQL_Physical_Memory_MB],
    memory_utilization_percentage AS [Memory_Util_Pct],
    process_physical_memory_low,
    process_virtual_memory_low,
    CASE
        WHEN process_physical_memory_low = 1 THEN N'OS signaled low memory — check VM RAM and max server memory'
        ELSE N'No low-memory signal from OS'
    END AS [OS_Pressure]
FROM sys.dm_os_process_memory;

PRINT '=== MANUAL OS ACTIONS (cannot automate from T-SQL) ===';
SELECT Action, Detail FROM (VALUES
    (N'Antivirus exclusion', N'Add .mdf, .ldf, .ndf, backup folders; restart AV service'),
    (N'AD latency test', N'Create SQL login; compare SSMS connect + expand time'),
    (N'Disk benchmark', N'Run diskspd on data/log volumes; compare to pre-migration'),
    (N'Filter drivers', N'Check fltmc instances for backup/AV mini-filters'),
    (N'VMware/Hyper-V', N'Align vCPU; use paravirtual SCSI; avoid oversubscribed datastore')
) AS x(Action, Detail);
