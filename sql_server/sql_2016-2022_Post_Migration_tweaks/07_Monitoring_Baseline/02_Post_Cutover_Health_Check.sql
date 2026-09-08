/*
================================================================================
02_Post_Cutover_Health_Check.sql
Purpose : Run every 15–30 minutes during first hours after compat 160 cutover.
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

PRINT '1) Compat + scoped configs';
SELECT name, compatibility_level, is_query_store_on FROM sys.databases WHERE name = DB_NAME();
SELECT name, value FROM sys.database_scoped_configurations
WHERE name IN (
    N'LEGACY_CARDINALITY_ESTIMATION',
    N'PARAMETER_SNIFFING',
    N'QUERY_OPTIMIZER_HOTFIXES',
    N'BATCH_MODE_ON_ROWSTORE'
);

PRINT '2) Query Store health (must stay READ_WRITE)';
SELECT actual_state_desc, readonly_reason, current_storage_size_mb, max_storage_size_mb
FROM sys.database_query_store_options;

PRINT '3) Forced plans with failures';
SELECT query_id, plan_id, force_failure_count, last_force_failure_reason_desc
FROM sys.query_store_plan
WHERE is_forced_plan = 1 AND force_failure_count > 0;

PRINT '4) Recent expensive queries (1 hour)';
SELECT TOP (20)
    q.query_id,
    rs.avg_duration/1000.0 AS avg_ms,
    rs.avg_cpu_time/1000.0 AS avg_cpu_ms,
    rs.avg_logical_io_reads AS avg_reads,
    rs.count_executions,
    LEFT(qt.query_sql_text, 180) AS preview
FROM sys.query_store_runtime_stats rs
JOIN sys.query_store_plan p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query q ON q.query_id = p.query_id
JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_runtime_stats_interval i ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE i.start_time >= DATEADD(HOUR, -1, GETUTCDATE())
ORDER BY rs.avg_duration * rs.count_executions DESC;

PRINT '5) Memory grant waits present?';
SELECT wait_type, waiting_tasks_count, wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type IN (N'RESOURCE_SEMAPHORE', N'RESOURCE_SEMAPHORE_QUERY_COMPILE', N'CXPACKET', N'CXCONSUMER', N'PAGEIOLATCH_SH', N'WRITELOG')
ORDER BY wait_time_ms DESC;

PRINT 'If avg_ms spikes vs baseline → open 03_QueryStore_PlanForce\\02_Find_Regressed_Queries.sql';
PRINT 'If widespread → LEGACY_CARDINALITY_ESTIMATION = ON or rollback compat to 130.';
