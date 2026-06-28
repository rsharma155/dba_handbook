/*
================================================================================
SQL Server Resource Governor Audit
================================================================================
Description:
    Reviews Resource Governor (RG) configuration status, resource pools, and
    workload groups. Identifies whether RG is enabled and how resources are
    allocated across workloads.

Output:
    RG enabled/disabled status, classifier function details, resource pool
    configuration (min/max CPU and memory), and workload group settings.

Action:
    If RG is disabled but workload isolation is needed (e.g., separating
    reporting from OLTP), plan an RG implementation:
    (1) Create resource pools with MIN/MAX CPU and memory settings
    (2) Create workload groups mapped to pools
    (3) Create a classifier function to route sessions
    (4) ALTER RESOURCE GOVERNOR RECONFIGURE;
    Test thoroughly in non-production first — a misconfigured classifier
    can affect all connections.

Criticality: Low
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

-- 1. Resource Governor Global Status
PRINT '--- Resource Governor Status ---';
SELECT 
    is_enabled,
    classifier_function_id,
    OBJECT_NAME(classifier_function_id) AS [Classifier_Function_Name],
    CASE 
        WHEN is_enabled = 1 THEN '🟢 ENABLED'
        ELSE '⚪ DISABLED (Default)'
    END AS [Status]
FROM sys.resource_governor_configuration;

-- 2. Resource Pool Usage & Limits
PRINT '--- Resource Pool Configuration ---';
SELECT 
    name AS [Pool_Name],
    min_cpu_percent,
    max_cpu_percent,
    min_memory_percent,
    max_memory_percent,
    CASE 
        WHEN name = 'internal' THEN '🔵 SYSTEM POOL'
        WHEN name = 'default' THEN '⚪ DEFAULT POOL'
        ELSE '🟢 USER POOL'
    END AS [Pool_Type]
FROM sys.resource_governor_resource_pools;

-- 3. Workload Groups
PRINT '--- Workload Group Mapping ---';
SELECT 
    name AS [Group_Name],
    pool_name = (SELECT name FROM sys.resource_governor_resource_pools WHERE pool_id = wg.pool_id),
    importance,
    request_max_memory_grant_percent,
    request_max_cpu_time_sec
FROM sys.resource_governor_workload_groups wg;
