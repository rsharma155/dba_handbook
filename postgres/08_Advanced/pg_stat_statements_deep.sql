/*
================================================================================
pg_stat_statements Deep Dive — Regressions, I/O, and temp usage
================================================================================
Description:
    Advanced query analysis: high variance, temp spill, and I/O-heavy queries.

Prerequisite: pg_stat_statements extension

Criticality: High
================================================================================
*/

SELECT round(mean_exec_time::numeric, 2) AS mean_ms,
       round(stddev_exec_time::numeric, 2) AS stddev_ms,
       calls,
       shared_blks_read, temp_blks_written,
       left(query, 180) AS query_snippet
FROM pg_stat_statements
WHERE calls > 50 AND stddev_exec_time > mean_exec_time
ORDER BY stddev_exec_time DESC
LIMIT 15;

SELECT calls, temp_blks_written,
       round(total_exec_time::numeric, 2) AS total_ms,
       left(query, 180) AS query_snippet
FROM pg_stat_statements
WHERE temp_blks_written > 1000
ORDER BY temp_blks_written DESC
LIMIT 15;
