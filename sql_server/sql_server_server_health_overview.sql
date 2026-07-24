/*
================================================================================
sql_server_server_health_overview — One-Script Daily Snapshot
================================================================================
Description:
    Simple, standalone T-SQL script that returns overall SQL Server health in
    one pass. No framework install required. Safe for production (read-only).
    PostgreSQL counterpart: postgres/pg_server_health_overview.sql

Reports:
    1.  Instance identity & uptime
    2.  CPU / scheduler pressure
    3.  Memory health
    4.  Key instance configuration
    5.  Database inventory & risk flags
    6.  Database sizes
    7.  TempDB configuration
    8.  Top file I/O latency
    9.  Backup currency
    10. Failed Agent jobs (last 24 hours)
    11. Active blocking
    12. Top wait types (since startup)
    13. Session / connection summary
    14. Always On AG status (when configured)
    15. Quick findings summary

Parameters (edit before running):
    @BackupHoursSLA     - full/diff backup SLA in hours (default 24)
    @LogBackupHoursSLA  - log backup SLA in hours for FULL recovery (default 1)

Prerequisites:
    VIEW SERVER STATE; access to msdb for backups/jobs.
    SQL Server 2016+.

Criticality: High — daily / on-call triage
Author:      Ravi Sharma
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @BackupHoursSLA    INT = 24;
DECLARE @LogBackupHoursSLA INT = 1;
DECLARE @Now               DATETIME2(0) = SYSDATETIME();

-------------------------------------------------------------------------------
-- 1. Instance identity & uptime
-------------------------------------------------------------------------------
PRINT '=== 1. INSTANCE IDENTITY ===';
SELECT
    CAST(SERVERPROPERTY(N'MachineName') AS NVARCHAR(128))        AS [Machine_Name],
    CAST(SERVERPROPERTY(N'ServerName') AS NVARCHAR(128))         AS [Server_Name],
    CAST(SERVERPROPERTY(N'InstanceName') AS NVARCHAR(128))       AS [Instance_Name],
    CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128))     AS [Product_Version],
    CAST(SERVERPROPERTY(N'ProductLevel') AS NVARCHAR(128))       AS [Product_Level],
    CAST(SERVERPROPERTY(N'ProductUpdateLevel') AS NVARCHAR(128)) AS [CU_Level],
    CAST(SERVERPROPERTY(N'Edition') AS NVARCHAR(256))            AS [Edition],
    CAST(SERVERPROPERTY(N'Collation') AS NVARCHAR(128))          AS [Collation],
    si.sqlserver_start_time                                      AS [SQL_Start_Time],
    DATEDIFF(DAY, si.sqlserver_start_time, @Now)                 AS [Uptime_Days],
    DATEDIFF(MINUTE, si.sqlserver_start_time, @Now)              AS [Uptime_Minutes],
    si.cpu_count                                                 AS [Logical_CPUs],
    si.hyperthread_ratio                                         AS [Hyperthread_Ratio],
    CAST(si.physical_memory_kb / 1024.0 AS DECIMAL(18, 1))       AS [Physical_RAM_MB],
    CASE
        WHEN COL_LENGTH(N'sys.dm_os_sys_info', N'sql_memory_model_desc') IS NOT NULL
            THEN (SELECT sql_memory_model_desc FROM sys.dm_os_sys_info)
        ELSE N'N/A'
    END AS [SQL_Memory_Model]
FROM sys.dm_os_sys_info AS si;

-------------------------------------------------------------------------------
-- 2. CPU / scheduler pressure
-------------------------------------------------------------------------------
PRINT '=== 2. CPU / SCHEDULER ===';
;WITH Ring AS
(
    SELECT TOP (1)
        record.value(N'(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', N'int') AS SystemIdle,
        record.value(N'(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', N'int') AS SQLProcessUtilization
    FROM
    (
        SELECT TOP (1) CONVERT(XML, record) AS [record]
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
          AND record LIKE N'%<SystemHealth>%'
        ORDER BY [timestamp] DESC
    ) AS x
)
SELECT
    r.SQLProcessUtilization AS [SQL_CPU_Pct],
    r.SystemIdle            AS [Idle_CPU_Pct],
    100 - r.SystemIdle - r.SQLProcessUtilization AS [Other_Process_CPU_Pct],
    sched.Online_Schedulers,
    sched.Total_Runnable_Tasks,
    sched.Max_Runnable_On_Any_Scheduler,
    CAST(
        CASE
            WHEN r.SQLProcessUtilization > 80 THEN N'WARNING: High SQL CPU'
            WHEN sched.Max_Runnable_On_Any_Scheduler > 10 THEN N'CRITICAL: CPU queue (runnable tasks)'
            WHEN (100 - r.SystemIdle - r.SQLProcessUtilization) > 20 THEN N'WARNING: External CPU contention'
            ELSE N'OK'
        END AS NVARCHAR(100)
    ) AS [CPU_Status]
FROM Ring AS r
CROSS JOIN
(
    SELECT
        SUM(CASE WHEN status = N'VISIBLE ONLINE' THEN 1 ELSE 0 END) AS Online_Schedulers,
        SUM(runnable_tasks_count) AS Total_Runnable_Tasks,
        MAX(runnable_tasks_count) AS Max_Runnable_On_Any_Scheduler
    FROM sys.dm_os_schedulers
    WHERE scheduler_id < 255
) AS sched;

-------------------------------------------------------------------------------
-- 3. Memory health
-------------------------------------------------------------------------------
PRINT '=== 3. MEMORY ===';
DECLARE @TargetMemMB BIGINT =
(
    SELECT cntr_value / 1024
    FROM sys.dm_os_performance_counters
    WHERE counter_name = N'Target Server Memory (KB)'
);
DECLARE @TotalMemMB BIGINT =
(
    SELECT cntr_value / 1024
    FROM sys.dm_os_performance_counters
    WHERE counter_name = N'Total Server Memory (KB)'
);
DECLARE @PLE INT =
(
    SELECT MIN(cntr_value)
    FROM sys.dm_os_performance_counters
    WHERE object_name LIKE N'%Buffer Manager%'
      AND counter_name = N'Page life expectancy'
);
DECLARE @PLEThreshold INT =
    CASE WHEN @TotalMemMB > 0 THEN (@TotalMemMB / 1024 / 4) * 150 ELSE 300 END;
DECLARE @MaxServerMemMB BIGINT =
(
    SELECT CAST(value_in_use AS BIGINT)
    FROM sys.configurations
    WHERE name = N'max server memory (MB)'
);
DECLARE @PhysicalRamMB BIGINT =
(
    SELECT physical_memory_kb / 1024
    FROM sys.dm_os_sys_info
);

SELECT
    @PhysicalRamMB AS [Physical_RAM_MB],
    @MaxServerMemMB AS [Max_Server_Memory_MB],
    @TargetMemMB AS [Target_Server_Memory_MB],
    @TotalMemMB AS [Total_Server_Memory_MB],
    @PLE AS [Page_Life_Expectancy_Sec],
    @PLEThreshold AS [PLE_Threshold_Sec],
    (
        SELECT COUNT(*)
        FROM sys.dm_exec_query_memory_grants
    ) AS [Active_Memory_Grant_Waits],
    CAST(
        CASE
            WHEN EXISTS (SELECT 1 FROM sys.dm_exec_query_memory_grants)
                THEN N'CRITICAL: Queries waiting on memory grants'
            WHEN @PLE < @PLEThreshold
                THEN N'WARNING: Low PLE (buffer pool churn)'
            WHEN @TotalMemMB < (@TargetMemMB * 0.9)
                THEN N'WARNING: Not reaching target memory'
            WHEN @MaxServerMemMB >= @PhysicalRamMB
                THEN N'WARNING: max server memory leaves little/no OS reserve'
            ELSE N'OK'
        END AS NVARCHAR(120)
    ) AS [Memory_Status];

-------------------------------------------------------------------------------
-- 4. Key instance configuration
-------------------------------------------------------------------------------
PRINT '=== 4. KEY CONFIGURATION ===';
SELECT
    c.name AS [Setting],
    c.value_in_use AS [Value_In_Use],
    CAST(
        CASE c.name
            WHEN N'max degree of parallelism' THEN
                CASE WHEN c.value_in_use = 0 THEN N'Review: MAXDOP 0 can over-parallelize'
                     ELSE N'OK / review per NUMA guidance' END
            WHEN N'cost threshold for parallelism' THEN
                CASE WHEN c.value_in_use = 5 THEN N'Review: default CTFP often too low (consider 50+)'
                     ELSE N'OK' END
            WHEN N'optimize for ad hoc workloads' THEN
                CASE WHEN c.value_in_use = 0 THEN N'Review: enable to reduce plan-cache bloat'
                     ELSE N'OK' END
            WHEN N'backup compression default' THEN
                CASE WHEN c.value_in_use = 0 THEN N'Review: enable for smaller/faster backups'
                     ELSE N'OK' END
            WHEN N'remote admin connections' THEN
                CASE WHEN c.value_in_use = 0 THEN N'Review: enable DAC for hung-instance access'
                     ELSE N'OK' END
            WHEN N'max server memory (MB)' THEN
                CASE WHEN c.value_in_use >= (SELECT physical_memory_kb / 1024 FROM sys.dm_os_sys_info)
                         THEN N'WARNING: little/no OS memory reserve'
                     ELSE N'OK' END
            ELSE N'Review'
        END AS NVARCHAR(200)
    ) AS [Note]
FROM sys.configurations AS c
WHERE c.name IN
(
    N'max server memory (MB)',
    N'min server memory (MB)',
    N'max degree of parallelism',
    N'cost threshold for parallelism',
    N'optimize for ad hoc workloads',
    N'backup compression default',
    N'remote admin connections',
    N'fill factor (%)',
    N'blocked process threshold (s)'
)
ORDER BY c.name;

-------------------------------------------------------------------------------
-- 5. Database inventory & risk flags
-------------------------------------------------------------------------------
PRINT '=== 5. DATABASE INVENTORY & RISK FLAGS ===';
SELECT
    d.name AS [Database_Name],
    d.state_desc AS [State],
    d.recovery_model_desc AS [Recovery_Model],
    d.compatibility_level AS [Compat_Level],
    d.page_verify_option_desc AS [Page_Verify],
    d.is_auto_close_on AS [Auto_Close],
    d.is_auto_shrink_on AS [Auto_Shrink],
    d.is_auto_create_stats_on AS [Auto_Create_Stats],
    d.is_auto_update_stats_on AS [Auto_Update_Stats],
    d.is_read_only AS [Read_Only],
    d.is_trustworthy_on AS [Trustworthy],
    d.is_query_store_on AS [Query_Store],
    CAST(
        CASE
            WHEN d.state <> 0 THEN N'CRITICAL: Not ONLINE'
            WHEN d.is_auto_shrink_on = 1 OR d.is_auto_close_on = 1 THEN N'CRITICAL: Auto-Shrink/Close ON'
            WHEN d.page_verify_option_desc <> N'CHECKSUM' THEN N'CRITICAL: Page Verify not CHECKSUM'
            WHEN d.is_trustworthy_on = 1 AND d.database_id > 4 THEN N'WARNING: TRUSTWORTHY ON'
            WHEN d.is_auto_update_stats_on = 0 THEN N'WARNING: Auto Update Stats OFF'
            ELSE N'OK'
        END AS NVARCHAR(80)
    ) AS [Health_Flag]
FROM sys.databases AS d
ORDER BY
    CASE
        WHEN d.state <> 0 THEN 0
        WHEN d.is_auto_shrink_on = 1 OR d.is_auto_close_on = 1 THEN 1
        WHEN d.page_verify_option_desc <> N'CHECKSUM' THEN 2
        ELSE 3
    END,
    d.name;

-------------------------------------------------------------------------------
-- 6. Database sizes
-------------------------------------------------------------------------------
PRINT '=== 6. DATABASE SIZES ===';
SELECT
    d.name AS [Database_Name],
    CAST(SUM(CASE WHEN mf.type_desc = N'ROWS' THEN mf.size END) * 8.0 / 1024 AS DECIMAL(18, 1)) AS [Data_MB],
    CAST(SUM(CASE WHEN mf.type_desc = N'LOG' THEN mf.size END) * 8.0 / 1024 AS DECIMAL(18, 1)) AS [Log_MB],
    CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(18, 1)) AS [Total_MB]
FROM sys.databases AS d
INNER JOIN sys.master_files AS mf ON d.database_id = mf.database_id
WHERE d.state = 0
GROUP BY d.name
ORDER BY [Total_MB] DESC;

-------------------------------------------------------------------------------
-- 7. TempDB configuration
-------------------------------------------------------------------------------
PRINT '=== 7. TEMPDB ===';
SELECT
    mf.name AS [Logical_Name],
    mf.type_desc AS [File_Type],
    mf.physical_name AS [Physical_Path],
    CAST(mf.size * 8.0 / 1024 AS DECIMAL(18, 1)) AS [Size_MB],
    CASE
        WHEN mf.is_percent_growth = 1 THEN CAST(mf.growth AS VARCHAR(20)) + N'%'
        ELSE CAST(mf.growth * 8 / 1024 AS VARCHAR(20)) + N' MB'
    END AS [Autogrowth],
    mf.max_size AS [Max_Size_Pages]
FROM sys.master_files AS mf
WHERE mf.database_id = 2
ORDER BY mf.type_desc, mf.file_id;

SELECT
    COUNT(*) AS [TempDB_Data_Files],
    COUNT(DISTINCT size) AS [Distinct_Sizes],
    CAST(
        CASE
            WHEN COUNT(*) < (SELECT CASE WHEN cpu_count > 8 THEN 8 ELSE cpu_count END FROM sys.dm_os_sys_info)
                THEN N'Review: fewer data files than recommended (often 1 per logical CPU, cap 8)'
            WHEN COUNT(DISTINCT size) > 1
                THEN N'WARNING: data files are not equal size'
            ELSE N'OK'
        END AS NVARCHAR(120)
    ) AS [TempDB_Status]
FROM sys.master_files
WHERE database_id = 2
  AND type_desc = N'ROWS';

-------------------------------------------------------------------------------
-- 8. Top file I/O latency
-------------------------------------------------------------------------------
PRINT '=== 8. TOP FILE I/O LATENCY ===';
SELECT TOP (15)
    DB_NAME(vfs.database_id) AS [Database_Name],
    mf.name AS [Logical_File],
    mf.type_desc AS [File_Type],
    vfs.num_of_reads AS [Reads],
    vfs.num_of_writes AS [Writes],
    CAST(vfs.io_stall_read_ms * 1.0 / NULLIF(vfs.num_of_reads, 0) AS DECIMAL(18, 1)) AS [Avg_Read_Stall_ms],
    CAST(vfs.io_stall_write_ms * 1.0 / NULLIF(vfs.num_of_writes, 0) AS DECIMAL(18, 1)) AS [Avg_Write_Stall_ms],
    CAST(vfs.io_stall * 1.0 / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) AS DECIMAL(18, 1)) AS [Avg_IO_Stall_ms],
    CAST(
        CASE
            WHEN vfs.io_stall * 1.0 / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) > 20 THEN N'CRITICAL'
            WHEN vfs.io_stall * 1.0 / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) > 15 THEN N'WARNING'
            ELSE N'OK'
        END AS NVARCHAR(20)
    ) AS [IO_Status]
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
INNER JOIN sys.master_files AS mf
    ON vfs.database_id = mf.database_id
   AND vfs.file_id = mf.file_id
WHERE vfs.num_of_reads + vfs.num_of_writes > 0
ORDER BY [Avg_IO_Stall_ms] DESC;

-------------------------------------------------------------------------------
-- 9. Backup currency
-------------------------------------------------------------------------------
PRINT '=== 9. BACKUP CURRENCY ===';
;WITH LastBackups AS
(
    SELECT
        database_name,
        MAX(CASE WHEN type = N'D' THEN backup_finish_date END) AS Last_Full_Backup,
        MAX(CASE WHEN type = N'I' THEN backup_finish_date END) AS Last_Diff_Backup,
        MAX(CASE WHEN type = N'L' THEN backup_finish_date END) AS Last_Log_Backup
    FROM msdb.dbo.backupset WITH (NOLOCK)
    GROUP BY database_name
)
SELECT
    d.name AS [Database_Name],
    d.recovery_model_desc AS [Recovery_Model],
    lb.Last_Full_Backup,
    lb.Last_Diff_Backup,
    lb.Last_Log_Backup,
    DATEDIFF(HOUR, COALESCE(lb.Last_Diff_Backup, lb.Last_Full_Backup), @Now) AS [Hours_Since_Full_Or_Diff],
    DATEDIFF(HOUR, lb.Last_Log_Backup, @Now) AS [Hours_Since_Log],
    CAST(
        CASE
            WHEN d.state <> 0 THEN N'N/A (not online)'
            WHEN lb.Last_Full_Backup IS NULL THEN N'CRITICAL: No full backup found'
            WHEN DATEDIFF(HOUR, COALESCE(lb.Last_Diff_Backup, lb.Last_Full_Backup), @Now) > @BackupHoursSLA
                THEN N'CRITICAL: Full/diff older than SLA'
            WHEN d.recovery_model_desc = N'FULL' AND lb.Last_Log_Backup IS NULL
                THEN N'WARNING: FULL recovery with no log backup'
            WHEN d.recovery_model_desc = N'FULL'
             AND DATEDIFF(HOUR, lb.Last_Log_Backup, @Now) > @LogBackupHoursSLA
                THEN N'WARNING: Log backup older than SLA'
            ELSE N'OK'
        END AS NVARCHAR(80)
    ) AS [Backup_Status]
FROM sys.databases AS d
LEFT JOIN LastBackups AS lb ON d.name = lb.database_name
WHERE d.database_id > 4
ORDER BY
    CASE
        WHEN lb.Last_Full_Backup IS NULL THEN 0
        WHEN DATEDIFF(HOUR, COALESCE(lb.Last_Diff_Backup, lb.Last_Full_Backup), @Now) > @BackupHoursSLA THEN 1
        ELSE 2
    END,
    d.name;

-------------------------------------------------------------------------------
-- 10. Failed Agent jobs (last 24 hours)
-------------------------------------------------------------------------------
PRINT '=== 10. FAILED AGENT JOBS (LAST 24 HOURS) ===';
SELECT
    j.name AS [Job_Name],
    h.step_id AS [Step_Id],
    h.step_name AS [Step_Name],
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS [Run_DateTime],
    CASE h.run_status
        WHEN 0 THEN N'FAILED'
        WHEN 2 THEN N'RETRY'
        WHEN 3 THEN N'CANCELLED'
        ELSE CAST(h.run_status AS NVARCHAR(10))
    END AS [Status],
    LEFT(h.message, 400) AS [Message]
FROM msdb.dbo.sysjobhistory AS h
INNER JOIN msdb.dbo.sysjobs AS j ON h.job_id = j.job_id
WHERE h.run_status IN (0, 2, 3)
  AND h.step_id > 0
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time) >= DATEADD(HOUR, -24, @Now)
ORDER BY [Run_DateTime] DESC;

IF @@ROWCOUNT = 0
    PRINT 'No failed/retry/cancelled job steps in the last 24 hours.';

-------------------------------------------------------------------------------
-- 11. Active blocking
-------------------------------------------------------------------------------
PRINT '=== 11. ACTIVE BLOCKING ===';
SELECT
    r.session_id AS [Session_Id],
    r.blocking_session_id AS [Blocking_Session_Id],
    r.wait_type AS [Wait_Type],
    r.wait_time AS [Wait_ms],
    r.wait_resource AS [Wait_Resource],
    DB_NAME(r.database_id) AS [Database_Name],
    s.login_name AS [Login_Name],
    s.host_name AS [Host_Name],
    s.program_name AS [Program_Name],
    SUBSTRING
    (
        st.text,
        (r.statement_start_offset / 2) + 1,
        CASE
            WHEN r.statement_end_offset = -1 THEN LEN(CONVERT(NVARCHAR(MAX), st.text))
            ELSE (r.statement_end_offset - r.statement_start_offset) / 2 + 1
        END
    ) AS [Current_Statement]
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.blocking_session_id <> 0
   OR r.session_id IN
   (
       SELECT DISTINCT blocking_session_id
       FROM sys.dm_exec_requests
       WHERE blocking_session_id <> 0
   )
ORDER BY r.wait_time DESC;

IF @@ROWCOUNT = 0
    PRINT 'No active blocking at this moment.';

-------------------------------------------------------------------------------
-- 12. Top wait types (since startup)
-------------------------------------------------------------------------------
PRINT '=== 12. TOP WAIT TYPES (SINCE STARTUP) ===';
SELECT TOP (15)
    ws.wait_type AS [Wait_Type],
    ws.waiting_tasks_count AS [Wait_Count],
    CAST(ws.wait_time_ms / 1000.0 AS DECIMAL(18, 1)) AS [Total_Wait_Sec],
    CAST((ws.wait_time_ms - ws.signal_wait_time_ms) / 1000.0 AS DECIMAL(18, 1)) AS [Resource_Wait_Sec],
    CAST(ws.signal_wait_time_ms / 1000.0 AS DECIMAL(18, 1)) AS [Signal_Wait_Sec],
    CAST(ws.wait_time_ms * 100.0 / NULLIF(SUM(ws.wait_time_ms) OVER (), 0) AS DECIMAL(5, 2)) AS [Pct_Of_Total],
    CAST(
        CASE
            WHEN ws.wait_type LIKE N'LCK%' THEN N'Blocking / locking'
            WHEN ws.wait_type LIKE N'PAGEIOLATCH%' OR ws.wait_type IN (N'WRITELOG', N'IO_COMPLETION')
                THEN N'Storage / log I/O'
            WHEN ws.wait_type LIKE N'RESOURCE_SEMAPHORE%' THEN N'Memory grant pressure'
            WHEN ws.wait_type IN (N'CXPACKET', N'CXCONSUMER', N'EXECSYNC') THEN N'Parallelism'
            WHEN ws.wait_type = N'SOS_SCHEDULER_YIELD' THEN N'CPU pressure'
            WHEN ws.wait_type = N'THREADPOOL' THEN N'CRITICAL: worker exhaustion'
            WHEN ws.wait_type = N'ASYNC_NETWORK_IO' THEN N'Client / network slow consume'
            WHEN ws.wait_type LIKE N'HADR%' THEN N'Always On'
            ELSE N'Review wait meaning'
        END AS NVARCHAR(80)
    ) AS [Category]
FROM sys.dm_os_wait_stats AS ws
WHERE ws.waiting_tasks_count > 0
  AND ws.wait_type NOT IN
  (
      N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH',
      N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE', N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT',
      N'CLR_SEMAPHORE', N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE',
      N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',
      N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
      N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT', N'HADR_NOTIFICATION_DEQUEUE',
      N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE', N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP',
      N'LOGMGR_QUEUE', N'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE',
      N'PARALLEL_REDO_DRAIN_WORKER', N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST',
      N'PARALLEL_REDO_WORKER_SYNC', N'PARALLEL_REDO_WORKER_WAIT_WORK',
      N'PREEMPTIVE_XE_GETTARGETSTATE', N'QDS_ASYNC_QUEUE',
      N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
      N'QDS_SHUTDOWN_QUEUE', N'REDO_THREAD_PENDING_WORK', N'REQUEST_FOR_DEADLOCK_SEARCH',
      N'RESOURCE_QUEUE', N'SERVER_IDLE_TASK', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP',
      N'SLEEP_DCOMSTARTUP', N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY', N'SLEEP_MASTERUPGRADED',
      N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TASK', N'SLEEP_TEMPDBSTARTUP',
      N'SNI_HTTP_ACCEPT', N'SOS_WORK_DISPATCHER', N'SP_SERVER_DIAGNOSTICS_SLEEP',
      N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES',
      N'WAIT_FOR_RESULTS', N'WAITFOR', N'XE_DISPATCHER_JOIN', N'XE_DISPATCHER_WAIT',
      N'XE_TIMER_EVENT'
  )
ORDER BY ws.wait_time_ms DESC;

-------------------------------------------------------------------------------
-- 13. Session / connection summary
-------------------------------------------------------------------------------
PRINT '=== 13. SESSIONS / CONNECTIONS ===';
SELECT
    COUNT(*) AS [User_Sessions],
    SUM(CASE WHEN s.status = N'running' THEN 1 ELSE 0 END) AS [Running],
    SUM(CASE WHEN s.status = N'sleeping' THEN 1 ELSE 0 END) AS [Sleeping],
    SUM(CASE WHEN r.status = N'suspended' THEN 1 ELSE 0 END) AS [Suspended_Requests],
    SUM(CASE WHEN r.blocking_session_id > 0 THEN 1 ELSE 0 END) AS [Blocked_Requests],
    MAX(r.open_transaction_count) AS [Max_Open_Tran_Count]
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r ON s.session_id = r.session_id
WHERE s.is_user_process = 1;

SELECT TOP (20)
    s.session_id AS [Session_Id],
    s.login_name AS [Login_Name],
    s.host_name AS [Host_Name],
    s.program_name AS [Program_Name],
    DB_NAME(r.database_id) AS [Database_Name],
    r.status AS [Request_Status],
    r.command AS [Command],
    r.wait_type AS [Wait_Type],
    r.wait_time AS [Wait_ms],
    r.cpu_time AS [CPU_ms],
    r.logical_reads AS [Logical_Reads],
    r.total_elapsed_time AS [Elapsed_ms]
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_requests AS r ON s.session_id = r.session_id
WHERE s.is_user_process = 1
  AND s.session_id <> @@SPID
ORDER BY r.total_elapsed_time DESC;

-------------------------------------------------------------------------------
-- 14. Always On AG status (when configured)
-------------------------------------------------------------------------------
PRINT '=== 14. ALWAYS ON AG STATUS ===';
IF SERVERPROPERTY(N'IsHadrEnabled') = 1
BEGIN
    SELECT
        ag.name AS [AG_Name],
        ar.replica_server_name AS [Replica],
        ars.role_desc AS [Role],
        ars.operational_state_desc AS [Operational_State],
        ars.connected_state_desc AS [Connected_State],
        ars.synchronization_health_desc AS [Sync_Health],
        ars.last_connect_error_description AS [Last_Connect_Error]
    FROM sys.availability_groups AS ag
    INNER JOIN sys.availability_replicas AS ar ON ag.group_id = ar.group_id
    INNER JOIN sys.dm_hadr_availability_replica_states AS ars
        ON ar.replica_id = ars.replica_id
    ORDER BY ag.name, ars.role_desc;

    SELECT
        DB_NAME(drs.database_id) AS [Database_Name],
        ar.replica_server_name AS [Replica],
        drs.synchronization_state_desc AS [Sync_State],
        drs.synchronization_health_desc AS [Sync_Health],
        drs.is_suspended AS [Is_Suspended],
        drs.suspend_reason_desc AS [Suspend_Reason],
        drs.log_send_queue_size AS [Log_Send_Queue_KB],
        drs.redo_queue_size AS [Redo_Queue_KB]
    FROM sys.dm_hadr_database_replica_states AS drs
    INNER JOIN sys.availability_replicas AS ar ON drs.replica_id = ar.replica_id
    ORDER BY [Database_Name], ar.replica_server_name;
END
ELSE
    PRINT 'Always On AG is not enabled on this instance.';

-------------------------------------------------------------------------------
-- 15. Quick findings summary
-------------------------------------------------------------------------------
PRINT '=== 15. QUICK FINDINGS SUMMARY ===';
;WITH Issues AS
(
    SELECT N'CPU' AS [Area],
           CASE
               WHEN EXISTS
               (
                   SELECT 1
                   FROM sys.dm_os_schedulers
                   WHERE status = N'VISIBLE ONLINE' AND runnable_tasks_count > 10
               ) THEN N'CRITICAL'
               ELSE N'OK'
           END AS [Status],
           N'Runnable tasks > 10 on a scheduler' AS [Check]
    UNION ALL
    SELECT N'Memory',
           CASE
               WHEN EXISTS (SELECT 1 FROM sys.dm_exec_query_memory_grants) THEN N'CRITICAL'
               WHEN @PLE < @PLEThreshold THEN N'WARNING'
               ELSE N'OK'
           END,
           N'Memory grants / low PLE'
    UNION ALL
    SELECT N'Config',
           CASE
               WHEN EXISTS
               (
                   SELECT 1
                   FROM sys.databases
                   WHERE database_id > 4
                     AND state = 0
                     AND (is_auto_shrink_on = 1 OR is_auto_close_on = 1 OR page_verify_option_desc <> N'CHECKSUM')
               ) THEN N'CRITICAL'
               ELSE N'OK'
           END,
           N'Auto-shrink/close or page verify'
    UNION ALL
    SELECT N'Backup',
           CASE
               WHEN EXISTS
               (
                   SELECT 1
                   FROM sys.databases AS d
                   LEFT JOIN
                   (
                       SELECT
                           database_name,
                           MAX(CASE WHEN type IN (N'D', N'I') THEN backup_finish_date END) AS Last_Data_Backup
                       FROM msdb.dbo.backupset WITH (NOLOCK)
                       GROUP BY database_name
                   ) AS b ON d.name = b.database_name
                   WHERE d.database_id > 4
                     AND d.state = 0
                     AND
                     (
                         b.Last_Data_Backup IS NULL
                         OR DATEDIFF(HOUR, b.Last_Data_Backup, @Now) > @BackupHoursSLA
                     )
               ) THEN N'CRITICAL'
               ELSE N'OK'
           END,
           N'Full/diff backup within SLA'
    UNION ALL
    SELECT N'Blocking',
           CASE
               WHEN EXISTS
               (
                   SELECT 1
                   FROM sys.dm_exec_requests
                   WHERE blocking_session_id <> 0
               ) THEN N'WARNING'
               ELSE N'OK'
           END,
           N'Active blocking chains'
    UNION ALL
    SELECT N'Jobs',
           CASE
               WHEN EXISTS
               (
                   SELECT 1
                   FROM msdb.dbo.sysjobhistory AS h
                   WHERE h.run_status = 0
                     AND h.step_id > 0
                     AND msdb.dbo.agent_datetime(h.run_date, h.run_time) >= DATEADD(HOUR, -24, @Now)
               ) THEN N'WARNING'
               ELSE N'OK'
           END,
           N'Failed job steps in last 24h'
)
SELECT
    [Area],
    [Status],
    [Check],
    CASE [Status]
        WHEN N'CRITICAL' THEN 1
        WHEN N'WARNING' THEN 2
        ELSE 3
    END AS [Sort]
FROM Issues
ORDER BY [Sort], [Area];

PRINT '=== SERVER HEALTH OVERVIEW COMPLETE ===';
PRINT 'For scored findings with recommendations: EXEC dbo.sp_DBA_HealthCheck @DeepDive = 0;';
PRINT 'For deeper area drills, use folders 01_Server_OS through 09_Maintenance.';
