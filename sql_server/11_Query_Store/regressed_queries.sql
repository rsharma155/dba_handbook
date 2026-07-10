/*
================================================================================
SQL Server Query Store Plan Regression Diagnostics
================================================================================
Description:
    Wrapper for sp_DBA_QueryStoreRegressions. Detects true plan regressions —
    queries with multiple plans where the recent slow plan performs significantly
    worse than the best historical plan for the same query_id.

Output:
    (1) Plan regressions with query text, plan IDs, regression percentage
    (2) Forced plans and force failure counts

Action:
    For regression plans > @RegressionPctThreshold: force the baseline plan:
        EXEC sp_query_store_force_plan @query_id, @baseline_plan_id;
    Monitor forced plans for regression. If regression does not resolve,
    investigate index changes or statistics updates that may have caused the
    plan change. Run after any significant database changes (index maintenance,
    statistics update, large data loads).

Parameters:
    @DatabaseList - comma-separated database names or NULL for all user DBs
    @RegressionPctThreshold - minimum regression % to flag (default 50)
    @RecentHours - lookback for regression data (default 24)
    @LookbackHours - historical window for baseline plans (default 168)

Prerequisites: sp_DBA_QueryStoreRegressions (deploy via 00_Framework/00_Deploy_Framework.ps1)

Criticality: High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @RegressionPctThreshold DECIMAL(10,2) = 50.0;
DECLARE @RecentHours INT = 24;
DECLARE @LookbackHours INT = 168;

IF OBJECT_ID(N'dbo.sp_DBA_QueryStoreRegressions', N'P') IS NULL
BEGIN
    SELECT
        N'Query Store Regression Dependency' AS [Result_Set],
        N'WARNING' AS [Severity],
        N'dbo.sp_DBA_QueryStoreRegressions' AS [Dependency],
        N'Not deployed' AS [Status],
        N'This ad-hoc regression report was skipped because the optional framework procedure is not available.' AS [Message],
        N'Deploy 00_Framework/sp_DBA_QueryStoreRegressions.sql or run 00_Framework/00_Deploy_Framework.ps1, then re-run this script.' AS [How_To_Deploy];
    RETURN;
END;

EXEC dbo.sp_DBA_QueryStoreRegressions
    @DatabaseList = @DatabaseList,
    @RegressionPctThreshold = @RegressionPctThreshold,
    @RecentHours = @RecentHours,
    @LookbackHours = @LookbackHours,
    @MinExecutions = 5,
    @TopPerDatabase = 20,
    @IncludeForcedPlans = 1;
