/*
================================================================================
Connection Pool Audit — Saturation signals for PgBouncer/pgpool
================================================================================
Description:
    Indicators that connection pooling should be used or tuned.
    Run against PostgreSQL; compare with PgBouncer SHOW POOLS separately.

Action:  When numbackends approaches max_connections, deploy PgBouncer in transaction mode.

Criticality: Medium
================================================================================
*/

SELECT (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_connections,
       (SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend') AS current_connections,
       round(100.0 * (SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend') /
             (SELECT setting::int FROM pg_settings WHERE name = 'max_connections'), 2) AS pct_used;

SELECT application_name, count(*) AS sessions,
       count(*) FILTER (WHERE state = 'idle') AS idle,
       count(*) FILTER (WHERE state = 'active') AS active
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY application_name
ORDER BY sessions DESC;

SELECT 'If using PgBouncer: SHOW POOLS; SHOW STATS; on admin console' AS pgbouncer_note;
