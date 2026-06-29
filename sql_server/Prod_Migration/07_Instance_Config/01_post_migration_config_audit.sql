/*
================================================================================
Post-Migration Instance Configuration Audit
================================================================================
Purpose:
    Audits instance settings that commonly cause systemic slowness after
    migrating from Express 2019 to Developer 2025 (or any version jump).

Validates:
    max/min server memory, MAXDOP, CTFP, optimize for ad hoc workloads,
    backup defaults, remote admin connections, blocked process threshold,
    priority boost, affinity masks, max worker threads, TF status

Interpretation:
    Follow Status column — Critical/Warning items first.

Next action:
    07_Instance_Config/02_recommended_fixes_with_rollback.sql

Criticality: High
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @RAM_MB BIGINT = (SELECT physical_memory_kb / 1024 FROM sys.dm_os_sys_info);
DECLARE @CPU INT = (SELECT cpu_count FROM sys.dm_os_sys_info);

;WITH ConfigAudit AS (
    SELECT
        c.name AS [Setting],
        c.value AS [Configured],
        c.value_in_use AS [Running_Value],
        c.is_dynamic,
        c.is_advanced,
        CASE c.name
            WHEN N'max server memory (MB)' THEN
                CASE
                    WHEN c.value_in_use < @RAM_MB * 0.4 THEN N'CRITICAL — likely Express-era cap'
                    WHEN c.value_in_use > @RAM_MB * 0.95 THEN N'WARNING — may starve OS'
                    ELSE N'OK — validate ~80-90% RAM on dedicated server'
                END
            WHEN N'max degree of parallelism' THEN
                CASE
                    WHEN c.value_in_use = 0 THEN N'WARNING — unlimited parallelism on OLTP'
                    WHEN c.value_in_use = 1 THEN N'INFO — OK for test; verify CTFP if prod'
                    ELSE N'OK'
                END
            WHEN N'cost threshold for parallelism' THEN
                CASE WHEN c.value_in_use <= 5 THEN N'CRITICAL — default 5, raise to 50 for OLTP' ELSE N'OK' END
            WHEN N'optimize for ad hoc workloads' THEN
                CASE WHEN c.value_in_use = 0 THEN N'WARNING — plan cache bloat risk' ELSE N'OK' END
            WHEN N'priority boost' THEN
                CASE WHEN c.value_in_use = 1 THEN N'CRITICAL — set to 0' ELSE N'OK' END
            WHEN N'remote admin connections' THEN
                CASE WHEN c.value_in_use = 0 THEN N'WARNING — enable DAC for hung instance' ELSE N'OK' END
            WHEN N'blocked process threshold (s)' THEN
                CASE WHEN c.value_in_use = 0 THEN N'INFO — set 5-10 for XE blocking capture' ELSE N'OK' END
            ELSE N'Review'
        END AS [Status],
        CASE c.name
            WHEN N'max server memory (MB)' THEN N'Leave 4-8 GB for OS; increase gradually after upgrade'
            WHEN N'max degree of parallelism' THEN N'Common: MIN(8, cores per NUMA node)'
            WHEN N'cost threshold for parallelism' THEN N'Set 50 for OLTP; lower only for reporting workloads'
            WHEN N'optimize for ad hoc workloads' THEN N'Enable if many single-use ad hoc queries'
            ELSE N'See 02_recommended_fixes_with_rollback.sql'
        END AS [Expert_Rationale]
    FROM sys.configurations AS c
    WHERE c.name IN (
        N'max server memory (MB)', N'min server memory (MB)', N'max degree of parallelism',
        N'cost threshold for parallelism', N'optimize for ad hoc workloads', N'backup compression default',
        N'backup checksum default', N'remote admin connections', N'priority boost', N'fill factor (%)',
        N'blocked process threshold (s)', N'max worker threads', N'affinity mask', N'affinity64 mask',
        N'clr enabled', N'contained database authentication'
    )
)
SELECT
    Setting,
    Configured,
    Running_Value,
    is_dynamic,
    is_advanced,
    Status,
    Expert_Rationale
FROM ConfigAudit
ORDER BY
    CASE
        WHEN Status LIKE N'CRITICAL%' THEN 1
        WHEN Status LIKE N'WARNING%' THEN 2
        ELSE 3
    END,
    Setting;

PRINT '=== GLOBAL TRACE FLAGS ===';
DBCC TRACESTATUS(-1);

PRINT '=== TF 4199 (optimizer hotfixes) — on by default in recent versions ===';
SELECT
    N'TF 4199 enables incremental optimizer fixes. After major upgrade, verify no conflicting legacy TFs.' AS [Note];

PRINT '=== IFI STATUS ===';
IF COL_LENGTH(N'sys.dm_server_services', N'instant_file_initialization_enabled') IS NOT NULL
    SELECT servicename, instant_file_initialization_enabled FROM sys.dm_server_services
    WHERE servicename LIKE N'SQL Server (%';
