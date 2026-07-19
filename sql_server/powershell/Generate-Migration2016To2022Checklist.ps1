#Requires -Version 5.1
<#
.SYNOPSIS
    Generates interactive HTML checklist for SQL Server 2016 to 2022 Enterprise migration.

.EXAMPLE
    .\Generate-Migration2016To2022Checklist.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath = '',
    [string]$ScriptsPath = '',
    [string]$ProdMigrationPath = '',
    [string]$ZipPath = '',
    [switch]$SkipZip
)

$__scriptRoot = $PSScriptRoot
if (-not $__scriptRoot) {
    $__scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $OutputPath) {
    $OutputPath = Join-Path (Join-Path $__scriptRoot '..') (Join-Path 'output' 'SQL_2016_to_2022_Migration_Checklist.html')
}
if (-not $ScriptsPath) {
    $ScriptsPath = Join-Path (Join-Path $__scriptRoot '..') 'Migration_2016_to_2022'
}
if (-not $ProdMigrationPath) {
    $ProdMigrationPath = Join-Path (Join-Path $__scriptRoot '..') 'Prod_Migration'
}
if (-not $ZipPath) {
    $ZipPath = Join-Path (Join-Path $__scriptRoot '..') (Join-Path 'output' 'SQL_2016_to_2022_Migration_Package.zip')
}

function Get-ScriptContent {
    param([string]$FileName)
    if (-not $FileName) { return $null }
    $path = Join-Path $ScriptsPath $FileName
    if (-not (Test-Path -LiteralPath $path)) { return "-- File not found: $FileName" }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
}

function Get-ScriptContentFromFullPath {
    param([string]$FullPath, [string]$DisplayKey)
    if (-not (Test-Path -LiteralPath $FullPath)) { return "-- File not found: $DisplayKey" }
    return (Get-Content -LiteralPath $FullPath -Raw -Encoding UTF8)
}

function Escape-Html([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
}

function Escape-Js([string]$s) {
    if ($null -eq $s) { return '' }
    $b = [string][char]92
    $q = [string][char]34
    $s = $s.Replace($b, $b + $b)
    $s = $s.Replace($q, $b + $q)
    $s = $s.Replace([string][char]13, '')
    $s = $s.Replace([string][char]10, $b + [string][char]110)
    return $s
}
$scriptFiles = @{
    '01_instance_version_and_patch.sql' = Get-ScriptContent '01_instance_version_and_patch.sql'
    '02_server_configuration.sql' = Get-ScriptContent '02_server_configuration.sql'
    '03_trace_flags_documentation.sql' = Get-ScriptContent '03_trace_flags_documentation.sql'
    '04_database_inventory.sql' = Get-ScriptContent '04_database_inventory.sql'
    '05_database_features_tde_cdc.sql' = Get-ScriptContent '05_database_features_tde_cdc.sql'
    '06_ha_dr_topology.sql' = Get-ScriptContent '06_ha_dr_topology.sql'
    '07_logins_and_server_roles.sql' = Get-ScriptContent '07_logins_and_server_roles.sql'
    '08_orphaned_users_precheck.sql' = Get-ScriptContent '08_orphaned_users_precheck.sql'
    '09_linked_servers_and_jobs.sql' = Get-ScriptContent '09_linked_servers_and_jobs.sql'
    '10_deprecated_features_usage.sql' = Get-ScriptContent '10_deprecated_features_usage.sql'
    '11_stretch_database_check.sql' = Get-ScriptContent '11_stretch_database_check.sql'
    '12_polybase_hadoop_check.sql' = Get-ScriptContent '12_polybase_hadoop_check.sql'
    '13_pre_migration_readiness.sql' = Get-ScriptContent '13_pre_migration_readiness.sql'
    '14_backup_chain_verification.sql' = Get-ScriptContent '14_backup_chain_verification.sql'
    '15_post_install_config_audit.sql' = Get-ScriptContent '15_post_install_config_audit.sql'
    '16_pre_cutover_baseline.sql' = Get-ScriptContent '16_pre_cutover_baseline.sql'
    '17_cutover_validation.sql' = Get-ScriptContent '17_cutover_validation.sql'
    '18_post_migration_validation.sql' = Get-ScriptContent '18_post_migration_validation.sql'
    '19_query_store_enable_and_status.sql' = Get-ScriptContent '19_query_store_enable_and_status.sql'
    '20_compatibility_level_report.sql' = Get-ScriptContent '20_compatibility_level_report.sql'
    '21_rollback_evidence_capture.sql' = Get-ScriptContent '21_rollback_evidence_capture.sql'
    '22_ag_health_check.sql' = Get-ScriptContent '22_ag_health_check.sql'
    '23_tde_certificate_inventory.sql' = Get-ScriptContent '23_tde_certificate_inventory.sql'
    '24_post_restore_checkdb_and_stats.sql' = Get-ScriptContent '24_post_restore_checkdb_and_stats.sql'
}

# Embed Prod_Migration troubleshooting scripts (clickable from Quick Links / Script Library)
$troubleshootKeys = @(
    'Prod_Migration/01_Quick_Triage/00_RUN_FIRST_triage_playbook.sql'
    'Prod_Migration/02_Upgrade_Validation/04_complete_post_upgrade_configuration_report.sql'
    'Prod_Migration/06_Optimizer_Plans/03_query_store_regression.sql'
    'Prod_Migration/04_Wait_Stats/02_post_migration_wait_decoder.sql'
    'Prod_Migration/05_Concurrency/01_blocking_and_locks.sql'
    'Prod_Migration/07_Instance_Config/01_post_migration_config_audit.sql'
    'Prod_Migration/MASTER_INDEX.sql'
)
foreach ($rel in $troubleshootKeys) {
    $sub = $rel.Substring('Prod_Migration/'.Length) -replace '/', [IO.Path]::DirectorySeparatorChar
    $full = Join-Path $ProdMigrationPath $sub
    $scriptFiles[$rel] = Get-ScriptContentFromFullPath -FullPath $full -DisplayKey $rel
}

$steps = @(
    @{ StepID='P0-01'; PhaseID='P0'; PhaseName='Initiation & Governance'; Task='Obtain executive approval, budget, and SQL Server 2022 Enterprise licensing'; Priority='Critical'; Script=$null; Details='Document RTO/RPO, downtime budget, and change management RFC/CR numbers.' }
    @{ StepID='P0-02'; PhaseID='P0'; PhaseName='Initiation & Governance'; Task='Confirm vendor/application certification for SQL Server 2022 and Windows Server version'; Priority='Critical'; Script=$null; Details='Collect certification matrix from ERP, reporting, ETL, ORM, backup, monitoring, and custom app vendors.' }
    @{ StepID='P0-03'; PhaseID='P0'; PhaseName='Initiation & Governance'; Task='Assign migration roles (DBA lead, infra, app owner, security, change manager)'; Priority='High'; Script=$null; Details='See migration plan Section 15 - Roles and Responsibilities.' }
    @{ StepID='P0-04'; PhaseID='P0'; PhaseName='Initiation & Governance'; Task='Choose migration strategy (side-by-side recommended for production)'; Priority='Critical'; Script=$null; Details='Options: in-place upgrade, backup/restore, log shipping, AG migration. Side-by-side provides best rollback path.' }
    @{ StepID='P0-05'; PhaseID='P0'; PhaseName='Initiation & Governance'; Task='Third-party tool compatibility matrix (monitoring, backup, ORM, SSIS, replication, linked servers)'; Priority='Critical'; Script=$null; Details='Confirm each tool supports SQL 2022: monitoring agents (DMVs), backup software (backup formats), ORMs, SSIS 2022, replication subscribers, linked-server providers to down-level SQL.' }
    @{ StepID='P0-06'; PhaseID='P0'; PhaseName='Initiation & Governance'; Task='Schedule maintenance window, change freeze, and communication plan'; Priority='Critical'; Script=$null; Details='Book cutover window with app/infra owners. Publish freeze dates, war-room bridge, and user notification timeline.' }

    @{ StepID='P1-01'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Capture instance version, edition, and patch level (must be 2016 SP3+ for in-place)'; Priority='Critical'; Script='01_instance_version_and_patch.sql'; Details='Run on SOURCE. Save output as baseline artifact.' }
    @{ StepID='P1-02'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Document server configuration (memory, MAXDOP, CTFP, security settings)'; Priority='Critical'; Script='02_server_configuration.sql'; Details='Compare SOURCE vs TARGET after build.' }
    @{ StepID='P1-03'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Document active trace flags and startup parameters'; Priority='High'; Script='03_trace_flags_documentation.sql'; Details='Re-test each trace flag on 2022 - many legacy flags are unnecessary.' }
    @{ StepID='P1-04'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Inventory all user databases (size, compat level, recovery model)'; Priority='Critical'; Script='04_database_inventory.sql'; Details='Flag AUTO_CLOSE/AUTO_SHRINK on production databases.' }
    @{ StepID='P1-05'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Identify TDE, CDC, Change Tracking, In-Memory OLTP, FileStream'; Priority='Critical'; Script='05_database_features_tde_cdc.sql'; Details='Plan certificate migration and feature reconfiguration on target.' }
    @{ StepID='P1-06'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Map HA/DR topology (AG, mirroring, log shipping, replication)'; Priority='Critical'; Script='06_ha_dr_topology.sql'; Details='Rebuild topology on 2022 - do not assume config transfers unchanged.' }
    @{ StepID='P1-07'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Audit logins, sysadmin membership, and server roles'; Priority='Critical'; Script='07_logins_and_server_roles.sql'; Details='Export logins with sp_help_revlogin or DBATools before cutover.' }
    @{ StepID='P1-08'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Identify orphaned database users (pre-migration baseline)'; Priority='High'; Script='08_orphaned_users_precheck.sql'; Details='Uses short LOCK_TIMEOUT + set-based DB list (safe for 100+ DBs). Re-run on TARGET after restore; apply generated fix scripts.' }
    @{ StepID='P1-09'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Inventory linked servers, SQL Agent jobs (flag ActiveX steps), TRUSTWORTHY'; Priority='Critical'; Script='09_linked_servers_and_jobs.sql'; Details='T-SQL Agent steps are NOT removed. ActiveX Scripting IS discontinued - convert to CmdExec/PowerShell. Review TRUSTWORTHY databases. Update SNAC providers to ODBC 18 / OLE DB 19.' }
    @{ StepID='P1-10'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Check deprecated feature usage counters'; Priority='Critical'; Script='10_deprecated_features_usage.sql'; Details='Also run Microsoft DMA or SSMS Upgrade Assessment report.' }
    @{ StepID='P1-11'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Verify no Stretch Database tables remain (blocker)'; Priority='Critical'; Script='11_stretch_database_check.sql'; Details='Stretch discontinued - unstretch all tables before migration.' }
    @{ StepID='P1-12'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Verify no PolyBase Hadoop/HDFS external data sources (blocker)'; Priority='Critical'; Script='12_polybase_hadoop_check.sql'; Details='Recreate with S3/Azure/supported connectors on 2022.' }
    @{ StepID='P1-13'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Inventory TDE certificates and backup status'; Priority='Critical'; Script='23_tde_certificate_inventory.sql'; Details='Backup SMK and TDE certificates before cutover - store offline.' }
    @{ StepID='P1-14'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Run combined pre-migration readiness summary'; Priority='Critical'; Script='13_pre_migration_readiness.sql'; Details='Review FAIL/WARN items with stakeholders before proceeding.' }
    @{ StepID='P1-15'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Audit client drivers (SNAC removal impact) on all app servers'; Priority='Critical'; Script=$null; Details='Replace SQLNCLI/SQLOLEDB with Microsoft ODBC Driver 18 or OLE DB Driver 19. Test TLS 1.2+ from app tier.' }
    @{ StepID='P1-16'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='System database compatibility evaluation (master/msdb/model)'; Priority='High'; Script='20_compatibility_level_report.sql'; Details='Upgrade leaves system DBs at compat 130 (supported). Inventory custom objects/login triggers in master; test before any raise to 160.' }
    @{ StepID='P1-17'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Inventory MSDTC / distributed transaction usage across AGs'; Priority='High'; Script=$null; Details='SQL Server 2022 DTC/AG transport differs. Validate cross-replica distributed transactions in UAT per Microsoft CU guidance.' }
    @{ StepID='P1-18'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Remediate ActiveX SQL Agent job steps (if any)'; Priority='Critical'; Script='09_linked_servers_and_jobs.sql'; Details='Common myth: T-SQL Agent subsystem is removed - it is NOT. ActiveX Scripting is discontinued. Convert ActiveX steps to CmdExec or PowerShell before cutover.' }
    @{ StepID='P1-19'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Review TRUSTWORTHY and cross-db ownership chaining usage'; Priority='High'; Script='09_linked_servers_and_jobs.sql'; Details='Still supported but higher security risk. Prefer certificates/module signing over TRUSTWORTHY where possible.' }
    @{ StepID='P1-20'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Inventory monitoring agents and confirm SQL 2022 / DMV support'; Priority='High'; Script=$null; Details='Old monitoring tools may call deprecated DMVs or miss 2022 counters. Upgrade agent/collector to a vendor-supported build for SQL 2022 before cutover.' }
    @{ StepID='P1-21'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Confirm backup software supports SQL Server 2022 backup formats'; Priority='Critical'; Script='14_backup_chain_verification.sql'; Details='Vendor-check Commvault/Veeam/Rubrik/NetBackup/etc. Test full/diff/log backup+restore on a 2022 UAT instance before prod cutover.' }
    @{ StepID='P1-22'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Inventory ORM frameworks and generated SQL patterns'; Priority='High'; Script=$null; Details='EF/Hibernate/Dapper/NHibernate/etc. may emit deprecated hints or patterns. Plan ORM upgrade + query regression tests in UAT.' }
    @{ StepID='P1-23'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Inventory SSIS/SSRS/SSAS versions and package connection managers'; Priority='Critical'; Script=$null; Details='SSIS 2016 packages often break on SNAC/SQLOLEDB. Plan upgrade of SSIS/SSRS/SSAS to 2022 and retest packages against ODBC 18 / OLE DB 19.' }
    @{ StepID='P1-24'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Map replication topology - publishers, distributors, subscribers (versions)'; Priority='Critical'; Script='06_ha_dr_topology.sql'; Details='SQL 2022 publisher generally cannot keep old-version subscribers healthy long-term. Upgrade or re-home subscribers; rebuild publications on TARGET.' }
    @{ StepID='P1-25'; PhaseID='P1'; PhaseName='Discovery & Assessment'; Task='Inventory all application connection strings / DSNs / service accounts'; Priority='Critical'; Script=$null; Details='List every app, job, report, ETL, and linked process that connects to SQL. Needed for DNS/listener cutover and driver upgrades.' }

    @{ StepID='P2-01'; PhaseID='P2'; PhaseName='Target Environment Design'; Task='Design target OS (Windows Server 2019/2022) and hardware/VM sizing'; Priority='Critical'; Script=$null; Details='Separate volumes: data, log, TempDB, backup. 64 KB alignment. OS must be 64-bit Windows Server 2016+ (prefer 2019/2022).' }
    @{ StepID='P2-02'; PhaseID='P2'; PhaseName='Target Environment Design'; Task='Confirm .NET Framework 4.8+ and infra readiness (Windows/network/storage/ISO)'; Priority='Critical'; Script=$null; Details='SQL Server 2022 requires .NET 4.8+. Coordinate Windows policies, network, storage capacity, and install media with infra teams.' }
    @{ StepID='P2-03'; PhaseID='P2'; PhaseName='Target Environment Design'; Task='Match server collation; plan UTF-8 catalog collation at install if needed'; Priority='High'; Script=$null; Details='Catalog collation cannot be changed after install.' }
    @{ StepID='P2-04'; PhaseID='P2'; PhaseName='Target Environment Design'; Task='Design TempDB layout (multiple equal-sized files, pre-sized)'; Priority='High'; Script=$null; Details='1 file per CPU up to 8, then add in multiples of 4.' }
    @{ StepID='P2-05'; PhaseID='P2'; PhaseName='Target Environment Design'; Task='Plan connection abstraction (listener/DNS) for cutover and rollback'; Priority='Critical'; Script=$null; Details='Enables fast connection rollback without mass app redeploy.' }
    @{ StepID='P2-06'; PhaseID='P2'; PhaseName='Target Environment Design'; Task='Document linked-server ports and non-SQL providers (Oracle drivers, etc.)'; Priority='High'; Script='09_linked_servers_and_jobs.sql'; Details='Open TCP 1433 (SQL), UDP 1434 (Browser if named), Oracle 1521 (or custom). Install provider drivers on TARGET before recreating linked servers.' }

    @{ StepID='P3-01'; PhaseID='P3'; PhaseName='Build & Configure Target'; Task='Install SQL Server 2022 Enterprise with latest CU (never RTM-only)'; Priority='Critical'; Script=$null; Details='PSP and other 2022 features had early-CU bugs. Always install latest CU before UAT/prod. See sql_server/docs/sqlserver_installation_checklist.md.' }
    @{ StepID='P3-02'; PhaseID='P3'; PhaseName='Build & Configure Target'; Task='Apply post-install configuration (memory, MAXDOP, backup compression, IFI)'; Priority='Critical'; Script='15_post_install_config_audit.sql'; Details='Grant Perform volume maintenance tasks to SQL service account.' }
    @{ StepID='P3-03'; PhaseID='P3'; PhaseName='Build & Configure Target'; Task='Evaluate memory-optimized TempDB metadata for high concurrency'; Priority='High'; Script='02_server_configuration.sql'; Details='ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON (requires restart). Critical for latch-heavy TempDB on 2022.' }
    @{ StepID='P3-04'; PhaseID='P3'; PhaseName='Build & Configure Target'; Task='Plan ADR enablement and Persistent Version Store (PVS) sizing'; Priority='High'; Script=$null; Details='ADR speeds crash recovery/long rollback. Size PVS in-DB or on a dedicated filegroup before enabling; monitor growth post-cutover.' }
    @{ StepID='P3-05'; PhaseID='P3'; PhaseName='Build & Configure Target'; Task='Install ODBC Driver 18 and OLE DB Driver 19 on application servers'; Priority='Critical'; Script=$null; Details='Required - SNAC removed in SQL Server 2022.' }
    @{ StepID='P3-06'; PhaseID='P3'; PhaseName='Build & Configure Target'; Task='Configure firewall (1433, AG 5022), AV exclusions, monitoring'; Priority='High'; Script=$null; Details='Extend alerting to target before cutover.' }
    @{ StepID='P3-07'; PhaseID='P3'; PhaseName='Build & Configure Target'; Task='Validate backup/restore to disk/share/S3 on empty target'; Priority='High'; Script='14_backup_chain_verification.sql'; Details='Run after first test backup on target.' }
    @{ StepID='P3-08'; PhaseID='P3'; PhaseName='Build & Configure Target'; Task='Install linked-server / OLEDB / Oracle (or other) providers on TARGET'; Priority='High'; Script=$null; Details='Required before recreating non-SQL linked servers. Validate connectivity after firewall rules are open.' }
    @{ StepID='P3-09'; PhaseID='P3'; PhaseName='Build & Configure Target'; Task='Configure Database Mail (enable feature, profiles, operators)'; Priority='High'; Script=$null; Details='Database Mail is off by default. Recreate profiles/accounts from SOURCE so Agent alerts work on day 1.' }
    @{ StepID='P3-10'; PhaseID='P3'; PhaseName='Build & Configure Target'; Task='Install/upgrade SSIS (and SSRS/SSAS if used) to 2022 on target tier'; Priority='Critical'; Script=$null; Details='Do not keep SSIS 2016 runtime against SQL 2022 as the long-term state. Redeploy packages; update connection managers to ODBC 18 / OLE DB 19.' }
    @{ StepID='P3-11'; PhaseID='P3'; PhaseName='Build & Configure Target'; Task='Deploy/upgrade monitoring + backup agents certified for SQL 2022'; Priority='High'; Script=$null; Details='Install vendor-supported monitoring and backup agents on TARGET; prove backup/restore and alert paths in UAT.' }

    @{ StepID='P4-01'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='Restore production backup to UAT 2022 instance (WITH MOVE; time the restore)'; Priority='Critical'; Script=$null; Details='Use WITH MOVE for new paths. Record restore duration - feeds cutover downtime budget. Restore TDE certs first if encrypted.' }
    @{ StepID='P4-02'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='Migrate logins and fix orphaned users on UAT'; Priority='Critical'; Script='08_orphaned_users_precheck.sql'; Details='Prefer dbatools Export/Import-DbaLogin or sp_help_revlogin (same SID). Validate app authentication paths on UAT before prod.' }
    @{ StepID='P4-03'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='Enable Query Store on UAT databases before compat level changes'; Priority='High'; Script='19_query_store_enable_and_status.sql'; Details='Use for plan regression detection during compat testing.' }
    @{ StepID='P4-04'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='Test compatibility levels 130 -> 140/150 -> 160 incrementally'; Priority='Critical'; Script='20_compatibility_level_report.sql'; Details='Do not jump to 160 on cutover day unless UAT proves zero regressions.' }
    @{ StepID='P4-05'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='Run DBCC CHECKDB on all restored UAT databases'; Priority='Critical'; Script='24_post_restore_checkdb_and_stats.sql'; Details='Verify integrity after backup/restore/file copy. Fix corruption before app testing.' }
    @{ StepID='P4-06'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='Update statistics on UAT after restore'; Priority='High'; Script='24_post_restore_checkdb_and_stats.sql'; Details='sp_updatestats or Ola Hallengren stats jobs - improves first-day plan quality on new instance.' }
    @{ StepID='P4-07'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='Run application regression and performance tests'; Priority='Critical'; Script='18_post_migration_validation.sql'; Details='Compare top queries vs 2016 baseline. Sign-off from app owners.' }
    @{ StepID='P4-08'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='Test string truncation / ANSI_WARNINGS and insert overflow behavior'; Priority='High'; Script=$null; Details='Apps that relied on silent truncation into shorter varchar/nvarchar columns can fail differently after upgrade. Include overflow/truncation cases in UAT.' }
    @{ StepID='P4-09'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='Test ORM-generated queries and ETL/SSIS packages on 2022'; Priority='Critical'; Script=$null; Details='Execute critical ORM paths and SSIS packages end-to-end. Fix deprecated SQL / connection managers before prod.' }
    @{ StepID='P4-10'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='Test linked servers to down-level SQL (2008/2012/2014) if still required'; Priority='High'; Script='09_linked_servers_and_jobs.sql'; Details='Use OLE DB Driver 19 / ODBC 18. Expect TLS and provider issues to old engines - prove or retire those linked servers.' }
    @{ StepID='P4-11'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='Validate backup-software restore of a 2022 backup'; Priority='Critical'; Script='14_backup_chain_verification.sql'; Details='Native or third-party: full backup on 2022 UAT then restore successfully. Block cutover if vendor tool cannot restore.' }
    @{ StepID='P4-12'; PhaseID='P4'; PhaseName='UAT Pilot'; Task='UAT / business sign-off matrix (all stakeholders approve)'; Priority='Critical'; Script=$null; Details='Required approvers: Application, DBA, Business, Infrastructure, Security, Vendor (if any), Management. No production cutover without written sign-off.' }

    @{ StepID='P5-01'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Re-run DMA / readiness scripts on production (read-only)'; Priority='Critical'; Script='13_pre_migration_readiness.sql'; Details='Freeze schema changes 2 weeks before cutover.' }
    @{ StepID='P5-02'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Verify full/diff/log backup chain for all databases'; Priority='Critical'; Script='14_backup_chain_verification.sql'; Details='Test restore on target. Backup TDE certs and SMK.' }
    @{ StepID='P5-03'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Patch SOURCE if possible; ensure TARGET has latest CU'; Priority='High'; Script='01_instance_version_and_patch.sql'; Details='Microsoft recommends patching source before migrate. If source cannot be patched, increase UAT validation and always CU-patch TARGET.' }
    @{ StepID='P5-04'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Migrate logins to prod TARGET (before database restore)'; Priority='Critical'; Script='07_logins_and_server_roles.sql'; Details='Use dbatools or sp_help_revlogin so SIDs match and orphans are minimized. Do this before restoring user databases.' }
    @{ StepID='P5-05'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Restore TDE certificates/keys to TARGET (before encrypted DB restore)'; Priority='Critical'; Script='23_tde_certificate_inventory.sql'; Details='Without certs, TDE databases will not come ONLINE. Backup cert + private key from SOURCE; restore on TARGET first.' }
    @{ StepID='P5-06'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Script and stage Agent jobs + maintenance plans on TARGET (disabled)'; Priority='High'; Script='09_linked_servers_and_jobs.sql'; Details='Recreate jobs/maintenance plans from SOURCE via SSMS Object Explorer Details or SSIS Transfer Jobs. Keep disabled until cutover.' }
    @{ StepID='P5-07'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Recreate linked servers on TARGET and test'; Priority='High'; Script='09_linked_servers_and_jobs.sql'; Details='Script from SOURCE; install providers first. Test SQL and non-SQL (e.g. Oracle) linked queries. Retest any links to SQL 2008/2012.' }
    @{ StepID='P5-08'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Rebuild replication on 2022 - upgrade/re-home old subscribers first'; Priority='High'; Script='06_ha_dr_topology.sql'; Details='Do not leave SQL 2022 publishing to unsupported old subscribers. Upgrade subscribers or move them off before cutover.' }
    @{ StepID='P5-09'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Configure log shipping or AG sync to 2022 target'; Priority='High'; Script='22_ag_health_check.sql'; Details='Monitor lag until consistently within SLA.' }
    @{ StepID='P5-10'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Prepare cutover runbook with rollback triggers and war-room contacts'; Priority='Critical'; Script=$null; Details='Include Option A (compat 130 hold) vs Option B (reverse replication). Document that 2022 DBs cannot restore to 2016.' }
    @{ StepID='P5-11'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Dry-run tabletop exercise with all stakeholders'; Priority='High'; Script=$null; Details='Walk through go/no-go, rollback, and communication plan.' }
    @{ StepID='P5-12'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Disaster recovery validation (failover, restore, TDE, failback, master, logins)'; Priority='Critical'; Script='22_ag_health_check.sql'; Details='Prove: AG failover works; backup restore works; TDE DB restores with cert; failback path known; master recovery plan; login rebuild from export.' }
    @{ StepID='P5-13'; PhaseID='P5'; PhaseName='Production Preparation'; Task='Backup system databases (master, msdb, model) on SOURCE'; Priority='Critical'; Script=$null; Details='Take fresh master/msdb/model backups before cutover for forensics and instance rebuild. Store offline with TDE certs.' }

    @{ StepID='P6-01'; PhaseID='P6'; PhaseName='Cutover'; Task='Go/No-Go decision - confirm replication lag and backups current'; Priority='Critical'; Script='22_ag_health_check.sql'; Details='Abort if lag exceeds SLA or readiness script shows blockers.' }
    @{ StepID='P6-02'; PhaseID='P6'; PhaseName='Cutover'; Task='Capture pre-cutover baseline on SOURCE (T-30 min)'; Priority='Critical'; Script='16_pre_cutover_baseline.sql'; Details='Save wait stats, blocking, and active requests for comparison.' }
    @{ StepID='P6-03'; PhaseID='P6'; PhaseName='Cutover'; Task='Stop applications / read-only mode; disable non-critical Agent jobs on SOURCE'; Priority='Critical'; Script=$null; Details='Notify users; freeze writes.' }
    @{ StepID='P6-04'; PhaseID='P6'; PhaseName='Cutover'; Task='Final log backup / AG sync; restore WITH RECOVERY or failover to 2022'; Priority='Critical'; Script=$null; Details='Follow side-by-side or AG runbook exactly. Use WITH MOVE if paths differ. Confirm TDE certs already on TARGET.' }
    @{ StepID='P6-05'; PhaseID='P6'; PhaseName='Cutover'; Task='Run cutover validation on TARGET before connection switch'; Priority='Critical'; Script='17_cutover_validation.sql'; Details='Verify version 16.x, databases ONLINE, Agent running.' }
    @{ StepID='P6-06'; PhaseID='P6'; PhaseName='Cutover'; Task='Run DBCC CHECKDB on critical/user databases on TARGET'; Priority='Critical'; Script='24_post_restore_checkdb_and_stats.sql'; Details='Strongly recommended after restore - catch corruption from backup/transfer before go-live.' }
    @{ StepID='P6-07'; PhaseID='P6'; PhaseName='Cutover'; Task='Run orphaned user check and fix on TARGET'; Priority='Critical'; Script='08_orphaned_users_precheck.sql'; Details='Apply generated ALTER USER scripts after review.' }
    @{ StepID='P6-08'; PhaseID='P6'; PhaseName='Cutover'; Task='Switch DNS/listener/connection strings to 2022 TARGET'; Priority='Critical'; Script=$null; Details='Coordinate connection pool drain with app teams.' }
    @{ StepID='P6-09'; PhaseID='P6'; PhaseName='Cutover'; Task='Enable Agent jobs / maintenance plans on TARGET; smoke-test critical transactions'; Priority='Critical'; Script=$null; Details='Rollback if P1 failure within first 4 hours (see Phase P8).' }
    @{ StepID='P6-10'; PhaseID='P6'; PhaseName='Cutover'; Task='Smoke-test critical stored procedures and app entry points'; Priority='Critical'; Script=$null; Details='Execute agreed critical SP/API list from app owners. Confirm success before declaring cutover complete.' }

    @{ StepID='P7-01'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='Day-1 post-migration validation'; Priority='Critical'; Script='18_post_migration_validation.sql'; Details='Also run Prod_Migration/02_Upgrade_Validation/04_complete_post_upgrade_configuration_report.sql' }
    @{ StepID='P7-02'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='Update statistics on all user databases (post-cutover)'; Priority='High'; Script='24_post_restore_checkdb_and_stats.sql'; Details='Recommended by field practice after version move - improves optimizer estimates on new engine.' }
    @{ StepID='P7-03'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='Optional index rebuild/reorganize during approved window'; Priority='Medium'; Script=$null; Details='MSSQLTips/field guidance: use downtime to clean indexes if window allows. Prefer Ola Hallengren; do not block go-live on this.' }
    @{ StepID='P7-04'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='Verify Query Store enabled; monitor plan regressions'; Priority='High'; Script='19_query_store_enable_and_status.sql'; Details='Run Prod_Migration/06_Optimizer_Plans/03_query_store_regression.sql if slowness reported.' }
    @{ StepID='P7-05'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='Hold user DBs at compat 130 for 7-14 days (Option A backout)'; Priority='Critical'; Script='20_compatibility_level_report.sql'; Details='Phased Compatibility Isolation: stay on 2022 engine at level 130. Optimizer/syntax rollback = scoped config or compat change - NOT restore to 2016.' }
    @{ StepID='P7-06'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='Validate backups succeed on 2022 and test restore'; Priority='Critical'; Script='14_backup_chain_verification.sql'; Details='First full backup post-migration must succeed. Note: 2022 backups cannot restore to 2016.' }
    @{ StepID='P7-07'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='Monitor waits, blocking, TempDB for 2 weeks'; Priority='High'; Script='16_pre_cutover_baseline.sql'; Details='Compare to pre-cutover baseline. Use Prod_Migration playbook if needed.' }
    @{ StepID='P7-08'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='First 24 hours monitoring dashboard checklist'; Priority='Critical'; Script='16_pre_cutover_baseline.sql'; Details='Watch: CPU, Memory, PLE, waits, blocking, failed logins, backup jobs, AG health, Agent failures, TempDB, version store/PVS, top Query Store regressions.' }
    @{ StepID='P7-09'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='Days 2-7 monitoring and regression review'; Priority='High'; Script='19_query_store_enable_and_status.sql'; Details='Daily review of top regressions, job failures, and capacity. Escalate if P1 trends worsen vs baseline.' }
    @{ StepID='P7-10'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='Keep SOURCE instance recoverable 30+ days before decommission'; Priority='High'; Script=$null; Details='Required for connection rollback and forensic comparison. Physical data failback after writes needs Option B (replication 2022->2016), not restore.' }
    @{ StepID='P7-11'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='Update runbooks, diagrams, monitoring docs, and CMDB for 2022'; Priority='High'; Script=$null; Details='Document new instance names, listeners, backup jobs, AG topology, and support contacts. Archive pre-migration evidence.' }
    @{ StepID='P7-12'; PhaseID='P7'; PhaseName='Post-Migration Stabilization'; Task='Plan staged compatibility raise toward 160 (after Query Store baseline)'; Priority='High'; Script='20_compatibility_level_report.sql'; Details='After 7-14 days stable at 130, raise 140/150 then 160 with Query Store regression checks - not on cutover night.' }

    @{ StepID='P8-01'; PhaseID='P8'; PhaseName='Rollback & Incident Response'; Task='Capture rollback evidence (incl. database scoped configs)'; Priority='Critical'; Script='21_rollback_evidence_capture.sql'; Details='Includes LEGACY_CARDINALITY_ESTIMATION, PARAMETER_SNIFFING, PSP, QUERY_OPTIMIZER_HOTFIXES. Save all result sets.' }
    @{ StepID='P8-02'; PhaseID='P8'; PhaseName='Rollback & Incident Response'; Task='Option A - optimizer rollback via compat/scoped config on 2022'; Priority='Critical'; Script='20_compatibility_level_report.sql'; Details='Preferred: keep traffic on 2022; set LEGACY_CARDINALITY_ESTIMATION or lower compat. Cannot restore 2022 DB to 2016.' }
    @{ StepID='P8-03'; PhaseID='P8'; PhaseName='Rollback & Incident Response'; Task='Connection rollback - redirect apps to 2016 SOURCE (pre-write or Option B)'; Priority='Critical'; Script=$null; Details='Safe only if no critical writes on 2022, or Option B reverse sync is catching them. Update DNS/listener/connection strings.' }
    @{ StepID='P8-04'; PhaseID='P8'; PhaseName='Rollback & Incident Response'; Task='Workload rollback - disable 2022 jobs, re-enable 2016 jobs'; Priority='Critical'; Script='09_linked_servers_and_jobs.sql'; Details='Stop maintenance/ETL causing regression on 2022.' }
    @{ StepID='P8-05'; PhaseID='P8'; PhaseName='Rollback & Incident Response'; Task='Option B - physical failback via reverse replication/ETL (if planned)'; Priority='Critical'; Script='06_ha_dr_topology.sql'; Details='Cannot use AG/log shipping downward. Requires transactional replication 2022->2016 or ETL deltas planned before cutover.' }
    @{ StepID='P8-06'; PhaseID='P8'; PhaseName='Rollback & Incident Response'; Task='Document RCA and update migration plan before retry'; Priority='High'; Script=$null; Details='Timeline, failure category, evidence, corrective action, prevention checklist item.' }
)

# Enrich steps with Risk / Owner / Duration / Success (Priority != Risk)
$ownerByPhase = @{
    'P0' = 'PM / DBA'
    'P1' = 'DBA'
    'P2' = 'Infra / DBA'
    'P3' = 'DBA / Infra'
    'P4' = 'DBA / App'
    'P5' = 'DBA / Change'
    'P6' = 'DBA / App / Network'
    'P7' = 'DBA / App'
    'P8' = 'DBA / Incident'
}
$durationByScript = @{
    '01_instance_version_and_patch.sql' = '5 min'
    '02_server_configuration.sql' = '10 min'
    '03_trace_flags_documentation.sql' = '10 min'
    '04_database_inventory.sql' = '15 min'
    '05_database_features_tde_cdc.sql' = '20 min'
    '06_ha_dr_topology.sql' = '20 min'
    '07_logins_and_server_roles.sql' = '15 min'
    '08_orphaned_users_precheck.sql' = '15-45 min'
    '09_linked_servers_and_jobs.sql' = '20 min'
    '10_deprecated_features_usage.sql' = '15 min'
    '11_stretch_database_check.sql' = '5 min'
    '12_polybase_hadoop_check.sql' = '10 min'
    '13_pre_migration_readiness.sql' = '20 min'
    '14_backup_chain_verification.sql' = '15 min'
    '15_post_install_config_audit.sql' = '20 min'
    '16_pre_cutover_baseline.sql' = '10 min'
    '17_cutover_validation.sql' = '15 min'
    '18_post_migration_validation.sql' = '30-60 min'
    '19_query_store_enable_and_status.sql' = '15-30 min'
    '20_compatibility_level_report.sql' = '10 min'
    '21_rollback_evidence_capture.sql' = '15 min'
    '22_ag_health_check.sql' = '10 min'
    '23_tde_certificate_inventory.sql' = '15 min'
    '24_post_restore_checkdb_and_stats.sql' = '30 min - several hrs'
}
$riskOverrides = @{
    'P3-03' = 'Medium'   # TempDB metadata - ops change, restart
    'P4-04' = 'Critical' # compat raise
    'P6-03' = 'Low'      # disable jobs
    'P7-03' = 'Medium'   # hold at 130 is protective
    'P8-02' = 'Medium'   # scoped config rollback
    'P8-03' = 'High'     # connection rollback
    'P8-05' = 'Critical' # physical failback
}
$successDefaults = @{
    'P1-14' = 'No FAIL blockers; WARN items owned with due dates'
    'P3-01' = 'ProductUpdateLevel = latest CU (not RTM)'
    'P4-03' = 'Query Store actual_state = READ_WRITE; no ERROR'
    'P4-06' = 'All stakeholder signatures captured and archived'
    'P5-06' = 'AG failover, restore, TDE restore, failback, master/login rebuild proven in UAT'
    'P6-01' = 'All cutover gate boxes green; war-room GO recorded'
    'P6-05' = 'Version 16.x; all user DBs ONLINE; Agent running'
    'P7-07' = 'No P1 alerts; metrics within baseline bands for 24h'
    'P8-01' = 'Evidence bundle saved with scoped configs + waits + error log'
}

foreach ($s in $steps) {
    $s['Status'] = 'Pending'
    if (-not $s.ContainsKey('Risk') -or -not $s['Risk']) {
        $s['Risk'] = if ($riskOverrides.ContainsKey($s.StepID)) { $riskOverrides[$s.StepID] } else { $s.Priority }
    }
    if (-not $s.ContainsKey('Owner') -or -not $s['Owner']) {
        $s['Owner'] = $ownerByPhase[$s.PhaseID]
    }
    if (-not $s.ContainsKey('Duration') -or -not $s['Duration']) {
        if ($s.Script -and $durationByScript.ContainsKey($s.Script)) {
            $s['Duration'] = $durationByScript[$s.Script]
        } else {
            $s['Duration'] = '30-60 min'
        }
    }
    if (-not $s.ContainsKey('Success') -or -not $s['Success']) {
        if ($successDefaults.ContainsKey($s.StepID)) {
            $s['Success'] = $successDefaults[$s.StepID]
        } elseif ($s.Script) {
            $s['Success'] = 'Script completes without error; output archived as evidence'
        } else {
            $s['Success'] = 'Task completed and documented in change record'
        }
    }
    if (-not $s.ContainsKey('Prereq') -or -not $s['Prereq']) {
        if ($s.Script) {
            $s['Prereq'] = 'sysadmin (or VIEW SERVER STATE); prefer SOURCE for discovery / TARGET for post-cutover; read-only unless noted'
        } else {
            $s['Prereq'] = 'Stakeholder availability; change ticket approved where required'
        }
    }
}

$phaseGates = @{
    'P0' = @('Executive approval + licensing confirmed','Vendor/app certification matrix complete','Third-party tool matrix complete (monitor/backup/ORM/SSIS/repl/linked)','Migration strategy chosen','Maintenance window scheduled','RACI owners assigned')
    'P1' = @('DMA / readiness clean of FAIL blockers','Backups verified','CHECKDB clean on critical DBs','No ActiveX Agent steps (or remediated)','Monitoring/backup/ORM/SSIS/repl inventories done','App connection inventory complete','Client driver plan signed','Hardware / capacity plan delivered','Security approved')
    'P2' = @('Target architecture signed off','.NET 4.8+ and infra/ISO ready','Collation / naming / DNS plan approved','TempDB and storage design complete','Linked-server ports/providers planned','Rollback connection abstraction defined')
    'P3' = @('SQL 2022 installed','Latest CU installed (not RTM)','TempDB configured','MAXDOP / memory configured','Instant File Init granted','LPIM evaluated','Database Mail configured','SSIS 2022 installed if used','Monitoring + backup agents on target','Linked-server providers installed')
    'P4' = @('UAT restore successful (timed)','Orphans fixed','CHECKDB clean','Statistics updated','Query Store ON (READ_WRITE)','Compat staging tested','ORM/SSIS tested','Down-level linked servers tested','Backup-software restore of 2022 backup OK','Truncation/overflow cases tested','App regression signed','UAT sign-off matrix complete')
    'P5' = @('Final readiness clean','Backup chain current','System DBs backed up on SOURCE','Logins migrated to TARGET','TDE certs on TARGET','Jobs/maintenance plans staged','Linked servers tested','Replication subscribers upgraded/re-homed','Sync lag within SLA','Cutover runbook ready','Tabletop completed','DR validation proven')
    'P6' = @('Final log backup / AG sync OK','Restore or failover verified','CHECKDB clean on TARGET','Jobs enabled as planned','Critical SPs/app smoke tests OK','AG healthy (if used)','DNS / listener prepared','Monitoring ready','Rollback path tested')
    'P7' = @('Day-1 validation green','Statistics refreshed','Query Store capturing','Compat held at 130 (unless UAT approved higher)','Compat-160 raise plan documented','Docs/CMDB updated','First full backup on 2022 OK','24h monitoring complete')
    'P8' = @('Evidence captured before traffic move','Failure category assigned','Rollback level chosen (A then escalate)','RCA logged before retry')
}
$phaseGatesJson = ($phaseGates | ConvertTo-Json -Compress)

$stepsJson = ($steps | ConvertTo-Json -Depth 6 -Compress)

$scriptContentsJs = ($scriptFiles.GetEnumerator() | ForEach-Object {
    '  "' + ($_.Key -replace '\\', '\\\\') + '": "' + (Escape-Js $_.Value) + '"'
}) -join ",`n"

$phaseNav = @(
    @{ Id='P0'; Name='Initiation'; Icon='&#128203;' }
    @{ Id='P1'; Name='Discovery'; Icon='&#128269;' }
    @{ Id='P2'; Name='Target Design'; Icon='&#128736;' }
    @{ Id='P3'; Name='Build Target'; Icon='&#128640;' }
    @{ Id='P4'; Name='UAT Pilot'; Icon='&#128300;' }
    @{ Id='P5'; Name='Prod Prep'; Icon='&#128221;' }
    @{ Id='P6'; Name='Cutover'; Icon='&#9889;' }
    @{ Id='P7'; Name='Stabilization'; Icon='&#128200;' }
    @{ Id='P8'; Name='Rollback'; Icon='&#9194;' }
)

$html = @"
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SQL Server 2016 to 2022 Migration Checklist</title>
<style>
:root {
  --bg-primary:#0f1419; --bg-secondary:#1a1f2e; --bg-card:#1e2538; --bg-hover:#263044;
  --text-primary:#e1e5ee; --text-secondary:#8892a4; --accent:#3b82f6; --accent-hover:#2563eb;
  --accent-light:rgba(59,130,246,0.15); --success:#22c55e; --warning:#f59e0b; --danger:#ef4444;
  --border:#2d3748; --sidebar-width:280px; --header-height:64px;
}
[data-theme="light"] {
  --bg-primary:#f0f2f5; --bg-secondary:#ffffff; --bg-card:#ffffff; --bg-hover:#f5f7fa;
  --text-primary:#1a202c; --text-secondary:#4a5568; --accent:#2563eb; --accent-hover:#1d4ed8;
  --accent-light:rgba(37,99,235,0.08); --border:#e2e8f0;
}
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Segoe UI',system-ui,sans-serif; background:var(--bg-primary); color:var(--text-primary); }
.header {
  position:fixed; top:0; left:0; right:0; height:var(--header-height);
  background:var(--bg-secondary); border-bottom:1px solid var(--border);
  display:grid; grid-template-columns:1fr auto 1fr; align-items:center;
  padding:0 24px; z-index:1000; gap:12px;
}
.header-left { display:flex; align-items:center; justify-self:start; }
.header-brand { text-align:center; justify-self:center; }
.header-brand h1 { font-size:17px; font-weight:700; line-height:1.25; margin:0; }
.header-brand .subtitle { font-size:11px; color:var(--text-secondary); text-transform:uppercase; letter-spacing:0.5px; margin-top:2px; }
.header-actions { display:flex; gap:8px; align-items:center; justify-self:end; }
.btn-icon {
  width:36px; height:36px; border-radius:8px; border:1px solid var(--border);
  background:var(--bg-card); color:var(--text-secondary); cursor:pointer; font-size:14px;
}
.btn-icon:hover { border-color:var(--accent); color:var(--text-primary); }
.btn-accent {
  padding:6px 14px; border-radius:8px; border:none; background:var(--accent); color:#fff;
  cursor:pointer; font-size:13px; font-weight:500;
}
.sidebar {
  position:fixed; top:var(--header-height); left:0; bottom:0; width:var(--sidebar-width);
  background:var(--bg-secondary); border-right:1px solid var(--border); overflow-y:auto; z-index:900;
}
.sidebar-item {
  display:flex; align-items:center; gap:10px; padding:10px 20px; cursor:pointer;
  font-size:13px; color:var(--text-secondary); border-left:3px solid transparent;
}
.sidebar-item:hover { background:var(--bg-hover); color:var(--text-primary); }
.sidebar-item.active { background:var(--accent-light); color:var(--accent); border-left-color:var(--accent); font-weight:600; }
.sidebar-item .badge { margin-left:auto; font-size:10px; padding:2px 6px; border-radius:10px; background:var(--accent-light); color:var(--accent); }
.main-content { margin-left:var(--sidebar-width); margin-top:var(--header-height); padding:24px; min-height:calc(100vh - var(--header-height)); }
.section-page { display:none; max-width:1100px; }
.section-page.active { display:block; }
.page-header { margin-bottom:20px; }
.page-header h2 { font-size:22px; font-weight:700; margin-bottom:6px; }
.page-header p { color:var(--text-secondary); font-size:14px; }
.progress-wrap { background:var(--bg-card); border:1px solid var(--border); border-radius:12px; padding:16px 20px; margin-bottom:20px; }
.progress-bar-container { height:8px; background:var(--border); border-radius:4px; overflow:hidden; margin-top:8px; }
.progress-bar-fill { height:100%; background:linear-gradient(90deg,var(--accent),var(--success)); width:0%; transition:width 0.4s; }
.card-box { background:var(--bg-card); border:1px solid var(--border); border-radius:12px; padding:20px; margin-bottom:16px; }
.card-box h3 { font-size:15px; font-weight:600; margin-bottom:12px; }
.checklist-item { display:flex; align-items:flex-start; gap:10px; padding:12px 0; border-bottom:1px solid var(--border); }
.checklist-item:last-child { border-bottom:none; }
.checklist-item input[type="checkbox"] { width:18px; height:18px; margin-top:2px; accent-color:var(--accent); flex-shrink:0; cursor:pointer; }
.checklist-item .item-content { flex:1; }
.checklist-item .item-text { font-size:14px; line-height:1.5; }
.checklist-item .item-details { font-size:12px; color:var(--text-secondary); margin-top:6px; line-height:1.45; }
.checklist-item .item-script {
  display:inline-flex; align-items:center; gap:4px; margin-top:6px; font-size:11px;
  color:var(--accent); background:var(--accent-light); padding:3px 10px; border-radius:4px;
  font-family:'Cascadia Code','Consolas',monospace; cursor:pointer;
}
.checklist-item .item-script:hover { background:var(--accent); color:#fff; }
.priority-badge { display:inline-block; font-size:10px; font-weight:600; padding:2px 8px; border-radius:4px; text-transform:uppercase; margin-top:4px; }
.priority-critical { background:rgba(239,68,68,0.15); color:var(--danger); }
.priority-high { background:rgba(245,158,11,0.15); color:var(--warning); }
.priority-medium { background:rgba(59,130,246,0.15); color:var(--accent); }
.priority-low { background:rgba(34,197,94,0.12); color:var(--success); }
.meta-row { display:flex; flex-wrap:wrap; gap:6px; margin-top:6px; }
.meta-chip { font-size:10px; padding:2px 8px; border-radius:4px; border:1px solid var(--border); color:var(--text-secondary); background:var(--bg-hover); }
.gate-box {
  background:var(--bg-card); border:1px solid var(--border); border-left:4px solid var(--success);
  border-radius:0 12px 12px 0; padding:14px 18px; margin-bottom:16px; font-size:13px;
}
.gate-box h3 { font-size:14px; margin-bottom:8px; }
.gate-box ul { margin:0 0 8px 18px; color:var(--text-secondary); line-height:1.55; }
.gate-box .gate-stop { color:var(--danger); font-weight:600; margin:0; }
.flow-box { font-family:'Cascadia Code','Consolas',monospace; font-size:12px; line-height:1.45;
  background:#1e1e1e; color:#d4d4d4; padding:14px 16px; border-radius:8px; overflow:auto; white-space:pre; }
.operator-bar { display:flex; gap:10px; align-items:center; flex-wrap:wrap; margin-bottom:12px; font-size:13px; }
.operator-bar input {
  padding:6px 10px; border-radius:6px; border:1px solid var(--border);
  background:var(--bg-hover); color:var(--text-primary); min-width:180px;
}
.script-viewer-overlay { display:none; position:fixed; inset:0; background:rgba(0,0,0,0.7); z-index:3000; align-items:center; justify-content:center; padding:20px; }
.script-viewer-overlay.active { display:flex; }
.script-viewer { width:95vw; max-width:1100px; max-height:90vh; background:var(--bg-card); border:1px solid var(--border); border-radius:12px; display:flex; flex-direction:column; overflow:hidden; }
.script-viewer-header { display:flex; justify-content:space-between; align-items:center; padding:14px 20px; border-bottom:1px solid var(--border); }
.script-viewer-body { flex:1; overflow:auto; }
.sql-code { margin:0; padding:16px 20px; font-family:'Cascadia Code','Consolas',monospace; font-size:12px; line-height:1.6; white-space:pre; background:#1e1e1e; color:#d4d4d4; }
.copy-btn { padding:4px 10px; border-radius:6px; border:1px solid var(--border); background:var(--bg-hover); cursor:pointer; font-size:11px; }
.note { background:var(--accent-light); border-left:4px solid var(--accent); padding:12px 16px; border-radius:0 8px 8px 0; font-size:13px; margin-bottom:16px; }
.changes-header { display:flex; align-items:center; justify-content:space-between; gap:12px; margin-bottom:12px; flex-wrap:wrap; }
.changes-header h3 { margin:0; }
.changes-actions { display:flex; gap:6px; }
.btn-sm {
  padding:4px 10px; border-radius:6px; border:1px solid var(--border); background:var(--bg-hover);
  color:var(--text-secondary); cursor:pointer; font-size:11px;
}
.btn-sm:hover { border-color:var(--accent); color:var(--text-primary); }
.change-item {
  border:1px solid var(--border); border-radius:8px; margin-bottom:8px; overflow:hidden;
  background:var(--bg-hover);
}
.change-item:last-child { margin-bottom:0; }
.change-summary {
  display:flex; align-items:center; gap:10px; width:100%; padding:10px 14px;
  cursor:pointer; background:transparent; border:none; color:var(--text-primary);
  text-align:left; font-size:13px; font-family:inherit;
}
.change-summary:hover { background:var(--accent-light); }
.change-chevron {
  flex-shrink:0; width:16px; color:var(--text-secondary); font-size:11px;
  transition:transform 0.2s;
}
.change-item.open .change-chevron { transform:rotate(90deg); }
.change-title { flex:1; font-weight:500; line-height:1.35; min-width:0; }
.change-tag {
  flex-shrink:0; font-size:10px; font-weight:700; padding:2px 8px; border-radius:4px;
  text-transform:uppercase; letter-spacing:0.3px;
}
.tag-blocker { background:rgba(239,68,68,0.15); color:var(--danger); }
.tag-behavior { background:rgba(245,158,11,0.15); color:var(--warning); }
.tag-feature { background:rgba(59,130,246,0.15); color:var(--accent); }
.tag-ops { background:rgba(34,197,94,0.15); color:var(--success); }
.change-body {
  display:none; padding:0 14px 14px 40px; border-top:1px solid var(--border);
  font-size:12px; color:var(--text-secondary); line-height:1.55;
}
.change-item.open .change-body { display:block; padding-top:12px; }
.change-body strong { color:var(--text-primary); }
.change-body ul { margin:6px 0 0 18px; }
.change-body li { margin-bottom:4px; }
.change-body .db-action {
  margin-top:8px; padding:8px 10px; border-radius:6px;
  background:var(--accent-light); border-left:3px solid var(--accent); color:var(--text-primary);
}
.note-warn { background:rgba(245,158,11,0.12); border-left:4px solid var(--warning); padding:12px 16px; border-radius:0 8px 8px 0; font-size:13px; margin-bottom:16px; }
.note-danger { background:rgba(239,68,68,0.12); border-left:4px solid var(--danger); padding:12px 16px; border-radius:0 8px 8px 0; font-size:13px; margin-bottom:16px; }
.strategy-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:10px; margin-top:10px; }
.strategy-card {
  border:1px solid var(--border); border-radius:8px; padding:12px 14px; background:var(--bg-hover); font-size:12px; line-height:1.5;
}
.strategy-card h4 { font-size:13px; margin-bottom:6px; color:var(--text-primary); }
.strategy-card .meta { color:var(--text-secondary); margin-bottom:6px; }
.strategy-card ul { margin:0 0 0 16px; color:var(--text-secondary); }
.strategy-card.preferred { border-color:var(--accent); background:var(--accent-light); }
.change-body .script-link {
  display:inline; margin:0 2px; padding:0;
  color:var(--accent); background:transparent; border:none; border-radius:0;
  font-family:'Cascadia Code','Consolas',monospace; font-size:12px; font-weight:600;
  text-decoration:underline; text-underline-offset:2px; cursor:pointer;
}
.change-body .script-link:hover {
  color:var(--accent-hover); background:transparent; text-decoration:underline;
}
.change-body .script-link::after {
  content:' \2197'; font-size:10px; opacity:0.75; text-decoration:none;
}
@media(max-width:768px) { .sidebar { transform:translateX(-100%); } .sidebar.open { transform:translateX(0); } .main-content { margin-left:0; } }
</style>
</head>
<body>
<div class="header">
  <div class="header-left">
    <button class="btn-icon" onclick="document.getElementById('sidebar').classList.toggle('open')" title="Menu">&#9776;</button>
  </div>
  <div class="header-brand">
    <h1>SQL Server 2016 &#8594; 2022 Migration Checklist</h1>
    <div class="subtitle">Enterprise Edition &bull; Interactive Runbook</div>
  </div>
  <div class="header-actions">
    <button class="btn-icon" id="themeBtn" onclick="toggleTheme()" title="Toggle theme">&#127769;</button>
    <button class="btn-accent" onclick="exportExcel()" title="Multi-sheet Excel workbook">Export Excel</button>
    <button class="btn-accent" onclick="exportCsv()">Export CSV</button>
    <button class="btn-accent" onclick="exportSummary()" style="background:var(--success)">Summary</button>
    <button class="btn-accent" onclick="resetProgress()" style="background:var(--danger)">Reset</button>
  </div>
</div>
<nav class="sidebar" id="sidebar">
  <div style="padding:12px 20px;font-size:10px;font-weight:700;text-transform:uppercase;color:var(--text-secondary);">Phases</div>
$(($phaseNav | ForEach-Object { @"
  <div class="sidebar-item" data-phase="$($_.Id)" onclick="showPhase('$($_.Id)')"><span>$($_.Icon)</span> $($_.Name) <span class="badge" id="badge-$($_.Id)">0/0</span></div>
"@ }) -join "`n")
  <div style="padding:12px 20px;font-size:10px;font-weight:700;text-transform:uppercase;color:var(--text-secondary);margin-top:8px;">Reference</div>
  <div class="sidebar-item" onclick="showPhase('dashboard')"><span>&#128202;</span> Dashboard</div>
  <div class="sidebar-item" onclick="showPhase('scripts')"><span>&#128451;</span> Script Library</div>
</nav>
<main class="main-content">
  <div class="section-page active" id="page-dashboard">
    <div class="page-header">
      <h2>Migration Dashboard</h2>
      <p>SQL Server 2016 Enterprise to 2022 Enterprise - interactive runbook with discovery, cutover, validation, and rollback scripts.</p>
    </div>
    <div class="note">
      <strong>Excel export:</strong> Use <em>Export Excel</em> for a formatted multi-sheet workbook
      (frozen headers, AutoFilter, color-coded Done/Priority/Risk, column widths, landscape print).
      Downloads a real <code>.xlsx</code> workbook (Open XML) that Excel opens natively.
      Progress checkboxes in this HTML are included as Done = Y/N.
    </div>
    <div class="progress-wrap">
      <div class="operator-bar">
        <label for="operatorName"><strong>Operator:</strong></label>
        <input id="operatorName" type="text" placeholder="Your name (saved for Summary export)" onchange="saveOperator()" />
        <span style="color:var(--text-secondary);font-size:12px;">Used in migration summary report</span>
      </div>
      <div style="display:flex;justify-content:space-between;font-size:13px;"><span>Overall Progress</span><span id="progressPct">0%</span></div>
      <div class="progress-bar-container"><div class="progress-bar-fill" id="progressBar"></div></div>
      <div style="font-size:12px;color:var(--text-secondary);margin-top:8px;" id="progressCount">0 / 0 steps complete</div>
    </div>

    <div class="card-box">
      <h3>Why migrate off SQL Server 2016?</h3>
      <p style="font-size:13px;line-height:1.55;margin-bottom:10px;color:var(--text-secondary);">
        SQL Server 2016 reached <strong style="color:var(--text-primary);">end of extended support on July 14, 2026</strong>. After that date Microsoft no longer provides security updates, cumulative updates, or standard product support for 2016. Continuing to run unsupported database engines is a business, compliance, and operational risk - not just a technical preference.
      </p>
      <div class="note-danger">
        <strong>Why it is crucial to move ASAP:</strong>
        <ul style="margin:8px 0 0 18px;color:var(--text-primary);">
          <li><strong>No security patches</strong> - newly discovered CVEs will not be fixed on 2016; exposed instances become permanent attack targets.</li>
          <li><strong>Compliance / audit failure</strong> - many frameworks (ISO, SOC2, PCI, HIPAA, internal IT policy) require supported platforms; auditors flag EOL databases.</li>
          <li><strong>No Microsoft support for Sev-A incidents</strong> - production outages may leave you without vendor escalation paths.</li>
          <li><strong>Insurance and cyber coverage risk</strong> - some policies limit payouts when known-unsupported software is in use.</li>
          <li><strong>Vendor / application pressure</strong> - ISVs certify newer SQL versions only; delayed migration blocks app upgrades.</li>
          <li><strong>Skills and tooling decay</strong> - monitoring, drivers, and SSMS features increasingly assume 2019/2022+.</li>
        </ul>
      </div>
      <div class="note-warn">
        <strong>What happens if you do not migrate soon?</strong> Short term you may still run fine. Medium term you accumulate unpatched risk and fail audits. Long term you face forced emergency migration under incident pressure (ransomware, compliance deadline, hardware failure) with no rollback runway and no vendor help - the most expensive and risky way to upgrade.
      </div>
    </div>

    <div class="card-box">
      <h3>Migration strategy - choose based on risk, downtime, and rollback needs</h3>
      <p style="font-size:13px;line-height:1.55;margin-bottom:8px;color:var(--text-secondary);">
        Do <strong style="color:var(--text-primary);">not</strong> pick a method only because it is popular. Match the approach to RTO/RPO, database size, HA topology, application certification, and how easily you must roll back. Microsoft supports a direct upgrade path from <strong style="color:var(--text-primary);">SQL Server 2016 SP3+</strong> to 2022, but production teams often prefer side-by-side for safer rollback.
      </p>
      <div class="strategy-grid">
        <div class="strategy-card preferred">
          <h4>A. Side-by-side + backup/restore</h4>
          <div class="meta">Downtime: medium &bull; Rollback: easy &bull; Risk: low-medium</div>
          <ul>
            <li>Build new Windows + SQL 2022; restore databases; rematch logins.</li>
            <li>Best for: most Enterprise production when downtime window is acceptable.</li>
            <li>Rollback: point apps back to 2016 instance.</li>
          </ul>
        </div>
        <div class="strategy-card preferred">
          <h4>B. Side-by-side + log shipping</h4>
          <div class="meta">Downtime: low &bull; Rollback: easy &bull; Risk: low</div>
          <ul>
            <li>Keep 2022 secondary applying log backups until cutover.</li>
            <li>Best for: large databases needing short cutover.</li>
            <li>Rollback: leave 2016 primary authoritative if go-live fails.</li>
          </ul>
        </div>
        <div class="strategy-card">
          <h4>C. Always On AG migration</h4>
          <div class="meta">Downtime: very low &bull; Rollback: moderate &bull; Risk: medium</div>
          <ul>
            <li>Add 2022 replicas / rebuild AG; failover listener at cutover.</li>
            <li>Best for: existing AG estates that must stay highly available.</li>
            <li>Requires careful WSFC/endpoint/listener redesign on 2022.</li>
          </ul>
        </div>
        <div class="strategy-card">
          <h4>D. In-place upgrade</h4>
          <div class="meta">Downtime: one window &bull; Rollback: hard &bull; Risk: medium-high</div>
          <ul>
            <li>Setup upgrades the same instance (requires 2016 SP3+).</li>
            <li>Best for: non-prod, small systems, strict hardware reuse.</li>
            <li>Rollback is not supported by setup - rely on VM snapshot / rebuild.</li>
          </ul>
        </div>
        <div class="strategy-card">
          <h4>E. Replication / CDC sync cutover</h4>
          <div class="meta">Downtime: low &bull; Rollback: moderate &bull; Risk: medium</div>
          <ul>
            <li>Stream changes to 2022; cut over when lag is inside SLA.</li>
            <li>Best for: very large DBs or selective database migration.</li>
            <li>Higher operational complexity; validate identity and DDL carefully.</li>
          </ul>
        </div>
        <div class="strategy-card">
          <h4>F. Azure MI Link / hybrid migrate</h4>
          <div class="meta">Downtime: varies &bull; Rollback: varies &bull; Risk: low-medium</div>
          <ul>
            <li>Use Managed Instance link or DMA-style migrate for cloud DR/exit.</li>
            <li>Best for: hybrid strategy or future Azure landing zone.</li>
            <li>Still requires driver, cert, and app certification work.</li>
          </ul>
        </div>
      </div>
      <p style="font-size:12px;color:var(--text-secondary);margin-top:12px;line-height:1.5;">
        <strong style="color:var(--text-primary);">How to decide:</strong> If rollback must be fast and you can build new hardware/VMs, prefer <em>A or B</em>. If you already run Always On and need near-zero downtime, evaluate <em>C</em>. Use <em>D</em> only when downtime is approved and a tested full-instance restore/snapshot exists. Use <em>E/F</em> for scale or cloud goals after a successful UAT. Full plan: <code>sql_server/docs/sql_2016_to_2022_migration_plan.md</code>.
      </p>
    </div>

    <div class="card-box">
      <div class="changes-header">
        <h3>Key Changes That May Affect Migration (2016 to 2022)</h3>
        <div class="changes-actions">
          <button type="button" class="btn-sm" onclick="setAllChanges(true)">Expand all</button>
          <button type="button" class="btn-sm" onclick="setAllChanges(false)">Collapse all</button>
        </div>
      </div>
      <p style="font-size:12px;color:var(--text-secondary);margin-bottom:12px;">Click a row to expand. <strong style="color:var(--accent);text-decoration:underline;">Blue underlined script names</strong> are clickable links (open SQL in viewer). Tags: <span class="change-tag tag-blocker">Blocker</span> must fix before/at cutover &nbsp; <span class="change-tag tag-behavior">Behavior</span> plan/CE risk &nbsp; <span class="change-tag tag-feature">Feature</span> optional adopt &nbsp; <span class="change-tag tag-ops">Ops</span> config/HA</p>

      <div class="note-danger" style="margin-bottom:14px;">
        <strong>Myth check (common “breaks in 2022” lists):</strong>
        SQL Agent <em>T-SQL</em> job steps are <strong>not</strong> removed.
        Remote Admin Connections / DAC are <strong>not</strong> removed.
        <code>RAISERROR</code> with formatting still works (prefer <code>THROW</code> for new code).
        What <strong>is</strong> discontinued: <strong>ActiveX</strong> Agent steps, PolyBase <strong>Hadoop</strong>, Stretch DB.
      </div>

      <div class="change-item" id="chg-myths-real">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Real breakers vs myths (Agent, DAC, RAISERROR, TRUSTWORTHY, truncation)</span>
          <span class="change-tag tag-blocker">Blocker</span>
        </button>
        <div class="change-body">
          <div><strong>Removed / will fail:</strong>
            <ul>
              <li><strong>ActiveX Scripting</strong> SQL Agent job steps — convert to CmdExec or PowerShell (not T-SQL steps).</li>
              <li><strong>PolyBase Hadoop/HDFS</strong> external data sources — recreate with S3/Azure/supported connectors.</li>
              <li><strong>Stretch Database</strong> — unstretch before migration.</li>
            </ul>
          </div>
          <div style="margin-top:8px;"><strong>Not removed (ignore bad checklists):</strong>
            <ul>
              <li>SQL Agent <strong>T-SQL</strong> job steps — still fully supported.</li>
              <li><strong>Remote admin connections / DAC</strong> — still available (<code>sp_configure 'remote admin connections'</code>).</li>
              <li><strong>RAISERROR</strong> printf-style formatting — still works; Microsoft prefers <code>THROW</code> for new development.</li>
            </ul>
          </div>
          <div style="margin-top:8px;"><strong>Changed behaviors (test in UAT):</strong>
            <ul>
              <li>Cardinality Estimator / plans when raising compat (130→150/160).</li>
              <li>TempDB metadata concurrency (evaluate memory-optimized TempDB metadata).</li>
              <li>Batch mode on rowstore / memory grants under newer compat + IQP.</li>
              <li>String truncation / ANSI_WARNINGS — apps relying on silent truncation can fail.</li>
              <li>TRUSTWORTHY / cross-db chaining — still supported; treat as security review, not automatic break.</li>
              <li>Trace flags — re-validate; many legacy flags are obsolete on 2022.</li>
              <li>New database / catalog collation choices at install (UTF-8 options).</li>
            </ul>
          </div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Scripts:
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('09_linked_servers_and_jobs.sql')">09_linked_servers_and_jobs.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('12_polybase_hadoop_check.sql')">12_polybase_hadoop_check.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('11_stretch_database_check.sql')">11_stretch_database_check.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('03_trace_flags_documentation.sql')">03_trace_flags_documentation.sql</a>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-thirdparty">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Third-party / tool compatibility (monitoring, backup, ORM, SSIS, replication, linked servers)</span>
          <span class="change-tag tag-ops">Ops</span>
        </button>
        <div class="change-body">
          <div><strong>What breaks in the field:</strong> tools around SQL often lag the engine upgrade.</div>
          <ul>
            <li><strong>Monitoring</strong> — old agents may use deprecated DMVs → upgrade to SQL 2022-supported build.</li>
            <li><strong>Backup software</strong> — may not understand 2022 backup formats → vendor-check + prove restore on UAT.</li>
            <li><strong>ORM frameworks</strong> — may emit deprecated SQL → upgrade ORM and regression-test generated queries.</li>
            <li><strong>SSIS 2016</strong> — SNAC/connection issues → upgrade SSIS to 2022; update connection managers to ODBC 18 / OLE DB 19.</li>
            <li><strong>Replication to older versions</strong> — not a durable topology → upgrade/re-home subscribers before 2022 publisher cutover.</li>
            <li><strong>Linked servers to 2008/2012</strong> — TLS/provider issues → OLE DB 19 / ODBC 18 updates and explicit UAT tests (or retire links).</li>
          </ul>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Complete matrix in P0-05; inventories in P1-20..P1-24; prove in P4-09..P4-11.</li>
              <li>Related scripts:
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('09_linked_servers_and_jobs.sql')">09_linked_servers_and_jobs.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('06_ha_dr_topology.sql')">06_ha_dr_topology.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('14_backup_chain_verification.sql')">14_backup_chain_verification.sql</a>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-snac">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">SQL Server Native Client (SNAC) / SQLOLEDB removed</span>
          <span class="change-tag tag-blocker">Blocker</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> SQLNCLI11 and legacy SQLOLEDB are not shipped with SQL Server 2022 or SSMS 19+. Apps, SSIS, and linked servers using these providers can fail to connect after cutover.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Inventory linked servers and SSIS connection managers for SQLNCLI / SQLOLEDB.</li>
              <li>Replace with Microsoft ODBC Driver 18 or OLE DB Driver 19 on all app/ETL tiers.</li>
              <li>Recreate linked servers with the new provider; retest TLS 1.2+ connectivity.</li>
              <li>Script: <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('09_linked_servers_and_jobs.sql')">09_linked_servers_and_jobs.sql</a></li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-stretch">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Stretch Database discontinued</span>
          <span class="change-tag tag-blocker">Blocker</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> Stretch Database was discontinued (July 2024). Stretched tables block a clean upgrade path and must be returned on-premises first.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Scan for <code>is_remote_data_archive_enabled</code> tables before migration.</li>
              <li>Unstretch / migrate remote data back to local tables; drop Stretch config.</li>
              <li>Re-validate table sizes and backup windows after unstretch.</li>
              <li>Script: <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('11_stretch_database_check.sql')">11_stretch_database_check.sql</a></li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-polybase">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">PolyBase Hadoop (HDFS) and scale-out groups removed</span>
          <span class="change-tag tag-blocker">Blocker</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> Hadoop/HDFS external data sources and PolyBase scale-out groups are not supported in SQL Server 2022. Scale-up PolyBase and S3/Azure connectors remain.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>List external data sources / tables of type Hadoop.</li>
              <li>Recreate external data sources with supported connectors (S3-compatible, Azure, Oracle, etc.).</li>
              <li>Rebuild dependent external tables and refresh SSIS/ETL packages.</li>
              <li>Script: <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('12_polybase_hadoop_check.sql')">12_polybase_hadoop_check.sql</a></li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-compat">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Compatibility level and Cardinality Estimator (130 vs 160)</span>
          <span class="change-tag tag-behavior">Behavior</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> Migrated DBs often stay at compat 130 on the 2022 engine until you change them. Raising to 140/150/160 enables newer CE and Intelligent Query Processing, which can improve or regress plans. Jumping 130 → 160 is a top community-reported regression source.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Cut over at current compat (usually 130) and hold 7-14 days (Option A backout) unless UAT signed off higher.</li>
              <li>Enable Query Store first, baseline, then stage 140/150, then 160.</li>
              <li>For confirmed CE regressions: temporary <code>LEGACY_CARDINALITY_ESTIMATION = ON</code> (database scoped) while remediating.</li>
              <li>You cannot restore a 2022 database back to 2016 — prefer compat/scoped-config rollback over physical failback.</li>
              <li>Scripts:
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('19_query_store_enable_and_status.sql')">19_query_store_enable_and_status.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('20_compatibility_level_report.sql')">20_compatibility_level_report.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('21_rollback_evidence_capture.sql')">21_rollback_evidence_capture.sql</a>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-iqp">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Intelligent Query Processing (PSP, DOP/CE feedback, memory grant feedback)</span>
          <span class="change-tag tag-behavior">Behavior</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> SQL Server 2017-2022 added adaptive joins, batch mode on rowstore, Parameter Sensitive Plan (PSP), DOP feedback, CE feedback, and persistent memory grant feedback. Behavior depends on compat level and Query Store. Early CUs had PSP edge-case bugs (CPU spikes / timeouts).</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li><strong>Never run production on RTM-only</strong> — install the latest CU before UAT and cutover.</li>
              <li>Do not enable all IQP features on day one in prod without UAT.</li>
              <li>After Query Store baseline and compat raise, evaluate <code>DOP_FEEDBACK</code> / plan forcing carefully.</li>
              <li>Watch for sudden plan flips on parameterized queries (PSP); capture scoped configs with evidence script.</li>
              <li>Related scripts:
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('19_query_store_enable_and_status.sql')">19_query_store_enable_and_status.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('21_rollback_evidence_capture.sql')">21_rollback_evidence_capture.sql</a>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-qs">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Query Store: ON by default for new DBs; upgraded DBs keep old settings</span>
          <span class="change-tag tag-behavior">Behavior</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> New databases on 2022 get Query Store ON by default. Restored/upgraded databases retain prior Query Store settings (often OFF on 2016).</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Explicitly enable Query Store (READ_WRITE) on all migrated user databases before compat changes.</li>
              <li>Size capture policy appropriately (AUTO or CUSTOM) to control overhead.</li>
              <li>Use Query Store for day-1 regression detection and rollback of bad plans.</li>
              <li>Script: <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('19_query_store_enable_and_status.sql')">19_query_store_enable_and_status.sql</a></li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-tls">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">TDS 8.0 / TLS encryption and client security stack</span>
          <span class="change-tag tag-behavior">Behavior</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> SQL Server 2022 supports TDS 8.0 (encryption-aligned) and TLS 1.3. Legacy clients, SSL inspection appliances, or old drivers may fail or negotiate poorly.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Test connectivity from every app tier with modern drivers before cutover.</li>
              <li>Confirm TLS 1.2+ enabled end-to-end; document any forced encryption settings.</li>
              <li>Coordinate with network/security if SSL inspection is in path.</li>
              <li>Related discovery: <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('01_instance_version_and_patch.sql')">01_instance_version_and_patch.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('09_linked_servers_and_jobs.sql')">09_linked_servers_and_jobs.sql</a></li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-tde">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">TDE certificates, SMK, and encryption key hierarchy</span>
          <span class="change-tag tag-blocker">Blocker</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> TDE continues, but side-by-side restore fails without the correct certificates and service master key hierarchy on the target.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Backup Service Master Key and all TDE certificates + private keys before cutover; store offline.</li>
              <li>Restore certs on TARGET before restoring encrypted databases.</li>
              <li>Verify encryption state and recent private-key backups post-restore.</li>
              <li>Scripts:
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('23_tde_certificate_inventory.sql')">23_tde_certificate_inventory.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('05_database_features_tde_cdc.sql')">05_database_features_tde_cdc.sql</a>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-logins">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Logins, SIDs, and orphaned users after restore</span>
          <span class="change-tag tag-ops">Ops</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> Side-by-side restore does not automatically rematch SQL logins by SID. Orphaned users and broken jobs/proxies are common cutover failures.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Export logins with matching SIDs (sp_help_revlogin / DBATools) before cutover.</li>
              <li>Run orphaned-user scan on TARGET; apply <code>ALTER USER ... WITH LOGIN</code> after review.</li>
              <li>Re-validate job owners, proxies, and linked-server logins.</li>
              <li>Scripts:
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('07_logins_and_server_roles.sql')">07_logins_and_server_roles.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('08_orphaned_users_precheck.sql')">08_orphaned_users_precheck.sql</a>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-hadr">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Always On / HA-DR rebuild (Contained AG optional)</span>
          <span class="change-tag tag-ops">Ops</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> AG topology does not transfer unchanged. 2022 adds Contained AGs, DAG network improvements, and Query Store on readable secondaries. Legacy mirroring should move to AG.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Inventory AG/mirroring/log shipping/replication on SOURCE.</li>
              <li>Rebuild endpoints, listeners, seeding, and jobs on 2022 WSFC/AG.</li>
              <li>Validate sync health and RPO before and after cutover.</li>
              <li>Scripts:
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('06_ha_dr_topology.sql')">06_ha_dr_topology.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('22_ag_health_check.sql')">22_ag_health_check.sql</a>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-adr">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Accelerated Database Recovery (ADR) available / improved</span>
          <span class="change-tag tag-feature">Feature</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> ADR (2019+, improved in 2022) speeds crash recovery and long-transaction rollback via persistent version store (PVS).</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Plan PVS capacity before enable — in the primary filegroup or redirected to a dedicated filegroup.</li>
              <li>Optional post-migration enable per database after validating disk for PVS growth.</li>
              <li>Monitor version store size and cleanup; do not enable blindly on all DBs day one.</li>
              <li>Useful for databases with long-running transactions or slow recovery times.</li>
              <li>Post-cutover health: <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('18_post_migration_validation.sql')">18_post_migration_validation.sql</a></li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-tempdb">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">TempDB, VLF, and log growth behavior changes</span>
          <span class="change-tag tag-ops">Ops</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> 2022 improves GAM/SGAM latch concurrency, VLF creation algorithm, and allows Instant File Initialization for transaction log growth up to 64 MB. Memory-optimized TempDB metadata (2019+) remains valuable for latch contention.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Pre-size TempDB with equal files (often up to 8, then multiples of 4); avoid tiny autogrowth.</li>
              <li>On 2022, evaluate <code>MEMORY_OPTIMIZED TEMPDB_METADATA = ON</code> (restart required) for latch-heavy workloads.</li>
              <li>Grant Perform volume maintenance tasks (IFI) to SQL service account.</li>
              <li>Monitor <code>dm_db_log_info</code> and TempDB waits after cutover.</li>
              <li>Scripts:
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('02_server_configuration.sql')">02_server_configuration.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('15_post_install_config_audit.sql')">15_post_install_config_audit.sql</a>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-config">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Max server memory / MAXDOP recommendations and Delayed Start</span>
          <span class="change-tag tag-ops">Ops</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> Setup recommends max memory differently; SQL service set to Automatic may actually use Automatic (Delayed Start). Old 2016 MAXDOP/CTFP/trace flags may be wrong on new hardware/NUMA.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Re-baseline max memory (leave headroom for OS), MAXDOP, and CTFP for the new host.</li>
              <li>Document Delayed Start behavior in DR/runbooks.</li>
              <li>Retest every startup trace flag; remove obsolete ones.</li>
              <li>Scripts:
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('02_server_configuration.sql')">02_server_configuration.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('03_trace_flags_documentation.sql')">03_trace_flags_documentation.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('15_post_install_config_audit.sql')">15_post_install_config_audit.sql</a>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-ml">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Machine Learning Services runtimes not bundled in setup</span>
          <span class="change-tag tag-blocker">Blocker</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> R/Python/Java runtimes are no longer installed by SQL Server 2022 setup. Existing <code>sp_execute_external_script</code> workloads break until runtimes are installed separately.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Inventory external script usage on SOURCE before migration.</li>
              <li>Install SQL Server 2022 Machine Learning Services + required packages on TARGET.</li>
              <li>Retest all R/Python/Java jobs in UAT.</li>
              <li>Readiness scan: <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('13_pre_migration_readiness.sql')">13_pre_migration_readiness.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('10_deprecated_features_usage.sql')">10_deprecated_features_usage.sql</a></li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-cdc">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">CDC, Change Tracking, and replication must be reconfigured</span>
          <span class="change-tag tag-ops">Ops</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> Features remain supported but do not auto-rebuild on a new instance. Agent jobs, distributors, and watermarks must be planned for cutover.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Script publications, subscriptions, CDC capture/cleanup jobs, and CT settings from SOURCE.</li>
              <li>Rebuild on TARGET; validate lag vs SLA before declaring go-live.</li>
              <li>Scripts:
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('05_database_features_tde_cdc.sql')">05_database_features_tde_cdc.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('09_linked_servers_and_jobs.sql')">09_linked_servers_and_jobs.sql</a>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-backup">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">Backup to S3-compatible object storage (optional modernization)</span>
          <span class="change-tag tag-feature">Feature</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> SQL Server 2022 extends BACKUP/RESTORE TO/FROM URL with an S3 connector via REST API, in addition to Azure Blob.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Optional: redesign backup targets to S3-compatible storage after cutover is stable.</li>
              <li>Do not change backup strategy on cutover night unless pre-tested.</li>
              <li>Always verify first full backup + restore test on 2022.</li>
              <li>Script: <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('14_backup_chain_verification.sql')">14_backup_chain_verification.sql</a></li>
            </ul>
          </div>
        </div>
      </div>

      <div class="change-item" id="chg-security">
        <button type="button" class="change-summary" onclick="toggleChange(this)">
          <span class="change-chevron">&#9654;</span>
          <span class="change-title">New security features (Entra auth, Ledger, granular roles) - optional adopt</span>
          <span class="change-tag tag-feature">Feature</span>
        </button>
        <div class="change-body">
          <div><strong>What changed:</strong> SQL Server 2022 adds Microsoft Entra authentication, Ledger, improved Always Encrypted enclaves, granular UNMASK, and new least-privilege server roles.</div>
          <div class="db-action"><strong>DB / DBA actions:</strong>
            <ul>
              <li>Do not require these for cutover success; adopt after stabilization.</li>
              <li>If Always Encrypted enclaves are already in use, validate host/driver versions on 2022.</li>
              <li>Plan least-privilege role cleanup after go-live (reduce sprawling sysadmin).</li>
              <li>Baseline security inventory:
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('07_logins_and_server_roles.sql')">07_logins_and_server_roles.sql</a>
                <a href="#" class="script-link" title="Click to open SQL script" onclick="event.preventDefault();event.stopPropagation();viewScript('02_server_configuration.sql')">02_server_configuration.sql</a>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>

    <div class="card-box"><h3>Rollback Decision Tree</h3>
      <p style="font-size:13px;color:var(--text-secondary);margin-bottom:10px;">Use after evidence capture (<code>21_rollback_evidence_capture.sql</code>). Prefer Option A (compat / scoped config) before connection or physical failback. <strong>You cannot restore a 2022 database to 2016.</strong></p>
      <div class="flow-box">Performance / app issue after cutover?
|
v
Optimizer rollback (Option A)
LEGACY_CARDINALITY_ESTIMATION / hold compat 130
|
v
Still bad?
|
v
Connection rollback to 2016 SOURCE
(only if no critical writes OR Option B catching them)
|
v
Writes occurred on 2022?
|
+-- No --> Keep 2016 authoritative; freeze 2022 for RCA
|
+-- Yes --> Reverse replication / ETL planned (Option B)?
           |
           +-- Yes --> Physical failback path
           |
           +-- No  --> Manual reconciliation / incident</div>
    </div>

    <div class="card-box"><h3>Quick Links - Post-Migration Troubleshooting</h3>
      <p style="font-size:12px;color:var(--text-secondary);margin-bottom:10px;">Click any link to open the embedded SQL in the script viewer (works offline from this HTML / unzipped package).</p>
      <ul style="font-size:13px;line-height:1.9;padding-left:20px;color:var(--text-secondary);">
        <li><a href="#" class="script-link" onclick="event.preventDefault();viewScript('Prod_Migration/01_Quick_Triage/00_RUN_FIRST_triage_playbook.sql')">Prod_Migration/01_Quick_Triage/00_RUN_FIRST_triage_playbook.sql</a> — start here for incidents</li>
        <li><a href="#" class="script-link" onclick="event.preventDefault();viewScript('Prod_Migration/02_Upgrade_Validation/04_complete_post_upgrade_configuration_report.sql')">Prod_Migration/02_Upgrade_Validation/04_complete_post_upgrade_configuration_report.sql</a> — day-1 config report</li>
        <li><a href="#" class="script-link" onclick="event.preventDefault();viewScript('Prod_Migration/06_Optimizer_Plans/03_query_store_regression.sql')">Prod_Migration/06_Optimizer_Plans/03_query_store_regression.sql</a> — plan regressions</li>
        <li><a href="#" class="script-link" onclick="event.preventDefault();viewScript('Prod_Migration/04_Wait_Stats/02_post_migration_wait_decoder.sql')">Prod_Migration/04_Wait_Stats/02_post_migration_wait_decoder.sql</a> — wait decoder</li>
        <li><a href="#" class="script-link" onclick="event.preventDefault();viewScript('Prod_Migration/05_Concurrency/01_blocking_and_locks.sql')">Prod_Migration/05_Concurrency/01_blocking_and_locks.sql</a> — blocking</li>
        <li><a href="#" class="script-link" onclick="event.preventDefault();viewScript('Prod_Migration/07_Instance_Config/01_post_migration_config_audit.sql')">Prod_Migration/07_Instance_Config/01_post_migration_config_audit.sql</a> — config audit</li>
        <li><a href="#" class="script-link" onclick="event.preventDefault();viewScript('Prod_Migration/MASTER_INDEX.sql')">Prod_Migration/MASTER_INDEX.sql</a> — full triage index</li>
      </ul>
    </div>
  </div>
  $(($phaseNav | ForEach-Object {
    $phaseId = $_.Id
    @"
  <div class="section-page" id="page-$phaseId">
    <div class="page-header"><h2>$($_.Icon) $($_.Name)</h2><p id="desc-$phaseId"></p></div>
    <div class="gate-box" id="gate-$phaseId"></div>
    <div class="card-box" id="steps-$phaseId"></div>
  </div>
"@
  }) -join "`n")
  <div class="section-page" id="page-scripts">
    <div class="page-header"><h2>Script Library</h2><p>All scripts are embedded in this HTML. Click a name to view/copy. Loose <code>.sql</code> files are also in the zip under <code>scripts/</code> for SSMS.</p></div>
    <div class="card-box"><h3>Migration scripts (2016 to 2022)</h3><div id="scriptLibraryMigration"></div></div>
    <div class="card-box"><h3>Post-migration troubleshooting (Prod_Migration)</h3><div id="scriptLibraryTroubleshoot"></div></div>
  </div>
</main>
<div class="script-viewer-overlay" id="scriptViewer" onclick="if(event.target===this)closeViewer()">
  <div class="script-viewer">
    <div class="script-viewer-header">
      <strong id="viewerTitle">SQL Script</strong>
      <div><button class="copy-btn" onclick="copyScript()">Copy</button> <button class="copy-btn" onclick="closeViewer()">Close</button></div>
    </div>
    <div class="script-viewer-body"><pre class="sql-code" id="viewerCode"></pre></div>
  </div>
</div>
<script id="steps-data" type="application/json">$stepsJson</script>
<script id="gates-data" type="application/json">$phaseGatesJson</script>
<script>
var stepsData = JSON.parse(document.getElementById('steps-data').textContent);
var phaseGates = JSON.parse(document.getElementById('gates-data').textContent);
var scriptContents = {
$scriptContentsJs
};
var phaseDesc = {
  P0:'Governance, licensing, strategy selection, and stakeholder alignment.',
  P1:'Run all discovery scripts on SOURCE SQL Server 2016. Remediate blockers before proceeding.',
  P2:'Architecture and sizing decisions for Windows Server and SQL Server 2022 target.',
  P3:'Build empty 2022 target instance and validate configuration.',
  P4:'Non-production pilot - restore, test compat levels, app + UAT sign-off.',
  P5:'Final production prep, backup verification, sync setup, DR validation, runbook.',
  P6:'Migration weekend cutover steps with validation gates.',
  P7:'Day-1 through week-2 stabilization, 24h/7-day monitoring on 2022.',
  P8:'Rollback layers, evidence capture, decision tree, and RCA before retry.'
};
var STORAGE_KEY = 'sql2016_2022_migration_checklist_v2';
var OPERATOR_KEY = 'sql2016_2022_migration_operator';
function priClass(p){
  if(p==='Critical') return 'priority-critical';
  if(p==='High') return 'priority-high';
  if(p==='Low') return 'priority-low';
  return 'priority-medium';
}
function loadOperator(){
  try{
    var n=localStorage.getItem(OPERATOR_KEY)||'';
    var el=document.getElementById('operatorName');
    if(el) el.value=n;
  }catch(e){}
}
function saveOperator(){
  var el=document.getElementById('operatorName');
  if(el) localStorage.setItem(OPERATOR_KEY, el.value||'');
}
function loadProgress(){
  try{
    var s=localStorage.getItem(STORAGE_KEY);
    if(!s)return;
    var m=JSON.parse(s);
    stepsData.forEach(function(x){ if(m[x.StepID]) x.Status=m[x.StepID]; });
  }catch(e){}
}
function saveProgress(){
  var m={};
  stepsData.forEach(function(x){ m[x.StepID]=x.Status; });
  localStorage.setItem(STORAGE_KEY, JSON.stringify(m));
}
function toggleStep(id, checked){
  stepsData.forEach(function(x){ if(x.StepID===id) x.Status=checked?'Completed':'Pending'; });
  saveProgress(); updateProgress();
}
function updateProgress(){
  var total=stepsData.length, done=stepsData.filter(function(x){return x.Status==='Completed';}).length;
  var pct=total?Math.round(done/total*100):0;
  document.getElementById('progressPct').textContent=pct+'%';
  document.getElementById('progressCount').textContent=done+' / '+total+' steps complete';
  document.getElementById('progressBar').style.width=pct+'%';
  ['P0','P1','P2','P3','P4','P5','P6','P7','P8'].forEach(function(pid){
    var ph=stepsData.filter(function(x){return x.PhaseID===pid;});
    var pd=ph.filter(function(x){return x.Status==='Completed';}).length;
    var el=document.getElementById('badge-'+pid);
    if(el) el.textContent=pd+'/'+ph.length;
  });
}
function renderGates(){
  ['P0','P1','P2','P3','P4','P5','P6','P7','P8'].forEach(function(pid){
    var box=document.getElementById('gate-'+pid);
    if(!box) return;
    var items=phaseGates[pid]||[];
    box.innerHTML='<h3>Go / No-Go Gate &mdash; '+pid+' Exit Criteria</h3><ul>'+
      items.map(function(t){return '<li>'+t+'</li>';}).join('')+
      '</ul><p class="gate-stop">Otherwise STOP. Do not advance until every item is green.</p>';
  });
}
function renderSteps(){
  ['P0','P1','P2','P3','P4','P5','P6','P7','P8'].forEach(function(pid){
    var desc=document.getElementById('desc-'+pid);
    if(desc) desc.textContent=phaseDesc[pid]||'';
    var box=document.getElementById('steps-'+pid);
    if(!box) return;
    var items=stepsData.filter(function(x){return x.PhaseID===pid;});
    box.innerHTML=items.map(function(s){
      var chk=s.Status==='Completed'?' checked':'';
      var scr=s.Script?'<div class="item-script" onclick="viewScript(\''+s.Script+'\')">&#128196; '+s.Script+'</div>':'';
      var meta='<div class="meta-row">'+
        '<span class="priority-badge '+priClass(s.Priority)+'">Priority: '+s.Priority+'</span>'+
        '<span class="priority-badge '+priClass(s.Risk||s.Priority)+'">Risk: '+(s.Risk||s.Priority)+'</span>'+
        '<span class="meta-chip">Owner: '+(s.Owner||'DBA')+'</span>'+
        '<span class="meta-chip">Duration: '+(s.Duration||'n/a')+'</span>'+
        '</div>';
      var success=s.Success?'<div class="item-details"><strong>Expected result:</strong> '+s.Success+'</div>':'';
      var prereq=s.Prereq?'<div class="item-details"><strong>Prerequisites:</strong> '+s.Prereq+'</div>':'';
      return '<div class="checklist-item"><input type="checkbox" data-id="'+s.StepID+'"'+chk+' onchange="toggleStep(\''+s.StepID+'\',this.checked)"><div class="item-content"><div class="item-text"><strong>'+s.StepID+'</strong> - '+s.Task+'</div><div class="item-details">'+s.Details+'</div>'+success+prereq+scr+meta+'</div></div>';
    }).join('');
  });
  var libMig=document.getElementById('scriptLibraryMigration');
  var libTs=document.getElementById('scriptLibraryTroubleshoot');
  var keys=Object.keys(scriptContents).sort();
  function libItem(k){
    return '<div class="checklist-item" style="border:none;padding:8px 0"><div class="item-content"><div class="item-script" onclick="viewScript(\''+k.replace(/'/g,"\\'")+'\')">'+k+'</div></div></div>';
  }
  if(libMig){
    libMig.innerHTML=keys.filter(function(k){return k.indexOf('Prod_Migration/')!==0;}).map(libItem).join('');
  }
  if(libTs){
    libTs.innerHTML=keys.filter(function(k){return k.indexOf('Prod_Migration/')===0;}).map(libItem).join('');
  }
}
function showPhase(id){
  document.querySelectorAll('.section-page').forEach(function(p){p.classList.remove('active');});
  document.querySelectorAll('.sidebar-item').forEach(function(i){i.classList.remove('active');});
  var page=document.getElementById('page-'+id);
  if(page) page.classList.add('active');
  document.querySelectorAll('.sidebar-item').forEach(function(i){
    if(i.getAttribute('data-phase')===id || (id==='dashboard'&&i.textContent.indexOf('Dashboard')>=0) || (id==='scripts'&&i.textContent.indexOf('Script Library')>=0)) i.classList.add('active');
  });
  window.scrollTo(0,0);
}
function viewScript(file){
  document.getElementById('viewerTitle').textContent=file;
  var body=scriptContents[file];
  if(!body){
    body='-- Script not found in this package: '+file+'\n-- Re-generate the checklist HTML or use the scripts/ folder in the zip.';
  }
  document.getElementById('viewerCode').textContent=body;
  document.getElementById('scriptViewer').classList.add('active');
}
function closeViewer(){ document.getElementById('scriptViewer').classList.remove('active'); }
function copyScript(){
  var t=document.getElementById('viewerCode').textContent;
  navigator.clipboard.writeText(t);
}
function resetProgress(){
  if(!confirm('Reset all checklist progress?')) return;
  localStorage.removeItem(STORAGE_KEY);
  stepsData.forEach(function(x){x.Status='Pending';});
  renderSteps(); updateProgress();
}
function xmlEsc(v){
  return String(v==null?'':v)
    .replace(/&/g,'&amp;')
    .replace(/</g,'&lt;')
    .replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;')
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g,'');
}
function colLetter(n){
  var s='';
  while(n>0){ var m=(n-1)%26; s=String.fromCharCode(65+m)+s; n=Math.floor((n-1)/26); }
  return s;
}
function stepHeaderRow(){
  return [
    'Done (Y/N)','StepID','Phase','Task','Status','Priority','Risk','Owner','Duration',
    'Expected Result','Prerequisites','Script','Details','Notes (editable)','Completed Date','Sign-off'
  ];
}
function stepDataRow(s){
  return [
    s.Status==='Completed'?'Y':'N',
    s.StepID,
    s.PhaseName,
    s.Task,
    s.Status,
    s.Priority,
    s.Risk||'',
    s.Owner||'',
    s.Duration||'',
    s.Success||'',
    s.Prereq||'',
    s.Script||'',
    s.Details||'',
    '',
    '',
    ''
  ];
}
var phaseSheetMeta = [
  {id:'P0', sheet:'P0_Initiation'},
  {id:'P1', sheet:'P1_Discovery'},
  {id:'P2', sheet:'P2_Target_Design'},
  {id:'P3', sheet:'P3_Build_Target'},
  {id:'P4', sheet:'P4_UAT_Pilot'},
  {id:'P5', sheet:'P5_Prod_Prep'},
  {id:'P6', sheet:'P6_Cutover'},
  {id:'P7', sheet:'P7_Stabilization'},
  {id:'P8', sheet:'P8_Rollback'}
];
function crc32(str){
  var table=crc32._t;
  if(!table){
    table=crc32._t=[];
    for(var n=0;n<256;n++){
      var c=n;
      for(var k=0;k<8;k++) c=(c&1)?(0xEDB88320^(c>>>1)):(c>>>1);
      table[n]=c>>>0;
    }
  }
  var crc=0^(-1);
  for(var i=0;i<str.length;i++) crc=(crc>>>8)^table[(crc^str.charCodeAt(i))&0xFF];
  return (crc^(-1))>>>0;
}
function u16(n){ return String.fromCharCode(n&255,(n>>>8)&255); }
function u32(n){ return String.fromCharCode(n&255,(n>>>8)&255,(n>>>16)&255,(n>>>24)&255); }
function utf8Encode(str){
  return unescape(encodeURIComponent(str));
}
function zipStore(files){
  var parts=[], central=[], offset=0;
  files.forEach(function(f){
    var name=f.name, data=utf8Encode(f.data), crc=crc32(data), size=data.length;
    var local=u32(0x04034b50)+u16(20)+u16(0)+u16(0)+u16(0)+u16(0)+
      u32(crc)+u32(size)+u32(size)+u16(name.length)+u16(0)+name+data;
    parts.push(local);
    central.push(
      u32(0x02014b50)+u16(20)+u16(20)+u16(0)+u16(0)+u16(0)+u16(0)+
      u32(crc)+u32(size)+u32(size)+u16(name.length)+u16(0)+u16(0)+u16(0)+u16(0)+
      u32(0)+u32(offset)+name
    );
    offset+=local.length;
  });
  var centralDir=central.join('');
  var end=u32(0x06054b50)+u16(0)+u16(0)+u16(files.length)+u16(files.length)+
    u32(centralDir.length)+u32(offset)+u16(0);
  return parts.join('')+centralDir+end;
}
function sheetToOOXML(rows, opts){
  opts=opts||{};
  var headerRow=(opts.headerRow===undefined)?0:opts.headerRow;
  var maxCols=1;
  rows.forEach(function(r){ if(r&&r.length>maxCols) maxCols=r.length; });
  var widths=opts.colWidths||[];
  var out=[];
  out.push('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
  out.push('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  if(opts.tabColor) out.push('<sheetPr><tabColor rgb="'+opts.tabColor+'"/></sheetPr>');
  out.push('<dimension ref="A1:'+colLetter(maxCols)+Math.max(1,rows.length)+'"/>');
  out.push('<sheetViews>');
  if(opts.freezeRow){
    out.push('<sheetView workbookViewId="0">');
    out.push('<pane ySplit="'+opts.freezeRow+'" topLeftCell="A'+(opts.freezeRow+1)+'" activePane="bottomLeft" state="frozen"/>');
    out.push('<selection pane="bottomLeft"/>');
    out.push('</sheetView>');
  } else {
    out.push('<sheetView workbookViewId="0"/>');
  }
  out.push('</sheetViews>');
  out.push('<cols>');
  for(var c=1;c<=maxCols;c++){
    var w=widths[c-1];
    if(w==null) w=14;
    out.push('<col min="'+c+'" max="'+c+'" width="'+w+'" customWidth="1"/>');
  }
  out.push('</cols>');
  out.push('<sheetData>');
  var mode=opts.mode||'table';
  var priIdx=opts.priorityCol, riskIdx=opts.riskCol, doneIdx=opts.doneCol;
  rows.forEach(function(row, ri){
    var r=ri+1, cells=[];
    var rowAttrs='r="'+r+'"';
    if(opts.rowHeights&&opts.rowHeights[ri]) rowAttrs+=' ht="'+opts.rowHeights[ri]+'" customHeight="1"';
    row.forEach(function(val, ci){
      var ref=colLetter(ci+1)+r;
      var s=String(val==null?'':val);
      var style=4;
      if(mode==='howto'){
        if(ri===0) style=2;
        else if(s==='Sheet guide'||s==='Tips') style=3;
        else if(ci===0) style=10;
        else style=4;
      } else if(mode==='summary'){
        if(ri===headerRow || (opts.secondHeader!=null && ri===opts.secondHeader)) style=1;
        else if(ci===0) style=10;
        else style=(ri%2===0)?4:5;
      } else if(headerRow!==null && ri===headerRow){
        style=1;
      } else {
        style=(ri%2===0)?5:4;
        if(opts.gateHeaderRows && opts.gateHeaderRows.indexOf(ri)>=0) style=3;
        if(doneIdx!=null && ci===doneIdx) style=(s.toUpperCase()==='Y')?6:7;
        if(priIdx!=null && ci===priIdx){
          if(s==='Critical') style=8; else if(s==='High') style=9;
        }
        if(riskIdx!=null && ci===riskIdx){
          if(s==='Critical') style=8; else if(s==='High') style=9;
        }
      }
      if(s!=='' && /^-?\d+(\.\d+)?$/.test(String(s).trim()) && !(headerRow!==null && ri===headerRow) && mode!=='howto'){
        cells.push('<c r="'+ref+'" s="'+style+'"><v>'+String(s).trim()+'</v></c>');
      } else {
        cells.push('<c r="'+ref+'" s="'+style+'" t="inlineStr"><is><t xml:space="preserve">'+xmlEsc(s)+'</t></is></c>');
      }
    });
    out.push('<row '+rowAttrs+'>'+cells.join('')+'</row>');
  });
  out.push('</sheetData>');
  if(opts.filter && headerRow!==null && rows.length>headerRow){
    var hc=(rows[headerRow]||[]).length||maxCols;
    out.push('<autoFilter ref="A'+(headerRow+1)+':'+colLetter(hc)+rows.length+'"/>');
  }
  out.push('<pageMargins left="0.5" right="0.5" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>');
  out.push('<pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/>');
  out.push('</worksheet>');
  return out.join('');
}
function stylesXml(){
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'+
  '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'+
  '<fonts count="5">'+
    '<font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>'+
    '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/><family val="2"/></font>'+
    '<font><b/><sz val="16"/><color rgb="FF1E293B"/><name val="Calibri"/><family val="2"/></font>'+
    '<font><b/><sz val="11"/><color rgb="FF0F172A"/><name val="Calibri"/><family val="2"/></font>'+
    '<font><b/><sz val="11"/><color rgb="FF1E3A8A"/><name val="Calibri"/><family val="2"/></font>'+
  '</fonts>'+
  '<fills count="8">'+
    '<fill><patternFill patternType="none"/></fill>'+
    '<fill><patternFill patternType="gray125"/></fill>'+
    '<fill><patternFill patternType="solid"><fgColor rgb="FF2563EB"/></patternFill></fill>'+
    '<fill><patternFill patternType="solid"><fgColor rgb="FFE2E8F0"/></patternFill></fill>'+
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF8FAFC"/></patternFill></fill>'+
    '<fill><patternFill patternType="solid"><fgColor rgb="FFDCFCE7"/></patternFill></fill>'+
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFEF3C7"/></patternFill></fill>'+
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFEE2E2"/></patternFill></fill>'+
  '</fills>'+
  '<borders count="2">'+
    '<border><left/><right/><top/><bottom/><diagonal/></border>'+
    '<border>'+
      '<left style="thin"><color rgb="FFCBD5E1"/></left>'+
      '<right style="thin"><color rgb="FFCBD5E1"/></right>'+
      '<top style="thin"><color rgb="FFCBD5E1"/></top>'+
      '<bottom style="thin"><color rgb="FFCBD5E1"/></bottom>'+
      '<diagonal/>'+
    '</border>'+
  '</borders>'+
  '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'+
  '<cellXfs count="11">'+
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'+
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'+
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'+
    '<xf numFmtId="0" fontId="3" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'+
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'+
    '<xf numFmtId="0" fontId="0" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'+
    '<xf numFmtId="0" fontId="3" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'+
    '<xf numFmtId="0" fontId="3" fillId="6" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'+
    '<xf numFmtId="0" fontId="3" fillId="7" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'+
    '<xf numFmtId="0" fontId="3" fillId="6" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'+
    '<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'+
  '</cellXfs>'+
  '</styleSheet>';
}
function buildXlsx(sheetSpecs){
  var files=[], sheetRels=[], wbSheets=[];
  sheetSpecs.forEach(function(spec, i){
    var n=i+1;
    var safe=String(spec.name).substring(0,31).replace(/[\\/*?:\[\]]/g,'-');
    files.push({name:'xl/worksheets/sheet'+n+'.xml', data:sheetToOOXML(spec.rows, spec.opts||{})});
    sheetRels.push('<Relationship Id="rId'+n+'" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet'+n+'.xml"/>');
    wbSheets.push('<sheet name="'+xmlEsc(safe)+'" sheetId="'+n+'" r:id="rId'+n+'"/>');
  });
  sheetRels.push('<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
  files.push({name:'xl/styles.xml', data:stylesXml()});
  files.push({name:'[Content_Types].xml', data:
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'+
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'+
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'+
    '<Default Extension="xml" ContentType="application/xml"/>'+
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'+
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'+
    sheetSpecs.map(function(_,i){ return '<Override PartName="/xl/worksheets/sheet'+(i+1)+'.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'; }).join('')+
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'+
    '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'+
    '</Types>'
  });
  files.push({name:'_rels/.rels', data:
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'+
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'+
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'+
    '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'+
    '</Relationships>'
  });
  files.push({name:'xl/workbook.xml', data:
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'+
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'+
    '<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="24000" windowHeight="15000" activeTab="1"/></bookViews>'+
    '<sheets>'+wbSheets.join('')+'</sheets></workbook>'
  });
  files.push({name:'xl/_rels/workbook.xml.rels', data:
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'+
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+
    sheetRels.join('')+'</Relationships>'
  });
  files.push({name:'docProps/core.xml', data:
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'+
    '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'+
    '<dc:title>SQL 2016 to 2022 Migration Checklist</dc:title>'+
    '<dc:creator>Migration Checklist</dc:creator>'+
    '</cp:coreProperties>'
  });
  files.push({name:'docProps/app.xml', data:
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'+
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'+
    '<Application>SQL Migration Checklist</Application></Properties>'
  });
  return zipStore(files);
}
function exportExcel(){
  saveOperator();
  var op=(document.getElementById('operatorName')||{}).value||'(not set)';
  var now=new Date().toISOString();
  var done=stepsData.filter(function(x){return x.Status==='Completed';}).length;
  var total=stepsData.length;
  var sheets=[];
  var stepWidths=[8,10,22,48,12,10,10,14,12,36,30,28,42,22,14,14];
  var stepOptsBase={mode:'steps', headerRow:0, freezeRow:1, filter:true, doneCol:0, priorityCol:5, riskCol:6, colWidths:stepWidths, rowHeights:{0:28}};

  sheets.push({name:'00_How_To_Use', rows:[
    ['SQL Server 2016 to 2022 Migration Checklist - Excel Workbook'],
    ['Generated', now],
    ['Operator', op],
    [''],
    ['Sheet guide'],
    ['01_Summary', 'Overall progress and phase completion counts'],
    ['02_All_Steps', 'Full checklist - filter/sort; fill Notes / Sign-off'],
    ['P0_... P8_...', 'One sheet per migration phase (gates included at bottom)'],
    ['Phase_Gates', 'Go/No-Go exit criteria - mark Gate Met = Y when ready'],
    ['Scripts', 'Script library catalog'],
    [''],
    ['Tips'],
    ['1. Header row is frozen; use AutoFilter arrows to filter'],
    ['2. Green Done=Y / amber Done=N; Critical priority/risk highlighted in red'],
    ['3. Priority = schedule urgency; Risk = blast radius if step fails'],
    ['4. Fill Notes, Completed Date, and Sign-off columns during execution']
  ], opts:{mode:'howto', headerRow:null, freezeRow:0, filter:false, tabColor:'FF64748B', colWidths:[28,70], rowHeights:{0:30}}});

  var summaryRows = [
    ['Metric', 'Value'],
    ['Operator', op],
    ['Generated UTC', now],
    ['Steps completed', done],
    ['Steps total', total],
    ['Percent complete', total?Math.round(done/total*100):0],
    [''],
    ['Phase', 'Name', 'Completed', 'Total', 'Remaining', 'Description']
  ];
  phaseSheetMeta.forEach(function(pm){
    var ph=stepsData.filter(function(x){return x.PhaseID===pm.id;});
    var pd=ph.filter(function(x){return x.Status==='Completed';}).length;
    summaryRows.push([
      pm.id,
      (ph[0]&&ph[0].PhaseName)||pm.sheet,
      pd,
      ph.length,
      ph.length-pd,
      phaseDesc[pm.id]||''
    ]);
  });
  sheets.push({name:'01_Summary', rows:summaryRows, opts:{
    mode:'summary', headerRow:0, secondHeader:7, freezeRow:1, filter:false, tabColor:'FF16A34A',
    colWidths:[14,36,12,10,12,55], rowHeights:{0:26,7:26}
  }});

  var allRows=[stepHeaderRow()];
  stepsData.forEach(function(s){ allRows.push(stepDataRow(s)); });
  sheets.push({name:'02_All_Steps', rows:allRows, opts:Object.assign({}, stepOptsBase, {tabColor:'FF2563EB'})});

  phaseSheetMeta.forEach(function(pm){
    var rows=[stepHeaderRow()];
    stepsData.filter(function(x){return x.PhaseID===pm.id;}).forEach(function(s){
      rows.push(stepDataRow(s));
    });
    var blankAt=rows.length;
    rows.push(['']);
    var gateHeaderAt=rows.length;
    rows.push(['GO / NO-GO GATE - '+pm.id, 'Gate Met (Y/N)', 'Evidence / Notes', 'Signed By', 'Date']);
    (phaseGates[pm.id]||[]).forEach(function(g){
      rows.push([g, '', '', '', '']);
    });
    rows.push(['Otherwise STOP. Do not advance until every gate item is Y.']);
    sheets.push({name:pm.sheet, rows:rows, opts:Object.assign({}, stepOptsBase, {
      tabColor:'FF0EA5E9',
      gateHeaderRows:[gateHeaderAt]
    })});
  });

  var gateRows=[['PhaseID', 'Phase Name', 'Gate Criterion', 'Gate Met (Y/N)', 'Evidence / Notes', 'Signed By', 'Date']];
  phaseSheetMeta.forEach(function(pm){
    var pname=(stepsData.filter(function(x){return x.PhaseID===pm.id;})[0]||{}).PhaseName||pm.sheet;
    (phaseGates[pm.id]||[]).forEach(function(g){
      gateRows.push([pm.id, pname, g, '', '', '', '']);
    });
  });
  sheets.push({name:'Phase_Gates', rows:gateRows, opts:{
    mode:'gates', headerRow:0, freezeRow:1, filter:true, doneCol:3, tabColor:'FFDC2626',
    colWidths:[10,28,55,14,30,16,14], rowHeights:{0:28}
  }});

  var scriptRows=[['Script', 'Used By Steps', 'Phases', 'Typical Duration', 'Open From HTML']];
  Object.keys(scriptContents).sort().forEach(function(fn){
    var used=stepsData.filter(function(s){return s.Script===fn;});
    var phases={};
    used.forEach(function(s){ phases[s.PhaseID]=1; });
    scriptRows.push([
      fn,
      used.map(function(s){return s.StepID;}).join(', '),
      Object.keys(phases).sort().join(', '),
      (used[0]&&used[0].Duration)||'',
      'Script Library in HTML checklist'
    ]);
  });
  sheets.push({name:'Scripts', rows:scriptRows, opts:{
    mode:'scripts', headerRow:0, freezeRow:1, filter:true, tabColor:'FF7C3AED',
    colWidths:[42,28,16,16,32], rowHeights:{0:28}
  }});

  var binary=buildXlsx(sheets);
  var bytes=new Uint8Array(binary.length);
  for(var i=0;i<binary.length;i++) bytes[i]=binary.charCodeAt(i)&0xFF;
  var blob=new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
  var a=document.createElement('a');
  a.href=URL.createObjectURL(blob);
  a.download='SQL_2016_to_2022_Migration_Checklist.xlsx';
  a.click();
  setTimeout(function(){ URL.revokeObjectURL(a.href); }, 2000);
}
function exportCsv(){
  var rows=[['StepID','Phase','Task','Status','Priority','Risk','Owner','Duration','Success','Prereq','Script','Details']];
  stepsData.forEach(function(s){
    rows.push([s.StepID,s.PhaseName,s.Task,s.Status,s.Priority,s.Risk||'',s.Owner||'',s.Duration||'',s.Success||'',s.Prereq||'',s.Script||'',s.Details]);
  });
  var csv=rows.map(function(r){return r.map(function(c){return '"'+String(c).replace(/"/g,'""')+'"';}).join(',');}).join('\\r\\n');
  var a=document.createElement('a');
  a.href='data:text/csv;charset=utf-8,'+encodeURIComponent('\\uFEFF'+csv);
  a.download='SQL_2016_to_2022_Migration_Checklist.csv';
  a.click();
}
function exportSummary(){
  saveOperator();
  var op=(document.getElementById('operatorName')||{}).value||'(not set)';
  var now=new Date().toISOString();
  var done=stepsData.filter(function(x){return x.Status==='Completed';});
  var pending=stepsData.filter(function(x){return x.Status!=='Completed';});
  var lines=[];
  lines.push('SQL Server 2016 to 2022 Migration Summary');
  lines.push('Generated: '+now);
  lines.push('Operator: '+op);
  lines.push('Completed: '+done.length+' / '+stepsData.length);
  lines.push('');
  lines.push('=== COMPLETED ===');
  done.forEach(function(s){ lines.push(s.StepID+' | '+s.PhaseName+' | '+s.Task+' | Owner='+(s.Owner||'')+' | Risk='+(s.Risk||'')); });
  lines.push('');
  lines.push('=== REMAINING / SKIPPED ===');
  pending.forEach(function(s){ lines.push(s.StepID+' | '+s.PhaseName+' | '+s.Task+' | Status='+s.Status); });
  lines.push('');
  lines.push('=== PHASE GATES (manual confirmation still required) ===');
  Object.keys(phaseGates).sort().forEach(function(pid){
    lines.push(pid+':');
    (phaseGates[pid]||[]).forEach(function(g){ lines.push('  [ ] '+g); });
  });
  var blob=new Blob([lines.join('\\r\\n')],{type:'text/plain;charset=utf-8'});
  var a=document.createElement('a');
  a.href=URL.createObjectURL(blob);
  a.download='SQL_2016_to_2022_Migration_Summary.txt';
  a.click();
}
function toggleTheme(){
  var h=document.documentElement;
  h.setAttribute('data-theme', h.getAttribute('data-theme')==='dark'?'light':'dark');
}
function toggleChange(btn){
  var item=btn.closest('.change-item');
  if(item) item.classList.toggle('open');
}
function setAllChanges(open){
  document.querySelectorAll('#page-dashboard .change-item').forEach(function(el){
    if(open) el.classList.add('open'); else el.classList.remove('open');
  });
}
document.documentElement.setAttribute('data-theme','light');
loadOperator(); loadProgress(); renderGates(); renderSteps(); updateProgress(); showPhase('dashboard');
</script>
</body>
</html>
"@

$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

[System.IO.File]::WriteAllText($OutputPath, $html, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated: $OutputPath"
Write-Host "Steps: $($steps.Count) | Scripts embedded: $($scriptFiles.Count)"

if (-not $SkipZip) {
    $pkgRoot = Join-Path $outDir 'SQL_2016_to_2022_Migration_Package'
    if (Test-Path -LiteralPath $pkgRoot) {
        Remove-Item -LiteralPath $pkgRoot -Recurse -Force
    }
    $migDir = Join-Path $pkgRoot (Join-Path 'scripts' 'Migration_2016_to_2022')
    $prodDir = Join-Path $pkgRoot (Join-Path 'scripts' 'Prod_Migration')
    New-Item -ItemType Directory -Path $migDir -Force | Out-Null
    New-Item -ItemType Directory -Path $prodDir -Force | Out-Null

    Copy-Item -LiteralPath $OutputPath -Destination (Join-Path $pkgRoot 'SQL_2016_to_2022_Migration_Checklist.html') -Force
    Get-ChildItem -LiteralPath $ScriptsPath -Filter '*.sql' -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $migDir $_.Name) -Force
    }
    foreach ($rel in $troubleshootKeys) {
        $sub = $rel.Substring('Prod_Migration/'.Length) -replace '/', [IO.Path]::DirectorySeparatorChar
        $src = Join-Path $ProdMigrationPath $sub
        if (Test-Path -LiteralPath $src) {
            $dest = Join-Path $prodDir $sub
            $destParent = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $destParent)) {
                New-Item -ItemType Directory -Path $destParent -Force | Out-Null
            }
            Copy-Item -LiteralPath $src -Destination $dest -Force
        }
    }

    $readme = @"
SQL Server 2016 to 2022 Migration Package
=========================================

How to use
----------
1. Unzip this folder anywhere (email attachment / shared drive).
2. Open SQL_2016_to_2022_Migration_Checklist.html in Chrome, Edge, or Firefox
   (double-click the file - no web server required).
3. All migration and troubleshooting SQL scripts are EMBEDDED in the HTML.
   Click any script link (Quick Links, checklist steps, or Script Library)
   to view and Copy them.

Loose SQL files (optional - for SSMS)
-------------------------------------
scripts/Migration_2016_to_2022/   Discovery, cutover, validation scripts
scripts/Prod_Migration/           Post-migration triage / troubleshooting

Notes
-----
- Progress checkboxes are stored in the browser (localStorage) on this machine.
- Use Export Excel / Export CSV / Summary from the header to share status.
- Re-run Generate-Migration2016To2022Checklist.ps1 to refresh this package.
"@
    [System.IO.File]::WriteAllText((Join-Path $pkgRoot 'README.txt'), $readme, [System.Text.UTF8Encoding]::new($false))

    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -LiteralPath $ZipPath -Force
    }
    Compress-Archive -Path $pkgRoot -DestinationPath $ZipPath -Force
    Write-Host "Package zip: $ZipPath"
    Write-Host "Unzip and open: SQL_2016_to_2022_Migration_Package\SQL_2016_to_2022_Migration_Checklist.html"
}
