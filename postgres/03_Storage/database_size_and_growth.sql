/*
================================================================================
Database Size and Growth — Capacity overview
================================================================================
Description:
    Database sizes, largest tables, and toast/index breakdown.

Action:  Plan disk capacity; archive or partition tables exceeding retention policy.

Criticality: Medium
================================================================================
*/

SELECT datname,
       pg_size_pretty(pg_database_size(datname)) AS size,
       pg_database_size(datname) AS size_bytes
FROM pg_database
WHERE datallowconn
ORDER BY pg_database_size(datname) DESC;

SELECT schemaname, relname,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       pg_size_pretty(pg_relation_size(relid)) AS table_size,
       pg_size_pretty(pg_indexes_size(relid)) AS indexes_size,
       n_live_tup, n_dead_tup,
       last_vacuum, last_autovacuum
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 30;
