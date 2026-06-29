/*
================================================================================
Recommended Post-Migration Fixes (with Rollback Notes)
================================================================================
Purpose:
    Actionable remediation templates. DO NOT run entire script blindly.
    Uncomment ONLY the section you need after triage confirms root cause.

Each section includes:
    - When to apply
    - Command
    - Rollback
    - What to do if fix fails

Criticality: High — change control required
================================================================================
*/

SET NOCOUNT ON;

PRINT '=== SECTION 1: INCREASE MAX SERVER MEMORY (after Express migration) ===';
PRINT 'When: 02_express_to_developer_limits_check shows memory << physical RAM';
PRINT 'Rollback: sp_configure max server memory back to prior value';
/*
DECLARE @NewMax INT = (SELECT physical_memory_kb / 1024 * 0.85 FROM sys.dm_os_sys_info);
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', @NewMax; RECONFIGURE;
-- If still slow: NOT a memory issue — return to wait stats
*/

PRINT '=== SECTION 2: MAXDOP AND COST THRESHOLD (OLTP defaults) ===';
PRINT 'When: CXPACKET waits + high CPU; NOT when LCK/LATCH/IO dominate';
PRINT 'Rollback: restore prior sp_configure values';
/*
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'max degree of parallelism', 4; RECONFIGURE;
EXEC sp_configure 'cost threshold for parallelism', 50; RECONFIGURE;
-- If fail: waits unchanged — problem is not parallelism
*/

PRINT '=== SECTION 3: OPTIMIZE FOR AD HOC WORKLOADS ===';
PRINT 'When: RESOURCE_SEMAPHORE_QUERY_COMPILE or huge plan cache ad hoc';
/*
EXEC sp_configure 'optimize for ad hoc workloads', 1; RECONFIGURE;
-- If fail: check compilation-heavy single procedure instead
*/

PRINT '=== SECTION 4: TEMPDB — ADD DATA FILES ===';
PRINT 'When: PAGELATCH_* on tempdb in wait decoder';
PRINT 'Rollback: files cannot be removed easily — test count in non-prod';
/*
DECLARE @files INT = (SELECT COUNT(*) FROM tempdb.sys.database_files WHERE type = 0);
DECLARE @cores INT = (SELECT cpu_count FROM sys.dm_os_sys_info);
DECLARE @target INT = CASE WHEN @cores > 8 THEN 8 ELSE @cores END;
-- Add files via SSMS or ALTER DATABASE tempdb ADD FILE ... equal size to file 1
*/

PRINT '=== SECTION 5: DISABLE AUTO_CLOSE / AUTO_SHRINK ===';
PRINT 'When: upgrade validation flags these ON';
/*
ALTER DATABASE [YourDB] SET AUTO_CLOSE OFF, AUTO_SHRINK OFF;
*/

PRINT '=== SECTION 6: FIX ORPHANED DATABASE OWNER ===';
PRINT 'When: SSMS metadata slow; owner_sid orphaned';
/*
ALTER AUTHORIZATION ON DATABASE::[YourDB] TO [sa];  -- or appropriate login
*/

PRINT '=== SECTION 7: QUERY STORE — UNFORCE BAD PLAN ===';
PRINT 'When: 03_query_store_regression identifies forced bad plan';
/*
USE [YourDB];
EXEC sys.sp_query_store_unforce_plan @query_id = 0, @plan_id = 0;  -- replace ids
*/

PRINT '=== SECTION 8: COMPATIBILITY LEVEL UPGRADE ===';
PRINT 'When: CE testing proves benefit in lower environment ONLY';
PRINT 'Rollback: ALTER DATABASE SET COMPATIBILITY_LEVEL = 150;';
/*
ALTER DATABASE [YourDB] SET COMPATIBILITY_LEVEL = 160;  -- or 170 for 2025
-- Run FULLSCAN stats update after change
*/

PRINT '=== SECTION 9: LEGACY CE (database scoped) ===';
PRINT 'When: USE HINT FORCE_LEGACY_CARDINALITY_ESTIMATION fixes plan in test';
/*
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;
-- Rollback: ... SET LEGACY_CARDINALITY_ESTIMATION = OFF;
*/

PRINT '=== SECTION 10: CLEAR WAIT STATS BASELINE (maintenance only) ===';
PRINT 'When: need clean wait delta after major fix';
/*
DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);
-- Document time of clear for future RCA
*/

PRINT '=== SECTION 11: FREEPROCCACHE (last resort, maintenance window) ===';
PRINT 'When: confirmed plan corruption; NOT for wait-bound issues';
/*
DBCC FREEPROCCACHE;
-- Causes compile storm — monitor RESOURCE_SEMAPHORE_QUERY_COMPILE
*/

PRINT '=== SECTION 12: ENABLE IFI ===';
PRINT 'When: PREEMPTIVE_OS_WRITEFILEGATHER waits; IFI = N in dm_server_services';
PRINT 'Action: Grant Perform volume maintenance tasks to SQL service account; restart SQL';

PRINT '=== IF ALL FIXES FAIL ===';
PRINT '1. Deploy 09_Extended_Events/01_xe_single_query_wait_capture.sql';
PRINT '2. Open Microsoft support case with wait stats + XE';
PRINT '3. Compare disk latency to pre-migration baseline on same VM';
