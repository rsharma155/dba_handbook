/* SQL_Initial_Assessment */
SELECT TOP (40)
    wait_type AS WaitType,
    waiting_tasks_count AS WaitingTasksCount,
    wait_time_ms AS WaitTimeMs,
    signal_wait_time_ms AS SignalWaitTimeMs,
    wait_time_ms - signal_wait_time_ms AS ResourceWaitTimeMs,
    CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS decimal(5, 2)) AS PctOfTotalWait,
    max_wait_time_ms AS MaxWaitTimeMs,
    CASE
        WHEN wait_type LIKE 'LCK_M_%' THEN 'Locking'
        WHEN wait_type LIKE 'PAGELATCH_%' OR wait_type LIKE 'PAGEIOLATCH_%' THEN 'Latch/IO'
        WHEN wait_type LIKE 'CX%' OR wait_type = 'CXPACKET' OR wait_type = 'CXCONSUMER' THEN 'Parallelism'
        WHEN wait_type = 'ASYNC_NETWORK_IO' THEN 'Client/network'
        WHEN wait_type = 'WRITELOG' THEN 'Log write'
        WHEN wait_type LIKE 'RESOURCE_SEMAPHORE%' THEN 'Memory grant'
        WHEN wait_type LIKE 'SOS_SCHEDULER_YIELD' THEN 'CPU'
        WHEN wait_type LIKE 'HADR_%' OR wait_type LIKE 'ALWAYS%' THEN 'HA/DR'
        ELSE 'Other'
    END AS WaitCategory
FROM sys.dm_os_wait_stats
WHERE wait_time_ms > 0
  AND wait_type NOT IN (
        'CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK','SLEEP_SYSTEMTASK',
        'SQLTRACE_BUFFER_FLUSH','WAITFOR','LOGMGR_QUEUE','CHECKPOINT_QUEUE',
        'REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT','BROKER_TO_FLUSH','BROKER_TASK_STOP',
        'CLR_MANUAL_EVENT','CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
        'XE_DISPATCHER_WAIT','XE_DISPATCHER_JOIN','SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        'ONDEMAND_TASK_QUEUE','BROKER_EVENTHANDLER','SLEEP_BPOOL_FLUSH','DIRTY_PAGE_POLL',
        'HADR_FILESTREAM_IOMGR_IOCOMPLETION','SP_SERVER_DIAGNOSTICS_SLEEP','QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
        'QDS_ASYNC_QUEUE','QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP','WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
        'WAIT_XTP_HOST_WAIT','WAIT_XTP_CKPT_CLOSE','XE_LIVE_TARGET_TVF','BROKER_RECEIVE_WAITFOR'
      )
ORDER BY wait_time_ms DESC;
