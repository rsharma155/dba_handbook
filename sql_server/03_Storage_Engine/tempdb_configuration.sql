/*
================================================================================
Purpose:        Analyzes TempDB file allocations (file counts, uniformity of 
                sizes/growths) and identifies PAGELATCH allocation bottlenecks.
Provides:       TempDB file counts, growth uniformity, active PAGELATCH 
                contention.
Importance:     TempDB is a shared resource; contention here bottlenecks the 
                entire instance.
 Interpretation: Files should match cores (up to 8). Mismatched growth is 
                critical. PAGELATCH waits indicate contention.
Action:         If file count < @ExpectedFiles, add equal-sized data files (1 per core/CPU up to 8). If file sizes are not uniform, resize all files to the same size. If PAGELATCH waits are detected, adding files often resolves allocation contention. Restart is NOT required after adding TempDB files.
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

-- 1. TempDB File Configuration Analysis
PRINT '--- TempDB File Configuration & Uniformity ---';
DECLARE @LogCores INT = (SELECT cpu_count FROM sys.dm_os_sys_info);
DECLARE @ExpectedFiles INT = CASE WHEN @LogCores <= 8 THEN @LogCores ELSE 8 END;

SELECT 
    name AS [Logical_File_Name],
    type_desc AS [File_Type],
    size * 8 / 1024 AS [Size_MB],
    growth AS [Growth_Value],
    is_percent_growth AS [Is_Percent_Growth],
    CASE 
        WHEN is_percent_growth = 1 THEN '🔴 CRITICAL: Use fixed-size growth (e.g. 256MB) to ensure uniformity.'
        WHEN growth <> (SELECT TOP 1 growth FROM sys.master_files WHERE database_id = 2 AND type = 0 ORDER BY file_id) 
             THEN '🔴 CRITICAL: Mismatched growth increments will break proportional fill.'
        ELSE '🟢 OPTIMAL'
    END AS [Growth_Uniformity_Status],
    (SELECT COUNT(*) FROM sys.master_files WHERE database_id = 2 AND type = 0) AS [Data_Files_Count],
    @ExpectedFiles AS [Target_Data_Files],
    CASE 
        WHEN (SELECT COUNT(*) FROM sys.master_files WHERE database_id = 2 AND type = 0) < @ExpectedFiles 
             THEN '🟡 WARNING: File count should match logical cores up to 8.'
        ELSE '🟢 OPTIMAL'
    END AS [File_Count_Status]
FROM sys.master_files WITH (NOLOCK)
WHERE database_id = 2; -- TempDB database_id is 2

-- 2. Detect TempDB PAGELATCH Contention (PFS, GAM, SGAM)
PRINT '--- Active TempDB PAGELATCH Contention (Allocation Pages) ---';
SELECT 
    session_id,
    wait_type,
    wait_duration_ms,
    resource_description,
    CASE 
        WHEN resource_description LIKE '2:%:1' OR resource_description LIKE '2:%:125440' THEN '🔴 CRITICAL: PFS page contention. More files or uniform growth needed.'
        WHEN resource_description LIKE '2:%:2' THEN '🔴 CRITICAL: GAM page contention.'
        WHEN resource_description LIKE '2:%:3' THEN '🔴 CRITICAL: SGAM page contention.'
        ELSE '⚪ INFO: Other Page Contention'
    END AS [Expert_Guidance]
FROM sys.dm_os_waiting_tasks WITH (NOLOCK)
WHERE wait_type LIKE 'PAGELATCH_%'
  AND resource_description LIKE '2:%'; -- Database 2 is TempDB

-- 3. Historical Allocation Contention (Waits)
PRINT '--- Historical Allocation Contention (Waits) ---';
SELECT 
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    CASE 
        WHEN wait_type IN ('PAGELATCH_UP', 'PAGELATCH_EX', 'PAGELATCH_SH') THEN '🟡 WARNING: Potential TempDB Metadata/Allocation bottleneck'
        ELSE '🟢 NORMAL'
    END AS [Wait_Status]
FROM sys.dm_os_wait_stats
WHERE wait_type LIKE 'PAGELATCH_%'
  AND waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;
