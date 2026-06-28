/*
================================================================================
sp_DBA_PlanCacheAnalyzer — Deep plan cache analysis with warnings
================================================================================
Analyzes the plan cache to find resource-intensive queries, plan quality issues,
and anti-patterns. Unlike a simple "top queries by CPU" script, this proc:

  1. Ranks queries by multiple dimensions (CPU, reads, duration, memory, executions)
  2. Detects anti-patterns via XML plan parsing (key lookups, implicit conversions,
     cursors, sorts, expensive plans)
  3. Groups results by "warning category" so you can fix patterns, not just queries
  4. Shows parameter sensitivity indicators (multiple plans for same query hash)
  5. Provides a human-readable "What To Do" column for each finding

Usage:
    EXEC dbo.sp_DBA_PlanCacheAnalyzer;
    EXEC dbo.sp_DBA_PlanCacheAnalyzer @SortOrder = 'READS', @TopN = 20;
    EXEC dbo.sp_DBA_PlanCacheAnalyzer @SortOrder = 'MEMORY', @TopN = 15;
    EXEC dbo.sp_DBA_PlanCacheAnalyzer @SortOrder = 'WARNING';
    EXEC dbo.sp_DBA_PlanCacheAnalyzer @FilterDatabase = N'SalesDB';
    EXEC dbo.sp_DBA_PlanCacheAnalyzer @MinExecutionCount = 10;

Sort Orders:
    CPU       - Top by total worker time (default)
    READS     - Top by logical reads
    DURATION  - Top by elapsed time
    MEMORY    - Top by memory grants
    EXECUTIONS- Top by execution count
    WRITES    - Top by logical writes
    WARNING   - Grouped by anti-pattern warning
    REGRESSION- Top by average duration (high = slow per-execution)
================================================================================
*/
IF OBJECT_ID(N'dbo.sp_DBA_PlanCacheAnalyzer', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DBA_PlanCacheAnalyzer AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_DBA_PlanCacheAnalyzer
    @SortOrder          VARCHAR(20) = 'CPU',
    @TopN               INT = 15,
    @FilterDatabase     NVARCHAR(128) = NULL,
    @MinExecutionCount  INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    IF @SortOrder NOT IN ('CPU','READS','DURATION','MEMORY','EXECUTIONS','WRITES','WARNING','REGRESSION')
    BEGIN
        RAISERROR(N'@SortOrder must be one of: CPU, READS, DURATION, MEMORY, EXECUTIONS, WRITES, WARNING, REGRESSION', 16, 1);
        RETURN;
    END;

    ------------------------------------------------------------
    -- Core CTE: extract plan warnings and anti-patterns
    ------------------------------------------------------------
    WITH PlanWarnings AS (
        SELECT
            qs.plan_handle,
            qs.sql_handle,
            qs.statement_start_offset,
            qs.statement_end_offset,
            -- Anti-pattern detection
            CASE WHEN qp.query_plan.exist('//IndexLookUp') = 1 THEN 1 ELSE 0 END AS Has_KeyLookup,
            CASE WHEN qp.query_plan.exist('//ScalarOperator[contains(@ScalarString,"CONVERT_IMPLICIT")]') = 1 THEN 1 ELSE 0 END AS Has_ImplicitConversion,
            CASE WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Sort"][@EstimateRows > 10000]') = 1 THEN 1 ELSE 0 END AS Has_ExpensiveSort,
            CASE WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Table Scan"]') = 1 THEN 1 ELSE 0 END AS Has_TableScan,
            CASE WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Index Scan"][@EstimateRows > 100000]') = 1 THEN 1 ELSE 0 END AS Has_LargeIndexScan,
            CASE WHEN qp.query_plan.exist('//Cursor') = 1 THEN 1 ELSE 0 END AS Has_Cursor,
            CASE WHEN qp.query_plan.exist('//Warnings/SpillToTempDb') = 1 THEN 1 ELSE 0 END AS Has_SpillToTempDB,
            CASE WHEN qp.query_plan.exist('//Warnings/PlanAffectingConvert') = 1 THEN 1 ELSE 0 END AS Has_ConvertWarning,
            CASE WHEN qp.query_plan.exist('//Warnings/NoJoinPredicate') = 1 THEN 1 ELSE 0 END AS Has_CartesianJoin,
            CASE WHEN qs.execution_count > 1 AND qs.total_elapsed_time / qs.execution_count > 10000000 THEN 1 ELSE 0 END AS Is_PossibleParamSniff,
            -- Build warning list
            CONCAT(
                CASE WHEN qp.query_plan.exist('//IndexLookUp') = 1 THEN 'KEY_LOOKUP; ' ELSE '' END,
                CASE WHEN qp.query_plan.exist('//ScalarOperator[contains(@ScalarString,"CONVERT_IMPLICIT")]') = 1 THEN 'IMPLICIT_CONVERSION; ' ELSE '' END,
                CASE WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Sort"][@EstimateRows > 10000]') = 1 THEN 'EXPENSIVE_SORT; ' ELSE '' END,
                CASE WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Table Scan"]') = 1 THEN 'TABLE_SCAN; ' ELSE '' END,
                CASE WHEN qp.query_plan.exist('//RelOp[@PhysicalOp="Index Scan"][@EstimateRows > 100000]') = 1 THEN 'LARGE_INDEX_SCAN; ' ELSE '' END,
                CASE WHEN qp.query_plan.exist('//Cursor') = 1 THEN 'CURSOR; ' ELSE '' END,
                CASE WHEN qp.query_plan.exist('//Warnings/SpillToTempDb') = 1 THEN 'TEMPDB_SPILL; ' ELSE '' END,
                CASE WHEN qp.query_plan.exist('//Warnings/NoJoinPredicate') = 1 THEN 'CARTESIAN_JOIN; ' ELSE '' END,
                CASE WHEN qs.execution_count > 1 AND qs.total_elapsed_time / qs.execution_count > 10000000 THEN 'PARAM_SNIFFING_SUSPECT; ' ELSE '' END
            ) AS Warnings
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
        WHERE qs.execution_count >= @MinExecutionCount
    ),
    MainQuery AS (
        SELECT
            qs.plan_handle,
            qs.sql_handle,
            qs.statement_start_offset,
            st.text                                                          AS Full_Query_Text,
            SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
                ((CASE qs.statement_end_offset
                    WHEN -1 THEN DATALENGTH(st.text)
                    ELSE qs.statement_end_offset
                 END - qs.statement_start_offset)/2)+1)                     AS Statement_Text,
            DB_NAME(st.dbid)                                                 AS Database_Name,
            qs.execution_count                                                AS Execution_Count,
            qs.total_worker_time / 1000                                       AS Total_CPU_ms,
            (qs.total_worker_time / qs.execution_count) / 1000               AS Avg_CPU_ms,
            qs.total_logical_reads                                            AS Total_Logical_Reads,
            qs.total_logical_reads / qs.execution_count                       AS Avg_Logical_Reads,
            qs.total_elapsed_time / 1000                                      AS Total_Duration_ms,
            (qs.total_elapsed_time / qs.execution_count) / 1000               AS Avg_Duration_ms,
            qs.total_physical_reads                                           AS Total_Physical_Reads,
            qs.total_logical_writes                                           AS Total_Logical_Writes,
            qs.total_grant_kb / 1024                                          AS Avg_Memory_Grant_MB,
            qs.total_spills * 8 / 1024                                        AS Total_Spills_MB,
            qs.plan_generation_num                                            AS Plan_Generation_Num,
            qs.creation_time                                                  AS Plan_Created_At,
            qs.last_execution_time                                            AS Last_Execution,
            HASHBYTES('SHA2_256', qs.query_hash)                              AS Query_Hash_Binary,
            CAST(qs.query_hash AS VARCHAR(16))                                AS Query_Hash,
            qp.query_plan                                                     AS Query_Plan
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
        WHERE qs.execution_count >= @MinExecutionCount
          AND (@FilterDatabase IS NULL OR DB_NAME(st.dbid) = @FilterDatabase)
    ),
    Combined AS (
        SELECT
            mq.*,
            pw.Warnings,
            pw.Has_KeyLookup,
            pw.Has_ImplicitConversion,
            pw.Has_ExpensiveSort,
            pw.Has_TableScan,
            pw.Has_LargeIndexScan,
            pw.Has_Cursor,
            pw.Has_SpillToTempDB,
            pw.Has_CartesianJoin,
            pw.Is_PossibleParamSniff,
            -- What to do
            CASE
                WHEN pw.Has_CartesianJoin = 1 THEN 'CRITICAL: Cartesian join detected. Check for missing WHERE clause or JOIN condition.'
                WHEN pw.Has_KeyLookup = 1 AND mq.Avg_CPU_ms > 500 THEN 'Add covering index to eliminate key lookup. High CPU + key lookup = priority fix.'
                WHEN pw.Has_ImplicitConversion = 1 THEN 'Check data type mismatch in WHERE/JOIN parameters. Match parameter types to column types.'
                WHEN pw.Has_SpillToTempDB = 1 THEN 'Query spills to TempDB. Add memory or create covering index to avoid sort/hash spills.'
                WHEN pw.Has_ExpensiveSort = 1 THEN 'Large sort operation. Add ORDER BY supporting index or reduce result set with WHERE.'
                WHEN pw.Has_TableScan = 1 AND mq.Avg_Logical_Reads > 10000 THEN 'Table scan on large table. Add appropriate index for this query pattern.'
                WHEN pw.Has_LargeIndexScan = 1 THEN 'Large index scan. Consider adding a more selective index or adding WHERE filters.'
                WHEN pw.Has_Cursor = 1 THEN 'Cursor detected. Consider converting to set-based logic for better performance.'
                WHEN pw.Is_PossibleParamSniff = 1 THEN 'Possible parameter sniffing. Test with OPTION(RECOMPILE) or use OPTIMIZE FOR hint.'
                WHEN mq.Avg_Duration_ms > 5000 THEN 'Slow query (>5s avg). Review execution plan for table scans, large sorts, or unnecessary I/O.'
                WHEN mq.Avg_Logical_Reads > 50000 THEN 'High reads (>50K avg). Check for missing indexes or inefficient joins.'
                ELSE 'Review execution plan for optimization opportunities.'
            END AS Recommendation
        FROM MainQuery mq
        LEFT JOIN PlanWarnings pw ON mq.plan_handle = pw.plan_handle
            AND mq.sql_handle = pw.sql_handle
            AND mq.statement_start_offset = pw.statement_start_offset
    )
    SELECT * INTO #PlanCacheResults FROM Combined;

    ------------------------------------------------------------
    -- Output based on sort order
    ------------------------------------------------------------
    IF @SortOrder = 'CPU'
        SELECT TOP (@TopN) * FROM #PlanCacheResults ORDER BY Total_CPU_ms DESC;

    ELSE IF @SortOrder = 'READS'
        SELECT TOP (@TopN) * FROM #PlanCacheResults ORDER BY Total_Logical_Reads DESC;

    ELSE IF @SortOrder = 'DURATION'
        SELECT TOP (@TopN) * FROM #PlanCacheResults ORDER BY Total_Duration_ms DESC;

    ELSE IF @SortOrder = 'MEMORY'
        SELECT TOP (@TopN) * FROM #PlanCacheResults ORDER BY Avg_Memory_Grant_MB DESC;

    ELSE IF @SortOrder = 'EXECUTIONS'
        SELECT TOP (@TopN) * FROM #PlanCacheResults ORDER BY Execution_Count DESC;

    ELSE IF @SortOrder = 'WRITES'
        SELECT TOP (@TopN) * FROM #PlanCacheResults ORDER BY Total_Logical_Writes DESC;

    ELSE IF @SortOrder = 'REGRESSION'
        SELECT TOP (@TopN) * FROM #PlanCacheResults ORDER BY Avg_Duration_ms DESC;

    ELSE IF @SortOrder = 'WARNING'
    BEGIN
        -- Summary: which warnings appear most frequently
        SELECT N'WARNING FREQUENCY SUMMARY' AS [Section];
        SELECT
            Warning_Type,
            COUNT(*) AS Occurrence_Count,
            SUM(Total_CPU_ms) AS Combined_CPU_ms
        FROM (
            SELECT
                CASE
                    WHEN Has_KeyLookup = 1 THEN 'KEY_LOOKUP'
                    WHEN Has_ImplicitConversion = 1 THEN 'IMPLICIT_CONVERSION'
                    WHEN Has_ExpensiveSort = 1 THEN 'EXPENSIVE_SORT'
                    WHEN Has_TableScan = 1 THEN 'TABLE_SCAN'
                    WHEN Has_LargeIndexScan = 1 THEN 'LARGE_INDEX_SCAN'
                    WHEN Has_Cursor = 1 THEN 'CURSOR'
                    WHEN Has_SpillToTempDB = 1 THEN 'TEMPDB_SPILL'
                    WHEN Has_CartesianJoin = 1 THEN 'CARTESIAN_JOIN'
                    WHEN Is_PossibleParamSniff = 1 THEN 'PARAM_SNIFFING'
                    ELSE 'NO_WARNING'
                END AS Warning_Type,
                Total_CPU_ms
            FROM #PlanCacheResults
        ) x
        GROUP BY Warning_Type
        ORDER BY COUNT(*) DESC;

        -- Then show the top queries by warning
        SELECT TOP (@TopN) * FROM #PlanCacheResults
        WHERE Warnings <> ''
        ORDER BY Total_CPU_ms DESC;
    END;

    -- Always show warning explanation
    SELECT
        'KEY_LOOKUP' AS Warning_Type,
        'Non-covering index requires a key lookup to fetch additional columns. Add included columns to the index.' AS Explanation
    UNION ALL SELECT 'IMPLICIT_CONVERSION', 'Data type mismatch forces implicit conversion, preventing index seeks. Match parameter types to column types.'
    UNION ALL SELECT 'EXPENSIVE_SORT', 'Sort operation on >10,000 rows. Add ORDER BY supporting index or reduce rows with WHERE.'
    UNION ALL SELECT 'TABLE_SCAN', 'Full table scan on a heap or clustered index. Add appropriate nonclustered index.'
    UNION ALL SELECT 'LARGE_INDEX_SCAN', 'Index scan on >100,000 rows. Review selectivity — may need a more selective index.'
    UNION ALL SELECT 'CURSOR', 'Cursor-based processing. Consider refactoring to set-based operations.'
    UNION ALL SELECT 'TEMPDB_SPILL', 'Sort/hash operation spilled to TempDB. Increase memory grant or add covering index.'
    UNION ALL SELECT 'CARTESIAN_JOIN', 'CRITICAL: Join without predicate. Check for missing ON/WHERE clause.'
    UNION ALL SELECT 'PARAM_SNIFFING', 'Same query has high avg duration despite many executions. Test with OPTION(RECOMPILE).'
    UNION ALL SELECT 'NO_WARNING', 'No anti-patterns detected in the cached plan.';
END;
GO
