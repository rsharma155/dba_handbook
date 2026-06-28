/********************************************************************************************
   DBA ESSENTIAL SCRIPTS - MASTER INDEX
   =====================================
   SQL Server Management Studio (SSMS 20+) no longer supports .ssmssqlproj project files.
   Use this file as your navigation hub. Open any script below from the Script Explorer
   or by navigating to the file path shown.

   HOW TO USE:
   1. Connect to your SQL Server instance
   2. Open this file in SSMS (File -> Open -> File)
   3. Browse to the script you need in the sections below
   4. Right-click the line and select "Open File" from the context menu of the file path comment

   TIP: In SSMS, Ctrl+Shift+E opens the file location of the currently highlighted path.
         Or simply use the Object Explorer to navigate folders.

   NOTE: A simplified deployment workflow is available via the PowerShell scripts in
         00_Framework/. Use 00_Deploy_Framework.ps1 to deploy core objects, then run
         individual scripts per section below as needed.
********************************************************************************************/

/*===========================================================================
   00 - FRAMEWORK (Required Foundation)
     Install these procedures first. Other scripts depend on them.
===========================================================================*/
-- 00_Install_Framework.sql
--      Creates the DBA repository database and all core stored procedures.
--      This must be run FIRST before any other scripts.
--      Location: 00_Framework\00_Install_Framework.sql

-- fn_DBA_AgentRunDurationSeconds.sql
--      Helper function to calculate SQL Agent job run durations.
--      Location: 00_Framework\fn_DBA_AgentRunDurationSeconds.sql

-- fn_DBA_ExcludedWaitTypes.sql
--      Helper function listing wait types to exclude from analysis.
--      Location: 00_Framework\fn_DBA_ExcludedWaitTypes.sql

-- sp_DBA_ActiveSessions.sql
--      Real-time active session monitor with DETAIL/SUMMARY/BLOCKING modes.
--      Location: 00_Framework\sp_DBA_ActiveSessions.sql

-- sp_DBA_BackupReview.sql
--      Reviews backup history - last backup dates, sizes, and status.
--      Location: 00_Framework\sp_DBA_BackupReview.sql

-- sp_DBA_BaselineCapture.sql
--      Captures a performance baseline for trend analysis.
--      Location: 00_Framework\sp_DBA_BaselineCapture.sql

-- sp_DBA_ForEachDatabase.sql
--      Utility to run a command against all user databases.
--      Location: 00_Framework\sp_DBA_ForEachDatabase.sql

-- sp_DBA_HealthCheck.sql
--      Comprehensive health check - the flagship script.
--      Location: 00_Framework\sp_DBA_HealthCheck.sql

-- sp_DBA_IndexReview.sql
--      Reviews index usage, fragmentation, and missing indexes.
--      Location: 00_Framework\sp_DBA_IndexReview.sql

-- sp_DBA_PlanCacheAnalyzer.sql
--      Deep plan cache analysis with anti-pattern detection and sort orders.
--      Location: 00_Framework\sp_DBA_PlanCacheAnalyzer.sql

-- sp_DBA_QueryStoreRegressions.sql
--      Identifies Query Store regressions.
--      Location: 00_Framework\sp_DBA_QueryStoreRegressions.sql

-- sp_DBA_SaveAssessmentRun.sql
--      Persists health check results for historical comparison.
--      Location: 00_Framework\sp_DBA_SaveAssessmentRun.sql

-- sp_DBA_SecurityAudit.sql
--      Audits server and database-level security.
--      Location: 00_Framework\sp_DBA_SecurityAudit.sql

-- sp_DBA_WaitAnalysis.sql
--      Analyzes wait statistics to identify performance bottlenecks.
--      Location: 00_Framework\sp_DBA_WaitAnalysis.sql


/*===========================================================================
   00 - REPOSITORY (Database Schema Objects)
     Core tables and types used by the Framework procedures.
===========================================================================*/
-- AssessmentFindingTableType.sql
--      User-defined table type for assessment results.
--      Location: 00_Repository\AssessmentFindingTableType.sql

-- CheckIdRegistry.sql
--      Registry of all health check IDs and descriptions.
--      Location: 00_Repository\CheckIdRegistry.sql

-- DBARepository_Create.sql
--      Creates the DBA_Repository database schema.
--      Location: 00_Repository\DBARepository_Create.sql

-- DBARepository_Deploy.sql
--      Deploys all repository objects to the target database.
--      Location: 00_Repository\DBARepository_Deploy.sql

-- DBARepository_Persistence.sql
--      Persistence layer for storing assessment results.
--      Location: 00_Repository\DBARepository_Persistence.sql


/*===========================================================================
   01 - SERVER OS
     Operating system level diagnostics.
===========================================================================*/
-- cpu_utilization.sql
--      Reports CPU usage, scheduler pressure, and system health.
--      Location: 01_Server_OS\cpu_utilization.sql

-- disk_latency.sql
--      Measures disk I/O latency per database file.
--      Location: 01_Server_OS\disk_latency.sql

-- memory_diagnostics.sql
--      Analyzes memory pressure, buffer pool, and page life expectancy.
--      Location: 01_Server_OS\memory_diagnostics.sql


/*===========================================================================
   02 - INSTANCE CONFIGURATION
     SQL Server instance-level settings audit.
===========================================================================*/
-- database_compatibility_audit.sql
--      Checks database compatibility levels and recommends updates.
--      Location: 02_Instance_Config\database_compatibility_audit.sql

-- os_integration_checks.sql
--      Reviews SQL Server integration with Windows OS (memory, accounts).
--      Location: 02_Instance_Config\os_integration_checks.sql

-- server_configuration_audit.sql
--      Audits sp_configure settings against best practices.
--      Location: 02_Instance_Config\server_configuration_audit.sql


/*===========================================================================
   03 - STORAGE ENGINE
     Database file configuration and storage internals.
===========================================================================*/
-- database_files_growth.sql
--      Reviews file growth settings and auto-growth events.
--      Location: 03_Storage_Engine\database_files_growth.sql

-- tempdb_configuration.sql
--      Checks TempDB file count, size, and placement.
--      Location: 03_Storage_Engine\tempdb_configuration.sql

-- vlf_fragmentation.sql
--      Analyzes Virtual Log File fragmentation in transaction logs.
--      Location: 03_Storage_Engine\vlf_fragmentation.sql


/*===========================================================================
   04 - PERFORMANCE DIAGNOSTICS
     Query and workload performance analysis.
===========================================================================*/
-- blocking_and_deadlocks.sql
--      Reports current blocking chains and deadlock history.
--      Location: 04_Performance_Diagnostics\blocking_and_deadlocks.sql

-- deadlock_analysis.sql
--      Advanced deadlock analysis from Extended Events with object contention map.
--      Location: 04_Performance_Diagnostics\deadlock_analysis.sql

-- plan_cache_deep_dive.sql
--      Analyzes query plan cache for compilation and reuse metrics.
--      Location: 04_Performance_Diagnostics\plan_cache_deep_dive.sql

-- top_resource_queries.sql
--      Identifies top queries by CPU, IO, and duration.
--      Location: 04_Performance_Diagnostics\top_resource_queries.sql

-- wait_statistics.sql
--      Comprehensive wait stats analysis with categorization.
--      Location: 04_Performance_Diagnostics\wait_statistics.sql

-- wait_statistics_reference.sql
--      Reference guide for common wait types and their meanings.
--      Location: 04_Performance_Diagnostics\wait_statistics_reference.sql


/*===========================================================================
   05 - INDEX & STATISTICS
     Index health, usage, and statistics freshness.
===========================================================================*/
-- advanced_index_analysis.sql
--      Deep-dive into index structure, fragmentation, and usage.
--      Location: 05_Index_Statistics\advanced_index_analysis.sql

-- index_usage_efficiency.sql
--      Identifies unused/overlapping indexes and missing indexes.
--      Location: 05_Index_Statistics\index_usage_efficiency.sql

-- physical_stats_and_heaps.sql
--      Reviews heap tables and physical index statistics.
--      Location: 05_Index_Statistics\physical_stats_and_heaps.sql

-- statistics_freshness.sql
--      Checks statistics update dates and row modification counters.
--      Location: 05_Index_Statistics\statistics_freshness.sql


/*===========================================================================
   06 - HIGH AVAILABILITY & DISASTER RECOVERY
     AG, backup chain, and restore validation.
===========================================================================*/
-- alwayson_ag_monitor.sql
--      Monitors Availability Group health, synchronization state.
--      Location: 06_HA_DR\alwayson_ag_monitor.sql

-- backup_log_chain.sql
--      Analyzes the backup log chain for gaps.
--      Location: 06_HA_DR\backup_log_chain.sql

-- backup_verification.sql
--      Verifies backup file integrity and restore readiness.
--      Location: 06_HA_DR\backup_verification.sql

-- restore_test_simulator.sql
--      Automated restore testing simulator with chain validation and RPO/RTO estimation.
--      Location: 06_HA_DR\restore_test_simulator.sql


/*===========================================================================
   07 - SECURITY
     Authentication, authorization, and encryption audit.
===========================================================================*/
-- authorization_audit.sql
--      Reviews database-level permissions and role memberships.
--      Location: 07_Security\authorization_audit.sql

-- encryption_hardening.sql
--      Checks TDE, SSL, and encryption configuration.
--      Location: 07_Security\encryption_hardening.sql

-- login_audit.sql
--      Audits server logins, orphaned users, and password policies.
--      Location: 07_Security\login_audit.sql


/*===========================================================================
   08 - ADVANCED
     Specialized deep-dives and advanced troubleshooting.
===========================================================================*/
-- cdc_health.sql
--      Monitors Change Data Capture (CDC) health and latency.
--      Location: 08_Advanced\cdc_health.sql

-- error_log_and_connectivity.sql
--      Reads the SQL Server error log for critical events.
--      Location: 08_Advanced\error_log_and_connectivity.sql

-- feature_deep_dive_audit.sql
--      Audits SQL Server feature usage across the instance.
--      Location: 08_Advanced\feature_deep_dive_audit.sql

-- inmemory_compression.sql
--      Reviews In-Memory OLTP tables and data compression.
--      Location: 08_Advanced\inmemory_compression.sql

-- query_store_health.sql
--      Monitors Query Store configuration, size, and health.
--      Location: 08_Advanced\query_store_health.sql

-- replication_monitor.sql
--      Monitors transactional and merge replication health.
--      Location: 08_Advanced\replication_monitor.sql

-- sql_agent_job_monitor.sql
--      Reviews SQL Agent job history, failures, and durations.
--      Location: 08_Advanced\sql_agent_job_monitor.sql

-- ultra_deep_internal_audit.sql
--      Comprehensive internal SQL Server audit.
--      Location: 08_Advanced\ultra_deep_internal_audit.sql


/*===========================================================================
   09 - MAINTENANCE
     Integrity checks and job monitoring.
===========================================================================*/
-- failed_jobs.sql
--      Reports SQL Agent jobs that have failed recently.
--      Location: 09_Maintenance\failed_jobs.sql

-- last_checkdb_dates.sql
--      Shows when DBCC CHECKDB last ran for each database.
--      Location: 09_Maintenance\last_checkdb_dates.sql


/*===========================================================================
   10 - CAPACITY PLANNING
===========================================================================*/
-- database_growth_forecast.sql
--      Predicts database growth based on historical data.
--      Location: 10_Capacity_Planning\database_growth_forecast.sql


/*===========================================================================
   11 - QUERY STORE
===========================================================================*/
-- regressed_queries.sql
--      Identifies queries with regressed performance in Query Store.
--      Location: 11_Query_Store\regressed_queries.sql


/*===========================================================================
   12 - EXTENDED EVENTS
===========================================================================*/
-- active_xe_sessions.sql
--      Lists active Extended Events sessions and their targets.
--      Location: 12_Extended_Events\active_xe_sessions.sql


/*===========================================================================
   13 - RESOURCE GOVERNOR
===========================================================================*/
-- resource_governor_config.sql
--      Reviews Resource Governor configuration and classifier function.
--      Location: 13_Resource_Governor\resource_governor_config.sql


/*===========================================================================
   14 - BASELINES
===========================================================================*/
-- performance_snapshot.sql
--      Captures a point-in-time performance snapshot for trending.
--      Location: 14_Baselines\performance_snapshot.sql


PRINT '=== DBA Essential Scripts Master Index ===';
PRINT 'Total script categories: 14';
PRINT '';
PRINT 'To open a script: File -> Open -> File, or drag & drop into SSMS.';
PRINT 'Recommended first step: Run 00_Framework\00_Deploy_Framework.ps1 to auto-deploy all required objects.';
PRINT 'Then run scripts from any category in any order.';
