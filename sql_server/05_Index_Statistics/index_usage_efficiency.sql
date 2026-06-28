/*
================================================================================
Index Usage Efficiency Across All User Databases
================================================================================
Description:
    Shows missing index recommendations from the DMV (instance-wide), identifies
    unused indexes that waste write I/O and maintenance time, and lists the most
    expensive index operations (seeks vs scans).

Output:
    Three result sets: (1) Top 20 missing indexes with advantage scores,
    (2) Unused indexes with high maintenance overhead, (3) Index usage summary.

Action:
    For missing indexes (result set 1): Review Index_Advantage_Score — scores
    > 100,000 are strong candidates. Validate against existing indexes before
    creating. For unused indexes (result set 2): Indexes with zero seeks and
    zero scans but high writes are maintenance overhead — drop only after
    confirming uptime and business approval. Do NOT act on first-run data alone;
    index usage stats reset on restart.

Parameters:
    @DatabaseList - comma-separated database names or NULL for all user DBs
    @MinIndexWrites - minimum writes to consider index maintenance cost (default 1000)

Criticality: Medium
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @MinIndexWrites BIGINT = 1000;

SELECT sqlserver_start_time AS [Instance_Start_Time], N'Index usage stats are cumulative since this time.' AS [Metric_Context]
FROM sys.dm_os_sys_info;

-- 1. Missing Index Recommendations (Instance-Wide)
PRINT N'--- Missing Index Recommendations (Instance-Wide) ---';
SELECT TOP (20)
    CAST(gs.user_seeks * gs.avg_user_impact * gs.avg_total_user_cost AS INT) AS [Index_Advantage_Score],
    DB_NAME(d.database_id) AS [Database_Name],
    d.statement AS [Table_Path],
    d.equality_columns AS [Equality_Columns],
    d.inequality_columns AS [Inequality_Columns],
    d.included_columns AS [Included_Columns],
    gs.user_seeks AS [User_Seeks],
    gs.avg_user_impact AS [Avg_User_Impact_Pct],
    CAST(N'WARNING: Never blindly create missing indexes from this DMV. Validate overlap and write overhead.' AS NVARCHAR(1000)) AS [Metric_Context]
FROM sys.dm_db_missing_index_groups AS g
INNER JOIN sys.dm_db_missing_index_group_stats AS gs ON gs.group_handle = g.index_group_handle
INNER JOIN sys.dm_db_missing_index_details AS d ON g.index_handle = d.index_handle
WHERE @DatabaseList IS NULL
   OR DB_NAME(d.database_id) IN (
        SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@DatabaseList, N',') WHERE LTRIM(RTRIM(value)) <> N''
   )
ORDER BY [Index_Advantage_Score] DESC;

-- 2. Unused Indexes (All User DBs)
PRINT N'--- Unused Indexes (All User DBs) ---';
IF OBJECT_ID(N'tempdb..#UnusedIndexes') IS NOT NULL DROP TABLE #UnusedIndexes;
CREATE TABLE #UnusedIndexes (
    [Database_Name] SYSNAME,
    [Table_Name] SYSNAME,
    [Index_Name] SYSNAME,
    [Writes] BIGINT,
    [Reads] BIGINT,
    [Index_Type] NVARCHAR(60)
);

DECLARE @IndexCommand NVARCHAR(MAX) = N'
INSERT INTO #UnusedIndexes
SELECT
    DB_NAME(),
    OBJECT_NAME(i.object_id),
    i.name,
    s.user_updates,
    s.user_seeks + s.user_scans + s.user_lookups,
    i.type_desc
FROM sys.indexes AS i
INNER JOIN sys.dm_db_index_usage_stats AS s
    ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.database_id = DB_ID()
  AND OBJECTPROPERTY(i.object_id, N''IsUserTable'') = 1
  AND i.index_id > 1
  AND s.user_updates > ' + CAST(@MinIndexWrites AS NVARCHAR(20)) + N'
  AND (s.user_seeks + s.user_scans + s.user_lookups) = 0;';

IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    EXEC dbo.sp_DBA_ForEachDatabase
        @Command = @IndexCommand,
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
        INSERT INTO #DbTargets SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0 AND is_in_standby = 0;

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT database_name FROM #DbTargets ORDER BY database_name;
    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db_name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @IndexCommand;
        BEGIN TRY EXEC sys.sp_executesql @SQL; END TRY BEGIN CATCH END CATCH;
        FETCH NEXT FROM db_cursor INTO @db_name;
    END;
    CLOSE db_cursor; DEALLOCATE db_cursor;
    DROP TABLE #DbTargets;
END;

SELECT * FROM #UnusedIndexes ORDER BY [Writes] DESC;
DROP TABLE #UnusedIndexes;
