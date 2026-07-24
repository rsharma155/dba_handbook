/*
================================================================================
01_Capture_Before_After_Metrics.sql
Purpose : Snapshot metrics before compat flip and after (same workload window).
Save     : Export result grids to CSV with timestamp in filename.
================================================================================
*/
SET NOCOUNT ON;
DECLARE @label nvarchar(100) = N'BEFORE_compat130';  -- change to AFTER_compat160

SELECT
    @label AS capture_label,
    SYSUTCDATETIME() AS capture_utc,
    SERVERPROPERTY('ProductVersion') AS version,
    d.name AS database_name,
    d.compatibility_level,
    dsc.value AS legacy_ce
FROM sys.databases d
OUTER APPLY (
    SELECT value
    FROM sys.database_scoped_configurations
    WHERE name = N'LEGACY_CARDINALITY_ESTIMATION'
) dsc
WHERE d.name = DB_NAME();

-- Batch requests / compilations (instance counters since startup — compare rates over time)
SELECT @label AS capture_label, counter_name, cntr_value
FROM sys.dm_os_performance_counters
WHERE counter_name IN (
    N'Batch Requests/sec',
    N'SQL Compilations/sec',
    N'SQL Re-Compilations/sec',
    N'Page life expectancy',
    N'Processes blocked'
)
AND (instance_name = N'' OR instance_name = N'_Total' OR object_name LIKE N'%Buffer Manager%' OR object_name LIKE N'%SQL Statistics%' OR object_name LIKE N'%General Statistics%');

-- Wait snapshot
SELECT TOP (15)
    @label AS capture_label,
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;

-- Query Store top duration (requires QS)
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_query_store_on = 1)
BEGIN
    SELECT TOP (20)
        @label AS capture_label,
        q.query_id,
        rs.avg_duration / 1000.0 AS avg_ms,
        rs.avg_cpu_time / 1000.0 AS avg_cpu_ms,
        rs.count_executions,
        LEFT(qt.query_sql_text, 200) AS query_preview
    FROM sys.query_store_runtime_stats rs
    JOIN sys.query_store_plan p ON p.plan_id = rs.plan_id
    JOIN sys.query_store_query q ON q.query_id = p.query_id
    JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
    JOIN sys.query_store_runtime_stats_interval i
        ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
    WHERE i.start_time >= DATEADD(HOUR, -24, GETUTCDATE())
    ORDER BY rs.avg_duration DESC;
END
