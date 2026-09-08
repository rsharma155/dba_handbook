/* SQL_Server_Assessment */
-- Inner TOP(30) still selects the files with the highest cumulative stall; the
-- outer SELECT re-orders them by database for readability. The Assessment column
-- follows common latency guidance: <=20 ms good, 20-100 ms marginal, >100 ms poor.
;WITH worst AS (
    SELECT TOP (30) DB_NAME(v.database_id) AS DatabaseName, mf.type_desc AS FileType,
           mf.physical_name AS PhysicalName, v.num_of_reads AS Reads, v.num_of_writes AS Writes,
           CAST(v.io_stall_read_ms*1.0/NULLIF(v.num_of_reads,0) AS decimal(18,2)) AS AvgReadLatencyMs,
           CAST(v.io_stall_write_ms*1.0/NULLIF(v.num_of_writes,0) AS decimal(18,2)) AS AvgWriteLatencyMs
    FROM sys.dm_io_virtual_file_stats(NULL,NULL) v
    JOIN sys.master_files mf ON v.database_id=mf.database_id AND v.file_id=mf.file_id
    ORDER BY (v.io_stall_read_ms+v.io_stall_write_ms) DESC
)
SELECT DatabaseName, FileType, PhysicalName, Reads, Writes, AvgReadLatencyMs, AvgWriteLatencyMs,
       CASE WHEN ISNULL(AvgReadLatencyMs,0) > 100 OR ISNULL(AvgWriteLatencyMs,0) > 100 THEN 'Poor (>100 ms)'
            WHEN ISNULL(AvgReadLatencyMs,0) > 20 OR ISNULL(AvgWriteLatencyMs,0) > 20 THEN 'Marginal (20-100 ms)'
            ELSE 'Good (<=20 ms)' END AS Assessment
FROM worst
ORDER BY DatabaseName, FileType, PhysicalName;
