/*
================================================================================
Purpose:        Analyzes read and write latencies (stalls) per database and 
                transaction log file.
Provides:       Average Read, Write, and Total stalls (ms) per file.
Importance:     Disk I/O is often the slowest component; high latency directly 
                throttles transaction throughput.
 Interpretation: <1ms = Excellent; 1-15ms = Acceptable; 15-20ms = Warning; 
                >20ms = Critical.
Action:         If Avg_Read_Stall_ms or Avg_Write_Stall_ms > 20ms for data files, move the affected database files to faster storage (SSD/SAN). For log files with > 20ms latency, separate logs from data on different physical drives. Run tempdb_configuration.sql if tempdb files show high latency.
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT 
    DB_NAME(vfs.database_id) AS [Database_Name],
    mf.name AS [Logical_File_Name],
    mf.physical_name AS [Physical_Path],
    mf.type_desc AS [File_Type],
    vfs.num_of_reads AS [Total_Reads],
    vfs.num_of_writes AS [Total_Writes],
    -- Calculate Average Read Stall
    CAST(vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) AS NUMERIC(10,1)) AS [Avg_Read_Stall_ms],
    -- Calculate Average Write Stall
    CAST(vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) AS NUMERIC(10,1)) AS [Avg_Write_Stall_ms],
    -- Calculate Average Latency Overall
    CAST(vfs.io_stall / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) AS NUMERIC(10,1)) AS [Avg_IO_Stall_ms],
    CAST('Analyzes disk latency per file. ' + 
         'Threshold: <1ms = Excellent; 1-5ms = Very Good; 5-15ms = Acceptable; 15-20ms = Warning; >20ms = Critical. ' +
         'Recommendation: If stalls are high on log files, move logs to dedicated fast storage (SSD/NVMe). If data file stalls are high, evaluate memory/buffer pool hit ratios to verify if too much physical read is occurring.'
         AS VARCHAR(1000)) AS [Metric_Context]
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
INNER JOIN sys.master_files AS mf WITH (NOLOCK)
   ON vfs.database_id = mf.database_id 
  AND vfs.file_id = mf.file_id
ORDER BY [Avg_IO_Stall_ms] DESC;

-- 2. Top 10 File-Level Latency Hotspots
PRINT '--- Top 10 File-Level Latency Hotspots ---';
SELECT TOP 10
    DB_NAME(vfs.database_id) AS [DB],
    mf.name AS [File],
    vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) AS [Read_Latency],
    vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) AS [Write_Latency],
    CASE 
        WHEN (vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) > 50) OR (vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) > 50) THEN '🔴 CRITICAL'
        WHEN (vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) > 20) OR (vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) > 20) THEN '🟡 WARNING'
        ELSE '🟢 OPTIMAL'
    END AS [Disk_Status]
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
INNER JOIN sys.master_files AS mf WITH (NOLOCK) ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
ORDER BY (vfs.io_stall / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0)) DESC;
