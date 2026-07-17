/*
================================================================================
Duplicate Unique Index / Unique Constraint Analysis — Production Diagnostic
================================================================================
Description:
    Finds indexes that duplicate or overlap a UNIQUE index or UNIQUE constraint.
    Loads all user-table indexes for pairing, then keeps only pairs where at
    least one side is a unique index or unique constraint (CREATE UNIQUE INDEX
    / UNIQUE CONSTRAINT). This catches:
      - unique index vs unique index / unique constraint
      - unique index / UC vs PRIMARY KEY (same or overlapping keys)
      - unique index / UC vs non-unique index (same or overlapping keys)

    Detects exact duplicates, same-key overlaps (order-insensitive via a
    name-sorted signature), and left-prefix overlaps. PRIMARY KEY and UNIQUE
    constraint indexes are never suggested as DROP INDEX targets.

    IMPORTANT — uniqueness semantics:
    A unique index on (A) is NOT subsumed by a unique index on (A, B). The
    wider key allows duplicate A values when B differs. Left-prefix pairs
    where BOTH sides enforce uniqueness (unique index/UC) are reported as
    LEFT_PREFIX_UNIQUE_OVERLAP and are never actionable drops.

Output:
    (1) Duplicate / overlapping pairs involving unique indexes or UCs.
    (2) Summary counts by database and duplicate type.
    (3) Collection diagnostics (databases scanned, indexes evaluated).

Action:
    Review EXACT_DUPLICATE first. Prefer keeping PRIMARY KEY, then UNIQUE
    constraint, then the unique index with better usage. Non-unique duplicates
    of a unique key are the safest drop candidates. Never DROP INDEX a UNIQUE
    constraint — use ALTER TABLE ... DROP CONSTRAINT after review.
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
    RAISERROR(N'duplicate_UQ_unique_index_details.sql requires SQL Server 2019 or higher.', 16, 1);
    RETURN;
END;

/*------------------------------------------------------------------------------
  User configuration
------------------------------------------------------------------------------*/
DECLARE @DatabaseList    NVARCHAR(MAX) = N'userdb';   -- e.g. N'userdb' or NULL = all user DBs
DECLARE @IncludeReadOnly BIT            = 0;
DECLARE @MinPageCount    INT            = 0;
DECLARE @ShowDiagnostics BIT            = 1;

/*------------------------------------------------------------------------------
  Staging
------------------------------------------------------------------------------*/
IF OBJECT_ID(N'tempdb..#DuplicateUniqueIndexes') IS NOT NULL
    DROP TABLE #DuplicateUniqueIndexes;

CREATE TABLE #DuplicateUniqueIndexes
(
    database_name             SYSNAME        NOT NULL,
    schema_name               SYSNAME        NOT NULL,
    table_name                SYSNAME        NOT NULL,
    duplicate_type            NVARCHAR(40)   NOT NULL,
    index_keep                SYSNAME        NOT NULL,
    index_drop_candidate      SYSNAME        NOT NULL,
    key_columns               NVARCHAR(MAX)  NULL,
    included_columns_keep     NVARCHAR(MAX)  NULL,
    included_columns_drop     NVARCHAR(MAX)  NULL,
    filter_definition         NVARCHAR(MAX)  NULL,
    keep_index_type           NVARCHAR(60)   NULL,
    drop_index_type           NVARCHAR(60)   NULL,
    keep_is_primary_key       BIT            NOT NULL,
    drop_is_primary_key       BIT            NOT NULL,
    keep_is_unique            BIT            NOT NULL,
    drop_is_unique            BIT            NOT NULL,
    keep_is_unique_constraint BIT            NOT NULL,
    drop_is_unique_constraint BIT            NOT NULL,
    keep_reads                BIGINT         NOT NULL,
    drop_reads                BIGINT         NOT NULL,
    keep_writes               BIGINT         NOT NULL,
    drop_writes               BIGINT         NOT NULL,
    keep_last_read            DATETIME       NULL,
    drop_last_read            DATETIME       NULL,
    keep_last_update          DATETIME       NULL,
    drop_last_update          DATETIME       NULL,
    keep_size_mb              DECIMAL(18, 2) NOT NULL,
    drop_size_mb              DECIMAL(18, 2) NOT NULL,
    suggested_action          NVARCHAR(500)  NOT NULL,
    drop_ddl                  NVARCHAR(MAX)  NOT NULL
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

/*------------------------------------------------------------------------------
  Per-database collection query (executed inside each target database)

  Loads ALL indexes for pairing. Emits only pairs where at least one side is
  a unique index or unique constraint (is_unique = 1 AND is_primary_key = 0).
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
    key_columns_sorted NVARCHAR(MAX) NULL,
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
KeySignaturesSorted AS
(
    SELECT
        icp.object_id,
        icp.index_id,
        STRING_AGG(
            QUOTENAME(icp.column_name)
                + CASE WHEN icp.is_descending_key = 1 THEN N'' DESC'' ELSE N'''' END,
            N'',''
        ) WITHIN GROUP (ORDER BY icp.column_name, icp.is_descending_key) AS key_columns_sorted
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
        kss.key_columns_sorted,
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
    INNER JOIN KeySignaturesSorted AS kss
        ON kss.object_id = i.object_id
       AND kss.index_id = i.index_id
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
        key_columns_sorted,
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
    key_columns_sorted,
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
    key_columns_sorted,
    included_columns,
    used_page_count,
    total_reads,
    total_writes,
    last_read,
    last_update
FROM Eligible;

-- Count unique indexes / unique constraints of interest (not PK)
SELECT @IndexesScanned = COUNT(*)
FROM #IdxEligible
WHERE is_unique = 1
  AND is_primary_key = 0;

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
        k1.key_columns_sorted AS key_columns_sorted_a,
        k2.key_columns_sorted AS key_columns_sorted_b,
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
        CAST(CASE WHEN k1.is_unique = 1 AND k1.is_primary_key = 0 THEN 1 ELSE 0 END AS BIT) AS is_uq_interest_a,
        CAST(CASE WHEN k2.is_unique = 1 AND k2.is_primary_key = 0 THEN 1 ELSE 0 END AS BIT) AS is_uq_interest_b,
        CASE
            WHEN k1.key_columns = k2.key_columns
             AND k1.included_columns = k2.included_columns
             AND k1.filter_definition = k2.filter_definition
             AND k1.type_desc = k2.type_desc
             AND k1.is_unique = k2.is_unique
            THEN N''EXACT_DUPLICATE''

            WHEN k1.key_columns_sorted = k2.key_columns_sorted
            THEN N''DUPLICATE_KEY''

            WHEN k1.filter_definition = k2.filter_definition
             AND LEN(k2.key_columns) > LEN(k1.key_columns)
             AND LEFT(k2.key_columns, LEN(k1.key_columns)) = k1.key_columns
             AND SUBSTRING(k2.key_columns, LEN(k1.key_columns) + 1, 1) = N'',''
            THEN CASE
                    WHEN (k1.is_unique = 1 AND k1.is_primary_key = 0)
                     AND (k2.is_unique = 1 AND k2.is_primary_key = 0)
                    THEN N''LEFT_PREFIX_UNIQUE_OVERLAP''
                    ELSE N''REDUNDANT_LEFT_PREFIX''
                 END

            WHEN k1.filter_definition = k2.filter_definition
             AND LEN(k1.key_columns) > LEN(k2.key_columns)
             AND LEFT(k1.key_columns, LEN(k2.key_columns)) = k2.key_columns
             AND SUBSTRING(k1.key_columns, LEN(k2.key_columns) + 1, 1) = N'',''
            THEN CASE
                    WHEN (k1.is_unique = 1 AND k1.is_primary_key = 0)
                     AND (k2.is_unique = 1 AND k2.is_primary_key = 0)
                    THEN N''LEFT_PREFIX_UNIQUE_OVERLAP''
                    ELSE N''REDUNDANT_LEFT_PREFIX''
                 END

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
            -- PRIMARY KEY / unique constraint are never drop candidates
            WHEN p.is_pk_a = 1 OR p.is_uc_a = 1
            THEN p.index_name_a
            WHEN p.is_pk_b = 1 OR p.is_uc_b = 1
            THEN p.index_name_b
            -- Prefer unique over non-unique when keys overlap
            WHEN p.is_unique_a = 1 AND p.is_unique_b = 0
            THEN p.index_name_a
            WHEN p.is_unique_b = 1 AND p.is_unique_a = 0
            THEN p.index_name_b
            WHEN p.duplicate_type IN (N''REDUNDANT_LEFT_PREFIX'', N''LEFT_PREFIX_UNIQUE_OVERLAP'')
            THEN CASE WHEN p.wider_index_id = p.index_id_a THEN p.index_name_a ELSE p.index_name_b END
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
            WHEN p.is_pk_a = 1 OR p.is_uc_a = 1
            THEN p.index_name_b
            WHEN p.is_pk_b = 1 OR p.is_uc_b = 1
            THEN p.index_name_a
            WHEN p.is_unique_a = 1 AND p.is_unique_b = 0
            THEN p.index_name_b
            WHEN p.is_unique_b = 1 AND p.is_unique_a = 0
            THEN p.index_name_a
            WHEN p.duplicate_type IN (N''REDUNDANT_LEFT_PREFIX'', N''LEFT_PREFIX_UNIQUE_OVERLAP'')
            THEN CASE WHEN p.narrower_index_id = p.index_id_a THEN p.index_name_a ELSE p.index_name_b END
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
      -- Only pairs that involve a unique index or unique constraint
      AND (p.is_uq_interest_a = 1 OR p.is_uq_interest_b = 1)
      -- Never suggest dropping PK/UC as a redundant left-prefix narrower index
      AND NOT (
            p.duplicate_type IN (N''REDUNDANT_LEFT_PREFIX'', N''LEFT_PREFIX_UNIQUE_OVERLAP'')
            AND (
                (p.narrower_index_id = p.index_id_a AND (p.is_pk_a = 1 OR p.is_uc_a = 1))
                OR (p.narrower_index_id = p.index_id_b AND (p.is_pk_b = 1 OR p.is_uc_b = 1))
            )
          )
      -- If both sides are PK/UC, there is no valid DROP INDEX candidate
      AND NOT ((p.is_pk_a = 1 OR p.is_uc_a = 1) AND (p.is_pk_b = 1 OR p.is_uc_b = 1))
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
            WHEN c.duplicate_type IN (N''REDUNDANT_LEFT_PREFIX'', N''LEFT_PREFIX_UNIQUE_OVERLAP'')
            THEN CASE WHEN c.wider_index_id = c.index_id_a THEN c.key_columns_a ELSE c.key_columns_b END
                + N'' (wider) | ''
                + CASE WHEN c.narrower_index_id = c.index_id_a THEN c.key_columns_a ELSE c.key_columns_b END
                + N'' (narrower)''
            WHEN c.key_columns_a = c.key_columns_b
            THEN c.key_columns_a
            WHEN c.key_columns_sorted_a = c.key_columns_sorted_b
            THEN N''SORTED: '' + c.key_columns_sorted_a
                + N'' | KEEP_ORD: ''
                + CASE WHEN c.index_keep = c.index_name_a THEN c.key_columns_a ELSE c.key_columns_b END
                + N'' | DROP_ORD: ''
                + CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.key_columns_a ELSE c.key_columns_b END
            ELSE c.key_columns_sorted_a
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
        CASE WHEN c.index_keep = c.index_name_a THEN c.is_uc_a ELSE c.is_uc_b END AS keep_is_unique_constraint,
        CASE WHEN c.index_drop_candidate = c.index_name_a THEN c.is_uc_a ELSE c.is_uc_b END AS drop_is_unique_constraint,
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
INSERT INTO #DuplicateUniqueIndexes
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
    keep_is_unique_constraint,
    drop_is_unique_constraint,
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
    r.keep_is_unique_constraint,
    r.drop_is_unique_constraint,
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
        WHEN r.duplicate_type = N''LEFT_PREFIX_UNIQUE_OVERLAP''
            THEN N''BLOCKED: Unique left-prefix overlap — narrower unique key is NOT subsumed by wider key; do not drop.''
        WHEN r.drop_is_primary_key = 1 OR r.drop_is_unique_constraint = 1
            THEN N''BLOCKED: Drop candidate is a PRIMARY KEY / UNIQUE constraint — never DROP INDEX; resolve manually.''
        WHEN r.drop_is_unique = 1 AND r.keep_is_unique = 0
            THEN N''REVIEW: Drop candidate enforces uniqueness — confirm constraint coverage before drop.''
        WHEN r.duplicate_type = N''EXACT_DUPLICATE''
            THEN N''DROP duplicate after validating usage stats and that uniqueness remains covered.''
        WHEN r.duplicate_type = N''DUPLICATE_KEY''
             AND CHARINDEX(N''SORTED:'', r.key_columns) = 1
            THEN N''REVIEW: Same key columns in different order — leading key affects seeks; validate before drop.''
        WHEN r.duplicate_type = N''DUPLICATE_KEY''
             AND (r.filter_keep <> r.filter_drop OR r.included_columns_keep <> r.included_columns_drop)
            THEN N''REVIEW: Same key columns with different filter/includes/uniqueness — validate before drop.''
        WHEN r.duplicate_type = N''DUPLICATE_KEY''
            THEN N''DROP overlapping index after validating usage stats and uniqueness coverage.''
        WHEN r.duplicate_type = N''REDUNDANT_LEFT_PREFIX''
            THEN N''REVIEW: Narrower index may be redundant — validate plans and includes.''
        ELSE N''REVIEW: Overlapping indexes involving a unique index/constraint.''
    END AS suggested_action,
    CASE
        WHEN r.duplicate_type = N''LEFT_PREFIX_UNIQUE_OVERLAP''
            THEN N''-- BLOCKED: Unique left-prefix overlap between ''
                + QUOTENAME(r.index_keep) + N'' and '' + QUOTENAME(r.index_drop_candidate)
                + N''. Narrower unique key enforces a stronger uniqueness rule; do not drop.''
        WHEN r.drop_is_primary_key = 1 OR r.drop_is_unique_constraint = 1
            THEN N''-- BLOCKED: '' + QUOTENAME(r.index_drop_candidate)
                + N'' is a PRIMARY KEY / UNIQUE constraint and must not be dropped via DROP INDEX.''
                + CASE WHEN r.drop_is_unique_constraint = 1
                       THEN CHAR(13) + CHAR(10)
                            + N''-- Review: ALTER TABLE '' + QUOTENAME(r.schema_name) + N''.'' + QUOTENAME(r.table_name)
                            + N'' DROP CONSTRAINT '' + QUOTENAME(r.index_drop_candidate) + N'';''
                       ELSE N'''' END
        ELSE N''-- REVIEW BEFORE EXECUTING'' + CHAR(13) + CHAR(10)
            + N''USE '' + QUOTENAME(DB_NAME()) + N'';'' + CHAR(13) + CHAR(10)
            + N''DROP INDEX '' + QUOTENAME(r.index_drop_candidate) + N'' ON ''
            + QUOTENAME(r.schema_name) + N''.'' + QUOTENAME(r.table_name) + N'';''
    END AS drop_ddl
FROM Resolved AS r
WHERE r.drop_is_primary_key = 0
  AND r.drop_is_unique_constraint = 0;

SELECT @PairsFound = @@ROWCOUNT;

IF OBJECT_ID(N''tempdb..#IdxEligible'') IS NOT NULL
    DROP TABLE #IdxEligible;

INSERT INTO #CollectionDiagnostics (database_name, indexes_scanned, pairs_found, status_message)
VALUES (
    DB_NAME(),
    @IndexesScanned,
    @PairsFound,
    N''OK (indexes_scanned = unique indexes/UCs; pairs involve those vs any index)''
);

END TRY
BEGIN CATCH
    IF OBJECT_ID(N''tempdb..#IdxEligible'') IS NOT NULL
        DROP TABLE #IdxEligible;

    INSERT INTO #CollectionDiagnostics (database_name, indexes_scanned, pairs_found, status_message)
    VALUES (DB_NAME(), @IndexesScanned, @PairsFound, LEFT(N''ERROR: '' + ERROR_MESSAGE(), 400));
END CATCH;
';

/*------------------------------------------------------------------------------
  Execute across target databases
------------------------------------------------------------------------------*/
IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    EXEC dbo.sp_DBA_ForEachDatabase
        @Command            = @DuplicateCommand,
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
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @DuplicateCommand;
        BEGIN TRY
            EXEC sys.sp_executesql @SQL;
        END TRY
        BEGIN CATCH
            IF @ShowDiagnostics = 1
                PRINT N'[WARN] Unique-index scan skipped ' + QUOTENAME(@db_name) + N': ' + ERROR_MESSAGE();

            INSERT INTO #CollectionDiagnostics (database_name, indexes_scanned, pairs_found, status_message)
            VALUES (@db_name, 0, 0, LEFT(N'ERROR: ' + ERROR_MESSAGE(), 400));
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

PRINT N'--- Duplicate Unique Index / Unique Constraint Pairs ---';

SELECT
    N'DUPLICATE UNIQUE INDEX ANALYSIS (UQ/UC vs any overlapping index)' AS metric_context,
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
    keep_is_unique_constraint,
    drop_is_unique_constraint,
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
        WHEN drop_reads = 0 AND drop_writes > 0 THEN N'UNUSED - WRITE ONLY (candidate if not blocked)'
        ELSE N'NO USAGE SINCE RESTART'
    END AS drop_usage_status,
    keep_size_mb,
    drop_size_mb,
    suggested_action,
    drop_ddl
FROM #DuplicateUniqueIndexes
ORDER BY
    CASE duplicate_type
        WHEN N'EXACT_DUPLICATE' THEN 1
        WHEN N'DUPLICATE_KEY' THEN 2
        WHEN N'REDUNDANT_LEFT_PREFIX' THEN 3
        WHEN N'LEFT_PREFIX_UNIQUE_OVERLAP' THEN 4
        ELSE 5
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
    SUM(CASE
            WHEN duplicate_type = N'LEFT_PREFIX_UNIQUE_OVERLAP' THEN 0
            WHEN drop_is_unique_constraint = 1 THEN 0
            WHEN drop_is_primary_key = 1 THEN 0
            ELSE drop_size_mb
        END) AS reclaimable_drop_candidate_mb
FROM #DuplicateUniqueIndexes
GROUP BY database_name, duplicate_type
ORDER BY database_name, duplicate_type;

IF NOT EXISTS (SELECT 1 FROM #DuplicateUniqueIndexes)
BEGIN
    PRINT N'No overlapping pairs involving unique indexes / unique constraints for the selected database scope.';
    PRINT N'Check Collection Diagnostics: indexes_scanned = unique indexes/UCs found; pairs_found = overlapping pairs.';
END;

DROP TABLE #DuplicateUniqueIndexes;
DROP TABLE #CollectionDiagnostics;
