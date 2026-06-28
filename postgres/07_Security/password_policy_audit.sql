/*
================================================================================
Password Policy Audit — Authentication methods and password settings
================================================================================
Description:
    Reviews password_encryption, auth settings, and roles without password expiry
    (PostgreSQL uses external IAM/LDAP or pg_hba for enterprise auth).

Action:  Use scram-sha-256; avoid trust auth in production; integrate SSO where possible.

Criticality: Medium
================================================================================
*/

SELECT name, setting FROM pg_settings
WHERE name IN ('password_encryption', 'authentication_timeout', 'db_user_namespace');

SELECT rolname, rolvaliduntil,
       CASE WHEN rolvaliduntil IS NOT NULL AND rolvaliduntil < now()
            THEN 'EXPIRED' WHEN rolcanlogin THEN 'ACTIVE' ELSE 'NOLOGIN' END AS status
FROM pg_roles
WHERE rolcanlogin
ORDER BY rolname;

-- Review pg_hba.conf externally; this query lists expected auth methods in use
SELECT 'Review pg_hba.conf for trust/peer on non-local connections' AS recommendation;
