/*
================================================================================
Query Store — Force or Unforce a Plan
================================================================================
Purpose:
    Apply or remove a forced plan after validating with scripts 02 and 03.
    Defaults to dry-run so you can confirm parameters before executing.

Parameters:
    @QueryId  - Query Store query_id
    @PlanId   - Query Store plan_id to force or unforce
    @Action   - FORCE or UNFORCE
    @DryRun   - 1 = print only (default), 0 = execute

Action:
    After forcing, monitor with 05_forced_plans_monitor.sql. Re-check regressions
    after statistics updates, index changes, or CE changes.

Criticality: High — modifies Query Store plan forcing state
Prerequisites: Query Store enabled; ALTER permission on database
================================================================================
*/

SET NOCOUNT ON;

DECLARE @QueryId BIGINT = 57;   -- << CHANGE
DECLARE @PlanId BIGINT = 57;    -- << CHANGE
DECLARE @Action NVARCHAR(10) = N'FORCE';  -- FORCE | UNFORCE
DECLARE @DryRun BIT = 1;        -- 1 = preview only, 0 = execute
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

IF @QueryId IS NULL OR @PlanId IS NULL
BEGIN
    RAISERROR(N'Set @QueryId and @PlanId before running.', 16, 1);
    RETURN;
END;

IF @Action NOT IN (N'FORCE', N'UNFORCE')
BEGIN
    RAISERROR(N'@Action must be FORCE or UNFORCE.', 16, 1);
    RETURN;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.query_store_plan
    WHERE query_id = @QueryId
      AND plan_id = @PlanId
)
BEGIN
    SET @ErrMsg = N'plan_id ' + CAST(@PlanId AS NVARCHAR(20)) + N' does not belong to query_id '
        + CAST(@QueryId AS NVARCHAR(20)) + N' in database ' + QUOTENAME(@CurrentDatabase) + N'.';
    RAISERROR(@ErrMsg, 16, 1);
    RETURN;
END;

PRINT N'=== PRE-FLIGHT: plan snapshot ===';

SELECT
    q.query_id,
    p.plan_id,
    p.is_forced_plan,
    p.force_failure_count,
    p.last_force_failure_reason_desc,
    p.last_execution_time,
    LEFT(qt.query_sql_text, 300) AS [Query_Text]
FROM sys.query_store_query AS q
INNER JOIN sys.query_store_plan AS p ON q.query_id = p.query_id
INNER JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE q.query_id = @QueryId
  AND p.plan_id = @PlanId;

IF @DryRun = 1
BEGIN
    PRINT N'';
    PRINT N'DRY RUN (@DryRun = 1). Set @DryRun = 0 to execute:';
    IF @Action = N'FORCE'
        PRINT N'EXEC sys.sp_query_store_force_plan @query_id = '
            + CAST(@QueryId AS NVARCHAR(20)) + N', @plan_id = ' + CAST(@PlanId AS NVARCHAR(20)) + N';';
    ELSE
        PRINT N'EXEC sys.sp_query_store_unforce_plan @query_id = '
            + CAST(@QueryId AS NVARCHAR(20)) + N', @plan_id = ' + CAST(@PlanId AS NVARCHAR(20)) + N';';
    RETURN;
END;

IF @Action = N'FORCE'
BEGIN
    EXEC sys.sp_query_store_force_plan
        @query_id = @QueryId,
        @plan_id = @PlanId;
    PRINT N'Forced plan_id ' + CAST(@PlanId AS NVARCHAR(20)) + N' for query_id ' + CAST(@QueryId AS NVARCHAR(20)) + N'.';
END
ELSE
BEGIN
    EXEC sys.sp_query_store_unforce_plan
        @query_id = @QueryId,
        @plan_id = @PlanId;
    PRINT N'Unforced plan_id ' + CAST(@PlanId AS NVARCHAR(20)) + N' for query_id ' + CAST(@QueryId AS NVARCHAR(20)) + N'.';
END;

SELECT
    p.plan_id,
    p.is_forced_plan,
    p.force_failure_count,
    p.last_force_failure_reason_desc
FROM sys.query_store_plan AS p
WHERE p.query_id = @QueryId
  AND p.plan_id = @PlanId;
