/*
================================================================================
Purpose:        Collects cumulative instance-wide wait statistics, filtering out 
                benign background system waits to highlight active bottlenecks.
Provides:       Wait types, wait times (total, resource, signal), wait counts, 
                percentage of total waits, and best practice recommendations.
Importance:     Critical for identifying the primary hardware or configuration 
                bottleneck (CPU, I/O, Memory, Locking) affecting the instance.
Interpretation: Focus on wait types with the highest "Percentage_Of_Total_Waits". 
                 The top 3-5 types typically represent 80%+ of total wait time.
Action: Focus on the top 3-5 wait types — they represent 80%+ of total wait time. Common patterns: PAGEIOLATCH_XX = disk I/O bottleneck (run disk_latency.sql), LCK_M_XX = blocking (run blocking_and_deadlocks.sql), SOS_SCHEDULER_YIELD = CPU pressure (run cpu_utilization.sql), RESOURCE_SEMAPHORE = memory pressure (run memory_diagnostics.sql). See wait_statistics_reference.sql for detailed investigation commands per wait type.
Criticality:    High
Prerequisites:  VIEW SERVER STATE permission. Optional dbo.fn_DBA_ExcludedWaitTypes
                in current database or DBARepository for centralized wait filtering.
Persistence:    None. Uses only session-scoped #ExcludedWaitTypes when needed.
Safety:         Read-only DMV queries; no permanent objects are created.
Author:        Ravi Sharma
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

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

SELECT 
    osi.sqlserver_start_time AS [Instance_Start_Time],
    N'Wait stats are cumulative since this time.' AS [Metric_Context]
FROM sys.dm_os_sys_info AS osi;

WITH [WaitStats] AS (
    SELECT 
        ws.wait_type AS [wait_type],
        ws.wait_time_ms / 1000.0 AS [Wait_S],
        (ws.wait_time_ms - ws.signal_wait_time_ms) / 1000.0 AS [Resource_S],
        ws.signal_wait_time_ms / 1000.0 AS [Signal_S],
        ws.waiting_tasks_count AS [Wait_Count],
        ROW_NUMBER() OVER(ORDER BY ws.wait_time_ms DESC) AS [Row_Num]
    FROM sys.dm_os_wait_stats AS ws
    WHERE ws.wait_type NOT IN (SELECT excluded_waits.wait_type FROM #ExcludedWaitTypes AS excluded_waits)
      AND ws.waiting_tasks_count > 0
)
SELECT 
    W1.wait_type AS [Wait_Type],
    CAST(W1.Wait_S AS DECIMAL(14, 2)) AS [Wait_Sec],
    CAST(W1.Resource_S AS DECIMAL(14, 2)) AS [Resource_Sec],
    CAST(W1.Signal_S AS DECIMAL(14, 2)) AS [Signal_Sec],
    W1.Wait_Count AS [Wait_Count],
    CAST(W1.Wait_S / NULLIF(SUM(W2.Wait_S), 0) * 100 AS DECIMAL(5, 2)) AS [Percentage_Of_Total_Waits],
    CASE 
        WHEN W1.wait_type LIKE 'LCK%' THEN 'Locking'
        WHEN W1.wait_type LIKE 'PAGEIOLATCH%' THEN 'Storage (Read)'
        WHEN W1.wait_type LIKE 'WRITELOG' OR W1.wait_type LIKE 'LOGMGR%' THEN 'Storage (Write)'
        WHEN W1.wait_type LIKE 'PAGELATCH%' THEN 'Buffer/TempDB'
        WHEN W1.wait_type = 'CXPACKET' THEN 'Parallelism'
        WHEN W1.wait_type = 'SOS_SCHEDULER_YIELD' THEN 'CPU'
        WHEN W1.wait_type = 'RESOURCE_SEMAPHORE' THEN 'Memory'
        WHEN W1.wait_type = 'ASYNC_NETWORK_IO' THEN 'Network/Client'
        ELSE 'Other'
    END AS [Wait_Category],
    CASE 
        WHEN W1.wait_type LIKE 'LCK%' THEN 'Locking / Blocking contention. Recommendation: Identify active blocking session, optimize query transactions, or modify isolation level (e.g. RCSI).'
        WHEN W1.wait_type LIKE 'PAGEIOLATCH%' THEN 'Disk to Memory transfer bottleneck. Recommendation: Improve indexing to avoid large table scans, or scale memory/I/O throughput.'
        WHEN W1.wait_type LIKE 'PAGELATCH%' THEN 'In-memory buffer contention (common in TempDB allocation pages). Recommendation: Optimize TempDB file allocation or review page-splits.'
        WHEN W1.wait_type = 'CXPACKET' THEN 'Parallel task coordination. Recommendation: Often occurs alongside other wait types. Investigate high-cost plans, increase CTFP configuration.'
        WHEN W1.wait_type = 'ASYNC_NETWORK_IO' THEN 'App server processing wait. Recommendation: Client application is processing rows too slowly or fetching massive datasets (RBAR).'
        WHEN W1.wait_type = 'RESOURCE_SEMAPHORE' THEN 'Query memory grant starvation. Recommendation: Optimize memory-heavy sorts/hashes or scale system memory.'
        ELSE 'Generic wait type. Review MSDN documentation or correlate with concurrent performance traces.'
    END AS [Best_Practice_Recommendation],
    CAST('Aggregates and formats cumulative wait stats. ' + 
         'Threshold: Top 3 wait types usually make up 80%+ of bottlenecks. ' +
         'Recommendation: Target optimization efforts on the highest percentage wait types.'
         AS VARCHAR(1000)) AS [Metric_Context]
FROM [WaitStats] AS W1
CROSS JOIN [WaitStats] AS W2
WHERE W2.Row_Num <= 20 -- Limits percentage calculation base to top 20 wait types
GROUP BY W1.wait_type, W1.Wait_S, W1.Resource_S, W1.Signal_S, W1.Wait_Count, W1.Row_Num
HAVING W1.Row_Num <= 20
ORDER BY W1.Wait_S DESC;
