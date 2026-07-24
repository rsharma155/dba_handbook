/*
================================================================================
04_QueryStore_Wait_Statistics_Report.sql
Purpose : Per-query wait breakdown from Query Store (requires WAIT_STATS_CAPTURE_MODE ON).
          Compare wait categories before vs after compat 160 change.
Requires: Query Store ON, SQL Server 2017+ (wait stats in QS)
Safety  : Read-only
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_query_store_on = 1)
BEGIN
    RAISERROR('Query Store must be ON. Enable WAIT_STATS_CAPTURE_MODE ON.', 16, 1);
    RETURN;
END

DECLARE
    @WindowStart datetime2 = DATEADD(DAY, -7, SYSUTCDATETIME()),
    @WindowEnd   datetime2 = SYSUTCDATETIME();

-- Per query + wait category (recent window)
SELECT TOP (80)
    q.query_id,
    ws.wait_category_desc,
    SUM(ws.total_query_wait_time_ms) AS total_wait_ms,
    SUM(ws.avg_query_wait_time_ms * ws.count_executions) / NULLIF(SUM(ws.count_executions),0) AS avg_wait_ms,
    SUM(ws.count_executions) AS executions,
    LEFT(qt.query_sql_text, 180) AS query_preview
FROM sys.query_store_wait_stats AS ws
JOIN sys.query_store_plan AS p ON p.plan_id = ws.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_runtime_stats_interval AS i
    ON i.runtime_stats_interval_id = ws.runtime_stats_interval_id
WHERE i.start_time >= @WindowStart AND i.start_time < @WindowEnd
GROUP BY q.query_id, ws.wait_category_desc, qt.query_sql_text
HAVING SUM(ws.total_query_wait_time_ms) > 1000
ORDER BY total_wait_ms DESC;

-- Wait category totals (instance-in-DB view)
SELECT
    ws.wait_category_desc,
    SUM(ws.total_query_wait_time_ms) AS total_wait_ms,
    SUM(ws.count_executions) AS executions
FROM sys.query_store_wait_stats AS ws
JOIN sys.query_store_runtime_stats_interval AS i
    ON i.runtime_stats_interval_id = ws.runtime_stats_interval_id
WHERE i.start_time >= @WindowStart AND i.start_time < @WindowEnd
GROUP BY ws.wait_category_desc
ORDER BY total_wait_ms DESC;

/*
COMPARE BEFORE/AFTER CL 160
Run twice with different @WindowStart/@WindowEnd aligned to cutover date.
Watch for increases in: Memory, Parallelism, Buffer IO, TranLog, Locking.
*/
