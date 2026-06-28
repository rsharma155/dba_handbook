/*
================================================================================
sp_DBA_SecurityAudit — Comprehensive security audit across databases
================================================================================
Checks for orphaned users, sysadmin members, trustworthy databases, guest
access, password policies, and dangerous permissions.

Usage:
    EXEC dbo.sp_DBA_SecurityAudit;
    EXEC dbo.sp_DBA_SecurityAudit @DatabaseList = N'SalesDB';
    EXEC dbo.sp_DBA_SecurityAudit @IncludeSysadminCheck = 1;
================================================================================
*/
IF OBJECT_ID(N'dbo.sp_DBA_SecurityAudit', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DBA_SecurityAudit AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_DBA_SecurityAudit
    @DatabaseList           NVARCHAR(MAX) = NULL,
    @IncludeReadOnly        BIT = 0,
    @IncludeSysadminCheck   BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    -- Section 1: Server-Level Security
    IF @IncludeSysadminCheck = 1
    BEGIN
        PRINT '--- Sysadmin Members ---';
        SELECT
            p.name AS LoginName,
            p.type_desc AS LoginType,
            p.create_date,
            p.is_disabled,
            p.default_database_name
        FROM sys.server_principals AS p
        INNER JOIN sys.server_role_members AS rm ON p.principal_id = rm.member_principal_id
        INNER JOIN sys.server_principals AS r ON rm.role_principal_id = r.principal_id
        WHERE r.name = N'sysadmin'
        ORDER BY p.name;

        PRINT '--- SQL Logins with Weak Policies ---';
        SELECT
            name AS LoginName,
            is_disabled,
            is_policy_checked,
            is_expiration_checked,
            login_history.last_login
        FROM sys.sql_logins AS sl
        OUTER APPLY (
            SELECT MAX(login_time) AS last_login
            FROM sys.dm_exec_sessions
            WHERE login_name = sl.name
        ) AS login_history
        WHERE sl.is_policy_checked = 0 OR sl.is_expiration_checked = 0
        ORDER BY sl.name;

        PRINT '--- Logins with sysadmin-like Permissions ---';
        SELECT
            p.name AS PrincipalName,
            p.type_desc,
            perm.permission_name,
            perm.state_desc
        FROM sys.server_principals AS p
        INNER JOIN sys.server_permissions AS perm ON p.principal_id = perm.grantee_principal_id
        WHERE perm.permission_name IN ('CONTROL SERVER','ALTER ANY DATABASE','ALTER ANY LOGIN')
          AND p.name NOT IN ('sa')
          AND p.type NOT IN ('R')
        ORDER BY p.name;
    END;

    -- Section 2: Per-Database Security
    IF OBJECT_ID(N'tempdb..#SecAuditDbs') IS NOT NULL DROP TABLE #SecAuditDbs;
    CREATE TABLE #SecAuditDbs (database_id INT NOT NULL PRIMARY KEY, database_name SYSNAME NOT NULL);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
    BEGIN
        INSERT INTO #SecAuditDbs (database_id, database_name)
        SELECT d.database_id, d.name
        FROM sys.databases AS d
        INNER JOIN (
            SELECT LTRIM(RTRIM(value)) AS database_name
            FROM STRING_SPLIT(@DatabaseList, N',')
            WHERE LTRIM(RTRIM(value)) <> N''
        ) AS req ON req.database_name = d.name
        WHERE d.state = 0 AND d.is_in_standby = 0;
    END
    ELSE
    BEGIN
        INSERT INTO #SecAuditDbs (database_id, database_name)
        SELECT database_id, name FROM sys.databases
        WHERE state = 0 AND is_in_standby = 0 AND database_id > 4
          AND (@IncludeReadOnly = 1 OR is_read_only = 0);
    END;

    -- Trustworthy databases
    PRINT '--- Trustworthy Databases ---';
    SELECT
        d.name AS DatabaseName,
        d.is_trustworthy_on,
        SUSER_SNAME(d.owner_sid) AS DBOwner
    FROM sys.databases AS d
    WHERE d.is_trustworthy_on = 1 AND d.database_id > 4;

    -- Orphaned users (per database)
    IF OBJECT_ID(N'tempdb..#OrphanedUsers') IS NOT NULL DROP TABLE #OrphanedUsers;
    CREATE TABLE #OrphanedUsers (
        DatabaseName SYSNAME, UserName SYSNAME, UserType VARCHAR(20),
        CreateDate DATETIME, LastLogin DATETIME
    );

    DECLARE @db_id INT, @db_name SYSNAME, @sql NVARCHAR(MAX);

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_id, database_name FROM #SecAuditDbs ORDER BY database_name;

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db_id, @db_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SET @sql = N'USE ' + QUOTENAME(@db_name) + N';
            INSERT INTO #OrphanedUsers
            SELECT
                DB_NAME(),
                dp.name,
                dp.type_desc,
                dp.create_date,
                NULL
            FROM sys.database_principals AS dp
            LEFT JOIN sys.server_principals AS sp ON dp.sid = sp.sid
            WHERE sp.sid IS NULL
              AND dp.type IN (''S'',''U'',''G'')
              AND dp.name NOT IN (''guest'',''sys'',''dbo'',''INFORMATION_SCHEMA'')
              AND dp.sid IS NOT NULL
              AND dp.sid <> 0x00;';
            EXEC sys.sp_executesql @sql;
        END TRY
        BEGIN CATCH
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @db_id, @db_name;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    PRINT '--- Orphaned Database Users ---';
    SELECT * FROM #OrphanedUsers ORDER BY DatabaseName, UserName;

    -- Guest access
    IF OBJECT_ID(N'tempdb..#GuestAccess') IS NOT NULL DROP TABLE #GuestAccess;
    CREATE TABLE #GuestAccess (DatabaseName SYSNAME, HasConnect BIT);

    DECLARE guest_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM #SecAuditDbs ORDER BY database_name;

    OPEN guest_cursor;
    FETCH NEXT FROM guest_cursor INTO @db_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            SET @sql = N'USE ' + QUOTENAME(@db_name) + N';
            INSERT INTO #GuestAccess
            SELECT DB_NAME(), CASE WHEN EXISTS (
                SELECT 1 FROM sys.database_permissions AS p
                INNER JOIN sys.database_principals AS pr ON p.grantee_principal_id = pr.principal_id
                WHERE pr.name = N''guest'' AND p.permission_name = N''CONNECT'' AND p.state = N''G''
            ) THEN 1 ELSE 0 END;';
            EXEC sys.sp_executesql @sql;
        END TRY
        BEGIN CATCH
        END CATCH;

        FETCH NEXT FROM guest_cursor INTO @db_name;
    END;

    CLOSE guest_cursor;
    DEALLOCATE guest_cursor;

    PRINT '--- Guest CONNECT Access ---';
    SELECT * FROM #GuestAccess WHERE HasConnect = 1;

    -- DB owners
    PRINT '--- Database Owners ---';
    SELECT
        d.name AS DatabaseName,
        SUSER_SNAME(d.owner_sid) AS OwnerLogin,
        d.is_trustworthy_on
    FROM sys.databases AS d
    INNER JOIN #SecAuditDbs AS db ON db.database_id = d.database_id
    WHERE d.database_id > 4
    ORDER BY d.name;

    -- Cleanup
    DROP TABLE #SecAuditDbs;
    DROP TABLE #OrphanedUsers;
    DROP TABLE #GuestAccess;
END;
GO
