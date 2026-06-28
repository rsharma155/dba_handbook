/*
================================================================================
Purpose:        Parses the XML execution plan cache to identify key lookups 
                (non-covering indexes) and implicit conversions (SARGability).
Provides:       Top 20 queries with Key Lookups and top 20 queries with Implicit 
                Conversions, including execution counts and XML query plans.
Importance:     Essential for identifying hidden performance killers that waste 
                CPU and I/O due to data type mismatches or suboptimal indexing.
Interpretation: High "Avg_CPU_ms" for these queries indicates high-impact 
                 optimization opportunities. Check Plan_XML for the specific nodes.
Action: For Key Lookup queries (first result set), create a covering nonclustered index that includes all columns from the SELECT and WHERE clauses to eliminate the lookup. For Implicit Conversion queries (second result set), fix the data type mismatch — typically the application is passing a string (NVARCHAR) to an INT or DATETIME column, or the join columns have mismatched types. Use the Plan_XML column to identify the specific node.
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-- 1. Find Top 20 Queries with Key Lookups
PRINT 'Searching for Key Lookups in Plan Cache...';
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT TOP 20
    qs.execution_count,
    qs.total_worker_time / 1000 AS [Total_CPU_ms],
    (qs.total_worker_time / qs.execution_count) / 1000 AS [Avg_CPU_ms],
    st.text AS [Parent_Query],
    qp.query_plan AS [Plan_XML]
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE qp.query_plan.exist('//IndexLookUp') = 1
ORDER BY qs.total_worker_time DESC;

-- 2. Find Queries with Implicit Conversions (Plan Bloat / SARGability issues)
PRINT 'Searching for Implicit Conversions in Plan Cache...';
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT TOP 20
    qs.execution_count,
    st.text AS [Query_Text],
    qp.query_plan AS [Plan_XML]
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE qp.query_plan.exist('//ScalarOperator[contains(@ScalarString, "CONVERT_IMPLICIT")]') = 1
ORDER BY qs.total_worker_time DESC;
