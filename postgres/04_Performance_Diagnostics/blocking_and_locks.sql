/*
================================================================================
Blocking and Locks — Blocking chains and lock holders
================================================================================
Description:
    Identifies blocked sessions, blocking PIDs, lock modes, and wait durations.

Action:  Contact app owner for head blocker; use pg_cancel_backend() or pg_terminate_backend() with care.

Criticality: High
================================================================================
*/

SELECT blocked.pid AS blocked_pid,
       blocked.usename AS blocked_user,
       blocked.datname,
       blocked.application_name,
       blocking.pid AS blocking_pid,
       blocking.usename AS blocking_user,
       round(extract(epoch FROM (now() - blocked.query_start))::numeric, 1) AS blocked_sec,
       blocked.wait_event_type,
       blocked.wait_event,
       left(blocked.query, 80) AS blocked_query,
       left(blocking.query, 80) AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.pid <> pg_backend_pid()
ORDER BY blocked_sec DESC;

SELECT l.locktype, l.mode, l.granted,
       a.pid, a.usename, a.datname, a.state,
       left(a.query, 60) AS query_snippet
FROM pg_locks l
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE NOT l.granted
ORDER BY a.query_start
LIMIT 30;
