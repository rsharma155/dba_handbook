# SQL Optima DBA Assessment Framework — Consolidated Requirement Specification

**Version:** 2.0 (Consolidated)
**Last Updated:** 2026-06-19
**Status:** Production-ready (P0 + P1 complete; P2 partial; P3 pending)

---

## 1. Executive Summary

This document consolidates all design requirements, review feedback, architecture decisions, and implementation status for the SQL Optima DBA Assessment Framework. The project evolved from a collection of diagnostic scripts into a three-layer assessment framework: Repository → Collection → Presentation.

### 1.1 Project Positioning

> From: *collection of DBA scripts*
> To: *SQL Server Health Assessment Framework* — collect → store → analyze → report

### 1.2 Target Audience

| Audience | Value Delivered |
|----------|-----------------|
| Junior DBA | Guided learning, explanations, recommended actions |
| Senior DBA | Rapid triage, server baseline, audit report |
| Consultant | Customer-ready deliverable, assessment report, remediation plan |
| Management | Risk overview, health score, capacity forecast |

### 1.3 Overall Assessment Scores

| Area | Score | Notes |
|------|-------|-------|
| Organization & discoverability | 9/10 | Folder naming is excellent |
| Production safety (read-only) | 8.5/10 | Mostly safe; a few scripts need guards |
| Expert DBA troubleshooting value | 8/10 | Good DMV choices; lacks depth in places |
| Junior DBA learning value | 7.5/10 | Metric_Context helps; needs prerequisites & runbook |
| Developer-to-DBA bridge | 7.5/10 | Blocking/plan cache useful; needs "why" links |
| Dynamic multi-DB readiness | 9/10 | sp_DBA_ForEachDatabase + per-DB params |
| Enterprise / automation readiness | 8.5/10 | Unified output schema, persistence layer, PowerShell |
| SQL Server coverage completeness | 7.5/10 | Core gaps closed; minor gaps remain |
| **Overall** | **8.5/10** | Strong foundation; revision cycle complete |

---

## 2. Architecture

### 2.1 Three-Layer Architecture

```
+---------------------------------------------------+
| Presentation Layer                                |
| PowerShell + PSWriteHTML → HTML (→ PDF optional)  |
+---------------------------------------------------+
                        ↑
+---------------------------------------------------+
| Collection / Intelligence Layer                   |
| sp_DBA_HealthCheck, section wrappers, folder SQL  |
| dbatools: inventory, backups, AG, jobs            |
+---------------------------------------------------+
                        ↑
+---------------------------------------------------+
| Repository Layer                                  |
| DBARepository database (per instance)             |
| SPs, functions, history tables, CheckId registry  |
+---------------------------------------------------+
```

### 2.2 Repository Layout

```
dba_essential_scripts/
├── 00_Framework/              # Shared SQL framework
│   ├── sp_DBA_HealthCheck.sql
│   ├── sp_DBA_ForEachDatabase.sql
│   ├── sp_DBA_WaitAnalysis.sql
│   ├── sp_DBA_IndexReview.sql
│   ├── sp_DBA_BackupReview.sql
│   ├── sp_DBA_SecurityAudit.sql
│   ├── sp_DBA_PlanCacheAnalyzer.sql
│   ├── sp_DBA_QueryStoreRegressions.sql
│   ├── sp_DBA_ActiveSessions.sql
│   ├── sp_DBA_BaselineCapture.sql
│   ├── sp_DBA_SaveAssessmentRun.sql
│   ├── fn_DBA_ExcludedWaitTypes.sql
│   ├── fn_DBA_AgentRunDurationSeconds.sql
│   ├── 00_Deploy_Framework.sql
│   ├── 00_Deploy_Framework.ps1
│   └── 00_Install_Framework.sql
├── 00_Repository/             # DBARepository DDL
│   ├── DBARepository_Create.sql
│   ├── DBARepository_Deploy.sql
│   ├── DBARepository_Persistence.sql
│   ├── CheckIdRegistry.sql
│   └── AssessmentFindingTableType.sql
├── 01_Server_OS/
│   ├── cpu_utilization.sql
│   ├── disk_latency.sql
│   └── memory_diagnostics.sql
├── 02_Instance_Config/
│   ├── server_configuration_audit.sql
│   ├── os_integration_checks.sql
│   └── database_compatibility_audit.sql
├── 03_Storage_Engine/
│   ├── database_files_growth.sql
│   ├── tempdb_configuration.sql
│   └── vlf_fragmentation.sql
├── 04_Performance_Diagnostics/
│   ├── wait_statistics.sql
│   ├── wait_statistics_reference.sql
│   ├── blocking_and_deadlocks.sql
│   ├── deadlock_analysis.sql
│   ├── plan_cache_deep_dive.sql
│   └── top_resource_queries.sql
├── 05_Index_Statistics/
│   ├── advanced_index_analysis.sql
│   ├── index_usage_efficiency.sql
│   ├── physical_stats_and_heaps.sql
│   └── statistics_freshness.sql
├── 06_HA_DR/
│   ├── alwayson_ag_monitor.sql
│   ├── backup_verification.sql
│   ├── backup_log_chain.sql
│   └── restore_test_simulator.sql
├── 07_Security/
│   ├── authorization_audit.sql
│   ├── encryption_hardening.sql
│   └── login_audit.sql
├── 08_Advanced/
│   ├── cdc_health.sql
│   ├── error_log_and_connectivity.sql
│   ├── feature_deep_dive_audit.sql
│   ├── inmemory_compression.sql
│   ├── query_store_health.sql
│   ├── replication_monitor.sql
│   ├── sql_agent_job_monitor.sql
│   └── ultra_deep_internal_audit.sql
├── 09_Maintenance/
│   ├── failed_jobs.sql
│   └── last_checkdb_dates.sql
├── 10_Capacity_Planning/
│   └── database_growth_forecast.sql
├── 11_Query_Store/
│   └── regressed_queries.sql
├── 12_Extended_Events/
│   └── active_xe_sessions.sql
├── 13_Resource_Governor/
│   └── resource_governor_config.sql
├── 14_Baselines/
│   └── performance_snapshot.sql
├── powershell/
│   ├── Invoke-SqlOptimaAssessment.ps1
│   ├── Generate-HADRChecklist.ps1
│   ├── Private/
│   │   ├── Export-AssessmentHtml.ps1
│   │   ├── Invoke-SectionCollector.ps1
│   │   └── Get-AssessmentConfig.ps1
│   └── README.md
├── output/                    # gitignore: html, json
├── _MASTER_INDEX.sql
└── README.md
```

---

## 3. Shared Framework Requirements

### 3.1 sp_DBA_ForEachDatabase

Standard cross-database execution helper. **Status: Implemented.**

| Parameter | Type | Default | Purpose |
|-----------|------|---------|---------|
| @Command | NVARCHAR(MAX) | Required | SQL batch with ? placeholder for DB name |
| @UserDatabasesOnly | BIT | 1 | Skip master/tempdb/model/msdb |
| @IncludeReadOnly | BIT | 0 | Include read-only databases |
| @DatabaseList | NVARCHAR(MAX) | NULL | Comma-separated override |
| @ExcludeList | NVARCHAR(MAX) | NULL | Comma-separated exclusions |
| @PrintOnly | BIT | 0 | Print commands instead of executing |
| @ContinueOnError | BIT | 1 | Log errors and continue |

**Requirements:**
- QUOTENAME on all database names in dynamic SQL
- TRY/CATCH with error logging per database
- Filter: `state = 0`, `is_in_standby = 0`

### 3.2 fn_DBA_ExcludedWaitTypes

Centralized benign wait type filter. **Status: Implemented.**

Must exclude: CLR_SEMAPHORE, LAZYWRITER_SLEEP, RESOURCE_QUEUE, SLEEP_TASK, SLEEP_SYSTEMTASK, SQLTRACE_BUFFER_FLUSH, WAITFOR, LOGMGR_QUEUE, CHECKPOINT_QUEUE, REQUEST_FOR_DEADLOCK_SEARCH, XE_TIMER_EVENT, XE_DISPATCHER_JOIN, XE_DISPATCHER_WAIT, FT_IFTS_SCHEDULER_VAL_KEEP_ALIVE, DIRTY_PAGE_TABLE_RELEASE, SP_SERVER_DIAGNOSTICS_SLEEP, QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP, QDS_PERSIST_TASK_MAIN_LOOP_SLEEP, REDO_THREAD_PENDING_WORK, WAIT_FOR_RESULTS, HADR_FILESTREAM_IOMGR_IOCOMPLETION, BROKER_EVENTHANDLER, BROKER_RECEIVE_WAITFOR, BROKER_TRANSMITTER, BROKER_TO_FLUSH, ONDEMAND_TASK_QUEUE, PREEMPTIVE_OS_AUTHENTICATIONOPS, HADR_FABRIC_CALLBACK_EVENT, HADR_NOTIFICATION_DEQUEUE, HADR_TIMER_TASK, HADR_LOGCAPTURE_WAIT

### 3.3 fn_DBA_AgentRunDurationSeconds

Converts msdb `run_duration` HHMMSS-encoded integer to seconds. **Status: Implemented.**

Formula: `((run_duration / 10000) * 3600) + (((run_duration % 10000) / 100) * 60) + (run_duration % 100)`

### 3.4 Findings Output Schema

Standardized output across all scripts. **Status: Implemented in sp_DBA_HealthCheck.**

| Column | Type | Purpose |
|--------|------|---------|
| CheckId | INT | Stable ID for automation/ticketing |
| Severity | VARCHAR(20) | Critical / High / Medium / Low / Info |
| Area | VARCHAR(50) | CPU, Memory, Security, I/O, etc. |
| Finding | VARCHAR(255) | Short title |
| Impact | VARCHAR(255) | Business/ops impact |
| Recommendation | VARCHAR(MAX) | Action text |
| NextStepCommand | VARCHAR(MAX) | Script path or SQL command |

### 3.5 CheckId Registry

Stable CheckId definitions for all findings. **Status: Implemented.**

| Range | Area |
|-------|------|
| 100-199 | CPU & Performance |
| 200-299 | Security & Best Practices |
| 300-399 | Configuration & OS |
| 400-499 | Memory |
| 500-599 | Performance (Waits) |
| 600-699 | Storage & TempDB |
| 700-799 | Indexes |
| 800-899 | Backups |
| 900-999 | AlwaysOn |

### 3.6 Health Scoring System

Starts at 100, deducts per-finding Weight. **Status: Implemented.**

| Category | Display Weight |
|----------|----------------|
| Backups | 20% |
| Corruption / CHECKDB | 25% |
| Storage / I/O | 15% |
| Memory | 10% |
| Security | 10% |
| Always On | 10% |
| Index health | 5% |
| Configuration | 5% |

Traffic light: Green >= 85, Yellow 70-84, Red < 70.

---

## 4. SQL Scripts — Requirements & Status

### 4.1 Folder 01 — Server & OS

#### cpu_utilization.sql
- **Requirement:** Capture current and historical CPU usage (ring buffers), split SQL vs OS, signal wait ratio.
- **Status:** Implemented. Uses ring buffers + signal waits + schedulers.
- **Enhancement available:** Add scheduler_id filter for NUMA, optional 5-second sample.

#### disk_latency.sql
- **Requirement:** Per-file read/write stall times from dm_io_virtual_file_stats.
- **Status:** Implemented.
- **Enhancement available:** Drive-level rollup, avg_bytes_per_read/write, io_stall_queued_ms (2016+).

#### memory_diagnostics.sql
- **Requirement:** Target vs Total memory, PLE, memory clerk distribution.
- **Status:** Implemented.
- **PLE formula:** `(TotalMem_MB / 4) * 150` — aligned with sp_DBA_HealthCheck.

### 4.2 Folder 02 — Instance Configuration

#### server_configuration_audit.sql
- **Requirement:** Audit sys.configurations against best practices (CTFP, MAXDOP, IFI, LPIM, etc.).
- **Status:** Implemented.
- **Enhancement available:** RAM vs max server memory validation, NUMA-aware MAXDOP.

#### os_integration_checks.sql
- **Requirement:** IFI status, LPIM status, trace flags.
- **Status:** Implemented.

#### database_compatibility_audit.sql
- **Requirement:** Flag databases below instance default compatibility level, auto_close/shrink, orphaned owners.
- **Status:** Implemented (new).

### 4.3 Folder 03 — Storage Engine

#### database_files_growth.sql
- **Requirement:** Track disk space, file size, used space, autogrowth settings.
- **Status:** Implemented. Dynamic DB loop with TRY/CATCH.
- **Enhancement available:** Flag percent-based growth, max_size unlimited flag.

#### tempdb_configuration.sql
- **Requirement:** Verify TempDB file count, size uniformity, PAGELATCH contention.
- **Status:** Implemented.
- **Enhancement available:** sys.dm_db_file_space_usage, trace flag check for pre-2016.

#### vlf_fragmentation.sql
- **Requirement:** Count and analyze VLFs per database.
- **Status:** Implemented. Uses sys.dm_db_log_info (SQL 2016+).
- **Enhancement available:** Pre-2016 fallback (DBCC LOGINFO), avg_vlf_size_mb.

### 4.4 Folder 04 — Performance Diagnostics

#### wait_statistics.sql
- **Requirement:** Cumulative wait stats with category + recommendation columns.
- **Status:** Implemented.

#### wait_statistics_reference.sql
- **Requirement:** Educational reference with investigation commands per wait type.
- **Status:** Implemented. Keep as junior DBA training artifact.

#### blocking_and_deadlocks.sql
- **Requirement:** Blocking tree CTE, system_health deadlock XML.
- **Status:** Implemented.
- **Enhancement available:** Parse victim from victim-list correctly.

#### deadlock_analysis.sql
- **Requirement:** Advanced deadlock analysis from XE sessions with victim ID, process details, resource contention.
- **Status:** Implemented (new).

#### plan_cache_deep_dive.sql
- **Requirement:** Key lookup and implicit conversion detection from plan cache.
- **Status:** Implemented.

#### top_resource_queries.sql
- **Requirement:** Top queries by CPU, I/O, duration, executions.
- **Status:** Implemented.

### 4.5 Folder 05 — Index & Statistics

#### advanced_index_analysis.sql
- **Requirement:** Cross-DB duplicate + contention detection.
- **Status:** Implemented.

#### index_usage_efficiency.sql
- **Requirement:** Missing index DMV + unused index detection.
- **Status:** Implemented with strong warning about DMV over-recommendation.

#### physical_stats_and_heaps.sql
- **Requirement:** Cross-DB dm_db_index_physical_stats with LIMITED mode.
- **Status:** Implemented.

#### statistics_freshness.sql
- **Requirement:** Last updated date, modification counter, auto-stats settings.
- **Status:** Implemented.

### 4.6 Folder 06 — HA/DR

#### alwayson_ag_monitor.sql
- **Requirement:** Replica health, per-DB queues, RPO estimate, listener status.
- **Status:** Implemented.

#### backup_verification.sql
- **Requirement:** Full/diff/log breakdown, recovery model awareness.
- **Status:** Implemented.

#### backup_log_chain.sql
- **Requirement:** Detect breaks in transaction log backup chain (LSN continuity).
- **Status:** Implemented (new).

#### restore_test_simulator.sql
- **Requirement:** Automated restore testing simulator for DR readiness validation.
- **Status:** Implemented (new, bonus).

### 4.7 Folder 07 — Security

#### authorization_audit.sql
- **Requirement:** Trustworthy, guest, orphaned users, sysadmin listing.
- **Status:** Implemented.

#### encryption_hardening.sql
- **Requirement:** TDE state, audit specs, SSL/TLS.
- **Status:** Implemented.

#### login_audit.sql
- **Requirement:** Disabled logins, password policy, sysadmin members, sa status.
- **Status:** Implemented (new).

### 4.8 Folder 08 — Advanced

#### cdc_health.sql
- **Requirement:** CDC capture lag, cleanup, log reader throughput.
- **Status:** Implemented.

#### error_log_and_connectivity.sql
- **Requirement:** Error log keyword search + connectivity ring buffer.
- **Status:** Implemented.

#### feature_deep_dive_audit.sql
- **Requirement:** CDC job params, Query Store config, replication metrics, job owner audit.
- **Status:** Implemented. CDC section fixed to use msdb.dbo.cdc_jobs (not dm_cdc_errors).

#### inmemory_compression.sql
- **Requirement:** Compression candidates by scan activity, In-Memory OLTP monitoring.
- **Status:** Implemented.

#### query_store_health.sql
- **Requirement:** Instance QS status + regressed/forced plans.
- **Status:** Implemented.

#### replication_monitor.sql
- **Requirement:** Replication health with distribution DB guard.
- **Status:** Implemented.

#### sql_agent_job_monitor.sql
- **Requirement:** Failed jobs + duration anomalies.
- **Status:** Implemented. run_duration HHMMSS encoding bug fixed via fn_DBA_AgentRunDurationSeconds.

#### ultra_deep_internal_audit.sql
- **Requirement:** TempDB breakdown, buffer pool by DB, parameter sniffing multi-plan.
- **Status:** Implemented. Documented as expensive (off-peak only).

### 4.9 Folder 09 — Maintenance

#### failed_jobs.sql
- **Requirement:** Failed jobs + currently running jobs with duration.
- **Status:** Implemented. run_duration bug fixed.

#### last_checkdb_dates.sql
- **Requirement:** Last successful DBCC CHECKDB date per database (Ola Hallengren CommandLog or msdb fallback).
- **Status:** Implemented (new).

### 4.10 Folder 10 — Capacity Planning

#### database_growth_forecast.sql
- **Requirement:** Backup size history, default trace autogrowth, growth projection.
- **Status:** Implemented.

### 4.11 Folder 11 — Query Store

#### regressed_queries.sql
- **Requirement:** Detect queries with multiple plans where slowest recent plan is worse than best.
- **Status:** Implemented. True regression detection (not just highest avg_duration).

### 4.12 Folder 12 — Extended Events

#### active_xe_sessions.sql
- **Requirement:** List active XE sessions + targets, extract deadlocks from system_health.
- **Status:** Implemented. Fixed: now joins dm_xe_session_targets correctly.

### 4.13 Folder 13 — Resource Governor

#### resource_governor_config.sql
- **Requirement:** RG configuration, classifier function, workload groups.
- **Status:** Implemented.

### 4.14 Folder 14 — Baselines

#### performance_snapshot.sql
- **Requirement:** Point-in-time performance snapshot for incident response.
- **Status:** Implemented.

---

## 5. Framework Stored Procedures

### 5.1 sp_DBA_HealthCheck

Central orchestrator with findings-first output. **Status: Implemented.**

**Parameters:**
| Parameter | Type | Default | Purpose |
|-----------|------|---------|---------|
| @DeepDive | BIT | 0 | 0=triage, 1=full detail |
| @DatabaseList | NVARCHAR(MAX) | NULL | Target specific databases |
| @IncludeReadOnly | BIT | 0 | Include read-only replicas |
| @BackupHoursSLA | INT | 24 | Backup SLA threshold |

**Sections:** CPU, Security (per-DB loop), Configuration, Memory, Wait Stats (TOP 30), Storage/VLF/TempDB, Missing Indexes, Backups, AlwaysOn.

**Health Score:** Starts at 100, deducts Weight per finding. Returns findings RS + dashboard RS + deep dive RS.

### 5.2 sp_DBA_ForEachDatabase

Standard cross-database helper. **Status: Implemented.**

### 5.3 sp_DBA_WaitAnalysis

Top N wait types with categories and recommendations. **Status: Implemented.**

### 5.4 sp_DBA_IndexReview

Unused + missing + duplicate indexes across databases. **Status: Implemented.**

### 5.5 sp_DBA_BackupReview

Backup health review. **Status: Implemented.**

### 5.6 sp_DBA_SecurityAudit

Comprehensive security audit across databases. **Status: Implemented.**

### 5.7 sp_DBA_PlanCacheAnalyzer

Plan cache analysis. **Status: Implemented.**

### 5.8 sp_DBA_QueryStoreRegressions

True plan regression detection across databases. **Status: Implemented.**

Compares recent vs historical plan avg_duration per query_id. Requires Query Store (SQL 2016+).

### 5.9 sp_DBA_ActiveSessions

Active session monitoring. **Status: Implemented.**

### 5.10 sp_DBA_BaselineCapture

Persist performance_snapshot metrics. **Status: Implemented.**

### 5.11 sp_DBA_SaveAssessmentRun

Save assessment run + findings to DBARepository. **Status: Implemented.**

---

## 6. Repository Layer (DBARepository)

### 6.1 Database DDL

**Status: Implemented.**

- `DBARepository_Create.sql` — Creates the database
- `DBARepository_Deploy.sql` — Install order for all sp_DBA_* and fn_DBA_*
- `DBARepository_Persistence.sql` — History tables (AssessmentRun, AssessmentFinding, AssessmentMetric)
- `CheckIdRegistry.sql` — Stable CheckId definitions
- `AssessmentFindingTableType.sql` — Table-valued parameter for batch inserts

### 6.2 History Tables

```sql
-- AssessmentRun: RunId, ServerName, RunUtc, Profile, HealthScore, ToolVersion, SqlVersion
-- AssessmentFinding: RunId, CheckId, Severity, Area, Finding, Recommendation, ...
-- AssessmentMetric: RunId, MetricName, MetricValue (dashboard keys)
```

---

## 7. PowerShell Layer

### 7.1 Main Entry Point

**Status: Implemented.**

`Invoke-SqlOptimaAssessment.ps1` — Parameters:
- `-SqlInstance` (required)
- `-Profile` Quick/Standard/Deep (default: Quick)
- `-OutputPath` (default: ..\output)
- `-DatabaseList` (optional)
- `-BackupHoursSLA` (default: 24)
- `-ConfigPath` (optional)
- `-Credential` (optional)
- `-Persist` (switch)
- `-OutputJson` (switch)

### 7.2 Assessment Profiles

| Profile | Duration | Includes | Use When |
|---------|----------|----------|----------|
| Quick | 30-90 sec | sp_DBA_HealthCheck @DeepDive=0 + inventory | Daily triage |
| Standard | 3-8 min | Quick + waits, backup, security, config, disk | Weekly assessment |
| Deep | 10-30+ min | Standard + index physical stats, statistics, QS | Off-peak audit |

### 7.3 Private Functions

- `Get-AssessmentConfig.ps1` — Load assessment.config.json
- `Invoke-SectionCollector.ps1` — Run section scripts and collect results
- `Export-AssessmentHtml.ps1` — Generate HTML report with PSWriteHTML

### 7.4 Required PowerShell Modules

| Module | Purpose |
|--------|---------|
| dbatools | SQL connectivity, inventory, backups, AG, jobs |
| PSWriteHTML | HTML dashboards, charts, tables, collapsible sections |
| ImportExcel (optional) | Excel export for consultants |
| PSWriteColor (optional) | Console progress during long runs |

---

## 8. Incident Response Playbooks

### 8.1 High CPU Utilization

1. Run `cpu_utilization.sql` → Confirm SQL vs external process
2. Run `top_resource_queries.sql` → Identify top CPU consumers
3. Run `plan_cache_deep_dive.sql` → Check compilation storms / ad-hoc bloat
4. Action: Tune queries, add indexes, enable Optimize for Ad Hoc Workloads

### 8.2 Blocking & Application Timeouts

1. Run `blocking_and_deadlocks.sql` → Identify head blocker
2. Run `wait_statistics.sql` → Check LCK_M_X / LCK_M_S percentages
3. Action: Investigate head blocker session; long-term: RCSI or tune transaction scopes

### 8.3 Sudden Query Slowdown (Plan Regression)

1. Run `regressed_queries.sql` → Find queries with multiple plans or increased duration
2. Run `statistics_freshness.sql` → Check stale stats
3. Action: Force last known good plan via Query Store, or UPDATE STATISTICS with FULLSCAN

### 8.4 Disk Space / I/O Bottlenecks

1. Run `disk_latency.sql` → Identify struggling database files
2. Run `database_files_growth.sql` → Check runaway autogrowths
3. Run `database_growth_forecast.sql` → Project when disk fills
4. Action: Move high-latency files to faster storage; switch to fixed MB growth

### 8.5 HA/DR Failover or Sync Issues

1. Run `alwayson_ag_monitor.sql` → Check Send/Redo queues and Sync state
2. Run `failed_jobs.sql` → Check if log backup jobs are failing
3. Action: Resume synchronization if suspended; check network between replicas

---

## 9. Permissions Matrix

| Permission | Scripts Needing It |
|------------|-------------------|
| VIEW SERVER STATE | Nearly all |
| VIEW ANY DEFINITION | Security, encryption, RG, XE |
| CONNECT SQL + DB access | Cross-DB dynamic scripts |
| msdb read | Backup, jobs, growth forecast |
| distribution read | Replication scripts |
| CONTROL SERVER | sp_readerrorlog, DBCC TRACESTATUS (sometimes) |

---

## 10. Version Compatibility

| Feature | Minimum Version | Scripts Affected |
|---------|----------------|------------------|
| sys.dm_db_log_info | SQL Server 2016+ | vlf_fragmentation, sp_DBA_HealthCheck |
| sys.dm_db_stats_properties | 2008 R2 SP2+ | statistics_freshness |
| sys.dm_server_services (IFI) | 2016 SP1+ | os_integration_checks |
| sys.database_query_store_options | 2016+ | Query Store scripts |
| STRING_AGG | 2017+ | encryption_hardening |
| sys.dm_os_buffer_descriptors DB name | 2012+ with hotfix | ultra_deep_internal_audit |

---

## 11. Thresholds & Standards

| Topic | Threshold | Formula/Logic |
|-------|-----------|---------------|
| PLE | Dynamic | `(TotalMem_MB / 4) * 150` (Jonathan Kehayias / Glenn Berry) |
| VLF Warning | 200-999 | Good < 200, Warning 200-999, Critical >= 1000 |
| Backup SLA | 24h (configurable) | Via @BackupHoursSLA parameter |
| TempDB files | 4-8 | Match cores up to 8; verify with PAGELATCH waits |
| Disk latency | > 20ms | io_stall_read/write_ms / num_of_reads/writes |
| Signal waits | > 25% | CPU scheduling pressure |
| CPU | > 80% | SQL Server process utilization |
| Missing index impact | > 1M | user_seeks * avg_user_impact * avg_total_user_cost |
| Stale statistics | > 20% | modification_counter / rows > 0.2 |
| Unused index threshold | > 10000 writes | user_updates with zero reads |

---

## 12. Implementation Status Summary

### 12.1 P0 Bug Fixes (All Complete)

| Bug | Status |
|-----|--------|
| active_xe_sessions.sql invalid column reference | Fixed (joins dm_xe_session_targets) |
| feature_deep_dive_audit.sql CDC wrong DMV | Fixed (uses msdb.dbo.cdc_jobs) |
| run_duration HHMMSS encoding in job scripts | Fixed (fn_DBA_AgentRunDurationSeconds) |
| sp_DBA_HealthCheck missing index wrong DB scope | Fixed (#HealthCheckDbs join) |
| sp_DBA_HealthCheck TOP 30 vs TOP 10 mismatch | Fixed (#TopWaits with TOP 30) |
| Centralized wait type exclusion list | Created fn_DBA_ExcludedWaitTypes |

### 12.2 P1 Framework (All Complete)

| Item | Status |
|------|--------|
| sp_DBA_ForEachDatabase with QUOTENAME, TRY/CATCH | Done |
| Standard parameters on all per-DB scripts | Done |
| sp_DBA_HealthCheck modular checks | Done |
| Unified Findings output schema with CheckId | Done |
| Baseline capture framework | Done |
| CheckId Registry | Done |

### 12.3 P2 Coverage Expansion (Partial)

| Item | Status |
|------|--------|
| last_checkdb_dates.sql | Done |
| backup_log_chain.sql | Done |
| login_audit.sql | Done |
| database_compatibility_audit.sql | Done |
| sp_DBA_QueryStoreRegressions (true regression) | Done |
| restore_test_simulator.sql | Done (bonus) |
| deadlock_analysis.sql | Done (bonus) |
| suspect_pages.sql | Not yet created |
| linked_server_security.sql | Not yet created |
| log_shipping_monitor.sql | Not yet created |
| operator_and_alert_audit.sql | Not yet created |
| columnstore_health.sql | Not yet created |

### 12.4 P3 Polish (Pending)

| Item | Status |
|------|--------|
| De-duplicate job monitor and QS scripts | Not started |
| Version-guard all scripts | Not started |
| Update traceability matrix | Not started |
| 00_Framework/README.md run order | Not started |

### 12.5 Phased Implementation (PowerShell)

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 0 | Design & contracts | Done |
| Phase 1 | MVP HTML report | Done |
| Phase 2 | Standard sectional report | Partial |
| Phase 3 | Persistence & trend | Not started |
| Phase 4 | Enterprise / multi-server / PDF | Not started |

---

## 13. Recommended Full Handbook Execution Order

```
1.  sp_DBA_HealthCheck @DeepDive = 0          -- triage
2.  14_Baselines/performance_snapshot.sql     -- capture point (if incident)
3.  01_Server_OS/*                            -- if CPU/memory/IO flagged
4.  02_Instance_Config/*                      -- config drift
5.  03_Storage_Engine/*                       -- space + tempdb + VLF
6.  04_Performance_Diagnostics/*              -- waits, blocking, top queries
7.  05_Index_Statistics/*                     -- per-DB (loop)
8.  06_HA_DR/*                                -- if AG/backup findings
9.  07_Security/*                             -- per-DB security
10. 08_Advanced/*                             -- feature-specific (CDC, QS, repl)
11. sp_DBA_HealthCheck @DeepDive = 1          -- full detail
```

---

## 14. HADR Deployment Checklist Summary

For 2-node WSFC + File Share Witness with AlwaysOn AG:

**Critical Steps:** Infrastructure planning → DC setup → Service accounts → DNS → Network → Domain join → SQL install → Enable Always On → WSFC → Validate → Create cluster → Quorum → Endpoints → Firewall → Test DB → Backup/Restore → Create AG → Join secondary → Create listener → Verify sync → Test failover.

**Key Corrections (from review):**
- CNO permission delegation must include Create Computer Child Objects
- Pre-stage SPN for AG Listener
- Add data loss warning for FORCE_FAILOVER_ALLOW_DATA_LOSS
- Add rollback instructions per phase
- Add network latency baseline test (<5ms for SYNCHRONOUS_COMMIT)
- Verify MOVE clause logical names with RESTORE FILELISTONLY

---

## 15. Audience-Specific Guidance

### For the Expert Production DBA
- Treat as starter kit to embed in monitoring pipeline
- Focus on: baseline deltas, CheckId automation, log chain, AG quorum
- Add "estimated runtime" header to expensive scripts

### For the Junior DBA
- Read DBA_essentials.md first, then wait_statistics_reference.sql as textbook
- Always note instance restart time before interpreting wait stats or index usage
- Never drop indexes based on index_usage_efficiency.sql alone
- Use sp_DBA_HealthCheck as daily dashboard

### For the Database Developer New to DBA
- Start with: blocking_and_deadlocks.sql, top_resource_queries.sql, plan_cache_deep_dive.sql, statistics_freshness.sql
- Learn how Metric_Context maps symptoms → infrastructure layer
- Do not run physical_stats_and_heaps on production during peak

---

## 16. Document Source Consolidation

This requirement specification consolidates the following source documents:

| Source Document | Content Incorporated |
|-----------------|---------------------|
| DBA_essentials.md | Core script requirements (Sections 1-9) |
| cursor_review.md | Comprehensive review, P0/P1/P2 priorities, PowerShell architecture |
| ps_script.md | Three-layer architecture, HTML/PDF vision, health scoring |
| revamp_design.md | Diagnostic engine design, decision tree logic |
| review_feedback.md | Prior review scores, missing folders, improvement suggestions |
| HADR_Checklist_REVIEW.md | HADR deployment corrections and missing steps |
| HADR_handbook.md | 25-phase deployment guide for WSFC + AG |
| DBA_essentials_utf8.md | Duplicate of DBA_essentials.md (UTF-8 encoded) |

All individual .md files have been removed. This single document is the authoritative reference.
