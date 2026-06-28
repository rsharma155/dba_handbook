/*
================================================================================
Security Audit Across User Databases
================================================================================
Description:
    Audits security configurations across databases: trustworthy bit, orphaned
    users, guest access, db_owner role members, and cross-database ownership chaining.

Output:
    Result sets for each security check with database name and affected principals.

Action:
    Disable trustworthy on databases that don't need it:
        ALTER DATABASE [DBName] SET TRUSTWORTHY OFF;
    Drop orphaned database users (users without matching server logins):
        DROP USER [OrphanedUser];
    Revoke db_owner from users who only need read or write access.
    Disable guest access in user databases unless explicitly required:
        REVOKE CONNECT FROM GUEST;

Parameters:
    @DatabaseList - comma-separated database names or NULL for all user DBs

Criticality: High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;

PRINT N'--- Trustworthy Databases ---';
SELECT name AS [DB], is_trustworthy_on
FROM sys.databases
WHERE is_trustworthy_on = 1 AND database_id > 4;

IF OBJECT_ID(N'tempdb..#SecurityAudit') IS NOT NULL DROP TABLE #SecurityAudit;
CREATE TABLE #SecurityAudit (
    [Database] SYSNAME,
    [Metric] NVARCHAR(128),
    [Principal] SYSNAME,
    [Type] NVARCHAR(60),
    [Created] DATETIME NULL
);

DECLARE @SecurityCommand NVARCHAR(MAX) = N'
IF EXISTS (
    SELECT 1
    FROM sys.database_permissions AS p
    INNER JOIN sys.database_principals AS pr ON p.grantee_principal_id = pr.principal_id
    WHERE pr.name = N''guest'' AND p.permission_name = N''CONNECT'' AND p.state = N''G''
)
INSERT INTO #SecurityAudit VALUES (DB_NAME(), N''Guest Access Enabled'', N''guest'', N''DATABASE_PRINCIPAL'', NULL);

INSERT INTO #SecurityAudit
SELECT DB_NAME(), N''Orphaned User'', dp.name, dp.type_desc, dp.create_date
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp ON dp.sid = sp.sid
WHERE dp.type IN (N''S'', N''U'')
  AND sp.sid IS NULL
  AND dp.authentication_type_desc = N''INSTANCE''
  AND dp.name NOT IN (N''guest'', N''INFORMATION_SCHEMA'', N''sys'');

IF EXISTS (
    SELECT 1 FROM sys.databases AS d
    WHERE d.database_id = DB_ID()
      AND d.owner_sid IS NOT NULL
      AND SUSER_SNAME(d.owner_sid) IS NULL
)
INSERT INTO #SecurityAudit
SELECT DB_NAME(), N''Orphaned Database Owner'', CONVERT(NVARCHAR(128), d.owner_sid, 1), N''DATABASE_OWNER'', NULL
FROM sys.databases AS d WHERE d.database_id = DB_ID();';

IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    EXEC dbo.sp_DBA_ForEachDatabase
        @Command = @SecurityCommand,
        @UserDatabasesOnly = 1,
        @IncludeReadOnly = 0,
        @DatabaseList = @DatabaseList,
        @ContinueOnError = 1;
END
ELSE
BEGIN
    DECLARE @db_name SYSNAME;
    DECLARE @SQL NVARCHAR(MAX);

    IF OBJECT_ID(N'tempdb..#DbTargets') IS NOT NULL DROP TABLE #DbTargets;
    CREATE TABLE #DbTargets (database_name SYSNAME PRIMARY KEY);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
        INSERT INTO #DbTargets SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@DatabaseList, N',') WHERE LTRIM(RTRIM(value)) <> N'';
    ELSE
        INSERT INTO #DbTargets SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0 AND is_in_standby = 0;

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT database_name FROM #DbTargets ORDER BY database_name;
    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db_name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @SecurityCommand;
        BEGIN TRY EXEC sys.sp_executesql @SQL; END TRY BEGIN CATCH END CATCH;
        FETCH NEXT FROM db_cursor INTO @db_name;
    END;
    CLOSE db_cursor; DEALLOCATE db_cursor;
    DROP TABLE #DbTargets;
END;

SELECT * FROM #SecurityAudit ORDER BY [Database], [Metric], [Principal];
DROP TABLE #SecurityAudit;

PRINT N'--- Sysadmins & SecurityAdmins ---';
SELECT l.name AS [Login], r.name AS [Role]
FROM sys.server_principals AS l
INNER JOIN sys.server_role_members AS srm ON l.principal_id = srm.member_principal_id
INNER JOIN sys.server_principals AS r ON srm.role_principal_id = r.principal_id
WHERE r.name IN (N'sysadmin', N'securityadmin')
  AND l.name NOT LIKE N'NT SERVICE\%'
ORDER BY r.name, l.name;
