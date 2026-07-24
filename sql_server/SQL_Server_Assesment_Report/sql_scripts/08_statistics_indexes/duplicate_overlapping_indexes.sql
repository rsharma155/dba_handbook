/* SQL_Server_Assessment */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
;WITH idx AS (
 SELECT sch.name AS SchemaName,t.name AS TableName,i.object_id,i.index_id,i.name AS IndexName,
        i.type_desc AS IndexType,i.is_unique AS IsUnique,i.is_disabled AS IsDisabled,
        i.is_hypothetical AS IsHypothetical,UPPER(LTRIM(RTRIM(ISNULL(i.filter_definition,N'')))) AS FilterDefinition,
        STUFF((SELECT N','+QUOTENAME(c.name)+CASE WHEN ic.is_descending_key=1 THEN N' DESC' ELSE N'' END
               FROM sys.index_columns ic JOIN sys.columns c ON ic.object_id=c.object_id AND ic.column_id=c.column_id
               WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.is_included_column=0 AND ic.key_ordinal>0
               ORDER BY ic.key_ordinal FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N'') AS KeyColumns,
        ISNULL(STUFF((SELECT N','+QUOTENAME(c.name)
               FROM sys.index_columns ic JOIN sys.columns c ON ic.object_id=c.object_id AND ic.column_id=c.column_id
               WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.is_included_column=1
               ORDER BY c.name FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N''),N'') AS IncludedColumns,
        ISNULL((SELECT SUM(used_page_count) FROM sys.dm_db_partition_stats ps
                WHERE ps.object_id=i.object_id AND ps.index_id=i.index_id),0) AS PageCount,
        ISNULL(us.user_seeks,0)+ISNULL(us.user_scans,0)+ISNULL(us.user_lookups,0) AS Reads,
        ISNULL(us.user_updates,0) AS Writes,
        (SELECT MAX(v) FROM (VALUES(us.last_user_seek),(us.last_user_scan),(us.last_user_lookup)) d(v)) AS LastRead,
        us.last_user_update AS LastWrite
 FROM sys.indexes i JOIN sys.tables t ON i.object_id=t.object_id
 JOIN sys.schemas sch ON t.schema_id=sch.schema_id
 LEFT JOIN sys.dm_db_index_usage_stats us
  ON us.database_id=DB_ID() AND us.object_id=i.object_id AND us.index_id=i.index_id
 WHERE t.is_ms_shipped=0 AND i.index_id>0 AND i.is_primary_key=0 AND i.is_unique_constraint=0
)
SELECT DB_NAME() AS DatabaseName,a.SchemaName,a.TableName,
       CASE WHEN a.IncludedColumns=b.IncludedColumns THEN 'EXACT_DUPLICATE' ELSE 'SAME_KEY_OVERLAP' END AS MatchType,
       a.IndexName AS IndexA,b.IndexName AS IndexB,a.KeyColumns,
       a.IncludedColumns AS IncludedColumnsA,b.IncludedColumns AS IncludedColumnsB,
       a.IndexType,a.IsUnique,a.FilterDefinition,
       a.IsDisabled AS IndexADisabled,b.IsDisabled AS IndexBDisabled,
       a.IsHypothetical AS IndexAHypothetical,b.IsHypothetical AS IndexBHypothetical,
       a.PageCount AS IndexAPages,b.PageCount AS IndexBPages,
       a.Reads AS IndexAReads,b.Reads AS IndexBReads,a.Writes AS IndexAWrites,b.Writes AS IndexBWrites,
       a.LastRead AS IndexALastRead,b.LastRead AS IndexBLastRead,
       CASE WHEN a.IncludedColumns=b.IncludedColumns
            THEN 'Same ordered keys, INCLUDE columns, filter, uniqueness, and type.'
            ELSE 'Same ordered keys/filter/uniqueness/type but different INCLUDE coverage; investigate overlap.' END AS ReviewRationale
FROM idx a JOIN idx b ON b.object_id=a.object_id AND b.index_id>a.index_id
 AND b.KeyColumns=a.KeyColumns AND b.IndexType=a.IndexType AND b.IsUnique=a.IsUnique
 AND b.FilterDefinition=a.FilterDefinition
WHERE a.KeyColumns IS NOT NULL AND a.IsHypothetical=0 AND b.IsHypothetical=0
ORDER BY a.SchemaName,a.TableName,a.IndexName,b.IndexName;
