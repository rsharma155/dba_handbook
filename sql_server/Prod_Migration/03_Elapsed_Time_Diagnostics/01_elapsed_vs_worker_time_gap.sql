/*
================================================================================
Elapsed Time vs Worker Time Gap Analysis
================================================================================
Purpose:
    Diagnose the exact pattern: HIGH elapsed time, LOW CPU, LOW logical reads.
    This means the session is WAITING, not processing data pages.

How to use:
    1. Set @DatabaseName and optionally filter by query text fragment
    2. Run during or immediately after slowness
    3. Review Result Set 1 (plan cache / QS) and Result Set 2 (active requests)

Key columns:
    - total_elapsed_time / elapsed_time  → wall clock (ms)
    - total_worker_time / cpu_time        → CPU work only (ms)
    - total_logical_reads / logical_reads → buffer pool pages
    - Gap_Ratio = Elapsed / NULLIF(CPU,0) → values >> 5 strongly imply waits

Interpretation:
    Gap_Ratio > 10 with low reads:
        Session is blocked, waiting on latches, IO, compilation, or OS calls.
        DO NOT add optimizer hints — run 02_capture_live_session_waits.sql instead.

    Gap_Ratio ~ 1-3 with high reads:
        True CPU/IO query — optimizer/index tuning territory.

    Gap_Ratio high + wait_type LIKE 'LCK%':
        Blocking — 05_Concurrency/01_blocking_and_locks.sql

    Gap_Ratio high + wait_type LIKE 'PAGEIOLATCH%':
        Storage — even "small" queries hit system DB pages on cold cache

Next action if gap confirmed:
    → 02_capture_live_session_waits.sql while reproducing
    → 09_Extended_Events/01_xe_single_query_wait_capture.sql for proof

Criticality: Critical — core diagnostic for reported issue
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @DatabaseName SYSNAME = NULL;  -- e.g. N'MyAppDB'
DECLARE @QueryTextFilter NVARCHAR(256) = NULL;  -- e.g. N'%CustomerOrder%'
DECLARE @TopN INT = 25;

PRINT '=== 1. PLAN CACHE: QUERIES WITH ELAPSED >> CPU (since cache load) ===';
SELECT TOP (@TopN)
    DB_NAME(st.dbid) AS [Database_Name],
    qs.execution_count,
    qs.total_elapsed_time / 1000.0 AS [Total_Elapsed_Sec],
    qs.total_worker_time / 1000.0 AS [Total_CPU_Sec],
    qs.total_logical_reads,
    qs.total_physical_reads,
    CAST(qs.total_elapsed_time * 1.0 / NULLIF(qs.total_worker_time, 0) AS DECIMAL(18,2)) AS [Gap_Ratio_Elapsed_Over_CPU],
    CAST(qs.total_elapsed_time * 1.0 / NULLIF(qs.execution_count, 0) / 1000.0 AS DECIMAL(18,3)) AS [Avg_Elapsed_Sec],
    CAST(qs.total_worker_time * 1.0 / NULLIF(qs.execution_count, 0) / 1000.0 AS DECIMAL(18,3)) AS [Avg_CPU_Sec],
    qs.creation_time AS [Plan_Cached_At],
    qs.last_execution_time,
    SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
        CASE WHEN qs.statement_end_offset = -1 THEN LEN(st.text)
             ELSE (qs.statement_end_offset - qs.statement_start_offset) / 2 + 1 END) AS [Query_Text],
    CASE
        WHEN qs.total_elapsed_time * 1.0 / NULLIF(qs.total_worker_time, 0) > 20
             AND qs.total_logical_reads / NULLIF(qs.execution_count, 0) < 1000
            THEN N'WAIT-BOUND: Low work per execution, high wall time — NOT a hint problem'
        WHEN qs.total_worker_time > qs.total_elapsed_time * 0.8
            THEN N'CPU-BOUND: Tune plan/indexes/parallelism'
        WHEN qs.total_physical_reads > qs.total_logical_reads * 0.1
            THEN N'IO-BOUND: Check storage latency'
        ELSE N'Review waits on active execution'
    END AS [Diagnosis],
    qp.query_plan
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE st.dbid IS NOT NULL
  AND (@DatabaseName IS NULL OR DB_NAME(st.dbid) = @DatabaseName)
  AND (@QueryTextFilter IS NULL OR st.text LIKE @QueryTextFilter)
  AND qs.total_worker_time > 0
  AND qs.execution_count >= 1
ORDER BY [Gap_Ratio_Elapsed_Over_CPU] DESC, qs.total_elapsed_time DESC;

PRINT '=== 2. CURRENTLY RUNNING / SUSPENDED REQUESTS (live gap) ===';
SELECT
    r.session_id,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time AS [Current_Wait_ms],
    r.total_elapsed_time AS [Elapsed_ms],
    r.cpu_time AS [CPU_ms],
    r.logical_reads,
    r.reads AS [Physical_Reads],
    CAST(r.total_elapsed_time * 1.0 / NULLIF(r.cpu_time, 0) AS DECIMAL(18,2)) AS [Gap_Ratio],
    s.login_name,
    s.host_name,
    s.program_name,
    SUBSTRING(st.text, (r.statement_start_offset / 2) + 1,
        CASE WHEN r.statement_end_offset = -1 THEN LEN(st.text)
             ELSE (r.statement_end_offset - r.statement_start_offset) / 2 + 1 END) AS [Query_Text],
    CASE
        WHEN r.wait_type LIKE N'LCK%' THEN N'Blocked — 05_Concurrency/01_blocking_and_locks.sql'
        WHEN r.wait_type LIKE N'LATCH%' OR r.wait_type LIKE N'PAGELATCH%' THEN N'Latch — 04_Wait_Stats/03_latch_metadata_waits.sql'
        WHEN r.wait_type LIKE N'PAGEIOLATCH%' OR r.wait_type = N'WRITELOG' THEN N'IO — 08_Storage_OS/01_io_latency_deep_dive.sql'
        WHEN r.wait_type LIKE N'RESOURCE_SEMAPHORE%' THEN N'Memory grant queue'
        WHEN r.wait_type LIKE N'PREEMPTIVE%' THEN N'OS/AV/AD delay'
        WHEN r.cpu_time = 0 AND r.total_elapsed_time > 5000 THEN N'Start blocked/waiting before work — capture XE'
        ELSE N'Run 02_capture_live_session_waits.sql on this session_id'
    END AS [Next_Action]
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.session_id <> @@SPID
  AND (@DatabaseName IS NULL OR DB_NAME(st.dbid) = @DatabaseName)
  AND r.total_elapsed_time > 100
ORDER BY [Gap_Ratio] DESC, r.total_elapsed_time DESC;

PRINT '=== 3. WHY LOCAL VM EXECUTION IS STILL SLOW ===';
SELECT
    N'Running on the same VM only eliminates network (ASYNC_NETWORK_IO). ' +
    N'Blocking, latches, tempdb, buffer pool pressure, disk latency, AD token resolution, ' +
    N'and antivirus still apply to local SSMS/sqlcmd connections. ' +
    N'If Gap_Ratio is high locally, the bottleneck is server-side waits — not app tier.' AS [Explanation];
