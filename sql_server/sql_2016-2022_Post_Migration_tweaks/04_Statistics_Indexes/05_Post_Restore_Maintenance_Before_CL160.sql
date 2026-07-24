/*
================================================================================
05_Post_Restore_Maintenance_Before_CL160.sql
Purpose : Mandatory post-backup/restore maintenance BEFORE enabling CL 160.
Why     : A restore from SQL Server 2016 carries over stale statistics headers,
          outdated histogram steps, and legacy modification counters. Page/row
          counts in sys.allocation_units / usage metadata can also be stale and
          feed Cardinality Estimator formulas incorrectly.

When    : Immediately after restore onto SQL Server 2022, while still at CL 130
          (or before first CL 160 flip in UAT).

Safety  : Test First - FULLSCAN can be long/IO-heavy on large databases.
          Prefer maintenance window. NORECOMPUTE not used (auto-update stays on).

Note    : Stats/indexes/MAXDOP may already be done on some engagements - keep this
          script in the package for future restore-based migrations.
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

PRINT '=== 1) DBCC UPDATEUSAGE - refresh page and row counts ===';
PRINT 'Feeds accurate row/page metadata used by CE and space reports.';
-- 0 = current database; WITH COUNT_ROWS updates row counts in sysindexes-compatible views
DBCC UPDATEUSAGE(0) WITH COUNT_ROWS, NO_INFOMSGS;
GO

PRINT '=== 2) Generate FULLSCAN UPDATE STATISTICS for all user tables ===';
-- Review the list, then run during a maintenance window.
SELECT
    'UPDATE STATISTICS ' + QUOTENAME(OBJECT_SCHEMA_NAME(t.object_id))
        + '.' + QUOTENAME(t.name)
        + ' WITH FULLSCAN;' AS update_sql,
    SUM(p.rows) AS approx_rows
FROM sys.tables AS t
JOIN sys.partitions AS p
  ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.is_ms_shipped = 0
GROUP BY t.object_id, t.name
ORDER BY approx_rows DESC;

PRINT '=== 3) Optional: execute FULLSCAN for all user tables (UNCOMMENT TO RUN) ===';
/*
-- WARNING: Can take hours on multi-TB databases. Prefer generated scripts in batches.
DECLARE @sql nvarchar(max) = N'';
SELECT @sql = @sql + N'UPDATE STATISTICS '
    + QUOTENAME(OBJECT_SCHEMA_NAME(t.object_id)) + N'.'
    + QUOTENAME(t.name) + N' WITH FULLSCAN;' + CHAR(13)
FROM sys.tables AS t
WHERE t.is_ms_shipped = 0
ORDER BY t.name;

-- Prefer cursor / Ola Hallengren for production control instead of one giant batch.
PRINT LEFT(@sql, 4000);  -- preview
-- EXEC sys.sp_executesql @sql;
*/

PRINT '=== 4) Avoid sp_MSforeachtable in production ===';
PRINT 'sp_MSforeachtable is undocumented and can miss tables / fail silently.';
PRINT 'Use the generated UPDATE STATISTICS list above, or Ola Hallengren IndexOptimize.';

/*
EXAMPLE (small DB only - undocumented; prefer generated scripts):
-- EXEC sp_MSforeachtable N'UPDATE STATISTICS ? WITH FULLSCAN;';
*/

PRINT '=== 5) Verify freshness after maintenance ===';
SELECT TOP (30)
    OBJECT_SCHEMA_NAME(s.object_id) AS schema_name,
    OBJECT_NAME(s.object_id) AS table_name,
    s.name AS stats_name,
    STATS_DATE(s.object_id, s.stats_id) AS last_updated,
    sp.rows,
    sp.rows_sampled,
    CASE WHEN sp.rows > 0 AND sp.rows_sampled = sp.rows THEN N'FULLSCAN-like'
         ELSE N'Sampled/other' END AS sample_quality
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
ORDER BY last_updated DESC;

PRINT 'Next: keep CL 130, enable Query Store, capture 3-7 days, THEN test CL 160 in UAT.';
GO
