/*
================================================================================
Bloat Analysis — Dead tuples and estimated table bloat
================================================================================
Description:
    Identifies tables with high dead tuple ratio and vacuum lag.
    For precise bloat estimates, use pgstattuple extension (optional).

Action:  Run VACUUM (ANALYZE) on flagged tables; tune autovacuum per table if needed.

Criticality: Medium
================================================================================
*/

SELECT schemaname, relname,
       n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
       last_vacuum, last_autovacuum, last_analyze, last_autoanalyze,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       CASE
           WHEN n_dead_tup > 100000 AND coalesce(last_autovacuum, 'epoch'::timestamptz) < now() - interval '7 days'
               THEN 'CRITICAL: High dead tuples, stale vacuum'
           WHEN n_dead_tup > 10000 AND n_dead_tup > n_live_tup
               THEN 'WARNING: Dead tuples exceed live tuples'
           ELSE 'OK'
       END AS bloat_status
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC
LIMIT 40;
