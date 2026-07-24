/*
================================================================================
04_Find_Implicit_Conversions_and_Warnings.sql
Purpose : Surface plan warnings that often get worse under CE 160.
Requires: Query Store ON (preferred) OR plan cache XML (heavier).
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

-- A) Query Store: plans containing Convert / Implicit conversion warnings in XML
SELECT TOP (50)
    q.query_id,
    qt.query_sql_text,
    p.plan_id,
    rs.avg_duration / 1000.0 AS avg_duration_ms,
    rs.avg_cpu_time / 1000.0 AS avg_cpu_ms,
    rs.count_executions,
    CAST(p.query_plan AS xml) AS query_plan_xml
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi
    ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(DAY, -7, GETUTCDATE())
  AND (
        CAST(p.query_plan AS nvarchar(max)) LIKE N'%Implicit Convert%'
     OR CAST(p.query_plan AS nvarchar(max)) LIKE N'%Convert Issue%'
     OR CAST(p.query_plan AS nvarchar(max)) LIKE N'%CardinalityEstimate%'
     OR CAST(p.query_plan AS nvarchar(max)) LIKE N'%SpillToTempDb%'
     OR CAST(p.query_plan AS nvarchar(max)) LIKE N'%ColumnsWithNoStatistics%'
  )
ORDER BY rs.avg_duration DESC;

-- B) Quick schema smell: nvarchar vs varchar join/filter mismatch candidates
SELECT
    t.name AS table_name,
    c.name AS column_name,
    ty.name AS data_type,
    c.max_length,
    c.collation_name
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE ty.name IN (N'varchar', N'nvarchar', N'char', N'nchar')
ORDER BY t.name, c.column_id;
