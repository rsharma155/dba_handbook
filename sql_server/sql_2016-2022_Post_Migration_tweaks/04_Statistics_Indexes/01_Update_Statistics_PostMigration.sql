/*
================================================================================
01_Update_Statistics_PostMigration.sql
Purpose : Refresh statistics after restore / before or after flipping to compat 160.
Why     : New CE is more sensitive to density/histogram quality. FULLSCAN on hot
          tables often eliminates large estimate errors overnight.
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

-- A) Inventory: oldest / most modified stats
SELECT TOP (100)
    OBJECT_SCHEMA_NAME(s.object_id) AS schema_name,
    OBJECT_NAME(s.object_id) AS table_name,
    s.name AS stats_name,
    STATS_DATE(s.object_id, s.stats_id) AS last_updated,
    sp.rows,
    sp.rows_sampled,
    sp.modification_counter,
    CASE WHEN sp.rows > 0
         THEN CAST(sp.modification_counter * 100.0 / sp.rows AS decimal(10,2))
         ELSE 0 END AS pct_modified
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
ORDER BY sp.modification_counter DESC, last_updated ASC;

-- B) Update ALL stats in DB (sampled) — good first pass on large DBs
-- EXEC sp_updatestats;

-- C) Targeted FULLSCAN for critical tables (preferred for top offenders)
/*
UPDATE STATISTICS dbo.Orders WITH FULLSCAN;
UPDATE STATISTICS dbo.OrderDetails WITH FULLSCAN;
UPDATE STATISTICS dbo.Customers WITH FULLSCAN;
*/

-- D) Generate FULLSCAN scripts for top modified tables
SELECT
    'UPDATE STATISTICS ' + QUOTENAME(OBJECT_SCHEMA_NAME(s.object_id))
        + '.' + QUOTENAME(OBJECT_NAME(s.object_id))
        + ' WITH FULLSCAN;' AS update_sql,
    sp.modification_counter,
    STATS_DATE(s.object_id, s.stats_id) AS last_updated
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE s.stats_id = 1  -- often clustered / first; expand as needed
  AND OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
  AND sp.modification_counter > 1000
ORDER BY sp.modification_counter DESC;

/*
E) Optional: permanent auto-stats async
ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS_ASYNC ON;
*/
