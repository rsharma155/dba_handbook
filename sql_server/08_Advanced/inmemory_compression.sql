/*
================================================================================
Compression Candidates and In-Memory OLTP Health
================================================================================
Description:
    Identifies tables that are good candidates for data compression (page or row)
    based on size and scan patterns, and reports In-Memory OLTP (Hekaton) health.

Output:
    (1) Compression candidates with table size and scan frequency
    (2) In-Memory OLTP memory usage and garbage collection status

Action:
    For compression candidates with large size and frequent scans: test page
    compression on a non-production copy:
        ALTER INDEX [IndexName] ON [TableName] REBUILD WITH (DATA_COMPRESSION = PAGE);
    Page compression can reduce storage by 50-80% with minimal CPU overhead on
    read-heavy workloads. For In-Memory OLTP: ensure garbage collection is keeping
    up — if not, increase the number of garbage collection worker threads.

Parameters:
    @DatabaseList - comma-separated database names or NULL for all user DBs
    @MinRows - minimum row count to consider (default 1000)
    @MinScans - minimum scan count to consider (default 1000)

Criticality: Low
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @MinRows BIGINT = 1000;
DECLARE @MinScans BIGINT = 1000;

IF OBJECT_ID(N'tempdb..#CompressionResults') IS NOT NULL DROP TABLE #CompressionResults;
CREATE TABLE #CompressionResults (
    [Database] SYSNAME,
    [Table] SYSNAME,
    [Index] SYSNAME,
    [Rows] BIGINT,
    [Scans] BIGINT,
    [Size_MB] DECIMAL(18,2)
);

DECLARE @CompressionCommand NVARCHAR(MAX) = N'
INSERT INTO #CompressionResults
SELECT
    DB_NAME(),
    OBJECT_NAME(s.object_id),
    i.name,
    p.rows,
    s.user_scans,
    CAST(p.used_page_count * 8.0 / 1024 AS DECIMAL(18,2))
FROM sys.dm_db_index_usage_stats AS s
INNER JOIN sys.indexes AS i ON s.object_id = i.object_id AND s.index_id = i.index_id
INNER JOIN sys.partitions AS p ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE s.database_id = DB_ID()
  AND OBJECTPROPERTY(s.object_id, N''IsUserTable'') = 1
  AND p.rows > ' + CAST(@MinRows AS NVARCHAR(20)) + N'
  AND p.data_compression = 0
  AND s.user_scans > ' + CAST(@MinScans AS NVARCHAR(20)) + N';';

IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    EXEC dbo.sp_DBA_ForEachDatabase
        @Command = @CompressionCommand,
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
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @CompressionCommand;
        BEGIN TRY EXEC sys.sp_executesql @SQL; END TRY BEGIN CATCH END CATCH;
        FETCH NEXT FROM db_cursor INTO @db_name;
    END;
    CLOSE db_cursor; DEALLOCATE db_cursor;
    DROP TABLE #DbTargets;
END;

PRINT N'--- Compression Candidates (uncompressed, scan-heavy) ---';
SELECT * FROM #CompressionResults ORDER BY [Size_MB] DESC;

-- In-Memory OLTP (per database with memory-optimized objects)
IF OBJECT_ID(N'tempdb..#XtpHealth') IS NOT NULL DROP TABLE #XtpHealth;
CREATE TABLE #XtpHealth (
    [Database] SYSNAME,
    [Table] SYSNAME,
    [Memory_Allocated_KB] BIGINT,
    [Memory_Used_KB] BIGINT
);

DECLARE @XtpCommand NVARCHAR(MAX) = N'
IF OBJECT_ID(N''sys.dm_db_xtp_table_memory_stats'', N''V'') IS NOT NULL
    INSERT INTO #XtpHealth
    SELECT DB_NAME(), OBJECT_NAME(object_id), memory_allocated_for_table_kb, memory_used_by_table_kb
    FROM sys.dm_db_xtp_table_memory_stats;';

IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
    EXEC dbo.sp_DBA_ForEachDatabase @Command = @XtpCommand, @UserDatabasesOnly = 1, @DatabaseList = @DatabaseList, @ContinueOnError = 1;
ELSE
BEGIN
    DECLARE @db_x SYSNAME;
    DECLARE @sql_x NVARCHAR(MAX);
    DECLARE xtp_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0 AND is_in_standby = 0
          AND (@DatabaseList IS NULL OR name IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@DatabaseList, N',') WHERE LTRIM(RTRIM(value)) <> N''));
    OPEN xtp_cursor;
    FETCH NEXT FROM xtp_cursor INTO @db_x;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql_x = N'USE ' + QUOTENAME(@db_x) + N';' + @XtpCommand;
        BEGIN TRY EXEC sys.sp_executesql @sql_x; END TRY BEGIN CATCH END CATCH;
        FETCH NEXT FROM xtp_cursor INTO @db_x;
    END;
    CLOSE xtp_cursor; DEALLOCATE xtp_cursor;
END;

PRINT N'--- In-Memory OLTP Table Memory ---';
SELECT * FROM #XtpHealth ORDER BY [Memory_Used_KB] DESC;
DROP TABLE #CompressionResults;
DROP TABLE #XtpHealth;
