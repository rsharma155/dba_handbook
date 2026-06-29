/*
================================================================================
Compatibility Level and Cardinality Estimator Impact
================================================================================
Purpose:
    After upgrading the SQL Server ENGINE (2019 → 2025), databases often remain
    at compatibility level 150. The optimizer behavior depends on BOTH engine
    version AND database compatibility_level.

    Misunderstanding this leads to "I tried RECOMPILE and hints but nothing
    worked" when the real issue is waits — but when CE/plan IS the issue,
    this script identifies it.

Checks:
    (1) Compat level per database vs instance default
    (2) Queries with multiple plans (plan instability)
    (3) Legacy CE test instructions (QUERYTRACEON 9481 / USE HINT)

Cardinality Estimator versions:
    CE 70  — SQL 2008-2014 compat
    CE 120 — SQL 2014 compat
    CE 150 — SQL 2017+ compat (default for 150+)

Test procedure (non-prod first):
    -- Force legacy CE on ONE statement:
    SELECT ... FROM ... OPTION (USE HINT ('FORCE_LEGACY_CARDINALITY_ESTIMATION'));

    -- Or trace flag 9481 at query level (older method):
    -- QUERYTRACEON 9481

If legacy CE fixes performance AND waits are low:
    Consider database scoped configuration LEGACY_CARDINALITY_ESTIMATION = ON
    OR update statistics with FULLSCAN and test compat upgrade

If legacy CE does NOT help:
    Problem is NOT CE — return to wait analysis.

Next action:
    06_Optimizer_Plans/03_query_store_regression.sql
    07_Instance_Config/02_recommended_fixes_with_rollback.sql (compat change)

Criticality: Medium-High
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @InstanceCompat INT =
    COALESCE(CAST(SERVERPROPERTY(N'ProductMajorVersion') AS INT), 16) * 10;

PRINT '=== COMPATIBILITY MATRIX ===';
SELECT
    d.name AS [Database_Name],
    d.compatibility_level AS [Current_Compat],
    @InstanceCompat AS [Instance_Max_Compat],
    CASE d.compatibility_level
        WHEN 150 THEN N'CE 150 (2017+) — typical after 2019 Express migration'
        WHEN 160 THEN N'CE 160 (2022) — new estimator features'
        WHEN 170 THEN N'CE 170 (2025) — latest'
        ELSE N'Legacy — review before changing'
    END AS [CE_Version],
    CASE
        WHEN d.compatibility_level < @InstanceCompat THEN N'Test upgrade in lower environment; capture plans before/after'
        ELSE N'At or above typical post-migration level'
    END AS [Recommendation]
FROM sys.databases AS d
WHERE d.database_id > 4 AND d.state = 0;

PRINT '=== DATABASE SCOPED CONFIG (CE overrides) ===';
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql = @sql + N'
SELECT ''' + REPLACE(name, '''', '''''') + N''' AS [Database],
       name AS [DSC_Name], value AS [DSC_Value], value_for_secondary AS [Secondary_Value]
FROM ' + QUOTENAME(name) + N'.sys.database_scoped_configurations
WHERE name IN (N''LEGACY_CARDINALITY_ESTIMATION'', N''OPTIMIZE_FOR_AD_HOC_WORKLOADS'', N''MAXDOP'', N''PARAMETER_SNIFFING'');
'
FROM sys.databases
WHERE database_id > 4 AND state = 0;

EXEC sys.sp_executesql @sql;

PRINT '=== PLAN INSTABILITY (multiple plans per query hash in cache) ===';
;WITH PlanInstability AS (
    SELECT
        DB_NAME(st.dbid) AS [Database_Name],
        qs.query_hash,
        COUNT(DISTINCT qs.plan_handle) AS [Distinct_Plans],
        SUM(qs.execution_count) AS [Total_Executions],
        SUM(qs.total_elapsed_time) / 1000.0 AS [Total_Elapsed_Sec],
        MIN(qs.total_elapsed_time * 1.0 / NULLIF(qs.execution_count, 0)) / 1000.0 AS [Min_Avg_Elapsed_Sec],
        MAX(qs.total_elapsed_time * 1.0 / NULLIF(qs.execution_count, 0)) / 1000.0 AS [Max_Avg_Elapsed_Sec],
        SUBSTRING(MIN(CAST(st.text AS NVARCHAR(MAX))), 1, 120) AS [Query_Sample]
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
    WHERE st.dbid IS NOT NULL
    GROUP BY DB_NAME(st.dbid), qs.query_hash
    HAVING COUNT(DISTINCT qs.plan_handle) > 1
)
SELECT TOP (20)
    Database_Name,
    query_hash,
    Distinct_Plans,
    Total_Executions,
    Total_Elapsed_Sec,
    Min_Avg_Elapsed_Sec,
    Max_Avg_Elapsed_Sec,
    Query_Sample
FROM PlanInstability
ORDER BY Max_Avg_Elapsed_Sec / NULLIF(Min_Avg_Elapsed_Sec, 0) DESC;

PRINT '=== WHEN CE TEST IS WORTH IT vs WHEN TO STOP ===';
SELECT
    N'Run CE test ONLY if: CPU or logical reads are HIGH and waits are low.' AS [Rule_1],
    N'Skip CE test if: elapsed >> CPU and session wait_type is LCK/LATCH/IO — hints will not help.' AS [Rule_2],
    N'Post-migration: update statistics WITH FULLSCAN on critical tables before compat change.' AS [Rule_3];
