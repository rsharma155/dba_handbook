/* SQL_Server_Assessment */
SELECT
 (SELECT TOP 1 CONVERT(int,record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int'))
  FROM (SELECT CONVERT(xml,record) record, [timestamp] FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type='RING_BUFFER_SCHEDULER_MONITOR' AND record LIKE '%<SystemHealth>%') x
  ORDER BY [timestamp] DESC) AS SqlCpuPercent,
 osi.cpu_count AS LogicalCpuCount, osi.scheduler_count AS SchedulerCount,
 osi.physical_memory_kb/1024 AS PhysicalMemoryMB,
 pm.physical_memory_in_use_kb/1024 AS SqlMemoryInUseMB,
 pm.memory_utilization_percentage AS SqlMemoryUtilizationPercent,
 pm.process_physical_memory_low AS ProcessPhysicalMemoryLow,
 pm.process_virtual_memory_low AS ProcessVirtualMemoryLow,
 (SELECT cntr_value FROM sys.dm_os_performance_counters
  WHERE object_name LIKE '%Buffer Manager%' AND counter_name='Page life expectancy') AS PageLifeExpectancySeconds,
 (SELECT cntr_value FROM sys.dm_os_performance_counters
  WHERE object_name LIKE '%Memory Manager%' AND counter_name='Memory Grants Pending') AS MemoryGrantsPending
FROM sys.dm_os_sys_info osi CROSS JOIN sys.dm_os_process_memory pm;
