/* SQL_Server_Assessment */
SELECT TOP (20) DB_NAME(txt.dbid) AS DatabaseName,qs.execution_count AS ExecutionCount,
       CAST(qs.total_grant_kb/1024.0 AS decimal(18,1)) AS TotalGrantMB,
       CAST(qs.max_grant_kb/1024.0 AS decimal(18,1)) AS MaxGrantMB,
       CAST(qs.max_used_grant_kb/1024.0 AS decimal(18,1)) AS MaxUsedGrantMB,
       CAST(qs.total_grant_kb/1024.0/NULLIF(qs.execution_count,0) AS decimal(18,2)) AS AvgGrantMB,
       qs.last_execution_time AS LastExecutionTime,
       LEFT(REPLACE(REPLACE(txt.text,CHAR(13),' '),CHAR(10),' '),1000) AS QueryText
FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) txt
WHERE (txt.dbid IS NULL OR txt.dbid>4)
  AND txt.text NOT LIKE '%/* SQL_Server_Assessment */%'
  AND txt.text NOT LIKE '%dbatools PowerShell%'
  AND (txt.objectid IS NULL OR txt.dbid IS NULL OR txt.dbid <> DB_ID()
       OR OBJECTPROPERTY(txt.objectid,'IsMSShipped')=0)
ORDER BY qs.max_grant_kb DESC;
