/* SQL_Server_Assessment */
SELECT wait_type AS WaitType,waiting_tasks_count AS WaitingTasks,
       wait_time_ms AS WaitTimeMs,max_wait_time_ms AS MaxWaitTimeMs,
       signal_wait_time_ms AS SignalWaitTimeMs,
       wait_time_ms/NULLIF(waiting_tasks_count,0) AS AvgWaitMs
FROM sys.dm_os_wait_stats
WHERE wait_type IN ('RESOURCE_SEMAPHORE','RESOURCE_SEMAPHORE_QUERY_COMPILE')
ORDER BY wait_time_ms DESC;
