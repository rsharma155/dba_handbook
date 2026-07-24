/*
================================================================================
03_Force_Last_Good_Plan.sql
Purpose : Force a previously good plan for a regressed query_id.
Safety  : Document owner + review date. Forced plans are technical debt.
================================================================================
*/
USE [YourDB]; -- <<< change
GO

DECLARE @query_id bigint = 123;   -- <<< from regression report
DECLARE @plan_id  bigint = 456;   -- <<< last good plan_id

-- Inspect candidates
SELECT
    p.plan_id,
    p.is_forced_plan,
    p.last_execution_time,
    rs.avg_duration / 1000.0 AS avg_ms,
    rs.count_executions,
    CAST(p.query_plan AS xml) AS plan_xml
FROM sys.query_store_plan p
LEFT JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
WHERE p.query_id = @query_id
ORDER BY rs.avg_duration ASC;

-- Force
EXEC sys.sp_query_store_force_plan @query_id = @query_id, @plan_id = @plan_id;

-- Verify
SELECT query_id, plan_id, is_forced_plan, force_failure_count, last_force_failure_reason_desc
FROM sys.query_store_plan
WHERE query_id = @query_id;

/*
UNFORCE when rewrite is done:
EXEC sys.sp_query_store_unforce_plan @query_id = @query_id, @plan_id = @plan_id;

If force fails repeatedly (statistics changed / plan invalid):
- Update stats
- Or use USE HINT / query rewrite instead of force
*/

-- Audit all forced plans
SELECT q.query_id, p.plan_id, p.force_failure_count, p.last_force_failure_reason_desc,
       qt.query_sql_text
FROM sys.query_store_plan p
JOIN sys.query_store_query q ON q.query_id = p.query_id
JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
WHERE p.is_forced_plan = 1
ORDER BY q.query_id;
