/*
================================================================================
Purpose:        Audits 20+ critical instance-level configurations (Max Memory, 
                MAXDOP, Cost Threshold, etc.) with detailed rationale.
Provides:       Current value, expert rationale, and status for each setting.
Importance:     Misconfigured instance settings are a leading cause of systemic 
                performance issues.
 Interpretation: Follow "Expert_Rationale" and "Status" columns 
                (Critical/Warning/Optimal).
Action:         For each setting marked "Critical" or "Warning", apply the recommended value using sp_configure. For MAXDOP and CTFP changes, test on non-production first. For max server memory, ensure at least 4-8 GB is reserved for the OS.
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT 
    name AS [Setting],
    value_in_use AS [Current_Value],
    CASE name
        WHEN 'max server memory (MB)' THEN 'Target: 80-90% of RAM. Crucial to prevent OS memory starvation and paging.'
        WHEN 'min server memory (MB)' THEN 'Target: 0 or low value. Forces SQL to release memory if OS needs it (rarely changed).'
        WHEN 'cost threshold for parallelism' THEN 'Target: >= 50. Prevents trivial queries from parallelizing and bloating CPU.'
        WHEN 'max degree of parallelism' THEN 'Target: 8 or NUMA node size. Prevents a single query from saturating all cores.'
        WHEN 'optimize for ad hoc workloads' THEN 'Target: 1. Reduces plan cache bloat by only caching stubs for single-use queries.'
        WHEN 'backup compression default' THEN 'Target: 1. Faster backups and significantly less disk usage.'
        WHEN 'backup checksum default' THEN 'Target: 1. Ensures backup integrity during the write process.'
        WHEN 'remote admin connections' THEN 'Target: 1. Allows Dedicated Admin Connection (DAC) when the server is hung.'
        WHEN 'clr enabled' THEN 'Security: Only enable if using .NET assemblies. Potential attack surface.'
        WHEN 'database mail XPs' THEN 'Management: Required for SQL Agent alerts and DB mail notifications.'
        WHEN 'show advanced options' THEN 'Info: Must be 1 to see all configurations below.'
        WHEN 'priority boost' THEN 'Target: 0. Modern OS scheduling makes this obsolete and dangerous.'
        WHEN 'fill factor (%)' THEN 'Target: 0 or 100. Global setting for index fullness. Lowering this wastes RAM/Disk.'
        WHEN 'blocked process threshold (s)' THEN 'Target: 5-20. Required for Profiler/Extended Events to capture blocking.'
        WHEN 'max worker threads' THEN 'Target: 0 (Auto). SQL manages threads based on CPU count.'
        WHEN 'cursor threshold' THEN 'Legacy: Only affects synchronous cursor generation. Usually left at default.'
        WHEN 'ad hoc distributed queries' THEN 'Security: Leave 0 unless using OPENROWSET/OPENDATASOURCE (Risk).'
        WHEN 'contained database authentication' THEN 'Info: Enable if using Contained DBs for easier migration.'
        WHEN 'clr strict security' THEN 'Security: Target: 1. Forces signed assemblies (SQL 2017+).'
        ELSE 'Review based on application-specific requirements.'
    END AS [Expert_Rationale],
    CASE 
        WHEN name = 'cost threshold for parallelism' AND value_in_use = 5 THEN '🔴 CRITICAL'
        WHEN name = 'priority boost' AND value_in_use = 1 THEN '🔴 CRITICAL'
        WHEN name = 'max degree of parallelism' AND value_in_use = 0 THEN '🟡 WARNING'
        WHEN name = 'optimize for ad hoc workloads' AND value_in_use = 0 THEN '🟡 WARNING'
        WHEN name = 'backup checksum default' AND value_in_use = 0 THEN '🟡 WARNING'
        ELSE '🟢 OPTIMAL / REVIEW'
    END AS [Status]
FROM sys.configurations WITH (NOLOCK)
WHERE name IN (
    'max server memory (MB)', 'min server memory (MB)', 'cost threshold for parallelism', 'max degree of parallelism',
    'optimize for ad hoc workloads', 'backup compression default', 'backup checksum default', 'remote admin connections',
    'clr enabled', 'database mail XPs', 'show advanced options', 'priority boost', 'fill factor (%)',
    'blocked process threshold (s)', 'max worker threads', 'cursor threshold', 'ad hoc distributed queries',
    'contained database authentication', 'clr strict security'
)
ORDER BY [Status] ASC, name ASC;
