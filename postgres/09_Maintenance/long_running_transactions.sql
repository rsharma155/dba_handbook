/*
================================================================================
Long Running Transactions — XID age and open transaction risk
================================================================================
Description:
    Flags long-running transactions and idle-in-transaction sessions.

Action:  Terminate only after app owner approval; fix app transaction handling.

Criticality: High
================================================================================
*/

SELECT pid, usename, datname, state,
       xact_start, query_start,
       round(extract(epoch FROM (now() - xact_start))::numeric, 1) AS xact_age_sec,
       age(backend_xid) AS xid_age,
       age(backend_xmin) AS xmin_age,
       left(query, 120) AS query_snippet
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND pid <> pg_backend_pid()
  AND state IN ('active', 'idle in transaction')
ORDER BY xact_start
LIMIT 25;
