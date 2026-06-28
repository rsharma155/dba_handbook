/*
================================================================================
Index Usage Efficiency — Scans, size, and utilization
================================================================================
Description:
    Index vs sequential scan ratio and index access counts.

Action:  Drop unused large indexes after validation; add indexes where seq_scan dominates.

Criticality: Medium
================================================================================
*/

SELECT schemaname, relname,
       seq_scan, seq_tup_read, idx_scan, idx_tup_fetch,
       n_live_tup,
       CASE WHEN seq_scan > coalesce(idx_scan, 0) * 5 AND n_live_tup > 10000
            THEN 'High sequential scans' ELSE 'OK' END AS scan_status
FROM pg_stat_user_tables
ORDER BY seq_scan DESC
LIMIT 25;

SELECT schemaname, relname, indexrelname,
       idx_scan, idx_tup_read, idx_tup_fetch,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC
LIMIT 25;
