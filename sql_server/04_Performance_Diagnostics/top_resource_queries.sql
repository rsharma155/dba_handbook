/*
================================================================================
Purpose:        Identifies the top 20 statements consuming the most CPU, 
                physical/logical reads, or having the longest elapsed durations.
Provides:       Execution counts, total/avg CPU, logical reads, duration, 
                query text, and associated execution plan XML.
Importance:     Pinpoints the "heavy hitters" in the workload that offer the 
                highest return on investment for query tuning and optimization.
Interpretation: Focus on queries with high "Avg_Logical_Reads" or "Avg_CPU_ms". 
                 Correlate with wait statistics to understand the wait type.
Action: Copy the query text from the top-ranked queries and analyze the execution plan in SSMS. Look for: (1) missing index warnings (green text), (2) table scans on large tables, (3) implicit conversions, (4) key lookups. For queries with high Avg_CPU_ms, create recommended indexes and re-evaluate. For large batches, consider breaking into smaller operations or optimizing the worst-performing steps.
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

SELECT TOP (20)
    qs.execution_count AS [Execution_Count],
    qs.total_worker_time / 1000 AS [Total_CPU_ms],
    (qs.total_worker_time / qs.execution_count) / 1000 AS [Avg_CPU_ms],
    qs.total_logical_reads AS [Total_Logical_Reads],
    qs.total_logical_reads / qs.execution_count AS [Avg_Logical_Reads],
    qs.total_elapsed_time / 1000 AS [Total_Duration_ms],
    (qs.total_elapsed_time / qs.execution_count) / 1000 AS [Avg_Duration_ms],
    -- Extract the specific statement from the batch
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
         END - qs.statement_start_offset)/2) + 1) AS [Query_Text],
    qp.query_plan AS [Query_Plan_XML],
    CAST('Displays worst performing queries from SQL Server plan cache. ' + 
         'Threshold: Queries with Avg_Logical_Reads > 10,000 or Avg_CPU_ms > 500ms are candidates for optimization. ' +
         'Recommendation: Open Query_Plan_XML to locate clustered index scans or key lookups. Add missing indexes, reduce sorting operations, or verify parameter statistics.'
         AS VARCHAR(1000)) AS [Metric_Context]
FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
ORDER BY [Total_CPU_ms] DESC; -- Can change to total_logical_reads or total_elapsed_time depending on diagnostic focus
