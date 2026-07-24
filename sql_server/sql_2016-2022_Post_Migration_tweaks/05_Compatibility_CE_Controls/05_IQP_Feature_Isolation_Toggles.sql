/*
================================================================================
05_IQP_Feature_Isolation_Toggles.sql
Purpose : At compat 160, disable ONE Intelligent Query Processing feature at a
          time to find which feature caused the regression. Never disable all.
Prereq  : Stats / indexes / MAXDOP already tuned. Compat set to 160 in test.
================================================================================
*/
USE [YourDB]; -- <<< change
GO

-- Current scoped configs (focus on IQP-related)
SELECT name, value, is_value_default
FROM sys.database_scoped_configurations
WHERE name IN (
    N'LEGACY_CARDINALITY_ESTIMATION',
    N'TSQL_SCALAR_UDF_INLINING',
    N'BATCH_MODE_ON_ROWSTORE',
    N'ROW_MODE_MEMORY_GRANT_FEEDBACK',
    N'BATCH_MODE_MEMORY_GRANT_FEEDBACK',
    N'DOP_FEEDBACK',
    N'CE_FEEDBACK',
    N'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION',
    N'OPTIONAL_PARAMETER_OPTIMIZATION',
    N'PARAMETER_SNIFFING',
    N'INTERLEAVED_EXECUTION_TVF',
    N'BATCH_MODE_ADAPTIVE_JOINS'
)
ORDER BY name;

/*
TEST PROTOCOL (UAT only)
1) ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 160;
2) Clear cache: ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
3) Run workload / top procs; note duration
4) Toggle ONE setting OFF; clear cache; retest
5) If fixed → keep that OFF (or use query-level hint) and re-enable others
6) If not → set it back ON; try next

--- A) Legacy CE (whole-DB bridge; proves CE regression) ---
-- ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;

--- B) Scalar UDF inlining ---
-- ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = OFF;

--- C) Batch mode on rowstore (memory grant / aggregate shape) ---
-- ALTER DATABASE SCOPED CONFIGURATION SET BATCH_MODE_ON_ROWSTORE = OFF;

--- D) Memory grant feedback ---
-- ALTER DATABASE SCOPED CONFIGURATION SET ROW_MODE_MEMORY_GRANT_FEEDBACK = OFF;
-- ALTER DATABASE SCOPED CONFIGURATION SET BATCH_MODE_MEMORY_GRANT_FEEDBACK = OFF;

--- E) DOP feedback ---
-- ALTER DATABASE SCOPED CONFIGURATION SET DOP_FEEDBACK = OFF;

--- F) CE feedback ---
-- ALTER DATABASE SCOPED CONFIGURATION SET CE_FEEDBACK = OFF;

--- G) Parameter Sensitive Plan (PSP) ---
-- ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = OFF;

--- H) Optional parameter optimization ---
-- ALTER DATABASE SCOPED CONFIGURATION SET OPTIONAL_PARAMETER_OPTIMIZATION = OFF;

-- After ANY change:
-- ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;

GOAL STATE: compat 160 with as many features ON as possible; isolate only the offender.
*/
GO
