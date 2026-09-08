/*
    Migration 2016 -> 2022 | Pre-cutover baseline snapshot
    Run on SOURCE immediately before stopping applications (T-30 min).
    Risk: Read-only
*/
SET NOCOUNT ON;

SELECT GETDATE() AS [CaptureTime], @@SERVERNAME AS [InstanceName], @@VERSION AS [Version];

SELECT sqlserver_start_time FROM sys.dm_os_sys_info;

SELECT TOP (15)
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms - signal_wait_time_ms AS [resource_wait_ms]
FROM sys.dm_os_wait_stats
WHERE wait_type NOT LIKE N'SLEEP%'
  AND wait_type NOT IN (
      N'WAITFOR', N'REQUEST_FOR_DEADLOCK_SEARCH', N'LAZYWRITER_SLEEP',
      N'LOGMGR_QUEUE', N'CHECKPOINT_QUEUE', N'BROKER_TO_FLUSH',
      N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_BUFFER_FLUSH',
      N'XE_TIMER_EVENT', N'XE_DISPATCHER_WAIT'
  )
ORDER BY wait_time_ms DESC;

SELECT
    r.session_id,
    r.status,
    r.command,
    DB_NAME(r.database_id) AS [DatabaseName],
    r.blocking_session_id,
    r.wait_type,
    r.wait_time,
    r.cpu_time,
    r.total_elapsed_time,
    r.reads,
    r.writes,
    SUBSTRING(st.text, (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE r.statement_end_offset END
            - r.statement_start_offset) / 2) + 1) AS [StatementText]
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.session_id > 50
ORDER BY r.total_elapsed_time DESC;
