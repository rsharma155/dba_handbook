/* SQL_Server_Assessment */
SELECT TOP (25) DB_NAME() AS DatabaseName, OBJECT_SCHEMA_NAME(ps.object_id) AS SchemaName,
       OBJECT_NAME(ps.object_id) AS TableName, i.name AS IndexName,
       i.type_desc AS IndexType,
       CAST(ps.avg_fragmentation_in_percent AS decimal(6,2)) AS FragmentationPercent,
       ps.page_count AS PageCount
FROM sys.dm_db_index_physical_stats(DB_ID(),NULL,NULL,NULL,'LIMITED') ps
JOIN sys.indexes i ON ps.object_id=i.object_id AND ps.index_id=i.index_id
JOIN sys.tables t ON ps.object_id=t.object_id
WHERE ps.index_id>0 AND ps.page_count>=1000 AND ps.avg_fragmentation_in_percent>=20
  AND t.is_ms_shipped=0
ORDER BY ps.page_count*ps.avg_fragmentation_in_percent DESC;
