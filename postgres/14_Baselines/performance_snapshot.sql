/*
================================================================================
Performance Snapshot — Point-in-time capture for incidents
================================================================================
Description:
    Captures key metrics in one run for before/after comparisons.
    Prefer dba.sp_baseline_capture() when framework is deployed.

Criticality: Medium
================================================================================
*/

SELECT now() AS snapshot_utc, pg_postmaster_start_time() AS instance_start;

SELECT 'Connections' AS area, state AS metric, count(*)::text AS value
FROM pg_stat_activity WHERE backend_type = 'client backend' GROUP BY state
UNION ALL
SELECT 'Database', datname, numbackends::text FROM pg_stat_database WHERE datname = current_database()
UNION ALL
SELECT 'Buffer Hit %', current_database(),
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2)::text
FROM pg_stat_database WHERE datname = current_database();

SELECT wait_event_type, wait_event, count(*) AS sessions
FROM pg_stat_activity
WHERE wait_event IS NOT NULL AND pid <> pg_backend_pid()
GROUP BY wait_event_type, wait_event
ORDER BY sessions DESC
LIMIT 10;
