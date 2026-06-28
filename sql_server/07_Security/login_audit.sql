/*
================================================================================
SQL Server Login Security Audit
================================================================================
Description:
    Audits SQL Server logins and role memberships. Reports disabled logins,
    password policy non-compliance, sysadmin role members, and sa account status.

Output:
    Multiple result sets: sysadmin members, disabled/enabled logins with
    password policy details, sa account status, and login auditing summary.

Action:
    Review sysadmin members — remove any logins that do not require full
    administrative access. Ensure the sa account is renamed and disabled.
    Enable "Enforce password policy" and "Enforce password expiration" for
    all SQL authentication logins. Disable any unused or test logins.

Criticality: High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

PRINT '--- Sysadmin Role Members ---';
SELECT
    sp.name AS [Login_Name],
    sp.type_desc AS [Login_Type],
    sp.is_disabled AS [Is_Disabled],
    sp.create_date,
    sp.modify_date,
    CASE WHEN sp.name LIKE N'NT SERVICE\%' OR sp.name LIKE N'NT AUTHORITY\%' THEN N'SERVICE ACCOUNT' ELSE N'REVIEW' END AS [Account_Class]
FROM sys.server_role_members AS srm
INNER JOIN sys.server_principals AS sp ON srm.member_principal_id = sp.principal_id
INNER JOIN sys.server_principals AS role ON srm.role_principal_id = role.principal_id
WHERE role.name = N'sysadmin'
ORDER BY sp.name;

PRINT '--- SQL Logins: Policy & Expiration ---';
SELECT
    name AS [Login_Name],
    is_disabled,
    is_policy_checked,
    is_expiration_checked,
    LOGINPROPERTY(name, N'IsLocked') AS [Is_Locked],
    LOGINPROPERTY(name, N'DaysUntilExpiration') AS [Days_Until_Expiration],
    create_date,
    modify_date
FROM sys.sql_logins
WHERE name NOT LIKE N'##%'
ORDER BY is_disabled DESC, name;

PRINT '--- sa Login Status ---';
SELECT
    name,
    is_disabled,
    is_policy_checked,
    create_date,
    CASE WHEN is_disabled = 0 THEN N'WARNING: sa enabled' ELSE N'OK: sa disabled' END AS [Status]
FROM sys.sql_logins
WHERE sid = 0x01;

PRINT '--- Orphaned Windows Logins (no server access) ---';
SELECT name, type_desc, create_date
FROM sys.server_principals
WHERE type IN (N'U', N'G')
  AND name NOT LIKE N'NT SERVICE\%'
  AND name NOT LIKE N'NT AUTHORITY\%'
  AND name NOT LIKE N'NT MACHINE\%'
ORDER BY name;
