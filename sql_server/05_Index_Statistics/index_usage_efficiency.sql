/*
================================================================================
Index Usage Efficiency & Nonclustered Index Activity Analysis
================================================================================
Description:
    A comprehensive, read-only diagnostic that answers four questions a DBA asks
    about indexes on a production server:

        1. Which indexes does the engine WISH existed?  (missing index DMV)
        2. Which nonclustered indexes are ACTIVELY READ, and how are they read
           (seeks vs scans vs lookups), how recently, and how hot are they?
        3. Which nonclustered indexes are NEVER read but still cost write I/O and
           storage (drop candidates)?
        4. What does index usage look like rolled up PER DATABASE?

    All read/write counters come from sys.dm_db_index_usage_stats, which is
    CUMULATIVE since the last SQL Server restart (or since the index was last
    rebuilt on some versions). The first result set prints that start time so you
    can judge whether the sample window is long enough to trust.

Result Sets:
    (0) Collection Window ...... Instance start time + uptime + how many indexes
                                 were sampled. Read this first to size the sample.
    (1) Missing Indexes ........ Top recommendations with an advantage score AND a
                                 ready-to-review CREATE INDEX statement.
    (2) Active NC Indexes ...... Every nonclustered index that has been READ, with
                                 a seek/scan/lookup breakdown, read:write ratio,
                                 access pattern, recency "temperature", size, a
                                 KEEP-or-DROP verdict, and a plain-English reason.
                                 THIS IS THE FOCUS.
    (3) Unused NC Indexes ...... Nonclustered indexes with ZERO reads but writes
                                 above @MinIndexWrites: pure maintenance overhead.
                                 Includes reclaimable size, a KEEP-or-DROP verdict,
                                 and a DROP statement.

Keep_Or_Drop verdicts:
    KEEP ............. Recently and actively read; leave it in place.
    KEEP / MONITOR ... Read before, but not recently; watch over the next cycle.
    KEEP BUT REDESIGN  Scan-heavy on a large table; useful but the key design or
                       queries likely need review.
    REVIEW / LIKELY DROP  Read very rarely relative to its write cost and not read
                       recently; strong candidate for removal after validation.
    DROP CANDIDATE ... Zero reads with ongoing writes; maintenance overhead only.
    (4) Per-Database Summary ... Counts of hot/active/unused indexes, total reads,
                                 total writes and total/reclaimable size per DB.

How to read "temperature" (Activity_Level):
    HOT   = last read within @HotDays days       -> clearly in use, keep.
    WARM  = last read within @WarmDays days       -> in use, keep.
    COOL  = last read within @CoolDays days        -> used occasionally (month-end?).
    COLD  = read at some point but not within @CoolDays, or only before the sample
            window started -> verify against a full business cycle before acting.

Action / Safety:
    * NEVER create a missing index blindly. Compare against existing indexes
      (see duplicate_index_analysis.sql) and weigh write overhead first.
    * A "WRITE-ONLY (unused for reads)" index is only a safe drop AFTER the server
      has been up long enough to cover month-end / quarter-end / reporting cycles.
    * Primary keys and unique constraints are reported but are NEVER emitted as
      drop candidates; they are excluded from result set (3) by design.
    * This script makes NO changes. All DDL is emitted as commented text for review.

Parameters:
    @DatabaseList     - comma-separated database names, or NULL for all user DBs.
    @IncludeReadOnly  - 1 to include read-only / standby databases (default 0).
    @MinIndexWrites   - min writes for an unused index to be flagged (default 1000).
    @TopActiveIndexes - row cap for the Active NC Indexes result set (default 100).
    @HotDays/@WarmDays/@CoolDays - recency thresholds for the temperature label.

Compatibility: SQL Server 2019 (15.x) and higher.
Criticality: Medium
Author:        Ravi Sharma
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

/*------------------------------------------------------------------------------
  Configuration
------------------------------------------------------------------------------*/
DECLARE @DatabaseList     NVARCHAR(MAX) = N'userdb';   -- NULL = all user databases
DECLARE @IncludeReadOnly  BIT           = 0;
DECLARE @MinIndexWrites   BIGINT        = 1000;
DECLARE @TopActiveIndexes INT           = 100;
DECLARE @HotDays          INT           = 7;
DECLARE @WarmDays         INT           = 30;
DECLARE @CoolDays         INT           = 90;

/*------------------------------------------------------------------------------
  (0) Collection window — how much history are we actually looking at?
------------------------------------------------------------------------------*/
DECLARE @InstanceStart DATETIME;
SELECT @InstanceStart = sqlserver_start_time FROM sys.dm_os_sys_info;

/*------------------------------------------------------------------------------
  Staging table: one row per (non-heap) index across all target databases
------------------------------------------------------------------------------*/
IF OBJECT_ID(N'tempdb..#IndexActivity') IS NOT NULL DROP TABLE #IndexActivity;
CREATE TABLE #IndexActivity
(
    database_name        SYSNAME        NOT NULL,
    schema_name          SYSNAME        NOT NULL,
    table_name           SYSNAME        NOT NULL,
    index_name           SYSNAME        NULL,
    index_type           NVARCHAR(60)   NOT NULL,
    is_primary_key       BIT            NOT NULL,
    is_unique            BIT            NOT NULL,
    is_unique_constraint BIT            NOT NULL,
    is_disabled          BIT            NOT NULL,
    is_filtered          BIT            NOT NULL,
    key_columns          NVARCHAR(MAX)  NULL,
    included_columns     NVARCHAR(MAX)  NULL,
    table_rows           BIGINT         NOT NULL,
    size_mb              DECIMAL(18, 2) NOT NULL,
    user_seeks           BIGINT         NOT NULL,
    user_scans           BIGINT         NOT NULL,
    user_lookups         BIGINT         NOT NULL,
    total_reads          BIGINT         NOT NULL,
    user_updates         BIGINT         NOT NULL,
    last_user_seek       DATETIME       NULL,
    last_user_scan       DATETIME       NULL,
    last_user_lookup     DATETIME       NULL,
    last_read            DATETIME       NULL,
    last_user_update     DATETIME       NULL
);

/*------------------------------------------------------------------------------
  Per-database collection command (runs in the context of each target DB)
------------------------------------------------------------------------------*/
DECLARE @CollectCommand NVARCHAR(MAX) = N'
BEGIN TRY
;WITH IndexColumnParts AS
(
    SELECT
        ic.object_id,
        ic.index_id,
        ic.is_included_column,
        ic.key_ordinal,
        ic.is_descending_key,
        c.name AS column_name
    FROM sys.index_columns AS ic
    INNER JOIN sys.columns AS c
        ON c.object_id = ic.object_id
       AND c.column_id = ic.column_id
),
KeyCols AS
(
    SELECT
        object_id,
        index_id,
        STRING_AGG(
            QUOTENAME(column_name) + CASE WHEN is_descending_key = 1 THEN N'' DESC'' ELSE N'''' END,
            N'', ''
        ) WITHIN GROUP (ORDER BY key_ordinal) AS key_columns
    FROM IndexColumnParts
    WHERE is_included_column = 0 AND key_ordinal > 0
    GROUP BY object_id, index_id
),
IncCols AS
(
    SELECT
        object_id,
        index_id,
        STRING_AGG(QUOTENAME(column_name), N'', '') WITHIN GROUP (ORDER BY column_name) AS included_columns
    FROM IndexColumnParts
    WHERE is_included_column = 1
    GROUP BY object_id, index_id
)
INSERT INTO #IndexActivity
(
    database_name, schema_name, table_name, index_name, index_type,
    is_primary_key, is_unique, is_unique_constraint, is_disabled, is_filtered,
    key_columns, included_columns, table_rows, size_mb,
    user_seeks, user_scans, user_lookups, total_reads, user_updates,
    last_user_seek, last_user_scan, last_user_lookup, last_read, last_user_update
)
SELECT
    DB_NAME(),
    s.name,
    t.name,
    i.name,
    i.type_desc,
    i.is_primary_key,
    i.is_unique,
    i.is_unique_constraint,
    i.is_disabled,
    CASE WHEN i.filter_definition IS NOT NULL THEN 1 ELSE 0 END,
    kc.key_columns,
    ic.included_columns,
    ISNULL(tr.rc, 0),
    CAST(ISNULL(sz.pages, 0) * 8.0 / 1024.0 AS DECIMAL(18, 2)),
    ISNULL(us.user_seeks, 0),
    ISNULL(us.user_scans, 0),
    ISNULL(us.user_lookups, 0),
    ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0),
    ISNULL(us.user_updates, 0),
    us.last_user_seek,
    us.last_user_scan,
    us.last_user_lookup,
    (SELECT MAX(v) FROM (VALUES (us.last_user_seek), (us.last_user_scan), (us.last_user_lookup)) AS d(v)),
    us.last_user_update
FROM sys.indexes AS i
INNER JOIN sys.tables AS t
    ON t.object_id = i.object_id
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
LEFT JOIN KeyCols AS kc
    ON kc.object_id = i.object_id AND kc.index_id = i.index_id
LEFT JOIN IncCols AS ic
    ON ic.object_id = i.object_id AND ic.index_id = i.index_id
LEFT JOIN sys.dm_db_index_usage_stats AS us
    ON us.database_id = DB_ID()
   AND us.object_id = i.object_id
   AND us.index_id = i.index_id
OUTER APPLY
(
    SELECT SUM(ps.used_page_count) AS pages
    FROM sys.dm_db_partition_stats AS ps
    WHERE ps.object_id = i.object_id AND ps.index_id = i.index_id
) AS sz
OUTER APPLY
(
    SELECT SUM(ps.row_count) AS rc
    FROM sys.dm_db_partition_stats AS ps
    WHERE ps.object_id = i.object_id AND ps.index_id IN (0, 1)
) AS tr
WHERE i.index_id > 0            -- exclude heaps
  AND i.is_hypothetical = 0
  AND t.is_ms_shipped = 0
  AND OBJECTPROPERTY(i.object_id, N''IsUserTable'') = 1;
END TRY
BEGIN CATCH
    /* Skip databases we cannot read (offline, permissions, etc.) */
END CATCH;
';

/*------------------------------------------------------------------------------
  Execute the collection across all target databases
------------------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    EXEC dbo.sp_DBA_ForEachDatabase
        @Command           = @CollectCommand,
        @UserDatabasesOnly = 1,
        @IncludeReadOnly   = @IncludeReadOnly,
        @DatabaseList      = @DatabaseList,
        @ContinueOnError   = 1;
END
ELSE
BEGIN
    DECLARE @db_name SYSNAME;
    DECLARE @SQL NVARCHAR(MAX);

    IF OBJECT_ID(N'tempdb..#DbTargets') IS NOT NULL DROP TABLE #DbTargets;
    CREATE TABLE #DbTargets (database_name SYSNAME PRIMARY KEY);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
        INSERT INTO #DbTargets
        SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@DatabaseList, N',')
        WHERE LTRIM(RTRIM(value)) <> N'';
    ELSE
        INSERT INTO #DbTargets
        SELECT name FROM sys.databases
        WHERE database_id > 4
          AND state = 0
          AND (@IncludeReadOnly = 1 OR (is_read_only = 0 AND is_in_standby = 0));

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM #DbTargets ORDER BY database_name;
    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db_name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @CollectCommand;
        BEGIN TRY EXEC sys.sp_executesql @SQL; END TRY BEGIN CATCH END CATCH;
        FETCH NEXT FROM db_cursor INTO @db_name;
    END;
    CLOSE db_cursor; DEALLOCATE db_cursor;
    DROP TABLE #DbTargets;
END;

/*==============================================================================
  (0) Collection window
==============================================================================*/
PRINT N'--- (0) Index Usage Collection Window ---';
SELECT
    N'Collection Window' AS [Result_Set],
    @InstanceStart AS [Instance_Start_Time],
    DATEDIFF(DAY, @InstanceStart, GETDATE()) AS [Sample_Window_Days],
    (SELECT COUNT(*) FROM #IndexActivity) AS [Indexes_Sampled],
    (SELECT COUNT(DISTINCT database_name) FROM #IndexActivity) AS [Databases_Sampled],
    CASE
        WHEN DATEDIFF(DAY, @InstanceStart, GETDATE()) < 30
            THEN N'CAUTION: sample window under 30 days. Usage counters reset on restart; do not drop indexes yet.'
        ELSE N'Usage counters are cumulative since Instance_Start_Time. Confirm the window covers month-end / reporting cycles.'
    END AS [Metric_Context];

/*==============================================================================
  (1) Missing Index Recommendations (instance-wide DMV) — with proposed DDL
==============================================================================*/
PRINT N'--- (1) Missing Index Recommendations (Instance-Wide) ---';
SELECT TOP (20)
    N'Missing Index Recommendations' AS [Result_Set],
    CAST(gs.avg_user_impact * gs.avg_total_user_cost * (gs.user_seeks + gs.user_scans) AS BIGINT) AS [Index_Advantage_Score],
    DB_NAME(d.database_id) AS [Database_Name],
    d.statement AS [Table_Path],
    d.equality_columns AS [Equality_Columns],
    d.inequality_columns AS [Inequality_Columns],
    d.included_columns AS [Included_Columns],
    gs.user_seeks AS [Query_Seeks],
    gs.user_scans AS [Query_Scans],
    CAST(gs.avg_user_impact AS DECIMAL(5, 2)) AS [Avg_Query_Improvement_Pct],
    CAST(gs.avg_total_user_cost AS DECIMAL(18, 4)) AS [Avg_Query_Cost],
    gs.last_user_seek AS [Last_Requested],
    N'CREATE NONCLUSTERED INDEX [IX_' + PARSENAME(d.statement, 1)
        + N'_missing_' + CONVERT(NVARCHAR(20), g.index_group_handle) + N']'
        + N' ON ' + d.statement + N' ('
        + ISNULL(d.equality_columns, N'')
        + CASE WHEN d.equality_columns IS NOT NULL AND d.inequality_columns IS NOT NULL THEN N', ' ELSE N'' END
        + ISNULL(d.inequality_columns, N'')
        + N')'
        + CASE WHEN d.included_columns IS NOT NULL THEN N' INCLUDE (' + d.included_columns + N')' ELSE N'' END
        + N';  -- REVIEW: validate overlap with existing indexes before creating.'
        AS [Proposed_Index_DDL],
    N'Higher Index_Advantage_Score = bigger potential win. NEVER create blindly — check for overlapping/duplicate indexes and added write cost first.' AS [Metric_Context]
FROM sys.dm_db_missing_index_groups AS g
INNER JOIN sys.dm_db_missing_index_group_stats AS gs
    ON gs.group_handle = g.index_group_handle
INNER JOIN sys.dm_db_missing_index_details AS d
    ON g.index_handle = d.index_handle
WHERE @DatabaseList IS NULL
   OR DB_NAME(d.database_id) IN (
        SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@DatabaseList, N',')
        WHERE LTRIM(RTRIM(value)) <> N''
   )
ORDER BY [Index_Advantage_Score] DESC;

/*==============================================================================
  (2) Active Nonclustered Indexes (READS) — the focus of this report
      Shows HOW each index is read and HOW RECENTLY, so you can tell which
      nonclustered indexes are genuinely earning their keep.
==============================================================================*/
PRINT N'--- (2) Active Nonclustered Indexes (Read Activity) ---';
SELECT TOP (@TopActiveIndexes)
    N'Active Nonclustered Indexes' AS [Result_Set],
    database_name           AS [Database_Name],
    schema_name             AS [Schema_Name],
    table_name              AS [Table_Name],
    index_name              AS [Index_Name],
    CASE
        WHEN is_primary_key = 1       THEN N'PRIMARY KEY (NC)'
        WHEN is_unique_constraint = 1 THEN N'UNIQUE CONSTRAINT'
        WHEN is_unique = 1            THEN N'UNIQUE INDEX'
        WHEN is_filtered = 1          THEN N'FILTERED INDEX'
        ELSE N'STANDARD NONCLUSTERED'
    END                     AS [Index_Purpose],
    key_columns             AS [Key_Columns],
    included_columns        AS [Included_Columns],
    user_seeks              AS [Seeks],
    user_scans              AS [Scans],
    user_lookups            AS [Lookups],
    total_reads             AS [Total_Reads],
    user_updates            AS [Writes],
    CASE
        WHEN user_updates = 0 THEN NULL
        ELSE CAST(total_reads * 1.0 / user_updates AS DECIMAL(18, 2))
    END                     AS [Read_Per_Write_Ratio],
    CASE
        WHEN user_scans > (user_seeks + user_lookups)
            THEN N'SCAN-HEAVY (range/whole-index scans — check key column order)'
        WHEN user_lookups > user_seeks
            THEN N'LOOKUP-DRIVEN (key lookups from other indexes)'
        ELSE N'SEEK-FRIENDLY (point/range seeks — efficient)'
    END                     AS [Access_Pattern],
    CASE
        WHEN last_read IS NULL
            THEN N'COLD (reads counted, but not since restart window)'
        WHEN DATEDIFF(DAY, last_read, GETDATE()) <= @HotDays  THEN N'HOT'
        WHEN DATEDIFF(DAY, last_read, GETDATE()) <= @WarmDays THEN N'WARM'
        WHEN DATEDIFF(DAY, last_read, GETDATE()) <= @CoolDays THEN N'COOL'
        ELSE N'COLD'
    END                     AS [Activity_Level],
    last_read               AS [Last_Read],
    last_user_seek          AS [Last_Seek],
    last_user_scan          AS [Last_Scan],
    last_user_lookup        AS [Last_Lookup],
    last_user_update        AS [Last_Write],
    table_rows              AS [Table_Rows],
    size_mb                 AS [Size_MB],
    CASE
        WHEN user_updates > 0 AND total_reads * 1.0 / user_updates < 0.1
             AND (last_read IS NULL OR DATEDIFF(DAY, last_read, GETDATE()) > @CoolDays)
            THEN N'REVIEW / LIKELY DROP'
        WHEN user_scans > (user_seeks + user_lookups) AND table_rows > 100000
            THEN N'KEEP BUT REDESIGN'
        WHEN last_read IS NOT NULL AND DATEDIFF(DAY, last_read, GETDATE()) <= @WarmDays
            THEN N'KEEP'
        ELSE N'KEEP / MONITOR'
    END                     AS [Keep_Or_Drop],
    CASE
        WHEN user_updates > 0 AND total_reads * 1.0 / user_updates < 0.1
             AND (last_read IS NULL OR DATEDIFF(DAY, last_read, GETDATE()) > @CoolDays)
            THEN N'Rarely read but carries write cost and not read recently — validate against a full cycle, then consider dropping.'
        WHEN user_scans > (user_seeks + user_lookups) AND table_rows > 100000
            THEN N'Scan-heavy on a large table — keep only if needed; review key column order / query predicates.'
        WHEN last_read IS NOT NULL AND DATEDIFF(DAY, last_read, GETDATE()) <= @WarmDays
            THEN N'Recently and actively read — keep.'
        ELSE N'Read at some point but not recently — keep and monitor over the next cycle.'
    END                     AS [Recommendation]
FROM #IndexActivity
WHERE index_type = N'NONCLUSTERED'
  AND total_reads > 0
ORDER BY total_reads DESC, size_mb DESC;

/*==============================================================================
  (3) Unused Nonclustered Indexes — reads = 0 but writes above threshold.
      Pure maintenance overhead + wasted storage. PK / unique constraints are
      intentionally excluded (dropping them would break constraints).
==============================================================================*/
PRINT N'--- (3) Unused Nonclustered Indexes (Write-Only / Drop Candidates) ---';
SELECT
    N'Unused Nonclustered Indexes' AS [Result_Set],
    database_name    AS [Database_Name],
    schema_name      AS [Schema_Name],
    table_name       AS [Table_Name],
    index_name       AS [Index_Name],
    key_columns      AS [Key_Columns],
    included_columns AS [Included_Columns],
    total_reads      AS [Total_Reads],
    user_updates     AS [Writes],
    last_user_update AS [Last_Write],
    table_rows       AS [Table_Rows],
    size_mb          AS [Reclaimable_Size_MB],
    CASE
        WHEN is_disabled = 1 THEN N'REVIEW (already disabled)'
        ELSE N'DROP CANDIDATE'
    END              AS [Keep_Or_Drop],
    CASE
        WHEN is_disabled = 1 THEN N'Already DISABLED — decide whether to keep the definition or drop it entirely.'
        ELSE N'Zero reads with active writes: maintenance overhead only. Drop after confirming a full business cycle of uptime.'
    END              AS [Metric_Context],
    N'-- REVIEW BEFORE EXECUTING' + CHAR(13) + CHAR(10)
        + N'USE ' + QUOTENAME(database_name) + N';' + CHAR(13) + CHAR(10)
        + N'DROP INDEX ' + QUOTENAME(index_name) + N' ON '
        + QUOTENAME(schema_name) + N'.' + QUOTENAME(table_name) + N';'
        AS [Drop_DDL]
FROM #IndexActivity
WHERE index_type = N'NONCLUSTERED'
  AND is_primary_key = 0
  AND is_unique_constraint = 0
  AND total_reads = 0
  AND user_updates > @MinIndexWrites
ORDER BY size_mb DESC, user_updates DESC;

/*==============================================================================
  (4) Per-Database Index Usage Summary
==============================================================================*/
PRINT N'--- (4) Per-Database Index Usage Summary ---';
SELECT
    N'Per-Database Summary' AS [Result_Set],
    database_name AS [Database_Name],
    COUNT(*) AS [Nonclustered_Indexes],
    SUM(CASE WHEN total_reads > 0 THEN 1 ELSE 0 END) AS [Read_Active_Indexes],
    SUM(CASE WHEN total_reads > 0
              AND last_read IS NOT NULL
              AND DATEDIFF(DAY, last_read, GETDATE()) <= @HotDays
             THEN 1 ELSE 0 END) AS [Hot_Indexes],
    SUM(CASE WHEN total_reads = 0 AND user_updates > @MinIndexWrites
              AND is_primary_key = 0 AND is_unique_constraint = 0
             THEN 1 ELSE 0 END) AS [Unused_Drop_Candidates],
    SUM(total_reads) AS [Total_Reads],
    SUM(user_updates) AS [Total_Writes],
    CAST(SUM(size_mb) AS DECIMAL(18, 2)) AS [Total_NC_Size_MB],
    CAST(SUM(CASE WHEN total_reads = 0 AND user_updates > @MinIndexWrites
                   AND is_primary_key = 0 AND is_unique_constraint = 0
                  THEN size_mb ELSE 0 END) AS DECIMAL(18, 2)) AS [Reclaimable_Size_MB]
FROM #IndexActivity
WHERE index_type = N'NONCLUSTERED'
GROUP BY database_name
ORDER BY [Reclaimable_Size_MB] DESC, [Total_Reads] DESC;

IF OBJECT_ID(N'tempdb..#IndexActivity') IS NOT NULL DROP TABLE #IndexActivity;
