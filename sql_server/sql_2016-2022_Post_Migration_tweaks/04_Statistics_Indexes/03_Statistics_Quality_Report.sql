/*
================================================================================
03_Statistics_Quality_Report.sql
Purpose : Histogram depth, sample rate, last update, modification counters.
          Validate statistics quality before blaming CE / applying hints.
Requires: VIEW DATABASE STATE
Safety  : Read-only
================================================================================
*/
USE [YourDB]; -- <<< change
GO
SET NOCOUNT ON;

SELECT TOP (150)
    OBJECT_SCHEMA_NAME(s.object_id) AS schema_name,
    OBJECT_NAME(s.object_id) AS table_name,
    s.name AS stats_name,
    s.stats_id,
    STATS_DATE(s.object_id, s.stats_id) AS last_updated,
    sp.rows,
    sp.rows_sampled,
    CASE WHEN sp.rows > 0
         THEN CAST(sp.rows_sampled * 100.0 / sp.rows AS decimal(8,2))
         ELSE 0 END AS sample_pct,
    sp.modification_counter,
    CASE WHEN sp.rows > 0
         THEN CAST(sp.modification_counter * 100.0 / sp.rows AS decimal(8,2))
         ELSE 0 END AS pct_modified_since_update,
    (SELECT COUNT(*) FROM sys.dm_db_stats_histogram(s.object_id, s.stats_id)) AS histogram_steps,
    CASE
        WHEN sp.rows_sampled = sp.rows THEN N'FULLSCAN (likely)'
        WHEN sp.rows > 0 AND sp.rows_sampled * 100.0 / sp.rows < 5 THEN N'LOW SAMPLE'
        ELSE N'SAMPLED'
    END AS update_quality,
    CASE
        WHEN sp.modification_counter > sp.rows * 0.20 THEN N'HIGH churn — update stats'
        WHEN STATS_DATE(s.object_id, s.stats_id) < DATEADD(DAY, -30, GETDATE()) THEN N'STALE date'
        ELSE N'OK'
    END AS recommendation
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
ORDER BY sp.modification_counter DESC, last_updated ASC;

-- Leading column of each stat (for targeted FULLSCAN)
SELECT TOP (80)
    OBJECT_SCHEMA_NAME(sc.object_id) + '.' + OBJECT_NAME(sc.object_id) AS table_name,
    s.name AS stats_name,
    c.name AS leading_column,
    STATS_DATE(s.object_id, s.stats_id) AS last_updated,
    sp.modification_counter
FROM sys.stats AS s
JOIN sys.stats_columns AS sc ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id AND sc.stats_column_id = 1
JOIN sys.columns AS c ON c.object_id = sc.object_id AND c.column_id = sc.column_id
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
  AND sp.modification_counter > 5000
ORDER BY sp.modification_counter DESC;
