/*
================================================================================
Connection Analysis — Client patterns and connection age
================================================================================
Description:
    Connection age distribution, client addresses, and backend types.

Action:  Stale idle connections → reduce pool size or enable timeouts.

Criticality: Medium
================================================================================
*/

SELECT state, count(*) AS sessions,
       round(avg(extract(epoch FROM (now() - backend_start)))::numeric, 0) AS avg_age_sec,
       round(max(extract(epoch FROM (now() - backend_start)))::numeric, 0) AS max_age_sec
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY sessions DESC;

SELECT client_addr, application_name, usename, count(*) AS connections
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY client_addr, application_name, usename
HAVING count(*) > 10
ORDER BY connections DESC;
