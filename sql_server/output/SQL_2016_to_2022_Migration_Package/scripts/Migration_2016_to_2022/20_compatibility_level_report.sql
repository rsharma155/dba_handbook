/*
    Migration 2016 -> 2022 | Compatibility level + database scoped configurations
    Staged approach: remain 130 at cutover, then 140/150, then 160 after UAT sign-off.
    Risk: Read-only

    Scoped configs (LEGACY_CARDINALITY_ESTIMATION, etc.) are critical for rollback triage.
*/
SET NOCOUNT ON;
SET LOCK_TIMEOUT 3000;

SELECT
    d.name AS [DatabaseName],
    d.compatibility_level,
    CASE d.compatibility_level
        WHEN 130 THEN N'SQL Server 2016'
        WHEN 140 THEN N'SQL Server 2017'
        WHEN 150 THEN N'SQL Server 2019'
        WHEN 160 THEN N'SQL Server 2022'
        ELSE N'Other/legacy'
    END AS [CompatMapsTo],
    d.state_desc,
    d.is_query_store_on
FROM sys.databases AS d
WHERE d.database_id > 4
ORDER BY d.compatibility_level, d.name;

SELECT
    compatibility_level,
    COUNT(*) AS [DatabaseCount]
FROM sys.databases
WHERE database_id > 4
GROUP BY compatibility_level
ORDER BY compatibility_level;

-- Database scoped configurations that affect optimizer / rollback decisions
IF OBJECT_ID('tempdb..#Scoped') IS NOT NULL DROP TABLE #Scoped;
CREATE TABLE #Scoped (
    DatabaseName SYSNAME NOT NULL,
    ConfigName   SYSNAME NOT NULL,
    Value        SQL_VARIANT NULL,
    ValueForSecondary SQL_VARIANT NULL,
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
ORDER BY name;

DECLARE @i INT = 1, @max INT = (SELECT COUNT(*) FROM #DbList);
DECLARE @db SYSNAME, @sql NVARCHAR(MAX);

WHILE @i <= @max
BEGIN
    SELECT @db = DatabaseName FROM #DbList WHERE RowId = @i;

    SET @sql = N'
USE ' + QUOTENAME(@db) + N';
INSERT INTO #Scoped (DatabaseName, ConfigName, Value, ValueForSecondary, ScanNote)
SELECT DB_NAME(), name, value, value_for_secondary, NULL
FROM sys.database_scoped_configurations
WHERE name IN (
    N''LEGACY_CARDINALITY_ESTIMATION'',
    N''QUERY_OPTIMIZER_HOTFIXES'',
    N''PARAMETER_SNIFFING'',
    N''PARAMETER_SENSITIVE_PLAN_OPTIMIZATION'',
    N''MAXDOP'',
    N''BATCH_MODE_ON_ROWSTORE'',
    N''CE_FEEDBACK'',
    N''DOP_FEEDBACK'',
    N''OPTIMIZED_PLAN_FORCING''
);';

    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #Scoped (DatabaseName, ConfigName, Value, ValueForSecondary, ScanNote)
        VALUES (@db, N'(scan skipped)', NULL, NULL, LEFT(ERROR_MESSAGE(), 400));
    END CATCH;

    SET @i += 1;
END;

SELECT DatabaseName, ConfigName, Value, ValueForSecondary, ScanNote
FROM #Scoped
ORDER BY DatabaseName, ConfigName;

-- Staged change template (run only after Query Store baseline):
-- ALTER DATABASE [YourDatabase] SET COMPATIBILITY_LEVEL = 150;
-- ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;  -- temporary mitigation
