/*
    Migration 2016 -> 2022 | Deprecated feature usage counters
    Run on SOURCE; remediate before migration. Also use DMA / SSMS Upgrade Assessment.
    Risk: Read-only
*/
SET NOCOUNT ON;

SELECT
    instance_name,
    counter_name,
    cntr_value AS [UsageCount]
FROM sys.dm_os_performance_counters
WHERE object_name LIKE N'%Deprecated Features%'
  AND cntr_value > 0
ORDER BY cntr_value DESC, counter_name;

-- Common deprecated patterns to search manually:
-- SQL Server Profiler traces, Database Mirroring, HASH/GROUP BY legacy hints, etc.
