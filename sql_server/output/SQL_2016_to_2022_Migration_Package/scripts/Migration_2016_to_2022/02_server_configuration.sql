/*
    Migration 2016 -> 2022 | Server configuration audit
    Run on: SOURCE and TARGET (compare side-by-side)
    Risk: Read-only
*/
SET NOCOUNT ON;

SELECT
    c.name,
    c.value,
    c.value_in_use,
    c.is_dynamic,
    c.is_advanced,
    c.description
FROM sys.configurations AS c
WHERE c.name IN (
    N'max server memory (MB)',
    N'min server memory (MB)',
    N'max degree of parallelism',
    N'cost threshold for parallelism',
    N'max worker threads',
    N'backup compression default',
    N'optimize for ad hoc workloads',
    N'remote admin connections',
    N'clr enabled',
    N'xp_cmdshell',
    N'Agent XPs',
    N'Database Mail XPs',
    N'allow updates',
    N'affinity mask',
    N'affinity i/o mask',
    N'lightweight pooling'
)
ORDER BY c.name;

SELECT
    SERVERPROPERTY('IsIntegratedSecurityOnly') AS [WindowsAuthOnly],
    CASE WHEN EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = N'sa' AND is_disabled = 0)
         THEN N'ENABLED' ELSE N'DISABLED_OR_MISSING' END AS [SaLoginStatus];

-- Memory-optimized TempDB metadata (SQL Server 2019+ / 2022) - critical for high-concurrency TempDB
-- Enable (requires restart): ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON;
SELECT
    SERVERPROPERTY('ProductMajorVersion') AS [MajorVersion],
    SERVERPROPERTY('IsTempdbMetadataMemoryOptimized') AS [IsTempdbMetadataMemoryOptimized],
    CASE
        WHEN CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 15
            THEN N'N/A on SQL Server 2016 source - plan enablement on 2022 target'
        WHEN SERVERPROPERTY('IsTempdbMetadataMemoryOptimized') = 1
            THEN N'ENABLED'
        ELSE N'DISABLED - evaluate for latch-heavy TempDB workloads on 2022'
    END AS [TempdbMetadataGuidance];

-- Related TempDB shape (file count / size) for contention review
SELECT
    COUNT(*) AS [TempDBDataFileCount],
    SUM(size) * 8 / 1024 AS [TempDBTotalSizeMB],
    SUM(CASE WHEN type_desc = N'ROWS' AND growth = 0 THEN 1 ELSE 0 END) AS [FixedSizeDataFiles]
FROM tempdb.sys.database_files;
