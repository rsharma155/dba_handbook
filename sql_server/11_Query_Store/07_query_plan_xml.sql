/*
================================================================================
Query Store — Retrieve Plan XML for a plan_id
================================================================================
Purpose:
    Return the showplan XML for one Query Store plan_id. Open in SSMS or save to
    .sqlplan for visual comparison after scripts 02/03 identify candidate plans.

Parameters:
    @QueryId - optional filter; must match plan if provided
    @PlanId  - Query Store plan_id (required)

Output:
    plan_id, query_id, compile/execution metadata, query_plan XML

Criticality: Medium
Prerequisites: Query Store enabled on current database
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @QueryId BIGINT = 57;  -- << optional; set NULL to skip query_id check
DECLARE @PlanId BIGINT = 57;    -- << CHANGE to target plan_id
DECLARE @CurrentDatabase SYSNAME = DB_NAME();
DECLARE @ErrMsg NVARCHAR(4000);

IF @PlanId IS NULL
BEGIN
    RAISERROR(N'Set @PlanId to the plan_id from 02_query_id_plan_breakdown.sql.', 16, 1);
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

SELECT
    p.query_id,
    p.plan_id,
    p.is_forced_plan,
    p.engine_version,
    p.compatibility_level,
    p.count_compiles,
    p.initial_compile_start_time,
    p.last_compile_start_time,
    p.last_execution_time,
    p.query_plan,
    LEFT(qt.query_sql_text, 500) AS [Query_Text]
FROM sys.query_store_plan AS p
INNER JOIN sys.query_store_query AS q ON p.query_id = q.query_id
INNER JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
WHERE p.plan_id = @PlanId
  AND (@QueryId IS NULL OR p.query_id = @QueryId);

IF @@ROWCOUNT = 0
BEGIN
    SET @ErrMsg = N'plan_id ' + CAST(@PlanId AS NVARCHAR(20)) + N' not found';
    IF @QueryId IS NOT NULL
        SET @ErrMsg = @ErrMsg + N' for query_id ' + CAST(@QueryId AS NVARCHAR(20));
    SET @ErrMsg = @ErrMsg + N' in database ' + QUOTENAME(@CurrentDatabase) + N'.';
    RAISERROR(@ErrMsg, 16, 1);
END;
