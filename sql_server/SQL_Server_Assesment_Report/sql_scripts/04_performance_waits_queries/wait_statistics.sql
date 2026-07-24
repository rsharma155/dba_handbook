/* SQL_Server_Assessment */
;WITH w AS (
 SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms,
        100.0*wait_time_ms/NULLIF(SUM(wait_time_ms) OVER(),0) AS WaitPercent
 FROM sys.dm_os_wait_stats
 WHERE wait_time_ms > 0
 AND wait_type NOT IN ('SLEEP_TASK','SLEEP_SYSTEMTASK','LAZYWRITER_SLEEP','SQLTRACE_BUFFER_FLUSH',
 'WAITFOR','LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT',
 'BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_AUTO_EVENT','CLR_MANUAL_EVENT','DISPATCHER_QUEUE_SEMAPHORE')
)
SELECT TOP (30) wait_type AS WaitType, waiting_tasks_count AS WaitCount,
       CAST(wait_time_ms/1000.0 AS decimal(18,1)) AS WaitSeconds,
       CAST(signal_wait_time_ms/1000.0 AS decimal(18,1)) AS SignalWaitSeconds,
       CAST(WaitPercent AS decimal(6,2)) AS WaitPercent,
       CASE WHEN wait_type LIKE 'LCK%' THEN 'Blocking'
            WHEN wait_type LIKE 'PAGEIOLATCH%' OR wait_type='WRITELOG' THEN 'Storage I/O'
            WHEN wait_type LIKE 'PAGELATCH%' THEN 'Latch/TempDB'
            WHEN wait_type IN ('SOS_SCHEDULER_YIELD','THREADPOOL') THEN 'CPU/Workers'
            WHEN wait_type LIKE 'RESOURCE_SEMAPHORE%' THEN 'Memory Grant'
            WHEN wait_type IN ('CXPACKET','CXCONSUMER') THEN 'Parallelism'
            ELSE 'Other' END AS Category
FROM w ORDER BY wait_time_ms DESC;
