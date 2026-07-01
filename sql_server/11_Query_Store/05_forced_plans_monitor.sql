/*
================================================================================
Query Store — Forced Plans and Force Failures
================================================================================
Purpose:
    List all currently forced plans, force failure counts, and plans that failed
    to remain forced. Use after 04_force_or_unforce_plan.sql or during periodic
    Query Store health reviews.

Output:
    (1) All forced plans with runtime stats
    (2) Plans with force_failure_count > 0
    (3) Query Store option summary for current database

Action:
    force_failure_count > 0: investigate last_force_failure_reason_desc — common
    causes include missing objects, plan not guidable, or incompatible hints.
    Forced plan slower than alternatives: unforce and re-run script 03.

Criticality: Medium
Prerequisites: Query Store enabled on current database
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @CurrentDatabase SYSNAME = DB_NAME();
DECLARE @ErrMsg NVARCHAR(4000);

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

PRINT N'=== FORCED PLANS ===';

SELECT
    q.query_id,
    p.plan_id,
    q.object_id,
    OBJECT_SCHEMA_NAME(q.object_id) AS [Schema_Name],
    OBJECT_NAME(q.object_id) AS [Object_Name],
    p.force_failure_count,
    p.last_force_failure_reason_desc,
    p.last_execution_time,
    SUM(rs.count_executions) AS [Count_Executions],
    SUM(rs.avg_duration * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS [Avg_Duration_ms],
    SUM(rs.avg_cpu_time * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS [Avg_CPU_ms],
    LEFT(qt.query_sql_text, 300) AS [Query_Text]
FROM sys.query_store_plan AS p
INNER JOIN sys.query_store_query AS q ON p.query_id = q.query_id
INNER JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
LEFT JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id
WHERE p.is_forced_plan = 1
GROUP BY
    q.query_id,
    p.plan_id,
    q.object_id,
    p.force_failure_count,
    p.last_force_failure_reason_desc,
    p.last_execution_time,
    qt.query_sql_text
ORDER BY [Avg_Duration_ms] DESC;

PRINT N'=== PLANS WITH FORCE FAILURES (forced or previously forced) ===';

SELECT
    q.query_id,
    p.plan_id,
    p.is_forced_plan,
    p.force_failure_count,
    p.last_force_failure_reason_desc,
    p.last_execution_time,
    LEFT(qt.query_sql_text, 300) AS [Query_Text]
FROM sys.query_store_plan AS p
INNER JOIN sys.query_store_query AS q ON p.query_id = q.query_id
INNER JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE p.force_failure_count > 0
ORDER BY p.force_failure_count DESC, p.last_execution_time DESC;

PRINT N'=== QUERY STORE OPTIONS ===';

SELECT
    actual_state_desc,
    desired_state_desc,
    current_storage_size_mb,
    max_storage_size_mb,
    query_capture_mode_desc,
    size_based_cleanup_mode_desc,
    stale_query_threshold_days,
    max_plans_per_query,
    wait_stats_capture_mode_desc
FROM sys.database_query_store_options;
