/*
================================================================================
Statement Timeout Policy — Recommended role/database settings
================================================================================
Description:
    Documents and checks statement_timeout and idle_in_transaction_session_timeout.

Action:  ALTER DATABASE ... SET statement_timeout = '30s'; (adjust per workload)

Criticality: Medium
================================================================================
*/

SELECT name, setting, unit,
       CASE name
           WHEN 'statement_timeout' THEN
               CASE WHEN setting = '0' THEN 'RECOMMENDED: Set non-zero statement_timeout in production' END
           WHEN 'idle_in_transaction_session_timeout' THEN
               CASE WHEN setting = '0' THEN 'RECOMMENDED: Set idle_in_transaction_session_timeout' END
       END AS policy_note
FROM pg_settings
WHERE name IN ('statement_timeout', 'lock_timeout', 'idle_in_transaction_session_timeout');

-- Example (review before running):
-- ALTER DATABASE mydb SET statement_timeout = '60s';
-- ALTER DATABASE mydb SET idle_in_transaction_session_timeout = '5min';
