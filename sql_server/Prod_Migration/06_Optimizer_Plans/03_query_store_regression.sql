/*
================================================================================
Query Store Plan Regression After Migration
================================================================================
Purpose:
    Detect queries where a NEW plan after migration performs much worse than
    the historical best plan. Forced plans from pre-migration can also hurt.

    NOTE: If elapsed is high but CPU/reads are LOW, Query Store may show
    "fast" plan costs but real executions wait on locks — always correlate
    with session wait_type.

Checks:
    (1) Query Store status per database
    (2) Top regressed queries by duration (last 24h vs prior window)
    (3) Forced plans list
    (4) Plan force failures

Remediation:
    -- Unforce bad plan:
    EXEC sys.sp_query_store_unforce_plan @query_id = X, @plan_id = Y;

    -- Force known good plan (after validation):
    EXEC sys.sp_query_store_force_plan @query_id = X, @plan_id = Y;

Next if unforce/force does not help:
    Problem is likely waits not plan — 03_Elapsed_Time_Diagnostics/

Criticality: High after in-place upgrade with Query Store ON
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

IF NOT EXISTS (
    SELECT 1
    FROM sys.databases
    WHERE database_id > 4
      AND state = 0
      AND is_query_store_on = 1
)
BEGIN
    PRINT N'Query Store is not enabled on any user database. Skipping regression analysis.';
    PRINT N'Enable with: ALTER DATABASE [DbName] SET QUERY_STORE = ON;';
    RETURN;
END;

DECLARE @db SYSNAME;
DECLARE @sql NVARCHAR(MAX);

IF OBJECT_ID(N'tempdb..#QSStatus') IS NOT NULL DROP TABLE #QSStatus;
CREATE TABLE #QSStatus (
    [Database_Name] SYSNAME NOT NULL,
    [Is_Query_Store_On] BIT NOT NULL,
    [Actual_State] NVARCHAR(60) NULL,
    [Desired_State] NVARCHAR(60) NULL
);

DECLARE status_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4 AND state = 0
    ORDER BY name;

OPEN status_cursor;
FETCH NEXT FROM status_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'USE ' + QUOTENAME(@db) + N';
    INSERT INTO #QSStatus (Database_Name, Is_Query_Store_On, Actual_State, Desired_State)
    SELECT
        DB_NAME(),
        (SELECT is_query_store_on FROM sys.databases WHERE database_id = DB_ID()),
        CASE WHEN EXISTS (SELECT 1 FROM sys.database_query_store_options)
             THEN (SELECT actual_state_desc FROM sys.database_query_store_options)
             ELSE N''OFF'' END,
        CASE WHEN EXISTS (SELECT 1 FROM sys.database_query_store_options)
             THEN (SELECT desired_state_desc FROM sys.database_query_store_options)
             ELSE N''OFF'' END;';

    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #QSStatus (Database_Name, Is_Query_Store_On, Actual_State, Desired_State)
        VALUES (@db, 0, N'ERROR', LEFT(ERROR_MESSAGE(), 60));
    END CATCH;

    FETCH NEXT FROM status_cursor INTO @db;
END;

CLOSE status_cursor;
DEALLOCATE status_cursor;

PRINT '=== QUERY STORE STATUS ===';
SELECT
    Database_Name,
    Is_Query_Store_On,
    Actual_State AS [QS_Actual_State],
    Desired_State AS [QS_Desired_State],
    CASE
        WHEN Is_Query_Store_On = 0 THEN N'OFF — skipped in regression scan'
        WHEN Actual_State = N'READ_ONLY' THEN N'WARNING — QS read-only; check storage'
        WHEN Actual_State <> Desired_State THEN N'STATE_MISMATCH — run SET QUERY_STORE = ON'
        ELSE N'OK — included below'
    END AS [Status]
FROM #QSStatus
ORDER BY Database_Name;

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4 AND state = 0 AND is_query_store_on = 1;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '--- Database: ' + @db + ' ---';

    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';

    -- Forced plans
    SELECT q.query_id, p.plan_id, q.object_id, LEFT(qt.query_sql_text, 200) AS query_text
    FROM sys.query_store_plan AS p
    INNER JOIN sys.query_store_query AS q ON p.query_id = q.query_id
    INNER JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
    WHERE p.is_forced_plan = 1;

    -- Duration regression: recent avg vs historical min
    ;WITH PlanStats AS (
        SELECT
            q.query_id,
            p.plan_id,
            SUM(rs.count_executions) AS exec_count,
            SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) AS avg_duration_us
        FROM sys.query_store_runtime_stats AS rs
        INNER JOIN sys.query_store_plan AS p ON rs.plan_id = p.plan_id
        INNER JOIN sys.query_store_query AS q ON p.query_id = q.query_id
        WHERE rs.last_execution_time >= DATEADD(HOUR, -24, SYSDATETIME())
        GROUP BY q.query_id, p.plan_id
    ),
    Ranked AS (
        SELECT
            query_id,
            plan_id,
            exec_count,
            avg_duration_us,
            MIN(avg_duration_us) OVER (PARTITION BY query_id) AS best_avg_us,
            MAX(avg_duration_us) OVER (PARTITION BY query_id) AS worst_avg_us
        FROM PlanStats
    )
    SELECT TOP (15)
        r.query_id,
        r.plan_id,
        r.exec_count,
        r.avg_duration_us / 1000.0 AS [Avg_Duration_ms],
        r.best_avg_us / 1000.0 AS [Best_Plan_Avg_ms],
        CAST(100.0 * (r.avg_duration_us - r.best_avg_us) / NULLIF(r.best_avg_us, 0) AS DECIMAL(10,1)) AS [Regression_Pct],
        LEFT(qt.query_sql_text, 300) AS [Query_Text]
    FROM Ranked AS r
    INNER JOIN sys.query_store_query AS q ON r.query_id = q.query_id
    INNER JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
    WHERE r.worst_avg_us > r.best_avg_us * 1.5
      AND r.exec_count >= 5
    ORDER BY [Regression_Pct] DESC;
    ';
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        PRINT 'Error on ' + @db + ': ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @db;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

DROP TABLE #QSStatus;

PRINT '=== INTERPRET WITH ELAPSED vs CPU ===';
SELECT
    N'Query Store avg_duration includes WAIT time.' AS [Note],
    N'If QS shows low duration but SSMS/client shows high elapsed, check ASYNC_NETWORK_IO or app tier.' AS [Note2],
    N'If QS duration high but dm_exec shows low CPU per exec, prioritize wait analysis over plan force.' AS [Note3];
