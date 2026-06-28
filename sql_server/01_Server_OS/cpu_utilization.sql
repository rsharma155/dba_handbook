/*
================================================================================
Purpose:        Analyzes historical CPU usage from OS ring buffers and evaluates 
                current thread scheduling health via Signal Wait ratio.
Provides:       Historical CPU metrics (last ~256 mins), Signal Wait Pct, 
                Scheduler Health (runnable tasks).
Importance:     CPU is a critical resource; high utilization or scheduling pressure 
                directly impacts query performance and instance stability.
 Interpretation: Historical CPU > 80% requires investigation. Signal Waits > 25% 
                indicates CPU bottleneck. Runnable tasks > 10 is critical CPU starvation.
Action:         If Historical CPU > 80%, identify top resource consumers via top_resource_queries.sql. If Signal Wait % > 25%, review MAXDOP and Cost Threshold for Parallelism settings via server_configuration_audit.sql. If Runnable Tasks > 10 sustained, CPU is oversubscribed — reduce parallelism or add cores.
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'dbo.fn_DBA_ExcludedWaitTypes', N'IF') IS NULL
    AND NOT EXISTS (SELECT 1 FROM DBARepository.sys.objects WHERE name = N'fn_DBA_ExcludedWaitTypes' AND type = 'IF')
BEGIN
    RAISERROR(N'Run 00_Framework/00_Deploy_Framework.ps1 (-ServerInstance . -Database master) to auto-deploy all required objects, or deploy fn_DBA_ExcludedWaitTypes manually.', 16, 1);
    RETURN;
END;

-- 1. Historical CPU Usage from System Health Ring Buffer
DECLARE @ts_now BIGINT;
SELECT @ts_now = cpu_ticks / (cpu_ticks / ms_ticks) 
FROM sys.dm_os_sys_info WITH (NOLOCK);

SELECT TOP (256)
    DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) AS [Event_Time],
    SQLProcessUtilization AS [SQL_Server_CPU_Pct],
    SystemIdle AS [System_Idle_Pct],
    100 - SystemIdle - SQLProcessUtilization AS [Other_Process_CPU_Pct],
    CAST('Historical CPU metrics parsed from SQL Server system ring buffers. ' + 
         'Threshold: Sustained CPU > 80% requires investigation. ' +
         'Recommendation: If Other Process CPU is high, check external processes (e.g., antivirus, backups). ' +
         'If SQL Server CPU is high, check top resource-consuming queries and missing indexes.' 
         AS VARCHAR(1000)) AS [Metric_Context]
FROM (
    SELECT 
        record.value('(./Record/@id)[1]', 'int') AS record_id,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
        [timestamp]
    FROM (
        SELECT [timestamp], CONVERT(xml, record) AS [record]
        FROM sys.dm_os_ring_buffers WITH (NOLOCK)
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
          AND record LIKE N'%<SystemHealth>%'
    ) AS x
) AS y
ORDER BY [Event_Time] DESC;

-- 2. Signal Wait Ratio (CPU Scheduling Pressure)
SELECT 
    SUM(signal_wait_time_ms) AS [Signal_Wait_Time_ms],
    SUM(wait_time_ms) AS [Total_Wait_Time_ms],
    CAST(CAST(SUM(signal_wait_time_ms) AS NUMERIC(18,2)) / 
         NULLIF(SUM(wait_time_ms), 0) * 100 AS DECIMAL(5,2)) AS [Signal_Wait_Pct],
    CAST('Signal wait time measures the time a thread had to wait in the runnable queue after its resource became available. ' +
         'Threshold: Signal Waits > 25% of Total Waits indicates significant CPU bottleneck / scheduling pressure. ' +
         'Recommendation: If > 25%, look into parallelism configurations (MAXDOP, Cost Threshold), compile locks, or CPU capacity scaling.' 
         AS VARCHAR(1000)) AS [Metric_Context]
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes()
);

-- 3. Scheduler Pressure (Runnable Tasks)
PRINT '--- Scheduler Health & Runnable Tasks ---';
SELECT 
    parent_node_id,
    scheduler_id,
    cpu_id,
    status,
    is_online,
    runnable_tasks_count,
    current_workers_count,
    CASE 
        WHEN runnable_tasks_count > 10 THEN '🔴 CRITICAL: High runnable tasks indicating CPU starvation.'
        WHEN runnable_tasks_count > 0 THEN '🟡 WARNING: Threads are waiting for CPU cycles.'
        ELSE '🟢 OPTIMAL'
    END AS [Scheduler_Status]
FROM sys.dm_os_schedulers
WHERE status = 'VISIBLE ONLINE';
