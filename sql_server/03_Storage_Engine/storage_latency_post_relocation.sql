/*
================================================================================
Storage Latency Deep Dive — Post MDF/LDF Relocation
================================================================================
Purpose:
    Validate I/O performance after moving database data (MDF/NDF) or log (LDF)
    files to new volumes. Identifies slow files, volume placement issues, and
    active I/O waits correlated with relocated paths.

DMVs used:
    sys.dm_io_virtual_file_stats
    sys.dm_io_pending_io_requests
    sys.dm_os_waiting_tasks
    sys.dm_os_performance_counters (physical disk counters when exposed)
    sys.master_files / sys.database_files

Parameters:
    @DatabaseList - comma-separated database names or NULL for all databases
    @WarnLatencyMs - warning threshold for avg read/write ms (default 15)
    @CritLatencyMs - critical threshold for avg read/write ms (default 20)

Thresholds:
    < 5 ms   good (SSD/NVMe typical)
    5-15 ms  acceptable
    15-20 ms warning
    > 20 ms  critical — storage investigation

Checks:
    (1)  File inventory with physical path, volume, size, growth
    (2)  Per-file read/write latency and IOPS since startup
    (3)  MDF vs LDF latency summary by database
    (4)  Data+log on same volume warnings
    (5)  Pending I/O backlog
    (6)  Active PAGEIOLATCH / WRITELOG / IO_COMPLETION waits
    (7)  Windows physical disk counters (if available)
    (8)  Relocation findings summary

Action:
    Log file > 15-20 ms write -> move LDF to dedicated fast volume
    Data file high read latency -> verify storage tier, AV exclusions, memory
    Data+log same slow volume -> split files across volumes
    High pending IO + PAGEIOLATCH -> engage storage team / VM host

Criticality: High after file relocation or migration
Prerequisites: VIEW SERVER STATE
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @WarnLatencyMs DECIMAL(10, 2) = 15.0;
DECLARE @CritLatencyMs DECIMAL(10, 2) = 20.0;

IF OBJECT_ID(N'tempdb..#DbFilter') IS NOT NULL DROP TABLE #DbFilter;
CREATE TABLE #DbFilter (database_id INT NOT NULL PRIMARY KEY);

IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
    INSERT INTO #DbFilter (database_id)
    SELECT d.database_id
    FROM sys.databases AS d
    INNER JOIN (
        SELECT LTRIM(RTRIM(value)) AS database_name
        FROM STRING_SPLIT(@DatabaseList, N',')
        WHERE LTRIM(RTRIM(value)) <> N''
    ) AS req ON req.database_name = d.name;
ELSE
    INSERT INTO #DbFilter (database_id)
    SELECT database_id FROM sys.databases WHERE database_id > 0;

PRINT N'=== (1) DATABASE FILE INVENTORY (paths after relocation) ===';

SELECT
    DB_NAME(mf.database_id) AS [Database_Name],
    mf.name AS [Logical_File_Name],
    mf.type_desc AS [File_Type],
    mf.physical_name AS [Physical_Path],
    UPPER(LEFT(mf.physical_name, 1)) AS [Drive_Letter],
    mf.state_desc AS [File_State],
    mf.size * 8 / 1024 AS [Size_MB],
    mf.growth AS [Growth_Value],
    mf.is_percent_growth AS [Is_Percent_Growth],
    CASE
        WHEN mf.is_percent_growth = 1 THEN N'Percent growth - prefer fixed MB growth on prod'
        WHEN mf.growth = 0 THEN N'Fixed size - autogrowth disabled'
        ELSE N'Fixed MB growth'
    END AS [Growth_Note]
FROM sys.master_files AS mf
INNER JOIN #DbFilter AS df ON mf.database_id = df.database_id
ORDER BY [Database_Name], mf.type_desc, mf.name;

PRINT N'=== (2) PER-FILE I/O LATENCY (since startup / last restart) ===';

SELECT
    DB_NAME(vfs.database_id) AS [Database_Name],
    mf.name AS [Logical_File_Name],
    mf.type_desc AS [File_Type],
    mf.physical_name AS [Physical_Path],
    UPPER(LEFT(mf.physical_name, 1)) AS [Drive_Letter],
    vfs.num_of_reads AS [Reads],
    vfs.num_of_writes AS [Writes],
    vfs.io_stall_read_ms AS [Total_Read_Stall_ms],
    vfs.io_stall_write_ms AS [Total_Write_Stall_ms],
    CAST(vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) AS DECIMAL(10, 2)) AS [Avg_Read_ms],
    CAST(vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) AS DECIMAL(10, 2)) AS [Avg_Write_ms],
    CAST(vfs.io_stall / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) AS DECIMAL(10, 2)) AS [Avg_IO_ms],
    CASE
        WHEN mf.type_desc = N'LOG'
             AND vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) > @CritLatencyMs THEN N'CRITICAL log write latency'
        WHEN mf.type_desc = N'ROWS'
             AND vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) > @CritLatencyMs THEN N'CRITICAL data read latency'
        WHEN vfs.io_stall / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) > @CritLatencyMs THEN N'CRITICAL'
        WHEN vfs.io_stall / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) > @WarnLatencyMs THEN N'WARNING'
        ELSE N'OK'
    END AS [Latency_Status],
    CASE
        WHEN mf.type_desc = N'LOG' AND vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) > @WarnLatencyMs
            THEN N'Log on slow volume - every commit waits on WRITELOG'
        WHEN mf.type_desc = N'ROWS' AND vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) > @WarnLatencyMs
            THEN N'Data reads slow - check tier, caching, memory, AV scan'
        WHEN vfs.num_of_reads + vfs.num_of_writes < 100
            THEN N'Low I/O volume - latency may be noisy; re-check under workload'
        ELSE N''
    END AS [Relocation_Note]
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
INNER JOIN sys.master_files AS mf
    ON vfs.database_id = mf.database_id
   AND vfs.file_id = mf.file_id
INNER JOIN #DbFilter AS df ON vfs.database_id = df.database_id
ORDER BY [Avg_IO_ms] DESC, [Total_Write_Stall_ms] DESC;

PRINT N'=== (3) MDF vs LDF LATENCY BY DATABASE ===';

SELECT
    DB_NAME(vfs.database_id) AS [Database_Name],
    SUM(CASE WHEN mf.type_desc = N'ROWS' THEN vfs.num_of_reads ELSE 0 END) AS [Data_Reads],
    SUM(CASE WHEN mf.type_desc = N'ROWS' THEN vfs.io_stall_read_ms ELSE 0 END) AS [Data_Read_Stall_ms],
    CAST(
        SUM(CASE WHEN mf.type_desc = N'ROWS' THEN vfs.io_stall_read_ms ELSE 0 END)
        / NULLIF(SUM(CASE WHEN mf.type_desc = N'ROWS' THEN vfs.num_of_reads ELSE 0 END), 0)
        AS DECIMAL(10, 2)
    ) AS [Data_Avg_Read_ms],
    SUM(CASE WHEN mf.type_desc = N'LOG' THEN vfs.num_of_writes ELSE 0 END) AS [Log_Writes],
    SUM(CASE WHEN mf.type_desc = N'LOG' THEN vfs.io_stall_write_ms ELSE 0 END) AS [Log_Write_Stall_ms],
    CAST(
        SUM(CASE WHEN mf.type_desc = N'LOG' THEN vfs.io_stall_write_ms ELSE 0 END)
        / NULLIF(SUM(CASE WHEN mf.type_desc = N'LOG' THEN vfs.num_of_writes ELSE 0 END), 0)
        AS DECIMAL(10, 2)
    ) AS [Log_Avg_Write_ms],
    CASE
        WHEN SUM(CASE WHEN mf.type_desc = N'LOG' THEN vfs.io_stall_write_ms ELSE 0 END)
             / NULLIF(SUM(CASE WHEN mf.type_desc = N'LOG' THEN vfs.num_of_writes ELSE 0 END), 0) > @CritLatencyMs
            THEN N'Log path bottleneck after relocation'
        WHEN SUM(CASE WHEN mf.type_desc = N'ROWS' THEN vfs.io_stall_read_ms ELSE 0 END)
             / NULLIF(SUM(CASE WHEN mf.type_desc = N'ROWS' THEN vfs.num_of_reads ELSE 0 END), 0) > @CritLatencyMs
            THEN N'Data path bottleneck after relocation'
        ELSE N'Within thresholds at aggregate level'
    END AS [Database_IO_Status]
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
INNER JOIN sys.master_files AS mf
    ON vfs.database_id = mf.database_id
   AND vfs.file_id = mf.file_id
INNER JOIN #DbFilter AS df ON vfs.database_id = df.database_id
GROUP BY vfs.database_id
ORDER BY [Log_Avg_Write_ms] DESC, [Data_Avg_Read_ms] DESC;

PRINT N'=== (4) DATA + LOG ON SAME VOLUME (placement risk) ===';

;WITH FileVolumes AS (
    SELECT
        DB_NAME(mf.database_id) AS database_name,
        mf.type_desc,
        mf.physical_name,
        UPPER(LEFT(mf.physical_name, 1)) AS drive_letter
    FROM sys.master_files AS mf
    INNER JOIN #DbFilter AS df ON mf.database_id = df.database_id
    WHERE mf.type_desc IN (N'ROWS', N'LOG')
)
SELECT
    d.database_name AS [Database_Name],
    d.drive_letter AS [Shared_Drive],
    d.physical_name AS [Data_File],
    l.physical_name AS [Log_File],
    N'Data and log share drive - consider splitting for production workloads' AS [Recommendation]
FROM FileVolumes AS d
INNER JOIN FileVolumes AS l
    ON d.database_name = l.database_name
   AND d.drive_letter = l.drive_letter
   AND d.type_desc = N'ROWS'
   AND l.type_desc = N'LOG'
ORDER BY d.database_name;

PRINT N'=== (5) PENDING I/O (sys.dm_io_pending_io_requests) ===';

SELECT
    COUNT(*) AS [Pending_IO_Count],
    SUM(io_pending_ms_ticks) AS [Total_Pending_ms],
    MAX(io_pending_ms_ticks) AS [Max_Pending_ms],
    CASE
        WHEN COUNT(*) > 10 THEN N'IO backlog - storage cannot keep pace'
        WHEN COUNT(*) > 0 THEN N'Minor pending IO at snapshot'
        ELSE N'No pending IO'
    END AS [Interpretation]
FROM sys.dm_io_pending_io_requests;

SELECT TOP (20)
    pio.io_pending_ms_ticks AS [Pending_ms],
    pio.io_type,
    pio.scheduler_address,
    CASE
        WHEN pio.io_pending_ms_ticks > 100 THEN N'Long pending IO - investigate storage'
        ELSE N''
    END AS [Note]
FROM sys.dm_io_pending_io_requests AS pio
ORDER BY pio.io_pending_ms_ticks DESC;

PRINT N'=== (6) ACTIVE I/O WAITS ===';

SELECT
    w.session_id,
    s.login_name,
    DB_NAME(r.database_id) AS [Database_Name],
    r.command,
    w.wait_type,
    w.wait_duration_ms,
    w.resource_description,
    LEFT(st.text, 200) AS [Query_Text]
FROM sys.dm_os_waiting_tasks AS w
LEFT JOIN sys.dm_exec_sessions AS s ON w.session_id = s.session_id
LEFT JOIN sys.dm_exec_requests AS r ON w.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE w.wait_type LIKE N'PAGEIOLATCH%'
   OR w.wait_type = N'WRITELOG'
   OR w.wait_type = N'IO_COMPLETION'
   OR w.wait_type LIKE N'ASYNC_IO%'
ORDER BY w.wait_duration_ms DESC;

PRINT N'=== (7) PHYSICAL DISK COUNTERS (if exposed on host) ===';

SELECT
    RTRIM(object_name) AS [Counter_Object],
    RTRIM(instance_name) AS [Disk_Instance],
    RTRIM(counter_name) AS [Counter],
    cntr_value AS [Value],
    CASE counter_name
        WHEN N'Avg. Disk sec/Read' THEN
            CASE WHEN cntr_value > @CritLatencyMs / 1000.0 THEN N'Slow disk reads at OS level'
                 WHEN cntr_value > @WarnLatencyMs / 1000.0 THEN N'Elevated read latency'
                 ELSE N'OK' END
        WHEN N'Avg. Disk sec/Write' THEN
            CASE WHEN cntr_value > @CritLatencyMs / 1000.0 THEN N'Slow disk writes at OS level'
                 WHEN cntr_value > @WarnLatencyMs / 1000.0 THEN N'Elevated write latency'
                 ELSE N'OK' END
        ELSE NULL
    END AS [Interpretation]
FROM sys.dm_os_performance_counters
WHERE object_name LIKE N'%PhysicalDisk%'
  AND counter_name IN (
        N'Avg. Disk sec/Read',
        N'Avg. Disk sec/Write',
        N'Avg. Disk Queue Length',
        N'Disk Reads/sec',
        N'Disk Writes/sec'
    )
  AND instance_name NOT IN (N'_Total', N'HarddiskVolume1')
ORDER BY [Disk_Instance], [Counter];

PRINT N'=== (8) RELOCATION FINDINGS SUMMARY ===';

SELECT
    finding AS [Finding],
    detail AS [Detail],
    action_item AS [Action]
FROM (
    SELECT
        1 AS ord,
        N'Critical per-file latency' AS finding,
        DB_NAME(vfs.database_id) + N' / ' + mf.name + N' avg IO '
        + CAST(CAST(vfs.io_stall / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) AS DECIMAL(10, 1)) AS NVARCHAR(20))
        + N' ms on ' + mf.physical_name AS detail,
        N'Validate new volume tier, host limits, AV exclusions, and path' AS action_item
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
    INNER JOIN sys.master_files AS mf
        ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
    INNER JOIN #DbFilter AS df ON vfs.database_id = df.database_id
    WHERE vfs.io_stall / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0) > @CritLatencyMs
      AND vfs.num_of_reads + vfs.num_of_writes >= 100

    UNION ALL

    SELECT
        2,
        N'Slow log writes after LDF move',
        DB_NAME(vfs.database_id) + N' log write avg '
        + CAST(CAST(vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) AS DECIMAL(10, 1)) AS NVARCHAR(20))
        + N' ms' AS detail,
        N'Move LDF to low-latency dedicated volume; check VLF and log reuse' AS action_item
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
    INNER JOIN sys.master_files AS mf
        ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
    INNER JOIN #DbFilter AS df ON vfs.database_id = df.database_id
    WHERE mf.type_desc = N'LOG'
      AND vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) > @WarnLatencyMs
      AND vfs.num_of_writes >= 100

    UNION ALL

    SELECT
        3,
        N'Pending I/O backlog',
        N'Pending count=' + CAST(COUNT(*) AS NVARCHAR(20)) AS detail,
        N'Storage saturation - engage infra team; compare to pre-move baseline' AS action_item
    FROM sys.dm_io_pending_io_requests
    HAVING COUNT(*) > 10
) AS summary
ORDER BY ord;

PRINT N'=== NOTES ===';
SELECT
    N'dm_io_virtual_file_stats is cumulative since file creation or last SQL restart.' AS [Note_1],
    N'Re-run under production workload after relocation; low I/O counts make averages noisy.' AS [Note_2],
    N'Correlate with 01_Server_OS/memory_bottleneck_deep_dive.sql if PAGEIOLATCH with low latency.' AS [Note_3],
    N'Enable Instant File Initialization for data files: 02_Instance_Config/os_integration_checks.sql' AS [Note_4];

DROP TABLE #DbFilter;
