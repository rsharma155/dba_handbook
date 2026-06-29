/*
================================================================================
Blocking, Lock Escalation, and Long Transactions
================================================================================
Purpose:
    Full blocking analysis when LCK_* waits dominate or elapsed >> CPU with
    low reads. Query hints CANNOT resolve lock waits.

Provides:
    (1) Head blockers and victims
    (2) Blocking hierarchy tree
    (3) Lock details per session (object-level where available)
    (4) Open transaction count by session
    (5) Lock escalation candidates (big scans in explicit transactions)

Interpretation:
    blocking_session_id chain → fix head blocker first
    open_transaction_count > 0 on sleeping session → app not committing
    Lock escalation on large table → partition strategy or ROWLOCK hints (careful)

Next action if head blocker is maintenance:
    Reschedule DBCC/index rebuild; use ONLINE index rebuild where possible

If no blocking but LCK_M_SCH_S:
    SSMS table designer or uncommitted DDL — 02_ssms_metadata_slowness.sql

Criticality: Critical
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET QUOTED_IDENTIFIER ON;

PRINT '=== HEAD BLOCKERS AND VICTIMS ===';
SELECT
    r.session_id,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time AS [Wait_ms],
    r.wait_resource,
    r.open_transaction_count,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status AS [Session_Status],
    SUBSTRING(st.text, (r.statement_start_offset / 2) + 1,
        CASE WHEN r.statement_end_offset = -1 THEN LEN(st.text)
             ELSE (r.statement_end_offset - r.statement_start_offset) / 2 + 1 END) AS [Current_Statement]
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.blocking_session_id <> 0
   OR r.session_id IN (SELECT DISTINCT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0)
ORDER BY r.blocking_session_id, r.wait_time DESC;

PRINT '=== BLOCKING TREE ===';
;WITH blockers AS (
    SELECT
        session_id,
        blocking_session_id,
        0 AS lvl,
        CAST(CAST(session_id AS NVARCHAR(12)) AS NVARCHAR(MAX)) AS path
    FROM sys.dm_exec_requests
    WHERE blocking_session_id = 0
      AND session_id IN (SELECT DISTINCT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0)
    UNION ALL
    SELECT
        r.session_id,
        r.blocking_session_id,
        b.lvl + 1,
        CAST(b.path + N' -> ' + CAST(r.session_id AS NVARCHAR(12)) AS NVARCHAR(MAX))
    FROM sys.dm_exec_requests AS r
    INNER JOIN blockers AS b ON r.blocking_session_id = b.session_id
)
SELECT REPLICATE(N'  ', lvl) + CAST(session_id AS VARCHAR(10)) AS [Hierarchy],
       path AS [Block_Chain],
       CASE WHEN lvl = 0 THEN N'HEAD BLOCKER — investigate this session' ELSE N'Victim' END AS [Role]
FROM blockers
ORDER BY path;

PRINT '=== SLEEPING SESSIONS WITH OPEN TRANSACTIONS (common app bug) ===';
SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status,
    s.open_transaction_count,
    DATEDIFF(SECOND, s.last_request_end_time, SYSDATETIME()) AS [Idle_Sec_Since_Last_Request],
    st.text AS [Last_Batch_Text]
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_connections AS c ON s.session_id = c.session_id
CROSS APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) AS st
WHERE s.is_user_process = 1
  AND s.open_transaction_count > 0
  AND s.status = N'sleeping'
ORDER BY s.open_transaction_count DESC, [Idle_Sec_Since_Last_Request] DESC;

PRINT '=== LOCK COUNT BY SESSION (top 20) ===';
SELECT TOP (20)
    l.request_session_id AS [Session_ID],
    COUNT(*) AS [Lock_Count],
    SUM(CASE WHEN l.request_status = N'WAIT' THEN 1 ELSE 0 END) AS [Waiting_Locks],
    MAX(l.request_mode) AS [Sample_Mode],
    s.login_name,
    s.program_name
FROM sys.dm_tran_locks AS l
INNER JOIN sys.dm_exec_sessions AS s ON l.request_session_id = s.session_id
WHERE l.request_session_id > 50
GROUP BY l.request_session_id, s.login_name, s.program_name
ORDER BY [Lock_Count] DESC;

PRINT '=== IF BLOCKING NOT FOUND: check RCSI / snapshot isolation conflicts ===';
SELECT
    d.name,
    d.snapshot_isolation_state_desc,
    d.is_read_committed_snapshot_on AS [RCSI_Enabled]
FROM sys.databases AS d
WHERE d.database_id > 4;

PRINT 'Remediation: Identify head blocker query plan and transaction scope.';
PRINT 'Last resort: KILL <head_blocker_spid> — only after documenting cause.';
