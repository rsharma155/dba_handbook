/*
================================================================================
Purpose:        High-level diagnostic analysis for advanced SQL Server internal 
                structures including TempDB, Buffer Pool, and Plan Cache.
Provides:       TempDB space breakdown, Buffer Pool residency per database, 
                and detection of potential parameter sniffing (multi-plan queries).
Importance:     Critical for identifying instance-wide resource bottlenecks 
                and query plan efficiency issues.
Interpretation: High TempDB version store suggests long transactions or RCSI. 
                Buffer Pool distribution shows which DBs dominate cache. 
                Multi-plan queries indicate parameter sniffing.
Action: For TempDB: if Version_Store_MB > 30% of total TempDB, investigate long-running transactions or read-committed snapshot isolation usage (RCSI). If Internal_Objects_MB is high, review large hash joins/sort spills. For Buffer Pool: if a small database dominates cache, investigate inefficient table scans via index_usage_efficiency.sql. For Multi-Plan queries (parameter sniffing candidates): review the query text and consider OPTION (RECOMPILE) or optimize for unknown pattern.
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-- 1. TempDB Space Usage Breakdown
PRINT '--- TempDB Space Usage Deep-Dive ---';
SELECT
    SUM(user_object_reserved_page_count) * 8 / 1024 AS [User_Objects_MB],
    SUM(internal_object_reserved_page_count) * 8 / 1024 AS [Internal_Objects_MB],
    SUM(version_store_reserved_page_count) * 8 / 1024 AS [Version_Store_MB],
    SUM(unallocated_extent_page_count) * 8 / 1024 AS [Free_Space_MB],
    CAST('Breakdown of what is consuming space in TempDB. ' +
         'Expert Note: High Version Store suggests RCSI or long-running transactions. High Internal Objects suggests massive hash joins/sorts spills.'
         AS VARCHAR(1000)) AS [Analysis]
FROM sys.dm_db_file_space_usage;

-- 2. Buffer Pool residency per Database
PRINT '--- Buffer Pool Distribution per Database ---';
SELECT 
    (CASE WHEN ([database_id] = 32767) THEN 'Resource Database' ELSE DB_NAME([database_id]) END) AS [Database_Name],
    COUNT(*) * 8 / 1024 AS [Cached_MB],
    CAST('Shows how much of the SQL Server memory (Buffer Pool) is dedicated to each database. ' +
         'Expert Note: If a small database is consuming most of the cache, it may have inefficient scans.'
         AS VARCHAR(1000)) AS [Analysis]
FROM sys.dm_os_buffer_descriptors
GROUP BY [database_id]
ORDER BY [Cached_MB] DESC;

-- 3. Parameter Sniffing / Multi-Plan Detection
PRINT '--- Potential Parameter Sniffing Candidates (Multi-Plan Batch) ---';
SELECT TOP 20
    st.text AS [Query_Text],
    COUNT(DISTINCT CAST(qp.query_plan AS NVARCHAR(MAX))) AS [Plan_Count],
    SUM(qs.execution_count) AS [Total_Executions],
    MAX(qs.max_elapsed_time) / 1000 AS [Max_Duration_ms],
    MIN(qs.min_elapsed_time) / 1000 AS [Min_Duration_ms],
    CAST('Queries with multiple execution plans for the same text. ' +
         'Expert Note: A high plan count with vast duration differences (Max vs Min) is a strong indicator of parameter sniffing.'
         AS VARCHAR(1000)) AS [Analysis]
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
GROUP BY st.text
HAVING COUNT(DISTINCT CAST(qp.query_plan AS NVARCHAR(MAX))) > 1
ORDER BY [Plan_Count] DESC;
