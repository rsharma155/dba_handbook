/*
================================================================================
04_SQL2022_IQP_and_CE_Feedback_Notes.sql
Purpose : IQP / CE feedback context when jumping SQL 2016 (CL 130) -> 2022 (CL 160).
Why it matters: Backup/restore migrations SKIP 2017 and 2019. Enabling CL 160
          activates multiple IQP features at once that apps never saw under 2016.
================================================================================
*/
USE [YourDB]; -- <<< change
GO

/*
================================================================================
SKIP-RELEASE EFFECT (2016 -> 2022 directly)
--------------------------------------------------------------------------------
SQL 2019 / CL 150 features that turn ON when you go to CL 160:
  - TSQL Scalar UDF Inlining
      Intended to remove row-by-row UDF cost. Can cause severe plan regressions,
      compilation CPU spikes, or wrong estimates on UDFs with complex logic,
      WHILE loops, or table access.
      Bridge: ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = OFF;
      Or: ALTER FUNCTION ... WITH INLINE = OFF; / query hint DISABLE_TSQL_SCALAR_UDF_INLINING

  - Batch Mode on Rowstore
      Batch operators on rowstore tables. Bad CE -> oversized memory grants,
      TempDB spills, or CXPACKET/CXCONSUMER under parallel batch plans.
      Bridge: SET BATCH_MODE_ON_ROWSTORE = OFF (test only); fix estimates/stats first.
      Also raise Cost Threshold for Parallelism (30-50) so trivial queries stay serial.

SQL 2022 / CL 160 features:
  - Parameter Sensitive Plan (PSP) Optimization
      Multiple plan variants for skewed parameters. Usually helps; can add QS
      overhead or thrash at variant boundaries. Check multi-plan queries in QS.
      Bridge: SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = OFF (targeted test).

  - CE Feedback / DOP Feedback / Memory Grant Feedback (refined)
      Learn over time; first executions after flip can still be bad.

Isolate ONE feature at a time - see 05_IQP_Feature_Isolation_Toggles.sql
================================================================================
*/

PRINT '=== Scoped configs that control IQP / CE bridges ===';
SELECT name, value, is_value_default
FROM sys.database_scoped_configurations
WHERE name IN (
    N'LEGACY_CARDINALITY_ESTIMATION',
    N'TSQL_SCALAR_UDF_INLINING',
    N'BATCH_MODE_ON_ROWSTORE',
    N'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION',
    N'OPTIONAL_PARAMETER_OPTIMIZATION',
    N'CE_FEEDBACK',
    N'DOP_FEEDBACK',
    N'ROW_MODE_MEMORY_GRANT_FEEDBACK',
    N'BATCH_MODE_MEMORY_GRANT_FEEDBACK',
    N'QUERY_OPTIMIZER_HOTFIXES'
)
ORDER BY name;

-- Query Store hints currently applied
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_query_store_on = 1)
BEGIN
    SELECT qsh.query_id, qsh.query_hint_id, qsh.query_hint_text,
           qsh.last_query_hint_failure_reason_desc,
           LEFT(qt.query_sql_text, 200) AS preview
    FROM sys.query_store_query_hints AS qsh
    JOIN sys.query_store_query AS q ON q.query_id = qsh.query_id
    JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id;

    -- PSP signal: many plans per query after CL 160
    SELECT q.query_id, COUNT(*) AS plan_count, LEFT(MAX(qt.query_sql_text), 120) AS preview
    FROM sys.query_store_query q
    JOIN sys.query_store_plan p ON p.query_id = q.query_id
    JOIN sys.query_store_query_text qt ON qt.query_text_id = q.query_text_id
    GROUP BY q.query_id
    HAVING COUNT(*) >= 3
    ORDER BY plan_count DESC;
END

-- INLINE = OFF candidates among scalar UDFs (if inlining hurts)
SELECT OBJECT_SCHEMA_NAME(o.object_id) AS schema_name,
       OBJECT_NAME(o.object_id) AS function_name,
       m.is_inlineable,
       m.inline_type
FROM sys.sql_modules AS m
JOIN sys.objects AS o ON o.object_id = m.object_id
WHERE o.type = N'FN';  -- scalar functions
GO
