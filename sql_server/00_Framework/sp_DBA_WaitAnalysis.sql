/*
================================================================================
sp_DBA_WaitAnalysis — Top wait types with categories and recommendations
================================================================================
Returns the top N wait types with percentage calculation, category mapping,
and expert recommendations. Uses fn_DBA_ExcludedWaitTypes for filtering.

Usage:
    EXEC dbo.sp_DBA_WaitAnalysis;
    EXEC dbo.sp_DBA_WaitAnalysis @TopN = 30, @IncludeRecommendations = 1;
================================================================================
*/
IF OBJECT_ID(N'dbo.sp_DBA_WaitAnalysis', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DBA_WaitAnalysis AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_DBA_WaitAnalysis
    @TopN                   INT = 20,
    @IncludeRecommendations BIT = 1,
    @MinWaitCount           INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @TotalWaitMs BIGINT;

    SELECT @TotalWaitMs = SUM(wait_time_ms)
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes())
      AND waiting_tasks_count > @MinWaitCount;

    ;WITH WaitCTE AS (
        SELECT
            ws.wait_type,
            ws.waiting_tasks_count AS Wait_Count,
            ws.wait_time_ms / 1000.0 AS Total_Wait_S,
            (ws.wait_time_ms - ws.signal_wait_time_ms) / 1000.0 AS Resource_Wait_S,
            ws.signal_wait_time_ms / 1000.0 AS Signal_Wait_S,
            CAST(ws.wait_time_ms * 100.0 / NULLIF(@TotalWaitMs, 0) AS DECIMAL(5,2)) AS Pct_Of_All_Waits,
            CAST(ws.signal_wait_time_ms * 100.0 / NULLIF(ws.wait_time_ms, 0) AS DECIMAL(5,2)) AS Signal_Pct,
            CASE
                -- Parallelism
                WHEN ws.wait_type IN ('CXPACKET','CXCONSUMER','CXPA','EXECSYNC')
                    THEN 'Parallelism'
                -- CPU / Scheduling
                WHEN ws.wait_type IN ('SOS_SCHEDULER_YIELD','THREADPOOL','RESOURCE_POOL')
                    THEN 'CPU'
                -- I/O
                WHEN ws.wait_type LIKE 'PAGEIOLATCH_%'
                    THEN 'Disk I/O'
                WHEN ws.wait_type IN ('WRITELOG','LOGMGR','LOGBUFFER','LOGGR池')
                    THEN 'Transaction Log'
                WHEN ws.wait_type IN ('ASYNC_DISKPOOL_LOCK','FILE_IO')
                    THEN 'Disk I/O'
                -- Memory
                WHEN ws.wait_type IN ('RESOURCE_SEMAPHORE','RESOURCE_SEMAPHORE_POOL')
                    THEN 'Memory'
                WHEN ws.wait_type LIKE 'MEMORY_ALLOCATION_%'
                    THEN 'Memory'
                -- Locking / Blocking
                WHEN ws.wait_type LIKE 'LCK_%'
                    THEN 'Locking'
                WHEN ws.wait_type IN ('PAGELATCH_%','PAGELATCH_SH','PAGELATCH_EX','PAGELATCH_UP')
                    THEN 'In-Memory Latch'
                -- Network
                WHEN ws.wait_type IN ('ASYNC_NETWORK_IO','NETWAITFORREPLY','NETWORKIO')
                    THEN 'Network / Client'
                -- Replication / AG
                WHEN ws.wait_type LIKE 'HADR_%'
                    THEN 'AlwaysOn AG'
                WHEN ws.wait_type LIKE 'REPL_%'
                    THEN 'Replication'
                -- TempDB
                WHEN ws.wait_type IN ('PFS_SYNC','GAM_CONTENTION','SGAM_CONTENTION','ALLOCATE_SPACE')
                    THEN 'TempDB Allocation'
                ELSE 'Other'
            END AS Wait_Category
        FROM sys.dm_os_wait_stats AS ws
        WHERE ws.wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes())
          AND ws.waiting_tasks_count > @MinWaitCount
    )
    SELECT TOP (@TopN)
        wait_type AS Wait_Type,
        Wait_Count,
        Total_Wait_S,
        Resource_Wait_S,
        Signal_Wait_S,
        Pct_Of_All_Waits,
        Signal_Pct,
        Wait_Category,
        CASE WHEN @IncludeRecommendations = 1 THEN
            CASE Wait_Category
                WHEN 'Parallelism' THEN 'Review MAXDOP and CTFP settings. Consider increasing CTFP to 50+. https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/configure-the-cost-threshold-for-parallelism-server-configuration-option'
                WHEN 'CPU' THEN 'CPU pressure. Check top queries and scheduler health. https://learn.microsoft.com/en-us/sql/relational-databases/system-dm-views/sys-dm-os-schedulers-transact-sql'
                WHEN 'Disk I/O' THEN 'Check disk latency (disk_latency.sql) and indexing. https://learn.microsoft.com/en-us/sql/relational-databases/system-dm-views/sys-dm-io-virtual-file-stats-transact-sql'
                WHEN 'Transaction Log' THEN 'Log I/O bottleneck. Check log file location and VLF count. https://learn.microsoft.com/en-us/sql/relational-databases/logs/manage-the-size-of-the-transaction-log-file'
                WHEN 'Memory' THEN 'Memory grant pressure. Check memory grants and server memory config. https://learn.microsoft.com/en-us/sql/relational-databases/system-dm-views/sys-dm-exec-query-memory-grants-transact-sql'
                WHEN 'Locking' THEN 'Blocking detected. Run blocking_and_deadlocks.sql. https://learn.microsoft.com/en-us/sql/relational-databases/system-dm-views/sys-dm-tran-locks-transact-sql'
                WHEN 'In-Memory Latch' THEN 'In-memory contention. Often TempDB — check tempdb_configuration.sql. https://learn.microsoft.com/en-us/sql/relational-databases/system-dm-views/sys-dm-os-wait-stats-transact-sql'
                WHEN 'Network / Client' THEN 'Client application consuming results slowly. Check app-side fetch patterns. https://learn.microsoft.com/en-us/sql/relational-databases/system-dm-views/sys-dm-exec-connections-transact-sql'
                WHEN 'AlwaysOn AG' THEN 'AG sync or redo bottleneck. Run alwayson_ag_monitor.sql. https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-group-listener-server-client-connectivity'
                WHEN 'Replication' THEN 'Replication lag. Check distribution agent history. https://learn.microsoft.com/en-us/sql/relational-databases/replication/monitor/replication-monitor-overview'
                WHEN 'TempDB Allocation' THEN 'TempDB allocation contention. Run tempdb_configuration.sql. https://learn.microsoft.com/en-us/sql/relational-databases/databases/tempdb-database'
                ELSE 'Review wait type: https://learn.microsoft.com/en-us/sql/relational-databases/system-dm-views/sys-dm-os-wait-stats-transact-sql'
            END
        ELSE NULL END AS Recommendation
    INTO #WaitResults
    FROM WaitCTE
    ORDER BY Total_Wait_S DESC;

    SELECT * FROM #WaitResults ORDER BY Total_Wait_S DESC;
    DROP TABLE #WaitResults;
END;
GO
