/*
================================================================================
Duplicate Indexes — Same column sets (key columns)
================================================================================
Description:
    Finds indexes on identical leading key columns within the same table.

Action:  Drop redundant index after confirming included columns and usage.

Criticality: Medium
================================================================================
*/

WITH index_cols AS (
    SELECT
        n.nspname AS schema_name,
        t.relname AS table_name,
        i.relname AS index_name,
        array_agg(a.attname ORDER BY k.n) AS key_columns
    FROM pg_index ix
    JOIN pg_class t ON t.oid = ix.indrelid
    JOIN pg_class i ON i.oid = ix.indexrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    JOIN LATERAL unnest(ix.indkey) WITH ORDINALITY AS k(attnum, n) ON true
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
    WHERE NOT ix.indisprimary
    GROUP BY n.nspname, t.relname, i.relname
)
SELECT i1.schema_name, i1.table_name,
       i1.index_name AS index_1,
       i2.index_name AS index_2,
       i1.key_columns
FROM index_cols i1
JOIN index_cols i2
  ON i1.schema_name = i2.schema_name
 AND i1.table_name = i2.table_name
 AND i1.key_columns = i2.key_columns
 AND i1.index_name < i2.index_name
ORDER BY i1.schema_name, i1.table_name;
