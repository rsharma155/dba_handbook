/*
================================================================================
Purpose:        Exhaustive wait statistics analysis with detailed root cause 
                analysis and suggested investigation commands for top 30 waits.
Provides:       Detailed breakdown of top 30 wait types, average wait times, 
                percentage impact, and actionable T-SQL investigation scripts.
Importance:     Serves as a comprehensive reference guide for DBAs to understand 
                and troubleshoot specific wait types with proven commands.
Interpretation: Use the "Root_Cause_Analysis" to understand the wait and execute 
                 the "Investigation_Command" to find the specific source of pressure.
Action: Use this script as a reference guide. For each high-impact wait type in your environment, execute the provided Investigation_Command to find the source. For example, if PAGEIOLATCH_XX is top, run the investigation command to find slow data files, then cross-reference with disk_latency.sql. This script does not require immediate action — it is educational and designed to guide your troubleshooting.
Criticality:    Medium (Educational/Reference)
Prerequisites:  VIEW SERVER STATE permission. Optional dbo.fn_DBA_ExcludedWaitTypes
                in current database or DBARepository for centralized wait filtering.
Persistence:    None. Uses only session-scoped #ExcludedWaitTypes when needed.
Safety:         Read-only DMV query; no permanent objects are created.
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

WITH WaitData AS (
    SELECT
        ws.wait_type AS [wait_type],
        ws.wait_time_ms / 1000.0 AS [Wait_S],
        (ws.wait_time_ms - ws.signal_wait_time_ms) / 1000.0 AS [Resource_S],
        ws.signal_wait_time_ms / 1000.0 AS [Signal_S],
        ws.waiting_tasks_count AS [Wait_Count],
        100.0 * ws.wait_time_ms / SUM(ws.wait_time_ms) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY ws.wait_time_ms DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats AS ws
    WHERE ws.wait_type NOT IN (SELECT excluded_waits.wait_type FROM #ExcludedWaitTypes AS excluded_waits)
      AND ws.waiting_tasks_count > 0
)
SELECT 
    wait_type AS [Wait_Type],
    CAST([Wait_S] AS DECIMAL(16,2)) AS [Wait_Sec],
    CAST([Percentage] AS DECIMAL(5,2)) AS [Percentage_Of_Total_Waits],
    CAST(([Wait_S] / NULLIF([Wait_Count], 0)) AS DECIMAL(16,4)) AS [Avg_Wait_S],
    CASE 
        WHEN wait_type = 'CXPACKET' THEN 'Parallel skew. Threads waiting for others.'
        WHEN wait_type = 'SOS_SCHEDULER_YIELD' THEN 'CPU pressure. Threads exhausted quantum.'
        WHEN wait_type = 'PAGEIOLATCH_SH' THEN 'Disk Read. Data pages coming from disk.'
        WHEN wait_type = 'PAGEIOLATCH_EX' THEN 'Disk Write. Buffer flush to disk.'
        WHEN wait_type = 'WRITELOG' THEN 'T-Log latency. Flush to disk bottleneck.'
        WHEN wait_type = 'ASYNC_NETWORK_IO' THEN 'App fetching too slow / RBAR.'
        WHEN wait_type = 'RESOURCE_SEMAPHORE' THEN 'Memory grant starvation (Sort/Hash).'
        WHEN wait_type = 'LCK_M_X' THEN 'Exclusive Lock blocking.'
        WHEN wait_type = 'LCK_M_S' THEN 'Shared Lock blocking.'
        WHEN wait_type = 'PAGELATCH_UP' THEN 'TempDB/Buffer metadata contention.'
        WHEN wait_type = 'THREADPOOL' THEN 'Worker thread exhaustion. CRITICAL.'
        WHEN wait_type = 'PREEMPTIVE_OS_WRITEFILEGATHER' THEN 'IFI Disabled check.'
        WHEN wait_type = 'CMEMTHREAD' THEN 'Memory object contention (Plan Cache).'
        WHEN wait_type = 'HADR_SYNC_COMMIT' THEN 'AlwaysOn Sync Latency (Network/IO).'
        WHEN wait_type = 'LOGBUFFER' THEN 'Wait for space in log buffer. IO bottleneck.'
        WHEN wait_type = 'RESOURCE_SEMAPHORE_QUERY_COMPILE' THEN 'Compilation storm. Plan cache bloat.'
        WHEN wait_type = 'LCK_M_IX' THEN 'Intent Exclusive Lock. Table/Page level blocking.'
        WHEN wait_type = 'PAGEIOLATCH_UP' THEN 'Page update read. Disk bottleneck.'
        WHEN wait_type = 'ASYNC_IO_COMPLETION' THEN 'General IO wait. Check storage.'
        WHEN wait_type = 'BACKUPIO' THEN 'SQL waiting for backup device.'
        WHEN wait_type = 'CXCONSUMER' THEN 'Safe to ignore if CXPACKET is high.'
        WHEN wait_type = 'REDO_THREAD_PENDING_WORK' THEN 'AlwaysOn Redo Lag.'
        WHEN wait_type = 'SLEEP_BPOOL_FLUSH' THEN 'Checkpoint/LazyWriter bottleneck.'
        WHEN wait_type = 'DTC' THEN 'Distributed Transaction Coordinator lag.'
        WHEN wait_type = 'OLEDB' THEN 'Linked Server or DMV overhead.'
        WHEN wait_type = 'DBMIRROR_SEND' THEN 'Mirroring network lag.'
        WHEN wait_type = 'SQLCLR_QUANTUM' THEN 'CLR code executing too long.'
        WHEN wait_type = 'WRITE_COMPLETION' THEN 'General async write wait.'
        WHEN wait_type = 'POOL_PAGELATCH_EX' THEN 'Buffer pool contention.'
        WHEN wait_type = 'QUERY_EXECUTION_INDEX_LOOKUP' THEN 'Key Lookup pressure.'
        ELSE 'Review SQL documentation.'
    END AS [Root_Cause_Analysis],
    CASE 
        WHEN wait_type LIKE 'PAGEIOLATCH%' THEN 'SELECT database_id, file_id, io_stall_read_ms, num_of_reads, io_stall_write_ms, num_of_writes FROM sys.dm_io_virtual_file_stats(NULL,NULL) ORDER BY io_stall_read_ms DESC;'
        WHEN wait_type = 'CXPACKET' THEN 'SELECT name, value_in_use FROM sys.configurations WHERE name IN (''max degree of parallelism'',''cost threshold for parallelism'');'
        WHEN wait_type = 'RESOURCE_SEMAPHORE' THEN 'SELECT session_id, requested_memory_kb, granted_memory_kb, wait_time_ms FROM sys.dm_exec_query_memory_grants;'
        WHEN wait_type LIKE 'LCK%' THEN 'EXEC sp_WhoIsActive @get_plans=1;'
        WHEN wait_type = 'SOS_SCHEDULER_YIELD' THEN 'SELECT TOP (20) execution_count, total_worker_time, total_logical_reads, total_elapsed_time FROM sys.dm_exec_query_stats ORDER BY total_worker_time DESC;'
        WHEN wait_type = 'WRITELOG' THEN 'SELECT database_id, file_id, io_stall_write_ms, num_of_writes FROM sys.dm_io_virtual_file_stats(2,NULL); -- Check TempDB/Log'
        ELSE 'N/A'
    END AS [Investigation_Command]
FROM WaitData
WHERE RowNum <= 30
ORDER BY [Wait_S] DESC;
