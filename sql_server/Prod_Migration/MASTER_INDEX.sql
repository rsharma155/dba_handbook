/*
================================================================================
Prod_Migration — Master Execution Index
================================================================================
Post-migration performance troubleshooting checklist.
Run scripts in order unless triage points elsewhere.

Scenario: 2019 Express → 2025 Developer, high elapsed, low CPU/reads,
           SSMS slow, query hints ineffective, slow on local VM too.

================================================================================
*/

PRINT '╔══════════════════════════════════════════════════════════════════════╗';
PRINT '║  PROD_MIGRATION TROUBLESHOOTING — EXECUTION ORDER                    ║';
PRINT '╚══════════════════════════════════════════════════════════════════════╝';

SELECT Step, Script, Purpose FROM (VALUES
    (0,  N'02_Upgrade_Validation/04_complete_post_upgrade_configuration_report.sql', N'FULL REPORT — config, DBs, waits, findings'),
    (1,  N'01_Quick_Triage/00_RUN_FIRST_triage_playbook.sql',           N'5-minute instance snapshot'),
    (2,  N'02_Upgrade_Validation/01_instance_upgrade_validation.sql',  N'Upgrade integrity, QS forced plans'),
    (3,  N'02_Upgrade_Validation/02_express_to_developer_limits_check.sql', N'Express memory/CPU artifacts'),
    (4,  N'02_Upgrade_Validation/03_cpu_numa_topology.sql',              N'CPU/NUMA topology after upgrade'),
    (5,  N'03_Elapsed_Time_Diagnostics/01_elapsed_vs_worker_time_gap.sql', N'Confirm wait-bound vs CPU-bound'),
    (6,  N'03_Elapsed_Time_Diagnostics/02_capture_live_session_waits.sql', N'Live wait on slow SPID'),
    (7,  N'04_Wait_Stats/01_wait_stats_delta_capture.sql',             N'Clean wait delta baseline'),
    (8,  N'04_Wait_Stats/02_wait_stats_delta_after_repro.sql',         N'Wait delta after repro (same session)'),
    (9,  N'04_Wait_Stats/02_post_migration_wait_decoder.sql',          N'Map waits to actions'),
    (10, N'04_Wait_Stats/03_latch_metadata_waits.sql',                 N'SSMS / latch investigation'),
    (11, N'05_Concurrency/01_blocking_and_locks.sql',                   N'Blocking chains'),
    (12, N'05_Concurrency/02_ssms_metadata_slowness.sql',              N'Object Explorer slowness'),
    (13, N'06_Optimizer_Plans/02_query_hint_guide.sql',                N'When hints fail (read first)'),
    (14, N'06_Optimizer_Plans/03_query_store_regression.sql',          N'Plan regression after upgrade'),
    (15, N'06_Optimizer_Plans/01_compatibility_and_ce.sql',            N'Compat / CE (if CPU-bound)'),
    (16, N'07_Instance_Config/01_post_migration_config_audit.sql',     N'MAXDOP, memory, CTFP'),
    (17, N'08_Storage_OS/01_io_latency_deep_dive.sql',                N'Disk latency'),
    (18, N'08_Storage_OS/03_tempdb_autogrowth_audit.sql',              N'TempDB PAGELATCH'),
    (19, N'08_Storage_OS/02_os_integration_post_migration.sql',        N'IFI, AV, AD'),
    (20, N'09_Extended_Events/01_xe_single_query_wait_capture.sql',   N'Proof-level wait capture'),
    (21, N'07_Instance_Config/02_recommended_fixes_with_rollback.sql', N'Apply fixes (controlled)')
) AS t(Step, Script, Purpose)
ORDER BY Step;

PRINT '';
PRINT 'Full playbook: Prod_Migration/README.md';
PRINT 'Related repo scripts: sql_server/04_Performance_Diagnostics/, 02_Instance_Config/';
