/*
================================================================================
05_Automatic_Regression_Report.sql
Purpose : Combined before/after regression report: duration, CPU, logical reads,
          and Query Store waits — single output for compat 130 vs 160 cutover.
Requires: Query Store ON with history spanning both windows
Safety  : Read-only
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_query_store_on = 1)
BEGIN
    RAISERROR('Query Store must be ON with baseline at CL 130 before flipping to 160.', 16, 1);
    RETURN;
END

-- <<< Adjust windows to your cutover
DECLARE
    @before_start datetime2 = DATEADD(DAY, -14, SYSUTCDATETIME()),
    @before_end   datetime2 = DATEADD(DAY, -7,  SYSUTCDATETIME()),
    @after_start  datetime2 = DATEADD(DAY, -7,  SYSUTCDATETIME()),
    @after_end    datetime2 = SYSUTCDATETIME(),
    @MinExecs     int = 5,
    @RegressPct   decimal(10,2) = 1.50;  -- 50% worse

;WITH RuntimeBefore AS (
    SELECT q.query_id,
           SUM(rs.count_executions) AS execs,
           SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_duration_us,
           SUM(rs.avg_cpu_time * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_cpu_us,
           SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_reads
    FROM sys.query_store_query q
    JOIN sys.query_store_plan p ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval i ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
    WHERE i.start_time >= @before_start AND i.start_time < @before_end
    GROUP BY q.query_id
),
RuntimeAfter AS (
    SELECT q.query_id,
           SUM(rs.count_executions) AS execs,
           SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_duration_us,
           SUM(rs.avg_cpu_time * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_cpu_us,
           SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_reads
    FROM sys.query_store_query q
    JOIN sys.query_store_plan p ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval i ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
    WHERE i.start_time >= @after_start AND i.start_time < @after_end
    GROUP BY q.query_id
),
WaitsBefore AS (
    SELECT p.query_id, SUM(ws.total_query_wait_time_ms) AS total_wait_ms
    FROM sys.query_store_wait_stats ws
    JOIN sys.query_store_plan p ON p.plan_id = ws.plan_id
    JOIN sys.query_store_runtime_stats_interval i ON i.runtime_stats_interval_id = ws.runtime_stats_interval_id
    WHERE i.start_time >= @before_start AND i.start_time < @before_end
    GROUP BY p.query_id
),
WaitsAfter AS (
    SELECT p.query_id, SUM(ws.total_query_wait_time_ms) AS total_wait_ms
    FROM sys.query_store_wait_stats ws
    JOIN sys.query_store_plan p ON p.plan_id = ws.plan_id
    JOIN sys.query_store_runtime_stats_interval i ON i.runtime_stats_interval_id = ws.runtime_stats_interval_id
    WHERE i.start_time >= @after_start AND i.start_time < @after_end
    GROUP BY p.query_id
)
SELECT TOP (60)
    b.query_id,
    LEFT(qt.query_sql_text, 200) AS query_preview,
    b.execs AS before_execs,
    a.execs AS after_execs,
    b.avg_duration_us / 1000.0 AS before_avg_ms,
    a.avg_duration_us / 1000.0 AS after_avg_ms,
    CAST(a.avg_duration_us / NULLIF(b.avg_duration_us,0) AS decimal(10,2)) AS duration_ratio,
    b.avg_cpu_us / 1000.0 AS before_cpu_ms,
    a.avg_cpu_us / 1000.0 AS after_cpu_ms,
    CAST(a.avg_cpu_us / NULLIF(b.avg_cpu_us,0) AS decimal(10,2)) AS cpu_ratio,
    b.avg_reads AS before_avg_reads,
    a.avg_reads AS after_avg_reads,
    CAST(a.avg_reads / NULLIF(b.avg_reads,0) AS decimal(10,2)) AS reads_ratio,
    ISNULL(wb.total_wait_ms,0) AS before_wait_ms,
    ISNULL(wa.total_wait_ms,0) AS after_wait_ms,
    CAST(ISNULL(wa.total_wait_ms,0) / NULLIF(wb.total_wait_ms,0) AS decimal(10,2)) AS wait_ratio,
    CASE
        WHEN a.avg_duration_us > b.avg_duration_us * @RegressPct THEN N'Duration regression'
        WHEN a.avg_cpu_us > b.avg_cpu_us * @RegressPct THEN N'CPU regression'
        WHEN a.avg_reads > b.avg_reads * @RegressPct THEN N'IO regression'
        WHEN ISNULL(wa.total_wait_ms,0) > ISNULL(wb.total_wait_ms,0) * @RegressPct THEN N'Wait regression'
        ELSE N'Mixed'
    END AS regression_type
FROM RuntimeBefore b
JOIN RuntimeAfter a ON a.query_id = b.query_id
JOIN sys.query_store_query q ON q.query_id = b.query_id
JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
LEFT JOIN WaitsBefore wb ON wb.query_id = b.query_id
LEFT JOIN WaitsAfter wa ON wa.query_id = b.query_id
WHERE a.execs >= @MinExecs
  AND (
        a.avg_duration_us > b.avg_duration_us * @RegressPct
     OR a.avg_cpu_us > b.avg_cpu_us * @RegressPct
     OR a.avg_reads > b.avg_reads * @RegressPct
     OR ISNULL(wa.total_wait_ms,0) > ISNULL(wb.total_wait_ms,0) * @RegressPct
  )
ORDER BY duration_ratio DESC, after_avg_ms DESC;

PRINT 'Use query_id to open plans, compare CE/IQP fingerprints, then apply targeted fix — hints last.';
