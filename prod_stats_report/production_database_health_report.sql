/*
================================================================================
Production Database Health Assessment Report
================================================================================
Description:
    Generates a consolidated production health report across all online user
    databases. Produces one summary row per database plus ranked detail reports
    for fragmentation, statistics, missing/duplicate/unused indexes, health
    scores, and maintenance recommendations.

    Database-scoped DMVs (sys.dm_db_index_physical_stats,
    sys.dm_db_stats_properties) are collected by looping each database context,
    consistent with production best practice.

Reports:
    1.  Database Health Summary (one row per database)
    2.  Top 20 Largest Databases
    3.  Top Fragmented Tables (all databases)
    4.  Top Fragmented Indexes (> @FragCriticalPct)
    5.  Outdated Statistics (ranked by modification counter)
    6.  Missing Indexes (instance DMV)
    7.  Duplicate Indexes
    8.  Unused Indexes
    9.  Database Health Score (0-100) with status
    10. Maintenance Recommendations

Parameters (edit before running):
    @DatabaseList           - comma-separated names or NULL for all user DBs
    @IncludeReadOnly        - include read-only databases
    @MinPageCount           - minimum pages for fragmentation analysis
    @FragWarningPct         - fragmentation warning threshold (default 5)
    @FragCriticalPct        - fragmentation critical threshold (default 30)
    @StatsWarningPct        - outdated stats % for Warning status (default 5)
    @StatsCriticalPct       - outdated stats % for Critical status (default 15)
    @StatsStalePct          - row-modification % threshold (default 20)
    @StatsUseSqrtThreshold   - also flag when mods > SQRT(rows * 1000)
    @MinIndexWrites          - minimum writes for unused-index detection
    @TopN                    - row limit for ranked detail reports

Warning:
    sys.dm_db_index_physical_stats can be expensive on large databases.
    Run during off-peak hours on production instances.

Prerequisites:
    SQL Server 2016+ (STRING_SPLIT). Optional: dbo.sp_DBA_ForEachDatabase
    from sql_server/00_Framework for cleaner cross-database execution.

Criticality: Medium (read-only report)
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-------------------------------------------------------------------------------
-- Parameters
-------------------------------------------------------------------------------
DECLARE @DatabaseList           NVARCHAR(MAX) = NULL;
DECLARE @IncludeReadOnly        BIT = 0;
DECLARE @MinPageCount           INT = 1000;
DECLARE @FragWarningPct         DECIMAL(5, 2) = 5.0;
DECLARE @FragCriticalPct        DECIMAL(5, 2) = 30.0;
DECLARE @StatsWarningPct        DECIMAL(5, 2) = 5.0;
DECLARE @StatsCriticalPct       DECIMAL(5, 2) = 15.0;
DECLARE @StatsStalePct          DECIMAL(5, 2) = 20.0;
DECLARE @StatsUseSqrtThreshold  BIT = 1;
DECLARE @MinIndexWrites         BIGINT = 1000;
DECLARE @TopN                   INT = 20;

DECLARE @ReportStart            DATETIME2(0) = SYSDATETIME();
DECLARE @db_name                SYSNAME;
DECLARE @SQL                    NVARCHAR(MAX);

-------------------------------------------------------------------------------
-- Target database list
-------------------------------------------------------------------------------
IF OBJECT_ID(N'tempdb..#DbTargets') IS NOT NULL DROP TABLE #DbTargets;
CREATE TABLE #DbTargets (
    database_id     INT NOT NULL PRIMARY KEY,
    database_name   SYSNAME NOT NULL
);

IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
BEGIN
    INSERT INTO #DbTargets (database_id, database_name)
    SELECT d.database_id, d.name
    FROM sys.databases AS d
    INNER JOIN (
        SELECT LTRIM(RTRIM(value)) AS database_name
        FROM STRING_SPLIT(@DatabaseList, N',')
        WHERE LTRIM(RTRIM(value)) <> N''
    ) AS req ON req.database_name = d.name
    WHERE d.state = 0
      AND d.is_in_standby = 0;
END
ELSE
BEGIN
    INSERT INTO #DbTargets (database_id, database_name)
    SELECT d.database_id, d.name
    FROM sys.databases AS d
    WHERE d.state = 0
      AND d.is_in_standby = 0
      AND d.database_id > 4
      AND (@IncludeReadOnly = 1 OR d.is_read_only = 0);
END;

-------------------------------------------------------------------------------
-- Instance-level size and backup metadata
-------------------------------------------------------------------------------
IF OBJECT_ID(N'tempdb..#DbInstanceInfo') IS NOT NULL DROP TABLE #DbInstanceInfo;
CREATE TABLE #DbInstanceInfo (
    database_id             INT NOT NULL PRIMARY KEY,
    database_name           SYSNAME NOT NULL,
    size_gb                 DECIMAL(18, 2) NOT NULL,
    data_size_gb            DECIMAL(18, 2) NOT NULL,
    log_size_gb             DECIMAL(18, 2) NOT NULL,
    compatibility_level     TINYINT NOT NULL,
    recovery_model          NVARCHAR(60) NOT NULL,
    state_desc              NVARCHAR(60) NOT NULL,
    is_auto_update_stats_on BIT NOT NULL,
    last_full_backup        DATETIME NULL,
    last_log_backup         DATETIME NULL
);

INSERT INTO #DbInstanceInfo (
    database_id, database_name, size_gb, data_size_gb, log_size_gb,
    compatibility_level, recovery_model, state_desc, is_auto_update_stats_on,
    last_full_backup, last_log_backup
)
SELECT
    d.database_id,
    d.name,
    CAST(SUM(mf.size) * 8.0 / 1024 / 1024 AS DECIMAL(18, 2)),
    CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size ELSE 0 END) * 8.0 / 1024 / 1024 AS DECIMAL(18, 2)),
    CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size ELSE 0 END) * 8.0 / 1024 / 1024 AS DECIMAL(18, 2)),
    d.compatibility_level,
    d.recovery_model_desc,
    d.state_desc,
    d.is_auto_update_stats_on,
    bk.last_full_backup,
    bk.last_log_backup
FROM sys.databases AS d
INNER JOIN #DbTargets AS t ON t.database_id = d.database_id
INNER JOIN sys.master_files AS mf ON mf.database_id = d.database_id
LEFT JOIN (
    SELECT
        database_name,
        MAX(CASE WHEN type = N'D' THEN backup_finish_date END) AS last_full_backup,
        MAX(CASE WHEN type = N'L' THEN backup_finish_date END) AS last_log_backup
    FROM msdb.dbo.backupset
    GROUP BY database_name
) AS bk ON bk.database_name = d.name
GROUP BY
    d.database_id, d.name, d.compatibility_level, d.recovery_model_desc,
    d.state_desc, d.is_auto_update_stats_on, bk.last_full_backup, bk.last_log_backup;

-------------------------------------------------------------------------------
-- Per-database metrics (populated in database context)
-------------------------------------------------------------------------------
IF OBJECT_ID(N'tempdb..#DatabaseHealth') IS NOT NULL DROP TABLE #DatabaseHealth;
CREATE TABLE #DatabaseHealth (
    database_name                   SYSNAME NOT NULL PRIMARY KEY,
    user_tables                     INT NOT NULL DEFAULT 0,
    views_count                     INT NOT NULL DEFAULT 0,
    procedures_count                INT NOT NULL DEFAULT 0,
    functions_count                 INT NOT NULL DEFAULT 0,
    index_count                     INT NOT NULL DEFAULT 0,
    approx_row_count                BIGINT NOT NULL DEFAULT 0,
    total_indexes                   INT NOT NULL DEFAULT 0,
    fragmented_indexes              INT NOT NULL DEFAULT 0,
    highly_fragmented_indexes       INT NOT NULL DEFAULT 0,
    fragmented_tables               INT NOT NULL DEFAULT 0,
    avg_fragmentation_pct           DECIMAL(8, 2) NULL,
    max_fragmentation_pct           DECIMAL(8, 2) NULL,
    largest_fragmented_index        NVARCHAR(500) NULL,
    largest_fragmented_table        NVARCHAR(500) NULL,
    total_statistics                INT NOT NULL DEFAULT 0,
    outdated_statistics             INT NOT NULL DEFAULT 0,
    outdated_statistics_pct         DECIMAL(8, 2) NULL,
    never_updated_statistics        INT NOT NULL DEFAULT 0,
    auto_created_statistics         INT NOT NULL DEFAULT 0,
    user_created_statistics         INT NOT NULL DEFAULT 0,
    auto_update_off_statistics      INT NOT NULL DEFAULT 0,
    norecompute_statistics          INT NOT NULL DEFAULT 0,
    last_stats_update               DATETIME NULL,
    missing_index_count             INT NOT NULL DEFAULT 0,
    duplicate_index_count           INT NOT NULL DEFAULT 0,
    unused_index_count              INT NOT NULL DEFAULT 0,
    disabled_index_count            INT NOT NULL DEFAULT 0,
    heap_tables                     INT NOT NULL DEFAULT 0,
    forwarded_records               BIGINT NOT NULL DEFAULT 0,
    tables_without_pk               INT NOT NULL DEFAULT 0,
    tables_without_clustered_index  INT NOT NULL DEFAULT 0,
    collection_error                NVARCHAR(4000) NULL
);

IF OBJECT_ID(N'tempdb..#FragTables') IS NOT NULL DROP TABLE #FragTables;
CREATE TABLE #FragTables (
    database_name       SYSNAME NOT NULL,
    schema_name         SYSNAME NOT NULL,
    table_name          SYSNAME NOT NULL,
    max_fragmentation   DECIMAL(8, 2) NOT NULL,
    page_count          BIGINT NOT NULL,
    fragmented_indexes  INT NOT NULL
);

IF OBJECT_ID(N'tempdb..#FragIndexes') IS NOT NULL DROP TABLE #FragIndexes;
CREATE TABLE #FragIndexes (
    database_name       SYSNAME NOT NULL,
    schema_name         SYSNAME NOT NULL,
    table_name          SYSNAME NOT NULL,
    index_name          SYSNAME NULL,
    fragmentation_pct   DECIMAL(8, 2) NOT NULL,
    page_count          BIGINT NOT NULL
);

IF OBJECT_ID(N'tempdb..#OutdatedStats') IS NOT NULL DROP TABLE #OutdatedStats;
CREATE TABLE #OutdatedStats (
    database_name           SYSNAME NOT NULL,
    schema_name             SYSNAME NOT NULL,
    table_name              SYSNAME NOT NULL,
    statistics_name         SYSNAME NOT NULL,
    last_updated            DATETIME NULL,
    total_rows              BIGINT NULL,
    modification_counter    BIGINT NOT NULL,
    modification_pct        DECIMAL(18, 2) NULL,
    auto_created            BIT NOT NULL,
    no_recompute            BIT NOT NULL
);

IF OBJECT_ID(N'tempdb..#DuplicateIndexes') IS NOT NULL DROP TABLE #DuplicateIndexes;
CREATE TABLE #DuplicateIndexes (
    database_name   SYSNAME NOT NULL,
    schema_name     SYSNAME NOT NULL,
    table_name      SYSNAME NOT NULL,
    index_1         SYSNAME NOT NULL,
    index_2         SYSNAME NOT NULL,
    column_list     NVARCHAR(MAX) NOT NULL
);

IF OBJECT_ID(N'tempdb..#UnusedIndexes') IS NOT NULL DROP TABLE #UnusedIndexes;
CREATE TABLE #UnusedIndexes (
    database_name   SYSNAME NOT NULL,
    schema_name     SYSNAME NOT NULL,
    table_name      SYSNAME NOT NULL,
    index_name      SYSNAME NOT NULL,
    writes          BIGINT NOT NULL,
    reads           BIGINT NOT NULL,
    size_mb         DECIMAL(18, 2) NOT NULL
);

INSERT INTO #DatabaseHealth (database_name)
SELECT database_name
FROM #DbTargets;

DECLARE @CollectCommand NVARCHAR(MAX) = N'
BEGIN TRY
DECLARE @DbAutoUpdateStats BIT = (SELECT is_auto_update_stats_on FROM sys.databases WHERE database_id = DB_ID());

DELETE FROM #DatabaseHealth WHERE database_name = DB_NAME();

INSERT INTO #DatabaseHealth (
    database_name, user_tables, views_count, procedures_count, functions_count,
    index_count, approx_row_count, total_indexes, fragmented_indexes,
    highly_fragmented_indexes, fragmented_tables, avg_fragmentation_pct,
    max_fragmentation_pct, largest_fragmented_index, largest_fragmented_table,
    total_statistics, outdated_statistics, outdated_statistics_pct,
    never_updated_statistics, auto_created_statistics, user_created_statistics,
    auto_update_off_statistics, norecompute_statistics, last_stats_update,
    duplicate_index_count, unused_index_count, disabled_index_count,
    heap_tables, forwarded_records, tables_without_pk, tables_without_clustered_index
)
SELECT
    DB_NAME(),
    ISNULL(obj.user_tables, 0),
    ISNULL(obj.views_count, 0),
    ISNULL(obj.procedures_count, 0),
    ISNULL(obj.functions_count, 0),
    ISNULL(obj.index_count, 0),
    ISNULL(obj.approx_row_count, 0),
    ISNULL(frag.total_indexes, 0),
    ISNULL(frag.fragmented_indexes, 0),
    ISNULL(frag.highly_fragmented_indexes, 0),
    ISNULL(frag.fragmented_tables, 0),
    frag.avg_fragmentation_pct,
    frag.max_fragmentation_pct,
    frag.largest_fragmented_index,
    frag.largest_fragmented_table,
    ISNULL(st.total_statistics, 0),
    ISNULL(st.outdated_statistics, 0),
    st.outdated_statistics_pct,
    ISNULL(st.never_updated_statistics, 0),
    ISNULL(st.auto_created_statistics, 0),
    ISNULL(st.user_created_statistics, 0),
    ISNULL(st.auto_update_off_statistics, 0),
    ISNULL(st.norecompute_statistics, 0),
    st.last_stats_update,
    ISNULL(dup.duplicate_index_count, 0),
    ISNULL(unused.unused_index_count, 0),
    ISNULL(dis.disabled_index_count, 0),
    ISNULL(heap.heap_tables, 0),
    ISNULL(heap.forwarded_records, 0),
    ISNULL(pk.tables_without_pk, 0),
    ISNULL(pk.tables_without_clustered_index, 0)
FROM (
    SELECT
        SUM(CASE WHEN o.type = N''U'' THEN 1 ELSE 0 END) AS user_tables,
        SUM(CASE WHEN o.type = N''V'' THEN 1 ELSE 0 END) AS views_count,
        SUM(CASE WHEN o.type = N''P'' THEN 1 ELSE 0 END) AS procedures_count,
        SUM(CASE WHEN o.type IN (N''FN'', N''IF'', N''TF'') THEN 1 ELSE 0 END) AS functions_count,
        SUM(CASE WHEN i.index_id > 0 AND o.type = N''U'' THEN 1 ELSE 0 END) AS index_count,
        SUM(CASE WHEN o.type = N''U'' THEN ISNULL(ps.row_count, 0) ELSE 0 END) AS approx_row_count
    FROM sys.objects AS o
    LEFT JOIN sys.indexes AS i
        ON i.object_id = o.object_id AND i.index_id > 0
    LEFT JOIN sys.dm_db_partition_stats AS ps
        ON ps.object_id = o.object_id AND ps.index_id IN (0, 1)
    WHERE o.is_ms_shipped = 0
) AS obj
CROSS JOIN (
    SELECT
        COUNT(*) AS total_indexes,
        SUM(CASE WHEN f.avg_fragmentation_in_percent > ' + CAST(@FragWarningPct AS NVARCHAR(20)) + N' THEN 1 ELSE 0 END) AS fragmented_indexes,
        SUM(CASE WHEN f.avg_fragmentation_in_percent > ' + CAST(@FragCriticalPct AS NVARCHAR(20)) + N' THEN 1 ELSE 0 END) AS highly_fragmented_indexes,
        COUNT(DISTINCT CASE WHEN f.avg_fragmentation_in_percent > ' + CAST(@FragWarningPct AS NVARCHAR(20)) + N' THEN f.object_id END) AS fragmented_tables,
        CAST(AVG(CASE WHEN f.index_id > 0 THEN f.avg_fragmentation_in_percent END) AS DECIMAL(8, 2)) AS avg_fragmentation_pct,
        CAST(MAX(CASE WHEN f.index_id > 0 THEN f.avg_fragmentation_in_percent END) AS DECIMAL(8, 2)) AS max_fragmentation_pct,
        (
            SELECT TOP (1)
                QUOTENAME(OBJECT_SCHEMA_NAME(ps.object_id)) + N''.'' + QUOTENAME(OBJECT_NAME(ps.object_id))
                + N''.'' + QUOTENAME(i.name) + N'' ('' + CAST(CAST(ps.avg_fragmentation_in_percent AS DECIMAL(8, 2)) AS NVARCHAR(20)) + N''%)''
            FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N''LIMITED'') AS ps
            INNER JOIN sys.indexes AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
            INNER JOIN sys.objects AS t ON t.object_id = ps.object_id AND t.type = N''U'' AND t.is_ms_shipped = 0
            WHERE ps.index_id > 0
              AND ps.page_count >= ' + CAST(@MinPageCount AS NVARCHAR(20)) + N'
              AND ps.avg_fragmentation_in_percent > ' + CAST(@FragWarningPct AS NVARCHAR(20)) + N'
            ORDER BY ps.avg_fragmentation_in_percent DESC, ps.page_count DESC
        ) AS largest_fragmented_index,
        (
            SELECT TOP (1)
                QUOTENAME(OBJECT_SCHEMA_NAME(ps.object_id)) + N''.'' + QUOTENAME(OBJECT_NAME(ps.object_id))
                + N'' ('' + CAST(CAST(MAX(ps.avg_fragmentation_in_percent) AS DECIMAL(8, 2)) AS NVARCHAR(20)) + N''%)''
            FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N''LIMITED'') AS ps
            INNER JOIN sys.objects AS t ON t.object_id = ps.object_id AND t.type = N''U'' AND t.is_ms_shipped = 0
            WHERE ps.index_id > 0
              AND ps.page_count >= ' + CAST(@MinPageCount AS NVARCHAR(20)) + N'
            GROUP BY ps.object_id
            HAVING MAX(ps.avg_fragmentation_in_percent) > ' + CAST(@FragWarningPct AS NVARCHAR(20)) + N'
            ORDER BY MAX(ps.avg_fragmentation_in_percent) DESC
        ) AS largest_fragmented_table
    FROM (
        SELECT
            ps.object_id,
            ps.index_id,
            ps.avg_fragmentation_in_percent,
            ps.page_count
        FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N''LIMITED'') AS ps
        INNER JOIN sys.objects AS t ON t.object_id = ps.object_id AND t.type = N''U'' AND t.is_ms_shipped = 0
        WHERE ps.page_count >= ' + CAST(@MinPageCount AS NVARCHAR(20)) + N'
    ) AS f
) AS frag
CROSS JOIN (
    SELECT
        COUNT(*) AS total_statistics,
        SUM(CASE
                WHEN sp.last_updated IS NULL THEN 1
                WHEN ' + CAST(@StatsUseSqrtThreshold AS NVARCHAR(1)) + N' = 1
                     AND sp.modification_counter > SQRT(CAST(sp.rows AS FLOAT) * 1000.0) THEN 1
                WHEN sp.modification_counter > CAST(sp.rows AS DECIMAL(18, 2)) * ' + CAST(@StatsStalePct AS NVARCHAR(20)) + N' / 100.0 THEN 1
                ELSE 0
            END) AS outdated_statistics,
        CAST(
            100.0 * SUM(CASE
                WHEN sp.last_updated IS NULL THEN 1
                WHEN ' + CAST(@StatsUseSqrtThreshold AS NVARCHAR(1)) + N' = 1
                     AND sp.modification_counter > SQRT(CAST(sp.rows AS FLOAT) * 1000.0) THEN 1
                WHEN sp.modification_counter > CAST(sp.rows AS DECIMAL(18, 2)) * ' + CAST(@StatsStalePct AS NVARCHAR(20)) + N' / 100.0 THEN 1
                ELSE 0
            END) / NULLIF(COUNT(*), 0)
        AS DECIMAL(8, 2)) AS outdated_statistics_pct,
        SUM(CASE WHEN sp.last_updated IS NULL THEN 1 ELSE 0 END) AS never_updated_statistics,
        SUM(CASE WHEN s.auto_created = 1 THEN 1 ELSE 0 END) AS auto_created_statistics,
        SUM(CASE WHEN s.auto_created = 0 THEN 1 ELSE 0 END) AS user_created_statistics,
        SUM(CASE WHEN @DbAutoUpdateStats = 0 OR s.no_recompute = 1 THEN 1 ELSE 0 END) AS auto_update_off_statistics,
        SUM(CASE WHEN s.no_recompute = 1 THEN 1 ELSE 0 END) AS norecompute_statistics,
        MAX(sp.last_updated) AS last_stats_update
    FROM sys.stats AS s
    INNER JOIN sys.objects AS o ON o.object_id = s.object_id AND o.type = N''U'' AND o.is_ms_shipped = 0
    CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
) AS st
CROSS JOIN (
    SELECT COUNT(*) AS duplicate_index_count
    FROM (
        SELECT i.object_id, i.index_id,
            STUFF((
                SELECT N'','' + c.name
                FROM sys.index_columns AS ic2
                INNER JOIN sys.columns AS c ON c.object_id = ic2.object_id AND c.column_id = ic2.column_id
                WHERE ic2.object_id = i.object_id
                  AND ic2.index_id = i.index_id
                  AND ic2.is_included_column = 0
                ORDER BY ic2.key_ordinal
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 1, N'''') AS key_cols
        FROM sys.indexes AS i
        INNER JOIN sys.objects AS t ON t.object_id = i.object_id AND t.type = N''U'' AND t.is_ms_shipped = 0
        WHERE i.index_id > 1
    ) AS a
    INNER JOIN (
        SELECT i.object_id, i.index_id,
            STUFF((
                SELECT N'','' + c.name
                FROM sys.index_columns AS ic2
                INNER JOIN sys.columns AS c ON c.object_id = ic2.object_id AND c.column_id = ic2.column_id
                WHERE ic2.object_id = i.object_id
                  AND ic2.index_id = i.index_id
                  AND ic2.is_included_column = 0
                ORDER BY ic2.key_ordinal
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 1, N'''') AS key_cols
        FROM sys.indexes AS i
        INNER JOIN sys.objects AS t ON t.object_id = i.object_id AND t.type = N''U'' AND t.is_ms_shipped = 0
        WHERE i.index_id > 1
    ) AS b
        ON a.object_id = b.object_id
       AND a.index_id < b.index_id
       AND a.key_cols = b.key_cols
) AS dup
CROSS JOIN (
    SELECT COUNT(*) AS unused_index_count
    FROM sys.indexes AS i
    INNER JOIN sys.objects AS t ON t.object_id = i.object_id AND t.type = N''U'' AND t.is_ms_shipped = 0
    INNER JOIN sys.dm_db_index_usage_stats AS us
        ON us.database_id = DB_ID()
       AND us.object_id = i.object_id
       AND us.index_id = i.index_id
    WHERE i.index_id > 1
      AND i.is_primary_key = 0
      AND i.is_unique_constraint = 0
      AND us.user_updates > ' + CAST(@MinIndexWrites AS NVARCHAR(20)) + N'
      AND (us.user_seeks + us.user_scans + us.user_lookups) = 0
) AS unused
CROSS JOIN (
    SELECT COUNT(*) AS disabled_index_count
    FROM sys.indexes AS i
    INNER JOIN sys.objects AS t ON t.object_id = i.object_id AND t.type = N''U'' AND t.is_ms_shipped = 0
    WHERE i.is_disabled = 1
) AS dis
CROSS JOIN (
    SELECT
        COUNT(*) AS heap_tables,
        SUM(ISNULL(ps.forwarded_record_count, 0)) AS forwarded_records
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N''LIMITED'') AS ps
    INNER JOIN sys.objects AS t ON t.object_id = ps.object_id AND t.type = N''U'' AND t.is_ms_shipped = 0
    WHERE ps.index_id = 0
) AS heap
CROSS JOIN (
    SELECT
        SUM(CASE WHEN pk.object_id IS NULL THEN 1 ELSE 0 END) AS tables_without_pk,
        SUM(CASE WHEN cl.object_id IS NULL THEN 1 ELSE 0 END) AS tables_without_clustered_index
    FROM sys.tables AS t
    LEFT JOIN (
        SELECT DISTINCT ic.object_id
        FROM sys.indexes AS ic
        WHERE ic.is_primary_key = 1
    ) AS pk ON pk.object_id = t.object_id
    LEFT JOIN (
        SELECT DISTINCT ic.object_id
        FROM sys.indexes AS ic
        WHERE ic.type = 1
    ) AS cl ON cl.object_id = t.object_id
    WHERE t.is_ms_shipped = 0
) AS pk;

INSERT INTO #FragTables (database_name, schema_name, table_name, max_fragmentation, page_count, fragmented_indexes)
SELECT
    DB_NAME(),
    OBJECT_SCHEMA_NAME(x.object_id),
    OBJECT_NAME(x.object_id),
    x.max_fragmentation,
    x.page_count,
    x.fragmented_indexes
FROM (
    SELECT
        ps.object_id,
        CAST(MAX(ps.avg_fragmentation_in_percent) AS DECIMAL(8, 2)) AS max_fragmentation,
        SUM(ps.page_count) AS page_count,
        SUM(CASE WHEN ps.avg_fragmentation_in_percent > ' + CAST(@FragWarningPct AS NVARCHAR(20)) + N' THEN 1 ELSE 0 END) AS fragmented_indexes
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N''LIMITED'') AS ps
    INNER JOIN sys.objects AS t ON t.object_id = ps.object_id AND t.type = N''U'' AND t.is_ms_shipped = 0
    WHERE ps.index_id > 0
      AND ps.page_count >= ' + CAST(@MinPageCount AS NVARCHAR(20)) + N'
    GROUP BY ps.object_id
    HAVING MAX(ps.avg_fragmentation_in_percent) > ' + CAST(@FragWarningPct AS NVARCHAR(20)) + N'
) AS x;

INSERT INTO #FragIndexes (database_name, schema_name, table_name, index_name, fragmentation_pct, page_count)
SELECT
    DB_NAME(),
    s.name,
    t.name,
    i.name,
    CAST(ps.avg_fragmentation_in_percent AS DECIMAL(8, 2)),
    ps.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N''LIMITED'') AS ps
INNER JOIN sys.indexes AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
INNER JOIN sys.tables AS t ON t.object_id = ps.object_id
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
  AND ps.index_id > 0
  AND ps.page_count >= ' + CAST(@MinPageCount AS NVARCHAR(20)) + N'
  AND ps.avg_fragmentation_in_percent > ' + CAST(@FragCriticalPct AS NVARCHAR(20)) + N';

INSERT INTO #OutdatedStats (
    database_name, schema_name, table_name, statistics_name, last_updated,
    total_rows, modification_counter, modification_pct, auto_created, no_recompute
)
SELECT
    DB_NAME(),
    OBJECT_SCHEMA_NAME(s.object_id),
    OBJECT_NAME(s.object_id),
    s.name,
    sp.last_updated,
    sp.rows,
    sp.modification_counter,
    CAST(sp.modification_counter AS DECIMAL(18, 2)) / NULLIF(sp.rows, 0) * 100.0,
    s.auto_created,
    s.no_recompute
FROM sys.stats AS s
INNER JOIN sys.objects AS o ON o.object_id = s.object_id AND o.type = N''U'' AND o.is_ms_shipped = 0
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE sp.last_updated IS NULL
   OR (' + CAST(@StatsUseSqrtThreshold AS NVARCHAR(1)) + N' = 1
       AND sp.modification_counter > SQRT(CAST(sp.rows AS FLOAT) * 1000.0))
   OR sp.modification_counter > CAST(sp.rows AS DECIMAL(18, 2)) * ' + CAST(@StatsStalePct AS NVARCHAR(20)) + N' / 100.0;

;WITH IndexCols AS (
    SELECT
        i.object_id,
        i.index_id,
        i.name,
        OBJECT_SCHEMA_NAME(i.object_id) AS schema_name,
        OBJECT_NAME(i.object_id) AS table_name,
        STUFF((
            SELECT N'','' + c.name
            FROM sys.index_columns AS ic2
            INNER JOIN sys.columns AS c ON c.object_id = ic2.object_id AND c.column_id = ic2.column_id
            WHERE ic2.object_id = i.object_id
              AND ic2.index_id = i.index_id
              AND ic2.is_included_column = 0
            ORDER BY ic2.key_ordinal
            FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 1, N'''') AS Cols
    FROM sys.indexes AS i
    INNER JOIN sys.objects AS t ON t.object_id = i.object_id AND t.type = N''U'' AND t.is_ms_shipped = 0
    WHERE i.index_id > 1
)
INSERT INTO #DuplicateIndexes (database_name, schema_name, table_name, index_1, index_2, column_list)
SELECT
    DB_NAME(),
    i1.schema_name,
    i1.table_name,
    i1.name,
    i2.name,
    i1.Cols
FROM IndexCols AS i1
INNER JOIN IndexCols AS i2
    ON i1.object_id = i2.object_id
   AND i1.index_id < i2.index_id
   AND i1.Cols = i2.Cols;

INSERT INTO #UnusedIndexes (database_name, schema_name, table_name, index_name, writes, reads, size_mb)
SELECT
    DB_NAME(),
    s.name,
    t.name,
    i.name,
    us.user_updates,
    us.user_seeks + us.user_scans + us.user_lookups,
    CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(18, 2))
FROM sys.indexes AS i
INNER JOIN sys.tables AS t ON t.object_id = i.object_id
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
INNER JOIN sys.dm_db_index_usage_stats AS us
    ON us.database_id = DB_ID()
   AND us.object_id = i.object_id
   AND us.index_id = i.index_id
INNER JOIN sys.dm_db_partition_stats AS ps
    ON ps.object_id = i.object_id
   AND ps.index_id = i.index_id
WHERE t.is_ms_shipped = 0
  AND i.index_id > 1
  AND i.is_primary_key = 0
  AND i.is_unique_constraint = 0
  AND us.user_updates > ' + CAST(@MinIndexWrites AS NVARCHAR(20)) + N'
  AND (us.user_seeks + us.user_scans + us.user_lookups) = 0
GROUP BY s.name, t.name, i.name, us.user_updates, us.user_seeks, us.user_scans, us.user_lookups;

END TRY
BEGIN CATCH
    IF NOT EXISTS (SELECT 1 FROM #DatabaseHealth WHERE database_name = DB_NAME())
        INSERT INTO #DatabaseHealth (database_name, collection_error)
        VALUES (DB_NAME(), ERROR_MESSAGE());
    ELSE
        UPDATE #DatabaseHealth
        SET collection_error = ERROR_MESSAGE()
        WHERE database_name = DB_NAME();
END CATCH;
';

-------------------------------------------------------------------------------
-- Execute per-database collection
-------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    DECLARE @DbList NVARCHAR(MAX) = STUFF((
        SELECT N',' + database_name
        FROM #DbTargets
        ORDER BY database_name
        FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 1, N'');

    EXEC dbo.sp_DBA_ForEachDatabase
        @Command = @CollectCommand,
        @UserDatabasesOnly = 0,
        @IncludeReadOnly = 1,
        @DatabaseList = @DbList,
        @ContinueOnError = 1;
END
ELSE
BEGIN
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
            IF NOT EXISTS (SELECT 1 FROM #DatabaseHealth WHERE database_name = @db_name)
                INSERT INTO #DatabaseHealth (database_name, collection_error)
                VALUES (@db_name, ERROR_MESSAGE());
            ELSE
                UPDATE #DatabaseHealth
                SET collection_error = ERROR_MESSAGE()
                WHERE database_name = @db_name;
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @db_name;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;
END;

-------------------------------------------------------------------------------
-- Missing index counts (instance DMV)
-------------------------------------------------------------------------------
IF OBJECT_ID(N'tempdb..#MissingIndexCounts') IS NOT NULL DROP TABLE #MissingIndexCounts;
SELECT
    d.database_id,
    COUNT(*) AS missing_index_count
INTO #MissingIndexCounts
FROM sys.dm_db_missing_index_details AS d
INNER JOIN sys.dm_db_missing_index_groups AS g ON g.index_handle = d.index_handle
INNER JOIN sys.dm_db_missing_index_group_stats AS gs ON gs.group_handle = g.index_group_handle
INNER JOIN #DbTargets AS t ON t.database_id = d.database_id
GROUP BY d.database_id;

UPDATE h
SET missing_index_count = ISNULL(m.missing_index_count, 0)
FROM #DatabaseHealth AS h
INNER JOIN #DbTargets AS t ON t.database_name = h.database_name
LEFT JOIN #MissingIndexCounts AS m ON m.database_id = t.database_id;

-------------------------------------------------------------------------------
-- Consolidated summary view
-------------------------------------------------------------------------------
IF OBJECT_ID(N'tempdb..#HealthSummary') IS NOT NULL DROP TABLE #HealthSummary;

SELECT
    i.database_name                           AS [Database],
    i.size_gb                                 AS [Size_GB],
    i.data_size_gb                            AS [Data_Size_GB],
    i.log_size_gb                             AS [Log_Size_GB],
    h.user_tables                             AS [User_Tables],
    h.views_count                             AS [Views],
    h.procedures_count                        AS [Stored_Procedures],
    h.functions_count                         AS [Functions],
    h.index_count                             AS [Index_Count],
    h.approx_row_count                        AS [Approx_Row_Count],
    i.compatibility_level                     AS [Compatibility_Level],
    i.recovery_model                          AS [Recovery_Model],
    i.last_full_backup                        AS [Last_Full_Backup],
    i.last_log_backup                         AS [Last_Log_Backup],
    i.state_desc                              AS [State],
    h.total_indexes                           AS [Total_Indexes],
    h.fragmented_indexes                      AS [Fragmented_Indexes],
    h.highly_fragmented_indexes               AS [Highly_Fragmented_Indexes],
    h.fragmented_tables                       AS [Fragmented_Tables],
    h.avg_fragmentation_pct                   AS [Avg_Fragmentation_Pct],
    h.max_fragmentation_pct                   AS [Max_Fragmentation_Pct],
    h.largest_fragmented_index                AS [Largest_Fragmented_Index],
    h.largest_fragmented_table                AS [Largest_Fragmented_Table],
    h.total_statistics                        AS [Total_Statistics],
    h.outdated_statistics                     AS [Outdated_Statistics],
    h.outdated_statistics_pct                 AS [Outdated_Statistics_Pct],
    h.never_updated_statistics                AS [Never_Updated_Statistics],
    h.auto_created_statistics                 AS [Auto_Created_Statistics],
    h.user_created_statistics                 AS [User_Created_Statistics],
    h.auto_update_off_statistics              AS [Auto_Update_OFF_Statistics],
    h.norecompute_statistics                  AS [NORECOMPUTE_Statistics],
    h.last_stats_update                       AS [Last_Stats_Update],
    h.missing_index_count                     AS [Missing_Index_Count],
    h.duplicate_index_count                   AS [Duplicate_Index_Count],
    h.unused_index_count                      AS [Unused_Index_Count],
    h.disabled_index_count                    AS [Disabled_Index_Count],
    h.heap_tables                             AS [Heap_Tables],
    h.forwarded_records                       AS [Forwarded_Records],
    h.tables_without_pk                       AS [Tables_Without_PK],
    h.tables_without_clustered_index          AS [Tables_Without_Clustered_Index],
    CAST(
        100.0
        - CASE WHEN ISNULL(h.avg_fragmentation_pct, 0) * 0.8 > 35 THEN 35 ELSE ISNULL(h.avg_fragmentation_pct, 0) * 0.8 END
        - CASE WHEN ISNULL(h.outdated_statistics_pct, 0) * 1.2 > 25 THEN 25 ELSE ISNULL(h.outdated_statistics_pct, 0) * 1.2 END
        - CASE WHEN h.missing_index_count * 1.0 > 10 THEN 10 ELSE h.missing_index_count * 1.0 END
        - CASE WHEN h.duplicate_index_count * 2.0 > 8 THEN 8 ELSE h.duplicate_index_count * 2.0 END
        - CASE WHEN h.unused_index_count * 1.0 > 8 THEN 8 ELSE h.unused_index_count * 1.0 END
        - CASE WHEN i.last_full_backup IS NULL OR DATEDIFF(DAY, i.last_full_backup, GETDATE()) > 7 THEN 12 ELSE 0 END
        - CASE WHEN h.collection_error IS NOT NULL THEN 15 ELSE 0 END
    AS INT) AS [Health_Score],
    CASE
        WHEN h.collection_error IS NOT NULL THEN N'Collection Error'
        WHEN ISNULL(h.avg_fragmentation_pct, 0) > @FragCriticalPct
          OR ISNULL(h.outdated_statistics_pct, 0) > @StatsCriticalPct THEN N'Critical'
        WHEN ISNULL(h.avg_fragmentation_pct, 0) >= @FragWarningPct
          OR ISNULL(h.outdated_statistics_pct, 0) >= @StatsWarningPct THEN N'Warning'
        ELSE N'Healthy'
    END AS [Health_Status],
    CASE
        WHEN h.collection_error IS NOT NULL THEN N'Review collection error and re-run for this database'
        WHEN h.highly_fragmented_indexes > 0 THEN N'Rebuild indexes above ' + CAST(@FragCriticalPct AS NVARCHAR(10)) + N'% fragmentation'
        WHEN h.fragmented_indexes > 0 THEN N'Reorganize indexes between ' + CAST(@FragWarningPct AS NVARCHAR(10)) + N'% and ' + CAST(@FragCriticalPct AS NVARCHAR(10)) + N'%'
        WHEN h.outdated_statistics > 0 THEN N'Update statistics on flagged objects'
        WHEN h.forwarded_records > 1000 THEN N'Review heap tables with forwarded records'
        WHEN h.duplicate_index_count > 0 THEN N'Review duplicate indexes for consolidation'
        WHEN h.unused_index_count > 0 THEN N'Review unused indexes after confirming uptime since restart'
        ELSE N'No Action'
    END AS [Maintenance_Recommendation],
    h.collection_error                        AS [Collection_Error]
INTO #HealthSummary
FROM #DbInstanceInfo AS i
INNER JOIN #DatabaseHealth AS h ON h.database_name = i.database_name;

-------------------------------------------------------------------------------
-- Report output
-------------------------------------------------------------------------------
PRINT REPLICATE(N'=', 80);
PRINT N'Report 1: Database Health Summary';
PRINT REPLICATE(N'=', 80);

SELECT
    [Database],
    [Size_GB],
    [User_Tables],
    [Fragmented_Tables],
    [Fragmented_Indexes],
    [Avg_Fragmentation_Pct],
    [Outdated_Statistics],
    [Outdated_Statistics_Pct],
    [Last_Stats_Update],
    [Recovery_Model],
    [Compatibility_Level],
    [Health_Status],
    [Health_Score],
    [Maintenance_Recommendation]
FROM #HealthSummary
ORDER BY [Size_GB] DESC, [Database];

PRINT REPLICATE(N'=', 80);
PRINT N'Report 1b: Full Database Detail (all columns)';
PRINT REPLICATE(N'=', 80);

SELECT *
FROM #HealthSummary
ORDER BY [Size_GB] DESC, [Database];

PRINT REPLICATE(N'=', 80);
PRINT N'Report 2: Top ' + CAST(@TopN AS NVARCHAR(10)) + N' Largest Databases';
PRINT REPLICATE(N'=', 80);

SELECT TOP (@TopN)
    [Database],
    [Size_GB],
    [Data_Size_GB],
    [Log_Size_GB],
    [User_Tables],
    [Approx_Row_Count],
    [Health_Status],
    [Health_Score]
FROM #HealthSummary
ORDER BY [Size_GB] DESC;

PRINT REPLICATE(N'=', 80);
PRINT N'Report 3: Top Fragmented Tables';
PRINT REPLICATE(N'=', 80);

SELECT TOP (@TopN)
    database_name AS [Database],
    schema_name AS [Schema],
    table_name AS [Table],
    max_fragmentation AS [Max_Fragmentation_Pct],
    page_count AS [Page_Count],
    fragmented_indexes AS [Fragmented_Indexes]
FROM #FragTables
ORDER BY max_fragmentation DESC, page_count DESC;

PRINT REPLICATE(N'=', 80);
PRINT N'Report 4: Top Fragmented Indexes (>' + CAST(@FragCriticalPct AS NVARCHAR(10)) + N'%)';
PRINT REPLICATE(N'=', 80);

SELECT TOP (@TopN)
    database_name AS [Database],
    schema_name AS [Schema],
    table_name AS [Table],
    index_name AS [Index],
    fragmentation_pct AS [Fragmentation_Pct],
    page_count AS [Page_Count]
FROM #FragIndexes
ORDER BY fragmentation_pct DESC, page_count DESC;

PRINT REPLICATE(N'=', 80);
PRINT N'Report 5: Outdated Statistics (by modification counter)';
PRINT REPLICATE(N'=', 80);

SELECT TOP (@TopN)
    database_name AS [Database],
    schema_name AS [Schema],
    table_name AS [Table],
    statistics_name AS [Statistics],
    last_updated AS [Last_Updated],
    total_rows AS [Rows],
    modification_counter AS [Modification_Counter],
    modification_pct AS [Modification_Pct],
    auto_created AS [Auto_Created],
    no_recompute AS [NORECOMPUTE]
FROM #OutdatedStats
ORDER BY modification_counter DESC, modification_pct DESC;

PRINT REPLICATE(N'=', 80);
PRINT N'Report 6: Missing Indexes (instance DMV)';
PRINT REPLICATE(N'=', 80);

SELECT TOP (@TopN)
    CAST(gs.user_seeks * gs.avg_user_impact * gs.avg_total_user_cost AS BIGINT) AS [Improvement_Measure],
    DB_NAME(d.database_id) AS [Database],
    d.statement AS [Table_Path],
    d.equality_columns AS [Equality_Columns],
    d.inequality_columns AS [Inequality_Columns],
    d.included_columns AS [Included_Columns],
    gs.user_seeks AS [User_Seeks],
    CAST(gs.avg_user_impact AS DECIMAL(8, 2)) AS [Avg_User_Impact_Pct]
FROM sys.dm_db_missing_index_group_stats AS gs
INNER JOIN sys.dm_db_missing_index_groups AS g ON gs.group_handle = g.index_group_handle
INNER JOIN sys.dm_db_missing_index_details AS d ON g.index_handle = d.index_handle
INNER JOIN #DbTargets AS t ON t.database_id = d.database_id
ORDER BY [Improvement_Measure] DESC;

PRINT REPLICATE(N'=', 80);
PRINT N'Report 7: Duplicate Indexes';
PRINT REPLICATE(N'=', 80);

SELECT TOP (@TopN)
    database_name AS [Database],
    schema_name AS [Schema],
    table_name AS [Table],
    index_1 AS [Index_1],
    index_2 AS [Index_2],
    column_list AS [Key_Columns]
FROM #DuplicateIndexes
ORDER BY database_name, schema_name, table_name;

PRINT REPLICATE(N'=', 80);
PRINT N'Report 8: Unused Indexes';
PRINT REPLICATE(N'=', 80);

SELECT TOP (@TopN)
    database_name AS [Database],
    schema_name AS [Schema],
    table_name AS [Table],
    index_name AS [Index],
    writes AS [Writes],
    reads AS [Reads],
    size_mb AS [Size_MB]
FROM #UnusedIndexes
ORDER BY writes DESC, size_mb DESC;

PRINT REPLICATE(N'=', 80);
PRINT N'Report 9: Database Health Score';
PRINT REPLICATE(N'=', 80);

SELECT
    [Database],
    [Health_Score],
    [Health_Status],
    [Avg_Fragmentation_Pct],
    [Outdated_Statistics_Pct],
    [Missing_Index_Count],
    [Duplicate_Index_Count],
    [Unused_Index_Count],
    [Last_Full_Backup]
FROM #HealthSummary
ORDER BY [Health_Score] ASC, [Size_GB] DESC;

PRINT REPLICATE(N'=', 80);
PRINT N'Report 10: Maintenance Recommendations';
PRINT REPLICATE(N'=', 80);

SELECT
    [Database],
    [Health_Status],
    [Maintenance_Recommendation],
    [Highly_Fragmented_Indexes],
    [Fragmented_Indexes],
    [Outdated_Statistics],
    [Forwarded_Records],
    [Duplicate_Index_Count],
    [Unused_Index_Count]
FROM #HealthSummary
WHERE [Maintenance_Recommendation] <> N'No Action'
   OR [Health_Status] <> N'Healthy'
ORDER BY
    CASE [Health_Status] WHEN N'Critical' THEN 1 WHEN N'Warning' THEN 2 WHEN N'Collection Error' THEN 3 ELSE 4 END,
    [Size_GB] DESC;

PRINT REPLICATE(N'=', 80);
PRINT N'Assessment completed at ' + CONVERT(NVARCHAR(30), SYSDATETIME(), 120)
    + N' (elapsed ' + CAST(DATEDIFF(SECOND, @ReportStart, SYSDATETIME()) AS NVARCHAR(20)) + N' seconds)';
PRINT REPLICATE(N'=', 80);

DROP TABLE #DbTargets;
DROP TABLE #DbInstanceInfo;
DROP TABLE #DatabaseHealth;
DROP TABLE #FragTables;
DROP TABLE #FragIndexes;
DROP TABLE #OutdatedStats;
DROP TABLE #DuplicateIndexes;
DROP TABLE #UnusedIndexes;
DROP TABLE #MissingIndexCounts;
DROP TABLE #HealthSummary;
