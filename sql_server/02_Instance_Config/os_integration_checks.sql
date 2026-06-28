/*
================================================================================
Purpose:        Verifies if Instant File Initialization (IFI) and Lock Pages in 
                Memory (LPIM) are properly configured for the service account.
Provides:       IFI enabled status, SQL Server memory model (LPIM status).
Importance:     IFI speeds up file growth/creation; LPIM prevents OS from paging 
                SQL memory, ensuring stable performance.
 Interpretation: IFI_Enabled should be "Y". Memory_Model should be "LOCK_PAGES".
Action:         If IFI_Enabled = 'N', grant 'Perform Volume Maintenance Tasks' to the SQL service account and restart. If Memory_Model is not 'LOCK_PAGES', grant 'Lock Pages in Memory' to the SQL service account and restart.
Criticality:    Medium
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

-- 1. Check Instant File Initialization (IFI) - Available on SQL Server 2016 SP1 and newer
IF COL_LENGTH(N'sys.dm_server_services', N'instant_file_initialization_enabled') IS NOT NULL
BEGIN
    SELECT 
        servicename AS [Service_Name],
        startup_type_desc AS [Startup_Type],
        status_desc AS [Service_Status],
        instant_file_initialization_enabled AS [IFI_Enabled],
        CAST('Instant File Initialization allows SQL Server to skip zeroing out disk space for data files. ' +
             'Threshold: IFI_Enabled should be "Y". ' +
             'Recommendation: If "N", grant the service account "Perform Volume Maintenance Tasks" privilege (SE_MANAGE_VOLUME_NAME) in local security policy and restart SQL Server.'
             AS VARCHAR(1000)) AS [Metric_Context]
    FROM sys.dm_server_services WITH (NOLOCK)
    WHERE servicename LIKE 'SQL Server (%)' OR servicename = 'MSSQLSERVER';
END
ELSE
    PRINT 'Instant File Initialization status requires SQL Server 2016 SP1 or newer.';

-- 2. Check Lock Pages in Memory (LPIM) Memory Model (sql_memory_model columns: SQL Server 2019+)
IF COL_LENGTH(N'sys.dm_os_sys_info', N'sql_memory_model_desc') IS NOT NULL
BEGIN
    SELECT 
        sql_memory_model AS [Memory_Model_ID],
        sql_memory_model_desc AS [Memory_Model_Description],
        CAST('Lock Pages in Memory prevents the operating system from paging SQL Server memory to disk. ' +
             'Threshold: Ideally "LOCK_PAGES" (LPIM enabled) or "CONVENTIONAL" (standard memory allocations, check if paging occurs). ' +
             'Recommendation: If "CONVENTIONAL" and OS memory pressure is frequent, grant "Lock Pages in Memory" privilege (SE_LOCK_MEMORY_NAME) in local security policy to the service account and restart.'
             AS VARCHAR(1000)) AS [Metric_Context]
    FROM sys.dm_os_sys_info WITH (NOLOCK);
END
ELSE
    PRINT 'sql_memory_model_desc is not available on this version (requires SQL Server 2019+). Check LPIM via service account privileges and sys.dm_os_process_memory.';

-- 3. Active Global Trace Flags
PRINT '--- Global Trace Flags Audit ---';
DBCC TRACESTATUS(-1);

/*
Expert Recommended Trace Flags:
- TF 1222: Capture deadlock graph in error log.
- TF 3226: Suppress successful backup log messages.
- TF 2371: Dynamic statistics update threshold (pre-2016).
*/
