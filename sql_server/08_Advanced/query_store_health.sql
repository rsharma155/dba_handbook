/*
================================================================================
SQL Server Query Store Health Monitor
================================================================================
Description:
    Reports Query Store operational status across all databases and detects
    true plan regressions (multi-plan queries where the recent slow plan is
    significantly worse than the best baseline) and lists forced plans.

Output:
    (1) Query Store status per database (READ_ONLY, STATE_MISMATCH, NEAR_MAX, OK)
    (2) Plan regression details with query text, plan IDs, and regression %
    (3) Forced plans and force failure counts

Action:
    For databases with Health_Status = READ_ONLY: increase max_storage_size_mb
    or clear the query store (EXEC sp_query_store_flush_db) if space is full.
    For STATE_MISMATCH: run ALTER DATABASE [DBName] SET QUERY_STORE = ON.
    For regression plans > 50%: consider forcing the baseline plan:
        EXEC sp_query_store_force_plan @query_id, @baseline_plan_id;
    For force failures: investigate why the plan cannot be forced (missing index,
    plan guidability issues).

Parameters:
    @DatabaseList - comma-separated database names or NULL for all user DBs
    @RegressionPctThreshold - minimum regression % to flag (default 50)
    @RecentHours - lookback window for recent execution (default 24)
    @LookbackHours - historical window for baseline (default 168)

Criticality: High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @RegressionPctThreshold DECIMAL(10,2) = 50.0;
DECLARE @RecentHours INT = 24;
DECLARE @LookbackHours INT = 168;

-- 1. Query Store Status (Instance-Wide)
PRINT N'--- Query Store Status (All User DBs) ---';
IF OBJECT_ID(N'tempdb..#QSStatus') IS NOT NULL DROP TABLE #QSStatus;
CREATE TABLE #QSStatus (
    [Database_Name]     SYSNAME         NOT NULL,
    [Actual_State]      NVARCHAR(60)    NULL,
    [Desired_State]     NVARCHAR(60)    NULL,
    [Current_Size_MB]   BIGINT          NULL,
    [Max_Size_MB]       BIGINT          NULL,
    [Capture_Mode]      NVARCHAR(60)    NULL,
    [Health_Status]     NVARCHAR(20)    NULL
);

DECLARE @db_name SYSNAME, @sql NVARCHAR(MAX);
DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state = 0
      AND is_in_standby = 0
      AND database_id > 4
      AND is_query_store_on = 1
      AND (
            @DatabaseList IS NULL
            OR name IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@DatabaseList, N',') WHERE LTRIM(RTRIM(value)) <> N'')
          )
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'USE ' + QUOTENAME(@db_name) + N';
    INSERT INTO #QSStatus (Database_Name, Actual_State, Desired_State, Current_Size_MB, Max_Size_MB, Capture_Mode, Health_Status)
    SELECT
        DB_NAME(),
        qs.actual_state_desc,
        qs.desired_state_desc,
        qs.current_storage_size_mb,
        qs.max_storage_size_mb,
        qs.query_capture_mode_desc,
        CASE
            WHEN qs.actual_state_desc = N''READ_ONLY'' THEN N''READ_ONLY''
            WHEN qs.actual_state_desc <> qs.desired_state_desc THEN N''STATE_MISMATCH''
            WHEN qs.current_storage_size_mb > (qs.max_storage_size_mb * 0.9) THEN N''NEAR_MAX''
            ELSE N''OK''
        END
    FROM sys.database_query_store_options AS qs;';

    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(N'query_store_health: Database [%s] failed: %s', 10, 1, @db_name, @ErrMsg);
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @db_name;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT * FROM #QSStatus ORDER BY [Database_Name];
DROP TABLE #QSStatus;

-- 2. True Plan Regressions
PRINT N'--- Query Store Plan Regressions ---';
IF OBJECT_ID(N'dbo.sp_DBA_QueryStoreRegressions', N'P') IS NOT NULL
BEGIN
    EXEC dbo.sp_DBA_QueryStoreRegressions
        @DatabaseList = @DatabaseList,
        @RegressionPctThreshold = @RegressionPctThreshold,
        @RecentHours = @RecentHours,
        @LookbackHours = @LookbackHours,
        @MinExecutions = 5,
        @TopPerDatabase = 10,
        @IncludeForcedPlans = 1;
END
ELSE
BEGIN
    RAISERROR(N'Deploy 00_Framework/sp_DBA_QueryStoreRegressions.sql for true regression detection.', 16, 1);
END;
