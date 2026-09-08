/* SQL_Server_Assessment */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
;WITH pages AS (
 SELECT object_id,index_id,SUM(used_page_count) AS PageCount
 FROM sys.dm_db_partition_stats GROUP BY object_id,index_id
)
SELECT DB_NAME() AS DatabaseName, sch.name AS SchemaName, tbl.name AS TableName,
       i.name AS IndexName, i.type_desc AS IndexType, i.is_disabled AS IsDisabled,
       i.is_hypothetical AS IsHypothetical, i.is_unique AS IsUnique,
       i.is_primary_key AS IsPrimaryKey, i.is_unique_constraint AS IsUniqueConstraint,
       i.fill_factor AS [FillFactor], ISNULL(p.PageCount,0) AS PageCount,
       CAST(NULL AS decimal(6,2)) AS FragmentationPercent,
       ISNULL(us.user_seeks,0) AS Seeks, ISNULL(us.user_scans,0) AS Scans,
       ISNULL(us.user_lookups,0) AS Lookups, ISNULL(us.user_updates,0) AS Updates,
       us.last_user_seek AS LastUserSeek, us.last_user_scan AS LastUserScan,
       us.last_user_lookup AS LastUserLookup, us.last_user_update AS LastUserUpdate
FROM sys.indexes i
JOIN sys.tables tbl ON i.object_id=tbl.object_id
JOIN sys.schemas sch ON tbl.schema_id=sch.schema_id
LEFT JOIN pages p ON i.object_id=p.object_id AND i.index_id=p.index_id
LEFT JOIN sys.dm_db_index_usage_stats us
 ON us.database_id=DB_ID() AND us.object_id=i.object_id AND us.index_id=i.index_id
WHERE tbl.is_ms_shipped=0 AND i.index_id>0
ORDER BY sch.name,tbl.name,i.index_id;
