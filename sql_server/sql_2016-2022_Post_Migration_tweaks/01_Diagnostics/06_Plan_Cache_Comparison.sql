/*
================================================================================
06_Plan_Cache_Comparison.sql
Purpose : Compare cached plans for the same query text / object before and after
          a compatibility level change (or after CLEAR PROCEDURE CACHE on one side).
Use     : Run snapshot A at CL 130 (or export results), flip to CL 160, run again.
          Compare plan_hash, operators, memory grant, and avg elapsed.
Requires: VIEW DATABASE STATE (plan cache DMVs)
Safety  : Read-only
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

DECLARE @TopN int = 50;
DECLARE @TextFilter nvarchar(200) = N'%';  -- e.g. N'%Orders%' to narrow

;WITH PlanCache AS (
    SELECT
        qs.plan_handle,
        qs.sql_handle,
        qs.query_hash,
        qs.query_plan_hash,
        qs.execution_count,
        qs.total_worker_time,
        qs.total_elapsed_time,
        qs.total_logical_reads,
        qs.total_grant_kb,
        qs.total_used_grant_kb,
        qs.total_spills,
        qs.min_grant_kb,
        qs.max_grant_kb,
        DB_NAME(st.dbid) AS db_name,
        OBJECT_SCHEMA_NAME(st.objectid, st.dbid) AS schema_name,
        OBJECT_NAME(st.objectid, st.dbid) AS object_name,
        SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
            ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
              ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS statement_text,
        qp.query_plan,
        CAST(qp.query_plan AS nvarchar(max)) AS plan_xml
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
    CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
    WHERE st.dbid = DB_ID()
      AND st.text NOT LIKE N'%sys.dm_exec_query_stats%'
)
SELECT TOP (@TopN)
    pc.db_name,
    pc.schema_name,
    pc.object_name,
    pc.query_hash,
    pc.query_plan_hash,
    pc.execution_count,
    pc.total_elapsed_time / NULLIF(pc.execution_count,0) AS avg_elapsed_us,
    pc.total_worker_time / NULLIF(pc.execution_count,0) AS avg_cpu_us,
    pc.total_logical_reads / NULLIF(pc.execution_count,0) AS avg_logical_reads,
    pc.total_grant_kb / NULLIF(pc.execution_count,0) AS avg_grant_kb,
    pc.total_used_grant_kb / NULLIF(pc.execution_count,0) AS avg_used_grant_kb,
    pc.total_spills,
    CASE
        WHEN pc.plan_xml LIKE N'%LegacyCardinalityEstimation="true"%'
          OR pc.plan_xml LIKE N'%LegacyCardinalityEstimation="1"%' THEN N'Legacy CE'
        WHEN pc.plan_xml LIKE N'%CardinalityEstimationModel="130"%' THEN N'CE 130'
        WHEN pc.plan_xml LIKE N'%CardinalityEstimationModel="160"%' THEN N'CE 160'
        ELSE N'Default'
    END AS ce_hint_in_plan,
    CASE
        WHEN pc.plan_xml LIKE N'%BatchMode="true"%' THEN N'Batch'
        ELSE N'Row'
    END AS exec_mode,
    LEFT(pc.statement_text, 200) AS statement_preview,
    pc.plan_handle
FROM PlanCache AS pc
WHERE pc.statement_text LIKE @TextFilter
ORDER BY pc.total_elapsed_time DESC;

/*
WORKFLOW
1) Save result set as "PlanCache_CL130.csv" before compat flip.
2) ALTER DATABASE ... SET COMPATIBILITY_LEVEL = 160;
3) ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
4) Run representative workload; re-run this script → "PlanCache_CL160.csv".
5) Join on query_hash (or object_name + statement hash) and diff plan_hash, avg_elapsed, spills.

Optional: export plan XML for one plan_handle
SELECT CAST(query_plan AS xml) FROM sys.dm_exec_query_plan(0xYOURPLANHANDLE);
*/
