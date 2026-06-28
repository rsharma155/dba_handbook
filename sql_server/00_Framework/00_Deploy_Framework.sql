/*
==============================================================================
00_Deploy_Framework.sql - Auto-deploy all DBA framework objects
==============================================================================
Scans the 00_Framework directory for .sql files and executes them in order
using xp_cmdshell + sqlcmd. Excludes 00_Install_Framework.sql, README.md,
and itself.

Prerequisites:
  - xp_cmdshell must be enabled (script enables it temporarily)
  - sqlcmd must be available on the server's PATH
  - Run in the context of your admin database

Usage:
    1. Update @TargetDB to your admin database name
    2. Execute in SSMS / sqlcmd
==============================================================================
*/
SET NOCOUNT ON;

DECLARE @TargetDB       SYSNAME         = N'master';   -- Change to your admin DB
DECLARE @FrameworkDir   NVARCHAR(500)   = N'C:\Users\Admin\Documents\dba_essential_scripts\dba_essential_scripts\00_Framework';
DECLARE @ServerName     SYSNAME         = @@SERVERNAME;

-- Step 1: Enable xp_cmdshell if not already
PRINT N'Enabling xp_cmdshell...';
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 1;
RECONFIGURE;

-- Step 2: Gather .sql files (sorted by name)
IF OBJECT_ID(N'tempdb..#Files') IS NOT NULL DROP TABLE #Files;
CREATE TABLE #Files (
    Id        INT IDENTITY(1,1) PRIMARY KEY,
    FileName  NVARCHAR(500),
    FullPath  NVARCHAR(1000)
);

DECLARE @file_list TABLE (line NVARCHAR(4000));
DECLARE @cmd NVARCHAR(4000) = N'dir /b "' + @FrameworkDir + N'\*.sql"';

INSERT INTO @file_list
EXEC xp_cmdshell @cmd;

INSERT INTO #Files (FileName)
SELECT RTRIM(LTRIM(line))
FROM @file_list
WHERE line IS NOT NULL
  AND line NOT LIKE N'00_Install_Framework%'
  AND line NOT LIKE N'00_Deploy_Framework%'
  AND line NOT LIKE N'README%'
ORDER BY line;

-- Step 3: Execute each file via sqlcmd
DECLARE @Id INT, @FileName NVARCHAR(500), @FullPath NVARCHAR(1000);
DECLARE @sqlcmd NVARCHAR(4000);
DECLARE @result TABLE (output NVARCHAR(4000));

SELECT @Id = MIN(Id) FROM #Files;

WHILE @Id IS NOT NULL
BEGIN
    SELECT @FileName = FileName FROM #Files WHERE Id = @Id;
    SET @FullPath = @FrameworkDir + N'\' + @FileName;

    PRINT N'--- Deploying: ' + @FileName + N' ---';

    SET @sqlcmd = N'sqlcmd -S "' + @ServerName + N'" -E -d "' + @TargetDB + N'" -i "' + @FullPath + N'" -b';

    DELETE FROM @result;
    INSERT INTO @result
    EXEC xp_cmdshell @sqlcmd;

    -- Print output
    SELECT output FROM @result WHERE output IS NOT NULL;

    SELECT @Id = MIN(Id) FROM #Files WHERE Id > @Id;
END;

-- Step 4: Cleanup
DROP TABLE #Files;

PRINT N'';
PRINT N'==============================================================================';
PRINT N'Deployment complete.';
PRINT N'All framework objects have been deployed to [' + @TargetDB + N'].';
PRINT N'==============================================================================';
GO
