/*
================================================================================
SQL Server Baseline Snapshot Capture (Lightweight)
================================================================================
Description:
    Captures a point-in-time snapshot of key performance metrics: wait stats,
    performance counters, OS info, and file I/O stall data. Use this before
    and after making changes to measure impact, or capture regularly for
    historical trending.

Output:
    (1) Instance performance counters (CPU, memory, I/O, batch requests)
    (2) Top waits with wait times
    (3) Database file I/O stalls

Action:
    Run this script BEFORE and AFTER any major change (configuration change,
    index rebuild, query optimization, hardware upgrade). Compare the two
    snapshots to quantify the impact. For ongoing monitoring, schedule this
    script hourly via SQL Agent and store results in a baseline table.
    Cross-reference with sp_DBA_BaselineCapture for persistent storage.

Criticality: Low
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT sqlserver_start_time AS [Instance_Start_Time], N'Cumulative counters below are since this time.' AS [Note]
FROM sys.dm_os_sys_info;

-- 1. Instance Performance Counters Snapshot
PRINT '--- Baseline: Performance Counters Snapshot ---';
SELECT 
    GETDATE() AS [Snapshot_Time],
    object_name,
    counter_name,
    instance_name,
    cntr_value,
    cntr_type
FROM sys.dm_os_performance_counters
WHERE counter_name IN (
    N'Page life expectancy', N'Batch Requests/sec', N'SQL Compilations/sec', 
    N'SQL Re-Compilations/sec', N'User Connections', N'Lock Waits/sec',
    N'Buffer cache hit ratio', N'Buffer cache hit ratio base'
)
AND (object_name LIKE N'%Buffer Manager%' OR object_name LIKE N'%SQL Statistics%' OR object_name LIKE N'%General Statistics%' OR object_name LIKE N'%Locks%');

-- 2. Instance Wait Stats Snapshot (Cumulative)
PRINT '--- Baseline: Cumulative Wait Stats ---';
IF OBJECT_ID(N'dbo.fn_DBA_ExcludedWaitTypes', N'IF') IS NOT NULL
BEGIN
    SELECT 
        GETDATE() AS [Snapshot_Time],
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE wait_time_ms > 1000
      AND wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes())
    ORDER BY wait_time_ms DESC;
END
ELSE
BEGIN
    RAISERROR(N'Install 00_Framework for filtered wait stats snapshot.', 10, 1);
    SELECT GETDATE() AS [Snapshot_Time], wait_type, waiting_tasks_count, wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE wait_time_ms > 1000
    ORDER BY wait_time_ms DESC;
END;

-- 3. I/O File Stats Snapshot
PRINT '--- Baseline: File I/O Stats ---';
SELECT
    GETDATE() AS [Snapshot_Time],
    DB_NAME(vfs.database_id) AS [Database_Name],
    mf.name AS [File_Name],
    vfs.num_of_reads,
    vfs.num_of_writes,
    vfs.io_stall_read_ms,
    vfs.io_stall_write_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
INNER JOIN sys.master_files AS mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id;
