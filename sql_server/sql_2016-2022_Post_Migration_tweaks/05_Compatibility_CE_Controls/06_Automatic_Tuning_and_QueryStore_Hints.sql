/*
================================================================================
06_Automatic_Tuning_and_QueryStore_Hints.sql
Purpose : Stay on compat 160 without app deploy — auto plan correction + QS hints.
================================================================================
*/
USE [YourDB]; -- <<< change
GO

/*----- A) Automatic plan correction (FORCE_LAST_GOOD_PLAN) -----*/
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
-- Keep index auto-create/drop OFF unless explicitly approved:
-- ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (CREATE_INDEX = OFF, DROP_INDEX = OFF);

SELECT name, actual_state_desc, desired_state_desc, reason_desc
FROM sys.database_automatic_tuning_options;

-- Recommendations (if any)
SELECT reason, score, state = JSON_VALUE(state, '$.currentValue'), details
FROM sys.dm_db_tuning_recommendations;

/*----- B) Query Store hints (no code change) — SQL 2022 -----*/
-- Examples (set real query_id from regression report):
/*
EXEC sys.sp_query_store_set_hints
    @query_id = 123,
    @query_hints = N'OPTION (USE HINT(''FORCE_LEGACY_CARDINALITY_ESTIMATION''))';

EXEC sys.sp_query_store_set_hints
    @query_id = 124,
    @query_hints = N'OPTION (RECOMPILE)';

EXEC sys.sp_query_store_set_hints
    @query_id = 125,
    @query_hints = N'OPTION (OPTIMIZE FOR UNKNOWN)';

EXEC sys.sp_query_store_set_hints
    @query_id = 126,
    @query_hints = N'OPTION (USE HINT(''DISABLE_TSQL_SCALAR_UDF_INLINING''))';

EXEC sys.sp_query_store_set_hints
    @query_id = 127,
    @query_hints = N'OPTION (USE HINT(''QUERY_OPTIMIZER_COMPATIBILITY_LEVEL_130''))';

EXEC sys.sp_query_store_set_hints
    @query_id = 128,
    @query_hints = N'OPTION (USE HINT(''DISABLE_BATCH_MODE_ON_ROWSTORE''))';

EXEC sys.sp_query_store_set_hints
    @query_id = 129,
    @query_hints = N'OPTION (USE HINT(''DISABLE_PARAMETER_SNIFFING''))';
*/

-- Audit hints
SELECT qsh.query_id, qsh.query_hint_text, qsh.last_query_hint_failure_reason_desc,
       LEFT(qt.query_sql_text, 200) AS preview
FROM sys.query_store_query_hints qsh
JOIN sys.query_store_query q ON q.query_id = qsh.query_id
JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id;

-- Clear one hint:
-- EXEC sys.sp_query_store_clear_hints @query_id = 123;

/*----- C) Manual force last-good plan (when Automatic Tuning is not enough) -----*/
-- EXEC sys.sp_query_store_force_plan @query_id = 123, @plan_id = 456;
GO
