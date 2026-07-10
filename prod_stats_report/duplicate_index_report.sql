/*
================================================================================
Duplicate & Redundant Index Analyzer (Production)
================================================================================
Description:
    Detects wasteful index pairs across online user databases:
      - Exact duplicates (identical keys, includes, filter)
      - Left-prefix redundant indexes
      - Overlapping indexes (one key set covers another with same includes)
      - Unused duplicate pairs (zero reads since instance restart)
      - Duplicate filtered / unique index pairs

    Compares key columns, sort direction, included columns, and filter
    definitions — not index names alone.

    Excludes XML, spatial, full-text, columnstore, and memory-optimized indexes.

Output:
    Database, schema, table, index pair, signatures, physical attributes,
    last access times, total reads/writes, duplicate type, recommendation.

Note:
    SQL Server does not store index creation timestamps in catalog views or
    DMVs. CreatedDate is intentionally omitted.

Action:
    Review recommendations before dropping indexes. Prefer keeping PK/unique
    constraints. Confirm uptime since restart before acting on usage stats.

Parameters:
    @DatabaseList       - comma-separated names or NULL for all user DBs
    @IncludeReadOnly    - include read-only databases
    @TopN               - max rows returned (NULL = all)

Prerequisites: SQL Server 2016+ (STRING_SPLIT)
Criticality: Medium (read-only, metadata/DMV only)
Author:        Ravi Sharma
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-------------------------------------------------------------------------------
-- Parameters
-------------------------------------------------------------------------------
DECLARE @DatabaseList       NVARCHAR(MAX) = NULL;
DECLARE @IncludeReadOnly    BIT = 0;
DECLARE @TopN               INT = NULL;

DECLARE @ReportStart        DATETIME2(0) = SYSDATETIME();

SELECT
    osi.sqlserver_start_time AS [Instance_Start_Time],
    N'Index usage stats are cumulative since instance start.' AS [Metric_Context]
FROM sys.dm_os_sys_info AS osi;

-------------------------------------------------------------------------------
-- Target database list (WHILE loop driver — no cursors)
-------------------------------------------------------------------------------
IF OBJECT_ID(N'tempdb..#DbWork') IS NOT NULL DROP TABLE #DbWork;
CREATE TABLE #DbWork (
    row_id          INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
    database_id     INT NOT NULL,
    database_name   SYSNAME NOT NULL
);

IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
BEGIN
    INSERT INTO #DbWork (database_id, database_name)
    SELECT d.database_id, d.name
    FROM sys.databases AS d
    INNER JOIN (
        SELECT LTRIM(RTRIM(value)) AS database_name
        FROM STRING_SPLIT(@DatabaseList, N',')
        WHERE LTRIM(RTRIM(value)) <> N''
    ) AS req ON req.database_name = d.name
    WHERE d.state = 0
      AND d.is_in_standby = 0
      AND d.database_id > 4;
END
ELSE
BEGIN
    INSERT INTO #DbWork (database_id, database_name)
    SELECT d.database_id, d.name
    FROM sys.databases AS d
    WHERE d.state = 0
      AND d.is_in_standby = 0
      AND d.database_id > 4
      AND (@IncludeReadOnly = 1 OR d.is_read_only = 0);
END;

IF OBJECT_ID(N'tempdb..#DuplicateIndexes') IS NOT NULL DROP TABLE #DuplicateIndexes;
CREATE TABLE #DuplicateIndexes (
    database_name               SYSNAME NOT NULL,
    schema_name                 SYSNAME NOT NULL,
    table_name                  SYSNAME NOT NULL,
    duplicate_index_1           SYSNAME NOT NULL,
    duplicate_index_2           SYSNAME NOT NULL,
    duplicate_type              NVARCHAR(60) NOT NULL,
    key_columns                 NVARCHAR(MAX) NOT NULL,
    sort_direction              NVARCHAR(MAX) NULL,
    included_columns            NVARCHAR(MAX) NULL,
    filter_definition           NVARCHAR(MAX) NULL,
    fill_factor_1               TINYINT NULL,
    fill_factor_2               TINYINT NULL,
    compression_1               NVARCHAR(60) NULL,
    compression_2               NVARCHAR(60) NULL,
    is_unique_1                 BIT NOT NULL,
    is_unique_2                 BIT NOT NULL,
    is_primary_key_1            BIT NOT NULL,
    is_primary_key_2            BIT NOT NULL,
    is_disabled_1               BIT NOT NULL,
    is_disabled_2               BIT NOT NULL,
    last_user_seek_1            DATETIME NULL,
    last_user_scan_1            DATETIME NULL,
    last_user_lookup_1          DATETIME NULL,
    last_user_update_1          DATETIME NULL,
    last_user_read_1            DATETIME NULL,
    last_user_seek_2            DATETIME NULL,
    last_user_scan_2            DATETIME NULL,
    last_user_lookup_2          DATETIME NULL,
    last_user_update_2          DATETIME NULL,
    last_user_read_2            DATETIME NULL,
    total_reads_1               BIGINT NOT NULL,
    total_writes_1              BIGINT NOT NULL,
    total_reads_2               BIGINT NOT NULL,
    total_writes_2              BIGINT NOT NULL,
    recommendation              NVARCHAR(200) NOT NULL
);

IF OBJECT_ID(N'tempdb..#CollectionErrors') IS NOT NULL DROP TABLE #CollectionErrors;
CREATE TABLE #CollectionErrors (
    database_name   SYSNAME NOT NULL,
    error_message   NVARCHAR(4000) NOT NULL,
    error_time      DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

DECLARE @CollectSql NVARCHAR(MAX) = N'
INSERT INTO #DuplicateIndexes (
    database_name, schema_name, table_name,
    duplicate_index_1, duplicate_index_2, duplicate_type,
    key_columns, sort_direction, included_columns, filter_definition,
    fill_factor_1, fill_factor_2, compression_1, compression_2,
    is_unique_1, is_unique_2, is_primary_key_1, is_primary_key_2,
    is_disabled_1, is_disabled_2,
    last_user_seek_1, last_user_scan_1, last_user_lookup_1, last_user_update_1, last_user_read_1,
    last_user_seek_2, last_user_scan_2, last_user_lookup_2, last_user_update_2, last_user_read_2,
    total_reads_1, total_writes_1, total_reads_2, total_writes_2,
    recommendation
)
SELECT
    DB_NAME(),
    pairs.schema_name,
    pairs.table_name,
    pairs.index_name_1,
    pairs.index_name_2,
    pairs.duplicate_type,
    pairs.key_columns_1,
    pairs.sort_direction_1,
    pairs.include_columns_1,
    pairs.filter_definition_1,
    pairs.fill_factor_1,
    pairs.fill_factor_2,
    pairs.compression_1,
    pairs.compression_2,
    pairs.is_unique_1,
    pairs.is_unique_2,
    pairs.is_primary_key_1,
    pairs.is_primary_key_2,
    pairs.is_disabled_1,
    pairs.is_disabled_2,
    pairs.last_user_seek_1,
    pairs.last_user_scan_1,
    pairs.last_user_lookup_1,
    pairs.last_user_update_1,
    pairs.last_user_read_1,
    pairs.last_user_seek_2,
    pairs.last_user_scan_2,
    pairs.last_user_lookup_2,
    pairs.last_user_update_2,
    pairs.last_user_read_2,
    pairs.total_reads_1,
    pairs.total_writes_1,
    pairs.total_reads_2,
    pairs.total_writes_2,
    pairs.recommendation
FROM (
    SELECT
        a.schema_name,
        a.table_name,
        a.index_name AS index_name_1,
        b.index_name AS index_name_2,
        CASE
            WHEN a.key_signature = b.key_signature
                 AND ISNULL(a.include_signature, N'''') = ISNULL(b.include_signature, N'''')
                 AND ISNULL(a.filter_signature, N'''') = ISNULL(b.filter_signature, N'''')
                THEN N''Exact Duplicate''
            WHEN a.key_signature = b.key_signature
                 AND ISNULL(a.include_signature, N'''') = ISNULL(b.include_signature, N'''')
                 AND ISNULL(a.filter_signature, N'''') <> ISNULL(b.filter_signature, N'''')
                THEN N''Duplicate Filtered Index''
            WHEN a.key_signature = b.key_signature
                 AND ISNULL(a.filter_signature, N'''') = ISNULL(b.filter_signature, N'''')
                 AND a.is_unique = 1 AND b.is_unique = 1
                THEN N''Duplicate Unique Index''
            WHEN a.key_signature LIKE b.key_signature + N'',%''
                 AND ISNULL(a.filter_signature, N'''') = ISNULL(b.filter_signature, N'''')
                 AND ISNULL(a.include_signature, N'''') = ISNULL(b.include_signature, N'''')
                THEN N''Left-Prefix Redundant''
            WHEN b.key_signature LIKE a.key_signature + N'',%''
                 AND ISNULL(a.filter_signature, N'''') = ISNULL(b.filter_signature, N'''')
                 AND ISNULL(a.include_signature, N'''') = ISNULL(b.include_signature, N'''')
                THEN N''Left-Prefix Redundant''
            WHEN (
                    a.key_signature LIKE b.key_signature + N'',%''
                 OR b.key_signature LIKE a.key_signature + N'',%''
                 )
                 AND ISNULL(a.filter_signature, N'''') = ISNULL(b.filter_signature, N'''')
                 AND (
                        ISNULL(a.include_signature, N'''') = ISNULL(b.include_signature, N'''')
                     OR ISNULL(a.include_signature, N'''') LIKE ISNULL(b.include_signature, N'''') + N''%,%''
                     OR ISNULL(b.include_signature, N'''') LIKE ISNULL(a.include_signature, N'''') + N''%,%''
                     OR ISNULL(a.include_signature, N'''') = N''''
                     OR ISNULL(b.include_signature, N'''') = N''''
                 )
                THEN N''Overlapping Redundant''
            ELSE NULL
        END AS duplicate_type,
        a.key_columns AS key_columns_1,
        a.sort_direction AS sort_direction_1,
        a.include_columns AS include_columns_1,
        a.filter_definition AS filter_definition_1,
        a.fill_factor AS fill_factor_1,
        b.fill_factor AS fill_factor_2,
        a.compression_desc AS compression_1,
        b.compression_desc AS compression_2,
        a.is_unique AS is_unique_1,
        b.is_unique AS is_unique_2,
        a.is_primary_key AS is_primary_key_1,
        b.is_primary_key AS is_primary_key_2,
        a.is_disabled AS is_disabled_1,
        b.is_disabled AS is_disabled_2,
        a.last_user_seek AS last_user_seek_1,
        a.last_user_scan AS last_user_scan_1,
        a.last_user_lookup AS last_user_lookup_1,
        a.last_user_update AS last_user_update_1,
        a.last_user_read AS last_user_read_1,
        b.last_user_seek AS last_user_seek_2,
        b.last_user_scan AS last_user_scan_2,
        b.last_user_lookup AS last_user_lookup_2,
        b.last_user_update AS last_user_update_2,
        b.last_user_read AS last_user_read_2,
        a.total_reads AS total_reads_1,
        a.total_writes AS total_writes_1,
        b.total_reads AS total_reads_2,
        b.total_writes AS total_writes_2,
        CASE
            WHEN a.is_primary_key = 1 OR b.is_primary_key = 1 THEN N''Keep - involves primary key; review manually''
            WHEN a.is_disabled = 1 AND b.is_disabled = 0 THEN N''Drop Candidate: '' + a.index_name
            WHEN b.is_disabled = 1 AND a.is_disabled = 0 THEN N''Drop Candidate: '' + b.index_name
            WHEN a.total_reads = 0 AND b.total_reads = 0 THEN N''Drop Candidate - both unused since restart; keep narrower or PK/unique''
            WHEN a.total_reads < b.total_reads AND a.is_primary_key = 0 AND a.is_unique = 0 THEN N''Drop Candidate: '' + a.index_name
            WHEN b.total_reads < a.total_reads AND b.is_primary_key = 0 AND b.is_unique = 0 THEN N''Drop Candidate: '' + b.index_name
            WHEN a.total_reads = b.total_reads AND a.total_writes <= b.total_writes THEN N''Review: '' + a.index_name
            WHEN a.total_reads = b.total_reads AND b.total_writes < a.total_writes THEN N''Review: '' + b.index_name
            ELSE N''Review - similar usage; validate in workload''
        END AS recommendation
    FROM (
        SELECT
            i.object_id,
            i.index_id,
            i.name AS index_name,
            s.name AS schema_name,
            t.name AS table_name,
            i.is_unique,
            i.is_primary_key,
            i.is_disabled,
            i.fill_factor,
            i.filter_definition,
            p.data_compression_desc AS compression_desc,
            STUFF((
                SELECT N'', '' + c.name
                FROM sys.index_columns AS ic
                INNER JOIN sys.columns AS c
                    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id = i.index_id
                  AND ic.is_included_column = 0
                ORDER BY ic.key_ordinal
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS key_columns,
            STUFF((
                SELECT N'', '' + c.name + CASE WHEN ic.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END
                FROM sys.index_columns AS ic
                INNER JOIN sys.columns AS c
                    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id = i.index_id
                  AND ic.is_included_column = 0
                ORDER BY ic.key_ordinal
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS sort_direction,
            STUFF((
                SELECT N'', '' + c.name
                FROM sys.index_columns AS ic
                INNER JOIN sys.columns AS c
                    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id = i.index_id
                  AND ic.is_included_column = 1
                ORDER BY c.name
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS include_columns,
            STUFF((
                SELECT N'', '' + c.name + CASE WHEN ic.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END
                FROM sys.index_columns AS ic
                INNER JOIN sys.columns AS c
                    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id = i.index_id
                  AND ic.is_included_column = 0
                ORDER BY ic.key_ordinal
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS key_signature,
            STUFF((
                SELECT N'', '' + c.name
                FROM sys.index_columns AS ic
                INNER JOIN sys.columns AS c
                    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id = i.index_id
                  AND ic.is_included_column = 1
                ORDER BY c.name
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS include_signature,
            ISNULL(i.filter_definition, N'''') AS filter_signature,
            us.last_user_seek,
            us.last_user_scan,
            us.last_user_lookup,
            us.last_user_update,
            (
                SELECT MAX(v.dt)
                FROM (VALUES
                    (us.last_user_seek),
                    (us.last_user_scan),
                    (us.last_user_lookup)
                ) AS v(dt)
            ) AS last_user_read,
            ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) AS total_reads,
            ISNULL(us.user_updates, 0) AS total_writes
        FROM sys.indexes AS i
        INNER JOIN sys.tables AS t
            ON t.object_id = i.object_id
        INNER JOIN sys.schemas AS s
            ON s.schema_id = t.schema_id
        INNER JOIN sys.partitions AS p
            ON p.object_id = i.object_id AND p.index_id = i.index_id
        LEFT JOIN sys.dm_db_index_usage_stats AS us
            ON us.database_id = DB_ID()
           AND us.object_id = i.object_id
           AND us.index_id = i.index_id
        WHERE t.is_ms_shipped = 0
          AND t.is_memory_optimized = 0
          AND i.type IN (1, 2)
          AND i.index_id > 0
    ) AS a
    INNER JOIN (
        SELECT
            i.object_id,
            i.index_id,
            i.name AS index_name,
            s.name AS schema_name,
            t.name AS table_name,
            i.is_unique,
            i.is_primary_key,
            i.is_disabled,
            i.fill_factor,
            i.filter_definition,
            p.data_compression_desc AS compression_desc,
            STUFF((
                SELECT N'', '' + c.name
                FROM sys.index_columns AS ic
                INNER JOIN sys.columns AS c
                    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id = i.index_id
                  AND ic.is_included_column = 0
                ORDER BY ic.key_ordinal
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS key_columns,
            STUFF((
                SELECT N'', '' + c.name + CASE WHEN ic.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END
                FROM sys.index_columns AS ic
                INNER JOIN sys.columns AS c
                    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id = i.index_id
                  AND ic.is_included_column = 0
                ORDER BY ic.key_ordinal
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS sort_direction,
            STUFF((
                SELECT N'', '' + c.name
                FROM sys.index_columns AS ic
                INNER JOIN sys.columns AS c
                    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id = i.index_id
                  AND ic.is_included_column = 1
                ORDER BY c.name
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS include_columns,
            STUFF((
                SELECT N'', '' + c.name + CASE WHEN ic.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END
                FROM sys.index_columns AS ic
                INNER JOIN sys.columns AS c
                    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id = i.index_id
                  AND ic.is_included_column = 0
                ORDER BY ic.key_ordinal
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS key_signature,
            STUFF((
                SELECT N'', '' + c.name
                FROM sys.index_columns AS ic
                INNER JOIN sys.columns AS c
                    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                WHERE ic.object_id = i.object_id
                  AND ic.index_id = i.index_id
                  AND ic.is_included_column = 1
                ORDER BY c.name
                FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS include_signature,
            ISNULL(i.filter_definition, N'''') AS filter_signature,
            us.last_user_seek,
            us.last_user_scan,
            us.last_user_lookup,
            us.last_user_update,
            (
                SELECT MAX(v.dt)
                FROM (VALUES
                    (us.last_user_seek),
                    (us.last_user_scan),
                    (us.last_user_lookup)
                ) AS v(dt)
            ) AS last_user_read,
            ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) AS total_reads,
            ISNULL(us.user_updates, 0) AS total_writes
        FROM sys.indexes AS i
        INNER JOIN sys.tables AS t
            ON t.object_id = i.object_id
        INNER JOIN sys.schemas AS s
            ON s.schema_id = t.schema_id
        INNER JOIN sys.partitions AS p
            ON p.object_id = i.object_id AND p.index_id = i.index_id
        LEFT JOIN sys.dm_db_index_usage_stats AS us
            ON us.database_id = DB_ID()
           AND us.object_id = i.object_id
           AND us.index_id = i.index_id
        WHERE t.is_ms_shipped = 0
          AND t.is_memory_optimized = 0
          AND i.type IN (1, 2)
          AND i.index_id > 0
    ) AS b
        ON a.object_id = b.object_id
       AND a.index_id < b.index_id
    WHERE
        (
            a.key_signature = b.key_signature
            AND ISNULL(a.include_signature, N'''') = ISNULL(b.include_signature, N'''')
        )
        OR (
            a.key_signature = b.key_signature
            AND ISNULL(a.filter_signature, N'''') <> ISNULL(b.filter_signature, N'''')
        )
        OR (
            a.key_signature LIKE b.key_signature + N'',%''
            AND ISNULL(a.filter_signature, N'''') = ISNULL(b.filter_signature, N'''')
        )
        OR (
            b.key_signature LIKE a.key_signature + N'',%''
            AND ISNULL(a.filter_signature, N'''') = ISNULL(b.filter_signature, N'''')
        )
) AS pairs
WHERE pairs.duplicate_type IS NOT NULL
  AND NOT (
        pairs.duplicate_type = N''Exact Duplicate''
        AND pairs.total_reads_1 = 0
        AND pairs.total_reads_2 = 0
      )
UNION ALL
SELECT
    DB_NAME(),
    unused.schema_name,
    unused.table_name,
    unused.index_name_1,
    unused.index_name_2,
    N''Unused Duplicate Pair'',
    unused.key_columns_1,
    unused.sort_direction_1,
    unused.include_columns_1,
    unused.filter_definition_1,
    unused.fill_factor_1,
    unused.fill_factor_2,
    unused.compression_1,
    unused.compression_2,
    unused.is_unique_1,
    unused.is_unique_2,
    unused.is_primary_key_1,
    unused.is_primary_key_2,
    unused.is_disabled_1,
    unused.is_disabled_2,
    unused.last_user_seek_1,
    unused.last_user_scan_1,
    unused.last_user_lookup_1,
    unused.last_user_update_1,
    unused.last_user_read_1,
    unused.last_user_seek_2,
    unused.last_user_scan_2,
    unused.last_user_lookup_2,
    unused.last_user_update_2,
    unused.last_user_read_2,
    unused.total_reads_1,
    unused.total_writes_1,
    unused.total_reads_2,
    unused.total_writes_2,
    N''Drop Candidate - exact duplicate pair unused since restart''
FROM (
    SELECT
        a.schema_name,
        a.table_name,
        a.index_name AS index_name_1,
        b.index_name AS index_name_2,
        a.key_columns AS key_columns_1,
        a.sort_direction AS sort_direction_1,
        a.include_columns AS include_columns_1,
        a.filter_definition AS filter_definition_1,
        a.fill_factor AS fill_factor_1,
        b.fill_factor AS fill_factor_2,
        a.compression_desc AS compression_1,
        b.compression_desc AS compression_2,
        a.is_unique AS is_unique_1,
        b.is_unique AS is_unique_2,
        a.is_primary_key AS is_primary_key_1,
        b.is_primary_key AS is_primary_key_2,
        a.is_disabled AS is_disabled_1,
        b.is_disabled AS is_disabled_2,
        a.last_user_seek AS last_user_seek_1,
        a.last_user_scan AS last_user_scan_1,
        a.last_user_lookup AS last_user_lookup_1,
        a.last_user_update AS last_user_update_1,
        a.last_user_read AS last_user_read_1,
        b.last_user_seek AS last_user_seek_2,
        b.last_user_scan AS last_user_scan_2,
        b.last_user_lookup AS last_user_lookup_2,
        b.last_user_update AS last_user_update_2,
        b.last_user_read AS last_user_read_2,
        a.total_reads AS total_reads_1,
        a.total_writes AS total_writes_1,
        b.total_reads AS total_reads_2,
        b.total_writes AS total_writes_2
    FROM (
        SELECT
            i.object_id, i.index_id, i.name AS index_name, s.name AS schema_name, t.name AS table_name,
            i.is_unique, i.is_primary_key, i.is_disabled, i.fill_factor, i.filter_definition,
            p.data_compression_desc AS compression_desc,
            STUFF((SELECT N'', '' + c.name FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                   WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0 ORDER BY ic.key_ordinal
                   FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS key_columns,
            STUFF((SELECT N'', '' + c.name + CASE WHEN ic.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END
                   FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                   WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0 ORDER BY ic.key_ordinal
                   FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS sort_direction,
            STUFF((SELECT N'', '' + c.name FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                   WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1 ORDER BY c.name
                   FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS include_columns,
            STUFF((SELECT N'', '' + c.name + CASE WHEN ic.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END
                   FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                   WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0 ORDER BY ic.key_ordinal
                   FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS key_signature,
            STUFF((SELECT N'', '' + c.name FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                   WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1 ORDER BY c.name
                   FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS include_signature,
            ISNULL(i.filter_definition, N'''') AS filter_signature,
            us.last_user_seek, us.last_user_scan, us.last_user_lookup, us.last_user_update,
            (SELECT MAX(v.dt) FROM (VALUES (us.last_user_seek), (us.last_user_scan), (us.last_user_lookup)) v(dt)) AS last_user_read,
            ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) AS total_reads,
            ISNULL(us.user_updates, 0) AS total_writes
        FROM sys.indexes i
        JOIN sys.tables t ON t.object_id = i.object_id
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        JOIN sys.partitions p ON p.object_id = i.object_id AND p.index_id = i.index_id
        LEFT JOIN sys.dm_db_index_usage_stats us ON us.database_id = DB_ID() AND us.object_id = i.object_id AND us.index_id = i.index_id
        WHERE t.is_ms_shipped = 0 AND t.is_memory_optimized = 0 AND i.type IN (1, 2) AND i.index_id > 0
    ) a
    INNER JOIN (
        SELECT
            i.object_id, i.index_id, i.name AS index_name,
            STUFF((SELECT N'', '' + c.name + CASE WHEN ic.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END
                   FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                   WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0 ORDER BY ic.key_ordinal
                   FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS key_signature,
            STUFF((SELECT N'', '' + c.name FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                   WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1 ORDER BY c.name
                   FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS include_signature,
            ISNULL(i.filter_definition, N'''') AS filter_signature,
            i.is_unique, i.is_primary_key, i.is_disabled, i.fill_factor, i.filter_definition, p.data_compression_desc AS compression_desc,
            us.last_user_seek, us.last_user_scan, us.last_user_lookup, us.last_user_update,
            (SELECT MAX(v.dt) FROM (VALUES (us.last_user_seek), (us.last_user_scan), (us.last_user_lookup)) v(dt)) AS last_user_read,
            ISNULL(us.user_seeks, 0) + ISNULL(us.user_scans, 0) + ISNULL(us.user_lookups, 0) AS total_reads,
            ISNULL(us.user_updates, 0) AS total_writes
        FROM sys.indexes i
        JOIN sys.tables t ON t.object_id = i.object_id
        JOIN sys.partitions p ON p.object_id = i.object_id AND p.index_id = i.index_id
        LEFT JOIN sys.dm_db_index_usage_stats us ON us.database_id = DB_ID() AND us.object_id = i.object_id AND us.index_id = i.index_id
        WHERE t.is_ms_shipped = 0 AND t.is_memory_optimized = 0 AND i.type IN (1, 2) AND i.index_id > 0
    ) b ON a.object_id = b.object_id AND a.index_id < b.index_id
    WHERE a.key_signature = b.key_signature
      AND ISNULL(a.include_signature, N'''') = ISNULL(b.include_signature, N'''')
      AND ISNULL(a.filter_signature, N'''') = ISNULL(b.filter_signature, N'''')
      AND a.total_reads = 0
      AND b.total_reads = 0
) AS unused;
';

DECLARE @RowId      INT = 1;
DECLARE @MaxRow     INT = (SELECT ISNULL(MAX(row_id), 0) FROM #DbWork);
DECLARE @DbName     SYSNAME;
DECLARE @SQL        NVARCHAR(MAX);

WHILE @RowId <= @MaxRow
BEGIN
    SELECT @DbName = database_name FROM #DbWork WHERE row_id = @RowId;

    BEGIN TRY
        SET @SQL = N'USE ' + QUOTENAME(@DbName) + N';' + @CollectSql;
        EXEC sys.sp_executesql @SQL;
    END TRY
    BEGIN CATCH
        INSERT INTO #CollectionErrors (database_name, error_message)
        VALUES (@DbName, ERROR_MESSAGE());
    END CATCH;

    SET @RowId += 1;
END;

-------------------------------------------------------------------------------
-- Report
-------------------------------------------------------------------------------
PRINT REPLICATE(N'=', 80);
PRINT N'Duplicate & Redundant Index Report';
PRINT REPLICATE(N'=', 80);

IF EXISTS (SELECT 1 FROM #CollectionErrors)
BEGIN
    PRINT N'--- Collection Errors ---';
    SELECT database_name AS [Database], error_message AS [Error], error_time AS [Error_Time]
    FROM #CollectionErrors
    ORDER BY database_name;
END;

IF @TopN IS NULL
BEGIN
    SELECT
        database_name           AS [Database],
        schema_name             AS [Schema],
        table_name              AS [Table],
        duplicate_type          AS [Duplicate_Type],
        duplicate_index_1       AS [Duplicate_Index_1],
        duplicate_index_2       AS [Duplicate_Index_2],
        key_columns             AS [Key_Columns],
        sort_direction          AS [Sort_Direction],
        included_columns        AS [Included_Columns],
        filter_definition       AS [Filter_Definition],
        fill_factor_1           AS [Fill_Factor_1],
        fill_factor_2           AS [Fill_Factor_2],
        compression_1           AS [Compression_1],
        compression_2           AS [Compression_2],
        is_unique_1             AS [Unique_1],
        is_unique_2             AS [Unique_2],
        is_primary_key_1        AS [Primary_Key_1],
        is_primary_key_2        AS [Primary_Key_2],
        is_disabled_1           AS [Disabled_1],
        is_disabled_2           AS [Disabled_2],
        last_user_seek_1        AS [Last_User_Seek_1],
        last_user_scan_1        AS [Last_User_Scan_1],
        last_user_lookup_1      AS [Last_User_Lookup_1],
        last_user_update_1      AS [Last_User_Update_1],
        last_user_read_1        AS [Last_User_Read_1],
        last_user_seek_2        AS [Last_User_Seek_2],
        last_user_scan_2        AS [Last_User_Scan_2],
        last_user_lookup_2      AS [Last_User_Lookup_2],
        last_user_update_2      AS [Last_User_Update_2],
        last_user_read_2        AS [Last_User_Read_2],
        total_reads_1           AS [Total_Reads_1],
        total_writes_1          AS [Total_Writes_1],
        total_reads_2           AS [Total_Reads_2],
        total_writes_2          AS [Total_Writes_2],
        recommendation          AS [Recommendation]
    FROM #DuplicateIndexes
    ORDER BY
        CASE duplicate_type
            WHEN N'Exact Duplicate' THEN 1
            WHEN N'Unused Duplicate Pair' THEN 2
            WHEN N'Left-Prefix Redundant' THEN 3
            WHEN N'Overlapping Redundant' THEN 4
            WHEN N'Duplicate Filtered Index' THEN 5
            WHEN N'Duplicate Unique Index' THEN 6
            ELSE 7
        END,
        database_name,
        schema_name,
        table_name;
END
ELSE
BEGIN
    SELECT TOP (@TopN)
        database_name           AS [Database],
        schema_name             AS [Schema],
        table_name              AS [Table],
        duplicate_type          AS [Duplicate_Type],
        duplicate_index_1       AS [Duplicate_Index_1],
        duplicate_index_2       AS [Duplicate_Index_2],
        key_columns             AS [Key_Columns],
        sort_direction          AS [Sort_Direction],
        included_columns        AS [Included_Columns],
        filter_definition       AS [Filter_Definition],
        fill_factor_1           AS [Fill_Factor_1],
        fill_factor_2           AS [Fill_Factor_2],
        compression_1           AS [Compression_1],
        compression_2           AS [Compression_2],
        is_unique_1             AS [Unique_1],
        is_unique_2             AS [Unique_2],
        is_primary_key_1        AS [Primary_Key_1],
        is_primary_key_2        AS [Primary_Key_2],
        is_disabled_1           AS [Disabled_1],
        is_disabled_2           AS [Disabled_2],
        last_user_seek_1        AS [Last_User_Seek_1],
        last_user_scan_1        AS [Last_User_Scan_1],
        last_user_lookup_1      AS [Last_User_Lookup_1],
        last_user_update_1      AS [Last_User_Update_1],
        last_user_read_1        AS [Last_User_Read_1],
        last_user_seek_2        AS [Last_User_Seek_2],
        last_user_scan_2        AS [Last_User_Scan_2],
        last_user_lookup_2      AS [Last_User_Lookup_2],
        last_user_update_2      AS [Last_User_Update_2],
        last_user_read_2        AS [Last_User_Read_2],
        total_reads_1           AS [Total_Reads_1],
        total_writes_1          AS [Total_Writes_1],
        total_reads_2           AS [Total_Reads_2],
        total_writes_2          AS [Total_Writes_2],
        recommendation          AS [Recommendation]
    FROM #DuplicateIndexes
    ORDER BY
        CASE duplicate_type
            WHEN N'Exact Duplicate' THEN 1
            WHEN N'Unused Duplicate Pair' THEN 2
            WHEN N'Left-Prefix Redundant' THEN 3
            WHEN N'Overlapping Redundant' THEN 4
            WHEN N'Duplicate Filtered Index' THEN 5
            WHEN N'Duplicate Unique Index' THEN 6
            ELSE 7
        END,
        database_name,
        schema_name,
        table_name;
END;

PRINT REPLICATE(N'=', 80);
DECLARE @RowCount INT = (SELECT COUNT(*) FROM #DuplicateIndexes);
PRINT N'Rows returned: ' + CAST(@RowCount AS NVARCHAR(20))
    + N' | Elapsed seconds: ' + CAST(DATEDIFF(SECOND, @ReportStart, SYSDATETIME()) AS NVARCHAR(20));
PRINT REPLICATE(N'=', 80);

DROP TABLE #DbWork;
DROP TABLE #DuplicateIndexes;
DROP TABLE #CollectionErrors;
