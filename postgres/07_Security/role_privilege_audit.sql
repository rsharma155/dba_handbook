/*
================================================================================
Role and Privilege Audit — Grants, superusers, and exposure
================================================================================
Description:
    Lists role memberships, dangerous grants, and object-level privileges.

Action:  Revoke excessive grants; enforce least privilege; rotate superuser accounts.

Criticality: High
================================================================================
*/

SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication
FROM pg_roles
WHERE rolcanlogin
ORDER BY rolsuper DESC, rolname;

SELECT grantor, grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee IN ('PUBLIC', 'authenticated', 'anon')
   OR grantee IN (SELECT rolname FROM pg_roles WHERE rolcanlogin AND NOT rolsuper)
ORDER BY table_schema, table_name, grantee
LIMIT 100;

SELECT nspname,
       has_schema_privilege('public', oid, 'CREATE') AS public_can_create
FROM pg_namespace
WHERE nspname NOT LIKE 'pg_%' AND nspname <> 'information_schema';
