/*
================================================================================
07_Parameter_Sensitive_Query_Detector.sql
Purpose : Find procedures / ad-hoc batches with multiple plans or highly variable
          runtimes (parameter sniffing / PSP candidates after CL 160).
Requires: VIEW SERVER STATE
Safety  : Read-only
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

-- A) Plan cache: same query_hash, multiple plan_hash (classic sniffing signal)
SELECT
    qs.query_hash,
    COUNT(DISTINCT qs.plan_handle) AS plan_count,
    COUNT(DISTINCT qs.query_plan_hash) AS distinct_plan_hashes,
    SUM(qs.execution_count) AS total_execs,
    MIN(qs.total_elapsed_time / NULLIF(qs.execution_count,0)) AS min_avg_elapsed_us,
    MAX(qs.total_elapsed_time / NULLIF(qs.execution_count,0)) AS max_avg_elapsed_us,
    CAST(
        MAX(qs.total_elapsed_time * 1.0 / NULLIF(qs.execution_count,0))
        / NULLIF(MIN(qs.total_elapsed_time * 1.0 / NULLIF(qs.execution_count,0)),0)
        AS decimal(12,2)) AS elapsed_variance_ratio,
    OBJECT_SCHEMA_NAME(st.objectid, st.dbid) AS schema_name,
    OBJECT_NAME(st.objectid, st.dbid) AS object_name,
    LEFT(MIN(st.text), 220) AS sample_text
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE st.dbid = DB_ID()
GROUP BY qs.query_hash, st.objectid, st.dbid
HAVING COUNT(DISTINCT qs.query_plan_hash) > 1
   AND SUM(qs.execution_count) >= 10
   AND MAX(qs.total_elapsed_time / NULLIF(qs.execution_count,0))
       > MIN(qs.total_elapsed_time / NULLIF(qs.execution_count,0)) * 3
ORDER BY elapsed_variance_ratio DESC, total_execs DESC;

-- B) Query Store: multiple plans per query_id with wide duration spread
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_query_store_on = 1)
BEGIN
    ;WITH PlanStats AS (
        SELECT
            q.query_id,
            p.plan_id,
            SUM(rs.count_executions) AS execs,
            SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions),0) AS avg_duration_us
        FROM sys.query_store_query AS q
        JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
        JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
        JOIN sys.query_store_runtime_stats_interval AS i
            ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
        WHERE i.start_time >= DATEADD(DAY, -14, GETUTCDATE())
        GROUP BY q.query_id, p.plan_id
    ),
    QuerySpread AS (
        SELECT
            query_id,
            COUNT(*) AS plan_count,
            MIN(avg_duration_us) AS min_avg_us,
            MAX(avg_duration_us) AS max_avg_us,
            SUM(execs) AS total_execs
        FROM PlanStats
        GROUP BY query_id
        HAVING COUNT(*) > 1
    )
    SELECT TOP (40)
        qs.query_id,
        qs.plan_count,
        qs.min_avg_us / 1000.0 AS min_avg_ms,
        qs.max_avg_us / 1000.0 AS max_avg_ms,
        CAST(qs.max_avg_us / NULLIF(qs.min_avg_us,0) AS decimal(12,2)) AS duration_ratio,
        qs.total_execs,
        LEFT(qt.query_sql_text, 220) AS query_preview
    FROM QuerySpread AS qs
    JOIN sys.query_store_query AS q ON q.query_id = qs.query_id
    JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    WHERE qs.max_avg_us > qs.min_avg_us * 2
    ORDER BY duration_ratio DESC;
END
ELSE
    PRINT 'Query Store is OFF — enable for richer PSP / sniffing history.';

/*
NEXT STEPS
- Test OPTION (RECOMPILE) on suspect proc in UAT
- Check PSP: multiple plan variants in QS after CL 160
- Consider OPTIMIZE FOR / Query Store hints only after confirming sniffing
*/
