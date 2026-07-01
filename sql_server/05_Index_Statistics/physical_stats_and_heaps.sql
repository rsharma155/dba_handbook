/*
================================================================================
Physical Stats, Fragmentation, and Heap Forwarded Records
================================================================================
Description:
    Analyzes index fragmentation levels and heap forwarded record counts across
    all user databases. High fragmentation degrades scan performance; forwarded
    records fragment heap reads.

    Thresholds align with Microsoft maintenance guidance and
    index_maintenance_online.sql:
      > 5% and <= 30%  -> REORGANIZE (always online)
      > 30%            -> REBUILD WITH (ONLINE = ON) when edition supports it

Output:
    Schema/table/index details, page count, fragmentation %, forwarded records,
  and maintenance recommendation per object.

Action:
    Review this report first. To apply maintenance online, run:
        index_maintenance_online.sql
    Set @ExecuteMaintenance = 0 for a dry-run preview, then 1 to execute.

Parameters:
    @DatabaseList           - comma-separated database names or NULL for all user DBs
    @MinPageCount           - minimum page count to include (default 1000)
    @ReorganizeMinPct       - fragmentation floor for reorganize hint (default 5)
    @RebuildMinPct          - fragmentation floor for rebuild hint (default 30)
    @ForwardedRecordMin     - heap forwarded-record review threshold (default 1000)

Warning: dm_db_index_physical_stats can be expensive on large databases.
         Run during off-peak hours.

Criticality: Medium (read-only report)
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @MinPageCount INT = 1000;
DECLARE @ReorganizeMinPct DECIMAL(5, 2) = 5.0;
DECLARE @RebuildMinPct DECIMAL(5, 2) = 30.0;
DECLARE @ForwardedRecordMin BIGINT = 1000;

DECLARE @SupportsOnlineRebuild BIT = CASE
    WHEN CAST(SERVERPROPERTY('EngineEdition') AS INT) IN (3, 5, 8) THEN 1
    WHEN CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) LIKE N'%Developer%' THEN 1
    ELSE 0
END;

DECLARE @db_name SYSNAME;
DECLARE @SQL NVARCHAR(MAX);

IF OBJECT_ID(N'tempdb..#PhysStats') IS NOT NULL DROP TABLE #PhysStats;
CREATE TABLE #PhysStats (
    [Database_Name] SYSNAME,
    [Schema_Name] SYSNAME,
    [Table_Name] SYSNAME,
    [Index_Name] SYSNAME,
    [Index_Type] NVARCHAR(60),
    [Page_Count] BIGINT,
    [Forwarded_Records] BIGINT,
    [Fragmentation_Pct] DECIMAL(5, 2),
    [Maintenance_Action] NVARCHAR(40),
    [Maintenance_Notes] NVARCHAR(200)
);

DECLARE @PhysCommand NVARCHAR(MAX) = N'
INSERT INTO #PhysStats
SELECT
    DB_NAME(),
    s.name,
    t.name,
    i.name,
    ps.index_type_desc,
    ps.page_count,
    ISNULL(ps.forwarded_record_count, 0),
    CAST(ps.avg_fragmentation_in_percent AS DECIMAL(5, 2)),
    CASE
        WHEN ps.index_id = 0 AND ISNULL(ps.forwarded_record_count, 0) >= ' + CAST(@ForwardedRecordMin AS NVARCHAR(20)) + N' THEN
            CASE WHEN ' + CAST(@SupportsOnlineRebuild AS NVARCHAR(1)) + N' = 1 THEN N''HEAP_REBUILD_ONLINE'' ELSE N''HEAP_REBUILD_REVIEW'' END
        WHEN ps.index_id = 0 AND ISNULL(ps.forwarded_record_count, 0) > 0 THEN N''REVIEW HEAP''
        WHEN i.is_disabled = 1 THEN N''SKIP_DISABLED''
        WHEN i.type NOT IN (1, 2) THEN N''SKIP_NON_ROWSTORE''
        WHEN ps.page_count < ' + CAST(@MinPageCount AS NVARCHAR(20)) + N' THEN N''SKIP_SMALL''
        WHEN ps.avg_fragmentation_in_percent > ' + CAST(@RebuildMinPct AS NVARCHAR(20)) + N' THEN
            CASE WHEN ' + CAST(@SupportsOnlineRebuild AS NVARCHAR(1)) + N' = 1 THEN N''REBUILD_ONLINE'' ELSE N''REORGANIZE_FALLBACK'' END
        WHEN ps.avg_fragmentation_in_percent > ' + CAST(@ReorganizeMinPct AS NVARCHAR(20)) + N'
             AND ps.avg_fragmentation_in_percent <= ' + CAST(@RebuildMinPct AS NVARCHAR(20)) + N' THEN N''REORGANIZE''
        ELSE N''OK''
    END,
    CASE
        WHEN ps.index_id = 0 AND ISNULL(ps.forwarded_record_count, 0) >= ' + CAST(@ForwardedRecordMin AS NVARCHAR(20)) + N'
             AND ' + CAST(@SupportsOnlineRebuild AS NVARCHAR(1)) + N' = 0 THEN
            N''Online heap rebuild needs Enterprise/Developer or Azure''
        WHEN ps.avg_fragmentation_in_percent > ' + CAST(@RebuildMinPct AS NVARCHAR(20)) + N'
             AND ' + CAST(@SupportsOnlineRebuild AS NVARCHAR(1)) + N' = 0 THEN
            N''Edition lacks online rebuild; maintenance script will REORGANIZE online instead''
        ELSE NULL
    END
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N''LIMITED'') AS ps
INNER JOIN sys.objects AS t ON ps.object_id = t.object_id
INNER JOIN sys.schemas AS s ON t.schema_id = s.schema_id
INNER JOIN sys.indexes AS i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE t.type = N''U''
  AND (
        ps.page_count >= ' + CAST(@MinPageCount AS NVARCHAR(20)) + N'
        OR ISNULL(ps.forwarded_record_count, 0) >= ' + CAST(@ForwardedRecordMin AS NVARCHAR(20)) + N'
      )
  AND (
        ps.avg_fragmentation_in_percent > ' + CAST(@ReorganizeMinPct AS NVARCHAR(20)) + N'
        OR ISNULL(ps.forwarded_record_count, 0) > 0
      );';

IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    EXEC dbo.sp_DBA_ForEachDatabase
        @Command = @PhysCommand,
        @UserDatabasesOnly = 1,
        @IncludeReadOnly = 0,
        @DatabaseList = @DatabaseList,
        @ContinueOnError = 1;
END
ELSE
BEGIN
    IF OBJECT_ID(N'tempdb..#DbTargets') IS NOT NULL DROP TABLE #DbTargets;
    CREATE TABLE #DbTargets (database_name SYSNAME PRIMARY KEY);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
        INSERT INTO #DbTargets
        SELECT LTRIM(RTRIM(value))
        FROM STRING_SPLIT(@DatabaseList, N',')
        WHERE LTRIM(RTRIM(value)) <> N'';
    ELSE
        INSERT INTO #DbTargets
        SELECT name
        FROM sys.databases
        WHERE database_id > 4
          AND state = 0
          AND is_in_standby = 0;

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM #DbTargets ORDER BY database_name;

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @PhysCommand;
        BEGIN TRY
            EXEC sys.sp_executesql @SQL;
        END TRY
        BEGIN CATCH
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @db_name;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;
    DROP TABLE #DbTargets;
END;

PRINT N'Online rebuild supported on this instance: '
    + CASE WHEN @SupportsOnlineRebuild = 1 THEN N'YES' ELSE N'NO' END;
PRINT N'To apply maintenance: index_maintenance_online.sql (@ExecuteMaintenance = 0 first for dry run)';

SELECT *
FROM #PhysStats
WHERE Maintenance_Action NOT IN (N'OK', N'SKIP_SMALL', N'SKIP_DISABLED', N'SKIP_NON_ROWSTORE')
ORDER BY
    CASE Maintenance_Action
        WHEN N'REBUILD_ONLINE' THEN 1
        WHEN N'HEAP_REBUILD_ONLINE' THEN 2
        WHEN N'REORGANIZE_FALLBACK' THEN 3
        WHEN N'REORGANIZE' THEN 4
        ELSE 5
    END,
    Fragmentation_Pct DESC,
    Forwarded_Records DESC;

DROP TABLE #PhysStats;
