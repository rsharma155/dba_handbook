/* SQL_Server_Assessment */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT DB_NAME() AS DatabaseName, sch.name AS SchemaName, tbl.name AS TableName,
       st.name AS StatisticsName, sp.last_updated AS LastUpdated,
       CASE WHEN sp.last_updated IS NULL THEN NULL ELSE DATEDIFF(DAY,sp.last_updated,GETDATE()) END AS DaysSinceUpdate,
       sp.rows AS [Rows], sp.rows_sampled AS RowsSampled,
       CAST(100.0*sp.rows_sampled/NULLIF(sp.rows,0) AS decimal(6,2)) AS SamplePercent,
       sp.modification_counter AS ModificationCounter,
       CAST(100.0*sp.modification_counter/NULLIF(sp.rows,0) AS decimal(8,2)) AS ModificationPercent,
       st.auto_created AS AutoCreated, st.user_created AS UserCreated,
       st.no_recompute AS NoRecompute
FROM sys.stats st
JOIN sys.tables tbl ON st.object_id=tbl.object_id
JOIN sys.schemas sch ON tbl.schema_id=sch.schema_id
OUTER APPLY sys.dm_db_stats_properties(st.object_id,st.stats_id) sp
WHERE tbl.is_ms_shipped=0
ORDER BY sch.name,tbl.name,st.name;
