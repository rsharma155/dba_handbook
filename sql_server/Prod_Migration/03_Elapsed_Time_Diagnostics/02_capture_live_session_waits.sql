/*
================================================================================
Capture Live Session Waits During Slow Query
================================================================================
Purpose:
    Pinpoint what a SPECIFIC session is waiting on while your slow query runs.
    Use when plan cache shows low CPU/reads but high elapsed time.

How to use:
    1. Start your slow query in Session A (note @@SPID or use SSMS status bar)
    2. Set @TargetSessionId to Session A's SPID
    3. Run this script repeatedly in Session B while A is suspended/slow
    4. Optionally run the polling loop block at bottom for 60 seconds

Interpretation:
    wait_type on dm_exec_requests = current wait (most important)
    dm_os_waiting_tasks = lower-level task waits with resource description
    blocking_session_id > 0 → not optimizer issue

Next action by wait_type:
    LCK_*           → 05_Concurrency/01_blocking_and_locks.sql
    LATCH_*         → 04_Wait_Stats/03_latch_metadata_waits.sql
    PAGEIOLATCH_*   → 08_Storage_OS/01_io_latency_deep_dive.sql
    PREEMPTIVE_*    → 08_Storage_OS/02_os_integration_post_migration.sql
    CXPACKET        → only if MAXDOP 1 was NOT tested at session level

If wait_type = NULL and status = running but still slow:
    May be client-side (SSMS rendering) or async completion — use XE script.

Criticality: Critical
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @TargetSessionId INT = NULL;  -- REQUIRED: set to slow query SPID

IF @TargetSessionId IS NULL
BEGIN
    PRINT 'Set @TargetSessionId to the SPID running your slow query.';
    PRINT 'Active non-system sessions:';
    SELECT session_id, login_name, host_name, program_name, status
    FROM sys.dm_exec_sessions
    WHERE is_user_process = 1 AND session_id <> @@SPID
    ORDER BY session_id;
    RETURN;
END;

PRINT '=== SESSION OVERVIEW ===';
SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status,
    s.cpu_time AS [Session_CPU_ms],
    s.memory_usage * 8 AS [Memory_KB],
    s.total_elapsed_time AS [Session_Elapsed_ms],
    s.reads,
    s.writes,
    s.logical_reads,
    s.last_request_start_time,
    s.last_request_end_time
FROM sys.dm_exec_sessions AS s
WHERE s.session_id = @TargetSessionId;

PRINT '=== REQUEST-LEVEL WAITS (dm_exec_requests) ===';
SELECT
    r.session_id,
    r.status,
    r.command,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time AS [Wait_ms],
    r.wait_resource,
    r.open_transaction_count,
    r.percent_complete,
    r.estimated_completion_time,
    r.cpu_time,
    r.total_elapsed_time,
    r.logical_reads,
    r.reads,
    r.writes,
    r.dop,
    r.granted_query_memory * 8192 / 1024 AS [Granted_Memory_KB],
    SUBSTRING(st.text, (r.statement_start_offset / 2) + 1,
        CASE WHEN r.statement_end_offset = -1 THEN LEN(st.text)
             ELSE (r.statement_end_offset - r.statement_start_offset) / 2 + 1 END) AS [Current_Statement],
    st.text AS [Full_Batch_Text]
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.session_id = @TargetSessionId;

PRINT '=== TASK-LEVEL WAITS (dm_os_waiting_tasks) ===';
SELECT
    wt.session_id,
    wt.wait_type,
    wt.wait_duration_ms,
    wt.resource_description,
    wt.blocking_session_id,
    t.task_state,
    t.context_switches_count,
    t.pending_io_count
FROM sys.dm_os_waiting_tasks AS wt
LEFT JOIN sys.dm_os_tasks AS t ON wt.waiting_task_address = t.task_address
WHERE wt.session_id = @TargetSessionId
ORDER BY wt.wait_duration_ms DESC;

PRINT '=== BLOCKING CHAIN (if blocked) ===';
;WITH block_chain AS (
    SELECT
        r.session_id,
        r.blocking_session_id,
        0 AS lvl,
        CAST(r.session_id AS VARCHAR(MAX)) AS chain
    FROM sys.dm_exec_requests AS r
    WHERE r.session_id = @TargetSessionId

    UNION ALL

    SELECT
        r.session_id,
        r.blocking_session_id,
        bc.lvl + 1,
        CAST(bc.chain + N' <- ' + CAST(r.session_id AS VARCHAR(12)) AS VARCHAR(MAX))
    FROM sys.dm_exec_requests AS r
    INNER JOIN block_chain AS bc ON r.session_id = bc.blocking_session_id
    WHERE bc.lvl < 20
)
SELECT * FROM block_chain ORDER BY lvl;

/*
-- POLLING LOOP: uncomment to sample every 2 seconds for 60 seconds
DECLARE @i INT = 0;
WHILE @i < 30
BEGIN
    SELECT SYSDATETIME() AS sample_time, wait_type, wait_time, wait_resource, status
    FROM sys.dm_exec_requests WHERE session_id = @TargetSessionId;
    WAITFOR DELAY '00:00:02';
    SET @i += 1;
END;
*/
