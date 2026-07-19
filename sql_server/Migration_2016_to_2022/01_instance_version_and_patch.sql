/*
    Migration 2016 -> 2022 | Instance version and patch baseline
    Run on: SOURCE (2016) before migration planning; TARGET (2022) after cutover
    Risk: Read-only
*/
SET NOCOUNT ON;

SELECT
    @@SERVERNAME AS [InstanceName],
    SERVERPROPERTY('MachineName') AS [MachineName],
    SERVERPROPERTY('InstanceName') AS [NamedInstance],
    SERVERPROPERTY('Edition') AS [Edition],
    SERVERPROPERTY('ProductVersion') AS [ProductVersion],
    SERVERPROPERTY('ProductLevel') AS [ProductLevel],
    SERVERPROPERTY('ProductUpdateLevel') AS [ProductUpdateLevel],
    SERVERPROPERTY('ProductMajorVersion') AS [MajorVersion],
    SERVERPROPERTY('Collation') AS [ServerCollation],
    SERVERPROPERTY('IsClustered') AS [IsClustered],
    SERVERPROPERTY('IsHadrEnabled') AS [IsHadrEnabled];

SELECT
    sqlserver_start_time,
    cpu_count,
    hyperthread_ratio,
    physical_memory_kb / 1024 AS [physical_memory_mb],
    virtual_memory_kb / 1024 AS [virtual_memory_mb],
    committed_kb / 1024 AS [committed_mb],
    committed_target_kb / 1024 AS [committed_target_mb]
FROM sys.dm_os_sys_info;

-- In-place upgrade prerequisite: SQL Server 2016 SP3+
IF SERVERPROPERTY('ProductMajorVersion') = 13
   AND SERVERPROPERTY('ProductLevel') <> N'SP3'
BEGIN
    RAISERROR('WARNING: SQL Server 2016 must be at SP3 or later for supported in-place upgrade to 2022.', 10, 1) WITH NOWAIT;
END;
