/*
================================================================================
02_Find_Regressed_Queries.sql
Purpose : Find queries whose duration/CPU got worse recently (e.g. after compat 160).
          Tuned for "before vs after" windows you set below.
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

DECLARE
    @before_start datetime2 = DATEADD(DAY, -14, SYSUTCDATETIME()),
    @before_end   datetime2 = DATEADD(DAY, -7,  SYSUTCDATETIME()),  -- last week at 130
    @after_start  datetime2 = DATEADD(DAY, -7,  SYSUTCDATETIME()),
    @after_end    datetime2 = SYSUTCDATETIME();                      -- this week at 160

;WITH before_stats AS (
    SELECT
        q.query_id,
        SUM(rs.count_executions) AS execs,
        SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_duration_us,
        SUM(rs.avg_cpu_time * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_cpu_us,
        SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_reads
    FROM sys.query_store_query q
    JOIN sys.query_store_plan p ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval i
        ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
    WHERE i.start_time >= @before_start AND i.start_time < @before_end
    GROUP BY q.query_id
),
after_stats AS (
    SELECT
        q.query_id,
        SUM(rs.count_executions) AS execs,
        SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_duration_us,
        SUM(rs.avg_cpu_time * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_cpu_us,
        SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_reads
    FROM sys.query_store_query q
    JOIN sys.query_store_plan p ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval i
        ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
    WHERE i.start_time >= @after_start AND i.start_time < @after_end
    GROUP BY q.query_id
)
SELECT TOP (50)
    b.query_id,
    qt.query_sql_text,
    b.execs AS before_execs,
    a.execs AS after_execs,
    b.avg_duration_us / 1000.0 AS before_avg_ms,
    a.avg_duration_us / 1000.0 AS after_avg_ms,
    (a.avg_duration_us * 1.0 / NULLIF(b.avg_duration_us,0)) AS duration_ratio,
    b.avg_cpu_us / 1000.0 AS before_cpu_ms,
    a.avg_cpu_us / 1000.0 AS after_cpu_ms,
    (a.avg_cpu_us * 1.0 / NULLIF(b.avg_cpu_us,0)) AS cpu_ratio,
    b.avg_reads AS before_avg_reads,
    a.avg_reads AS after_avg_reads
FROM before_stats b
JOIN after_stats a ON a.query_id = b.query_id
JOIN sys.query_store_query q ON q.query_id = b.query_id
JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
WHERE a.avg_duration_us > b.avg_duration_us * 1.5   -- 50%+ slower
  AND a.execs >= 5
ORDER BY duration_ratio DESC, after_avg_ms DESC;

-- Plans for a specific query_id:
-- SELECT plan_id, is_forced_plan, last_execution_time, CAST(query_plan AS xml)
-- FROM sys.query_store_plan WHERE query_id = 123;
