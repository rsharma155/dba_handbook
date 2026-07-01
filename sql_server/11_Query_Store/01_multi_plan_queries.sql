/*
================================================================================
Query Store — Queries With Multiple Plans
================================================================================
Purpose:
    Find queries that have compiled more than one plan in Query Store. Multiple
    plans often indicate parameter sniffing, data skew, CE changes, or index
    changes. Use this as the first step when investigating unstable performance.

Workflow:
    (1) Run this script in the target database.
    (2) Note query_id values with high plan_count or high duration.
    (3) Drill down with 02_query_id_plan_breakdown.sql and
        03_plan_comparison_and_force_candidate.sql.

Parameters:
    @TopN           - rows to return (default 20)
    @MinPlanCount   - minimum distinct plans required (default 2)
    @MinExecutions  - minimum total executions across all plans (default 5)

Output:
    query_id, plan_count, execution totals, worst/best avg duration, query text

Action:
    High plan_count + large duration gap between best and worst plan suggests
    plan regression or sniffing. Do not force a plan until you validate the
  best plan on recent workload (see script 03).

Criticality: High
Prerequisites: Query Store enabled on current database (SQL Server 2016+)
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @TopN INT = 20;
DECLARE @MinPlanCount INT = 2;
DECLARE @MinExecutions BIGINT = 5;
DECLARE @CurrentDatabase SYSNAME = DB_NAME();
DECLARE @ErrMsg NVARCHAR(4000);

IF NOT EXISTS (
    SELECT 1
    FROM sys.databases
    WHERE database_id = DB_ID()
      AND is_query_store_on = 1
)
BEGIN
    SET @ErrMsg = N'Query Store is not enabled on database ' + QUOTENAME(@CurrentDatabase)
        + N'. Run: ALTER DATABASE ' + QUOTENAME(@CurrentDatabase) + N' SET QUERY_STORE = ON;';
    RAISERROR(@ErrMsg, 16, 1);
    RETURN;
END;

;WITH PlanCounts AS (
    SELECT
        q.query_id,
        q.query_text_id,
        q.object_id,
        COUNT(DISTINCT p.plan_id) AS plan_count
    FROM sys.query_store_query AS q
    INNER JOIN sys.query_store_plan AS p ON q.query_id = p.query_id
    GROUP BY q.query_id, q.query_text_id, q.object_id
    HAVING COUNT(DISTINCT p.plan_id) >= @MinPlanCount
),
PlanStats AS (
    SELECT
        p.query_id,
        p.plan_id,
        SUM(rs.count_executions) AS count_executions,
        SUM(rs.avg_duration * rs.count_executions)
            / NULLIF(SUM(rs.count_executions), 0) AS avg_duration_us,
        SUM(rs.avg_cpu_time * rs.count_executions)
            / NULLIF(SUM(rs.count_executions), 0) AS avg_cpu_us,
        SUM(rs.avg_logical_io_reads * rs.count_executions)
            / NULLIF(SUM(rs.count_executions), 0) AS avg_logical_reads,
        MAX(rs.last_execution_time) AS last_execution_time
    FROM sys.query_store_plan AS p
    INNER JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id
    GROUP BY p.query_id, p.plan_id
),
QueryRollup AS (
    SELECT
        ps.query_id,
        SUM(ps.count_executions) AS total_executions,
        MIN(ps.avg_duration_us) AS best_avg_duration_us,
        MAX(ps.avg_duration_us) AS worst_avg_duration_us,
        MAX(ps.last_execution_time) AS last_execution_time
    FROM PlanStats AS ps
    GROUP BY ps.query_id
    HAVING SUM(ps.count_executions) >= @MinExecutions
)
SELECT TOP (@TopN)
    pc.query_id,
    pc.plan_count,
    pc.object_id,
    qr.total_executions,
    qr.best_avg_duration_us / 1000.0 AS [Best_Plan_Avg_Duration_ms],
    qr.worst_avg_duration_us / 1000.0 AS [Worst_Plan_Avg_Duration_ms],
    CAST(
        100.0 * (qr.worst_avg_duration_us - qr.best_avg_duration_us)
        / NULLIF(qr.best_avg_duration_us, 0) AS DECIMAL(10, 1)
    ) AS [Duration_Spread_Pct],
    qr.last_execution_time,
    LEFT(qt.query_sql_text, 400) AS [Query_Text]
FROM PlanCounts AS pc
INNER JOIN QueryRollup AS qr ON pc.query_id = qr.query_id
INNER JOIN sys.query_store_query_text AS qt ON pc.query_text_id = qt.query_text_id
ORDER BY
    pc.plan_count DESC,
    [Duration_Spread_Pct] DESC,
    qr.worst_avg_duration_us DESC;

PRINT N'--- Next step: set @QueryId in 02_query_id_plan_breakdown.sql ---';
