/*
================================================================================
SQL Server Baseline Snapshot Capture (Lightweight)
================================================================================
Description:
    Captures a point-in-time snapshot of key performance metrics: wait stats,
    performance counters, OS info, and file I/O stall data. Use this before
    and after making changes to measure impact, or capture regularly for
    historical trending.

Output:
    (1) Instance performance counters (CPU, memory, I/O, batch requests)
    (2) Top waits with wait times
    (3) Database file I/O stalls

Action:
    Run this script BEFORE and AFTER any major change (configuration change,
    index rebuild, query optimization, hardware upgrade). Compare the two
    snapshots to quantify the impact. For ongoing monitoring, schedule this
    script hourly via SQL Agent and store results in a baseline table.
    Cross-reference with sp_DBA_BaselineCapture for persistent storage.

Criticality: Low
Prerequisites: VIEW SERVER STATE permission. Optional dbo.fn_DBA_ExcludedWaitTypes
    in current database or DBARepository for centralized wait filtering.
Persistence: None. Uses only session-scoped #ExcludedWaitTypes when needed.
Safety: Read-only DMV queries; no permanent objects are created.
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
    N'Cumulative counters below are since this time.' AS [Metric_Context]
FROM sys.dm_os_sys_info AS osi;

-- 1. Instance Performance Counters Snapshot
PRINT '--- Baseline: Performance Counters Snapshot ---';
SELECT 
    GETDATE() AS [Snapshot_Time],
    pc.object_name AS [Object_Name],
    pc.counter_name AS [Counter_Name],
    pc.instance_name AS [Instance_Name],
    pc.cntr_value AS [Counter_Value],
    pc.cntr_type AS [Counter_Type]
FROM sys.dm_os_performance_counters AS pc
WHERE pc.counter_name IN (
    N'Page life expectancy', N'Batch Requests/sec', N'SQL Compilations/sec', 
    N'SQL Re-Compilations/sec', N'User Connections', N'Lock Waits/sec',
    N'Buffer cache hit ratio', N'Buffer cache hit ratio base'
)
AND (pc.object_name LIKE N'%Buffer Manager%' OR pc.object_name LIKE N'%SQL Statistics%' OR pc.object_name LIKE N'%General Statistics%' OR pc.object_name LIKE N'%Locks%');

-- 2. Instance Wait Stats Snapshot (Cumulative)
PRINT '--- Baseline: Cumulative Wait Stats ---';
SELECT 
    GETDATE() AS [Snapshot_Time],
    ws.wait_type AS [Wait_Type],
    ws.waiting_tasks_count AS [Waiting_Tasks_Count],
    ws.wait_time_ms AS [Wait_Time_ms],
    ws.max_wait_time_ms AS [Max_Wait_Time_ms],
    ws.signal_wait_time_ms AS [Signal_Wait_Time_ms]
FROM sys.dm_os_wait_stats AS ws
WHERE ws.wait_time_ms > 1000
  AND ws.wait_type NOT IN (SELECT excluded_waits.wait_type FROM #ExcludedWaitTypes AS excluded_waits)
ORDER BY ws.wait_time_ms DESC;

-- 3. I/O File Stats Snapshot
PRINT '--- Baseline: File I/O Stats ---';
SELECT
    GETDATE() AS [Snapshot_Time],
    DB_NAME(vfs.database_id) AS [Database_Name],
    mf.name AS [File_Name],
    vfs.num_of_reads AS [Number_Of_Reads],
    vfs.num_of_writes AS [Number_Of_Writes],
    vfs.io_stall_read_ms AS [Io_Stall_Read_ms],
    vfs.io_stall_write_ms AS [Io_Stall_Write_ms]
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
INNER JOIN sys.master_files AS mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id;
