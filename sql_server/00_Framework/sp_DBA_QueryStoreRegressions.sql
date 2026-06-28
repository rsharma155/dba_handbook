/*
================================================================================
sp_DBA_QueryStoreRegressions - True plan regression detection across databases
================================================================================
Detects queries with multiple plans where the slowest recent plan is significantly
worse than the best-performing plan for the same query_id.

Prerequisites: Query Store enabled per database (SQL Server 2016+).

Usage:
    EXEC dbo.sp_DBA_QueryStoreRegressions;
    EXEC dbo.sp_DBA_QueryStoreRegressions
        @DatabaseList = N'SalesDB',
        @RegressionPctThreshold = 50,
        @RecentHours = 24,
        @LookbackHours = 168,
        @MinExecutions = 5,
        @TopPerDatabase = 10;
================================================================================
*/
IF OBJECT_ID(N'dbo.sp_DBA_QueryStoreRegressions', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DBA_QueryStoreRegressions AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_DBA_QueryStoreRegressions
    @DatabaseList           NVARCHAR(MAX) = NULL,
    @RegressionPctThreshold DECIMAL(10,2) = 50.0,
    @RecentHours            INT = 24,
    @LookbackHours          INT = 168,
    @MinExecutions          INT = 5,
    @TopPerDatabase         INT = 10,
    @IncludeForcedPlans     BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    IF @RegressionPctThreshold < 0 SET @RegressionPctThreshold = 0;
    IF @RecentHours < 1 SET @RecentHours = 1;
    IF @LookbackHours < @RecentHours SET @LookbackHours = @RecentHours;
    IF @MinExecutions < 1 SET @MinExecutions = 1;
    IF @TopPerDatabase < 1 SET @TopPerDatabase = 1;

    IF OBJECT_ID(N'tempdb..#QSRegression') IS NOT NULL DROP TABLE #QSRegression;
    CREATE TABLE #QSRegression (
        [Database_Name]             SYSNAME         NOT NULL,
        [Query_ID]                  BIGINT          NOT NULL,
        [Regressed_Plan_ID]         BIGINT          NOT NULL,
        [Baseline_Plan_ID]          BIGINT          NOT NULL,
        [Regressed_Avg_Duration_ms] DECIMAL(18,4)   NOT NULL,
        [Baseline_Avg_Duration_ms]  DECIMAL(18,4)   NOT NULL,
        [Regression_Pct]            DECIMAL(10,2)   NOT NULL,
        [Regressed_Executions]      BIGINT          NOT NULL,
        [Baseline_Executions]       BIGINT          NOT NULL,
        [Regressed_Plan_Last_Exec]  DATETIME2(7)    NULL,
        [Baseline_Plan_Last_Exec]   DATETIME2(7)    NULL,
        [Query_Text]                NVARCHAR(MAX)   NULL
    );

    IF OBJECT_ID(N'tempdb..#QSDbTargets') IS NOT NULL DROP TABLE #QSDbTargets;
    CREATE TABLE #QSDbTargets (database_id INT NOT NULL PRIMARY KEY, database_name SYSNAME NOT NULL);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
    BEGIN
        INSERT INTO #QSDbTargets (database_id, database_name)
        SELECT d.database_id, d.name
        FROM sys.databases AS d
        INNER JOIN (
            SELECT LTRIM(RTRIM(value)) AS database_name
            FROM STRING_SPLIT(@DatabaseList, N',')
            WHERE LTRIM(RTRIM(value)) <> N''
        ) AS requested ON requested.database_name = d.name
        WHERE d.state = 0
          AND d.is_in_standby = 0
          AND d.is_query_store_on = 1;
    END
    ELSE
    BEGIN
        INSERT INTO #QSDbTargets (database_id, database_name)
        SELECT database_id, name
        FROM sys.databases
        WHERE state = 0
          AND is_in_standby = 0
          AND database_id > 4
          AND is_query_store_on = 1;
    END;

    DECLARE @db_name SYSNAME;
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @RegressionFactor NVARCHAR(30) = CAST((1.0 + (@RegressionPctThreshold / 100.0)) AS NVARCHAR(30));

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM #QSDbTargets ORDER BY database_name;

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';
        ;WITH PlanMetrics AS (
            SELECT
                q.query_id,
                qt.query_sql_text,
                p.plan_id,
                SUM(rs.count_executions) AS executions,
                AVG(CAST(rs.avg_duration AS FLOAT)) / 1000.0 AS avg_duration_ms,
                MAX(rs.last_execution_time) AS last_execution_time
            FROM sys.query_store_query AS q
            INNER JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
            INNER JOIN sys.query_store_plan AS p ON q.query_id = p.query_id
            INNER JOIN sys.query_store_runtime_stats AS rs ON p.plan_id = rs.plan_id
            INNER JOIN sys.query_store_runtime_stats_interval AS rsi
                ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
            WHERE rsi.start_time >= DATEADD(HOUR, -' + CAST(@LookbackHours AS NVARCHAR(10)) + N', SYSUTCDATETIME())
            GROUP BY q.query_id, qt.query_sql_text, p.plan_id
        ),
        MultiPlan AS (
            SELECT query_id
            FROM PlanMetrics
            GROUP BY query_id
            HAVING COUNT(DISTINCT plan_id) > 1
        ),
        Ranked AS (
            SELECT
                pm.query_id,
                pm.query_sql_text,
                pm.plan_id,
                pm.executions,
                pm.avg_duration_ms,
                pm.last_execution_time,
                ROW_NUMBER() OVER (PARTITION BY pm.query_id ORDER BY pm.avg_duration_ms DESC, pm.last_execution_time DESC) AS slow_rank,
                ROW_NUMBER() OVER (PARTITION BY pm.query_id ORDER BY pm.avg_duration_ms ASC, pm.executions DESC) AS fast_rank
            FROM PlanMetrics AS pm
            INNER JOIN MultiPlan AS mp ON pm.query_id = mp.query_id
            WHERE pm.executions >= ' + CAST(@MinExecutions AS NVARCHAR(10)) + N'
        ),
        Regressed AS (
            SELECT TOP (' + CAST(@TopPerDatabase AS NVARCHAR(10)) + N')
                DB_NAME() AS database_name,
                slow.query_id,
                slow.plan_id AS regressed_plan_id,
                fast.plan_id AS baseline_plan_id,
                slow.avg_duration_ms AS regressed_avg_duration_ms,
                fast.avg_duration_ms AS baseline_avg_duration_ms,
                CAST((slow.avg_duration_ms - fast.avg_duration_ms) * 100.0 / NULLIF(fast.avg_duration_ms, 0) AS DECIMAL(10,2)) AS regression_pct,
                slow.executions AS regressed_executions,
                fast.executions AS baseline_executions,
                slow.last_execution_time AS regressed_plan_last_exec,
                fast.last_execution_time AS baseline_plan_last_exec,
                slow.query_sql_text
            FROM Ranked AS slow
            INNER JOIN Ranked AS fast
                ON slow.query_id = fast.query_id
               AND fast.fast_rank = 1
            WHERE slow.slow_rank = 1
              AND slow.plan_id <> fast.plan_id
              AND slow.avg_duration_ms > fast.avg_duration_ms * ' + @RegressionFactor + N'
              AND slow.last_execution_time >= DATEADD(HOUR, -' + CAST(@RecentHours AS NVARCHAR(10)) + N', SYSUTCDATETIME())
            ORDER BY regression_pct DESC
        )
        INSERT INTO #QSRegression
        SELECT
            database_name,
            query_id,
            regressed_plan_id,
            baseline_plan_id,
            regressed_avg_duration_ms,
            baseline_avg_duration_ms,
            regression_pct,
            regressed_executions,
            baseline_executions,
            regressed_plan_last_exec,
            baseline_plan_last_exec,
            query_sql_text
        FROM Regressed;';

        BEGIN TRY
            EXEC sys.sp_executesql @SQL;
        END TRY
        BEGIN CATCH
            DECLARE @ErrMsg1 NVARCHAR(4000) = ERROR_MESSAGE();
            RAISERROR(N'sp_DBA_QueryStoreRegressions: Database [%s] failed: %s', 10, 1, @db_name, @ErrMsg1);
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @db_name;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    SELECT
        Database_Name,
        Query_ID,
        Regressed_Plan_ID,
        Baseline_Plan_ID,
        Regressed_Avg_Duration_ms,
        Baseline_Avg_Duration_ms,
        Regression_Pct,
        Regressed_Executions,
        Baseline_Executions,
        Regressed_Plan_Last_Exec,
        Baseline_Plan_Last_Exec,
        Query_Text
    FROM #QSRegression
    ORDER BY Regression_Pct DESC, Regressed_Avg_Duration_ms DESC;

    IF @IncludeForcedPlans = 1
    BEGIN
        SELECT N'FORCED PLANS' AS [Section];

        IF OBJECT_ID(N'tempdb..#QSForced') IS NOT NULL DROP TABLE #QSForced;
        CREATE TABLE #QSForced (
            [Database_Name] SYSNAME NOT NULL,
            [Query_ID] BIGINT NOT NULL,
            [Plan_ID] BIGINT NOT NULL,
            [Is_Forced] BIT NOT NULL,
            [Force_Failure_Count] INT NULL,
            [Query_Text] NVARCHAR(MAX) NULL
        );

        DECLARE @db_name2 SYSNAME;
        DECLARE @SQL2 NVARCHAR(MAX);

        DECLARE forced_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT database_name FROM #QSDbTargets ORDER BY database_name;

        OPEN forced_cursor;
        FETCH NEXT FROM forced_cursor INTO @db_name2;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @SQL2 = N'USE ' + QUOTENAME(@db_name2) + N';
            INSERT INTO #QSForced
            SELECT
                DB_NAME(),
                q.query_id,
                p.plan_id,
                p.is_forced_plan,
                p.force_failure_count,
                qt.query_sql_text
            FROM sys.query_store_plan AS p
            INNER JOIN sys.query_store_query AS q ON p.query_id = q.query_id
            INNER JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
            WHERE p.is_forced_plan = 1
               OR p.force_failure_count > 0;';

            BEGIN TRY
                EXEC sys.sp_executesql @SQL2;
            END TRY
            BEGIN CATCH
                DECLARE @ErrMsg2 NVARCHAR(4000) = ERROR_MESSAGE();
                RAISERROR(N'sp_DBA_QueryStoreRegressions forced-plan section: Database [%s] failed: %s', 10, 1, @db_name2, @ErrMsg2);
            END CATCH;

            FETCH NEXT FROM forced_cursor INTO @db_name2;
        END;

        CLOSE forced_cursor;
        DEALLOCATE forced_cursor;

        SELECT * FROM #QSForced ORDER BY Database_Name, Query_ID;
        DROP TABLE #QSForced;
    END;

    DROP TABLE #QSRegression;
    DROP TABLE #QSDbTargets;
END;
GO
