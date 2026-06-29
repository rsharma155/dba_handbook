/*
================================================================================
Post-Migration Wait Pattern Decoder
================================================================================
Purpose:
    Maps wait types to root causes common after SQL Server version/edition
    upgrades. Includes investigation queries and remediation pointers.

Use with:
    Output from 01_wait_stats_delta_capture.sql OR triage playbook top waits.

Criticality: High
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

PRINT '=== TOP 25 ACTIONABLE WAITS WITH POST-MIGRATION CONTEXT ===';
SELECT TOP (25)
    ws.wait_type,
    ws.waiting_tasks_count AS [Wait_Count],
    ws.wait_time_ms / 1000.0 AS [Total_Wait_Sec],
    CAST(ws.wait_time_ms * 1.0 / NULLIF(ws.waiting_tasks_count, 0) AS DECIMAL(18,2)) AS [Avg_Wait_ms],
    CASE
        WHEN ws.wait_type LIKE N'LCK_M_S%' THEN N'Shared lock block — reader blocked by writer or DDL'
        WHEN ws.wait_type LIKE N'LCK_M_X%' THEN N'Exclusive lock — blocking chain; check long transactions'
        WHEN ws.wait_type LIKE N'LCK_M_IX%' THEN N'Intent exclusive — update/delete blocking'
        WHEN ws.wait_type LIKE N'LCK_M_SCH_%' THEN N'Schema lock — DDL or SSMS designer open'
        WHEN ws.wait_type LIKE N'LATCH_EX%' THEN N'Exclusive latch — metadata cache, hash buckets'
        WHEN ws.wait_type LIKE N'LATCH_SH%' THEN N'Shared latch — frequent with parallel metadata scans'
        WHEN ws.wait_type LIKE N'PAGELATCH_%' THEN N'TempDB PFS/SGAM/GAM or allocation contention'
        WHEN ws.wait_type LIKE N'METADATA_LATCH_%' THEN N'System catalog latch — SSMS Object Explorer'
        WHEN ws.wait_type LIKE N'PAGEIOLATCH_SH%' THEN N'Waiting for data page read from disk (cold cache or IO slow)'
        WHEN ws.wait_type LIKE N'PAGEIOLATCH_EX%' THEN N'Waiting for page write flush'
        WHEN ws.wait_type = N'WRITELOG' THEN N'Transaction log write stall — check log file latency'
        WHEN ws.wait_type = N'IO_COMPLETION' THEN N'Async IO completion — often bulk IO or backup'
        WHEN ws.wait_type = N'RESOURCE_SEMAPHORE' THEN N'Query waiting for memory grant (sort/hash)'
        WHEN ws.wait_type = N'RESOURCE_SEMAPHORE_QUERY_COMPILE' THEN N'Compilation throttling — plan cache pressure'
        WHEN ws.wait_type = N'SOS_SCHEDULER_YIELD' THEN N'CPU quantum exhausted — real CPU pressure'
        WHEN ws.wait_type = N'CXPACKET' THEN N'Parallel skew — one thread waits for others'
        WHEN ws.wait_type = N'CXCONSUMER' THEN N'Parallel consumer wait — often with CXPACKET'
        WHEN ws.wait_type LIKE N'PREEMPTIVE_OS_GETPROCADDRESS%' THEN N'Windows DLL call — sometimes AV hooks'
        WHEN ws.wait_type LIKE N'PREEMPTIVE_OS_WRITEFILEGATHER%' THEN N'IFI disabled — zeroing data files during growth'
        WHEN ws.wait_type LIKE N'PREEMPTIVE_OS_AUTHENTICATIONOPS%' THEN N'Windows auth / AD latency'
        WHEN ws.wait_type = N'THREADPOOL' THEN N'CRITICAL: No worker threads — reduce load immediately'
        WHEN ws.wait_type = N'ASYNC_NETWORK_IO' THEN N'Client slow fetch — unlikely if local VM only'
        ELSE N'Look up wait type in SQL Server docs; correlate with active session'
    END AS [Post_Migration_Meaning],
    CASE
        WHEN ws.wait_type LIKE N'LCK%' THEN N'05_Concurrency/01_blocking_and_locks.sql'
        WHEN ws.wait_type LIKE N'LATCH%' OR ws.wait_type LIKE N'METADATA%' OR ws.wait_type LIKE N'PAGELATCH%' THEN N'04_Wait_Stats/03_latch_metadata_waits.sql'
        WHEN ws.wait_type LIKE N'PAGEIOLATCH%' OR ws.wait_type IN (N'WRITELOG', N'IO_COMPLETION') THEN N'08_Storage_OS/01_io_latency_deep_dive.sql'
        WHEN ws.wait_type LIKE N'RESOURCE_SEMAPHORE%' THEN N'07_Instance_Config/01_post_migration_config_audit.sql'
        WHEN ws.wait_type LIKE N'PREEMPTIVE%' THEN N'08_Storage_OS/02_os_integration_post_migration.sql'
        WHEN ws.wait_type IN (N'CXPACKET', N'CXCONSUMER') THEN N'06_Optimizer_Plans/01_compatibility_and_ce.sql'
        ELSE N'03_Elapsed_Time_Diagnostics/02_capture_live_session_waits.sql'
    END AS [Next_Script],
    CASE
        WHEN ws.wait_type LIKE N'LCK%' THEN N'Find head blocker; shorten transactions; consider RCSI; avoid SCHEMA locks in business hours'
        WHEN ws.wait_type LIKE N'PAGELATCH_%' THEN N'Add tempdb data files (1 per core up to 8); enable TF 1118/1117 for tempdb'
        WHEN ws.wait_type LIKE N'PAGEIOLATCH%' THEN N'Check avg disk latency; increase memory; fix indexes'
        WHEN ws.wait_type = N'PREEMPTIVE_OS_WRITEFILEGATHER' THEN N'Enable IFI for service account'
        WHEN ws.wait_type = N'RESOURCE_SEMAPHORE_QUERY_COMPILE' THEN N'Clear ad hoc plan bloat; optimize for ad hoc workloads=1'
        ELSE N'See README.md wait pattern table'
    END AS [Remediation_Summary]
FROM sys.dm_os_wait_stats AS ws
WHERE ws.waiting_tasks_count > 0
  AND ws.wait_type NOT IN (N'SLEEP_TASK', N'WAIT_XTP_HOST_WAIT', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP')
ORDER BY ws.wait_time_ms DESC;

PRINT '=== SIGNAL WAIT PERCENTAGE (scheduler pressure indicator) ===';
SELECT TOP (15)
    wait_type,
    wait_time_ms,
    signal_wait_time_ms,
    CAST(100.0 * signal_wait_time_ms / NULLIF(wait_time_ms, 0) AS DECIMAL(5,2)) AS [Signal_Pct],
    CASE WHEN signal_wait_time_ms * 1.0 / NULLIF(wait_time_ms, 0) > 0.25
         THEN N'High signal % — CPU scheduling; check runnable tasks and MAXDOP'
         ELSE N'Resource wait dominates — IO/lock/latch'
    END AS [Interpretation]
FROM sys.dm_os_wait_stats
WHERE wait_time_ms > 1000 AND waiting_tasks_count > 0
ORDER BY signal_wait_time_ms DESC;
