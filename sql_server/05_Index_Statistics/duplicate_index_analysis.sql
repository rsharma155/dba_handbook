/*
================================================================================
Duplicate Index Analysis — Production Diagnostic
================================================================================
Description:
    Identifies wasteful and overlapping indexes across one or all user databases.
    Detects exact duplicates, same-key overlaps, and redundant left-prefix
    indexes where a narrower key list is subsumed by a wider one.

Output:
    (1) Duplicate index pairs with usage, size, and keep/drop guidance.
    (2) Summary counts by database and duplicate type.
    (3) Collection diagnostics (databases scanned, indexes evaluated).

Action:
    Review EXACT_DUPLICATE first — drop the candidate with lower reads or higher
    writes after change-window approval. For DUPLICATE_KEY and
    REDUNDANT_LEFT_PREFIX, validate execution plans and constraint coverage before
    dropping. Never drop PK/unique-constraint indexes without schema review.
    Index usage stats reset on instance restart.

Parameters (local variables — edit before execution):
    @DatabaseList       Comma-separated database names, or NULL for all online
                        user databases (excludes master, model, msdb, tempdb).
    @IncludeReadOnly    1 = include read-only databases when @DatabaseList is NULL.
    @MinPageCount       Minimum index size (pages) to include; default 0.
    @ShowDiagnostics    1 = print per-database collection stats and errors.

Prerequisites: SQL Server 2019+ (STRING_AGG, STRING_SPLIT)

Criticality: Medium (read-only; generates DROP suggestions for review only)
Author:        Ravi Sharma
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

IF CAST(SERVERPROPERTY(N'ProductMajorVersion') AS INT) < 15
BEGIN
    RAISERROR(N'duplicate_index_analysis.sql requires SQL Server 2019 or higher.', 16, 1);
    RETURN;
END;

/*------------------------------------------------------------------------------
  User configuration
------------------------------------------------------------------------------*/
DECLARE @DatabaseList    NVARCHAR(MAX) = N'userdb';   -- e.g. N'userdb' or NULL = all user DBs
DECLARE @IncludeReadOnly BIT            = 0;
DECLARE @MinPageCount    INT            = 0;
DECLARE @ShowDiagnostics BIT            = 1;

-- Big-table index consolidation section
DECLARE @BigTableTopN      INT           = 20;     -- top N largest tables per database to analyze
DECLARE @BigTableMinRows   BIGINT        = 100000; -- a table is "big" at/above this row count ...
DECLARE @BigTableMinSizeMB DECIMAL(18,2) = 100.0;  -- ... or at/above this reserved size in MB

-- ONLINE rebuild is available on Enterprise (3), Azure SQL DB (5), Azure MI (8), and Developer (reports 3)
DECLARE @OnlineClause NVARCHAR(50) =
    CASE WHEN CAST(SERVERPROPERTY(N'EngineEdition') AS INT) IN (3, 5, 8)
         THEN N', ONLINE = ON' ELSE N'' END;

/*------------------------------------------------------------------------------
  Staging
------------------------------------------------------------------------------*/
IF OBJECT_ID(N'tempdb..#DuplicateIndexes') IS NOT NULL
    DROP TABLE #DuplicateIndexes;

CREATE TABLE #DuplicateIndexes
(
    database_name           SYSNAME        NOT NULL,
    schema_name             SYSNAME        NOT NULL,
    table_name              SYSNAME        NOT NULL,
    duplicate_type          NVARCHAR(40)   NOT NULL,
    index_keep              SYSNAME        NOT NULL,
    index_drop_candidate    SYSNAME        NOT NULL,
    key_columns             NVARCHAR(MAX)  NULL,
    included_columns_keep   NVARCHAR(MAX)  NULL,
    included_columns_drop   NVARCHAR(MAX)  NULL,
    filter_definition       NVARCHAR(MAX)  NULL,
    keep_index_type         NVARCHAR(60)   NULL,
    drop_index_type         NVARCHAR(60)   NULL,
    keep_is_primary_key     BIT            NOT NULL,
    drop_is_primary_key     BIT            NOT NULL,
    keep_is_unique          BIT            NOT NULL,
    drop_is_unique          BIT            NOT NULL,
    keep_reads              BIGINT         NOT NULL,
    drop_reads              BIGINT         NOT NULL,
    keep_writes             BIGINT         NOT NULL,
    drop_writes             BIGINT         NOT NULL,
    keep_last_read          DATETIME       NULL,
    drop_last_read          DATETIME       NULL,
    keep_last_update        DATETIME       NULL,
    drop_last_update        DATETIME       NULL,
    keep_size_mb            DECIMAL(18, 2) NOT NULL,
    drop_size_mb            DECIMAL(18, 2) NOT NULL,
    suggested_action        NVARCHAR(500)  NOT NULL,
    drop_ddl                NVARCHAR(MAX)  NOT NULL
);

IF OBJECT_ID(N'tempdb..#CollectionDiagnostics') IS NOT NULL
    DROP TABLE #CollectionDiagnostics;

CREATE TABLE #CollectionDiagnostics
(
    database_name   SYSNAME       NOT NULL,
    indexes_scanned INT           NOT NULL,
    pairs_found     INT           NOT NULL,
    status_message  NVARCHAR(400) NOT NULL
);

IF OBJECT_ID(N'tempdb..#BigTableList') IS NOT NULL
    DROP TABLE #BigTableList;

CREATE TABLE #BigTableList
(
    database_name   SYSNAME        NOT NULL,
    schema_name     SYSNAME        NOT NULL,
    table_name      SYSNAME        NOT NULL,
    table_rows      BIGINT         NOT NULL,
    table_size_mb   DECIMAL(18, 2) NOT NULL,
    index_count     INT            NOT NULL,
    nc_index_count  INT            NOT NULL
);

IF OBJECT_ID(N'tempdb..#IndexMergeSuggestions') IS NOT NULL
    DROP TABLE #IndexMergeSuggestions;

CREATE TABLE #IndexMergeSuggestions
(
    database_name           SYSNAME        NOT NULL,
    schema_name             SYSNAME        NOT NULL,
    table_name              SYSNAME        NOT NULL,
    table_rows              BIGINT         NOT NULL,
    table_size_mb           DECIMAL(18, 2) NOT NULL,
    suggestion_type         NVARCHAR(40)   NOT NULL,
    keep_index              SYSNAME        NOT NULL,
    drop_index              SYSNAME        NOT NULL,
    keep_key_columns        NVARCHAR(MAX)  NULL,
    keep_included_columns   NVARCHAR(MAX)  NULL,
    drop_key_columns        NVARCHAR(MAX)  NULL,
    drop_included_columns   NVARCHAR(MAX)  NULL,
    merged_key_columns      NVARCHAR(MAX)  NULL,
    merged_included_columns NVARCHAR(MAX)  NULL,
    keep_reads              BIGINT         NOT NULL,
    keep_writes             BIGINT         NOT NULL,
    drop_reads              BIGINT         NOT NULL,
    drop_writes             BIGINT         NOT NULL,
    keep_last_read          DATETIME       NULL,
    drop_last_read          DATETIME       NULL,
    keep_last_update        DATETIME       NULL,
    drop_last_update        DATETIME       NULL,
    est_space_reclaim_mb    DECIMAL(18, 2) NOT NULL,
    is_blocked              BIT            NOT NULL,
    proposed_index_ddl      NVARCHAR(MAX)  NOT NULL,
    drop_ddl                NVARCHAR(MAX)  NOT NULL,
    safety_notes            NVARCHAR(1000) NOT NULL,
    rationale               NVARCHAR(1000) NOT NULL
);

/*------------------------------------------------------------------------------
  Per-database collection query (executed inside each target database)
------------------------------------------------------------------------------*/
DECLARE @DuplicateCommand NVARCHAR(MAX) = N'
DECLARE @IndexesScanned INT = 0;
DECLARE @PairsFound INT = 0;

BEGIN TRY

IF OBJECT_ID(N''tempdb..#IdxEligible'') IS NOT NULL
    DROP TABLE #IdxEligible;

CREATE TABLE #IdxEligible
(
    schema_name SYSNAME NOT NULL,
    table_name SYSNAME NOT NULL,
    object_id INT NOT NULL,
    index_id INT NOT NULL,
    index_name SYSNAME NULL,
    type_desc NVARCHAR(60) NOT NULL,
    is_unique BIT NOT NULL,
    is_primary_key BIT NOT NULL,
    is_unique_constraint BIT NOT NULL,
    is_disabled BIT NOT NULL,
    filter_definition NVARCHAR(MAX) NULL,
    key_columns NVARCHAR(MAX) NULL,
    included_columns NVARCHAR(MAX) NOT NULL,
    used_page_count BIGINT NOT NULL,
    total_reads BIGINT NOT NULL,
    total_writes BIGINT NOT NULL,
    last_read DATETIME NULL,
    last_update DATETIME NULL
);

;WITH IndexColumnParts AS
(
    SELECT
        ic.object_id,
        ic.index_id,
        ic.is_included_column,
        ic.key_ordinal,
        ic.is_descending_key,
        ic.column_id,
        c.name AS column_name
    FROM sys.index_columns AS ic
    INNER JOIN sys.columns AS c
        ON c.object_id = ic.object_id
       AND c.column_id = ic.column_id
),
KeySignatures AS
(
    SELECT
        icp.object_id,
        icp.index_id,
        STRING_AGG(
            QUOTENAME(icp.column_name)
                + CASE WHEN icp.is_descending_key = 1 THEN N'' DESC'' ELSE N'''' END,
            N'',''
        ) WITHIN GROUP (ORDER BY icp.key_ordinal) AS key_columns
    FROM IndexColumnParts AS icp
    WHERE icp.is_included_column = 0
      AND icp.key_ordinal > 0
    GROUP BY icp.object_id, icp.index_id
),
IncludeSignatures AS
(
    SELECT
        icp.object_id,
        icp.index_id,
        STRING_AGG(QUOTENAME(icp.column_name), N'','') WITHIN GROUP (ORDER BY icp.column_name) AS included_columns
    FROM IndexColumnParts AS icp
    WHERE icp.is_included_column = 1
    GROUP BY icp.object_id, icp.index_id
),
IndexMeta AS
(
    SELECT
        s.name AS schema_name,
        t.name AS table_name,
        i.object_id,
        i.index_id,
        i.name AS index_name,
        i.type_desc,
        i.is_unique,
        i.is_primary_key,
        i.is_unique_constraint,
        i.is_disabled,
        UPPER(LTRIM(RTRIM(ISNULL(i.filter_definition, N'''')))) AS filter_definition,
        ks.key_columns,
        ISNULL(inc.included_columns, N'''') AS included_columns,
        ISNULL(ps.used_page_count, 0) AS used_page_count,
        ISNULL(ust.user_seeks, 0) + ISNULL(ust.user_scans, 0) + ISNULL(ust.user_lookups, 0) AS total_reads,
        ISNULL(ust.user_updates, 0) AS total_writes,
        (
            SELECT MAX(v)
            FROM (VALUES (ust.last_user_seek), (ust.last_user_scan), (ust.last_user_lookup)) AS d(v)
        ) AS last_read,
        ust.last_user_update AS last_update
    FROM sys.indexes AS i
    INNER JOIN sys.tables AS t
        ON t.object_id = i.object_id
    INNER JOIN sys.schemas AS s
        ON s.schema_id = t.schema_id
    INNER JOIN KeySignatures AS ks
        ON ks.object_id = i.object_id
       AND ks.index_id = i.index_id
    LEFT JOIN IncludeSignatures AS inc
        ON inc.object_id = i.object_id
       AND inc.index_id = i.index_id
    LEFT JOIN sys.dm_db_index_usage_stats AS ust
        ON ust.database_id = DB_ID()
       AND ust.object_id = i.object_id
       AND ust.index_id = i.index_id
    OUTER APPLY
    (
        SELECT SUM(ps.used_page_count) AS used_page_count
        FROM sys.dm_db_partition_stats AS ps
        WHERE ps.object_id = i.object_id
          AND ps.index_id = i.index_id
    ) AS ps
    WHERE i.index_id > 0
      AND i.is_hypothetical = 0
      AND t.is_ms_shipped = 0
      AND OBJECTPROPERTY(i.object_id, N''IsUserTable'') = 1
),
Eligible AS
(
    SELECT
        schema_name,
        table_name,
        object_id,
        index_id,
        index_name,
        type_desc,
        is_unique,
        is_primary_key,
        is_unique_constraint,
        is_disabled,
        filter_definition,
        key_columns,
        included_columns,
        used_page_count,
        total_reads,
        total_writes,
        last_read,
        last_update
    FROM IndexMeta
    WHERE key_columns IS NOT NULL
      AND LEN(key_columns) > 0
      AND used_page_count >= ' + CAST(@MinPageCount AS NVARCHAR(20)) + N'
)
INSERT INTO #IdxEligible
(
    schema_name,
    table_name,
    object_id,
    index_id,
    index_name,
    type_desc,
    is_unique,
    is_primary_key,
    is_unique_constraint,
    is_disabled,
    filter_definition,
    key_columns,
    included_columns,
    used_page_count,
    total_reads,
    total_writes,
    last_read,
    last_update
)
SELECT
    schema_name,
    table_name,
    object_id,
    index_id,
    index_name,
    type_desc,
    is_unique,
    is_primary_key,
    is_unique_constraint,
    is_disabled,
    filter_definition,
    key_columns,
    included_columns,
    used_page_count,
    total_reads,
    total_writes,
    last_read,
    last_update
FROM Eligible;

SELECT @IndexesScanned = COUNT(*) FROM #IdxEligible;

;WITH Pairs AS
(
    SELECT
        k1.schema_name,
        k1.table_name,
        k1.object_id,
        k1.index_id AS index_id_a,
        k2.index_id AS index_id_b,
        k1.index_name AS index_name_a,
        k2.index_name AS index_name_b,
        k1.key_columns AS key_columns_a,
        k2.key_columns AS key_columns_b,
        k1.included_columns AS included_columns_a,
        k2.included_columns AS included_columns_b,
        k1.filter_definition AS filter_a,
        k2.filter_definition AS filter_b,
        k1.type_desc AS type_a,
        k2.type_desc AS type_b,
        k1.is_primary_key AS is_pk_a,
        k2.is_primary_key AS is_pk_b,
        k1.is_unique AS is_unique_a,
        k2.is_unique AS is_unique_b,
        k1.is_unique_constraint AS is_uc_a,
        k2.is_unique_constraint AS is_uc_b,
        k1.is_disabled AS is_disabled_a,
        k2.is_disabled AS is_disabled_b,
        k1.total_reads AS reads_a,
        k2.total_reads AS reads_b,
        k1.total_writes AS writes_a,
        k2.total_writes AS writes_b,
        k1.last_read AS last_read_a,
        k2.last_read AS last_read_b,
        k1.last_update AS last_update_a,
        k2.last_update AS last_update_b,
        k1.used_page_count AS pages_a,
        k2.used_page_count AS pages_b,
        CASE
            WHEN k1.key_columns = k2.key_columns
             AND k1.included_columns = k2.included_columns
             AND k1.filter_definition = k2.filter_definition
             AND k1.is_unique = k2.is_unique
             AND k1.type_desc = k2.type_desc
            THEN N''EXACT_DUPLICATE''

            WHEN k1.key_columns = k2.key_columns
            THEN N''DUPLICATE_KEY''

            WHEN k1.filter_definition = k2.filter_definition
             AND LEN(k2.key_columns) > LEN(k1.key_columns)
             AND LEFT(k2.key_columns, LEN(k1.key_columns)) = k1.key_columns
             AND SUBSTRING(k2.key_columns, LEN(k1.key_columns) + 1, 1) = N'',''
            THEN N''REDUNDANT_LEFT_PREFIX''

            WHEN k1.filter_definition = k2.filter_definition
             AND LEN(k1.key_columns) > LEN(k2.key_columns)
             AND LEFT(k1.key_columns, LEN(k2.key_columns)) = k2.key_columns
             AND SUBSTRING(k1.key_columns, LEN(k2.key_columns) + 1, 1) = N'',''
            THEN N''REDUNDANT_LEFT_PREFIX''

            ELSE NULL
        END AS duplicate_type,
        CASE
            WHEN LEN(k2.key_columns) > LEN(k1.key_columns)
             AND LEFT(k2.key_columns, LEN(k1.key_columns)) = k1.key_columns
             AND SUBSTRING(k2.key_columns, LEN(k1.key_columns) + 1, 1) = N'',''
            THEN k1.index_id
            WHEN LEN(k1.key_columns) > LEN(k2.key_columns)
             AND LEFT(k1.key_columns, LEN(k2.key_columns)) = k2.key_columns
             AND SUBSTRING(k1.key_columns, LEN(k2.key_columns) + 1, 1) = N'',''
            THEN k2.index_id
            ELSE CASE WHEN k1.index_id < k2.index_id THEN k1.index_id ELSE k2.index_id END
        END AS narrower_index_id,
        CASE
            WHEN LEN(k2.key_columns) > LEN(k1.key_columns)
             AND LEFT(k2.key_columns, LEN(k1.key_columns)) = k1.key_columns
             AND SUBSTRING(k2.key_columns, LEN(k1.key_columns) + 1, 1) = N'',''
            THEN k2.index_id
            WHEN LEN(k1.key_columns) > LEN(k2.key_columns)
             AND LEFT(k1.key_columns, LEN(k2.key_columns)) = k2.key_columns
             AND SUBSTRING(k1.key_columns, LEN(k2.key_columns) + 1, 1) = N'',''
            THEN k1.index_id
            ELSE CASE WHEN k1.index_id < k2.index_id THEN k2.index_id ELSE k1.index_id END
        END AS wider_index_id
    FROM #IdxEligible AS k1
    INNER JOIN #IdxEligible AS k2
        ON k2.object_id = k1.object_id
       AND k2.index_id > k1.index_id
),
Chosen AS
(
    SELECT
        p.*,
        CASE
            WHEN p.duplicate_type = N''REDUNDANT_LEFT_PREFIX''
            THEN CASE WHEN p.wider_index_id = p.index_id_a THEN p.index_name_a ELSE p.index_name_b END
            WHEN p.is_pk_a = 1 OR p.is_uc_a = 1
            THEN p.index_name_a
            WHEN p.is_pk_b = 1 OR p.is_uc_b = 1
            THEN p.index_name_b
            WHEN p.is_disabled_a = 1 AND p.is_disabled_b = 0
            THEN p.index_name_b
            WHEN p.is_disabled_b = 1 AND p.is_disabled_a = 0
            THEN p.index_name_a
            WHEN p.reads_a > p.reads_b
              OR (p.reads_a = p.reads_b AND p.writes_a <= p.writes_b)
            THEN p.index_name_a
            WHEN p.reads_b > p.reads_a
              OR (p.reads_a = p.reads_b AND p.writes_b < p.writes_a)
            THEN p.index_name_b
            WHEN LEN(p.included_columns_a) > LEN(p.included_columns_b)
            THEN p.index_name_a
            WHEN LEN(p.included_columns_b) > LEN(p.included_columns_a)
            THEN p.index_name_b
            WHEN LEN(p.key_columns_b) > LEN(p.key_columns_a)
            THEN p.index_name_b
            ELSE p.index_name_a
        END AS index_keep,
        CASE
            WHEN p.duplicate_type = N''REDUNDANT_LEFT_PREFIX''
            THEN CASE WHEN p.narrower_index_id = p.index_id_a THEN p.index_name_a ELSE p.index_name_b END
            WHEN p.is_pk_a = 1 OR p.is_uc_a = 1
            THEN p.index_name_b
            WHEN p.is_pk_b = 1 OR p.is_uc_b = 1
            THEN p.index_name_a
            WHEN p.is_disabled_a = 1 AND p.is_disabled_b = 0
            THEN p.index_name_a
            WHEN p.is_disabled_b = 1 AND p.is_disabled_a = 0
            THEN p.index_name_b
            WHEN p.reads_a > p.reads_b
              OR (p.reads_a = p.reads_b AND p.writes_a <= p.writes_b)
            THEN p.index_name_b
            WHEN p.reads_b > p.reads_a
              OR (p.reads_a = p.reads_b AND p.writes_b < p.writes_a)
            THEN p.index_name_a
            WHEN LEN(p.included_columns_a) > LEN(p.included_columns_b)
            THEN p.index_name_b
            WHEN LEN(p.included_columns_b) > LEN(p.included_columns_a)
            THEN p.index_name_a
            WHEN LEN(p.key_columns_b) > LEN(p.key_columns_a)
            THEN p.index_name_a
            ELSE p.index_name_b
        END AS index_drop_candidate
    FROM Pairs AS p
    WHERE p.duplicate_type IS NOT NULL
),
Resolved AS
(
    SELECT
        c.schema_name,
        c.table_name,
        c.duplicate_type,
        c.index_keep,
        c.index_drop_candidate,
        CASE
            WHEN c.duplicate_type = N''REDUNDANT_LEFT_PREFIX''
            THEN CASE WHEN c.wider_index_id = c.index_id_a THEN c.key_columns_a ELSE c.key_columns_b END
            ELSE c.key_columns_a
        END AS key_columns,
        CASE WHEN c.index_keep = c.index_name_a THEN c.included_columns_a ELSE c.included_columns_b END AS included_columns_keep,
        CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.included_columns_a ELSE c.included_columns_b END AS included_columns_drop,
        CASE WHEN c.index_keep = c.index_name_a THEN c.filter_a ELSE c.filter_b END AS filter_keep,
        CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.filter_a ELSE c.filter_b END AS filter_drop,
        CASE WHEN c.index_keep = c.index_name_a THEN c.type_a ELSE c.type_b END AS keep_index_type,
        CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.type_a ELSE c.type_b END AS drop_index_type,
        CASE WHEN c.index_keep = c.index_name_a THEN c.is_pk_a ELSE c.is_pk_b END AS keep_is_primary_key,
        CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.is_pk_a ELSE c.is_pk_b END AS drop_is_primary_key,
        CASE WHEN c.index_keep = c.index_name_a THEN c.is_unique_a ELSE c.is_unique_b END AS keep_is_unique,
        CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.is_unique_a ELSE c.is_unique_b END AS drop_is_unique,
        CASE WHEN c.index_keep = c.index_name_a THEN c.reads_a ELSE c.reads_b END AS keep_reads,
        CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.reads_a ELSE c.reads_b END AS drop_reads,
        CASE WHEN c.index_keep = c.index_name_a THEN c.writes_a ELSE c.writes_b END AS keep_writes,
        CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.writes_a ELSE c.writes_b END AS drop_writes,
        CASE WHEN c.index_keep = c.index_name_a THEN c.last_read_a ELSE c.last_read_b END AS keep_last_read,
        CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.last_read_a ELSE c.last_read_b END AS drop_last_read,
        CASE WHEN c.index_keep = c.index_name_a THEN c.last_update_a ELSE c.last_update_b END AS keep_last_update,
        CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.last_update_a ELSE c.last_update_b END AS drop_last_update,
        CASE WHEN c.index_keep = c.index_name_a THEN c.pages_a ELSE c.pages_b END AS keep_pages,
        CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.pages_a ELSE c.pages_b END AS drop_pages
    FROM Chosen AS c
)
INSERT INTO #DuplicateIndexes
(
    database_name,
    schema_name,
    table_name,
    duplicate_type,
    index_keep,
    index_drop_candidate,
    key_columns,
    included_columns_keep,
    included_columns_drop,
    filter_definition,
    keep_index_type,
    drop_index_type,
    keep_is_primary_key,
    drop_is_primary_key,
    keep_is_unique,
    drop_is_unique,
    keep_reads,
    drop_reads,
    keep_writes,
    drop_writes,
    keep_last_read,
    drop_last_read,
    keep_last_update,
    drop_last_update,
    keep_size_mb,
    drop_size_mb,
    suggested_action,
    drop_ddl
)
SELECT
    DB_NAME(),
    r.schema_name,
    r.table_name,
    r.duplicate_type,
    r.index_keep,
    r.index_drop_candidate,
    r.key_columns,
    r.included_columns_keep,
    r.included_columns_drop,
    NULLIF(
        CASE
            WHEN r.filter_keep = r.filter_drop THEN NULLIF(r.filter_keep, N'''')
            ELSE N''KEEP: '' + NULLIF(r.filter_keep, N'''') + N'' | DROP: '' + NULLIF(r.filter_drop, N'''')
        END,
        N''''
    ) AS filter_definition,
    r.keep_index_type,
    r.drop_index_type,
    r.keep_is_primary_key,
    r.drop_is_primary_key,
    r.keep_is_unique,
    r.drop_is_unique,
    r.keep_reads,
    r.drop_reads,
    r.keep_writes,
    r.drop_writes,
    r.keep_last_read,
    r.drop_last_read,
    r.keep_last_update,
    r.drop_last_update,
    CAST(r.keep_pages * 8.0 / 1024.0 AS DECIMAL(18, 2)) AS keep_size_mb,
    CAST(r.drop_pages * 8.0 / 1024.0 AS DECIMAL(18, 2)) AS drop_size_mb,
    CASE
        WHEN r.drop_is_primary_key = 1
            THEN N''BLOCKED: Drop candidate is a PRIMARY KEY — resolve manually.''
        WHEN r.drop_is_unique = 1 AND r.keep_is_unique = 0
            THEN N''REVIEW: Drop candidate enforces uniqueness — confirm constraint coverage.''
        WHEN r.duplicate_type = N''EXACT_DUPLICATE''
            THEN N''DROP duplicate after validating usage stats and change approval.''
        WHEN r.duplicate_type = N''DUPLICATE_KEY''
             AND (r.filter_keep <> r.filter_drop OR r.included_columns_keep <> r.included_columns_drop)
            THEN N''REVIEW: Same key columns with different filter/includes/uniqueness — validate before drop.''
        WHEN r.duplicate_type = N''DUPLICATE_KEY''
            THEN N''DROP overlapping index after validating usage stats and change approval.''
        WHEN r.duplicate_type = N''REDUNDANT_LEFT_PREFIX''
            THEN N''REVIEW: Narrower index may be redundant — validate plans and includes.''
        ELSE N''REVIEW: Overlapping indexes detected.''
    END AS suggested_action,
    N''-- REVIEW BEFORE EXECUTING'' + CHAR(13) + CHAR(10)
        + N''USE '' + QUOTENAME(DB_NAME()) + N'';'' + CHAR(13) + CHAR(10)
        + N''DROP INDEX '' + QUOTENAME(r.index_drop_candidate) + N'' ON ''
        + QUOTENAME(r.schema_name) + N''.'' + QUOTENAME(r.table_name) + N'';''
    AS drop_ddl
FROM Resolved AS r;

SELECT @PairsFound = @@ROWCOUNT;

IF OBJECT_ID(N''tempdb..#IdxEligible'') IS NOT NULL
    DROP TABLE #IdxEligible;

INSERT INTO #CollectionDiagnostics (database_name, indexes_scanned, pairs_found, status_message)
VALUES (DB_NAME(), @IndexesScanned, @PairsFound, N''OK'');

END TRY
BEGIN CATCH
    IF OBJECT_ID(N''tempdb..#IdxEligible'') IS NOT NULL
        DROP TABLE #IdxEligible;

    INSERT INTO #CollectionDiagnostics (database_name, indexes_scanned, pairs_found, status_message)
    VALUES (DB_NAME(), @IndexesScanned, @PairsFound, LEFT(N''ERROR: '' + ERROR_MESSAGE(), 400));
END CATCH;
';

/*------------------------------------------------------------------------------
  Per-database big-table index consolidation query
  (executed inside each target database, same pass as the duplicate scan)

  Tokens {{TOPN}}, {{MINROWS}}, {{MINSIZEMB}}, {{ONLINE}} are substituted below.
------------------------------------------------------------------------------*/
DECLARE @MergeCommand NVARCHAR(MAX) = N'
BEGIN TRY

IF OBJECT_ID(N''tempdb..#BigTables'') IS NOT NULL DROP TABLE #BigTables;
IF OBJECT_ID(N''tempdb..#BigIdx'') IS NOT NULL DROP TABLE #BigIdx;
IF OBJECT_ID(N''tempdb..#BigIdxCol'') IS NOT NULL DROP TABLE #BigIdxCol;

;WITH TableStats AS
(
    SELECT
        ps.object_id,
        SUM(CASE WHEN ps.index_id IN (0, 1) THEN ps.row_count ELSE 0 END) AS table_rows,
        SUM(ps.reserved_page_count) AS reserved_pages
    FROM sys.dm_db_partition_stats AS ps
    INNER JOIN sys.tables AS t ON t.object_id = ps.object_id
    WHERE t.is_ms_shipped = 0
    GROUP BY ps.object_id
)
SELECT TOP ({{TOPN}})
    ts.object_id,
    ts.table_rows,
    CAST(ts.reserved_pages * 8.0 / 1024.0 AS DECIMAL(18, 2)) AS table_size_mb
INTO #BigTables
FROM TableStats AS ts
WHERE ts.table_rows >= {{MINROWS}}
   OR (ts.reserved_pages * 8.0 / 1024.0) >= {{MINSIZEMB}}
ORDER BY ts.reserved_pages DESC, ts.table_rows DESC;

INSERT INTO #BigTableList (database_name, schema_name, table_name, table_rows, table_size_mb, index_count, nc_index_count)
SELECT
    DB_NAME(),
    s.name,
    t.name,
    bt.table_rows,
    bt.table_size_mb,
    (SELECT COUNT(*) FROM sys.indexes AS i WHERE i.object_id = bt.object_id AND i.index_id > 0),
    (SELECT COUNT(*) FROM sys.indexes AS i WHERE i.object_id = bt.object_id AND i.type = 2)
FROM #BigTables AS bt
INNER JOIN sys.tables AS t ON t.object_id = bt.object_id
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id;

SELECT
    ic.object_id,
    ic.index_id,
    c.name AS column_name,
    ic.is_included_column,
    ic.key_ordinal,
    ic.is_descending_key
INTO #BigIdxCol
FROM sys.index_columns AS ic
INNER JOIN sys.columns AS c
    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE ic.object_id IN (SELECT object_id FROM #BigTables);

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    bt.table_rows,
    bt.table_size_mb,
    i.object_id,
    i.index_id,
    i.name AS index_name,
    i.is_unique,
    i.is_primary_key,
    i.is_unique_constraint,
    i.is_disabled,
    UPPER(LTRIM(RTRIM(ISNULL(i.filter_definition, N'''')))) AS filter_definition,
    (
        SELECT STRING_AGG(
                   QUOTENAME(c.name)
                       + CASE WHEN ic.is_descending_key = 1 THEN N'' DESC'' ELSE N'''' END,
                   N'',''
               ) WITHIN GROUP (ORDER BY ic.key_ordinal)
        FROM sys.index_columns AS ic
        INNER JOIN sys.columns AS c
            ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 0
          AND ic.key_ordinal > 0
    ) AS key_sig,
    ISNULL((
        SELECT STRING_AGG(QUOTENAME(c.name), N'','') WITHIN GROUP (ORDER BY c.name)
        FROM sys.index_columns AS ic
        INNER JOIN sys.columns AS c
            ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 1
    ), N'''') AS include_sig,
    (
        SELECT c.name
        FROM sys.index_columns AS ic
        INNER JOIN sys.columns AS c
            ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 0
          AND ic.key_ordinal = 1
    ) AS leading_key,
    ISNULL(ust.user_seeks, 0) + ISNULL(ust.user_scans, 0) + ISNULL(ust.user_lookups, 0) AS reads,
    ISNULL(ust.user_updates, 0) AS writes,
    (
        SELECT MAX(v)
        FROM (VALUES (ust.last_user_seek), (ust.last_user_scan), (ust.last_user_lookup)) AS d(v)
    ) AS last_read,
    ust.last_user_update AS last_update,
    CAST(ISNULL((
        SELECT SUM(ps.used_page_count)
        FROM sys.dm_db_partition_stats AS ps
        WHERE ps.object_id = i.object_id AND ps.index_id = i.index_id
    ), 0) * 8.0 / 1024.0 AS DECIMAL(18, 2)) AS size_mb
INTO #BigIdx
FROM sys.indexes AS i
INNER JOIN #BigTables AS bt ON bt.object_id = i.object_id
INNER JOIN sys.tables AS t ON t.object_id = i.object_id
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
LEFT JOIN sys.dm_db_index_usage_stats AS ust
    ON ust.database_id = DB_ID()
   AND ust.object_id = i.object_id
   AND ust.index_id = i.index_id
WHERE i.type = 2            -- nonclustered rowstore only
  AND i.is_hypothetical = 0;

;WITH Flags AS
(
    SELECT
        a.object_id,
        a.schema_name,
        a.table_name,
        a.table_rows,
        a.table_size_mb,
        a.index_id AS id_a,
        b.index_id AS id_b,
        a.index_name AS name_a,
        b.index_name AS name_b,
        a.key_sig AS key_a,
        b.key_sig AS key_b,
        a.include_sig AS inc_a,
        b.include_sig AS inc_b,
        a.is_unique AS uq_a,
        b.is_unique AS uq_b,
        a.is_primary_key AS pk_a,
        b.is_primary_key AS pk_b,
        a.is_unique_constraint AS uc_a,
        b.is_unique_constraint AS uc_b,
        a.reads AS reads_a,
        b.reads AS reads_b,
        a.writes AS writes_a,
        b.writes AS writes_b,
        a.size_mb AS size_a,
        b.size_mb AS size_b,
        CAST(CASE WHEN a.key_sig = b.key_sig THEN 1 ELSE 0 END AS BIT) AS same_key,
        CAST(CASE
            WHEN LEN(b.key_sig) > LEN(a.key_sig)
             AND LEFT(b.key_sig, LEN(a.key_sig)) = a.key_sig
             AND SUBSTRING(b.key_sig, LEN(a.key_sig) + 1, 1) = N'',''
            THEN 1 ELSE 0 END AS BIT) AS a_prefix_b,
        CAST(CASE
            WHEN LEN(a.key_sig) > LEN(b.key_sig)
             AND LEFT(a.key_sig, LEN(b.key_sig)) = b.key_sig
             AND SUBSTRING(a.key_sig, LEN(b.key_sig) + 1, 1) = N'',''
            THEN 1 ELSE 0 END AS BIT) AS b_prefix_a,
        CAST(CASE WHEN NOT EXISTS (
            SELECT 1 FROM #BigIdxCol ca
            WHERE ca.object_id = a.object_id AND ca.index_id = a.index_id
              AND NOT EXISTS (
                  SELECT 1 FROM #BigIdxCol cb
                  WHERE cb.object_id = b.object_id AND cb.index_id = b.index_id
                    AND cb.column_name = ca.column_name)
        ) THEN 1 ELSE 0 END AS BIT) AS a_cov_b,
        CAST(CASE WHEN NOT EXISTS (
            SELECT 1 FROM #BigIdxCol cb
            WHERE cb.object_id = b.object_id AND cb.index_id = b.index_id
              AND NOT EXISTS (
                  SELECT 1 FROM #BigIdxCol ca
                  WHERE ca.object_id = a.object_id AND ca.index_id = a.index_id
                    AND ca.column_name = cb.column_name)
        ) THEN 1 ELSE 0 END AS BIT) AS b_cov_a,
        CAST(CASE WHEN a.leading_key = b.leading_key THEN 1 ELSE 0 END AS BIT) AS same_lead
    FROM #BigIdx AS a
    INNER JOIN #BigIdx AS b
        ON b.object_id = a.object_id
       AND a.index_id < b.index_id
       AND a.filter_definition = b.filter_definition
),
Classified AS
(
    SELECT
        f.*,
        CASE
            WHEN same_key = 1 AND a_cov_b = 1 AND b_cov_a = 1 THEN N''DROP_REDUNDANT''
            WHEN same_key = 1 AND b_cov_a = 1 THEN N''SUPERSET_INCLUDES''
            WHEN same_key = 1 AND a_cov_b = 1 THEN N''SUPERSET_INCLUDES''
            WHEN same_key = 1 THEN N''MERGE_INCLUDES''
            WHEN a_prefix_b = 1 AND a_cov_b = 1 THEN N''PREFIX_SUBSUMED''
            WHEN b_prefix_a = 1 AND b_cov_a = 1 THEN N''PREFIX_SUBSUMED''
            WHEN a_prefix_b = 1 THEN N''PREFIX_MERGE''
            WHEN b_prefix_a = 1 THEN N''PREFIX_MERGE''
            WHEN same_lead = 1 THEN N''LEADING_KEY_REVIEW''
            ELSE NULL
        END AS suggestion_type,
        CASE
            WHEN same_key = 1 AND a_cov_b = 1 AND b_cov_a = 1
                THEN CASE
                        WHEN pk_a = 1 OR uc_a = 1 OR uq_a = 1 THEN id_a
                        WHEN pk_b = 1 OR uc_b = 1 OR uq_b = 1 THEN id_b
                        WHEN reads_a >= reads_b THEN id_a ELSE id_b END
            WHEN same_key = 1 AND b_cov_a = 1 THEN id_a
            WHEN same_key = 1 AND a_cov_b = 1 THEN id_b
            WHEN same_key = 1
                THEN CASE
                        WHEN pk_a = 1 OR uc_a = 1 THEN id_a
                        WHEN pk_b = 1 OR uc_b = 1 THEN id_b
                        WHEN uq_a = 1 AND uq_b = 0 THEN id_a
                        WHEN uq_b = 1 AND uq_a = 0 THEN id_b
                        WHEN reads_a > reads_b THEN id_a
                        WHEN reads_b > reads_a THEN id_b
                        WHEN LEN(inc_a) >= LEN(inc_b) THEN id_a ELSE id_b END
            WHEN a_prefix_b = 1 THEN id_b
            WHEN b_prefix_a = 1 THEN id_a
            ELSE CASE WHEN reads_a >= reads_b THEN id_a ELSE id_b END
        END AS keep_id
    FROM Flags AS f
    WHERE
        (same_key = 1)
        OR (a_prefix_b = 1)
        OR (b_prefix_a = 1)
        OR (same_lead = 1)
),
Picked AS
(
    SELECT
        c.*,
        CASE WHEN c.keep_id = c.id_a THEN c.id_b ELSE c.id_a END AS drop_id
    FROM Classified AS c
    WHERE c.suggestion_type IS NOT NULL
)
INSERT INTO #IndexMergeSuggestions
(
    database_name, schema_name, table_name, table_rows, table_size_mb,
    suggestion_type, keep_index, drop_index,
    keep_key_columns, keep_included_columns,
    drop_key_columns, drop_included_columns,
    merged_key_columns, merged_included_columns,
    keep_reads, keep_writes, drop_reads, drop_writes,
    keep_last_read, drop_last_read, keep_last_update, drop_last_update,
    est_space_reclaim_mb,
    is_blocked, proposed_index_ddl, drop_ddl, safety_notes, rationale
)
SELECT
    DB_NAME(),
    p.schema_name,
    p.table_name,
    p.table_rows,
    p.table_size_mb,
    p.suggestion_type,
    ki.index_name AS keep_index,
    di.index_name AS drop_index,
    ki.key_sig AS keep_key_columns,
    NULLIF(ki.include_sig, N'''') AS keep_included_columns,
    di.key_sig AS drop_key_columns,
    NULLIF(di.include_sig, N'''') AS drop_included_columns,
    ki.key_sig AS merged_key_columns,
    merged.included_columns AS merged_included_columns,
    ki.reads AS keep_reads,
    ki.writes AS keep_writes,
    di.reads AS drop_reads,
    di.writes AS drop_writes,
    ki.last_read AS keep_last_read,
    di.last_read AS drop_last_read,
    ki.last_update AS keep_last_update,
    di.last_update AS drop_last_update,
    di.size_mb AS est_space_reclaim_mb,
    CASE WHEN blk.is_blocked = 1 THEN 1 ELSE 0 END AS is_blocked,
    CASE
        WHEN p.suggestion_type IN (N''DROP_REDUNDANT'', N''SUPERSET_INCLUDES'', N''PREFIX_SUBSUMED'')
            THEN N''No new index required. Keep '' + QUOTENAME(ki.index_name) + N'' unchanged.''
        WHEN p.suggestion_type IN (N''MERGE_INCLUDES'', N''PREFIX_MERGE'')
            THEN N''CREATE ''
                 + CASE WHEN (p.suggestion_type = N''MERGE_INCLUDES'' AND (ki.is_unique = 1 OR di.is_unique = 1))
                             OR (p.suggestion_type = N''PREFIX_MERGE'' AND ki.is_unique = 1)
                        THEN N''UNIQUE '' ELSE N'''' END
                 + N''NONCLUSTERED INDEX '' + QUOTENAME(ki.index_name)
                 + N'' ON '' + QUOTENAME(p.schema_name) + N''.'' + QUOTENAME(p.table_name)
                 + N'' ('' + ki.key_sig + N'')''
                 + CASE WHEN merged.included_columns IS NOT NULL AND merged.included_columns <> N''''
                        THEN N'' INCLUDE ('' + merged.included_columns + N'')'' ELSE N'''' END
                 + N'' WITH (DROP_EXISTING = ON{{ONLINE}});''
        ELSE N''REVIEW: manual analysis required — same leading key but divergent key columns.''
    END AS proposed_index_ddl,
    CASE
        WHEN p.suggestion_type = N''LEADING_KEY_REVIEW''
            THEN N''-- REVIEW ONLY: no automatic drop for same-leading-key/divergent indexes.''
        WHEN blk.is_blocked = 1
            THEN N''-- BLOCKED: drop candidate '' + QUOTENAME(di.index_name)
                 + N'' backs a PRIMARY KEY / UNIQUE constraint or a unique guarantee. Resolve manually.''
        ELSE N''-- REVIEW BEFORE EXECUTING'' + CHAR(13) + CHAR(10)
             + N''USE '' + QUOTENAME(DB_NAME()) + N'';'' + CHAR(13) + CHAR(10)
             + N''DROP INDEX '' + QUOTENAME(di.index_name) + N'' ON ''
             + QUOTENAME(p.schema_name) + N''.'' + QUOTENAME(p.table_name) + N'';''
    END AS drop_ddl,
    CASE WHEN blk.is_blocked = 1
         THEN N''BLOCKED: constraint/uniqueness on drop candidate. ''
         ELSE N'''' END
    + N''Validate against Query Store / plan cache and test in non-production before applying. ''
    + N''ONLINE rebuild option auto-selected by edition. Rebuilding widens the kept index (extra write/space cost).''
    AS safety_notes,
    CASE p.suggestion_type
        WHEN N''DROP_REDUNDANT''    THEN N''Both indexes cover the same key and column set; one is fully redundant.''
        WHEN N''SUPERSET_INCLUDES'' THEN N''Same key columns; kept index already covers all columns of the drop candidate.''
        WHEN N''PREFIX_SUBSUMED''   THEN N''Drop candidate key is a left-prefix of the kept index and all its columns are covered.''
        WHEN N''MERGE_INCLUDES''    THEN N''Same key columns with different INCLUDE lists; merge the includes into one index.''
        WHEN N''PREFIX_MERGE''      THEN N''Narrower key is a left-prefix of the wider index; fold its INCLUDE columns into the wider index.''
        WHEN N''LEADING_KEY_REVIEW'' THEN N''Shared leading key but divergent key columns; merging may downgrade a seek to a scan — review manually.''
        ELSE N''Overlapping indexes.''
    END AS rationale
FROM Picked AS p
INNER JOIN #BigIdx AS ki ON ki.object_id = p.object_id AND ki.index_id = p.keep_id
INNER JOIN #BigIdx AS di ON di.object_id = p.object_id AND di.index_id = p.drop_id
CROSS APPLY
(
    SELECT STRING_AGG(x.col, N'', '') AS included_columns
    FROM
    (
        SELECT DISTINCT QUOTENAME(bic.column_name) AS col
        FROM #BigIdxCol AS bic
        WHERE bic.object_id = p.object_id
          AND bic.index_id IN (p.keep_id, p.drop_id)
          AND bic.column_name NOT IN (
                SELECT k.column_name
                FROM #BigIdxCol AS k
                WHERE k.object_id = p.object_id
                  AND k.index_id = p.keep_id
                  AND k.is_included_column = 0)
    ) AS x
) AS merged
CROSS APPLY
(
    SELECT CAST(CASE
        WHEN di.is_primary_key = 1 OR di.is_unique_constraint = 1 THEN 1
        WHEN di.is_unique = 1 AND p.suggestion_type IN (N''PREFIX_SUBSUMED'', N''PREFIX_MERGE'') THEN 1
        ELSE 0 END AS BIT) AS is_blocked
) AS blk
WHERE p.suggestion_type IS NOT NULL;

INSERT INTO #CollectionDiagnostics (database_name, indexes_scanned, pairs_found, status_message)
SELECT
    DB_NAME(),
    (SELECT COUNT(*) FROM #BigTableList WHERE database_name = DB_NAME()),
    (SELECT COUNT(*) FROM #IndexMergeSuggestions WHERE database_name = DB_NAME()),
    N''MERGE OK (indexes_scanned = big tables analyzed, pairs_found = consolidation suggestions)'';

IF OBJECT_ID(N''tempdb..#BigTables'') IS NOT NULL DROP TABLE #BigTables;
IF OBJECT_ID(N''tempdb..#BigIdx'') IS NOT NULL DROP TABLE #BigIdx;
IF OBJECT_ID(N''tempdb..#BigIdxCol'') IS NOT NULL DROP TABLE #BigIdxCol;

END TRY
BEGIN CATCH
    IF OBJECT_ID(N''tempdb..#BigTables'') IS NOT NULL DROP TABLE #BigTables;
    IF OBJECT_ID(N''tempdb..#BigIdx'') IS NOT NULL DROP TABLE #BigIdx;
    IF OBJECT_ID(N''tempdb..#BigIdxCol'') IS NOT NULL DROP TABLE #BigIdxCol;

    INSERT INTO #CollectionDiagnostics (database_name, indexes_scanned, pairs_found, status_message)
    VALUES (DB_NAME(), -1, -1, LEFT(N''MERGE ERROR: '' + ERROR_MESSAGE(), 400));
END CATCH;
';

SET @MergeCommand = REPLACE(@MergeCommand, N'{{TOPN}}',      CAST(@BigTableTopN AS NVARCHAR(20)));
SET @MergeCommand = REPLACE(@MergeCommand, N'{{MINROWS}}',   CAST(@BigTableMinRows AS NVARCHAR(30)));
SET @MergeCommand = REPLACE(@MergeCommand, N'{{MINSIZEMB}}', CAST(@BigTableMinSizeMB AS NVARCHAR(30)));
SET @MergeCommand = REPLACE(@MergeCommand, N'{{ONLINE}}',    @OnlineClause);

/*------------------------------------------------------------------------------
  Execute across target databases

  The duplicate scan and the big-table merge scan are executed as TWO separate
  batches so a failure in one can never suppress the results of the other.
------------------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    EXEC dbo.sp_DBA_ForEachDatabase
        @Command            = @DuplicateCommand,
        @UserDatabasesOnly  = 1,
        @IncludeReadOnly    = @IncludeReadOnly,
        @DatabaseList       = @DatabaseList,
        @ContinueOnError    = 1;

    EXEC dbo.sp_DBA_ForEachDatabase
        @Command            = @MergeCommand,
        @UserDatabasesOnly  = 1,
        @IncludeReadOnly    = @IncludeReadOnly,
        @DatabaseList       = @DatabaseList,
        @ContinueOnError    = 1;
END
ELSE
BEGIN
    DECLARE @db_name SYSNAME;
    DECLARE @SQL     NVARCHAR(MAX);

    IF OBJECT_ID(N'tempdb..#DbTargets') IS NOT NULL
        DROP TABLE #DbTargets;

    CREATE TABLE #DbTargets
    (
        database_name SYSNAME NOT NULL PRIMARY KEY
    );

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
    BEGIN
        INSERT INTO #DbTargets (database_name)
        SELECT d.name
        FROM sys.databases AS d
        INNER JOIN
        (
            SELECT LTRIM(RTRIM(value)) AS database_name
            FROM STRING_SPLIT(@DatabaseList, N',')
            WHERE LTRIM(RTRIM(value)) <> N''
        ) AS req
            ON req.database_name = d.name
        WHERE d.state = 0
          AND d.is_in_standby = 0;
    END
    ELSE
    BEGIN
        INSERT INTO #DbTargets (database_name)
        SELECT d.name
        FROM sys.databases AS d
        WHERE d.database_id > 4
          AND d.state = 0
          AND d.is_in_standby = 0
          AND (@IncludeReadOnly = 1 OR d.is_read_only = 0);
    END;

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name
        FROM #DbTargets
        ORDER BY database_name;

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Pass 1: duplicate / overlapping index scan
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @DuplicateCommand;
        BEGIN TRY
            EXEC sys.sp_executesql @SQL;
        END TRY
        BEGIN CATCH
            IF @ShowDiagnostics = 1
                PRINT N'[WARN] Duplicate scan skipped ' + QUOTENAME(@db_name) + N': ' + ERROR_MESSAGE();

            INSERT INTO #CollectionDiagnostics (database_name, indexes_scanned, pairs_found, status_message)
            VALUES (@db_name, 0, 0, LEFT(N'ERROR: ' + ERROR_MESSAGE(), 400));
        END CATCH;

        -- Pass 2: big-table index consolidation scan (isolated from pass 1)
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @MergeCommand;
        BEGIN TRY
            EXEC sys.sp_executesql @SQL;
        END TRY
        BEGIN CATCH
            IF @ShowDiagnostics = 1
                PRINT N'[WARN] Merge scan skipped ' + QUOTENAME(@db_name) + N': ' + ERROR_MESSAGE();

            INSERT INTO #CollectionDiagnostics (database_name, indexes_scanned, pairs_found, status_message)
            VALUES (@db_name, -1, -1, LEFT(N'MERGE ERROR: ' + ERROR_MESSAGE(), 400));
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @db_name;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    DROP TABLE #DbTargets;
END;

/*------------------------------------------------------------------------------
  Results
------------------------------------------------------------------------------*/
SELECT
    sqlserver_start_time AS instance_start_time,
    N'Index usage stats are cumulative since this time.' AS metric_context
FROM sys.dm_os_sys_info;

IF @ShowDiagnostics = 1
BEGIN
    PRINT N'--- Collection Diagnostics ---';

    SELECT
        database_name,
        indexes_scanned,
        pairs_found,
        status_message
    FROM #CollectionDiagnostics
    ORDER BY database_name;
END;

PRINT N'--- Duplicate Index Pairs ---';

SELECT
    N'DUPLICATE INDEX ANALYSIS (exact / duplicate-key / left-prefix)' AS metric_context,
    database_name,
    schema_name,
    table_name,
    duplicate_type,
    index_keep,
    index_drop_candidate,
    key_columns,
    included_columns_keep,
    included_columns_drop,
    filter_definition,
    keep_index_type,
    drop_index_type,
    keep_is_primary_key,
    drop_is_primary_key,
    keep_reads,
    drop_reads,
    keep_writes,
    drop_writes,
    keep_last_read,
    drop_last_read,
    keep_last_update,
    drop_last_update,
    CASE
        WHEN keep_reads > 0 THEN N'USED (reads since restart)'
        WHEN keep_reads = 0 AND keep_writes > 0 THEN N'UNUSED - WRITE ONLY (maintained, never read)'
        ELSE N'NO USAGE SINCE RESTART'
    END AS keep_usage_status,
    CASE
        WHEN drop_reads > 0 THEN N'USED (reads since restart)'
        WHEN drop_reads = 0 AND drop_writes > 0 THEN N'UNUSED - WRITE ONLY (safe drop candidate)'
        ELSE N'NO USAGE SINCE RESTART'
    END AS drop_usage_status,
    keep_size_mb,
    drop_size_mb,
    suggested_action,
    drop_ddl
FROM #DuplicateIndexes
ORDER BY
    CASE duplicate_type
        WHEN N'EXACT_DUPLICATE' THEN 1
        WHEN N'DUPLICATE_KEY' THEN 2
        WHEN N'REDUNDANT_LEFT_PREFIX' THEN 3
        ELSE 4
    END,
    database_name,
    schema_name,
    table_name,
    index_drop_candidate;

PRINT N'--- Summary By Database And Duplicate Type ---';

SELECT
    database_name,
    duplicate_type,
    COUNT(*) AS pair_count,
    SUM(drop_size_mb) AS reclaimable_drop_candidate_mb
FROM #DuplicateIndexes
GROUP BY database_name, duplicate_type
ORDER BY database_name, duplicate_type;

IF NOT EXISTS (SELECT 1 FROM #DuplicateIndexes)
BEGIN
    PRINT N'No duplicate or overlapping index pairs found for the selected database scope.';
    PRINT N'Check Collection Diagnostics above: indexes_scanned = 0 usually means the database was skipped or the inner query failed.';
END;

PRINT N'--- Big Tables Analyzed (Top N by Size / Rows) ---';

SELECT
    database_name,
    schema_name,
    table_name,
    table_rows,
    table_size_mb,
    index_count,
    nc_index_count
FROM #BigTableList
ORDER BY table_size_mb DESC, table_rows DESC;

PRINT N'--- Index Consolidation Suggestions (Big Tables) ---';

SELECT
    N'INDEX CONSOLIDATION - BIG TABLES (superset / redundant / overlapping / merge)' AS metric_context,
    database_name,
    schema_name,
    table_name,
    table_rows,
    table_size_mb,
    suggestion_type,
    keep_index,
    keep_key_columns,
    keep_included_columns,
    drop_index,
    drop_key_columns,
    drop_included_columns,
    merged_key_columns,
    merged_included_columns,
    keep_reads,
    keep_writes,
    drop_reads,
    drop_writes,
    keep_last_read,
    drop_last_read,
    keep_last_update,
    drop_last_update,
    CASE
        WHEN keep_reads > 0 THEN N'USED (reads since restart)'
        WHEN keep_reads = 0 AND keep_writes > 0 THEN N'UNUSED - WRITE ONLY (maintained, never read)'
        ELSE N'NO USAGE SINCE RESTART'
    END AS keep_usage_status,
    CASE
        WHEN drop_reads > 0 THEN N'USED (reads since restart)'
        WHEN drop_reads = 0 AND drop_writes > 0 THEN N'UNUSED - WRITE ONLY (safe drop candidate)'
        ELSE N'NO USAGE SINCE RESTART'
    END AS drop_usage_status,
    est_space_reclaim_mb,
    is_blocked,
    proposed_index_ddl,
    drop_ddl,
    safety_notes,
    rationale
FROM #IndexMergeSuggestions
ORDER BY
    is_blocked,
    CASE suggestion_type
        WHEN N'DROP_REDUNDANT'     THEN 1
        WHEN N'SUPERSET_INCLUDES'  THEN 2
        WHEN N'PREFIX_SUBSUMED'    THEN 3
        WHEN N'MERGE_INCLUDES'     THEN 4
        WHEN N'PREFIX_MERGE'       THEN 5
        WHEN N'LEADING_KEY_REVIEW' THEN 6
        ELSE 7
    END,
    est_space_reclaim_mb DESC,
    database_name,
    schema_name,
    table_name;

PRINT N'--- Consolidation Summary By Database And Type ---';

SELECT
    database_name,
    suggestion_type,
    COUNT(*) AS suggestion_count,
    SUM(CASE WHEN is_blocked = 0 THEN 1 ELSE 0 END) AS actionable_count,
    SUM(est_space_reclaim_mb) AS est_space_reclaim_mb
FROM #IndexMergeSuggestions
GROUP BY database_name, suggestion_type
ORDER BY database_name, suggestion_type;

IF NOT EXISTS (SELECT 1 FROM #IndexMergeSuggestions)
BEGIN
    PRINT N'No index consolidation opportunities found on the big tables in scope.';
    PRINT N'Adjust @BigTableTopN / @BigTableMinRows / @BigTableMinSizeMB to widen the analysis.';
END;

DROP TABLE #DuplicateIndexes;
DROP TABLE #CollectionDiagnostics;
DROP TABLE #BigTableList;
DROP TABLE #IndexMergeSuggestions;
