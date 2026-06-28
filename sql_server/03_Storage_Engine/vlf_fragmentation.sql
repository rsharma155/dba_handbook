/*
================================================================================
Purpose:        Retrieves VLF count per database to identify transaction log 
                fragmentation across the entire instance.
Provides:       VLF count and total log size (MB) per database.
Importance:     High VLF counts degrade replication, backup, and crash recovery 
                speed.
 Interpretation: <200 = Good; 200-500 = Warning; >1000 = Critical.
Action:         If VLF_Count > 1000 for any database, schedule a log file rebuild during maintenance:
                    1. Shrink the log file: DBCC SHRINKFILE (logical_name, TRUNCATEONLY)
                    2. Grow back in large chunks: ALTER DATABASE ... MODIFY FILE (SIZE = <new_size>, FILEGROWTH = <large_increment>)
                    Use uniform growth increments (e.g., 8GB) to prevent future VLF proliferation.
Criticality:    Medium
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT 
    d.name AS [Database_Name],
    vlf_info.vlf_count AS [VLF_Count],
    vlf_info.total_log_size_mb AS [Total_Log_Size_MB],
    CAST('Virtual Log Files (VLFs) partition the physical transaction log file. ' + 
         'Threshold: <200 = Excellent/Good; 200-500 = Warning; >1000 = Critical (high VLF count degrades replication, backup, and crash recovery speed). ' +
         'Recommendation: If VLF count is critical, shrink the transaction log file during maintenance, then manually grow it back using large, discrete growth increments (e.g., grow by 8GB blocks) to generate fewer, larger VLFs.'
         AS VARCHAR(1000)) AS [Metric_Context]
FROM sys.databases AS d WITH (NOLOCK)
CROSS APPLY (
    SELECT 
        COUNT(*) AS vlf_count,
        CAST(SUM(vlf_size_mb) AS NUMERIC(18,2)) AS total_log_size_mb
    FROM sys.dm_db_log_info(d.database_id)
) AS vlf_info
WHERE d.state = 0 AND d.database_id > 4
ORDER BY [VLF_Count] DESC;
