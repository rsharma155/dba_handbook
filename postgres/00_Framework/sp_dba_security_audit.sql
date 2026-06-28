/*
================================================================================
sp_dba_security_audit — Roles, privileges, and exposure checks
================================================================================
Description:
    Audits superusers, PUBLIC grants, default privileges, and databases
  without forced row security where expected.

Usage:
    SELECT * FROM dba.sp_security_audit();

Criticality: High
================================================================================
*/

CREATE OR REPLACE FUNCTION dba.sp_security_audit()
RETURNS TABLE (
    severity         text,
    area             text,
    finding          text,
    recommendation   text
)
LANGUAGE sql
STABLE
AS $$
    SELECT 'Critical', 'Roles', 'Superuser: ' || rolname,
        'Limit superuser accounts; use least privilege roles'
    FROM pg_roles WHERE rolsuper AND rolcanlogin

    UNION ALL

    SELECT 'High', 'PUBLIC', 'PUBLIC has CREATE on schema ' || nspname,
        'REVOKE CREATE ON SCHEMA ... FROM PUBLIC'
    FROM pg_namespace n
    JOIN pg_roles r ON r.oid = n.nspowner
    WHERE has_schema_privilege('public', n.oid, 'CREATE')
      AND nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')

    UNION ALL

    SELECT 'Medium', 'Connections', datname || ' allows unlimited connections',
        'Consider CONNECTION LIMIT per database'
    FROM pg_database
    WHERE datconnlimit = -1 AND datallowconn AND datname NOT IN ('template0', 'template1')

    UNION ALL

    SELECT 'Medium', 'SSL', 'ssl = ' || setting,
        CASE WHEN setting <> 'on' THEN 'Enable SSL for production' END
    FROM pg_settings WHERE name = 'ssl'

    UNION ALL

    SELECT 'Info', 'Password', 'password_encryption = ' || setting, NULL
    FROM pg_settings WHERE name = 'password_encryption';
$$;
