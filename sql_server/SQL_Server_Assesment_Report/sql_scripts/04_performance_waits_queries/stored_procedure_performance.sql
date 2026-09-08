/* SQL_Server_Assessment */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
-- sys.dm_exec_procedure_stats does not retain client program_name. Exclude
-- Microsoft-shipped procedures; cached metrics remain workload-wide.
SELECT TOP (25) DB_NAME() AS DatabaseName,OBJECT_SCHEMA_NAME(ps.object_id) AS SchemaName,
       OBJECT_NAME(ps.object_id) AS ProcedureName,ps.execution_count AS ExecutionCount,
       CAST(ps.total_elapsed_time/1000.0 AS decimal(18,1)) AS TotalElapsedMs,
       CAST(ps.total_elapsed_time/1000.0/NULLIF(ps.execution_count,0) AS decimal(18,2)) AS AvgElapsedMs,
       CAST(ps.total_worker_time/1000.0 AS decimal(18,1)) AS TotalCpuMs,
       CAST(ps.total_worker_time/1000.0/NULLIF(ps.execution_count,0) AS decimal(18,2)) AS AvgCpuMs,
       ps.total_logical_reads AS TotalLogicalReads,
       CAST(ps.total_logical_reads*1.0/NULLIF(ps.execution_count,0) AS decimal(18,1)) AS AvgLogicalReads,
       ps.total_logical_writes AS TotalLogicalWrites,
       CAST(ps.total_logical_writes*1.0/NULLIF(ps.execution_count,0) AS decimal(18,1)) AS AvgLogicalWrites,
       ps.cached_time AS CachedTime,DATEDIFF(MINUTE,ps.cached_time,GETDATE()) AS CacheAgeMinutes,
       ps.last_execution_time AS LastExecutionTime
FROM sys.dm_exec_procedure_stats ps
WHERE ps.database_id=DB_ID() AND OBJECTPROPERTY(ps.object_id,'IsMSShipped')=0
ORDER BY ps.total_worker_time DESC;
