/*
================================================================================
Memory Diagnostics — Buffer cache, settings, and memory pressure signals
================================================================================
Description:
    Reviews shared_buffers, work_mem, effective_cache_size, and buffer hit ratio.
    Flags high temp file usage and active memory-heavy queries.

Action:  Buffer hit ratio < 99% on OLTP → increase shared_buffers or reduce seq scans.
         High temp_bytes in pg_stat_statements → lower work_mem per query or optimize sorts.

Criticality: High
================================================================================
*/

SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name IN (
    'shared_buffers', 'effective_cache_size', 'work_mem', 'maintenance_work_mem',
    'huge_pages', 'temp_buffers', 'max_connections'
)
ORDER BY name;

SELECT datname,
       blks_hit,
       blks_read,
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS buffer_hit_pct,
       CASE WHEN blks_hit + blks_read > 0 AND 100.0 * blks_hit / (blks_hit + blks_read) < 99
            THEN 'WARNING: Low buffer hit ratio'
            ELSE 'OK' END AS status
FROM pg_stat_database
WHERE datname = current_database();

SELECT pid, usename, datname,
       round(extract(epoch FROM (now() - query_start))::numeric, 1) AS duration_sec,
       left(query, 100) AS query_snippet
FROM pg_stat_activity
WHERE state = 'active'
  AND wait_event IN ('BufferPin', 'BufferIO', 'Lock')
  AND pid <> pg_backend_pid()
ORDER BY query_start
LIMIT 15;
