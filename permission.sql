/*
================================================================================
DBA Essential Scripts — Permissions Setup
================================================================================
Purpose:
    Grant minimum permissions to run diagnostic scripts in this repository.

Platforms:
    Part A — Microsoft SQL Server (run in SSMS/sqlcmd as sysadmin)
    Part B — PostgreSQL (run in psql as superuser; scroll to Part B below)

Customize before running:
    SQL Server:   @LoginName in Part A
    PostgreSQL:   dba_monitor role name / password in Part B

Tiers:
    Monitor     — read-only diagnostics (default)
    Maintenance — index rebuild, UPDATE STATISTICS, VACUUM (optional notes)
    Deploy      — one-time framework install (sysadmin / superuser)
Author:        Ravi Sharma
================================================================================
*/


/* ============================================================================
   PART A — MICROSOFT SQL SERVER
   ============================================================================ */

SET NOCOUNT ON;

DECLARE @LoginName SYSNAME = N'DOMAIN\DBA_Monitor';  -- Windows group/login or SQL login name

PRINT N'=== SQL Server: granting DBA monitor permissions to ' + @LoginName + N' ===';

IF SUSER_SID(@LoginName) IS NULL
BEGIN
    IF @LoginName LIKE N'%\%'
        EXEC(N'CREATE LOGIN ' + QUOTENAME(@LoginName) + N' FROM WINDOWS;');
    ELSE
        RAISERROR(N'SQL login must be created manually before running grants.', 16, 1);
END;

DECLARE @sql NVARCHAR(MAX) = N'
GRANT CONNECT SQL TO ' + QUOTENAME(@LoginName) + N';
GRANT VIEW SERVER STATE TO ' + QUOTENAME(@LoginName) + N';
GRANT VIEW ANY DEFINITION TO ' + QUOTENAME(@LoginName) + N';
GRANT VIEW ANY DATABASE TO ' + QUOTENAME(@LoginName) + N';';
EXEC sys.sp_executesql @sql;

USE msdb;

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @LoginName)
    EXEC(N'CREATE USER ' + QUOTENAME(@LoginName) + N' FOR LOGIN ' + QUOTENAME(@LoginName) + N';');

EXEC sys.sp_addrolemember @rolename = N'db_datareader', @membername = @LoginName;

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'SQLAgentReaderRole')
    EXEC sys.sp_addrolemember @rolename = N'SQLAgentReaderRole', @membername = @LoginName;

DECLARE @DbName SYSNAME;
DECLARE @DbSql NVARCHAR(MAX);

DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4 AND state = 0 AND is_read_only = 0;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @DbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @DbSql = N'
USE ' + QUOTENAME(@DbName) + N';
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N''' + REPLACE(@LoginName, N'''', N'''''') + N''')
    CREATE USER ' + QUOTENAME(@LoginName) + N' FOR LOGIN ' + QUOTENAME(@LoginName) + N';
IF IS_ROLEMEMBER(N''db_datareader'', N''' + REPLACE(@LoginName, N'''', N'''''') + N''') <> 1
    ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@LoginName) + N';';

    BEGIN TRY
        EXEC sys.sp_executesql @DbSql;
    END TRY
    BEGIN CATCH
        PRINT N'Warning: ' + @DbName + N' — ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM db_cur INTO @DbName;
END;

CLOSE db_cur;
DEALLOCATE db_cur;

IF DB_ID(N'DBARepository') IS NOT NULL
BEGIN
    USE DBARepository;
    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @LoginName)
        EXEC(N'CREATE USER ' + QUOTENAME(@LoginName) + N' FOR LOGIN ' + QUOTENAME(@LoginName) + N';');
    IF IS_ROLEMEMBER(N'db_datareader', @LoginName) <> 1
        EXEC sys.sp_addrolemember @rolename = N'db_datareader', @membername = @LoginName;
END;

USE master;

PRINT N'';
PRINT N'SQL Server monitor tier complete.';
PRINT N'';
PRINT N'Read-only scripts covered:';
PRINT N'  sql_server/01_Server_OS through 14_Baselines, Prod_Migration/*';
PRINT N'';
PRINT N'Optional elevated grants (grant only if needed):';
PRINT N'  ALTER SERVER STATE     — clear wait stats (Prod_Migration wait delta)';
PRINT N'  ALTER ANY EVENT SESSION — Extended Events setup';
PRINT N'  db_ddladmin per DB     — index_maintenance_online.sql, UPDATE STATISTICS';
PRINT N'  ALTER DATABASE         — Query Store plan force/unforce';
PRINT N'  sysadmin               — one-time 00_Framework / 00_Repository deploy';
GO


/*
================================================================================
PART B — POSTGRESQL
================================================================================
Executable script: postgres/permission.sql

  psql -U postgres -f postgres/permission.sql

Minimum monitor grants:
  pg_monitor, pg_read_all_stats, pg_read_all_settings
  CONNECT + USAGE/SELECT on dba schema and application schemas

Optional maintenance:
  pg_maintain (PostgreSQL 18+) or superuser for VACUUM/ANALYZE/REINDEX execute paths

One-time deploy (superuser):
  postgres/00_Repository/00_create_repository.sql
  postgres/00_Framework/00_Deploy_Framework.sql
================================================================================
*/
