/*
================================================================================
Post-Migration Instance Upgrade Validation
================================================================================
Purpose:
    Validates that the instance was upgraded correctly and flags settings that
    commonly remain wrong after attach/restore/in-place upgrade.

Checks:
    (1) Build, edition, collation, clustered status
    (2) Last errorlog startup messages (version line)
    (3) Database states, recovery models, Query Store status
    (4) Orphaned database owners (breaks metadata operations in SSMS)
    (5) Suspect/offline databases
    (6) Server-level triggers, linked servers count

Interpretation:
    - Orphaned owner on many DBs → SSMS Object Explorer slow, metadata errors
    - Query Store READ_WRITE with forced bad plan → run regression script
    - Database OFFLINE/SUSPECT → expand tree hangs on those nodes

Next action:
    Orphaned owner fix (per DB, maintenance window):
        ALTER AUTHORIZATION ON DATABASE::[DbName] TO [sa_or_login];
    If upgrade build is RTM with no CU → check Microsoft KB for 2025 CU list.

Criticality: High
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

PRINT '=== INSTANCE PROPERTIES ===';
SELECT
    @@SERVERNAME AS [Server_Name],
    SERVERPROPERTY(N'IsClustered') AS [Is_Clustered],
    SERVERPROPERTY(N'Collation') AS [Instance_Collation],
    SERVERPROPERTY(N'Edition') AS [Edition],
    SERVERPROPERTY(N'ProductVersion') AS [Version],
    SERVERPROPERTY(N'ProductLevel') AS [Level],
    SERVERPROPERTY(N'ProductUpdateLevel') AS [Update_Level],
    SERVERPROPERTY(N'ProductBuild') AS [Build],
    SERVERPROPERTY(N'IsHadrEnabled') AS [HADR_Enabled];

PRINT '=== USER DATABASE HEALTH ===';
SELECT
    d.name AS [Database_Name],
    d.state_desc AS [State],
    d.recovery_model_desc AS [Recovery_Model],
    d.compatibility_level AS [Compat_Level],
    d.collation_name,
    SUSER_SNAME(d.owner_sid) AS [Owner],
    d.is_query_store_on AS [Query_Store_On],
    CASE
        WHEN SUSER_SNAME(d.owner_sid) IS NULL THEN N'FIX: ALTER AUTHORIZATION ON DATABASE'
        WHEN d.state_desc <> N'ONLINE' THEN N'FIX: Bring database online or remove from SSMS view'
        WHEN d.is_auto_close_on = 1 THEN N'FIX: SET AUTO_CLOSE OFF'
        ELSE N'OK'
    END AS [Action]
FROM sys.databases AS d
WHERE d.database_id > 4
ORDER BY d.state_desc, d.name;

PRINT '=== QUERY STORE FORCED PLANS (carried over from pre-migration) ===';
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql = @sql + N'
SELECT ''' + REPLACE(d.name, '''', '''''') + N''' AS [Database_Name],
       COUNT(*) AS [Forced_Plan_Count]
FROM [' + REPLACE(d.name, ']', ']]') + N'].sys.query_store_plan
WHERE is_forced_plan = 1
HAVING COUNT(*) > 0
UNION ALL
'
FROM sys.databases AS d
WHERE d.database_id > 4 AND d.state = 0 AND d.is_query_store_on = 1;

IF LEN(@sql) > 0
BEGIN
    SET @sql = LEFT(@sql, LEN(@sql) - 11);
    EXEC sys.sp_executesql @sql;
END
ELSE
    PRINT 'No databases with Query Store enabled, or none online.';

PRINT '=== ERRORLOG — RECENT STARTUP (last 20 rows) ===';
CREATE TABLE #ErrorLog (
    LogDate DATETIME,
    ProcessInfo NVARCHAR(50),
    [Text] NVARCHAR(MAX)
);

INSERT INTO #ErrorLog
EXEC sys.xp_readerrorlog 0, 1, N'SQL Server';

SELECT TOP (20) LogDate, ProcessInfo, [Text]
FROM #ErrorLog
ORDER BY LogDate DESC;

DROP TABLE #ErrorLog;

PRINT '=== LINKED SERVERS / SERVER TRIGGERS (can slow distributed metadata) ===';
SELECT name AS [Linked_Server], product, provider, is_linked FROM sys.servers WHERE is_linked = 1;
SELECT name, is_disabled FROM sys.server_triggers;

PRINT 'Next: 02_express_to_developer_limits_check.sql if prior edition was Express.';
