/*
================================================================================
Connection Settings — Limits, timeouts, and pooling readiness
================================================================================
Description:
    Reviews connection limits, timeout settings, and current connection breakdown.

Action:  Enable idle_in_transaction_session_timeout and statement_timeout in production.
         Use connection pooling when max_connections is stressed.

Criticality: Medium
================================================================================
*/

SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name IN (
    'max_connections', 'superuser_reserved_connections',
    'statement_timeout', 'lock_timeout', 'idle_in_transaction_session_timeout',
    'tcp_keepalives_idle', 'tcp_keepalives_interval'
)
ORDER BY name;

SELECT datname, numbackends, datconnlimit,
       CASE WHEN datconnlimit = -1 THEN 'unlimited' ELSE datconnlimit::text END AS conn_limit
FROM pg_stat_database d
JOIN pg_database db ON db.datname = d.datname
WHERE d.datname NOT IN ('template0', 'template1')
ORDER BY numbackends DESC;

SELECT application_name, usename, client_addr, state, count(*) AS sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY application_name, usename, client_addr, state
ORDER BY sessions DESC
LIMIT 20;
