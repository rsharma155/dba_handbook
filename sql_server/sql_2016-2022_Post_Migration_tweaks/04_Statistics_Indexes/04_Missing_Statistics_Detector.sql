/*
================================================================================
04_Missing_Statistics_Detector.sql
Purpose : Find columns referenced in plans with ColumnsWithNoStatistics warnings,
          plus heuristic: filter/join columns without stats on user tables.
Requires: Query Store ON (section A) or plan cache (section B)
Safety  : Read-only
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

-- A) Query Store plans with ColumnsWithNoStatistics warning
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_query_store_on = 1)
BEGIN
    SELECT TOP (50)
        q.query_id,
        p.plan_id,
        rs.avg_duration / 1000.0 AS avg_ms,
        rs.count_executions,
        LEFT(qt.query_sql_text, 200) AS query_preview,
        CAST(p.query_plan AS xml) AS plan_xml
    FROM sys.query_store_query AS q
    JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    WHERE CAST(p.query_plan AS nvarchar(max)) LIKE N'%ColumnsWithNoStatistics%'
    ORDER BY rs.avg_duration DESC;
END

-- B) Plan cache — same warning
SELECT TOP (30)
    qs.total_elapsed_time / NULLIF(qs.execution_count,0) AS avg_elapsed_us,
    OBJECT_NAME(st.objectid, st.dbid) AS object_name,
    LEFT(SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1), 200) AS statement_preview,
    qp.query_plan
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE st.dbid = DB_ID()
  AND CAST(qp.query_plan AS nvarchar(max)) LIKE N'%ColumnsWithNoStatistics%'
ORDER BY avg_elapsed_us DESC;

-- C) Heuristic: index key columns without dedicated stats (beyond auto single-column)
SELECT
    OBJECT_SCHEMA_NAME(i.object_id) AS schema_name,
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    c.name AS column_name,
    N'Consider CREATE STATISTICS on filter/join column' AS suggestion
FROM sys.indexes AS i
JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.type > 0
  AND OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
  AND ic.is_included_column = 0
  AND ic.key_ordinal > 1
  AND NOT EXISTS (
      SELECT 1 FROM sys.stats_columns sc
      WHERE sc.object_id = i.object_id AND sc.column_id = c.column_id AND sc.stats_column_id = 1
  )
ORDER BY table_name, index_name, ic.key_ordinal;

/*
REMEDIATION (after validation)
CREATE STATISTICS [stat_Table_Col] ON dbo.TableName (ColumnName) WITH FULLSCAN;
-- or UPDATE STATISTICS on parent table
*/
