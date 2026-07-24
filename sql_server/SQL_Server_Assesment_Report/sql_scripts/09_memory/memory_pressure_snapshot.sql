/* SQL_Server_Assessment */
SELECT
 pm.physical_memory_in_use_kb/1024 AS SqlPhysicalMemoryMB,
 pm.memory_utilization_percentage AS SqlMemoryUtilizationPercent,
 pm.process_physical_memory_low AS ProcessPhysicalMemoryLow,
 pm.process_virtual_memory_low AS ProcessVirtualMemoryLow,
 osm.total_physical_memory_kb/1024 AS OsTotalMemoryMB,
 osm.available_physical_memory_kb/1024 AS OsAvailableMemoryMB,
 (SELECT TOP (1) cntr_value/1024 FROM sys.dm_os_performance_counters
  WHERE object_name LIKE '%Memory Manager%' AND counter_name='Total Server Memory (KB)' AND instance_name='') AS TotalServerMemoryMB,
 (SELECT TOP (1) cntr_value/1024 FROM sys.dm_os_performance_counters
  WHERE object_name LIKE '%Memory Manager%' AND counter_name='Target Server Memory (KB)' AND instance_name='') AS TargetServerMemoryMB,
 (SELECT TOP (1) cntr_value FROM sys.dm_os_performance_counters
  WHERE object_name LIKE '%Memory Manager%' AND counter_name='Memory Grants Pending' AND instance_name='') AS MemoryGrantsPending,
 (SELECT TOP (1) cntr_value FROM sys.dm_os_performance_counters
  WHERE object_name LIKE '%Memory Manager%' AND counter_name='Memory Grants Outstanding' AND instance_name='') AS MemoryGrantsOutstanding,
 (SELECT TOP (1) cntr_value FROM sys.dm_os_performance_counters
  WHERE object_name LIKE '%Buffer Manager%' AND counter_name='Page life expectancy' AND instance_name='') AS PageLifeExpectancySeconds,
 CAST(100.0*(SELECT wait_time_ms FROM sys.dm_os_wait_stats WHERE wait_type='RESOURCE_SEMAPHORE')/
      NULLIF((SELECT SUM(wait_time_ms) FROM sys.dm_os_wait_stats),0) AS decimal(7,3)) AS ResourceSemaphoreWaitPercent,
 (SELECT wait_time_ms FROM sys.dm_os_wait_stats WHERE wait_type='RESOURCE_SEMAPHORE') AS ResourceSemaphoreWaitMs
FROM sys.dm_os_process_memory pm CROSS JOIN sys.dm_os_sys_memory osm;
