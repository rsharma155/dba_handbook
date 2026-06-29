/*
================================================================================
Wait Statistics Delta — AFTER Reproduction (Batch 2)
================================================================================
Purpose:
    Run this AFTER 01_wait_stats_delta_capture.sql Section A AND reproducing
    the slowness — in the SAME SSMS query window (same session).

    #WaitBaseline is session-scoped; a new query window will not see it.

If you need cross-session delta:
    Use 01_wait_stats_delta_capture.sql Section A, reproduce, then run this
    in the original window without closing it.

Criticality: High
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

IF OBJECT_ID('tempdb..#WaitBaseline') IS NULL
BEGIN
    RAISERROR(N'#WaitBaseline not found. Run Section A of 01_wait_stats_delta_capture.sql first in this session.', 16, 1);
    RETURN;
END;

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
