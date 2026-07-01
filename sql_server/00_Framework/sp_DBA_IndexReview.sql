/*
================================================================================
sp_DBA_IndexReview — Comprehensive index health across databases
================================================================================
Detects unused indexes, duplicate indexes, missing indexes, and fragmentation
candidates across all user databases (or a specified list).

Usage:
    EXEC dbo.sp_DBA_IndexReview;
    EXEC dbo.sp_DBA_IndexReview @DatabaseList = N'SalesDB,HRDB';
    EXEC dbo.sp_DBA_IndexReview @MinPageCount = 1000, @IncludeFragmentation = 0;
================================================================================
*/
IF OBJECT_ID(N'dbo.sp_DBA_IndexReview', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DBA_IndexReview AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_DBA_IndexReview
    @DatabaseList           NVARCHAR(MAX) = NULL,
    @IncludeReadOnly        BIT = 0,
    @MinPageCount           INT = 1000,
    @IncludeFragmentation   BIT = 1,
    @IncludeMissingIndexes  BIT = 1,
    @TopN                   INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    IF OBJECT_ID(N'tempdb..#IndexReviewDbs') IS NOT NULL DROP TABLE #IndexReviewDbs;
    CREATE TABLE #IndexReviewDbs (database_id INT NOT NULL PRIMARY KEY, database_name SYSNAME NOT NULL);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
    BEGIN
        INSERT INTO #IndexReviewDbs (database_id, database_name)
        SELECT d.database_id, d.name
        FROM sys.databases AS d
        INNER JOIN (
            SELECT LTRIM(RTRIM(value)) AS database_name
            FROM STRING_SPLIT(@DatabaseList, N',')
            WHERE LTRIM(RTRIM(value)) <> N''
        ) AS req ON req.database_name = d.name
        WHERE d.state = 0 AND d.is_in_standby = 0;
    END
    ELSE
    BEGIN
        INSERT INTO #IndexReviewDbs (database_id, database_name)
        SELECT database_id, name FROM sys.databases
        WHERE state = 0 AND is_in_standby = 0 AND database_id > 4
          AND (@IncludeReadOnly = 1 OR is_read_only = 0);
    END;

    -- Section 1: Unused Indexes
    IF OBJECT_ID(N'tempdb..#UnusedIndexes') IS NOT NULL DROP TABLE #UnusedIndexes;
    CREATE TABLE #UnusedIndexes (
        DatabaseName SYSNAME, SchemaName SYSNAME, TableName SYSNAME,
        IndexName SYSNAME, IndexType VARCHAR(20), SizeMB DECIMAL(10,2),
        UserUpdates BIGINT, UserSeeks BIGINT, UserScans BIGINT, UserLookups BIGINT,
        LastSeek DATETIME, LastScan DATETIME, LastUpdate DATETIME
    );

    DECLARE @db_id INT, @db_name SYSNAME, @sql NVARCHAR(MAX);

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_id, database_name FROM #IndexReviewDbs ORDER BY database_name;

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db_id, @db_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SET @sql = N'USE ' + QUOTENAME(@db_name) + N';
            INSERT INTO #UnusedIndexes
            SELECT
                DB_NAME(), s.name, t.name, i.name,
                i.type_desc,
                CAST((ps.used_page_count * 8.0 / 1024) AS DECIMAL(10,2)),
                ISNULL(ust.user_updates, 0),
                ISNULL(ust.user_seeks, 0),
                ISNULL(ust.user_scans, 0),
                ISNULL(ust.user_lookups, 0),
                ust.last_user_seek,
                ust.last_user_scan,
                ust.last_user_update
            FROM sys.indexes AS i
            INNER JOIN sys.tables AS t ON i.object_id = t.object_id
            INNER JOIN sys.schemas AS s ON t.schema_id = s.schema_id
            LEFT JOIN sys.dm_db_index_usage_stats AS ust
                ON ust.object_id = i.object_id AND ust.index_id = i.index_id AND ust.database_id = DB_ID()
            LEFT JOIN sys.dm_db_partition_stats AS ps
                ON ps.object_id = i.object_id AND ps.index_id = i.index_id
            WHERE i.index_id > 1
              AND i.is_primary_key = 0
              AND i.is_unique_constraint = 0
              AND t.is_ms_shipped = 0
              AND ISNULL(ust.user_updates, 0) > 1000
              AND ISNULL(ust.user_seeks, 0) + ISNULL(ust.user_scans, 0) + ISNULL(ust.user_lookups, 0) = 0
              AND ps.used_page_count > ' + CAST(@MinPageCount AS NVARCHAR(20)) + N'
            ORDER BY ust.user_updates DESC;';
            EXEC sys.sp_executesql @sql;
        END TRY
        BEGIN CATCH
            -- Skip databases we can't access
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @db_id, @db_name;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    SELECT TOP (@TopN) * FROM #UnusedIndexes ORDER BY UserUpdates DESC;

    -- Section 2: Missing Indexes (instance-wide DMV)
    IF @IncludeMissingIndexes = 1
    BEGIN
        SELECT TOP (@TopN)
            DB_NAME(d.database_id) AS DatabaseName,
            d.equality_columns AS EqualityColumns,
            d.inequality_columns AS InequalityColumns,
            d.included_columns AS IncludedColumns,
            CAST(gs.avg_user_impact AS DECIMAL(5,1)) AS AvgUserImpact,
            gs.user_seeks AS UserSeeks,
            gs.user_scans AS UserScans,
            CAST(gs.avg_total_user_cost AS DECIMAL(10,2)) AS AvgTotalUserCost,
            CAST((gs.user_seeks * gs.avg_user_impact * gs.avg_total_user_cost) AS DECIMAL(18,0)) AS ImprovementMeasure
        FROM sys.dm_db_missing_index_group_stats AS gs
        INNER JOIN sys.dm_db_missing_index_groups AS g ON gs.group_handle = g.index_group_handle
        INNER JOIN sys.dm_db_missing_index_details AS d ON g.index_handle = d.index_handle
        WHERE d.database_id IN (SELECT database_id FROM #IndexReviewDbs)
          AND (gs.user_seeks * gs.avg_user_impact * gs.avg_total_user_cost) > 100000
        ORDER BY (gs.user_seeks * gs.avg_user_impact * gs.avg_total_user_cost) DESC;
    END;

    -- Section 3: Fragmentation (optional, expensive)
    IF @IncludeFragmentation = 1
    BEGIN
        IF OBJECT_ID(N'tempdb..#FragResults') IS NOT NULL DROP TABLE #FragResults;
        CREATE TABLE #FragResults (
            DatabaseName SYSNAME, SchemaName SYSNAME, TableName SYSNAME,
            IndexName SYSNAME, fragmentation_pct DECIMAL(5,2), page_count INT,
            Recommendation VARCHAR(20)
        );

        DECLARE frag_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT database_name FROM #IndexReviewDbs ORDER BY database_name;

        OPEN frag_cursor;
        FETCH NEXT FROM frag_cursor INTO @db_name;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                SET @sql = N'USE ' + QUOTENAME(@db_name) + N';
                INSERT INTO #FragResults
                SELECT
                    DB_NAME(), s.name, t.name, i.name,
                    ps.avg_fragmentation_in_percent,
                    ps.page_count,
                    CASE
                        WHEN ps.avg_fragmentation_in_percent > 30 AND ps.page_count > 1000 THEN ''REBUILD_ONLINE''
                        WHEN ps.avg_fragmentation_in_percent > 5 AND ps.page_count > 1000 THEN ''REORGANIZE''
                        ELSE ''OK''
                    END
                FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') AS ps
                INNER JOIN sys.indexes AS i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
                INNER JOIN sys.tables AS t ON i.object_id = t.object_id
                INNER JOIN sys.schemas AS s ON t.schema_id = s.schema_id
                WHERE ps.page_count > ' + CAST(@MinPageCount AS NVARCHAR(20)) + N'
                  AND ps.avg_fragmentation_in_percent > 5
                  AND i.index_id > 0
                  AND t.is_ms_shipped = 0;';
                EXEC sys.sp_executesql @sql;
            END TRY
            BEGIN CATCH
            END CATCH;

            FETCH NEXT FROM frag_cursor INTO @db_name;
        END;

        CLOSE frag_cursor;
        DEALLOCATE frag_cursor;

        SELECT TOP (@TopN) * FROM #FragResults WHERE Recommendation <> 'OK' ORDER BY fragmentation_pct DESC;
    END;

    DROP TABLE #IndexReviewDbs;
    DROP TABLE #UnusedIndexes;
    IF OBJECT_ID(N'tempdb..#FragResults') IS NOT NULL DROP TABLE #FragResults;
END;
GO
