/*
================================================================================
Database Growth Forecast — Size trends from statistics
================================================================================
Description:
    Current database/table sizes with dead tuple growth indicators.
    For true trending, schedule dba.sp_baseline_capture() or use monitoring tools.

Action:  Plan disk expansion when largest DB growth rate exceeds capacity runway.

Criticality: Medium
================================================================================
*/

SELECT datname,
       pg_size_pretty(pg_database_size(datname)) AS current_size,
       pg_database_size(datname) AS size_bytes,
       (SELECT sum(n_tup_ins + n_tup_upd + n_tup_del) FROM pg_stat_user_tables) AS cluster_write_activity
FROM pg_database
WHERE datallowconn AND datname NOT IN ('template0', 'template1')
ORDER BY pg_database_size(datname) DESC;

SELECT date_trunc('day', now()) AS forecast_note,
       'Capture daily pg_database_size via monitoring for linear growth forecast' AS method;
