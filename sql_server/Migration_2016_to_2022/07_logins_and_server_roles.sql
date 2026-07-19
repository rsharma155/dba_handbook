/*
    Migration 2016 -> 2022 | Logins and server roles
    Export logins separately with sp_help_revlogin before cutover.
    Risk: Read-only
*/
SET NOCOUNT ON;

SELECT
    sp.name AS [LoginName],
    sp.type_desc,
    sp.is_disabled,
    sp.default_database_name,
    sp.default_language_name,
    sp.create_date,
    sp.modify_date,
    CASE WHEN sp.type IN ('S', 'U') THEN LOGINPROPERTY(sp.name, 'PasswordLastSetTime') END AS [PasswordLastSetTime]
FROM sys.server_principals AS sp
WHERE sp.type IN ('S', 'U', 'G')
  AND sp.name NOT LIKE N'##%'
ORDER BY sp.name;

SELECT
    r.name AS [ServerRole],
    m.name AS [MemberLogin]
FROM sys.server_role_members AS rm
JOIN sys.server_principals AS r ON rm.role_principal_id = r.principal_id
JOIN sys.server_principals AS m ON rm.member_principal_id = m.principal_id
WHERE r.type = 'R'
ORDER BY r.name, m.name;

SELECT name AS [SysadminLogin]
FROM sys.syslogins
WHERE sysadmin = 1 AND hasaccess = 1
ORDER BY name;
