/*
================================================================================
Query Regression — Mean time increase detection
================================================================================
Description:
    Identifies queries with high execution time variance (proxy for regression).
    Compare snapshots over time using pg_stat_statements export for true regression.

Prerequisite: pg_stat_statements

Criticality: High
================================================================================
*/

SELECT calls,
       round(min_exec_time::numeric, 2) AS min_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       round(max_exec_time::numeric, 2) AS max_ms,
       round((max_exec_time / nullif(mean_exec_time, 0))::numeric, 2) AS max_to_mean_ratio,
       left(query, 200) AS query_snippet
FROM pg_stat_statements
WHERE calls > 20 AND mean_exec_time > 50
ORDER BY max_exec_time / nullif(mean_exec_time, 0) DESC NULLS LAST
LIMIT 20;
