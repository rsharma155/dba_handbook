/*
================================================================================
Statistics Freshness — Stale stats detection
================================================================================
Description:
    Tables with old ANALYZE timestamps or high modification since analyze.

Action:  ANALYZE affected tables; consider autovacuum_analyze_scale_factor per table.

Criticality: Medium
================================================================================
*/

SELECT schemaname, relname,
       n_mod_since_analyze,
       n_live_tup,
       last_analyze, last_autoanalyze,
       CASE
           WHEN n_live_tup > 0 AND n_mod_since_analyze::float / n_live_tup > 0.2
               THEN 'WARNING: >20% rows changed since analyze'
           WHEN coalesce(last_analyze, last_autoanalyze) < now() - interval '30 days'
               THEN 'WARNING: Stats older than 30 days'
           ELSE 'OK'
       END AS stats_status
FROM pg_stat_user_tables
WHERE n_live_tup > 1000
ORDER BY n_mod_since_analyze DESC
LIMIT 40;
