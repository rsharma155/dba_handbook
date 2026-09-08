/*
================================================================================
Effective Permissions for a Login (fn_my_permissions)
================================================================================
Description:
    Shows effective SERVER and DATABASE permissions for a login via EXECUTE AS + fn_my_permissions, plus xp_logininfo group expansion.

Source Attribution:
    Adapted from Kendal Van Dyke's SQL-Server-Scripts
    https://github.com/kendalvandyke/SQL-Server-Scripts
    Original file: Security - Show Permissions For Login (2005+).sql
    Original license requires the author header below to be preserved.
    Free for personal, educational, and internal corporate use; redistribution
    or sale without the author's express written consent is prohibited.

Action:
    Edit DOMAIN\account placeholders before running. Requires IMPERSONATE permission. Revert is included.

Criticality: Medium
Integrated into DBA Handbook: 2026-07-23
================================================================================
*/
-- Impersonate domain login
EXECUTE AS LOGIN = 'DOMAIN\account'

-- Server permissions
SELECT *
FROM fn_my_permissions(NULL, 'SERVER');

-- Datbase permissions
SELECT *
FROM fn_my_permissions(NULL, 'DATABASE');

REVERT;

/* https://docs.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/xp-logininfo-transact-sql */
EXECUTE xp_logininfo @acctname = 'DOMAIN\account'
	, @option = 'all';

