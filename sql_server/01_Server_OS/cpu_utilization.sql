/*
================================================================================
Purpose:        Analyzes historical CPU usage from OS ring buffers and evaluates 
                current thread scheduling health via Signal Wait ratio.
Provides:       Historical CPU metrics (last ~256 mins), Signal Wait Pct, 
                Scheduler Health (runnable tasks).
Importance:     CPU is a critical resource; high utilization or scheduling pressure 
                directly impacts query performance and instance stability.
 Interpretation: Historical CPU > 80% requires investigation. Signal Waits > 25% 
                indicates CPU bottleneck. Runnable tasks > 10 is critical CPU starvation.
Action:         If Historical CPU > 80%, identify top resource consumers via top_resource_queries.sql. If Signal Wait % > 25%, review MAXDOP and Cost Threshold for Parallelism settings via server_configuration_audit.sql. If Runnable Tasks > 10 sustained, CPU is oversubscribed — reduce parallelism or add cores.
Criticality:    High
Prerequisites:  VIEW SERVER STATE permission. Optional dbo.fn_DBA_ExcludedWaitTypes
                in current database or DBARepository for centralized wait filtering.
Persistence:    None. Uses only session-scoped #ExcludedWaitTypes when needed.
Safety:         Read-only DMV/ring-buffer queries; no permanent objects are created.
Author:        Ravi Sharma
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'tempdb..#ExcludedWaitTypes', N'U') IS NOT NULL
    DROP TABLE #ExcludedWaitTypes;

CREATE TABLE #ExcludedWaitTypes
(
    wait_type NVARCHAR(60) NOT NULL PRIMARY KEY
);

DECLARE @CurrentDbExcludedWaitFunction INT = OBJECT_ID(N'dbo.fn_DBA_ExcludedWaitTypes', N'IF');
DECLARE @DbaRepositoryExcludedWaitFunction INT = NULL;
DECLARE @ExcludedWaitSource NVARCHAR(256) = N'Inline fallback';

IF DB_ID(N'DBARepository') IS NOT NULL
BEGIN
    SET @DbaRepositoryExcludedWaitFunction = OBJECT_ID(N'DBARepository.dbo.fn_DBA_ExcludedWaitTypes', N'IF');
END;

IF @CurrentDbExcludedWaitFunction IS NOT NULL
BEGIN
    INSERT INTO #ExcludedWaitTypes (wait_type)
    EXEC sys.sp_executesql N'SELECT DISTINCT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes() WHERE wait_type IS NOT NULL;';

    SET @ExcludedWaitSource = DB_NAME() + N'.dbo.fn_DBA_ExcludedWaitTypes';
END
ELSE IF @DbaRepositoryExcludedWaitFunction IS NOT NULL
BEGIN
    INSERT INTO #ExcludedWaitTypes (wait_type)
    EXEC sys.sp_executesql N'SELECT DISTINCT wait_type FROM DBARepository.dbo.fn_DBA_ExcludedWaitTypes() WHERE wait_type IS NOT NULL;';

    SET @ExcludedWaitSource = N'DBARepository.dbo.fn_DBA_ExcludedWaitTypes';
END;

IF NOT EXISTS (SELECT 1 FROM #ExcludedWaitTypes)
BEGIN
    INSERT INTO #ExcludedWaitTypes (wait_type)
    VALUES
        (N'BROKER_EVENTHANDLER'), (N'BROKER_RECEIVE_WAITFOR'), (N'BROKER_TASK_STOP'), (N'BROKER_TO_FLUSH'),
        (N'BROKER_TRANSMITTER'), (N'CHECKPOINT_QUEUE'), (N'CHKPT'), (N'CLR_AUTO_EVENT'), (N'CLR_MANUAL_EVENT'),
        (N'CLR_SEMAPHORE'), (N'DBMIRROR_DBM_EVENT'), (N'DBMIRROR_EVENTS_QUEUE'), (N'DBMIRROR_WORKER_QUEUE'),
        (N'DBMIRRORING_CMD'), (N'DIRTY_PAGE_POLL'), (N'DIRTY_PAGE_TABLE_RELEASE'), (N'DISPATCHER_QUEUE_SEMAPHORE'), (N'EXECSYNC'),
        (N'FSAGENT'), (N'FT_IFTS_SCHEDULER_IDLE_WAIT'), (N'FT_IFTS_SCHEDULER_VAL_KEEP_ALIVE'), (N'FT_IFTSHC_MUTEX'),
        (N'HADR_FABRIC_CALLBACK_EVENT'), (N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'),
        (N'HADR_LOGCAPTURE_WAIT'), (N'HADR_NOTIFICATION_DEQUEUE'), (N'HADR_TIMER_TASK'), (N'HADR_WORK_QUEUE'),
        (N'KSOURCE_WAKEUP'), (N'LAZYWRITER_SLEEP'), (N'LOGMGR_QUEUE'), (N'MEMORY_ALLOCATION_EXT'),
        (N'ONDEMAND_TASK_QUEUE'), (N'PARALLEL_REDO_DRAIN_WORKER'), (N'PARALLEL_REDO_LOG_CACHE'),
        (N'PARALLEL_REDO_TRAN_LIST'), (N'PARALLEL_REDO_WORKER_SYNC'), (N'PARALLEL_REDO_WORKER_WAIT_WORK'),
        (N'PREEMPTIVE_OS_AUTHENTICATIONOPS'), (N'PREEMPTIVE_OS_FLUSHFILEBUFFERS'), (N'PREEMPTIVE_XE_GETTARGETSTATE'),
        (N'PVS_PREALLOCATE'), (N'PWAIT_ALL_COMPONENTS_INITIALIZED'), (N'PWAIT_DIRECTLOGCONSUMER_GETNEXT'),
        (N'QDS_ASYNC_QUEUE'), (N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP'),
        (N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP'), (N'QDS_SHUTDOWN_QUEUE'), (N'REDO_THREAD_PENDING_WORK'),
        (N'REQUEST_FOR_DEADLOCK_SEARCH'), (N'RESOURCE_QUEUE'), (N'SERVER_IDLE_TASK'), (N'SERVER_IDLE_CHECK'),
        (N'SLEEP_BPOOL_FLUSH'), (N'SLEEP_DBSTARTUP'), (N'SLEEP_DCOMSTARTUP'), (N'SLEEP_MASTERDBREADY'),
        (N'SLEEP_MASTERMDREADY'), (N'SLEEP_MASTERUPGRADED'), (N'SLEEP_MSDBSTARTUP'), (N'SLEEP_SYSTEMTASK'),
        (N'SLEEP_TASK'), (N'SLEEP_TEMPDBSTARTUP'), (N'SNI_HTTP_ACCEPT'), (N'SOS_WORK_DISPATCHER'),
        (N'SP_SERVER_DIAGNOSTICS_SLEEP'), (N'SQLTRACE_BUFFER_FLUSH'), (N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP'),
        (N'SQLTRACE_WAIT_ENTRIES'), (N'WAIT_FOR_RESULTS'), (N'WAITFOR'), (N'WAITFOR_TASKSHUTDOWN'),
        (N'WAIT_XTP_HOST_WAIT'), (N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG'), (N'WAIT_XTP_CKPT_CLOSE'), (N'WAIT_XTP_RECOVERY'),
        (N'XE_BUFFERMGR_ALLPROCESSED_EVENT'), (N'XE_DISPATCHER_JOIN'), (N'XE_DISPATCHER_WAIT'),
        (N'XE_FILE_TARGET_TVF'), (N'XE_LIVE_TARGET_TVF'), (N'XE_TIMER_EVENT');
END;

PRINT N'Excluded wait filter source: ' + @ExcludedWaitSource;

-- 1. Historical CPU Usage from System Health Ring Buffer
DECLARE @ts_now BIGINT;
SELECT @ts_now = cpu_ticks / (cpu_ticks / ms_ticks) 
FROM sys.dm_os_sys_info WITH (NOLOCK);

SELECT TOP (256)
    DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) AS [Event_Time],
    SQLProcessUtilization AS [SQL_Server_CPU_Pct],
    SystemIdle AS [System_Idle_Pct],
    100 - SystemIdle - SQLProcessUtilization AS [Other_Process_CPU_Pct],
    CAST('Historical CPU metrics parsed from SQL Server system ring buffers. ' + 
         'Threshold: Sustained CPU > 80% requires investigation. ' +
         'Recommendation: If Other Process CPU is high, check external processes (e.g., antivirus, backups). ' +
         'If SQL Server CPU is high, check top resource-consuming queries and missing indexes.' 
         AS VARCHAR(1000)) AS [Metric_Context]
FROM (
    SELECT 
        rb_record.record.value('(./Record/@id)[1]', 'int') AS [Record_Id],
        rb_record.record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS [SystemIdle],
        rb_record.record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS [SQLProcessUtilization],
        rb_record.[timestamp] AS [timestamp]
    FROM (
        SELECT 
            rb.[timestamp] AS [timestamp],
            CONVERT(xml, rb.record) AS [record]
        FROM sys.dm_os_ring_buffers AS rb WITH (NOLOCK)
        WHERE rb.ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
          AND rb.record LIKE N'%<SystemHealth>%'
    ) AS rb_record
) AS y
ORDER BY [Event_Time] DESC;

-- 2. Signal Wait Ratio (CPU Scheduling Pressure)
SELECT 
    SUM(signal_wait_time_ms) AS [Signal_Wait_Time_ms],
    SUM(wait_time_ms) AS [Total_Wait_Time_ms],
    CAST(CAST(SUM(signal_wait_time_ms) AS NUMERIC(18,2)) / 
         NULLIF(SUM(wait_time_ms), 0) * 100 AS DECIMAL(5,2)) AS [Signal_Wait_Pct],
    CAST('Signal wait time measures the time a thread had to wait in the runnable queue after its resource became available. ' +
         'Threshold: Signal Waits > 25% of Total Waits indicates significant CPU bottleneck / scheduling pressure. ' +
         'Recommendation: If > 25%, look into parallelism configurations (MAXDOP, Cost Threshold), compile locks, or CPU capacity scaling.' 
         AS VARCHAR(1000)) AS [Metric_Context]
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    SELECT excluded_waits.wait_type FROM #ExcludedWaitTypes AS excluded_waits
);

-- 3. Scheduler Pressure (Runnable Tasks)
PRINT '--- Scheduler Health & Runnable Tasks ---';
SELECT 
    parent_node_id AS [Parent_Node_Id],
    scheduler_id AS [Scheduler_Id],
    cpu_id AS [Cpu_Id],
    status AS [Status],
    is_online AS [Is_Online],
    runnable_tasks_count AS [Runnable_Tasks_Count],
    current_workers_count AS [Current_Workers_Count],
    CASE 
        WHEN runnable_tasks_count > 10 THEN '🔴 CRITICAL: High runnable tasks indicating CPU starvation.'
        WHEN runnable_tasks_count > 0 THEN '🟡 WARNING: Threads are waiting for CPU cycles.'
        ELSE '🟢 OPTIMAL'
    END AS [Scheduler_Status]
FROM sys.dm_os_schedulers
WHERE status = 'VISIBLE ONLINE';
