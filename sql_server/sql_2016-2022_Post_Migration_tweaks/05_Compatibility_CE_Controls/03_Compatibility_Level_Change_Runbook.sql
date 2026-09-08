/*
================================================================================
03_Compatibility_Level_Change_Runbook.sql
Purpose : Safe production cutover / rollback between 130 and 160.
================================================================================
*/
USE [YourDB]; -- <<< change
GO

-- Pre-check
SELECT name, compatibility_level, is_query_store_on
FROM sys.databases WHERE name = DB_NAME();

SELECT actual_state_desc, current_storage_size_mb, max_storage_size_mb
FROM sys.database_query_store_options;

/*
======================== CUTOVER TO 160 ========================
Window: low traffic. Have app owners on call. Rollback script ready.
*/
-- 1) Ensure Query Store is healthy (READ_WRITE, not tiny)
-- 2) Optional: take a manual stats pass on hot tables first
-- 3) Flip:
-- ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 160;
-- 4) Clear proc cache for THIS database only:
-- ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
-- 5) Watch: Query Store regressions, wait stats, app APDEX/timeouts for 30–120 min
-- 6) If widespread pain:
--    ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;
--    ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
--    (keeps compat 160 features where possible while restoring old CE)

/*
======================== EMERGENCY ROLLBACK ========================
*/
-- ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 130;
-- ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF;
-- ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;

/*
Document in change ticket:
- Start time / end time
- Forced plan IDs
- Scoped config flags changed
- Queries rewritten
*/
