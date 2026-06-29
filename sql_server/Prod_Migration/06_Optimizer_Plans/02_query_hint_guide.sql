/*
================================================================================
Query Hints Reference — When They Work and When They Fail
================================================================================
Purpose:
    Documents industry-standard query hints for post-migration tuning AND
    explicitly lists why each hint FAILS for wait-bound queries (your scenario).

Your tested hints:
    OPTION (MAXDOP 1)     — limits parallel threads; fails on blocking/IO/latches
    OPTION (RECOMPILE)    — new plan each execution; fails on lock waits
    SET ARITHABORT ON     — plan cache key alignment; fails on non-compilation waits
    OPTION (FORCE ORDER)  — join order; fails when query never gets to execution

Use this script as a template — replace @SampleQuery with your problem query.

Criticality: High — prevents wasted time on wrong tooling
================================================================================
*/

SET NOCOUNT ON;

PRINT '=== DECISION: HINT vs WAIT ANALYSIS ===';
SELECT
    Scenario,
    Use_Hints,
    Primary_Tool
FROM (VALUES
    (N'High elapsed, LOW cpu, LOW reads', N'NO — waits dominate', N'02_capture_live_session_waits.sql'),
    (N'High cpu, high reads, slow', N'YES — plan/index', N'Actual execution plan + missing indexes'),
    (N'CXPACKET top wait, high cpu', N'YES — MAXDOP, CTFP', N'Session MAXDOP or server MAXDOP'),
    (N'Recent upgrade, same data, new plan', N'YES — QS force plan', N'03_query_store_regression.sql'),
    (N'SSMS expand slow, app queries fast', N'NO', N'02_ssms_metadata_slowness.sql'),
    (N'Parameter sniffing (variable plan times)', N'MAYBE — OPTIMIZE FOR UNKNOWN', N'Query Store + RECOMPILE test')
) AS t(Scenario, Use_Hints, Primary_Tool);

PRINT '=== HINT EXAMPLES (copy and adapt) ===';

/*
-- 1. MAXDOP — parallelism control
SELECT ...
FROM ...
WHERE ...
OPTION (MAXDOP 1);  -- or MAXDOP 4, or USE HINT ('MAXDOP', 1) in 2016+

When it helps: CXPACKET/CXCONSUMER waits, uneven thread work
When it fails:  Blocking, PAGEIOLATCH, LATCH, PREEMPTIVE waits
Next if fail:   04_Wait_Stats/02_post_migration_wait_decoder.sql
*/

/*
-- 2. RECOMPILE — fresh plan per execution
SELECT ...
FROM ...
WHERE @p = ...
OPTION (RECOMPILE);

When it helps: Parameter sniffing, stale stats after migration
When it fails:  Lock waits, metadata waits (plan never executes)
Side effect:    Higher CPU compile cost — watch RESOURCE_SEMAPHORE_QUERY_COMPILE
Next if fail:   Update statistics FULLSCAN; Query Store regression check
*/

/*
-- 3. ARITHABORT — plan cache consistency (often set at app connection level)
SET ARITHABORT ON;
SET ANSI_NULLS ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SELECT ...

When it helps: Same query, two plans in cache, different default connection settings
When it fails:  Wait-bound queries (your reported pattern)
Next if fail:   Compare dm_exec_query_stats plans by sql_handle; fix app connection defaults
*/

/*
-- 4. FORCE ORDER — preserve join order from text
SELECT ...
FROM A
INNER JOIN B ON ...
INNER JOIN C ON ...
OPTION (FORCE ORDER);

When it helps: Optimizer reordering joins badly (nested loops vs hash)
When it fails:  Blocking during join execution; small row counts with huge elapsed = waits
Next if fail:   Live session waits capture
*/

/*
-- 5. USE HINT — modern hint syntax (SQL 2016 SP1+)
SELECT ...
OPTION (USE HINT ('DISABLE_OPTIMIZER_ROWGOAL'), USE HINT ('FORCE_LEGACY_CARDINALITY_ESTIMATION'));

When it helps: Row goal mis-estimates (TOP/EXISTS), CE regression after upgrade
When it fails:  Non-optimizer bottlenecks
*/

/*
-- 6. LOOP JOIN / HASH JOIN / MERGE JOIN — physical operator force
SELECT ...
OPTION (LOOP JOIN);   -- or HASH JOIN, MERGE JOIN

When it helps: Proven wrong join operator in plan XML
When it fails:  When query is blocked before join starts
*/

/*
-- 7. OPTIMIZE FOR UNKNOWN / OPTIMIZE FOR (@p = value)
DECLARE @p INT = 5;
SELECT ... WHERE col = @p
OPTION (OPTIMIZE FOR (@p UNKNOWN));

When it helps: Parameter sniffing with volatile parameter values
*/

PRINT '=== SESSION-LEVEL TEST ISOLATION ===';
PRINT 'Test one hint at a time. Combine MAXDOP 1 + RECOMPILE only after single-hint tests.';
PRINT 'If ALL hints fail with elapsed >> CPU: STOP hinting — run wait delta capture.';

-- Optional: list plans in cache for a query pattern
DECLARE @Filter NVARCHAR(200) = N'%';  -- set to your table name
SELECT TOP (10)
    qs.execution_count,
    qs.total_elapsed_time / NULLIF(qs.execution_count, 0) AS [Avg_Elapsed_ms],
    qs.total_worker_time / NULLIF(qs.execution_count, 0) AS [Avg_CPU_ms],
    qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS [Avg_Logical_Reads],
    qp.query_plan,
    st.text
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE st.text LIKE @Filter
  AND st.text NOT LIKE N'%dm_exec_query_stats%'
ORDER BY [Avg_Elapsed_ms] DESC;
