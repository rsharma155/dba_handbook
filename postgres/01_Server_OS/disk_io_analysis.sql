/*
================================================================================
Disk I/O Analysis — Per-table and database I/O statistics
================================================================================
Description:
    Ranks databases and tables by blocks read/written and checkpoint impact.
    Correlates with checkpoint activity from pg_stat_bgwriter.

Action:  High heap_blks_read → missing indexes or insufficient cache.
         High idx_blks_read on small tables → review index usage.

Criticality: High
================================================================================
*/

SELECT datname,
       pg_size_pretty(pg_database_size(datname)) AS db_size,
       blks_read, blks_hit,
       tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted
FROM pg_stat_database
WHERE datname NOT IN ('template0', 'template1')
ORDER BY blks_read DESC;

SELECT schemaname, relname,
       heap_blks_read, heap_blks_hit,
       idx_blks_read, idx_blks_hit,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       round(100.0 * heap_blks_hit / nullif(heap_blks_hit + heap_blks_read, 0), 2) AS heap_hit_pct
FROM pg_statio_user_tables
ORDER BY heap_blks_read DESC
LIMIT 25;

SELECT checkpoints_timed, checkpoints_req,
       checkpoint_write_time, checkpoint_sync_time,
       buffers_checkpoint, buffers_clean, buffers_backend,
       CASE WHEN checkpoints_req > checkpoints_timed * 2
            THEN 'WARNING: Frequent requested checkpoints — tune max_wal_size'
            ELSE 'OK' END AS checkpoint_status
FROM pg_stat_bgwriter;
