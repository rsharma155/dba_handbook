/*
================================================================================
Purpose:        Collects cumulative instance-wide wait statistics, filtering out 
                benign background system waits to highlight active bottlenecks.
Provides:       Wait types, wait times (total, resource, signal), wait counts, 
                percentage of total waits, and best practice recommendations.
Importance:     Critical for identifying the primary hardware or configuration 
                bottleneck (CPU, I/O, Memory, Locking) affecting the instance.
Interpretation: Focus on wait types with the highest "Percentage_Of_Total_Waits". 
                 The top 3-5 types typically represent 80%+ of total wait time.
Action: Focus on the top 3-5 wait types — they represent 80%+ of total wait time. Common patterns: PAGEIOLATCH_XX = disk I/O bottleneck (run disk_latency.sql), LCK_M_XX = blocking (run blocking_and_deadlocks.sql), SOS_SCHEDULER_YIELD = CPU pressure (run cpu_utilization.sql), RESOURCE_SEMAPHORE = memory pressure (run memory_diagnostics.sql). See wait_statistics_reference.sql for detailed investigation commands per wait type.
Criticality:    High
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

SELECT sqlserver_start_time AS [Instance_Start_Time], N'Wait stats are cumulative since this time.' AS [Metric_Context]
FROM sys.dm_os_sys_info;

WITH [WaitStats] AS (
    SELECT 
        wait_type,
        wait_time_ms / 1000.0 AS [Wait_S],
        (wait_time_ms - signal_wait_time_ms) / 1000.0 AS [Resource_S],
        signal_wait_time_ms / 1000.0 AS [Signal_S],
        waiting_tasks_count AS [Wait_Count],
        ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS [Row_Num]
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes())
      AND waiting_tasks_count > 0
)
SELECT 
    W1.wait_type AS [Wait_Type],
    CAST(W1.Wait_S AS DECIMAL(14, 2)) AS [Wait_Sec],
    CAST(W1.Resource_S AS DECIMAL(14, 2)) AS [Resource_Sec],
    CAST(W1.Signal_S AS DECIMAL(14, 2)) AS [Signal_Sec],
    W1.Wait_Count AS [Wait_Count],
    CAST(W1.Wait_S / NULLIF(SUM(W2.Wait_S), 0) * 100 AS DECIMAL(5, 2)) AS [Percentage_Of_Total_Waits],
    CASE 
        WHEN W1.wait_type LIKE 'LCK%' THEN 'Locking'
        WHEN W1.wait_type LIKE 'PAGEIOLATCH%' THEN 'Storage (Read)'
        WHEN W1.wait_type LIKE 'WRITELOG' OR W1.wait_type LIKE 'LOGMGR%' THEN 'Storage (Write)'
        WHEN W1.wait_type LIKE 'PAGELATCH%' THEN 'Buffer/TempDB'
        WHEN W1.wait_type = 'CXPACKET' THEN 'Parallelism'
        WHEN W1.wait_type = 'SOS_SCHEDULER_YIELD' THEN 'CPU'
        WHEN W1.wait_type = 'RESOURCE_SEMAPHORE' THEN 'Memory'
        WHEN W1.wait_type = 'ASYNC_NETWORK_IO' THEN 'Network/Client'
        ELSE 'Other'
    END AS [Wait_Category],
    CASE 
        WHEN W1.wait_type LIKE 'LCK%' THEN 'Locking / Blocking contention. Recommendation: Identify active blocking session, optimize query transactions, or modify isolation level (e.g. RCSI).'
        WHEN W1.wait_type LIKE 'PAGEIOLATCH%' THEN 'Disk to Memory transfer bottleneck. Recommendation: Improve indexing to avoid large table scans, or scale memory/I/O throughput.'
        WHEN W1.wait_type LIKE 'PAGELATCH%' THEN 'In-memory buffer contention (common in TempDB allocation pages). Recommendation: Optimize TempDB file allocation or review page-splits.'
        WHEN W1.wait_type = 'CXPACKET' THEN 'Parallel task coordination. Recommendation: Often occurs alongside other wait types. Investigate high-cost plans, increase CTFP configuration.'
        WHEN W1.wait_type = 'ASYNC_NETWORK_IO' THEN 'App server processing wait. Recommendation: Client application is processing rows too slowly or fetching massive datasets (RBAR).'
        WHEN W1.wait_type = 'RESOURCE_SEMAPHORE' THEN 'Query memory grant starvation. Recommendation: Optimize memory-heavy sorts/hashes or scale system memory.'
        ELSE 'Generic wait type. Review MSDN documentation or correlate with concurrent performance traces.'
    END AS [Best_Practice_Recommendation],
    CAST('Aggregates and formats cumulative wait stats. ' + 
         'Threshold: Top 3 wait types usually make up 80%+ of bottlenecks. ' +
         'Recommendation: Target optimization efforts on the highest percentage wait types.'
         AS VARCHAR(1000)) AS [Metric_Context]
FROM [WaitStats] AS W1
CROSS JOIN [WaitStats] AS W2
WHERE W2.Row_Num <= 20 -- Limits percentage calculation base to top 20 wait types
GROUP BY W1.wait_type, W1.Wait_S, W1.Resource_S, W1.Signal_S, W1.Wait_Count, W1.Row_Num
HAVING W1.Row_Num <= 20
ORDER BY W1.Wait_S DESC;
