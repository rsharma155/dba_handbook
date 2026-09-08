/* SQL_Server_Assessment */
SELECT TOP (25) DB_NAME(st.dbid) AS DatabaseName, qs.execution_count AS ExecutionCount,
       CAST(qs.total_worker_time/1000.0 AS decimal(18,1)) AS TotalCpuMs,
       CAST(qs.total_elapsed_time/1000.0 AS decimal(18,1)) AS TotalElapsedMs,
       qs.total_logical_reads AS TotalLogicalReads, qs.total_physical_reads AS TotalPhysicalReads,
       qs.total_logical_writes AS TotalWrites, qs.last_execution_time AS LastExecutionTime,
       LEFT(REPLACE(REPLACE(st.text,CHAR(13),' '),CHAR(10),' '),4000) AS QueryText
FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
-- dbid > 4 drops queries compiled in system databases (master/tempdb/model/msdb);
-- dbid IS NULL is kept because ad-hoc/prepared statements often have no dbid and
-- excluding them would hide real application workload. Cached-query DMVs do not
-- retain client program_name, so the assessment marker is the reliable exclusion.
WHERE (st.dbid IS NULL OR st.dbid > 4)
  AND st.text NOT LIKE '%/* SQL_Server_Assessment */%'
  AND st.text NOT LIKE '%dbatools PowerShell%'
  AND (st.objectid IS NULL OR st.dbid IS NULL OR st.dbid <> DB_ID()
       OR OBJECTPROPERTY(st.objectid,'IsMSShipped')=0)
ORDER BY qs.total_worker_time DESC;
