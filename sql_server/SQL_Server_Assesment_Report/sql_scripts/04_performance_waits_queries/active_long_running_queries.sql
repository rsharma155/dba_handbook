/* SQL_Server_Assessment */
SELECT TOP (25) r.session_id AS SessionId, r.status AS Status, DB_NAME(r.database_id) AS DatabaseName,
       r.total_elapsed_time/1000.0 AS ElapsedSeconds, r.cpu_time/1000.0 AS CpuSeconds,
       r.logical_reads AS LogicalReads, r.reads AS PhysicalReads, r.writes AS Writes,
       s.login_name AS LoginName, s.host_name AS HostName, s.program_name AS ProgramName,
       LEFT(t.text,4000) AS QueryText
FROM sys.dm_exec_requests r JOIN sys.dm_exec_sessions s ON r.session_id=s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID AND s.is_user_process=1
  AND (s.program_name IS NULL
       OR s.program_name COLLATE Latin1_General_CI_AS NOT LIKE 'dbatools PowerShell%')
ORDER BY r.total_elapsed_time DESC;
