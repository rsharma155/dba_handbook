/*
================================================================================
Database File Space, Autogrowth, and Utilization
================================================================================
Description:
    Reports current file size, space used, free space, and autogrowth settings
    for all data and log files across user databases. Identifies files that are
    near capacity or have suboptimal autogrowth configurations.

Output:
    File-level details including used space percentage, autogrowth increments,
    and a status column indicating files that need attention.

Action:
    For files with UsedPct > 90%, extend the file size immediately:
        ALTER DATABASE [DBName] MODIFY FILE (NAME = logical_name, SIZE = new_size_MB);
    For files with percentage-based autogrowth ("BY_PERCENT"), switch to fixed-MB
    growth to prevent uncontrolled growth events:
        ALTER DATABASE [DBName] MODIFY FILE (NAME = logical_name, FILEGROWTH = 1024MB);
    Monitor log files closely — logs that grow unexpectedly may indicate
    long-running transactions or missing log backups.

Parameters:
    @DatabaseList - comma-separated database names or NULL for all user DBs
    @StalePctThreshold - used space % threshold for warnings (default 80)

Criticality: High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL; -- e.g. N'SalesDB,HRDB'
DECLARE @StalePctThreshold DECIMAL(5,2) = 80.0;

IF OBJECT_ID(N'tempdb..#FileSpaceStats') IS NOT NULL DROP TABLE #FileSpaceStats;
CREATE TABLE #FileSpaceStats (
    DatabaseName SYSNAME,
    LogicalName SYSNAME,
    PhysicalName NVARCHAR(260),
    FileType VARCHAR(10),
    TotalSizeMB DECIMAL(18,2),
    SpaceUsedMB DECIMAL(18,2),
    FreeSpaceMB DECIMAL(18,2),
    AutogrowthSetting VARCHAR(50),
    UsedPct DECIMAL(5,2),
    SpaceStatus VARCHAR(20)
);

IF OBJECT_ID(N'tempdb..#DbTargets') IS NOT NULL DROP TABLE #DbTargets;
CREATE TABLE #DbTargets (database_name SYSNAME NOT NULL PRIMARY KEY);

IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
BEGIN
    INSERT INTO #DbTargets (database_name)
    SELECT LTRIM(RTRIM(value))
    FROM STRING_SPLIT(@DatabaseList, N',')
    WHERE LTRIM(RTRIM(value)) <> N'';
END
ELSE
BEGIN
    INSERT INTO #DbTargets (database_name)
    SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0 AND is_in_standby = 0;
END;

DECLARE @db_name SYSNAME;
DECLARE @SQL NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT database_name FROM #DbTargets ORDER BY database_name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';
    INSERT INTO #FileSpaceStats
    SELECT
        DB_NAME(),
        df.name,
        df.physical_name,
        df.type_desc,
        CAST(df.size * 8.0 / 1024 AS DECIMAL(18,2)),
        CAST(FILEPROPERTY(df.name, N''SpaceUsed'') * 8.0 / 1024 AS DECIMAL(18,2)),
        CAST((df.size - FILEPROPERTY(df.name, N''SpaceUsed'')) * 8.0 / 1024 AS DECIMAL(18,2)),
        CASE WHEN df.is_percent_growth = 1 THEN CAST(df.growth AS VARCHAR(10)) + N''%'' ELSE CAST(df.growth * 8 / 1024 AS VARCHAR(10)) + N'' MB'' END,
        CAST(FILEPROPERTY(df.name, N''SpaceUsed'') * 100.0 / NULLIF(df.size, 0) AS DECIMAL(5,2)),
        CASE
            WHEN CAST(FILEPROPERTY(df.name, N''SpaceUsed'') * 100.0 / NULLIF(df.size, 0) AS DECIMAL(5,2)) >= ' + CAST(@StalePctThreshold AS NVARCHAR(10)) + N' THEN N''WARNING''
            ELSE N''OK''
        END
    FROM sys.database_files AS df;';

    BEGIN TRY
        EXEC sys.sp_executesql @SQL;
    END TRY
    BEGIN CATCH
        INSERT INTO #FileSpaceStats
        VALUES (@db_name, N'ERROR', LEFT(ERROR_MESSAGE(), 260), N'N/A', 0, 0, 0, N'N/A', 0, N'ERROR');
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @db_name;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT * FROM #FileSpaceStats ORDER BY UsedPct DESC, TotalSizeMB DESC;
DROP TABLE #FileSpaceStats;
DROP TABLE #DbTargets;
