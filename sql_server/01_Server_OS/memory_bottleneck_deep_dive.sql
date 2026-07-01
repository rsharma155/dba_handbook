/*
================================================================================
Memory Bottleneck Deep Dive
================================================================================
Purpose:
    In-depth instance memory analysis for pressure, starvation, and imbalance
    using process memory, buffer pool, clerks, performance counters, and grants.

DMVs / views used:
    sys.dm_os_process_memory
    sys.dm_os_sys_memory (OS physical memory, when available)
    sys.dm_os_buffer_descriptors
    sys.dm_os_memory_clerks
    sys.dm_os_performance_counters
    sys.dm_exec_query_memory_grants
    sys.dm_os_memory_nodes
    sys.dm_os_wait_stats (RESOURCE_SEMAPHORE)

Output:
    (1)  SQL process memory vs OS and max server memory
    (2)  Instance memory configuration (optimize for ad hoc workloads)
    (3)  Stolen vs total server memory (outside buffer pool)
    (4)  Memory Manager / Buffer Manager performance counters
    (5)  Buffer pool by database (cached MB, dirty %)
    (6)  Top object/page consumers in buffer pool
    (7)  Memory clerks (top consumers + plan cache / workspace breakdown)
    (8)  Active and queued memory grants with query text
    (9)  NUMA node memory distribution
    (10) RESOURCE_SEMAPHORE wait accumulation
    (11) Bottleneck summary with recommended next steps

Thresholds (guidance):
    PLE < (Total Memory GB / 4) * 150  -> buffer pool churn / memory pressure
    Memory Grants Pending > 0          -> RESOURCE_SEMAPHORE risk
    Lazy writes/sec sustained high       -> checkpoint / memory pressure
    Buffer cache hit ratio < 95%         -> investigate (OLTP warm workload)

Action:
    Pressure + high PAGEIOLATCH -> add RAM or reduce max server memory headroom issue
    Pending grants -> tune hash/sort queries, update stats, reduce DOP, add RAM
    High CACHESTORE_SQLCP -> optimize for ad hoc workloads, fix parameterization
    High USERSTORE_WSMB (workspace) -> review sorts/hashes in top grant queries

Criticality: High
Prerequisites: VIEW SERVER STATE; column set varies by version (Azure SQL / 2022+ omit some
              dm_os_process_memory and dm_os_memory_clerks columns — script uses dynamic SQL)
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @TotalMemGB DECIMAL(18, 2);
DECLARE @PLEThreshold INT;

SELECT @TotalMemGB = cntr_value / 1024.0 / 1024.0
FROM sys.dm_os_performance_counters
WHERE counter_name = N'Total Server Memory (KB)'
  AND object_name LIKE N'%Memory Manager%';

SET @PLEThreshold = CASE
    WHEN @TotalMemGB > 0 THEN CAST((@TotalMemGB / 4.0) * 150 AS INT)
    ELSE 300
END;

PRINT N'=== (1) SQL PROCESS MEMORY (sys.dm_os_process_memory) ===';

DECLARE @ProcessMemSql NVARCHAR(MAX);

SET @ProcessMemSql = N'
SELECT
    physical_memory_in_use_kb / 1024 AS [SQL_Physical_In_Use_MB],
    locked_page_allocations_kb / 1024 AS [Locked_Pages_MB],
    large_page_allocations_kb / 1024 AS [Large_Pages_MB],
    total_virtual_address_space_kb / 1024 AS [Virtual_Address_Space_MB],
    virtual_address_space_committed_kb / 1024 AS [Virtual_Committed_MB],
    available_commit_limit_kb / 1024 AS [Available_Commit_Limit_MB],
    process_physical_memory_low AS [Process_Phys_Memory_Low],
    process_virtual_memory_low AS [Process_Virtual_Memory_Low]';

IF COL_LENGTH(N'sys.dm_os_process_memory', N'system_physical_memory_high') IS NOT NULL
    SET @ProcessMemSql = @ProcessMemSql + N',
    system_physical_memory_high AS [System_Phys_Memory_High],
    system_physical_memory_low AS [System_Phys_Memory_Low]';

IF COL_LENGTH(N'sys.dm_os_process_memory', N'system_memory_state_desc') IS NOT NULL
    SET @ProcessMemSql = @ProcessMemSql + N',
    system_memory_state_desc AS [System_Memory_State]';

IF COL_LENGTH(N'sys.dm_os_process_memory', N'memory_utilization_percentage') IS NOT NULL
    SET @ProcessMemSql = @ProcessMemSql + N',
    memory_utilization_percentage AS [Memory_Utilization_Pct]';

SET @ProcessMemSql = @ProcessMemSql + N',
    (SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = N''max server memory (MB)'') AS [Max_Server_Memory_MB],
    (SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = N''min server memory (MB)'') AS [Min_Server_Memory_MB],
    CASE
        WHEN process_physical_memory_low = 1 OR process_virtual_memory_low = 1
            THEN N''WARNING: SQL Server signalled low memory''';

IF COL_LENGTH(N'sys.dm_os_process_memory', N'system_physical_memory_low') IS NOT NULL
    SET @ProcessMemSql = @ProcessMemSql + N'
        WHEN system_physical_memory_low = 1
            THEN N''WARNING: OS reports low physical memory''';

SET @ProcessMemSql = @ProcessMemSql + N'
        ELSE N''OK''
    END AS [Memory_Pressure_Flag]
FROM sys.dm_os_process_memory;';

EXEC sys.sp_executesql @ProcessMemSql;

PRINT N'=== (2) INSTANCE MEMORY CONFIGURATION ===';

SELECT
    c.name AS [Configuration_Name],
    c.value AS [Configured_Value],
    c.value_in_use AS [Value_In_Use],
    c.is_dynamic,
    c.is_advanced,
    CASE c.name
        WHEN N'optimize for ad hoc workloads' THEN
            CASE
                WHEN c.value_in_use = 0 THEN
                    N'OFF - plan cache may bloat on single-use ad hoc SQL; enable if CACHESTORE_SQLCP is large'
                ELSE N'ON - only plan stubs cached for single-use ad hoc batches'
            END
        WHEN N'max server memory (MB)' THEN N'Cap for buffer pool + stolen memory combined'
        WHEN N'min server memory (MB)' THEN N'Floor SQL Server will not release below'
        ELSE NULL
    END AS [Interpretation]
FROM sys.configurations AS c
WHERE c.name IN (
    N'optimize for ad hoc workloads',
    N'max server memory (MB)',
    N'min server memory (MB)'
)
ORDER BY c.name;

PRINT N'=== (3) STOLEN VS TOTAL SERVER MEMORY ===';
PRINT N'Stolen memory = SQL Server memory outside the buffer pool (plan cache, connections, locks, workspace, etc.).';
PRINT N'Source: Memory Manager counters (Stolen Server Memory KB / Total Server Memory KB).';

SELECT
    stolen.cntr_value / 1024 AS [Stolen_MB],
    total.cntr_value / 1024 AS [Total_MB],
    CAST(100.0 * stolen.cntr_value / NULLIF(total.cntr_value, 0) AS DECIMAL(10, 1)) AS [Stolen_Pct],
    CASE
        WHEN stolen.cntr_value / NULLIF(total.cntr_value, 0) > 0.50
            THEN N'HIGH - majority of SQL memory is outside buffer pool; review plan cache clerks (section 7)'
        WHEN stolen.cntr_value / NULLIF(total.cntr_value, 0) > 0.35
            THEN N'ELEVATED - check CACHESTORE_* clerks and ad hoc workload settings'
        ELSE N'OK - stolen memory within typical range'
    END AS [Interpretation],
    CASE
        WHEN (SELECT value_in_use FROM sys.configurations WHERE name = N'optimize for ad hoc workloads') = 0
             AND stolen.cntr_value / NULLIF(total.cntr_value, 0) > 0.35
            THEN N'Consider: EXEC sp_configure ''optimize for ad hoc workloads'', 1; RECONFIGURE;'
        ELSE NULL
    END AS [Suggested_Action]
FROM sys.dm_os_performance_counters AS stolen
CROSS JOIN sys.dm_os_performance_counters AS total
WHERE stolen.object_name LIKE N'%Memory Manager%'
  AND stolen.counter_name = N'Stolen Server Memory (KB)'
  AND stolen.instance_name = N''
  AND total.object_name LIKE N'%Memory Manager%'
  AND total.counter_name = N'Total Server Memory (KB)'
  AND total.instance_name = N'';

IF OBJECT_ID(N'sys.dm_os_sys_memory') IS NOT NULL
BEGIN
    PRINT N'=== (3b) OS PHYSICAL MEMORY (sys.dm_os_sys_memory) ===';

    SELECT
        total_physical_memory_kb / 1024 AS [OS_Total_Physical_MB],
        available_physical_memory_kb / 1024 AS [OS_Available_Physical_MB],
        total_page_file_kb / 1024 AS [OS_Total_Page_File_MB],
        available_page_file_kb / 1024 AS [OS_Available_Page_File_MB]
    FROM sys.dm_os_sys_memory;
END;

PRINT N'=== (4) MEMORY & BUFFER PERFORMANCE COUNTERS ===';

SELECT
    RTRIM(object_name) AS [Counter_Object],
    RTRIM(instance_name) AS [Instance],
    RTRIM(counter_name) AS [Counter],
    cntr_value AS [Value],
    CASE counter_name
        WHEN N'Page life expectancy' THEN
            CASE WHEN cntr_value < @PLEThreshold THEN N'LOW PLE - buffer churn' ELSE N'OK' END
        WHEN N'Memory Grants Pending' THEN
            CASE WHEN cntr_value > 0 THEN N'GRANTS PENDING - RESOURCE_SEMAPHORE' ELSE N'OK' END
        WHEN N'Lazy writes/sec' THEN
            CASE WHEN cntr_value > 20 THEN N'Elevated lazy writes' ELSE N'OK' END
        WHEN N'Stolen Server Memory (KB)' THEN N'Non-buffer-pool SQL memory - see section 3'
        ELSE NULL
    END AS [Interpretation]
FROM sys.dm_os_performance_counters
WHERE (
        object_name LIKE N'%Memory Manager%'
        AND counter_name IN (
            N'Target Server Memory (KB)',
            N'Total Server Memory (KB)',
            N'Memory Grants Outstanding',
            N'Memory Grants Pending',
            N'Connection Memory (KB)',
            N'Granted Workspace Memory (KB)',
            N'Maximum Workspace Memory (KB)',
            N'Optimizer Memory (KB)',
            N'Stolen Server Memory (KB)'
        )
    )
    OR (
        object_name LIKE N'%Buffer Manager%'
        AND counter_name IN (
            N'Page life expectancy',
            N'Buffer cache hit ratio',
            N'Buffer cache hit ratio base',
            N'Page reads/sec',
            N'Lazy writes/sec',
            N'Readahead pages/sec',
            N'Database pages',
            N'Target pages'
        )
    )
ORDER BY [Counter_Object], [Counter];

PRINT N'=== (5) BUFFER POOL BY DATABASE (sys.dm_os_buffer_descriptors) ===';

SELECT
    CASE
        WHEN bd.database_id = 32767 THEN N'Resource / Free Pages'
        ELSE DB_NAME(bd.database_id)
    END AS [Database_Name],
    COUNT(*) AS [Page_Count],
    COUNT(*) * 8 / 1024 AS [Cached_MB],
    SUM(CASE WHEN bd.is_modified = 1 THEN 1 ELSE 0 END) AS [Dirty_Pages],
    CAST(
        100.0 * SUM(CASE WHEN bd.is_modified = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)
        AS DECIMAL(5, 1)
    ) AS [Dirty_Pct],
    COUNT(DISTINCT bd.allocation_unit_id) AS [Allocation_Units]
FROM sys.dm_os_buffer_descriptors AS bd
GROUP BY bd.database_id
ORDER BY [Cached_MB] DESC;

PRINT N'=== (6) TOP BUFFER POOL OBJECTS (current database context) ===';
PRINT N'Connect to the target user database for object-level detail, or use section 5 for instance-wide DB totals.';

IF DB_ID() > 4
BEGIN
    SELECT TOP (25)
        DB_NAME() AS [Database_Name],
        OBJECT_SCHEMA_NAME(p.object_id) AS [Schema_Name],
        OBJECT_NAME(p.object_id) AS [Object_Name],
        i.name AS [Index_Name],
        i.type_desc AS [Index_Type],
        COUNT(*) * 8 / 1024 AS [Cached_MB],
        SUM(CASE WHEN bd.is_modified = 1 THEN 1 ELSE 0 END) AS [Dirty_Pages]
    FROM sys.dm_os_buffer_descriptors AS bd
    INNER JOIN sys.allocation_units AS au
        ON bd.allocation_unit_id = au.allocation_unit_id
    INNER JOIN sys.partitions AS p
        ON au.container_id = p.hobt_id
    LEFT JOIN sys.indexes AS i
        ON p.object_id = i.object_id
       AND p.index_id = i.index_id
    WHERE bd.database_id = DB_ID()
    GROUP BY
        p.object_id,
        i.name,
        i.type_desc
    ORDER BY [Cached_MB] DESC;
END
ELSE
    PRINT N'Skipped: connect to a user database for per-object buffer pool breakdown.';

PRINT N'=== (7) MEMORY CLERKS (sys.dm_os_memory_clerks) ===';

DECLARE @ClerkSql NVARCHAR(MAX);

SET @ClerkSql = N'
SELECT TOP (20)
    mc.type AS [Clerk_Type],
    SUM(mc.pages_kb) / 1024 AS [Allocated_MB],
    SUM(mc.virtual_memory_reserved_kb) / 1024 AS [Virtual_Reserved_MB],
    SUM(mc.virtual_memory_committed_kb) / 1024 AS [Virtual_Committed_MB]';

IF COL_LENGTH(N'sys.dm_os_memory_clerks', N'single_pages_kb') IS NOT NULL
    SET @ClerkSql = @ClerkSql + N',
    SUM(mc.single_pages_kb) / 1024 AS [Single_Pages_MB],
    SUM(mc.multi_pages_kb) / 1024 AS [Multi_Pages_MB]';

IF COL_LENGTH(N'sys.dm_os_memory_clerks', N'awe_allocated_kb') IS NOT NULL
    SET @ClerkSql = @ClerkSql + N',
    SUM(mc.awe_allocated_kb) / 1024 AS [AWE_MB]';

SET @ClerkSql = @ClerkSql + N',
    CASE
        WHEN mc.type LIKE N''MEMORYCLERK_SQLBUFFERPOOL%'' THEN N''Buffer pool - expected largest''
        WHEN mc.type LIKE N''CACHESTORE_SQLCP%'' OR mc.type LIKE N''CACHESTORE_OBJCP%''
            THEN N''Plan cache pressure - review ad hoc / parameterization''
        WHEN mc.type LIKE N''USERSTORE%'' THEN N''User store - often workspace / connection memory''
        WHEN mc.type LIKE N''MEMORYCLERK_SOSOS%'' THEN N''SQLOS internal''
        ELSE N''Review if unexpectedly large''
    END AS [Interpretation]
FROM sys.dm_os_memory_clerks AS mc
WHERE mc.pages_kb > 0
GROUP BY mc.type
ORDER BY [Allocated_MB] DESC;';

EXEC sys.sp_executesql @ClerkSql;

PRINT N'=== (7b) PLAN CACHE & WORKSPACE CLERK SUMMARY ===';

SELECT
    SUM(CASE WHEN type LIKE N'CACHESTORE_%' THEN pages_kb ELSE 0 END) / 1024 AS [Plan_Cache_Total_MB],
    SUM(CASE WHEN type LIKE N'USERSTORE_WSMB%' THEN pages_kb ELSE 0 END) / 1024 AS [Workspace_Grants_MB],
    SUM(CASE WHEN type LIKE N'MEMORYCLERK_SQLBUFFERPOOL%' THEN pages_kb ELSE 0 END) / 1024 AS [Buffer_Pool_MB],
    SUM(CASE WHEN type LIKE N'MEMORYCLERK_SQLGENERAL%' THEN pages_kb ELSE 0 END) / 1024 AS [SQL_General_MB]
FROM sys.dm_os_memory_clerks;

PRINT N'=== (8) MEMORY GRANTS (sys.dm_exec_query_memory_grants) ===';

SELECT
    mg.session_id,
    mg.request_id,
    mg.grant_time,
    mg.requested_memory_kb / 1024 AS [Requested_MB],
    mg.granted_memory_kb / 1024 AS [Granted_MB],
    mg.required_memory_kb / 1024 AS [Required_MB],
    mg.used_memory_kb / 1024 AS [Used_MB],
    mg.max_used_memory_kb / 1024 AS [Max_Used_MB],
    mg.query_cost,
    mg.dop,
    mg.wait_order,
    mg.wait_time_ms,
    mg.is_next_candidate,
    mg.timeout_sec,
    s.login_name,
    s.host_name,
    s.program_name,
    r.status AS [Request_Status],
    r.command,
    r.wait_type AS [Current_Wait],
  LEFT(st.text, 300) AS [Query_Text]
FROM sys.dm_exec_query_memory_grants AS mg
LEFT JOIN sys.dm_exec_sessions AS s ON mg.session_id = s.session_id
LEFT JOIN sys.dm_exec_requests AS r ON mg.session_id = r.session_id AND mg.request_id = r.request_id
OUTER APPLY sys.dm_exec_sql_text(mg.sql_handle) AS st
ORDER BY
    CASE WHEN mg.grant_time IS NULL THEN 0 ELSE 1 END,
    mg.requested_memory_kb DESC;

PRINT N'=== (9) NUMA MEMORY NODES ===';

SELECT
    mn.memory_node_id,
    mn.virtual_address_space_reserved_kb / 1024 AS [VA_Reserved_MB],
    mn.virtual_address_space_committed_kb / 1024 AS [VA_Committed_MB],
    mn.locked_page_allocations_kb / 1024 AS [Locked_Pages_MB],
    mn.pages_kb / 1024 AS [Pages_MB],
    mn.foreign_committed_kb / 1024 AS [Foreign_Committed_MB]
FROM sys.dm_os_memory_nodes AS mn
WHERE mn.memory_node_id <> 64
ORDER BY mn.memory_node_id;

PRINT N'=== (10) RESOURCE_SEMAPHORE WAIT ACCUMULATION ===';

SELECT
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms / NULLIF(waiting_tasks_count, 0) AS [Avg_Wait_ms]
FROM sys.dm_os_wait_stats
WHERE wait_type IN (N'RESOURCE_SEMAPHORE', N'RESOURCE_SEMAPHORE_QUERY_COMPILE')
ORDER BY wait_time_ms DESC;

PRINT N'=== (11) BOTTLENECK SUMMARY ===';

SELECT
    signal AS [Signal],
    detail AS [Detail],
    recommendation AS [Recommendation]
FROM (
    SELECT
        1 AS ord,
        N'PLE below threshold' AS signal,
        N'PLE=' + CAST(cntr_value AS NVARCHAR(20)) + N', threshold=' + CAST(@PLEThreshold AS NVARCHAR(20)) AS detail,
        N'Add RAM, reduce memory consumers, or verify max server memory leaves 4-10 GB for OS' AS recommendation
    FROM sys.dm_os_performance_counters
    WHERE object_name LIKE N'%Buffer Manager%'
      AND counter_name = N'Page life expectancy'
      AND instance_name = N''
      AND cntr_value < @PLEThreshold

    UNION ALL

    SELECT
        2,
        N'Memory grants pending',
        N'Pending grants=' + CAST(cntr_value AS NVARCHAR(20)),
        N'Tune queries with large sorts/hashes; review section 8; consider MAXDOP and RAM'
    FROM sys.dm_os_performance_counters
    WHERE object_name LIKE N'%Memory Manager%'
      AND counter_name = N'Memory Grants Pending'
      AND cntr_value > 0

    UNION ALL

    SELECT
        3,
        N'SQL process low memory flag',
        N'process_physical_memory_low or process_virtual_memory_low is set',
        N'Immediate memory pressure - check OS RAM, other processes, max server memory'
    FROM sys.dm_os_process_memory
    WHERE process_physical_memory_low = 1 OR process_virtual_memory_low = 1

    UNION ALL

    SELECT
        4,
        N'High RESOURCE_SEMAPHORE waits',
        N'Accumulated wait_ms=' + CAST(wait_time_ms AS NVARCHAR(20)),
        N'Historical memory grant starvation - correlate with section 8 and top_resource_queries.sql'
    FROM sys.dm_os_wait_stats
    WHERE wait_type = N'RESOURCE_SEMAPHORE'
      AND wait_time_ms > 60000

    UNION ALL

    SELECT
        5,
        N'High stolen server memory',
        N'Stolen_MB=' + CAST(stolen.cntr_value / 1024 AS NVARCHAR(20))
        + N', Total_MB=' + CAST(total.cntr_value / 1024 AS NVARCHAR(20))
        + N', Pct=' + CAST(CAST(100.0 * stolen.cntr_value / NULLIF(total.cntr_value, 0) AS DECIMAL(10, 1)) AS NVARCHAR(20)),
        N'Memory consumed outside buffer pool - review section 7 clerks; enable optimize for ad hoc workloads if plan cache is large'
    FROM sys.dm_os_performance_counters AS stolen
    CROSS JOIN sys.dm_os_performance_counters AS total
    WHERE stolen.object_name LIKE N'%Memory Manager%'
      AND stolen.counter_name = N'Stolen Server Memory (KB)'
      AND stolen.instance_name = N''
      AND total.object_name LIKE N'%Memory Manager%'
      AND total.counter_name = N'Total Server Memory (KB)'
      AND total.instance_name = N''
      AND stolen.cntr_value / NULLIF(total.cntr_value, 0) > 0.35

    UNION ALL

    SELECT
        6,
        N'Optimize for ad hoc workloads is OFF',
        N'value_in_use=0 with elevated plan cache risk',
        N'EXEC sp_configure ''optimize for ad hoc workloads'', 1; RECONFIGURE;'
    FROM sys.configurations
    WHERE name = N'optimize for ad hoc workloads'
      AND value_in_use = 0
      AND EXISTS (
          SELECT 1
          FROM sys.dm_os_performance_counters AS stolen
          INNER JOIN sys.dm_os_performance_counters AS total
              ON total.object_name LIKE N'%Memory Manager%'
             AND total.counter_name = N'Total Server Memory (KB)'
             AND total.instance_name = N''
          WHERE stolen.object_name LIKE N'%Memory Manager%'
            AND stolen.counter_name = N'Stolen Server Memory (KB)'
            AND stolen.instance_name = N''
            AND stolen.cntr_value / NULLIF(total.cntr_value, 0) > 0.35
      )
) AS findings
ORDER BY ord;

IF NOT EXISTS (
    SELECT 1
    FROM sys.dm_os_performance_counters
    WHERE object_name LIKE N'%Buffer Manager%'
      AND counter_name = N'Page life expectancy'
      AND instance_name = N''
      AND cntr_value < @PLEThreshold
    UNION ALL
    SELECT 1 FROM sys.dm_os_performance_counters
    WHERE object_name LIKE N'%Memory Manager%'
      AND counter_name = N'Memory Grants Pending'
      AND cntr_value > 0
)
    PRINT N'No critical memory bottleneck signals at snapshot time. Re-run under peak workload.';
