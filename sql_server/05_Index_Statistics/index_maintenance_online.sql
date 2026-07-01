/*
================================================================================
Online Index Maintenance — Reorganize and Rebuild by Fragmentation
================================================================================
Description:
    Performs index maintenance across user databases using Microsoft-recommended
    fragmentation thresholds:
      > 5% and <= 30%  -> ALTER INDEX ... REORGANIZE (always online)
      > 30%            -> ALTER INDEX ... REBUILD WITH (ONLINE = ON) when supported

    Heaps with high forwarded-record counts use ALTER TABLE ... REBUILD WITH
    (ONLINE = ON) when the edition supports online operations.

Best practices applied:
    - Defaults to dry-run (@ExecuteMaintenance = 0); set to 1 to apply changes
    - Skips small indexes below @MinPageCount (default 1000 pages)
    - Rowstore indexes only; columnstore/XML/spatial indexes are reported, not altered
    - Skips disabled and hypothetical indexes
    - Online rebuild uses WAIT_AT_LOW_PRIORITY, SORT_IN_TEMPDB, configurable MAXDOP
    - Standard/Web/Express: no online rebuild license — falls back to REORGANIZE
      (online) for high-fragmentation indexes and logs a warning
    - REORGANIZE uses LOB_COMPACTION = ON
    - Continues on per-index errors; review #MaintenanceLog output

Parameters:
    @DatabaseList           - comma-separated database names or NULL for all user DBs
    @ExecuteMaintenance     - 0 = preview commands only (default), 1 = execute
    @MinPageCount           - minimum pages before maintenance (default 1000)
    @ReorganizeMinPct       - fragmentation floor for reorganize (default 5)
    @RebuildMinPct          - fragmentation floor for rebuild (default 30)
    @ForwardedRecordMin     - heap forwarded-record threshold (default 1000)
    @MaxDOP                 - MAXDOP for rebuild; 0 = omit option (server default)
    @SortInTempdb           - SORT_IN_TEMPDB = ON for rebuild (default 1)
    @WaitAtLowPriority      - WAIT_AT_LOW_PRIORITY on online rebuild (default 1)
    @MaxIndexesToProcess    - safety cap per run (default 500)

Warning: dm_db_index_physical_stats can be expensive. Run off-peak.
         Test on a non-production database before @ExecuteMaintenance = 1.

Criticality: High — modifies indexes
Prerequisites: ALTER permission on target tables/indexes
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @ExecuteMaintenance BIT = 0;          -- 1 = execute maintenance
DECLARE @MinPageCount INT = 1000;
DECLARE @ReorganizeMinPct DECIMAL(5, 2) = 5.0;
DECLARE @RebuildMinPct DECIMAL(5, 2) = 30.0;
DECLARE @ForwardedRecordMin BIGINT = 1000;
DECLARE @MaxDOP INT = 0;
DECLARE @SortInTempdb BIT = 1;
DECLARE @WaitAtLowPriority BIT = 1;
DECLARE @MaxIndexesToProcess INT = 500;

DECLARE @SupportsOnlineRebuild BIT = CASE
    WHEN CAST(SERVERPROPERTY('EngineEdition') AS INT) IN (3, 5, 8) THEN 1  -- Enterprise, Azure SQL DB, MI
    WHEN CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) LIKE N'%Developer%' THEN 1
    ELSE 0
END;

DECLARE @RebuildWithOptions NVARCHAR(MAX) = N'ONLINE = ON';
DECLARE @db_name SYSNAME;
DECLARE @SQL NVARCHAR(MAX);
DECLARE @QueueId INT;
DECLARE @Db SYSNAME;
DECLARE @SchemaName SYSNAME;
DECLARE @TableName SYSNAME;
DECLARE @IndexName SYSNAME;
DECLARE @Action NVARCHAR(30);
DECLARE @Cmd NVARCHAR(MAX);
DECLARE @StartTime DATETIME2(7);
DECLARE @DurationMs INT;
DECLARE @Processed INT = 0;

IF @SortInTempdb = 1
    SET @RebuildWithOptions = @RebuildWithOptions + N', SORT_IN_TEMPDB = ON';

IF @MaxDOP > 0
    SET @RebuildWithOptions = @RebuildWithOptions + N', MAXDOP = ' + CAST(@MaxDOP AS NVARCHAR(10));

IF @WaitAtLowPriority = 1
    SET @RebuildWithOptions = @RebuildWithOptions
        + N', WAIT_AT_LOW_PRIORITY (MAX_DURATION = 0 MINUTES, ABORT_AFTER_WAIT = BLOCKERS)';

IF OBJECT_ID(N'tempdb..#MaintenanceQueue') IS NOT NULL DROP TABLE #MaintenanceQueue;
CREATE TABLE #MaintenanceQueue (
    [Queue_Id] INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
    [Database_Name] SYSNAME NOT NULL,
    [Schema_Name] SYSNAME NOT NULL,
    [Table_Name] SYSNAME NOT NULL,
    [Index_Name] SYSNAME NULL,
    [Index_Id] INT NOT NULL,
    [Index_Type] TINYINT NULL,
    [Is_Disabled] BIT NOT NULL,
    [Page_Count] BIGINT NOT NULL,
    [Fragmentation_Pct] DECIMAL(5, 2) NULL,
    [Forwarded_Records] BIGINT NOT NULL,
    [Maintenance_Action] NVARCHAR(30) NULL,
    [Sql_Command] NVARCHAR(MAX) NULL,
    [Notes] NVARCHAR(200) NULL
);

IF OBJECT_ID(N'tempdb..#MaintenanceLog') IS NOT NULL DROP TABLE #MaintenanceLog;
CREATE TABLE #MaintenanceLog (
    [Database_Name] SYSNAME NOT NULL,
    [Schema_Name] SYSNAME NOT NULL,
    [Table_Name] SYSNAME NOT NULL,
    [Index_Name] SYSNAME NULL,
    [Maintenance_Action] NVARCHAR(30) NOT NULL,
    [Sql_Command] NVARCHAR(MAX) NOT NULL,
    [Execution_Status] NVARCHAR(20) NOT NULL,
    [Duration_ms] INT NULL,
    [Message] NVARCHAR(4000) NULL
);

DECLARE @CollectCommand NVARCHAR(MAX) = N'
INSERT INTO #MaintenanceQueue (
    Database_Name, Schema_Name, Table_Name, Index_Name, Index_Id, Index_Type, Is_Disabled,
    Page_Count, Fragmentation_Pct, Forwarded_Records
)
SELECT
    DB_NAME(),
    s.name,
    t.name,
    i.name,
    ps.index_id,
    i.type,
    i.is_disabled,
    ps.page_count,
    CAST(ps.avg_fragmentation_in_percent AS DECIMAL(5, 2)),
    ISNULL(ps.forwarded_record_count, 0)
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N''LIMITED'') AS ps
INNER JOIN sys.objects AS t ON ps.object_id = t.object_id
INNER JOIN sys.schemas AS s ON t.schema_id = s.schema_id
INNER JOIN sys.indexes AS i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE t.type = N''U''
  AND (
        (
            ps.index_id = 0
            AND ISNULL(ps.forwarded_record_count, 0) >= ' + CAST(@ForwardedRecordMin AS NVARCHAR(20)) + N'
        )
        OR (
            ps.index_id > 0
            AND i.is_hypothetical = 0
            AND i.type IN (1, 2)
            AND ps.page_count >= ' + CAST(@MinPageCount AS NVARCHAR(20)) + N'
            AND ps.avg_fragmentation_in_percent > ' + CAST(@ReorganizeMinPct AS NVARCHAR(20)) + N'
        )
      );';

IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    EXEC dbo.sp_DBA_ForEachDatabase
        @Command = @CollectCommand,
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
          AND is_in_standby = 0
          AND is_read_only = 0;

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM #DbTargets ORDER BY database_name;

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @CollectCommand;
        BEGIN TRY
            EXEC sys.sp_executesql @SQL;
        END TRY
        BEGIN CATCH
            INSERT INTO #MaintenanceLog (
                Database_Name, Schema_Name, Table_Name, Index_Name,
                Maintenance_Action, Sql_Command, Execution_Status, Message
            )
            VALUES (
                @db_name, N'', N'', NULL, N'COLLECT', N'',
                N'ERROR', LEFT(ERROR_MESSAGE(), 4000)
            );
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @db_name;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;
    DROP TABLE #DbTargets;
END;

UPDATE #MaintenanceQueue
SET Maintenance_Action = CASE
    WHEN Index_Id = 0
         AND Forwarded_Records >= @ForwardedRecordMin
         AND @SupportsOnlineRebuild = 1 THEN N'HEAP_REBUILD'
    WHEN Index_Id = 0
         AND Forwarded_Records >= @ForwardedRecordMin THEN N'HEAP_REBUILD_OFFLINE'
    WHEN Index_Id > 0 AND Is_Disabled = 1 THEN NULL
    WHEN Index_Id > 0
         AND Fragmentation_Pct > @RebuildMinPct
         AND @SupportsOnlineRebuild = 1 THEN N'REBUILD'
    WHEN Index_Id > 0
         AND Fragmentation_Pct > @RebuildMinPct THEN N'REORGANIZE_FALLBACK'
    WHEN Index_Id > 0
         AND Fragmentation_Pct > @ReorganizeMinPct
         AND Fragmentation_Pct <= @RebuildMinPct THEN N'REORGANIZE'
    ELSE NULL
END,
Notes = CASE
    WHEN Index_Id > 0 AND Is_Disabled = 1 THEN N'Skipped disabled index'
    WHEN Index_Id > 0
         AND Fragmentation_Pct > @RebuildMinPct
         AND @SupportsOnlineRebuild = 0 THEN
        N'Online rebuild unavailable on this edition; using REORGANIZE instead'
    WHEN Index_Id = 0
         AND Forwarded_Records >= @ForwardedRecordMin
         AND @SupportsOnlineRebuild = 0 THEN
        N'Heap rebuild requires Enterprise/Developer or Azure for ONLINE; skipped'
    ELSE NULL
END;

UPDATE mq
SET Sql_Command = CASE mq.Maintenance_Action
    WHEN N'HEAP_REBUILD' THEN
        N'ALTER TABLE ' + QUOTENAME(mq.Schema_Name) + N'.' + QUOTENAME(mq.Table_Name)
        + N' REBUILD WITH (ONLINE = ON);'
    WHEN N'REBUILD' THEN
        N'ALTER INDEX ' + QUOTENAME(mq.Index_Name) + N' ON '
        + QUOTENAME(mq.Schema_Name) + N'.' + QUOTENAME(mq.Table_Name)
        + N' REBUILD PARTITION = ALL WITH (' + @RebuildWithOptions + N');'
    WHEN N'REORGANIZE' THEN
        N'ALTER INDEX ' + QUOTENAME(mq.Index_Name) + N' ON '
        + QUOTENAME(mq.Schema_Name) + N'.' + QUOTENAME(mq.Table_Name)
        + N' REORGANIZE WITH (LOB_COMPACTION = ON);'
    WHEN N'REORGANIZE_FALLBACK' THEN
        N'ALTER INDEX ' + QUOTENAME(mq.Index_Name) + N' ON '
        + QUOTENAME(mq.Schema_Name) + N'.' + QUOTENAME(mq.Table_Name)
        + N' REORGANIZE WITH (LOB_COMPACTION = ON);'
    ELSE NULL
END
FROM #MaintenanceQueue AS mq
WHERE mq.Maintenance_Action IS NOT NULL
  AND mq.Maintenance_Action <> N'HEAP_REBUILD_OFFLINE';

DELETE FROM #MaintenanceQueue
WHERE Maintenance_Action IS NULL
   OR (Sql_Command IS NULL AND Maintenance_Action <> N'HEAP_REBUILD_OFFLINE');

PRINT N'=== INDEX MAINTENANCE QUEUE ===';
PRINT N'Online rebuild supported: '
    + CASE WHEN @SupportsOnlineRebuild = 1 THEN N'YES'
           ELSE N'NO (high-fragmentation indexes will REORGANIZE online instead)' END;
PRINT N'Mode: '
    + CASE WHEN @ExecuteMaintenance = 1 THEN N'EXECUTE'
           ELSE N'DRY RUN - set @ExecuteMaintenance = 1 to apply' END;
PRINT N'Thresholds: REORGANIZE > ' + CAST(@ReorganizeMinPct AS NVARCHAR(10)) + N'% and <= '
    + CAST(@RebuildMinPct AS NVARCHAR(10)) + N'%; REBUILD > ' + CAST(@RebuildMinPct AS NVARCHAR(10)) + N'%';

SELECT TOP (@MaxIndexesToProcess)
    Database_Name,
    Schema_Name,
    Table_Name,
    Index_Name,
    Page_Count,
    Fragmentation_Pct,
    Forwarded_Records,
    Maintenance_Action,
    Sql_Command,
    Notes
FROM #MaintenanceQueue
ORDER BY
    CASE Maintenance_Action
        WHEN N'REBUILD' THEN 1
        WHEN N'HEAP_REBUILD' THEN 2
        WHEN N'REORGANIZE' THEN 3
        WHEN N'REORGANIZE_FALLBACK' THEN 4
        ELSE 5
    END,
    Fragmentation_Pct DESC,
    Forwarded_Records DESC;

IF @ExecuteMaintenance = 0
BEGIN
    PRINT N'';
    PRINT N'DRY RUN complete. Review the queue above, then set @ExecuteMaintenance = 1.';
    DROP TABLE #MaintenanceQueue;
    DROP TABLE #MaintenanceLog;
END
ELSE
BEGIN
    DECLARE work_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT TOP (@MaxIndexesToProcess)
            Queue_Id, Database_Name, Schema_Name, Table_Name, Index_Name, Maintenance_Action, Sql_Command
        FROM #MaintenanceQueue
        WHERE Sql_Command IS NOT NULL
        ORDER BY Queue_Id;

    OPEN work_cursor;
    FETCH NEXT FROM work_cursor INTO @QueueId, @Db, @SchemaName, @TableName, @IndexName, @Action, @Cmd;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @StartTime = SYSDATETIME();
        SET @Processed += 1;

        BEGIN TRY
            SET @SQL = N'USE ' + QUOTENAME(@Db) + N'; ' + @Cmd;
            EXEC sys.sp_executesql @SQL;

            SET @DurationMs = DATEDIFF(MILLISECOND, @StartTime, SYSDATETIME());
            INSERT INTO #MaintenanceLog (
                Database_Name, Schema_Name, Table_Name, Index_Name,
                Maintenance_Action, Sql_Command, Execution_Status, Duration_ms, Message
            )
            VALUES (
                @Db, @SchemaName, @TableName, @IndexName,
                @Action, @Cmd, N'SUCCESS', @DurationMs, NULL
            );
        END TRY
        BEGIN CATCH
            SET @DurationMs = DATEDIFF(MILLISECOND, @StartTime, SYSDATETIME());
            INSERT INTO #MaintenanceLog (
                Database_Name, Schema_Name, Table_Name, Index_Name,
                Maintenance_Action, Sql_Command, Execution_Status, Duration_ms, Message
            )
            VALUES (
                @Db, @SchemaName, @TableName, @IndexName,
                @Action, @Cmd, N'ERROR', @DurationMs, LEFT(ERROR_MESSAGE(), 4000)
            );
        END CATCH;

        FETCH NEXT FROM work_cursor INTO @QueueId, @Db, @SchemaName, @TableName, @IndexName, @Action, @Cmd;
    END;

    CLOSE work_cursor;
    DEALLOCATE work_cursor;

    PRINT N'';
    PRINT N'=== MAINTENANCE EXECUTION LOG (' + CAST(@Processed AS NVARCHAR(10)) + N' indexes processed) ===';

    SELECT
        Database_Name,
        Schema_Name,
        Table_Name,
        Index_Name,
        Maintenance_Action,
        Execution_Status,
        Duration_ms,
        Message,
        Sql_Command
    FROM #MaintenanceLog
    ORDER BY Execution_Status DESC, Duration_ms DESC;

    DROP TABLE #MaintenanceQueue;
    DROP TABLE #MaintenanceLog;
END;
