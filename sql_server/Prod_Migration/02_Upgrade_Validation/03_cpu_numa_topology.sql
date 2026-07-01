/*
================================================================================
CPU and NUMA Topology Check (Post Express → Developer)
================================================================================
Purpose:
    After migrating from SQL Server Express to Developer/Standard/Enterprise,
    SQL Server may suddenly see many more schedulers and NUMA nodes than before.
    The workload execution model changes even when data and queries are unchanged.

    Express (typical):  4 schedulers, 1 NUMA node, MAXDOP effectively constrained
    Developer (typical): 32 schedulers, 4 NUMA nodes, full parallelism available

    This shift can surface as:
    - CXPACKET / CXCONSUMER waits (parallelism skew)
    - PAGELATCH_* on tempdb (more concurrent allocators)
    - SOS_SCHEDULER_YIELD (scheduler pressure)
    - Metadata latch contention (parallel catalog scans)

Checks:
    (1) Instance-level CPU / NUMA summary (dm_os_sys_info)
    (2) NUMA node layout and worker distribution (dm_os_nodes)
    (3) Online schedulers per node with runnable tasks (dm_os_schedulers)
    (4) MAXDOP vs NUMA topology alignment

Interpretation:
    - runnable_tasks_count > 0 sustained on multiple schedulers → CPU queue pressure
    - scheduler_count >> prior Express baseline → revalidate MAXDOP, CTFP, tempdb files
    - numa_node_count > 1 with MAXDOP = 0 or very high → cross-node parallel risk

Next action:
    MAXDOP / CTFP misaligned → 07_Instance_Config/01_post_migration_config_audit.sql
    PAGELATCH on tempdb        → 08_Storage_OS/03_tempdb_autogrowth_audit.sql
  Parallelism waits            → 06_Optimizer_Plans/02_query_hint_guide.sql

Criticality: High for Express → non-Express migrations on multi-core VMs
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

PRINT '=== 1. INSTANCE CPU / NUMA SUMMARY (dm_os_sys_info) ===';
IF COL_LENGTH(N'sys.dm_os_sys_info', N'socket_count') IS NOT NULL
BEGIN
    SELECT
        cpu_count,
        scheduler_count,
        numa_node_count,
        socket_count,
        hyperthread_ratio,
        cpu_count / NULLIF(hyperthread_ratio, 0) AS [Physical_Cores_Approx],
        CAST(
            N'Express historically exposed fewer schedulers (e.g. 4) and often 1 NUMA node. ' +
            N'After Developer upgrade, scheduler_count and numa_node_count may jump sharply — ' +
            N'the execution model changed; revisit MAXDOP, CTFP, and tempdb file count.'
        AS NVARCHAR(600)) AS [Post_Migration_Note]
    FROM sys.dm_os_sys_info;
END
ELSE
BEGIN
    SELECT
        cpu_count,
        scheduler_count,
        numa_node_count,
        CAST(NULL AS INT) AS [socket_count],
        hyperthread_ratio,
        cpu_count / NULLIF(hyperthread_ratio, 0) AS [Physical_Cores_Approx],
        CAST(
            N'socket_count requires SQL Server 2016+. ' +
            N'Compare scheduler_count and numa_node_count to pre-migration baseline.'
        AS NVARCHAR(500)) AS [Post_Migration_Note]
    FROM sys.dm_os_sys_info;
END;

PRINT '=== 2. NUMA NODES (dm_os_nodes) ===';
SELECT
    node_id,
    memory_node_id,
    online_scheduler_count,
    active_worker_count,
    CASE node_id
        WHEN 64 THEN N'DAC node — ignore for capacity planning'
        ELSE N'User schedulers mapped to this node'
    END AS [Node_Role]
FROM sys.dm_os_nodes
ORDER BY node_id;

PRINT '=== 3. ONLINE SCHEDULERS (dm_os_schedulers) ===';
SELECT
    scheduler_id,
    parent_node_id,
    status,
    runnable_tasks_count,
    current_tasks_count,
    active_workers_count,
    CASE
        WHEN runnable_tasks_count > 0 THEN N'CPU queue — workload waiting for scheduler'
        WHEN current_tasks_count > active_workers_count * 2 THEN N'Review — elevated task load on scheduler'
        ELSE N'OK at snapshot'
    END AS [Scheduler_Status]
FROM sys.dm_os_schedulers
WHERE status = N'VISIBLE ONLINE'
ORDER BY parent_node_id, scheduler_id;

PRINT '=== 4. MAXDOP / CTFP vs TOPOLOGY ===';
SELECT
    (SELECT value_in_use FROM sys.configurations WHERE name = N'max degree of parallelism') AS [MAXDOP],
    (SELECT value_in_use FROM sys.configurations WHERE name = N'cost threshold for parallelism') AS [CTFP],
    os.cpu_count AS [Logical_CPUs],
    os.numa_node_count AS [NUMA_Nodes],
    os.scheduler_count AS [Schedulers],
    CAST(
        CASE
            WHEN os.numa_node_count > 1
                 AND (SELECT value_in_use FROM sys.configurations WHERE name = N'max degree of parallelism') = 0
                THEN N'WARNING: MAXDOP 0 (unlimited) on multi-NUMA — common post-Express surprise'
            WHEN os.scheduler_count > 8
                 AND (SELECT value_in_use FROM sys.configurations WHERE name = N'max degree of parallelism') = 1
                THEN N'INFO: MAXDOP 1 on many schedulers — OK for triage; validate for production OLTP'
            WHEN (SELECT value_in_use FROM sys.configurations WHERE name = N'cost threshold for parallelism') <= 5
                THEN N'WARNING: CTFP default 5 — trivial queries may parallelize after core count increase'
            ELSE N'Review MAXDOP against cores per NUMA node (often MIN(8, cores_per_node))'
        END AS NVARCHAR(500)
    ) AS [Recommendation]
FROM sys.dm_os_sys_info AS os;

PRINT '=== 5. EXPRESS → DEVELOPER TOPOLOGY CHANGE (reference) ===';
SELECT
    N'Before (Express)' AS [Phase],
    N'~4 schedulers, 1 NUMA node, engine CPU/RAM caps' AS [Typical_Topology],
    N'Plans and waits tuned to low parallelism' AS [Workload_Impact]
UNION ALL
SELECT
    N'After (Developer)',
    CAST(scheduler_count AS NVARCHAR(10)) + N' schedulers, '
        + CAST(numa_node_count AS NVARCHAR(10)) + N' NUMA node(s), caps removed',
    N'Same queries may parallelize differently — wait profile can change completely'
FROM sys.dm_os_sys_info;

PRINT 'Next: 07_Instance_Config/01_post_migration_config_audit.sql';
