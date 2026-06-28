/*
================================================================================
Vacuum Bloat Maintenance — Priority maintenance queue
================================================================================
Description:
    Generates prioritized VACUUM candidates by dead tuple count and table size.

Action:  Run VACUUM (ANALYZE) manually on top tables during low-traffic windows.

Criticality: Medium
================================================================================
*/

SELECT schemaname, relname,
       n_dead_tup,
       pg_size_pretty(pg_total_relation_size(relid)) AS size,
       last_autovacuum,
       format('VACUUM (ANALYZE) %I.%I;', schemaname, relname) AS suggested_command
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC
LIMIT 25;
