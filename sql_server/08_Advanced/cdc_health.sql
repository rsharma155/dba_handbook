/*
================================================================================
CDC Capture Health Across Databases
================================================================================
Description:
    Monitors Change Data Capture (CDC) health across all CDC-enabled databases.
    Reports capture latency, capture instance configuration, and log scan issues.

Output:
    CDC-enabled databases list, capture instance details (source table, captured
    columns), and latency metrics in seconds.

Action:
    If Latency_Seconds > @LatencyWarningSeconds, investigate: (1) check if the
    CDC capture job is running, (2) monitor transaction log growth (CDC holds
    log truncation), (3) review if the source table has too many columns tracked.
    For high latency, increase capture job frequency or reduce captured columns.

Parameters:
    @DatabaseList - comma-separated database names or NULL for all user DBs
    @LatencyWarningSeconds - latency threshold for warning (default 60)

Criticality: High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @LatencyWarningSeconds INT = 60;

PRINT N'--- CDC Enabled Databases ---';
SELECT name AS [Database_Name], is_cdc_enabled, state_desc, recovery_model_desc
FROM sys.databases
WHERE is_cdc_enabled = 1;

IF OBJECT_ID(N'tempdb..#CDCHealth') IS NOT NULL DROP TABLE #CDCHealth;
CREATE TABLE #CDCHealth (
    [Database] SYSNAME,
    [Capture_Instance] SYSNAME,
    [Source_Table] SYSNAME,
    [Captured_Columns] INT,
    [Latest_Latency_S] INT,
    [Latest_Scan_End] DATETIME NULL,
    [Latency_Status] NVARCHAR(20)
);

DECLARE @CdcCommand NVARCHAR(MAX) = N'
DECLARE @latency INT = (
    SELECT TOP (1) latency
    FROM sys.dm_cdc_log_scan_sessions
    WHERE end_time IS NOT NULL
    ORDER BY end_time DESC
);
DECLARE @scan_end DATETIME = (
    SELECT TOP (1) end_time
    FROM sys.dm_cdc_log_scan_sessions
    WHERE end_time IS NOT NULL
    ORDER BY end_time DESC
);
INSERT INTO #CDCHealth
SELECT
    DB_NAME(),
    ct.capture_instance,
    ct.source_schema + N''.'' + ct.source_name,
    ct.captured_column_count,
    @latency,
    @scan_end,
    CASE WHEN @latency > ' + CAST(@LatencyWarningSeconds AS NVARCHAR(10)) + N' THEN N''WARNING'' ELSE N''OK'' END
FROM cdc.change_tables AS ct;';

IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
BEGIN
    DECLARE @CdcDbList NVARCHAR(MAX) = STUFF((
        SELECT N',' + name
        FROM sys.databases
        WHERE is_cdc_enabled = 1 AND state = 0 AND is_in_standby = 0
        FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 1, N'');
    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
        SET @CdcDbList = @DatabaseList;

    IF @CdcDbList IS NOT NULL AND LEN(@CdcDbList) > 0
        EXEC dbo.sp_DBA_ForEachDatabase
            @Command = @CdcCommand,
            @UserDatabasesOnly = 0,
            @IncludeReadOnly = 0,
            @DatabaseList = @CdcDbList,
            @ContinueOnError = 1;
END
ELSE
BEGIN
    DECLARE @db_name SYSNAME;
    DECLARE @SQL NVARCHAR(MAX);

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.databases WHERE is_cdc_enabled = 1 AND state = 0 AND is_in_standby = 0
          AND (@DatabaseList IS NULL OR name IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@DatabaseList, N',') WHERE LTRIM(RTRIM(value)) <> N''))
        ORDER BY name;

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @db_name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'USE ' + QUOTENAME(@db_name) + N';' + @CdcCommand;
        BEGIN TRY EXEC sys.sp_executesql @SQL; END TRY BEGIN CATCH END CATCH;
        FETCH NEXT FROM db_cursor INTO @db_name;
    END;
    CLOSE db_cursor; DEALLOCATE db_cursor;
END;

SELECT * FROM #CDCHealth ORDER BY [Latest_Latency_S] DESC, [Database];
DROP TABLE #CDCHealth;
