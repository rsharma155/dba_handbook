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
    2. Set @ExecuteDeployment = 1 and @AllowProductionChanges = 1
    3. Execute in SSMS / sqlcmd

Safety:
  - Defaults to dry run; no configuration changes or deployment actions occur
  - Requires both @ExecuteDeployment = 1 and @AllowProductionChanges = 1

Persistence:
  - Executes child scripts against @TargetDB when explicitly enabled
  - Temporarily enables xp_cmdshell when needed and restores prior settings
==============================================================================
*/
SET NOCOUNT ON;

DECLARE @TargetDB       SYSNAME         = N'master';   -- Change to your admin DB
DECLARE @FrameworkDir   NVARCHAR(500)   = N'C:\Users\Admin\Documents\dba_essential_scripts\dba_essential_scripts\00_Framework';
DECLARE @ServerName     SYSNAME         = @@SERVERNAME;
DECLARE @ExecuteDeployment BIT          = 0;           -- 1 = execute deployment
DECLARE @AllowProductionChanges BIT     = 0;           -- must also be 1 to mutate

PRINT N'=== DBA FRAMEWORK DEPLOYMENT ===';
PRINT N'Mode: '
    + CASE WHEN @ExecuteDeployment = 1 AND @AllowProductionChanges = 1 THEN N'EXECUTE'
           ELSE N'DRY RUN - set @ExecuteDeployment = 1 and @AllowProductionChanges = 1 to apply' END;

IF @ExecuteDeployment <> 1 OR @AllowProductionChanges <> 1
BEGIN
    PRINT N'DRY RUN complete. No action was taken; xp_cmdshell was not changed and no framework scripts were deployed.';
    PRINT N'Target database would be: [' + @TargetDB + N']';
    PRINT N'Framework directory would be: ' + @FrameworkDir;
    RETURN;
END;

DECLARE @ShowAdvancedWasEnabled BIT = (
    SELECT CAST(value_in_use AS BIT)
    FROM sys.configurations
    WHERE name = N'show advanced options'
);
DECLARE @XpCmdShellWasEnabled BIT = (
    SELECT CAST(value_in_use AS BIT)
    FROM sys.configurations
    WHERE name = N'xp_cmdshell'
);

-- Step 1: Enable xp_cmdshell only for this deployment run when not already enabled
IF @ShowAdvancedWasEnabled = 0
BEGIN
    PRINT N'Enabling show advanced options temporarily...';
    EXEC sp_configure 'show advanced options', 1;
    RECONFIGURE;
END;

IF @XpCmdShellWasEnabled = 0
BEGIN
    PRINT N'Enabling xp_cmdshell temporarily...';
    EXEC sp_configure 'xp_cmdshell', 1;
    RECONFIGURE;
END;

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

IF @XpCmdShellWasEnabled = 0
BEGIN
    PRINT N'Restoring xp_cmdshell to disabled...';
    EXEC sp_configure 'xp_cmdshell', 0;
    RECONFIGURE;
END;

IF @ShowAdvancedWasEnabled = 0
BEGIN
    PRINT N'Restoring show advanced options to disabled...';
    EXEC sp_configure 'show advanced options', 0;
    RECONFIGURE;
END;

PRINT N'';
PRINT N'==============================================================================';
PRINT N'Deployment complete.';
PRINT N'All framework objects have been deployed to [' + @TargetDB + N'].';
PRINT N'==============================================================================';
GO
