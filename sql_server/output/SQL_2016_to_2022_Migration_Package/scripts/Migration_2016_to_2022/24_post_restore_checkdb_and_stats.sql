/*
    Migration 2016 -> 2022 | Post-restore integrity (CHECKDB) + statistics refresh
    Run on: TARGET after restore (UAT and production cutover)
    Risk: CHECKDB is read-intensive; schedule during maintenance or after restore before go-live.
           sp_updatestats is generally safe but can increase CPU briefly.

    Based on common side-by-side upgrade practice (e.g. MSSQLTips upgrade guidance):
    - Verify integrity after backup/restore/file transfer
    - Refresh statistics so the new engine has current density info
*/
SET NOCOUNT ON;
SET LOCK_TIMEOUT 5000;

PRINT '=== DATABASE ONLINE / STATE CHECK ===';
SELECT
    name AS [DatabaseName],
    state_desc,
    user_access_desc,
    is_read_only,
    is_encrypted,
    compatibility_level
FROM sys.databases
WHERE database_id > 4
ORDER BY name;

PRINT '=== CHECKDB COMMAND GENERATOR (review, then run per DB) ===';
PRINT 'Tip: For large DBs use PHYSICAL_ONLY first if time-constrained, then full CHECKDB later.';
SELECT
    d.name AS [DatabaseName],
    N'DBCC CHECKDB (' + QUOTENAME(d.name, '''') + N') WITH NO_INFOMSGS, ALL_ERRORMSGS;' AS [FullCheckDbCommand],
    N'DBCC CHECKDB (' + QUOTENAME(d.name, '''') + N') WITH PHYSICAL_ONLY, NO_INFOMSGS, ALL_ERRORMSGS;' AS [PhysicalOnlyCommand]
FROM sys.databases AS d
WHERE d.database_id > 4
  AND d.state = 0
ORDER BY d.name;

PRINT '=== UPDATE STATISTICS (per-database template) ===';
PRINT 'Uncomment and run per database after restore, or use your standard maintenance solution (Ola Hallengren).';
/*
-- Example for one database:
USE [YourDatabase];
EXEC sys.sp_updatestats;
*/

SELECT
    d.name AS [DatabaseName],
    N'USE ' + QUOTENAME(d.name) + N'; EXEC sys.sp_updatestats;' AS [UpdateStatsCommand]
FROM sys.databases AS d
WHERE d.database_id > 4
  AND d.state = 0
  AND d.is_read_only = 0
ORDER BY d.name;

PRINT '=== OPTIONAL: last successful CHECKDB from persisted suspect_pages / history (if available) ===';
-- Prefer your monitoring / Ola CommandLog for historical CHECKDB results.
SELECT TOP (50)
    DB_NAME(database_id) AS [DatabaseName],
    file_id,
    page_id,
    event_type,
    error_count,
    last_update_date
FROM msdb.dbo.suspect_pages
ORDER BY last_update_date DESC;
