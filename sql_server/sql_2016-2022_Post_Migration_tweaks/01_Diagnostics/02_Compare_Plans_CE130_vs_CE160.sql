/*
================================================================================
02_Compare_Plans_CE130_vs_CE160.sql
Purpose : Side-by-side estimate/actual plan comparison for a suspect query
          under legacy CE vs modern CE (compat 160 behavior).
How     : Paste the problem statement into @sql. Run in the user database.
Notes   : Uses query-level hints so you need NOT change DB compatibility to test.
          Review SET STATISTICS IO/TIME and the graphical/XML plans in SSMS.
================================================================================
*/
USE [YourDB];  -- <<< change
GO
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

DECLARE @sql nvarchar(max) = N'
-- PASTE the slow statement / proc body HERE (single batch). Example:
SELECT TOP (100) *
FROM dbo.YourTable AS t
WHERE t.SomeDate >= @d
ORDER BY t.Id
';

DECLARE @sqlExec nvarchar(max);
DECLARE @d date = DATEADD(DAY, -30, CAST(GETDATE() AS date));  -- sample params

PRINT '========== A) FORCE LEGACY CE (2016-like estimates) ==========';
SET @sqlExec = @sql + N' OPTION (RECOMPILE, USE HINT(''FORCE_LEGACY_CARDINALITY_ESTIMATION''));';
EXEC sp_executesql @stmt = @sqlExec, @params = N'@d date', @d = @d;

PRINT '========== B) DEFAULT / MODERN CE (160-like) ==========';
SET @sqlExec = @sql + N' OPTION (RECOMPILE);';
EXEC sp_executesql @stmt = @sqlExec, @params = N'@d date', @d = @d;

PRINT '========== C) OPTIONAL: DISABLE ROW GOAL (sometimes helps TOP/EXISTS) ==========';
SET @sqlExec = @sql + N' OPTION (RECOMPILE, USE HINT(''DISABLE_OPTIMIZER_ROWGOAL''));';
EXEC sp_executesql @stmt = @sqlExec, @params = N'@d date', @d = @d;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/*
WHAT TO COMPARE IN THE PLAN
- Estimated rows vs actual rows (biggest CE failures)
- Join type change (NL vs Hash vs Merge)
- Memory grant / spill to tempdb (thick warnings)
- Parallelism (Degree of Parallelism) changes
- Implicit conversion warnings
- Key Lookup percentage

NEXT STEPS
- If Legacy CE is fast -> use DB scoped LEGACY_CE temporarily OR fix estimates (stats/rewrite)
- If only parameter sets are bad -> sniffing / PSP / OPTIMIZE FOR
*/
GO

/*
================================================================================
Bonus: Capture live plan handles for a running session / known query text
================================================================================
*/
-- Find plans by query text fragment
SELECT TOP (20)
    qs.total_elapsed_time / NULLIF(qs.execution_count,0) AS avg_elapsed_us,
    qs.total_worker_time / NULLIF(qs.execution_count,0)  AS avg_cpu_us,
    qs.execution_count,
    qs.total_logical_reads / NULLIF(qs.execution_count,0) AS avg_reads,
    DB_NAME(st.dbid) AS db_name,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS statement_text,
    qp.query_plan,
    qs.plan_handle
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE st.text LIKE N'%YourTable%'   -- <<< change
ORDER BY avg_elapsed_us DESC;
