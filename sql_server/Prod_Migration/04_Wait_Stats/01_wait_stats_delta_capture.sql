/*
================================================================================
Wait Statistics Delta Capture (Before / After Reproduction)
================================================================================
Purpose:
    Instance-wide wait stats are cumulative since startup. For production
    triage, capture a CLEAN DELTA while reproducing slowness.

How to use:
    STEP 1: Run section A (snapshot baseline) — saves to #WaitBaseline
    STEP 2: Reproduce the problem (run slow app query, expand SSMS databases)
    STEP 3: Run section B (delta) within 1-5 minutes of reproduction

Interpretation:
    Focus on waits that APPEAR or SPIKE in the delta, not historical noise.
    High Avg_Wait_ms with moderate count = chronic bottleneck
    High Wait_Count with low avg = frequent short waits (latches)

Next action:
    Match top delta wait to 02_post_migration_wait_decoder.sql
    If delta is empty → issue may be outside SQL (SSMS client) or very brief

Rollback / reset (maintenance window only):
    DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);

Criticality: High
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

-- ============================================================================
-- SECTION A: BASELINE SNAPSHOT (run first, then reproduce issue)
-- ============================================================================
IF OBJECT_ID('tempdb..#WaitBaseline') IS NOT NULL DROP TABLE #WaitBaseline;

SELECT
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms
INTO #WaitBaseline
FROM sys.dm_os_wait_stats;

SELECT
    SYSDATETIME() AS [Baseline_Captured_At],
    (SELECT sqlserver_start_time FROM sys.dm_os_sys_info) AS [Instance_Start_Time],
    COUNT(*) AS [Wait_Types_Snapshotted],
    N'Reproduce slowness now, then run SECTION B below.' AS [Next_Step];

-- ============================================================================
-- SECTION B: DELTA (run after reproduction — paste below after GO if split)
-- ============================================================================
/*
-- Uncomment and run as batch 2 after reproduction:

SELECT TOP (20)
    d.wait_type,
    d.wait_count_delta AS [Wait_Count_Delta],
    d.wait_time_delta_ms / 1000.0 AS [Wait_Sec_Delta],
    d.signal_wait_delta_ms / 1000.0 AS [Signal_Sec_Delta],
    CAST(d.wait_time_delta_ms * 1.0 / NULLIF(d.wait_count_delta, 0) AS DECIMAL(18,2)) AS [Avg_Wait_ms_Delta],
    CASE
        WHEN d.wait_type LIKE N'LCK%' THEN N'Blocking'
        WHEN d.wait_type LIKE N'LATCH%' OR d.wait_type LIKE N'PAGELATCH%' OR d.wait_type LIKE N'METADATA%' THEN N'Latch/Metadata'
        WHEN d.wait_type LIKE N'PAGEIOLATCH%' OR d.wait_type IN (N'WRITELOG', N'IO_COMPLETION') THEN N'Storage IO'
        WHEN d.wait_type LIKE N'RESOURCE_SEMAPHORE%' THEN N'Memory/Compile'
        WHEN d.wait_type LIKE N'PREEMPTIVE%' THEN N'OS/External'
        WHEN d.wait_type IN (N'CXPACKET', N'CXCONSUMER') THEN N'Parallelism'
        ELSE N'Other'
    END AS [Category],
    CASE
        WHEN d.wait_type LIKE N'LCK%' THEN N'05_Concurrency/01_blocking_and_locks.sql'
        WHEN d.wait_type LIKE N'LATCH%' OR d.wait_type LIKE N'METADATA%' THEN N'04_Wait_Stats/03_latch_metadata_waits.sql'
        WHEN d.wait_type LIKE N'PAGEIOLATCH%' THEN N'08_Storage_OS/01_io_latency_deep_dive.sql'
        WHEN d.wait_type LIKE N'PREEMPTIVE%' THEN N'08_Storage_OS/02_os_integration_post_migration.sql'
        ELSE N'04_Wait_Stats/02_post_migration_wait_decoder.sql'
    END AS [Next_Script]
FROM (
    SELECT
        cur.wait_type,
        cur.waiting_tasks_count - b.waiting_tasks_count AS wait_count_delta,
        cur.wait_time_ms - b.wait_time_ms AS wait_time_delta_ms,
        cur.signal_wait_time_ms - b.signal_wait_time_ms AS signal_wait_delta_ms
    FROM sys.dm_os_wait_stats AS cur
    INNER JOIN #WaitBaseline AS b ON cur.wait_type = b.wait_type
    WHERE cur.waiting_tasks_count > b.waiting_tasks_count
) AS d
ORDER BY d.wait_time_delta_ms DESC;
*/

PRINT 'Baseline captured in #WaitBaseline (session-scoped).';
PRINT 'Reproduce issue, then run SECTION B (uncomment block above) in SAME session.';
