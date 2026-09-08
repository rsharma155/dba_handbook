/*
    Migration 2016 -> 2022 | Query Store status and enable template
    Enable Query Store BEFORE raising compatibility level.
    Risk: Read-only (status); ALTER DATABASE below is commented — review before enabling.

    Note: sys.database_query_store_options is per-database (no database_id column).
    Use sys.databases.is_query_store_on, then probe options inside each online user DB.
    Avoid readonly_reason_desc (not present on SQL Server 2016).
*/
SET NOCOUNT ON;
SET LOCK_TIMEOUT 3000;

IF OBJECT_ID('tempdb..#QsStatus') IS NOT NULL DROP TABLE #QsStatus;
CREATE TABLE #QsStatus (
    DatabaseName       SYSNAME NOT NULL,
    CompatibilityLevel TINYINT NOT NULL,
    IsQueryStoreOn     BIT NULL,
    ActualStateDesc    NVARCHAR(60) NULL,
    ReadonlyReason     INT NULL,
    DesiredStateDesc   NVARCHAR(60) NULL,
    CurrentStorageMB   DECIMAL(18, 2) NULL,
    MaxStorageMB       BIGINT NULL,
    ScanNote           NVARCHAR(400) NULL
);

IF OBJECT_ID('tempdb..#DbList') IS NOT NULL DROP TABLE #DbList;
CREATE TABLE #DbList (
    RowId INT IDENTITY(1,1) PRIMARY KEY,
    DatabaseName SYSNAME NOT NULL,
    CompatibilityLevel TINYINT NOT NULL,
    IsQueryStoreOn BIT NULL
);

INSERT INTO #DbList (DatabaseName, CompatibilityLevel, IsQueryStoreOn)
SELECT
    d.name,
    d.compatibility_level,
    d.is_query_store_on
FROM sys.databases AS d
WHERE d.database_id > 4
  AND d.state = 0
ORDER BY d.name;

DECLARE @i INT = 1, @max INT = (SELECT COUNT(*) FROM #DbList);
DECLARE @db SYSNAME, @compat TINYINT, @qsOn BIT, @sql NVARCHAR(MAX);

WHILE @i <= @max
BEGIN
    SELECT
        @db = DatabaseName,
        @compat = CompatibilityLevel,
        @qsOn = IsQueryStoreOn
    FROM #DbList
    WHERE RowId = @i;

    SET @sql = N'
USE ' + QUOTENAME(@db) + N';
INSERT INTO #QsStatus (
    DatabaseName, CompatibilityLevel, IsQueryStoreOn,
    ActualStateDesc, ReadonlyReason, DesiredStateDesc,
    CurrentStorageMB, MaxStorageMB, ScanNote
)
SELECT
    DB_NAME(),
    @compat,
    @qsOn,
    qso.actual_state_desc,
    qso.readonly_reason,
    qso.desired_state_desc,
    CAST(qso.current_storage_size_mb AS DECIMAL(18, 2)),
    qso.max_storage_size_mb,
    NULL
FROM sys.database_query_store_options AS qso;';

    BEGIN TRY
        EXEC sys.sp_executesql
            @sql,
            N'@compat TINYINT, @qsOn BIT',
            @compat = @compat,
            @qsOn = @qsOn;
    END TRY
    BEGIN CATCH
        INSERT INTO #QsStatus (
            DatabaseName, CompatibilityLevel, IsQueryStoreOn,
            ActualStateDesc, ReadonlyReason, DesiredStateDesc,
            CurrentStorageMB, MaxStorageMB, ScanNote
        )
        VALUES (
            @db, @compat, @qsOn,
            NULL, NULL, NULL, NULL, NULL,
            LEFT(ERROR_MESSAGE(), 400)
        );
    END CATCH;

    SET @i += 1;
END;

SELECT
    DatabaseName,
    CompatibilityLevel,
    IsQueryStoreOn,
    ActualStateDesc,
    ReadonlyReason,
    DesiredStateDesc,
    CurrentStorageMB,
    MaxStorageMB,
    ScanNote,
    CASE
        WHEN IsQueryStoreOn = 1 AND ActualStateDesc = N'READ_WRITE' THEN N'OK'
        WHEN IsQueryStoreOn = 1 AND ActualStateDesc = N'READ_ONLY' THEN N'WARN - Query Store read-only'
        WHEN IsQueryStoreOn = 0 OR ActualStateDesc = N'OFF' OR ActualStateDesc IS NULL THEN N'ENABLE before compat raise'
        ELSE N'REVIEW'
    END AS [MigrationGuidance]
FROM #QsStatus
ORDER BY DatabaseName;

-- Enable template (uncomment and run per database after review):
/*
ALTER DATABASE [YourDatabase] SET QUERY_STORE = ON;
ALTER DATABASE [YourDatabase] SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 2048,
    QUERY_CAPTURE_MODE = AUTO
);
*/
