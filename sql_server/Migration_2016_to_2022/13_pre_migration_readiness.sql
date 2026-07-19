/*
    Migration 2016 -> 2022 | Pre-migration readiness summary
    Run on SOURCE before cutover window approval.
    Risk: Read-only
*/
SET NOCOUNT ON;

PRINT '=== INSTANCE ===';
SELECT @@VERSION AS [Version], SERVERPROPERTY('Edition') AS [Edition], SERVERPROPERTY('ProductLevel') AS [ProductLevel];

PRINT '=== USER DATABASE COUNT ===';
SELECT COUNT(*) AS [UserDatabaseCount] FROM sys.databases WHERE database_id > 4 AND state = 0;

PRINT '=== SUSPECT / OFFLINE DATABASES ===';
SELECT name, state_desc FROM sys.databases WHERE database_id > 4 AND state_desc <> N'ONLINE';

PRINT '=== COMPATIBILITY LEVELS ===';
SELECT compatibility_level, COUNT(*) AS [DbCount]
FROM sys.databases WHERE database_id > 4
GROUP BY compatibility_level ORDER BY compatibility_level;

PRINT '=== TDE ENABLED DATABASES ===';
SELECT name, is_encrypted FROM sys.databases WHERE database_id > 4 AND is_encrypted = 1;

PRINT '=== AUTO_CLOSE / AUTO_SHRINK (BAD ON PROD) ===';
SELECT name, is_auto_close_on, is_auto_shrink_on
FROM sys.databases
WHERE database_id > 4 AND (is_auto_close_on = 1 OR is_auto_shrink_on = 1);

PRINT '=== LAST FULL BACKUP OLDER THAN 7 DAYS ===';
SELECT d.name, MAX(b.backup_finish_date) AS [LastFullBackup]
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b ON d.name = b.database_name AND b.type = 'D'
WHERE d.database_id > 4 AND d.state = 0
GROUP BY d.name
HAVING MAX(b.backup_finish_date) IS NULL OR MAX(b.backup_finish_date) < DATEADD(DAY, -7, GETDATE())
ORDER BY d.name;

PRINT '=== DEPRECATED FEATURE USAGE > 0 ===';
SELECT COUNT(*) AS [DeprecatedCountersNonZero]
FROM sys.dm_os_performance_counters
WHERE object_name LIKE N'%Deprecated Features%' AND cntr_value > 0;

PRINT '=== 2016 SP3 CHECK ===';
IF SERVERPROPERTY('ProductMajorVersion') = 13 AND SERVERPROPERTY('ProductLevel') <> N'SP3'
    PRINT 'FAIL: Apply SQL Server 2016 SP3 before in-place upgrade.';
ELSE
    PRINT 'PASS: Version/patch level acceptable for upgrade path validation.';
