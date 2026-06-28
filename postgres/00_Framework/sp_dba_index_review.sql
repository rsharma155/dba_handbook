/*
================================================================================
sp_dba_index_review — Index usage, bloat signals, and missing FK indexes
================================================================================
Description:
    Reports unused indexes, high sequential scan tables, and foreign keys
    without supporting indexes across the current database.

Usage:
    SELECT * FROM dba.sp_index_review(min_size_mb => 10);

Criticality: Medium
================================================================================
*/

CREATE OR REPLACE FUNCTION dba.sp_index_review(min_size_mb integer DEFAULT 10)
RETURNS TABLE (
    finding_type     text,
    schema_name      text,
    object_name      text,
    index_name       text,
    detail           text,
    recommendation   text
)
LANGUAGE sql
STABLE
AS $$
    -- Unused indexes (never scanned since stats reset)
    SELECT
        'Unused Index',
        schemaname,
        relname,
        indexrelname,
        format('Size: %s; idx_scan=%s', pg_size_pretty(pg_relation_size(indexrelid)), idx_scan),
        'Validate with business; consider DROP INDEX CONCURRENTLY after monitoring'
    FROM pg_stat_user_indexes
    WHERE idx_scan = 0
      AND pg_relation_size(indexrelid) >= min_size_mb * 1024 * 1024
      AND indexrelname NOT LIKE '%_pkey'

    UNION ALL

    -- High seq scan vs index scan ratio
    SELECT
        'High Sequential Scans',
        schemaname,
        relname,
        NULL,
        format('seq_scan=%s, idx_scan=%s, rows=%s',
               seq_scan, idx_scan, n_live_tup),
        'Review query plans; add selective indexes where appropriate'
    FROM pg_stat_user_tables
    WHERE seq_scan > idx_scan * 10
      AND n_live_tup > 10000

    UNION ALL

    -- FK without index on referencing column
    SELECT
        'Missing FK Index',
        n.nspname,
        c.relname,
        con.conname,
        format('FK references %s.%s', fn.nspname, fc.relname),
        'CREATE INDEX CONCURRENTLY on FK column to speed joins and cascades'
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_class fc ON fc.oid = con.confrelid
    JOIN pg_namespace fn ON fn.oid = fc.relnamespace
    WHERE con.contype = 'f'
      AND NOT EXISTS (
          SELECT 1 FROM pg_index i
          WHERE i.indrelid = con.conrelid
            AND (i.indkey::smallint[])[0] = (con.conkey::smallint[])[0]
      );
$$;
