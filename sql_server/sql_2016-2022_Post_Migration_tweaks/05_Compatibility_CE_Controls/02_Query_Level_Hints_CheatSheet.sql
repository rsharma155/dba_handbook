/*
================================================================================
02_Query_Level_Hints_CheatSheet.sql
Purpose : Surgical hints for CE 160 regressions without changing whole DB.
================================================================================
*/

-- 1) Force legacy CE for one statement (best first A/B test)
SELECT /* your query */
FROM dbo.YourTable
WHERE ...
OPTION (USE HINT('FORCE_LEGACY_CARDINALITY_ESTIMATION'));

-- 2) Disable optimizer row goal (helps some TOP / EXISTS / IN / FAST patterns)
SELECT TOP (100) *
FROM dbo.YourTable
WHERE ...
OPTION (USE HINT('DISABLE_OPTIMIZER_ROWGOAL'));

-- 3) Force CE version explicitly (120 = 2014 CE family; useful experiments)
SELECT ...
OPTION (USE HINT('QUERY_OPTIMIZER_COMPATIBILITY_LEVEL_130'));  -- 2016-like optimizer model
-- Other values: 140, 150, 160

-- 4) Parameter sniffing mitigations
SELECT ...
WHERE Col = @p
OPTION (OPTIMIZE FOR UNKNOWN);

SELECT ...
WHERE Col = @p
OPTION (OPTIMIZE FOR (@p = 12345));  -- sniffed "typical" value

-- 5) Recompile (volatile params / skewed data; CPU cost on high-freq calls)
EXEC dbo.YourProc @p = 1 WITH RECOMPILE;
-- or inside proc: OPTION (RECOMPILE)

-- 6) Join / memory pressure tactics (validate!)
SELECT ...
OPTION (HASH JOIN);          -- or LOOP JOIN / MERGE JOIN
SELECT ...
OPTION (MIN_GRANT_PERCENT = 5, MAX_GRANT_PERCENT = 25);

-- 7) Disable interleaved execution for MSTVFs if it hurts a specific query
SELECT ...
OPTION (USE HINT('DISABLE_INTERLEAVED_EXECUTION_TVF'));

-- 8) Adaptive joins off for one query (rare)
SELECT ...
OPTION (USE HINT('DISABLE_BATCH_MODE_ADAPTIVE_JOINS'));

/*
PROCEDURE WRAPPER PATTERN — add hint without rewriting app SQL
*/
CREATE OR ALTER PROCEDURE dbo.usp_Report_Orders
    @FromDate date,
    @ToDate   date
AS
BEGIN
    SET NOCOUNT ON;
    SELECT o.*
    FROM dbo.Orders AS o
    WHERE o.OrderDate >= @FromDate AND o.OrderDate < @ToDate
    OPTION (USE HINT('FORCE_LEGACY_CARDINALITY_ESTIMATION'), RECOMPILE);
END;
GO

/*
QUERY STORE HINTS (SQL 2022) — apply hint without changing code
*/
-- EXEC sys.sp_query_store_set_hints @query_id = 123,
--      @query_hints = N'OPTION (USE HINT(''FORCE_LEGACY_CARDINALITY_ESTIMATION''))';
-- Check: SELECT * FROM sys.query_store_query_hints;
-- Clear: EXEC sys.sp_query_store_clear_hints @query_id = 123;
