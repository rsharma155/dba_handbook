/*
================================================================================
Generate Enable/Disable replicate_ddl Statements
================================================================================
Description:
    Scripts sp_changepublication statements to enable or disable replicate_ddl for publications.

Source Attribution:
    Adapted from Kendal Van Dyke's SQL-Server-Scripts
    https://github.com/kendalvandyke/SQL-Server-Scripts
    Original file: Replication - Generate enable & disable replicate DDL statements (2005+).sql
    Original license requires the author header below to be preserved.
    Free for personal, educational, and internal corporate use; redistribution
    or sale without the author's express written consent is prohibited.

Action:
    Run on publisher. Review before executing — disabling DDL replication can leave subscribers out of sync on schema changes.

Criticality: Low
Integrated into DBA Handbook: 2026-07-23
================================================================================
*/
-- Execute in published database on publisher to generate scripts which enable\diable DDL replication
-- Value = 0 indicates DO NOT replicate DDL changes
-- Value = 1 indicates DO replicate DDL changes
SELECT 'exec sp_changepublication @publication = N''' + name + ''', @property = N''replicate_ddl'', @value = N''0'''
FROM syspublications WITH (NOLOCK)
ORDER BY name

