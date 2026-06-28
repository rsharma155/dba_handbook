/*
================================================================================
Capture Long Queries — Snapshot for policy enforcement
================================================================================
Description:
    Inserts active queries exceeding threshold into dba.governance_alert.

Prerequisite: preventive_measures/01_create_governance_schema.sql

Criticality: Medium
================================================================================
*/

INSERT INTO dba.governance_alert (alert_type, severity, database_name, pid, username, duration_sec, query_snippet)
SELECT 'long_running_query',
       CASE WHEN extract(epoch FROM (now() - query_start)) > 600 THEN 'CRITICAL' ELSE 'WARNING' END,
       datname, pid, usename,
       round(extract(epoch FROM (now() - query_start))::numeric, 1),
       left(query, 500)
FROM pg_stat_activity
WHERE state = 'active'
  AND pid <> pg_backend_pid()
  AND query_start < now() - interval '5 minutes'
  AND query NOT LIKE '%governance_alert%';

SELECT alert_utc, severity, database_name, pid, duration_sec, left(query_snippet, 80)
FROM dba.governance_alert
WHERE alert_utc > now() - interval '24 hours'
ORDER BY alert_utc DESC
LIMIT 50;
