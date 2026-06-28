/*
================================================================================
Blocking Detection — Log blocking chains to governance_alert
================================================================================
Description:
    Captures blocking relationships exceeding policy threshold.

Prerequisite: preventive_measures/01_create_governance_schema.sql

Criticality: High
================================================================================
*/

INSERT INTO dba.governance_alert (alert_type, severity, database_name, pid, username, duration_sec, detail, query_snippet)
SELECT 'blocking_chain', 'WARNING',
       blocked.datname, blocked.pid, blocked.usename,
       round(extract(epoch FROM (now() - blocked.query_start))::numeric, 1),
       format('Blocked by PID %s (%s)', blocking.pid, blocking.usename),
       left(blocked.query, 500)
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.pid <> pg_backend_pid()
  AND blocked.query_start < now() - interval '1 minute';

SELECT * FROM dba.governance_alert
WHERE alert_type = 'blocking_chain' AND alert_utc > now() - interval '24 hours'
ORDER BY alert_utc DESC;
