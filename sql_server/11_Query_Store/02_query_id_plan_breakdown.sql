/*
================================================================================
Query Store — Plan Breakdown for a Single query_id
================================================================================
Purpose:
    List every plan compiled for one query_id with runtime stats, force status,
    and last execution time. Use after 01_multi_plan_queries.sql identifies a
    suspect query.

Parameters:
    @QueryId - Query Store query_id to investigate (required)

Output:
    (1) Query text and metadata
    (2) Per-plan runtime stats (duration, CPU, reads, executions)
    (3) Plan compile metadata

Action:
    Compare avg_duration_ms across plan_id values. If one plan is clearly
    better on recent executions, review it in script 03 before forcing.

Criticality: High
Prerequisites: Query Store enabled on current database
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @QueryId BIGINT = 57;  -- << CHANGE to target query_id
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

IF NOT EXISTS (SELECT 1 FROM sys.query_store_query WHERE query_id = @QueryId)
BEGIN
    SET @ErrMsg = N'query_id ' + CAST(@QueryId AS NVARCHAR(20))
        + N' not found in Query Store for database ' + QUOTENAME(@CurrentDatabase) + N'.';
    RAISERROR(@ErrMsg, 16, 1);
    RETURN;
END;

PRINT N'=== QUERY METADATA (query_id = ' + CAST(@QueryId AS NVARCHAR(20)) + N') ===';

SELECT
    q.query_id,
    q.query_text_id,
    q.object_id,
    OBJECT_SCHEMA_NAME(q.object_id) AS [Schema_Name],
    OBJECT_NAME(q.object_id) AS [Object_Name],
    q.query_parameterization_type_desc,
    q.initial_compile_start_time,
    q.last_compile_start_time,
    q.last_execution_time,
    qt.query_sql_text
FROM sys.query_store_query AS q
INNER JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE q.query_id = @QueryId;

PRINT N'=== PLAN RUNTIME STATS ===';

SELECT
    q.query_id,
    p.plan_id,
    p.is_forced_plan,
    p.is_natively_compiled,
    p.force_failure_count,
    p.last_force_failure_reason_desc,
    p.count_compiles,
    p.initial_compile_start_time AS [Plan_First_Compiled],
    p.last_compile_start_time AS [Plan_Last_Compiled],
    p.last_execution_time AS [Plan_Last_Execution],
    SUM(rs.count_executions) AS [Count_Executions],
    SUM(rs.avg_duration * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS [Avg_Duration_ms],
    SUM(rs.avg_cpu_time * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS [Avg_CPU_ms],
    SUM(rs.avg_logical_io_reads * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) AS [Avg_Logical_Reads],
    SUM(rs.avg_physical_io_reads * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) AS [Avg_Physical_Reads],
    MIN(rs.first_execution_time) AS [Stats_First_Execution],
    MAX(rs.last_execution_time) AS [Stats_Last_Execution]
FROM sys.query_store_query AS q
INNER JOIN sys.query_store_plan AS p ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id
WHERE q.query_id = @QueryId
GROUP BY
    q.query_id,
    p.plan_id,
    p.is_forced_plan,
    p.is_natively_compiled,
    p.force_failure_count,
    p.last_force_failure_reason_desc,
    p.count_compiles,
    p.initial_compile_start_time,
    p.last_compile_start_time,
    p.last_execution_time
ORDER BY [Avg_Duration_ms] ASC;

PRINT N'--- Next step: run 03_plan_comparison_and_force_candidate.sql with same @QueryId ---';
