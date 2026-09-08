/*
================================================================================
08_Memory_Grant_and_Spill_Analysis.sql
Purpose : Correlate active/recent memory grants with spills and plan cache stats.
          Strong signal for CE 160 regressions (wrong estimates → hash/sort grants).
Requires: VIEW SERVER STATE
Safety  : Read-only
================================================================================
*/
SET NOCOUNT ON;

-- A) Currently executing / queued memory grants
SELECT
    mg.session_id,
    mg.request_id,
    mg.grant_time,
    mg.requested_memory_kb / 1024.0 AS requested_mb,
    mg.granted_memory_kb / 1024.0 AS granted_mb,
    mg.used_memory_kb / 1024.0 AS used_mb,
    mg.max_used_memory_kb / 1024.0 AS max_used_mb,
    mg.ideal_memory_kb / 1024.0 AS ideal_mb,
    mg.required_memory_kb / 1024.0 AS required_mb,
    mg.query_cost,
    mg.dop,
    mg.wait_time_ms,
    mg.wait_order,
    mg.is_next_candidate,
    mg.queue_id,
    DB_NAME(er.database_id) AS db_name,
    SUBSTRING(st.text, (er.statement_start_offset/2)+1,
        ((CASE er.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
          ELSE er.statement_end_offset END - er.statement_start_offset)/2)+1) AS statement_text,
    mg.plan_handle
FROM sys.dm_exec_query_memory_grants AS mg
LEFT JOIN sys.dm_exec_requests AS er
    ON er.session_id = mg.session_id AND er.request_id = mg.request_id
OUTER APPLY sys.dm_exec_sql_text(COALESCE(er.sql_handle, mg.sql_handle)) AS st
ORDER BY mg.granted_memory_kb DESC, mg.requested_memory_kb DESC;

-- B) Plan cache: top spillers + grant utilization
SELECT TOP (40)
    DB_NAME(st.dbid) AS db_name,
    OBJECT_NAME(st.objectid, st.dbid) AS object_name,
    qs.total_spills,
    qs.execution_count,
    qs.total_grant_kb / NULLIF(qs.execution_count,0) AS avg_grant_kb,
    qs.total_used_grant_kb / NULLIF(qs.execution_count,0) AS avg_used_grant_kb,
    CAST(qs.total_used_grant_kb * 100.0 / NULLIF(qs.total_grant_kb,0) AS decimal(8,2)) AS grant_util_pct,
    qs.total_elapsed_time / NULLIF(qs.execution_count,0) AS avg_elapsed_us,
    LEFT(SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1), 200) AS statement_preview
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE (qs.total_spills > 0
    OR qs.total_grant_kb / NULLIF(qs.execution_count,0) > 51200)  -- >50MB avg grant
  AND st.dbid = DB_ID()  -- remove filter for instance-wide
ORDER BY qs.total_spills DESC, avg_grant_kb DESC;

-- C) Query Store: high memory + duration (if ON)
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_query_store_on = 1)
BEGIN
    SELECT TOP (30)
        q.query_id,
        p.plan_id,
        rs.avg_query_max_used_memory / 1024.0 AS avg_max_used_memory_mb,
        rs.avg_duration / 1000.0 AS avg_ms,
        rs.count_executions,
        LEFT(qt.query_sql_text, 180) AS preview
    FROM sys.query_store_runtime_stats AS rs
    JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
    JOIN sys.query_store_query AS q ON q.query_id = p.query_id
    JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    ORDER BY rs.avg_query_max_used_memory DESC, rs.avg_duration DESC;
END

PRINT 'Interpretation: high grant + low utilization or spills → CE estimate issue or batch-mode hash join.';
