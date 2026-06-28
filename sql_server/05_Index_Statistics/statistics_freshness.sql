/*
================================================================================
Statistics Freshness Across User Databases
================================================================================
Description:
    Reports stale statistics (modifications since last update exceeding a
    threshold) across databases. Stale statistics lead to poor cardinality
    estimates and bad execution plans.

Output:
    List of statistics with last update date, row count, modifications,
    and modification percentage relative to row count.

Action:
    For statistics with Modification_Pct exceeding 20-30% of row count,
    update statistics:
        UPDATE STATISTICS [TableName] ([StatisticsName]) WITH FULLSCAN;
    For very large tables, use WITH SAMPLE instead. Schedule a nightly
    statistics maintenance job (e.g., Ola Hallengren's IndexOptimize) to
    prevent future plan regressions.

Parameters:
    @DatabaseList - comma-separated database names or NULL for all user DBs
    @StalePctThreshold - modification % threshold for flagging (default 20)

Criticality: High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @StalePctThreshold DECIMAL(5,2) = 20.0;
DECLARE @DatabaseList NVARCHAR(MAX) = NULL;

IF OBJECT_ID(N'tempdb..#StatsResults') IS NOT NULL DROP TABLE #StatsResults;
CREATE TABLE #StatsResults (
    [Database_Name] SYSNAME,
    [Table_Name] SYSNAME,
    [Statistics_Name] SYSNAME,
    [Last_Updated] DATETIME,
    [Total_Rows] BIGINT,
    [Rows_Sampled] BIGINT,
    [Modifications] BIGINT,
    [Modification_Pct] DECIMAL(18,2)
);

DECLARE @StatsCommand NVARCHAR(MAX) = N'
INSERT INTO #StatsResults
SELECT
    DB_NAME(),
    OBJECT_NAME(s.object_id),
    s.name,
    sp.last_updated,
    sp.rows,
    sp.rows_sampled,
    sp.modification_counter,
    CAST(sp.modification_counter AS DECIMAL(18,2)) / NULLIF(sp.rows, 0) * 100
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE OBJECTPROPERTY(s.object_id, N''IsUserTable'') = 1
  AND CAST(sp.modification_counter AS DECIMAL(18,2)) / NULLIF(sp.rows, 0) * 100 >= ' + CAST(@StalePctThreshold AS NVARCHAR(10)) + N';';

IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    EXEC dbo.sp_DBA_ForEachDatabase
        @Command = @StatsCommand,
        @UserDatabasesOnly = 1,
        @IncludeReadOnly = 0,
        @DatabaseList = @DatabaseList,
        @ContinueOnError = 1;
END
ELSE
BEGIN
    DECLARE @db_name SYSNAME;
    DECLARE @SQL NVARCHAR(MAX);

    IF OBJECT_ID(N'tempdb..#DbTargets') IS NOT NULL DROP TABLE #DbTargets;
    CREATE TABLE #DbTargets (database_name SYSNAME PRIMARY KEY);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
        INSERT INTO #DbTargets SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@DatabaseList, N',') WHERE LTRIM(RTRIM(value)) <> N'';
    ELSE
        INSERT INTO #DbTargets SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0 AND is_read_only = 0 AND is_in_standby = 0;

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT database_name FROM #DbTargets ORDER BY database_name;
    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db_name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @StatsCommand;
        BEGIN TRY EXEC sys.sp_executesql @SQL; END TRY BEGIN CATCH END CATCH;
        FETCH NEXT FROM db_cursor INTO @db_name;
    END;
    CLOSE db_cursor; DEALLOCATE db_cursor;
    DROP TABLE #DbTargets;
END;

SELECT * FROM #StatsResults ORDER BY [Modification_Pct] DESC, [Modifications] DESC;
DROP TABLE #StatsResults;
