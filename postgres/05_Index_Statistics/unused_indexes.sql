/*
================================================================================
Unused Indexes — Zero-scan indexes above size threshold
================================================================================
Description:
    Indexes with idx_scan = 0 since last stats reset (post restart or pg_stat_reset).

Action:  Confirm with business; DROP INDEX CONCURRENTLY during maintenance window.

Criticality: Medium
================================================================================
*/

SELECT schemaname, relname, indexrelname,
       idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
       pg_relation_size(indexrelid) AS size_bytes,
       'Consider DROP INDEX CONCURRENTLY after monitoring period' AS recommendation
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexrelname NOT LIKE '%_pkey'
  AND pg_relation_size(indexrelid) > 10 * 1024 * 1024
ORDER BY pg_relation_size(indexrelid) DESC;
