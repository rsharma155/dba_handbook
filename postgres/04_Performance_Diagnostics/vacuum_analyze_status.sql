/*
================================================================================
Vacuum and Analyze Status — Maintenance health per table
================================================================================
Description:
    Tables needing VACUUM/ANALYZE based on dead tuples and stats age.

Action:  VACUUM ANALYZE on flagged tables; adjust autovacuum storage parameters for hot tables.

Criticality: Medium
================================================================================
*/

SELECT schemaname, relname,
       n_live_tup, n_dead_tup,
       last_vacuum, last_autovacuum,
       last_analyze, last_autoanalyze,
       vacuum_count, autovacuum_count,
       CASE
           WHEN n_dead_tup > 50000 AND last_autovacuum < now() - interval '3 days'
               THEN 'VACUUM recommended'
           WHEN last_analyze IS NULL OR last_analyze < now() - interval '14 days'
               THEN 'ANALYZE recommended'
           ELSE 'OK'
       END AS maintenance_action
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 40;

SELECT datname,
       age(datfrozenxid) AS xid_age,
       current_setting('autovacuum_freeze_max_age')::bigint AS freeze_max_age,
       CASE WHEN age(datfrozenxid) > current_setting('autovacuum_freeze_max_age')::bigint * 0.75
            THEN 'WARNING: Approaching wraparound — prioritize vacuum'
            ELSE 'OK' END AS wraparound_status
FROM pg_database
WHERE datallowconn AND datname NOT IN ('template0', 'template1');
