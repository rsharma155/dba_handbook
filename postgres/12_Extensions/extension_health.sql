/*
================================================================================
Extension Health — Versions, dependencies, and preload status
================================================================================
Description:
    Extension inventory with upgrade recommendations.

Criticality: Low
================================================================================
*/

SELECT e.extname, e.extversion, n.nspname,
       c.description,
       EXISTS (
           SELECT 1 FROM pg_settings
           WHERE name = 'shared_preload_libraries'
             AND setting LIKE '%' || e.extname || '%'
       ) AS in_shared_preload
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
LEFT JOIN pg_description c ON c.objoid = e.oid AND c.classoid = 'pg_extension'::regclass
ORDER BY e.extname;
