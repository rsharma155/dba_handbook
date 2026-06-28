/*
================================================================================
Top Resource Queries — pg_stat_statements ranking
================================================================================
Description:
    Top queries by total time, mean time, calls, and temp I/O.
    Requires pg_stat_statements extension.

Action:  Optimize or index top offenders; reset stats only after capturing baseline.

Criticality: High
================================================================================
*/

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
        RAISE EXCEPTION 'pg_stat_statements not installed. Add to shared_preload_libraries and CREATE EXTENSION.';
    END IF;
END $$;

SELECT calls,
       round(total_exec_time::numeric, 2) AS total_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       round((100 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 2) AS pct_total_time,
       rows,
       shared_blks_hit, shared_blks_read,
       temp_blks_read, temp_blks_written,
       left(query, 200) AS query_snippet
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC
LIMIT 20;

SELECT calls,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       left(query, 200) AS query_snippet
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND calls > 10
ORDER BY mean_exec_time DESC
LIMIT 15;
