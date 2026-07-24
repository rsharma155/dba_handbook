/* SQL_Server_Assessment */
SELECT r.blocking_session_id AS BlockingSessionId, r.session_id AS BlockedSessionId,
       DB_NAME(r.database_id) AS DatabaseName, r.wait_type AS WaitType,
       r.wait_time/1000.0 AS WaitSeconds, r.wait_resource AS WaitResource,
       s.login_name AS BlockedLogin, s.host_name AS BlockedHost,
       LEFT(t.text,2000) AS BlockedStatement
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id=s.session_id
LEFT JOIN sys.dm_exec_sessions blocker ON r.blocking_session_id=blocker.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id <> 0
  AND r.session_id <> @@SPID
  AND r.blocking_session_id <> @@SPID
  AND (s.program_name IS NULL
       OR s.program_name COLLATE Latin1_General_CI_AS NOT LIKE 'dbatools PowerShell%')
  AND (blocker.program_name IS NULL
       OR blocker.program_name COLLATE Latin1_General_CI_AS NOT LIKE 'dbatools PowerShell%')
ORDER BY r.wait_time DESC;
