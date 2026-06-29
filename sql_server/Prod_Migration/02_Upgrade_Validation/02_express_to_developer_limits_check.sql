/*
================================================================================
Express → Standard/Developer Edition Limits Check
================================================================================
Purpose:
    After migrating OFF SQL Server Express, several limits and configuration
    artifacts remain and cause "mysterious" slowness:

    Express limits (2019):
    - ~1.4 GB buffer pool cap (engine enforced)
    - 1 CPU socket / 4 cores max
    - 10 GB per database size limit (removed when not Express)
    - Often deployed with tiny max server memory and MAXDOP=1

    After upgrade to Developer/Standard, the ENGINE limits are gone but
    sp_configure values and Windows VM sizing may still reflect Express era.

Checks:
    (1) Current edition vs Express
    (2) max server memory vs physical RAM
    (3) MAXDOP, CTFP, affinity mask
    (4) CPU count visible to SQL vs VM cores
    (5) Buffer pool size vs target memory
    (6) Database file sizes (historical Express 10GB concern)

Interpretation:
    - max server memory = 2048 on 32 GB VM → massive unnecessary IO/waits
    - MAXDOP = 1 on 16-core box → not always wrong, but verify CTFP and waits
    - committed_kb << physical RAM after Developer upgrade → increase max server memory

Next action if memory capped:
    See 07_Instance_Config/02_recommended_fixes_with_rollback.sql section 1.

Criticality: High for Express → non-Express migrations
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @Edition NVARCHAR(256) = CAST(SERVERPROPERTY(N'Edition') AS NVARCHAR(256));
DECLARE @EngineEdition INT = CAST(SERVERPROPERTY(N'EngineEdition') AS INT);
-- EngineEdition: 4 = Express

PRINT '=== EDITION CHECK ===';
SELECT
    @Edition AS [Edition],
    @EngineEdition AS [Engine_Edition_ID],
    CASE @EngineEdition
        WHEN 4 THEN N'STILL EXPRESS — migration may not be complete'
        ELSE N'Not Express — engine-level RAM/CPU caps removed'
    END AS [Express_Status];

PRINT '=== MEMORY: CONFIG vs OS vs BUFFER POOL ===';
SELECT
    max_mem.value_in_use AS [Max_Server_Memory_MB],
    min_mem.value_in_use AS [Min_Server_Memory_MB],
    os.physical_memory_kb / 1024 AS [Physical_RAM_MB],
    os.committed_kb / 1024 AS [SQL_Committed_Memory_MB],
    os.committed_target_kb / 1024 AS [SQL_Target_Memory_MB],
    buf.Buffer_Pool_MB,
    CAST(
        CASE
            WHEN max_mem.value_in_use < os.physical_memory_kb / 1024 * 0.4
                THEN N'LIKELY POST-EXPRESS CAP: Increase max server memory after validating OS headroom'
            WHEN os.committed_kb / 1024 < os.physical_memory_kb / 1024 * 0.3
                THEN N'SQL memory under-utilized — memory setting, recent startup, or workload not warmed'
            ELSE N'Review — compare to workload working set'
        END AS NVARCHAR(500)
    ) AS [Recommendation]
FROM sys.dm_os_sys_info AS os
CROSS JOIN (
    SELECT value_in_use
    FROM sys.configurations
    WHERE name = N'max server memory (MB)'
) AS max_mem
CROSS JOIN (
    SELECT value_in_use
    FROM sys.configurations
    WHERE name = N'min server memory (MB)'
) AS min_mem
CROSS JOIN (
    SELECT SUM(pages_kb) / 1024 AS Buffer_Pool_MB
    FROM sys.dm_os_memory_clerks
    WHERE type = N'MEMORYCLERK_SQLBUFFERPOOL'
) AS buf;

PRINT '=== PARALLELISM SETTINGS ===';
SELECT
    name,
    value_in_use AS [Current_Value],
    CASE name
        WHEN N'max degree of parallelism' THEN
            CASE
                WHEN value_in_use = 0 THEN N'0 = unlimited — often bad on OLTP; 4-8 typical'
                WHEN value_in_use = 1 THEN N'MAXDOP 1 — fine for troubleshooting, not always for prod'
                ELSE N'Validate against NUMA layout'
            END
        WHEN N'cost threshold for parallelism' THEN
            CASE WHEN value_in_use <= 5 THEN N'Default 5 — often too low after upgrade; try 50' ELSE N'OK' END
        ELSE N'Review'
    END AS [Post_Migration_Note]
FROM sys.configurations
WHERE name IN (N'max degree of parallelism', N'cost threshold for parallelism', N'affinity mask', N'affinity64 mask');

PRINT '=== CPU VISIBLE TO SQL SERVER ===';
SELECT
    cpu_count AS [Logical_CPUs],
    hyperthread_ratio,
    cpu_count / hyperthread_ratio AS [Physical_Cores_Approx],
    scheduler_count AS [Schedulers],
    CAST(
        N'Express allowed 1 socket/4 cores. If VM has more but performance odd, ' +
        N'check VM vCPU alignment and MAXDOP.'
    AS NVARCHAR(500)) AS [Note]
FROM sys.dm_os_sys_info;

PRINT '=== DATABASE FILE SIZES (historical Express 10 GB limit) ===';
SELECT
    DB_NAME(database_id) AS [Database_Name],
    type_desc AS [File_Type],
    name AS [Logical_Name],
    size * 8 / 1024 AS [Size_MB],
    CASE WHEN size * 8 / 1024 > 10240 AND @EngineEdition <> 4 THEN N'Would have exceeded Express 10GB — OK on Developer'
         ELSE N'OK'
    END AS [Express_Limit_Note]
FROM sys.master_files
WHERE database_id > 4
ORDER BY size DESC;

PRINT 'Next: 07_Instance_Config/01_post_migration_config_audit.sql';
