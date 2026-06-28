/*
================================================================================
CPU Utilization — Active query CPU and backend load
================================================================================
Description:
    Shows backends by state, long-running active queries, and parallel workers.
    PostgreSQL does not expose historical CPU ring buffers like SQL Server;
    use OS tools (top, pidstat) alongside this for host CPU.

Output:  Session counts, top CPU-time queries (from pg_stat_statements if available).

Action:  High active count + long queries → run top_resource_queries.sql.
         Many parallel workers → review max_parallel_workers_per_gather.

Criticality: High
================================================================================
*/

SELECT state, count(*) AS session_count,
       'Point-in-time from pg_stat_activity' AS metric_context
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY session_count DESC;

SELECT pid, usename, datname, application_name,
       round(extract(epoch FROM (now() - query_start))::numeric, 1) AS duration_sec,
       wait_event_type, wait_event,
       left(query, 120) AS query_snippet
FROM pg_stat_activity
WHERE state = 'active'
  AND pid <> pg_backend_pid()
ORDER BY query_start
LIMIT 20;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
        RAISE NOTICE 'See top_resource_queries.sql for pg_stat_statements CPU ranking.';
    ELSE
        RAISE NOTICE 'Install pg_stat_statements for query-level CPU history.';
    END IF;
END $$;
