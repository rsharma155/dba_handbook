/*
================================================================================
Wait Events — Current wait snapshot with categories
================================================================================
Description:
    Point-in-time wait events from pg_stat_activity (not cumulative).
    Uses dba.fn_excluded_wait_events() when framework is deployed.

Action:  Top Lock waits → blocking_and_locks.sql. IO waits → disk_io_analysis.sql.

Criticality: High
================================================================================
*/

SELECT now() AS snapshot_time,
       pg_postmaster_start_time() AS instance_start_time,
       'Waits are point-in-time, not cumulative since startup' AS metric_context;

WITH excluded AS (
    SELECT wait_event FROM dba.fn_excluded_wait_events()
    WHERE EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'dba')
    UNION ALL
    SELECT unnest(ARRAY['ClientRead','ClientWrite','Timeout','PgSleep']) WHERE NOT EXISTS (
        SELECT 1 FROM pg_namespace WHERE nspname = 'dba'
    )
)
SELECT wait_event_type, wait_event, count(*) AS sessions,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct,
       CASE
           WHEN wait_event_type = 'Lock' THEN 'Blocking — run blocking_and_locks.sql'
           WHEN wait_event_type = 'IO' THEN 'Storage I/O — run disk_io_analysis.sql'
           WHEN wait_event = 'WalSync' THEN 'WAL sync — review storage and synchronous_commit'
           WHEN wait_event_type = 'LWLock' THEN 'Internal contention — check pg_stat_activity detail'
           ELSE 'See wait_events_reference.sql'
       END AS recommendation
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
  AND pid <> pg_backend_pid()
  AND wait_event NOT IN (SELECT wait_event FROM excluded)
GROUP BY wait_event_type, wait_event
ORDER BY sessions DESC
LIMIT 20;
