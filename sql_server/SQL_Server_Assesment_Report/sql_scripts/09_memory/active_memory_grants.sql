/* SQL_Server_Assessment */
SELECT mg.session_id AS SessionId,mg.request_id AS RequestId,
       CASE WHEN mg.grant_time IS NULL THEN 'Waiting' ELSE 'Granted' END AS GrantStatus,
       mg.request_time AS RequestTime,mg.grant_time AS GrantTime,
       mg.requested_memory_kb/1024.0 AS RequestedMB,mg.granted_memory_kb/1024.0 AS GrantedMB,
       mg.required_memory_kb/1024.0 AS RequiredMB,mg.used_memory_kb/1024.0 AS UsedMB,
       mg.max_used_memory_kb/1024.0 AS MaxUsedMB,mg.dop AS DOP,mg.wait_time_ms AS WaitTimeMs,
       s.login_name AS LoginName,s.host_name AS HostName,s.program_name AS ProgramName,
       LEFT(REPLACE(REPLACE(txt.text,CHAR(13),' '),CHAR(10),' '),1000) AS QueryText
FROM sys.dm_exec_query_memory_grants mg
LEFT JOIN sys.dm_exec_sessions s ON mg.session_id=s.session_id
OUTER APPLY sys.dm_exec_sql_text(mg.sql_handle) txt
WHERE mg.session_id <> @@SPID
  AND (s.program_name IS NULL
       OR s.program_name COLLATE Latin1_General_CI_AS NOT LIKE 'dbatools PowerShell%')
ORDER BY CASE WHEN mg.grant_time IS NULL THEN 0 ELSE 1 END,mg.requested_memory_kb DESC;
