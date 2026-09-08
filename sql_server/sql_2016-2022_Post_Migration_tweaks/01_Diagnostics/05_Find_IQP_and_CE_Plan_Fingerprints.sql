/*
================================================================================
05_Find_IQP_and_CE_Plan_Fingerprints.sql
Purpose : Flag plans showing Legacy CE, UDF inlining, batch mode, spills, MGF.
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

SELECT TOP (40)
    q.query_id,
    p.plan_id,
    rs.avg_duration / 1000.0 AS avg_ms,
    rs.avg_cpu_time / 1000.0 AS avg_cpu_ms,
    rs.avg_memory_grant_kb,
    rs.avg_used_memory_grant_kb,
    rs.avg_spills,
    rs.count_executions,
    CASE
        WHEN CAST(p.query_plan AS nvarchar(max)) LIKE N'%LegacyCardinalityEstimation="true"%'
          OR CAST(p.query_plan AS nvarchar(max)) LIKE N'%LegacyCardinalityEstimation="1"%'
            THEN N'Legacy CE'
        ELSE N'Default CE'
    END AS ce_mode,
    CASE
        WHEN CAST(p.query_plan AS nvarchar(max)) LIKE N'%IsInlined="true"%'
          OR CAST(p.query_plan AS nvarchar(max)) LIKE N'%IsInlined="1"%'
            THEN N'UDF inlined'
        ELSE N'-'
    END AS udf_inline,
    CASE
        WHEN CAST(p.query_plan AS nvarchar(max)) LIKE N'%BatchMode="true"%'
          OR CAST(p.query_plan AS nvarchar(max)) LIKE N'%EstimatedExecutionMode="Batch"%'
            THEN N'Batch'
        ELSE N'Row'
    END AS exec_mode,
    LEFT(qt.query_sql_text, 160) AS preview
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval i
    ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE i.start_time >= DATEADD(DAY, -7, GETUTCDATE())
ORDER BY rs.avg_duration DESC;
GO
