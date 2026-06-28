/*
================================================================================
Alert Views — Dashboard views for governance monitoring
================================================================================
Description:
    Creates views summarizing recent governance alerts.

Prerequisite: preventive_measures/01_create_governance_schema.sql

Criticality: Low
================================================================================
*/

CREATE OR REPLACE VIEW dba.v_governance_alerts_24h AS
SELECT alert_type, severity, count(*) AS alert_count,
       max(alert_utc) AS last_alert
FROM dba.governance_alert
WHERE alert_utc > now() - interval '24 hours'
GROUP BY alert_type, severity
ORDER BY alert_count DESC;

CREATE OR REPLACE VIEW dba.v_governance_long_queries AS
SELECT alert_utc, database_name, pid, username, duration_sec, query_snippet
FROM dba.governance_alert
WHERE alert_type = 'long_running_query'
  AND alert_utc > now() - interval '24 hours'
ORDER BY duration_sec DESC;

GRANT SELECT ON dba.v_governance_alerts_24h TO PUBLIC;
GRANT SELECT ON dba.v_governance_long_queries TO PUBLIC;
