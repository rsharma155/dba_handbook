/*
================================================================================
Storage I/O Latency Deep Dive (Post-Migration)
================================================================================
Purpose:
    High elapsed + low CPU + low logical reads can still be I/O bound when:
    - System databases (master/tempdb) pages are cold
    - Transaction log WRITELOG waits occur between statements
    - Metadata pages read with few user-table logical reads

    Running on local VM does NOT eliminate disk latency.

Checks:
    (1) Per-file read/write stall averages
    (2) Pending I/O requests
    (3) IO latch waits active now
    (4) Database files on slow volumes / growth settings

Thresholds:
    < 5 ms avg  = good
    5-15 ms     = acceptable
    15-20 ms    = warning
    > 20 ms     = critical — storage investigation required

Next action:
    Move log/data to faster volume; check VM storage policy; exclude SQL paths from AV
    08_Storage_OS/02_os_integration_post_migration.sql

Criticality: High
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

PRINT '=== FILE-LEVEL LATENCY (all databases) ===';
SELECT
    DB_NAME(vfs.database_id) AS [Database_Name],
    mf.name AS [Logical_File],
    mf.physical_name AS [Physical_Path],
    mf.type_desc AS [File_Type],
    mf.size * 8 / 1024 AS [Size_MB],
    mf.growth,
    mf.is_percent_growth,
    CAST(vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) AS DECIMAL(10,2)) AS [Avg_Read_ms],
    CAST(vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) AS DECIMAL(10,2)) AS [Avg_Write_ms],
    CAST(vfs.io_stall / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) AS DECIMAL(10,2)) AS [Avg_IO_ms],
    CASE
        WHEN vfs.io_stall / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) > 20 THEN N'CRITICAL'
        WHEN vfs.io_stall / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) > 15 THEN N'WARNING'
        ELSE N'OK'
    END AS [Status],
    CASE
        WHEN mf.type_desc = N'LOG' AND vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) > 15
            THEN N'Log write latency — impacts every transaction commit'
        WHEN DB_NAME(vfs.database_id) = N'tempdb' AND vfs.io_stall > 0
            THEN N'TempDB IO — affects all workloads using sorts/hashes'
        ELSE N'Review volume type (HDD vs SSD/NVMe)'
    END AS [Post_Migration_Note]
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
INNER JOIN sys.master_files AS mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
ORDER BY [Avg_IO_ms] DESC;

PRINT '=== PENDING I/O (dm_io_pending_io_requests) ===';
SELECT
    COUNT(*) AS [Pending_IO_Count],
    SUM(io_pending_ms_ticks) AS [Total_Pending_ms],
    MAX(io_pending_ms_ticks) AS [Max_Pending_ms],
    CASE WHEN COUNT(*) > 10 THEN N'IO subsystem backlog — correlate with PAGEIOLATCH waits'
         ELSE N'No significant pending IO at snapshot'
    END AS [Interpretation]
FROM sys.dm_io_pending_io_requests;

PRINT '=== ACTIVE IO-RELATED WAITS ===';
SELECT
    session_id,
    wait_type,
    wait_duration_ms,
    resource_description
FROM sys.dm_os_waiting_tasks
WHERE wait_type LIKE N'PAGEIOLATCH%'
   OR wait_type = N'WRITELOG'
   OR wait_type = N'IO_COMPLETION'
ORDER BY wait_duration_ms DESC;

PRINT '=== WHY LOW LOGICAL READS + HIGH ELAPSED CAN STILL BE IO ===';
SELECT
    N'Logical reads only count user data pages in buffer pool.' AS [Point_1],
    N'WRITELOG waits happen on log flush — zero user logical reads.' AS [Point_2],
    N'First-touch reads after restart show PAGEIOLATCH with few cached pages.' AS [Point_3],
    N'Post-migration file relocation to slower disk is a common root cause.' AS [Point_4];
