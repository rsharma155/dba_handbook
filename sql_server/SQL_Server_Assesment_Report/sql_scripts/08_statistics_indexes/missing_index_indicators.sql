/* SQL_Server_Assessment */
SELECT TOP (100) DB_NAME(mid.database_id) AS DatabaseName, mid.statement AS TableName,
       CAST(migs.avg_total_user_cost*migs.avg_user_impact*(migs.user_seeks+migs.user_scans) AS decimal(18,1)) AS ImprovementScore,
       migs.user_seeks AS UserSeeks, migs.user_scans AS UserScans,
       mid.equality_columns AS EqualityColumns, mid.inequality_columns AS InequalityColumns,
       mid.included_columns AS IncludedColumns
FROM sys.dm_db_missing_index_details mid
JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle=mig.index_handle
JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle=migs.group_handle
ORDER BY ImprovementScore DESC;
