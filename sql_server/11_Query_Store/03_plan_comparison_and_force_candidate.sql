/*
================================================================================
Query Store — Plan Comparison and Force Candidate
================================================================================
Purpose:
    Rank all plans for one query_id by duration, CPU, and reads. Highlights the
    best-performing plan and prints the sp_query_store_force_plan command to run
    if you choose to force it.

Parameters:
    @QueryId        - Query Store query_id (required)
    @RecentHours    - only consider executions in this window (default 168 = 7d)
    @MinExecutions  - minimum executions per plan in the window (default 3)

Output:
    (1) Ranked plan comparison with BEST_CANDIDATE flag
    (2) Suggested FORCE / UNFORCE commands (printed, not executed)

Action:
    Validate the BEST_CANDIDATE plan is still appropriate (recent data, enough
    executions, not a one-off lucky run). Then run 04_force_or_unforce_plan.sql
    with @DryRun = 0.

    If elapsed is high but CPU/reads are low, the problem may be waits — correlate
    with 06_query_store_wait_stats_by_plan.sql before forcing.

Criticality: High
Prerequisites: Query Store enabled on current database
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @QueryId BIGINT = 57;  -- << CHANGE to target query_id
DECLARE @RecentHours INT = 168;
DECLARE @MinExecutions BIGINT = 3;
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

DECLARE @Cutoff DATETIME2(7) = DATEADD(HOUR, -@RecentHours, SYSDATETIME());

;WITH PlanAgg AS (
    SELECT
        p.query_id,
        p.plan_id,
        p.is_forced_plan,
        p.last_execution_time,
        SUM(rs.count_executions) AS count_executions,
        SUM(rs.avg_duration * rs.count_executions)
            / NULLIF(SUM(rs.count_executions), 0) AS avg_duration_us,
        SUM(rs.avg_cpu_time * rs.count_executions)
            / NULLIF(SUM(rs.count_executions), 0) AS avg_cpu_us,
        SUM(rs.avg_logical_io_reads * rs.count_executions)
            / NULLIF(SUM(rs.count_executions), 0) AS avg_logical_reads
    FROM sys.query_store_plan AS p
    INNER JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id
    WHERE p.query_id = @QueryId
      AND rs.last_execution_time >= @Cutoff
    GROUP BY
        p.query_id,
        p.plan_id,
        p.is_forced_plan,
        p.last_execution_time
    HAVING SUM(rs.count_executions) >= @MinExecutions
),
Ranked AS (
    SELECT
        pa.*,
        ROW_NUMBER() OVER (ORDER BY pa.avg_duration_us ASC, pa.avg_cpu_us ASC) AS duration_rank,
        ROW_NUMBER() OVER (ORDER BY pa.avg_cpu_us ASC, pa.avg_duration_us ASC) AS cpu_rank,
        MAX(pa.avg_duration_us) OVER () AS worst_duration_us
    FROM PlanAgg AS pa
)
SELECT
    r.query_id,
    r.plan_id,
    r.is_forced_plan,
    r.count_executions,
    r.avg_duration_us / 1000.0 AS [Avg_Duration_ms],
    r.avg_cpu_us / 1000.0 AS [Avg_CPU_ms],
    r.avg_logical_reads AS [Avg_Logical_Reads],
    r.last_execution_time,
    r.duration_rank,
    r.cpu_rank,
    CAST(
        100.0 * (r.avg_duration_us - MIN(r.avg_duration_us) OVER ())
        / NULLIF(MIN(r.avg_duration_us) OVER (), 0) AS DECIMAL(10, 1)
    ) AS [Pct_Slower_Than_Best],
    CASE
        WHEN r.duration_rank = 1 AND r.is_forced_plan = 0 THEN N'BEST_CANDIDATE — consider FORCE'
        WHEN r.duration_rank = 1 AND r.is_forced_plan = 1 THEN N'BEST_CANDIDATE — already forced'
        WHEN r.is_forced_plan = 1 AND r.avg_duration_us > MIN(r.avg_duration_us) OVER () * 1.2
            THEN N'FORCED_BUT_SLOW — consider UNFORCE'
        WHEN r.avg_duration_us = r.worst_duration_us
            THEN N'WORST_PLAN'
        ELSE N''
    END AS [Recommendation]
FROM Ranked AS r
ORDER BY r.avg_duration_us ASC;

DECLARE @BestPlanId BIGINT;
DECLARE @ForcedPlanId BIGINT;

IF OBJECT_ID(N'tempdb..#PlanAgg') IS NOT NULL DROP TABLE #PlanAgg;

SELECT
    p.plan_id,
    p.is_forced_plan,
    SUM(rs.avg_duration * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0) AS avg_duration_us
INTO #PlanAgg
FROM sys.query_store_plan AS p
INNER JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id
WHERE p.query_id = @QueryId
  AND rs.last_execution_time >= @Cutoff
GROUP BY p.plan_id, p.is_forced_plan
HAVING SUM(rs.count_executions) >= @MinExecutions;

SELECT TOP (1) @BestPlanId = plan_id
FROM #PlanAgg
ORDER BY avg_duration_us ASC;

SELECT TOP (1) @ForcedPlanId = plan_id
FROM #PlanAgg
WHERE is_forced_plan = 1;

DROP TABLE #PlanAgg;

PRINT N'';
PRINT N'=== SUGGESTED COMMANDS (review before running 04_force_or_unforce_plan.sql) ===';

IF @BestPlanId IS NOT NULL AND (@ForcedPlanId IS NULL OR @ForcedPlanId <> @BestPlanId)
BEGIN
    PRINT N'-- Force best plan by duration (last ' + CAST(@RecentHours AS NVARCHAR(10)) + N' hours):';
    PRINT N'EXEC sys.sp_query_store_force_plan @query_id = ' + CAST(@QueryId AS NVARCHAR(20))
        + N', @plan_id = ' + CAST(@BestPlanId AS NVARCHAR(20)) + N';';
END
ELSE IF @BestPlanId IS NOT NULL AND @ForcedPlanId = @BestPlanId
    PRINT N'Best plan (plan_id ' + CAST(@BestPlanId AS NVARCHAR(20)) + N') is already forced.';

IF @ForcedPlanId IS NOT NULL AND @BestPlanId IS NOT NULL AND @ForcedPlanId <> @BestPlanId
BEGIN
    PRINT N'';
    PRINT N'-- Unforce current forced plan before forcing the better one:';
    PRINT N'EXEC sys.sp_query_store_unforce_plan @query_id = ' + CAST(@QueryId AS NVARCHAR(20))
        + N', @plan_id = ' + CAST(@ForcedPlanId AS NVARCHAR(20)) + N';';
END;

IF @BestPlanId IS NULL
    PRINT N'No plan met @MinExecutions in the recent window. Lower @MinExecutions or widen @RecentHours.';
