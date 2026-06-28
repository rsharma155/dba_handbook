/*
================================================================================
Extension Audit — Installed extensions and versions
================================================================================
Description:
    Lists all extensions with schema, version, and relocation status.
    Flags common production extensions that should be present or updated.

Action:  Keep extensions patched with minor PG upgrades; review untrusted extensions.

Criticality: Low
================================================================================
*/

SELECT e.extname, n.nspname AS schema, e.extversion,
       e.extrelocatable,
       CASE e.extname
           WHEN 'pg_stat_statements' THEN 'Recommended for query diagnostics'
           WHEN 'pgcrypto' THEN 'Cryptographic functions'
           WHEN 'citext' THEN 'Case-insensitive text'
           WHEN 'postgis' THEN 'Geospatial — verify version compatibility'
           ELSE NULL
       END AS notes
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY e.extname;

SELECT 'pg_stat_statements' AS recommended,
       EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') AS installed;
