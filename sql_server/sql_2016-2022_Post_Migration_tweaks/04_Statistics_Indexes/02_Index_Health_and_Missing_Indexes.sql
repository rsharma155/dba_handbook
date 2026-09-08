/*
================================================================================
02_Index_Health_and_Missing_Indexes.sql
Purpose : After CE change, new plans may need different covering indexes.
Caution : Missing-index DMVs are suggestions — validate with workload + writes.
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

PRINT '=== Fragmentation (sample; filter large tables) ===';
SELECT
    OBJECT_SCHEMA_NAME(ips.object_id) AS schema_name,
    OBJECT_NAME(ips.object_id) AS table_name,
    i.name AS index_name,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N'SAMPLED') AS ips
JOIN sys.indexes AS i
  ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE ips.page_count > 1000
  AND ips.avg_fragmentation_in_percent > 30
ORDER BY ips.avg_fragmentation_in_percent DESC;

PRINT '=== Missing index suggestions (impact * seeks) ===';
SELECT TOP (30)
    ROUND(migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans), 0) AS improvement_measure,
    mid.statement AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_user_impact
FROM sys.dm_db_missing_index_groups mig
JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details mid ON mid.index_handle = mig.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY improvement_measure DESC;

PRINT '=== Unused indexes (careful in short uptime windows) ===';
SELECT
    OBJECT_SCHEMA_NAME(i.object_id) AS schema_name,
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates,
    ius.last_user_seek, ius.last_user_scan
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats ius
  ON ius.object_id = i.object_id AND ius.index_id = i.index_id AND ius.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
  AND i.type_desc <> 'HEAP'
  AND i.is_primary_key = 0
  AND i.is_unique_constraint = 0
  AND ISNULL(ius.user_seeks,0) + ISNULL(ius.user_scans,0) + ISNULL(ius.user_lookups,0) = 0
ORDER BY ISNULL(ius.user_updates,0) DESC;
