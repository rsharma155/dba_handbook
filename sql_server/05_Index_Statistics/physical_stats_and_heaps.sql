/*
================================================================================
Physical Stats, Fragmentation, and Heap Forwarded Records
================================================================================
Description:
    Analyzes index fragmentation levels and heap forwarded record counts across
    all user databases. High fragmentation degrades scan performance; forwarded
    records fragment heap reads.

Output:
    Table/Index level details including page count, fragmentation percentage,
    and forwarded record count for heaps.

Action:
    For indexes with Fragmentation_Pct > 30%: rebuild ONLINE if possible:
        ALTER INDEX [IndexName] ON [TableName] REBUILD WITH (ONLINE = ON);
    For 5-30% fragmentation: reorganize:
        ALTER INDEX [IndexName] ON [TableName] REORGANIZE;
    For heaps with > 1000 forwarded records: create a clustered index then drop
    it (or keep it), or use ALTER TABLE ... REBUILD to eliminate forwarding.

Parameters:
    @DatabaseList - comma-separated database names or NULL for all user DBs
    @MinPageCount - minimum page count to include (default 1000)
    @MinFragmentationPct - minimum fragmentation to flag (default 5)

Warning: dm_db_index_physical_stats can be expensive on large databases.
         Run during off-peak hours.

Criticality: Medium
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @MinPageCount INT = 1000;
DECLARE @MinFragmentationPct DECIMAL(5,2) = 5.0;

IF OBJECT_ID(N'tempdb..#PhysStats') IS NOT NULL DROP TABLE #PhysStats;
CREATE TABLE #PhysStats (
    [Database_Name] SYSNAME,
    [Table_Name] SYSNAME,
    [Index_Name] SYSNAME,
    [Index_Type] NVARCHAR(60),
    [Page_Count] BIGINT,
    [Forwarded_Records] BIGINT,
    [Fragmentation_Pct] DECIMAL(5,2),
    [Maintenance_Hint] NVARCHAR(40)
);

DECLARE @PhysCommand NVARCHAR(MAX) = N'
INSERT INTO #PhysStats
SELECT
    DB_NAME(),
    OBJECT_NAME(ps.object_id),
    i.name,
    ps.index_type_desc,
    ps.page_count,
    ps.forwarded_record_count,
    CAST(ps.avg_fragmentation_in_percent AS DECIMAL(5,2)),
    CASE
        WHEN ps.forwarded_record_count > 0 THEN N''REVIEW HEAP''
        WHEN ps.avg_fragmentation_in_percent >= 30 AND ps.page_count >= 10000 THEN N''REBUILD''
        WHEN ps.avg_fragmentation_in_percent >= ' + CAST(@MinFragmentationPct AS NVARCHAR(10)) + N' THEN N''REORGANIZE''
        ELSE N''OK''
    END
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N''LIMITED'') AS ps
INNER JOIN sys.indexes AS i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE ps.page_count >= ' + CAST(@MinPageCount AS NVARCHAR(10)) + N'
  AND (ps.avg_fragmentation_in_percent > ' + CAST(@MinFragmentationPct AS NVARCHAR(10)) + N' OR ps.forwarded_record_count > 0);';

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
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @PhysCommand;
        BEGIN TRY EXEC sys.sp_executesql @SQL; END TRY BEGIN CATCH END CATCH;
        FETCH NEXT FROM db_cursor INTO @db_name;
    END;
    CLOSE db_cursor; DEALLOCATE db_cursor;
    DROP TABLE #DbTargets;
END;

SELECT * FROM #PhysStats ORDER BY [Fragmentation_Pct] DESC, [Forwarded_Records] DESC;
DROP TABLE #PhysStats;
