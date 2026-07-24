/*
================================================================================
01_Recommended_Instance_Settings_2022.sql
Purpose : Align SQL Server 2022 instance settings after migrating from 2016.
IMPORTANT: Review each value for YOUR hardware before applying.
           Script prints recommendations; APPLY section is commented.
================================================================================
*/
SET NOCOUNT ON;

DECLARE
    @cpu int = (SELECT cpu_count FROM sys.dm_os_sys_info),
    @mem_mb bigint = (SELECT physical_memory_kb/1024 FROM sys.dm_os_sys_info),
    @recommended_maxdop int,
    @recommended_ctfp int = 50,          -- common starting point (was often 5 on old installs)
    @os_reserve_mb int,
    @recommended_max_mem_mb bigint;

-- MAXDOP: align with single NUMA node physical core count (common OLTP start: 4-8).
-- Restored DBs often land on new hardware / different core & NUMA topology than 2016.
SET @recommended_maxdop = CASE
    WHEN @cpu <= 8 THEN @cpu
    WHEN @cpu <= 16 THEN 4
    ELSE 8
END;

PRINT 'NOTE: Default Cost Threshold for Parallelism = 5 is too low on modern CPUs.';
PRINT 'Under CL 160 batch mode, low CTFP causes unnecessary parallel overhead.';
PRINT 'Recommended CTFP starting point: 30-50 (this script uses 50).';
PRINT 'Confirm MAXDOP against soft-NUMA / physical cores per NUMA node (not just cpu_count).';

-- Leave headroom for OS + other services (rough starting point)
SET @os_reserve_mb = CASE
    WHEN @mem_mb < 16384 THEN 2048
    WHEN @mem_mb < 65536 THEN 4096
    WHEN @mem_mb < 131072 THEN 8192
    ELSE 16384
END;
SET @recommended_max_mem_mb = @mem_mb - @os_reserve_mb;

SELECT
    @cpu AS logical_cpus,
    @mem_mb AS physical_memory_mb,
    @recommended_maxdop AS recommended_maxdop,
    @recommended_ctfp AS recommended_cost_threshold,
    @recommended_max_mem_mb AS recommended_max_server_memory_mb,
    @os_reserve_mb AS os_reserve_mb;

PRINT '--- Current values ---';
SELECT name, value_in_use
FROM sys.configurations
WHERE name IN (
    N'max degree of parallelism',
    N'cost threshold for parallelism',
    N'max server memory (MB)',
    N'min server memory (MB)',
    N'optimize for ad hoc workloads'
);

/*
========== APPLY (uncomment after validation) ==========
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'max degree of parallelism', @recommended_maxdop;           -- or hardcode
EXEC sp_configure 'cost threshold for parallelism', 50;
EXEC sp_configure 'max server memory (MB)', @recommended_max_mem_mb;
EXEC sp_configure 'optimize for ad hoc workloads', 1;  -- good for ad-hoc heavy apps
RECONFIGURE;
*/

/*
CHECKLIST OUTSIDE T-SQL
[ ] Instant File Initialization enabled for SQL service account
[ ] Lock Pages in Memory only if vetted (and max server memory set correctly)
[ ] Power plan = High Performance
[ ] Antivirus exclusions for data/log/tempdb/backup dirs
[ ] Windows / storage: 64KB allocation unit on data volumes (best practice)
[ ] Backup compression default ON (optional)
*/
