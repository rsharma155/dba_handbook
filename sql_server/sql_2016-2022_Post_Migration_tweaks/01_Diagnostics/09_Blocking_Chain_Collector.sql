/*
================================================================================
09_Blocking_Chain_Collector.sql
Purpose : Live snapshot of blockers, victims, wait types, and statement text.
          Rule out blocking before blaming compat 160 / CE.
Requires: VIEW SERVER STATE
Safety  : Read-only (run during slowness incident)
================================================================================
*/
SET NOCOUNT ON;

;WITH BlockingChain AS (
    SELECT
        r.session_id,
        r.blocking_session_id,
        r.wait_type,
        r.wait_time,
        r.wait_resource,
        r.status,
        r.command,
        r.cpu_time,
        r.total_elapsed_time,
        r.reads,
        r.writes,
        r.logical_reads,
        DB_NAME(r.database_id) AS db_name,
        s.login_name,
        s.host_name,
        s.program_name,
        SUBSTRING(st.text, (r.statement_start_offset/2)+1,
            ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
              ELSE r.statement_end_offset END - r.statement_start_offset)/2)+1) AS statement_text
    FROM sys.dm_exec_requests AS r
    JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
    WHERE r.session_id <> @@SPID
)
SELECT
    bc.session_id AS victim_session_id,
    bc.blocking_session_id,
    bc.wait_type,
    bc.wait_time AS wait_time_ms,
    bc.wait_resource,
    bc.db_name,
    bc.login_name,
    bc.program_name,
    bc.total_elapsed_time AS elapsed_ms,
    LEFT(bc.statement_text, 220) AS victim_statement,
    LEFT(blocker.statement_text, 220) AS blocker_statement,
    blocker.total_elapsed_time AS blocker_elapsed_ms
FROM BlockingChain AS bc
LEFT JOIN BlockingChain AS blocker ON blocker.session_id = bc.blocking_session_id
WHERE bc.blocking_session_id <> 0
   OR bc.session_id IN (SELECT DISTINCT blocking_session_id FROM BlockingChain WHERE blocking_session_id <> 0)
ORDER BY bc.wait_time DESC;

-- Head blockers (not blocked themselves but blocking others)
SELECT
    r.session_id AS head_blocker_session,
    COUNT(*) AS victims_blocked,
    MAX(r.wait_time) AS max_victim_wait_ms,
    s.login_name,
    s.program_name,
    LEFT(st.text, 250) AS batch_text
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.blocking_session_id = 0
  AND EXISTS (
      SELECT 1 FROM sys.dm_exec_requests r2
      WHERE r2.blocking_session_id = r.session_id
  )
GROUP BY r.session_id, s.login_name, s.program_name, st.text
ORDER BY victims_blocked DESC;
