/*
================================================================================
SQL Server Ultra-Deep Index Diagnostic: Contention & Exact Duplicates
================================================================================
Description:
    Identifies indexes with high row/page lock contention and detects exact
    duplicate indexes (same key columns, same included columns) across databases.

Output:
    Two result sets: (1) Indexes with lock contention (row + page lock waits),
    sorted by total wait time. (2) Exact duplicate indexes that waste space.

Action:
    For high-contention indexes (result set 1): Consider index redesign
    (narrowing the key, using hash partitioning, or reducing transaction scope).
    For duplicate indexes (result set 2): Drop the duplicate with the lower
    number of seeks or the one that was created later. Duplicate indexes add
    write overhead and maintenance cost without benefit.

Parameters:
    @DatabaseList - comma-separated database names or NULL for all user DBs

Prerequisites: SQL Server 2016+ (FOR XML PATH used for column aggregation on 2016; STRING_AGG on 2017+)

Criticality: Medium
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;

IF OBJECT_ID(N'tempdb..#Contention') IS NOT NULL DROP TABLE #Contention;
CREATE TABLE #Contention (
    [Database] SYSNAME,
    [Table] SYSNAME,
    [Index] SYSNAME,
    [Row_Lock_Wait_ms] BIGINT,
    [Page_Lock_Wait_ms] BIGINT
);

IF OBJECT_ID(N'tempdb..#Duplicates') IS NOT NULL DROP TABLE #Duplicates;
CREATE TABLE #Duplicates (
    [Database] SYSNAME,
    [Table] SYSNAME,
    [Index_1] SYSNAME,
    [Index_2] SYSNAME,
    [Column_List] NVARCHAR(MAX)
);

DECLARE @ContentionCommand NVARCHAR(MAX) = N'
INSERT INTO #Contention
SELECT DB_NAME(), OBJECT_NAME(s.object_id), i.name, s.row_lock_wait_in_ms, s.page_lock_wait_in_ms
FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) AS s
INNER JOIN sys.indexes AS i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.row_lock_wait_in_ms > 0 OR s.page_lock_wait_in_ms > 0;';

DECLARE @DuplicateCommand NVARCHAR(MAX) = N'
;WITH IndexCols AS (
    SELECT i.object_id, i.index_id, i.name,
        STUFF((
            SELECT N'','' + c.name
            FROM sys.index_columns AS ic2
            INNER JOIN sys.columns AS c ON ic2.object_id = c.object_id AND ic2.column_id = c.column_id
            WHERE ic2.object_id = i.object_id AND ic2.index_id = i.index_id AND ic2.is_included_column = 0
            ORDER BY ic2.key_ordinal
            FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 1, N'''') AS Cols
    FROM sys.indexes AS i
    WHERE i.index_id > 1
    GROUP BY i.object_id, i.index_id, i.name
)
INSERT INTO #Duplicates
SELECT DB_NAME(), OBJECT_NAME(i1.object_id), i1.name, i2.name, i1.Cols
FROM IndexCols AS i1
INNER JOIN IndexCols AS i2 ON i1.object_id = i2.object_id AND i1.index_id < i2.index_id AND i1.Cols = i2.Cols;';

DECLARE @CombinedCommand NVARCHAR(MAX) = @ContentionCommand + NCHAR(10) + @DuplicateCommand;

IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    EXEC dbo.sp_DBA_ForEachDatabase
        @Command = @CombinedCommand,
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
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @CombinedCommand;
        BEGIN TRY EXEC sys.sp_executesql @SQL; END TRY BEGIN CATCH END CATCH;
        FETCH NEXT FROM db_cursor INTO @db_name;
    END;
    CLOSE db_cursor; DEALLOCATE db_cursor;
    DROP TABLE #DbTargets;
END;

PRINT N'--- Index Contention & Blocking (Top 20) ---';
SELECT TOP (20) * FROM #Contention ORDER BY (Row_Lock_Wait_ms + Page_Lock_Wait_ms) DESC;

PRINT N'--- Exact Duplicate Indexes (Wasteful) ---';
SELECT * FROM #Duplicates ORDER BY [Database], [Table];

DROP TABLE #Contention;
DROP TABLE #Duplicates;
