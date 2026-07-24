/*
================================================================================
03_Wait_Stats_and_Top_Queries.sql
Purpose : Identify whether slowness is CPU, IO, parallelism, memory grants,
          or specific query regressions after moving to compat 160.
================================================================================
*/
SET NOCOUNT ON;

PRINT '=== TOP WAITS (clear noise) ===';
;WITH Waits AS (
    SELECT
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        signal_wait_time_ms,
        wait_time_ms - signal_wait_time_ms AS resource_wait_ms,
        100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS pct
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (
        N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP',
        N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE',
        N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
        N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE',
        N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',
        N'EXECSYNC', N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
        N'HADR_CLUSINTER_CONTRACT', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        N'HADR_LOGCAPTURE_WAIT', N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK',
        N'HADR_WORK_QUEUE', N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE',
        N'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE', N'PARALLEL_REDO_DRAIN_WORKER',
        N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST', N'PARALLEL_REDO_WORKER_SYNC',
        N'PARALLEL_REDO_WORKER_WAIT_WORK', N'PREEMPTIVE_OS_FLUSHFILEBUFFERS',
        N'PREEMPTIVE_XE_GETTARGETSTATE', N'PWAIT_ALL_COMPONENTS_INITIALIZED',
        N'PWAIT_DIRECTLOGCONSUMER_GETNEXT', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
        N'QDS_ASYNC_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
        N'QDS_SHUTDOWN_QUEUE', N'REDO_THREAD_PENDING_WORK', N'REQUEST_FOR_DEADLOCK_SEARCH',
        N'RESOURCE_QUEUE', N'SERVER_IDLE_CHECK', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP',
        N'SLEEP_DCOMSTARTUP', N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY',
        N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TASK',
        N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT', N'SP_SERVER_DIAGNOSTICS_SLEEP',
        N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES',
        N'WAIT_FOR_RESULTS', N'WAITFOR', N'WAITFOR_TASKSHUTDOWN', N'WAIT_XTP_CKPT_CLOSE',
        N'WAIT_XTP_HOST_WAIT', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'WAIT_XTP_RECOVERY',
        N'XE_DISPATCHER_JOIN', N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT'
    )
)
SELECT TOP (20) *
FROM Waits
WHERE waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;

PRINT '=== INTERPRETATION HINTS ===';
PRINT 'CXPACKET/CXCONSUMER + high SOS_SCHEDULER_YIELD → parallelism / CPU pressure; revisit MAXDOP & CTFP';
PRINT 'PAGEIOLATCH_* / WRITELOG → storage latency; check disk and log Autogrowth';
PRINT 'RESOURCE_SEMAPHORE → memory grant waits (often bad CE → oversized hash/sort grants)';
PRINT 'LCK_M_* → blocking (not usually caused by compat alone)';

PRINT '=== TOP CPU QUERIES (plan cache) ===';
SELECT TOP (25)
    qs.total_worker_time / NULLIF(qs.execution_count,0) AS avg_cpu_us,
    qs.total_elapsed_time / NULLIF(qs.execution_count,0) AS avg_elapsed_us,
    qs.execution_count,
    qs.total_logical_reads / NULLIF(qs.execution_count,0) AS avg_logical_reads,
    qs.total_grant_kb / NULLIF(qs.execution_count,0) AS avg_grant_kb,
    qs.total_used_grant_kb / NULLIF(qs.execution_count,0) AS avg_used_grant_kb,
    qs.total_spills AS total_spills,
    DB_NAME(st.dbid) AS db_name,
    OBJECT_NAME(st.objectid, st.dbid) AS object_name,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS statement_text
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE st.dbid = DB_ID()  -- current DB; remove filter for instance-wide
ORDER BY qs.total_worker_time DESC;

PRINT '=== MEMORY GRANT SPILLS (strong CE smell) ===';
SELECT TOP (25)
    qs.total_spills,
    qs.execution_count,
    qs.total_grant_kb / NULLIF(qs.execution_count,0) AS avg_grant_kb,
    qs.total_used_grant_kb / NULLIF(qs.execution_count,0) AS avg_used_grant_kb,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS statement_text
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE qs.total_spills > 0
ORDER BY qs.total_spills DESC;
