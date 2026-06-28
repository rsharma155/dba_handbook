/*
================================================================================
Purpose:        Exhaustive wait statistics analysis with detailed root cause 
                analysis and suggested investigation commands for top 30 waits.
Provides:       Detailed breakdown of top 30 wait types, average wait times, 
                percentage impact, and actionable T-SQL investigation scripts.
Importance:     Serves as a comprehensive reference guide for DBAs to understand 
                and troubleshoot specific wait types with proven commands.
Interpretation: Use the "Root_Cause_Analysis" to understand the wait and execute 
                 the "Investigation_Command" to find the specific source of pressure.
Action: Use this script as a reference guide. For each high-impact wait type in your environment, execute the provided Investigation_Command to find the source. For example, if PAGEIOLATCH_XX is top, run the investigation command to find slow data files, then cross-reference with disk_latency.sql. This script does not require immediate action — it is educational and designed to guide your troubleshooting.
Criticality:    Medium (Educational/Reference)
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.fn_DBA_ExcludedWaitTypes', N'IF') IS NULL
    AND NOT EXISTS (SELECT 1 FROM DBARepository.sys.objects WHERE name = N'fn_DBA_ExcludedWaitTypes' AND type = 'IF')
BEGIN
    RAISERROR(N'Run 00_Framework/00_Deploy_Framework.ps1 (-ServerInstance . -Database master) to auto-deploy all required objects, or deploy fn_DBA_ExcludedWaitTypes manually.', 16, 1);
    RETURN;
END;

WITH WaitData AS (
    SELECT
        wait_type,
        wait_time_ms / 1000.0 AS [Wait_S],
        (wait_time_ms - signal_wait_time_ms) / 1000.0 AS [Resource_S],
        signal_wait_time_ms / 1000.0 AS [Signal_S],
        waiting_tasks_count AS [Wait_Count],
        100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS [Percentage],
        ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes())
)
SELECT 
    wait_type AS [Wait_Type],
    CAST([Wait_S] AS DECIMAL(16,2)) AS [Wait_Sec],
    CAST([Percentage] AS DECIMAL(5,2)) AS [%],
    CAST(([Wait_S] / [Wait_Count]) AS DECIMAL(16,4)) AS [Avg_Wait_S],
    CASE 
        WHEN wait_type = 'CXPACKET' THEN 'Parallel skew. Threads waiting for others.'
        WHEN wait_type = 'SOS_SCHEDULER_YIELD' THEN 'CPU pressure. Threads exhausted quantum.'
        WHEN wait_type = 'PAGEIOLATCH_SH' THEN 'Disk Read. Data pages coming from disk.'
        WHEN wait_type = 'PAGEIOLATCH_EX' THEN 'Disk Write. Buffer flush to disk.'
        WHEN wait_type = 'WRITELOG' THEN 'T-Log latency. Flush to disk bottleneck.'
        WHEN wait_type = 'ASYNC_NETWORK_IO' THEN 'App fetching too slow / RBAR.'
        WHEN wait_type = 'RESOURCE_SEMAPHORE' THEN 'Memory grant starvation (Sort/Hash).'
        WHEN wait_type = 'LCK_M_X' THEN 'Exclusive Lock blocking.'
        WHEN wait_type = 'LCK_M_S' THEN 'Shared Lock blocking.'
        WHEN wait_type = 'PAGELATCH_UP' THEN 'TempDB/Buffer metadata contention.'
        WHEN wait_type = 'THREADPOOL' THEN 'Worker thread exhaustion. CRITICAL.'
        WHEN wait_type = 'PREEMPTIVE_OS_WRITEFILEGATHER' THEN 'IFI Disabled check.'
        WHEN wait_type = 'CMEMTHREAD' THEN 'Memory object contention (Plan Cache).'
        WHEN wait_type = 'HADR_SYNC_COMMIT' THEN 'AlwaysOn Sync Latency (Network/IO).'
        WHEN wait_type = 'LOGBUFFER' THEN 'Wait for space in log buffer. IO bottleneck.'
        WHEN wait_type = 'RESOURCE_SEMAPHORE_QUERY_COMPILE' THEN 'Compilation storm. Plan cache bloat.'
        WHEN wait_type = 'LCK_M_IX' THEN 'Intent Exclusive Lock. Table/Page level blocking.'
        WHEN wait_type = 'PAGEIOLATCH_UP' THEN 'Page update read. Disk bottleneck.'
        WHEN wait_type = 'ASYNC_IO_COMPLETION' THEN 'General IO wait. Check storage.'
        WHEN wait_type = 'BACKUPIO' THEN 'SQL waiting for backup device.'
        WHEN wait_type = 'CXCONSUMER' THEN 'Safe to ignore if CXPACKET is high.'
        WHEN wait_type = 'REDO_THREAD_PENDING_WORK' THEN 'AlwaysOn Redo Lag.'
        WHEN wait_type = 'SLEEP_BPOOL_FLUSH' THEN 'Checkpoint/LazyWriter bottleneck.'
        WHEN wait_type = 'DTC' THEN 'Distributed Transaction Coordinator lag.'
        WHEN wait_type = 'OLEDB' THEN 'Linked Server or DMV overhead.'
        WHEN wait_type = 'DBMIRROR_SEND' THEN 'Mirroring network lag.'
        WHEN wait_type = 'SQLCLR_QUANTUM' THEN 'CLR code executing too long.'
        WHEN wait_type = 'WRITE_COMPLETION' THEN 'General async write wait.'
        WHEN wait_type = 'POOL_PAGELATCH_EX' THEN 'Buffer pool contention.'
        WHEN wait_type = 'QUERY_EXECUTION_INDEX_LOOKUP' THEN 'Key Lookup pressure.'
        ELSE 'Review SQL documentation.'
    END AS [Root_Cause_Analysis],
    CASE 
        WHEN wait_type LIKE 'PAGEIOLATCH%' THEN 'SELECT * FROM sys.dm_io_virtual_file_stats(NULL,NULL) ORDER BY io_stall DESC;'
        WHEN wait_type = 'CXPACKET' THEN 'SELECT * FROM sys.configurations WHERE name IN (''max degree of parallelism'',''cost threshold for parallelism'');'
        WHEN wait_type = 'RESOURCE_SEMAPHORE' THEN 'SELECT * FROM sys.dm_exec_query_memory_grants;'
        WHEN wait_type LIKE 'LCK%' THEN 'EXEC sp_WhoIsActive @get_plans=1;'
        WHEN wait_type = 'SOS_SCHEDULER_YIELD' THEN 'SELECT TOP 20 * FROM sys.dm_exec_query_stats ORDER BY total_worker_time DESC;'
        WHEN wait_type = 'WRITELOG' THEN 'SELECT * FROM sys.dm_io_virtual_file_stats(2,NULL); -- Check TempDB/Log'
        ELSE 'N/A'
    END AS [Investigation_Command]
FROM WaitData
WHERE RowNum <= 30
ORDER BY [Wait_S] DESC;
