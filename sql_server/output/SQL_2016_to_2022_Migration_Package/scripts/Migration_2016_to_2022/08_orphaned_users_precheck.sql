/*
    Migration 2016 -> 2022 | Orphaned database users (pre/post migration)
    Run after restore on target; fix with ALTER USER ... WITH LOGIN = ...
    Risk: Read-only

    Optimized for multi-database instances:
    - Short LOCK_TIMEOUT so a blocked DB does not stall the whole scan
    - Skips offline / restoring / standby databases
    - Uses a set-based DB list + WHILE (no open server-side cursor across long work)
*/
SET NOCOUNT ON;
SET LOCK_TIMEOUT 3000;

IF OBJECT_ID('tempdb..#Orphans') IS NOT NULL DROP TABLE #Orphans;
CREATE TABLE #Orphans (
    DatabaseName SYSNAME NOT NULL,
    OrphanUser   SYSNAME NOT NULL,
    UserType     CHAR(1) NOT NULL,
    ScanNote     NVARCHAR(400) NULL
);

IF OBJECT_ID('tempdb..#DbList') IS NOT NULL DROP TABLE #DbList;
CREATE TABLE #DbList (
    RowId INT IDENTITY(1,1) PRIMARY KEY,
    DatabaseName SYSNAME NOT NULL
);

INSERT INTO #DbList (DatabaseName)
SELECT name
FROM sys.databases
WHERE database_id > 4
  AND state = 0
  AND is_read_only = 0
  AND ISNULL(is_in_standby, 0) = 0
ORDER BY name;

DECLARE @i INT = 1, @max INT = (SELECT COUNT(*) FROM #DbList);
DECLARE @db SYSNAME, @sql NVARCHAR(MAX);

WHILE @i <= @max
BEGIN
    SELECT @db = DatabaseName FROM #DbList WHERE RowId = @i;

    SET @sql = N'
USE ' + QUOTENAME(@db) + N';
INSERT INTO #Orphans (DatabaseName, OrphanUser, UserType, ScanNote)
SELECT DB_NAME(), dp.name, dp.type, NULL
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp ON dp.sid = sp.sid
WHERE dp.type = ''S''
  AND dp.name NOT IN (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'')
  AND dp.sid IS NOT NULL
  AND sp.sid IS NULL;';

    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #Orphans (DatabaseName, OrphanUser, UserType, ScanNote)
        VALUES (@db, N'(scan skipped)', N'!', LEFT(ERROR_MESSAGE(), 400));
    END CATCH;

    SET @i += 1;
END;

SELECT DatabaseName, OrphanUser, UserType, ScanNote
FROM #Orphans
ORDER BY DatabaseName, OrphanUser;

-- Remediation template (review before executing):
SELECT
    DatabaseName,
    N'USE ' + QUOTENAME(DatabaseName) + N'; ALTER USER '
        + QUOTENAME(OrphanUser) + N' WITH LOGIN = ' + QUOTENAME(OrphanUser) + N';' AS [FixScript]
FROM #Orphans
WHERE UserType = 'S'
ORDER BY DatabaseName, OrphanUser;

PRINT 'Tip: For 100+ databases, run during a maintenance window. Databases that time out appear with UserType = !.';
