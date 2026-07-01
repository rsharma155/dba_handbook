/*
================================================================================
Query Store — Wait Stats by Plan (SQL Server 2017+)
================================================================================
Purpose:
    Break down wait time by plan for one query_id. Use when avg_duration is high
    but avg_cpu and logical reads look low — the bottleneck is likely waits, not
    a bad plan shape.

Parameters:
    @QueryId     - Query Store query_id (required)
    @RecentHours - lookback window (default 168)

Output:
    Per-plan wait category totals and average wait per execution (via runtime stats join)

Note:
    sys.query_store_wait_stats has no count_executions or last_execution_time.
    Join plan_id + runtime_stats_interval_id + execution_type to runtime stats,
    and filter intervals with sys.query_store_runtime_stats_interval.start_time.

Action:
    If CXPACKET, PAGEIOLATCH, or LCK_M_* dominate, fix waits (indexes, blocking,
    I/O) before forcing a plan. Requires wait_stats_capture_mode ON or ALL in
    Query Store options.

Criticality: High for elapsed-vs-CPU mismatches
Prerequisites: SQL Server 2017+, Query Store wait stats capture enabled
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @QueryId BIGINT = 57;  -- << CHANGE to target query_id
DECLARE @RecentHours INT = 168;
DECLARE @CurrentDatabase SYSNAME = DB_NAME();
DECLARE @ErrMsg NVARCHAR(4000);

IF @QueryId IS NULL
BEGIN
    RAISERROR(N'Set @QueryId to the query_id from 01_multi_plan_queries.sql.', 16, 1);
    RETURN;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.databases
    WHERE database_id = DB_ID()
      AND is_query_store_on = 1
)
BEGIN
    SET @ErrMsg = N'Query Store is not enabled on database ' + QUOTENAME(@CurrentDatabase) + N'.';
    RAISERROR(@ErrMsg, 16, 1);
    RETURN;
END;

IF COL_LENGTH(N'sys.query_store_wait_stats', N'wait_category_desc') IS NULL
BEGIN
    RAISERROR(N'query_store_wait_stats is not available (requires SQL Server 2017+).', 16, 1);
    RETURN;
END;

DECLARE @WaitCapture NVARCHAR(60);
SELECT @WaitCapture = wait_stats_capture_mode_desc
FROM sys.database_query_store_options;

IF @WaitCapture = N'OFF'
BEGIN
    SET @ErrMsg = N'Query Store wait stats capture is OFF on ' + QUOTENAME(@CurrentDatabase)
        + N'. Enable with: ALTER DATABASE ' + QUOTENAME(@CurrentDatabase)
        + N' SET QUERY_STORE (WAIT_STATS_CAPTURE_MODE = ON);';
    RAISERROR(@ErrMsg, 16, 1);
    RETURN;
END;

DECLARE @Cutoff DATETIME2(7) = DATEADD(HOUR, -@RecentHours, SYSDATETIME());

PRINT N'=== WAIT STATS BY PLAN (query_id = ' + CAST(@QueryId AS NVARCHAR(20)) + N', last '
    + CAST(@RecentHours AS NVARCHAR(10)) + N' hours) ===';

SELECT
    p.query_id,
    p.plan_id,
    p.is_forced_plan,
    ws.wait_category_desc,
    SUM(ws.total_query_wait_time_ms) AS [Total_Wait_ms],
    SUM(ws.avg_query_wait_time_ms * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) AS [Avg_Wait_Per_Exec_ms],
    SUM(rs.count_executions) AS [Count_Executions],
    MAX(rsi.end_time) AS [Last_Interval_End]
FROM sys.query_store_plan AS p
INNER JOIN sys.query_store_wait_stats AS ws ON p.plan_id = ws.plan_id
INNER JOIN sys.query_store_runtime_stats AS rs
    ON ws.plan_id = rs.plan_id
   AND ws.runtime_stats_interval_id = rs.runtime_stats_interval_id
   AND ws.execution_type = rs.execution_type
INNER JOIN sys.query_store_runtime_stats_interval AS rsi
    ON ws.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE p.query_id = @QueryId
  AND rsi.start_time >= @Cutoff
GROUP BY
    p.query_id,
    p.plan_id,
    p.is_forced_plan,
    ws.wait_category_desc
ORDER BY
    p.plan_id,
    [Total_Wait_ms] DESC;

PRINT N'=== PLAN DURATION vs WAIT (same window) ===';

SELECT
    p.plan_id,
    p.is_forced_plan,
    SUM(rs.count_executions) AS [Count_Executions],
    SUM(rs.avg_duration * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS [Avg_Duration_ms],
    SUM(rs.avg_cpu_time * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS [Avg_CPU_ms],
    ISNULL(wait_tot.total_wait_ms, 0) AS [Total_Wait_ms_All_Categories],
    CAST(
        100.0 * ISNULL(wait_tot.total_wait_ms, 0)
        / NULLIF(SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0, 0)
        AS DECIMAL(10, 1)
    ) AS [Wait_Pct_of_Duration]
FROM sys.query_store_plan AS p
INNER JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id
INNER JOIN sys.query_store_runtime_stats_interval AS rsi
    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
LEFT JOIN (
    SELECT
        ws.plan_id,
        SUM(ws.total_query_wait_time_ms) AS total_wait_ms
    FROM sys.query_store_wait_stats AS ws
    INNER JOIN sys.query_store_runtime_stats_interval AS rsi2
        ON ws.runtime_stats_interval_id = rsi2.runtime_stats_interval_id
    WHERE rsi2.start_time >= @Cutoff
    GROUP BY ws.plan_id
) AS wait_tot ON p.plan_id = wait_tot.plan_id
WHERE p.query_id = @QueryId
  AND rsi.start_time >= @Cutoff
GROUP BY
    p.plan_id,
    p.is_forced_plan,
    wait_tot.total_wait_ms
ORDER BY [Avg_Duration_ms] DESC;
