/*
================================================================================
Autovacuum Health — Workers, settings, and table-level tuning
================================================================================
Description:
    Autovacuum configuration and tables with custom storage parameters.

Action:  Increase autovacuum_max_workers on large catalogs; per-table autovacuum for hot tables.

Criticality: Medium
================================================================================
*/

SELECT name, setting, unit FROM pg_settings
WHERE name LIKE 'autovacuum%'
ORDER BY name;

SELECT schemaname, relname,
       reloptions,
       n_dead_tup, last_autovacuum
FROM pg_stat_user_tables t
JOIN pg_class c ON c.relname = t.relname
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = t.schemaname
WHERE reloptions IS NOT NULL
ORDER BY n_dead_tup DESC
LIMIT 20;

SELECT count(*) AS autovacuum_workers_active
FROM pg_stat_activity
WHERE query LIKE 'autovacuum:%';
