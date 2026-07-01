# SQL Server DBA Essential Scripts

> **Location:** This handbook lives under `sql_server/` in the multi-platform [DBA Essential Scripts](../README.md) repository. The root [README.md](../README.md) contains **both** SQL Server and PostgreSQL documentation in one file.

A production-oriented **SQL Server diagnostic handbook** -- a curated library of read-only T-SQL scripts for monitoring, troubleshooting, and auditing Microsoft SQL Server instances. Scripts are organized by troubleshooting layer (OS -> instance -> storage -> performance -> indexes -> HA/DR -> security -> advanced features) and designed to run safely against production systems.

Includes a **PowerShell assessment framework** that generates self-contained HTML reports with health scores, findings, and collapsible detail panels.

**Author:** Ravi Sharma
**Platform:** Microsoft SQL Server (2016+; version-conditional logic through SQL Server 2025)

**Jump to:** [Quick Start](#quick-start) | [Installation](#installation-one-time-per-instance) | [Cheat Sheet](#dba-cheat-sheet-one-page) | [Troubleshooting Flow](#troubleshooting-flow) | [Script Catalog](#script-catalog)

---

## What This Project Is

This repository is **not** a single monolithic tool. It is a **modular DBA toolkit** that provides:

1. **Standalone diagnostic scripts** -- run individually during incidents or scheduled health checks.
2. **Shared framework objects** -- functions and procedures for cross-database execution, wait-type filtering, and consolidated reporting.
3. **An orchestrator** -- `sp_DBA_HealthCheck` aggregates findings into a prioritized dashboard with severity, impact, and recommended next steps.
4. **Modular wrapper procedures** -- `sp_DBA_WaitAnalysis`, `sp_DBA_IndexReview`, `sp_DBA_SecurityAudit`, `sp_DBA_BackupReview` for area-specific deep dives.
5. **Persistence layer** -- `sp_DBA_BaselineCapture` and `sp_DBA_SaveAssessmentRun` store results for historical trending.
6. **PowerShell HTML reports** -- one-command assessment with `Invoke-SqlOptimaAssessment.ps1`.

Use it as:

- A **daily/weekly health check** playbook for DBAs
- An **on-call incident** reference ("high CPU -> run these scripts in this order")
- A **learning path** for developers moving into DBA work (each script includes context and thresholds)
- A **consulting deliverable** -- HTML reports with health scores for customers and management

---

## Who It Is For

| Audience | How to use this repo |
|----------|----------------------|
| **Production DBA** | Deploy framework objects once; run `sp_DBA_HealthCheck` for triage; drill into folder scripts by area |
| **Junior DBA** | Start with `wait_statistics_reference.sql`; note instance uptime before interpreting cumulative DMVs |
| **Database developer** | Use blocking, plan cache, statistics, and Query Store scripts to diagnose application-impacting issues |
| **Consultant / Management** | Run PowerShell assessment for HTML report with health score and findings summary |

---

## Repository Structure

```
sql_server/
├── 00_Framework/                  Shared functions, stored procedures & install guide
│   ├── fn_DBA_ExcludedWaitTypes.sql
│   ├── fn_DBA_AgentRunDurationSeconds.sql
│   ├── sp_DBA_ForEachDatabase.sql
│   ├── sp_DBA_QueryStoreRegressions.sql
│   ├── sp_DBA_HealthCheck.sql
│   ├── sp_DBA_WaitAnalysis.sql
│   ├── sp_DBA_IndexReview.sql
│   ├── sp_DBA_SecurityAudit.sql
│   ├── sp_DBA_BackupReview.sql
│   ├── sp_DBA_ActiveSessions.sql
│   ├── sp_DBA_PlanCacheAnalyzer.sql
│   ├── sp_DBA_BaselineCapture.sql
│   ├── sp_DBA_SaveAssessmentRun.sql
│   ├── 00_Install_Framework.sql
│   ├── 00_Deploy_Framework.sql         (xp_cmdshell-based T-SQL deploy)
│   ├── 00_Deploy_Framework.ps1         (PowerShell deploy script — no xp_cmdshell needed)
│   └── README.md
├── 00_Repository/                 DBARepository DDL, deploy script, persistence, CheckId registry
├── 01_Server_OS/                  CPU, memory, disk latency
├── 02_Instance_Config/            sp_configure, OS integration, compatibility
├── 03_Storage_Engine/             Files, TempDB, VLFs
├── 04_Performance_Diagnostics/    Waits, blocking, top queries, plan cache
├── 05_Index_Statistics/           Usage, fragmentation, statistics, duplicates
├── 06_HA_DR/                      Always On, backups, log chain
├── 07_Security/                   Auth, encryption, logins
├── 08_Advanced/                   CDC, Query Store, replication, agent jobs
├── 09_Maintenance/                Failed jobs, CHECKDB history
├── 10_Capacity_Planning/          Growth forecasting
├── 11_Query_Store/                Plan regression, multi-plan debug, force workflow
├── 12_Extended_Events/            XE sessions, deadlocks
├── 13_Resource_Governor/          RG pools and workload groups
├── 14_Baselines/                  Point-in-time performance snapshots
├── preventive_measures/           Query protection & workload governance (Layered Automation)
│   ├── 01_Create_Governance_Database.sql
│   ├── 02_Capture_Running_Queries.sql
│   ├── 03_Check_Long_Running_Queries.sql
│   ├── 04_Check_Massive_DML.sql
│   ├── 05_Check_Blocked_Applications.sql
│   ├── 06_Enforce_Query_Policy.sql
│   ├── 07_Setup_Extended_Events.sql
│   ├── 08_Alert_Management.sql
│   ├── 09_Dashboard_Views.sql
│   ├── 10_Create_SQL_Agent_Jobs.sql
│   ├── 11_Setup_Resource_Governor.sql
│   └── README.md
├── powershell/                    Automated assessment & HTML reports
│   ├── Invoke-SqlOptimaAssessment.ps1
│   ├── Generate-HADRChecklist.ps1
│   ├── Private/                   Helper functions
│   ├── config/                    assessment.config.json
│   └── README.md
├── output/                        Generated reports (gitignored)
├── docs/                          Documentation & reference
│   ├── requirement_spec.md        Requirements specification
│   ├── watchdog.md                Preventive measures discussion
│   ├── toolkit_comparison.md      Toolkit comparison reference
│   └── templates/                 Report templates
├── DBA_essentials_utf8.md         Duplicate (UTF-8) in root
├── .gitignore                     Git ignore rules
└── README.md                      This file
```

---

## Prerequisites

### SQL Server version

| Version | Support |
|---------|---------|
| SQL Server 2016+ | Full support (Query Store, `dm_db_log_info`, IFI DMV on SP1+) |
| SQL Server 2017+ | Optional `STRING_AGG` paths replaced with 2016-compatible aggregation |
| SQL Server 2022+ | Full support with version-conditional logic for deprecated DMVs |
| SQL Server 2025+ | Full support — dynamic SQL branches handle removed columns (`backupset.type_desc`, `sys.dm_hadr_database_replica_states.database_name`, `sys.server_audit_specifications.type_desc`, etc.) |
| SQL Server 2012-2014 | Partial; VLF and some DMVs need alternate approaches |

**Backward compatibility notes (v2025.06):** All scripts auto-detect the SQL Server version using `SERVERPROPERTY('ProductVersion')` and use dynamic SQL where DMV schemas changed in SQL Server 2025. Key changes handled:

- `msdb.dbo.backupset`: `type_desc` → `type` (char codes D/I/L), `compressed` → `compressed_backup_size > 0`, `recovery_model_desc` → `CASE recovery_model WHEN 'F' THEN 'FULL'...`
- `sys.dm_hadr_database_replica_states`: `database_name` → `sys.availability_databases_cluster` JOIN, `log_send_time` removed
- `sys.server_audits`: `destination_type_desc`, `path`, `max_files` removed in 2025
- `sys.server_audit_specifications`: `type_desc`/`type` removed
- `sys.dm_cdc_errors`: `database_id`, `phase`, `error_code` renamed to `phase_number`, `error_number`
- `msdb.dbo.cdc_jobs`: `database_name`/`job_name` → `database_id`/`job_id`
- `sys.database_query_store_options`: `database_id` removed (database-scoped DMV)
- `sys.availability_group_listeners`: `state_desc` removed
- `sys.dm_exec_requests`: `LEFT JOIN` TVFs → `OUTER APPLY` (required in SQL 2025)
- XML `.value()` methods: `SET QUOTED_IDENTIFIER ON` required

### Permissions (minimum)

| Permission | Needed for |
|------------|------------|
| `VIEW SERVER STATE` | Most DMV scripts |
| `VIEW ANY DEFINITION` | Security, encryption, Extended Events, Resource Governor |
| `CONNECT` + access to each user database | Cross-database scripts |
| Read access to `msdb` | Backup, SQL Agent, growth forecast, CHECKDB history |
| `CREATE FUNCTION` / `CREATE PROCEDURE` | Deploying framework objects (one-time) |

### Important: cumulative DMVs

These counters reset **only on instance restart** (or manual clear):

- `sys.dm_os_wait_stats`
- `sys.dm_db_index_usage_stats`
- `sys.dm_io_virtual_file_stats`
- `sys.dm_exec_query_stats`

Always note `sqlserver_start_time` (shown in several scripts) before drawing conclusions. For trending, use `sp_DBA_BaselineCapture` on a schedule and compare deltas.

---

## Installation (one-time per instance)

### Option A: PowerShell auto-deploy (recommended — no xp_cmdshell required)

One command deploys all 13 framework objects (functions and procedures):

```powershell
# From the repository root, target your admin database (default: master)
.\00_Framework\00_Deploy_Framework.ps1 -ServerInstance "YourServer" -Database "DBARepository"
```

The script scans `00_Framework\*.sql`, runs each file in sorted order via `sqlcmd`, and reports pass/fail for each.

### Option B: T-SQL auto-deploy (uses xp_cmdshell)

If you prefer to run from SSMS and have `xp_cmdshell` enabled:

```sql
EXEC 00_Framework\00_Deploy_Framework.sql  -- or open and run in SSMS
```

Update `@TargetDB` at the top to your admin database name.

### Option C: Repository deploy (full framework + persistence)

Three commands to get fully operational:

```bash
# Step 1: Create the DBARepository database
sqlcmd -S YourServer -d master -i "00_Repository/DBARepository_Create.sql" -C

# Step 2: Deploy all framework objects
sqlcmd -S YourServer -d DBARepository -i "00_Repository/DBARepository_Deploy.sql" -C

# Step 3: Create persistence tables for historical trending (optional but recommended)
sqlcmd -S YourServer -d DBARepository -i "00_Repository/DBARepository_Persistence.sql" -C
```

### Option D: Manual step-by-step (SSMS)

Open each file in SSMS, set database context to your admin database, execute (F5):

```text
 1. 00_Framework/fn_DBA_ExcludedWaitTypes.sql
 2. 00_Framework/fn_DBA_AgentRunDurationSeconds.sql
 3. 00_Framework/sp_DBA_ForEachDatabase.sql
 4. 00_Framework/sp_DBA_QueryStoreRegressions.sql
 5. 00_Framework/sp_DBA_HealthCheck.sql
 6. 00_Framework/sp_DBA_WaitAnalysis.sql
 7. 00_Framework/sp_DBA_IndexReview.sql
 8. 00_Framework/sp_DBA_SecurityAudit.sql
 9. 00_Framework/sp_DBA_BackupReview.sql
10. 00_Framework/sp_DBA_ActiveSessions.sql
11. 00_Framework/sp_DBA_PlanCacheAnalyzer.sql
12. 00_Framework/sp_DBA_BaselineCapture.sql
13. 00_Repository/AssessmentFindingTableType.sql
14. 00_Framework/sp_DBA_SaveAssessmentRun.sql
```

### Verify installation

```sql
USE DBARepository;

-- List all deployed objects
SELECT name, type_desc FROM sys.objects
WHERE name LIKE '%DBA%' OR name LIKE '%Assessment%'
ORDER BY type_desc, name;

-- Quick smoke test
EXEC dbo.sp_DBA_HealthCheck @DeepDive = 0;
```

Framework objects are optional for standalone scripts (many include a manual fallback loop), but **required** for:

- `sp_DBA_HealthCheck` and all wrapper procedures
- `wait_statistics.sql`, `wait_statistics_reference.sql`, `cpu_utilization.sql` (wait filter)
- `query_store_health.sql` / `regressed_queries.sql` (true regression detection)

---

## Quick Start

### 1. Daily health triage (recommended)

```sql
USE DBARepository;
GO

-- Quick findings dashboard
EXEC dbo.sp_DBA_HealthCheck @DeepDive = 0;

-- Full detail with wait encyclopedia, top CPU, disk latency
EXEC dbo.sp_DBA_HealthCheck @DeepDive = 1;

-- Limit to specific databases
EXEC dbo.sp_DBA_HealthCheck
    @DeepDive = 0,
    @DatabaseList = N'SalesDB,HRDB',
    @BackupHoursSLA = 24;
```

### 2. Area-specific deep dives

```sql
USE DBARepository;

-- Wait analysis with categories and recommendations
EXEC dbo.sp_DBA_WaitAnalysis @TopN = 20, @IncludeRecommendations = 1;

-- Active session monitor (what's running RIGHT NOW)
EXEC dbo.sp_DBA_ActiveSessions @OutputMode = 'SUMMARY';  -- Aggregated view
EXEC dbo.sp_DBA_ActiveSessions @OutputMode = 'BLOCKING'; -- Blocking tree

-- Plan cache analysis with anti-pattern detection
EXEC dbo.sp_DBA_PlanCacheAnalyzer @SortOrder = 'WARNING'; -- Grouped by warning type

-- Index health across all databases
EXEC dbo.sp_DBA_IndexReview @DatabaseList = N'SalesDB', @MinPageCount = 1000;

-- Security audit (orphaned users, sysadmin, trustworthy)
EXEC dbo.sp_DBA_SecurityAudit;

-- Backup SLA compliance
EXEC dbo.sp_DBA_BackupReview @BackupHoursSLA = 24;

-- Query Store regressions
EXEC dbo.sp_DBA_QueryStoreRegressions @RegressionPctThreshold = 50;
```

### 3. Capture baseline for trending

> **Prerequisite:** Run `00_Repository/DBARepository_Persistence.sql` first to create the `dbo.BaselineSnapshot` table. Without it, `sp_DBA_BaselineCapture` will raise an error: *"Run DBARepository_Persistence.sql first to create BaselineSnapshot table."*

```sql
USE DBARepository;

-- Capture current performance snapshot
EXEC dbo.sp_DBA_BaselineCapture;

-- Later, capture again and compare
EXEC dbo.sp_DBA_BaselineCapture;

-- Compare deltas (manual query)
WITH Latest AS (
    SELECT TOP (2) * FROM dbo.BaselineSnapshot
    WHERE ServerName = @@SERVERNAME AND WaitType IS NOT NULL
    ORDER BY SnapshotUtc DESC
)
SELECT a.WaitType, a.WaitTimeMs AS CurrentWait, b.WaitTimeMs AS PreviousWait,
       a.WaitTimeMs - b.WaitTimeMs AS DeltaWait
FROM Latest a INNER JOIN Latest b ON a.WaitType = b.WaitType AND a.SnapshotId > b.SnapshotId;
```

### 4. Save assessment to history

```sql
USE DBARepository;

-- Save a health check run
DECLARE @Findings dbo.AssessmentFindingTableType;
INSERT INTO @Findings (CheckId, Severity, Weight, Area, Finding, Impact, Recommendation)
VALUES (1001, 'CRITICAL', 10, 'CPU', 'High CPU', 'Degradation', 'Review top queries');

EXEC dbo.sp_DBA_SaveAssessmentRun
    @ServerName = @@SERVERNAME,
    @Profile = 'Standard',
    @HealthScore = 78,
    @SQLCPUPct = 85.5,
    @SignalWaitPct = 28.3,
    @Findings = @Findings;
```

### 5. PowerShell HTML report

```powershell
# Install modules (once)
Install-Module dbatools, PSWriteHTML -Scope CurrentUser

# Quick triage report (30-90 seconds)
.\powershell\Invoke-SqlOptimaAssessment.ps1 -SqlInstance 'PROD-SQL01' -Profile Quick

# Standard assessment (3-8 minutes)
.\powershell\Invoke-SqlOptimaAssessment.ps1 -SqlInstance 'PROD-SQL01' -Profile Standard

# Full deep assessment (10-30+ minutes, off-peak)
.\powershell\Invoke-SqlOptimaAssessment.ps1 -SqlInstance 'PROD-SQL01' -Profile Deep

# Multiple instances
@('SRV01','SRV02') | .\powershell\Invoke-SqlOptimaAssessment.ps1 -Profile Quick

# Output: .\output\Assessment_PROD-SQL01_20260616_143000.html
```

### 6. Run a single diagnostic script

Open any script under a numbered folder in SSMS and execute. Most are self-contained batches (no deploy step).

```sql
-- Example: open and run entire file
-- 04_Performance_Diagnostics/wait_statistics.sql
```

---

## DBA Handbook UI Features

### Junior / Senior DBA Mode Toggle

The handbook includes a toggle switch in the top-right corner that switches between **Junior** and **Senior** DBA modes.

| Mode | Description | Who should use it |
|------|-------------|-------------------|
| **Junior** (default) | Shows essential content only. Sections marked `senior-only` are hidden. Provides a focused, simplified view for DBAs learning SQL Server operations. | Junior DBAs, new team members, developers transitioning to DBA |
| **Senior** | Reveals all content including advanced sections tagged with `senior-only`. Includes deeper diagnostics, advanced troubleshooting, and expert-level guidance. | Experienced DBAs, senior engineers, consultants |

**How it works:**
- The toggle switches the `<body>` class between `mode-junior` and `mode-senior`
- CSS rule: `.senior-only { display:none; }` hides advanced content by default
- CSS rule: `body.mode-senior .senior-only { display:block; }` shows it when senior mode is active
- The toggle state is visual only (not persisted in localStorage)

**To tag content as senior-only**, add `class="senior-only"` to any HTML element:

```html
<!-- This card only appears in Senior mode -->
<div class="card-box senior-only">
  <h3><i class="fas fa-brain"></i> Advanced Diagnostics</h3>
  ...
</div>
```

### Quick Actions

The Dashboard includes quick-action buttons for common DBA tasks:

| Button | Section | Description |
|--------|---------|-------------|
| Daily Health Check | 05. Daily Health Checks | Morning production health check routine |
| Incident Response | 07. Incident Response Playbook | Structured response procedures for production incidents |
| Review Configuration | 04. SQL Configuration | SQL Server configuration audit checklist |
| Backup Validation | 11. Backup & Recovery | Backup strategy validation and DR readiness |
| Performance Analysis | 08. Performance Tuning | Query and index performance diagnostics |

Clicking a quick-action button navigates to that section and shows a **Back to Dashboard** button at the top. Sidebar navigation and search do not trigger the back button.

### Back to Dashboard Button

A "Back to Dashboard" button appears when navigating to a section via a quick-action button. It allows one-click return to the main dashboard. The button uses theme-aware styling and hover effects.

---

## DBA Cheat Sheet (One Page)

Print or bookmark this section for on-call use.

### First 60 seconds on any incident

```sql
-- 1. Capture baseline (note the timestamp)
EXEC dbo.sp_DBA_BaselineCapture;

-- 2. Triage dashboard (requires framework install)
USE DBARepository;
EXEC dbo.sp_DBA_HealthCheck @DeepDive = 0;

-- 3. Check instance uptime (cumulative DMVs reset on restart)
SELECT sqlserver_start_time FROM sys.dm_os_sys_info;
```

### Symptom -> script (run in order)

| # | Symptom | Scripts |
|---|---------|---------|
| 1 | **High CPU** | `01_Server_OS/cpu_utilization.sql` -> `04/top_resource_queries.sql` -> `04/plan_cache_deep_dive.sql` -> `02/server_configuration_audit.sql` |
| 2 | **Blocking / hangs** | `04/blocking_and_deadlocks.sql` -> `04/wait_statistics.sql` |
| 3 | **One query got slow** | `11/regressed_queries.sql` -> `05/statistics_freshness.sql` |
| 4 | **Slow disk / I/O** | `01/disk_latency.sql` -> `03/database_files_growth.sql` -> `10/database_growth_forecast.sql` |
| 5 | **Memory pressure** | `01/memory_diagnostics.sql` -> `04/wait_statistics.sql` |
| 6 | **AG unhealthy** | `06/alwayson_ag_monitor.sql` -> `09/failed_jobs.sql` -> `06/backup_verification.sql` |
| 7 | **Backup alert** | `06/backup_verification.sql` -> `06/backup_log_chain.sql` -> `09/failed_jobs.sql` |
| 8 | **TempDB issues** | `03/tempdb_configuration.sql` -> `04/wait_statistics.sql` (PAGELATCH) |
| 9 | **Daily / weekly health** | `sp_DBA_HealthCheck @DeepDive=0` then drill by finding area |

*Paths shortened: `04` = `04_Performance_Diagnostics`, etc.*

### Top wait types -> where to look

| Wait pattern | Likely cause | Script |
|--------------|--------------|--------|
| `LCK_*` | Blocking | `blocking_and_deadlocks.sql` |
| `PAGEIOLATCH_*` | Disk read / memory | `disk_latency.sql`, `index_usage_efficiency.sql` |
| `PAGELATCH_*` | TempDB / allocation | `tempdb_configuration.sql` |
| `CXPACKET` / `CXCONSUMER` | Parallelism | `server_configuration_audit.sql`, `top_resource_queries.sql` |
| `RESOURCE_SEMAPHORE` | Memory grants | `memory_diagnostics.sql` |
| `SOS_SCHEDULER_YIELD` | CPU pressure | `cpu_utilization.sql`, `top_resource_queries.sql` |
| `ASYNC_NETWORK_IO` | Client / network | App-side investigation |
| `WRITELOG` | Log I/O | `disk_latency.sql` (log files) |
| `HADR_SYNC_COMMIT` | AG sync | `alwayson_ag_monitor.sql` |

### Key thresholds (defaults in scripts)

| Metric | Warning | Critical |
|--------|---------|----------|
| SQL CPU (ring buffer) | > 70% | > 80% |
| Signal waits % | > 15% | > 25% |
| Disk stall (avg) | > 15 ms | > 20 ms |
| PLE | < `(RAM_GB/4)*150` | well below threshold |
| Runnable tasks / scheduler | > 0 sustained | > 10 |
| VLF count | 200-999 | >= 1000 |
| File used % | > 80% | > 90% |
| Backup age (FULL recovery) | log > 24 h | any backup > SLA |
| Stats modifications | > 20% of rows | -- |
| QS regression | plan >= 50% slower than best | -- |

### Essential commands (after framework install)

```sql
USE DBARepository;

-- Health dashboard
EXEC dbo.sp_DBA_HealthCheck @DeepDive = 0;
EXEC dbo.sp_DBA_HealthCheck @DeepDive = 1, @DatabaseList = N'MyDB';

-- Wait analysis
EXEC dbo.sp_DBA_WaitAnalysis @TopN = 20;

-- What's running right now
EXEC dbo.sp_DBA_ActiveSessions @OutputMode = 'SUMMARY';
EXEC dbo.sp_DBA_ActiveSessions @OutputMode = 'BLOCKING';

-- Plan cache anti-patterns
EXEC dbo.sp_DBA_PlanCacheAnalyzer @SortOrder = 'WARNING';

-- Index review
EXEC dbo.sp_DBA_IndexReview @DatabaseList = N'SalesDB';

-- Security audit
EXEC dbo.sp_DBA_SecurityAudit;

-- Backup review
EXEC dbo.sp_DBA_BackupReview @BackupHoursSLA = 24;

-- Baseline capture
EXEC dbo.sp_DBA_BaselineCapture;

-- Plan regressions (Query Store)
EXEC dbo.sp_DBA_QueryStoreRegressions @RegressionPctThreshold = 50;

-- Run in all / selected databases
EXEC dbo.sp_DBA_ForEachDatabase
    @Command = N'SELECT DB_NAME(), COUNT(*) FROM sys.tables;',
    @DatabaseList = N'DB1,DB2';
```

### Deploy once (order matters)

```
fn_DBA_ExcludedWaitTypes -> fn_DBA_AgentRunDurationSeconds -> sp_DBA_ForEachDatabase
-> sp_DBA_QueryStoreRegressions -> sp_DBA_HealthCheck -> sp_DBA_WaitAnalysis
-> sp_DBA_IndexReview -> sp_DBA_SecurityAudit -> sp_DBA_BackupReview
-> sp_DBA_BaselineCapture -> AssessmentFindingTableType -> sp_DBA_SaveAssessmentRun
```

### Do not do on first snapshot

- Drop indexes from `dm_db_index_usage_stats` alone (resets on restart)
- Create every missing-index DMV suggestion (validate overlap first)
- Run `physical_stats_and_heaps.sql` on all DBs during peak without `@DatabaseList`
- Run `index_maintenance_online.sql` with `@ExecuteMaintenance = 0` first (dry run), then `1` off-peak
- Execute remediation commands from health check without review

---

---

## HADR Checklist Generator (`Generate-HADRChecklist.ps1`)

An interactive HTML checklist generator that guides through the complete process of setting up SQL Server Always On Availability Groups — from infrastructure planning through failover testing.

### Quick Start

```powershell
# Interactive mode (recommended - run with no arguments)
.\Generate-HADRChecklist.ps1

# Or specify all parameters (non-interactive, for automation)
.\Generate-HADRChecklist.ps1 -SecondaryReplicas 2 -WitnessType Cloud -DomainControllerCount 2 -IncludeReadableSecondary
```

### Features

| Feature | Description |
|---------|-------------|
| **Dynamic checklist** | Steps adjust based on number of replicas, witness type, and DC count |
| **Interactive wizard** | Menu-driven prompts with explanations of each option |
| **22 phases** | Covers planning, DC setup, service accounts, DNS, networking, SQL install, WSFC, AG configuration, monitoring, and operations |
| **Interactive HTML** | Paginated view, progress bar, checkboxes with localStorage persistence |
| **Multi-replica support** | 1-3 secondary replicas with automatic synchronous/asynchronous assignment |
| **Witness options** | FileShare, Cloud (Azure), Disk (SAN), or None |
| **Multi-DC support** | Single or dual domain controller with AD replication steps |
| **Readable secondary** | Optional read-only routing configuration steps |
| **Severity levels** | Required / Recommended / Optional badges on each step |

### Parameters

| Parameter | Default | Values | Description |
|-----------|---------|--------|-------------|
| `-SecondaryReplicas` | 1 | 1-3 | Number of secondary replicas |
| `-WitnessType` | FileShare | FileShare, Cloud, Disk, None | Cluster witness type |
| `-DomainControllerCount` | 1 | 1-2 | Number of domain controllers |
| `-OutputPath` | HADR_Checklist.html | Path | Output file path for the HTML checklist |
| `-IncludeReadableSecondary` | off | Switch | Add read-only routing configuration |
| `-IncludeBackupOnSecondary` | off | Switch | Add backup-on-secondary strategy steps |
| `-Interactive` | off | Switch | Force interactive mode |

### Usage Examples

```powershell
# Default: 1 secondary, file share witness, 1 DC
.\Generate-HADRChecklist.ps1

# 3-node AG with cloud witness and 2 DCs
.\Generate-HADRChecklist.ps1 -SecondaryReplicas 2 -WitnessType Cloud -DomainControllerCount 2

# Multi-site DR: 3 secondaries, disk witness
.\Generate-HADRChecklist.ps1 -SecondaryReplicas 3 -WitnessType Disk -IncludeReadableSecondary

# Automated run for CI/CD pipeline
.\Generate-HADRChecklist.ps1 -SecondaryReplicas 1 -WitnessType None -OutputPath "C:\Reports\HADR.html"
```

### How Replica Topology Works

| Replicas | SQL01 | SQL02 | SQL03 | SQL04 |
|----------|-------|-------|-------|-------|
| 1 secondary | Primary (sync) | Secondary (sync) | — | — |
| 2 secondaries | Primary (sync) | Secondary (sync) | Secondary (async) | — |
| 3 secondaries | Primary (sync) | Secondary (sync) | Secondary (async) | Secondary (async) |

- **Synchronous commit**: Zero data loss, automatic failover. Typically used within same datacenter.
- **Asynchronous commit**: Potential data loss, manual failover. Typically used across datacenters for DR.

### What's Generated

A self-contained HTML file (~170-250 KB) with no external dependencies:

- **Sidebar navigation** — phase list with completion status dots (green = done, orange = partial, gray = none)
- **Progress bar** — % complete with steps done / remaining
- **Paginated view** — one phase at a time with Next / Previous buttons
- **Expandable steps** — details, T-SQL commands, expected results, and "why this matters"
- **Checkboxes** — track progress with localStorage persistence across sessions
- **Reset button** — clear all progress
- **Responsive** — works on desktop and mobile

---

## PowerShell Assessment (HTML Reports)

Automated health assessment for SQL Server instances. Generates self-contained HTML reports with severity-scored findings, recommendations, and drill-down sections.

### Quick Start

```powershell
# Install modules (once)
Install-Module dbatools, PSWriteHTML -Scope CurrentUser

# Navigate to powershell folder
cd .\powershell\

# Quick assessment (30-90 seconds)
.\Invoke-SqlOptimaAssessment.ps1 -SqlInstance 'PROD-SQL01' -Profile Quick

# Standard assessment (3-8 minutes)
.\Invoke-SqlOptimaAssessment.ps1 -SqlInstance 'PROD-SQL01' -Profile Standard

# Deep assessment (10-30+ minutes, off-peak)
.\Invoke-SqlOptimaAssessment.ps1 -SqlInstance 'PROD-SQL01' -Profile Deep

# Multiple instances
@('SRV01','SRV02') | .\powershell\Invoke-SqlOptimaAssessment.ps1 -Profile Quick

# Output: .\output\Assessment_PROD-SQL01_20260616_143000.html
```

### Assessment Profiles

| Profile | Duration | Sections | Use When |
|---------|----------|----------|----------|
| **Quick** | 30-90s | HealthCheck, Inventory | Daily triage, many servers |
| **Standard** | 3-8m | + Waits, Backup, Security, Config, Disk | Weekly assessment |
| **Deep** | 10-30m+ | + Index, Capacity, Query Store | Off-peak, migration audit |

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SqlInstance` | string | *required* | SQL Server instance name |
| `-Profile` | string | `Quick` | Assessment profile |
| `-OutputPath` | string | `..\output` | HTML output directory |
| `-DatabaseList` | string | `NULL` | Comma-separated DBs to scope |
| `-BackupHoursSLA` | int | `24` | Backup SLA in hours |
| `-Persist` | switch | `false` | Save to DBARepository history |
| `-OutputJson` | switch | `false` | Also export JSON |

### HADR Checklist Generator

Generates an interactive HTML checklist for SQL Server Always On Availability Group deployment (22 phases).

```powershell
# Interactive mode (recommended)
.\Generate-HADRChecklist.ps1

# Non-interactive with parameters
.\Generate-HADRChecklist.ps1 -SecondaryReplicas 2 -WitnessType Cloud -DomainControllerCount 2
```

See [powershell/README.md](powershell/README.md) for full documentation.

---

## Toolkit Comparison

For a detailed comparison with other DBA toolkits (including Brent Ozar's First Responder Kit), see [docs/toolkit_comparison.md](docs/toolkit_comparison.md).

---

## Troubleshooting Flow

Use this decision tree after `sp_DBA_HealthCheck` or when the alert symptom is known.

```mermaid
flowchart TD
    Start([Alert or slowness reported]) --> Snapshot[Run sp_DBA_BaselineCapture]
    Snapshot --> Health[EXEC sp_DBA_HealthCheck @DeepDive=0]
    Health --> Symptom{Primary symptom?}

    Symptom -->|High CPU| CPU[cpu_utilization.sql]
    CPU --> CPUwait{Signal waits > 25%?}
    CPUwait -->|Yes| ConfigCPU[server_configuration_audit.sql<br/>MAXDOP / CTFP]
    CPUwait -->|No| TopCPU[top_resource_queries.sql]
    TopCPU --> PlanCPU[plan_cache_deep_dive.sql]

    Symptom -->|Blocking / timeout| Block[blocking_and_deadlocks.sql]
    Block --> Deadlock[deadlock_analysis.sql<br/>XE deadlock history]
    Block --> WaitsLCK[wait_statistics.sql<br/>confirm LCK_%]
    Deadlock --> WaitsLCK

    Symptom -->|One query slow| QS{Query Store on?}
    QS -->|Yes| Regress[regressed_queries.sql]
    QS -->|No| Stats[statistics_freshness.sql]
    Regress --> Stats
    Regress --> PlanCache[sp_DBA_PlanCacheAnalyzer<br/>@SortOrder='REGRESSION']

    Symptom -->|Disk / I/O| Disk[disk_latency.sql]
    Disk --> Files[database_files_growth.sql]
    Files --> Growth[database_growth_forecast.sql]

    Symptom -->|Memory| Mem[memory_diagnostics.sql]
    Mem --> MemWait[wait_statistics.sql<br/>PAGEIOLATCH / RESOURCE_SEMAPHORE]

    Symptom -->|AG / DR| AG[alwayson_ag_monitor.sql]
    AG --> Jobs[failed_jobs.sql]
    Jobs --> Backup[backup_verification.sql]

    Symptom -->|Unknown| WaitFirst[wait_statistics.sql]
    WaitFirst --> ActiveNow[sp_DBA_ActiveSessions<br/>@OutputMode='SUMMARY']
    ActiveNow --> Ref[wait_statistics_reference.sql]
    Ref --> Symptom

    ConfigCPU --> Deep[Optional: sp_DBA_HealthCheck @DeepDive=1]
    PlanCPU --> Deep
    WaitsLCK --> Deep
    Stats --> Deep
    Growth --> Deep
    MemWait --> Deep
    Backup --> Deep
    Deep --> End([Document findings + compare to baseline])
```

### Layered diagnostic model

Scripts follow the same order as production troubleshooting -- outside in:

```mermaid
flowchart LR
    subgraph L1 [01 Server OS]
        CPU[CPU]
        MEM[Memory]
        IO[Disk latency]
    end

    subgraph L2 [02 Instance]
        CFG[Config]
        OSINT[IFI / LPIM]
    end

    subgraph L3 [03 Storage]
        FILES[Files / growth]
        TEMP[TempDB]
        VLF[VLFs]
    end

    subgraph L4 [04 Performance]
        WAIT[Waits]
        BLOCK[Blocking]
        TOPQ[Top queries]
    end

    subgraph L5 [05 Indexes]
        IDX[Index usage]
        FRAG[Fragmentation]
        STAT[Statistics]
    end

    subgraph L6 [06 HA DR]
        AG[Always On]
        BKP[Backups]
    end

    L1 --> L2 --> L3 --> L4 --> L5 --> L6
```

---

## Framework Objects (`00_Framework/`)

### Functions

| Object | Purpose |
|--------|---------|
| `fn_DBA_ExcludedWaitTypes()` | Single source of truth for benign wait types to filter out |
| `fn_DBA_AgentRunDurationSeconds()` | Converts msdb `run_duration` (HHMMSS) to seconds |

### Core Procedures

| Object | Purpose |
|--------|---------|
| `sp_DBA_ForEachDatabase` | Cross-DB execution with `QUOTENAME`, `@DatabaseList`, `TRY/CATCH` |
| `sp_DBA_QueryStoreRegressions` | True multi-plan Query Store regression detection |
| `sp_DBA_HealthCheck` | Consolidated health check with findings table and health score |

### Wrapper Procedures

| Object | Purpose |
|--------|---------|
| `sp_DBA_WaitAnalysis` | Top wait types with categories, percentages, and recommendations |
| `sp_DBA_IndexReview` | Unused, missing indexes, and fragmentation across databases |
| `sp_DBA_SecurityAudit` | Orphaned users, sysadmin, guest access, trustworthy, password policies |
| `sp_DBA_BackupReview` | Backup SLA compliance, log chain, recovery model alignment |

### Persistence Procedures

| Object | Purpose |
|--------|---------|
| `sp_DBA_BaselineCapture` | Performance snapshot persistence (wait stats, counters, file I/O) |
| `sp_DBA_SaveAssessmentRun` | Save assessment run, findings, and metrics to history tables |
| `AssessmentFindingTableType` | Table-valued parameter type for passing findings to save proc |

### `sp_DBA_HealthCheck` parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `@DeepDive` | `0` | `1` = extra result sets (top waits, CPU queries, disk latency) |
| `@DatabaseList` | `NULL` | Comma-separated DB names; `NULL` = all online user DBs |
| `@IncludeReadOnly` | `0` | Include read-only databases when `@DatabaseList` is null |
| `@BackupHoursSLA` | `24` | Hours since last backup before critical finding |

### Procedure parameters

```sql
-- WaitAnalysis
EXEC dbo.sp_DBA_WaitAnalysis @TopN = 20, @IncludeRecommendations = 1, @MinWaitCount = 0;

-- IndexReview
EXEC dbo.sp_DBA_IndexReview
    @DatabaseList = N'SalesDB,HRDB',
    @MinPageCount = 1000,
    @IncludeFragmentation = 1,
    @IncludeMissingIndexes = 1;

-- SecurityAudit
EXEC dbo.sp_DBA_SecurityAudit @DatabaseList = NULL, @IncludeSysadminCheck = 1;

-- BackupReview
EXEC dbo.sp_DBA_BackupReview @BackupHoursSLA = 24, @BackupDaysSLA = 7;

-- BaselineCapture
EXEC dbo.sp_DBA_BaselineCapture @CaptureWaitStats = 1, @CaptureCounters = 1, @CaptureFileStats = 1;

-- SaveAssessmentRun
EXEC dbo.sp_DBA_SaveAssessmentRun
    @ServerName = @@SERVERNAME, @Profile = 'Standard', @HealthScore = 78,
    @SQLCPUPct = 85.5, @SignalWaitPct = 28.3, @MinPLEs = 120;

-- ActiveSessions (real-time session monitor)
EXEC dbo.sp_DBA_ActiveSessions;                                    -- Default: detail view of all sessions
EXEC dbo.sp_DBA_ActiveSessions @FilterDatabase = N'SalesDB';       -- Filter by database
EXEC dbo.sp_DBA_ActiveSessions @FilterWaitType = N'LCK%';          -- Filter by wait type
EXEC dbo.sp_DBA_ActiveSessions @MinCPUSeconds = 10;                -- Only sessions using >10s CPU
EXEC dbo.sp_DBA_ActiveSessions @OutputMode = 'SUMMARY';            -- Aggregated view by wait/database/app
EXEC dbo.sp_DBA_ActiveSessions @OutputMode = 'BLOCKING';           -- Blocking tree with root blocker details

-- PlanCacheAnalyzer (plan cache with anti-pattern detection)
EXEC dbo.sp_DBA_PlanCacheAnalyzer;                                 -- Default: top 15 by CPU
EXEC dbo.sp_DBA_PlanCacheAnalyzer @SortOrder = 'READS';            -- Top by logical reads
EXEC dbo.sp_DBA_PlanCacheAnalyzer @SortOrder = 'MEMORY';           -- Top by memory grants
EXEC dbo.sp_DBA_PlanCacheAnalyzer @SortOrder = 'WARNING';          -- Grouped by warning type
EXEC dbo.sp_DBA_PlanCacheAnalyzer @SortOrder = 'REGRESSION';       -- Top by avg duration (slow queries)
EXEC dbo.sp_DBA_PlanCacheAnalyzer @FilterDatabase = N'SalesDB';    -- Single database only
```

---

## Script Catalog

Every script header includes:
- **Description** — What the script checks and why it matters
- **Output** — What columns/result sets to expect
- **Action** — Concrete next steps based on the output

### `00_Framework/`

| File | Description | How to run |
|------|-------------|------------|
| `fn_DBA_ExcludedWaitTypes.sql` | Inline table function of benign wait types | Deploy once (see Installation) |
| `fn_DBA_AgentRunDurationSeconds.sql` | Parses msdb job duration encoding | Deploy once |
| `sp_DBA_ForEachDatabase.sql` | Cross-DB execution helper | Deploy once |
| `sp_DBA_QueryStoreRegressions.sql` | True QS regression detection | Deploy once |
| `sp_DBA_HealthCheck.sql` | Consolidated health orchestrator | Deploy once |
| `sp_DBA_WaitAnalysis.sql` | Wait analysis with categories | Deploy once |
| `sp_DBA_IndexReview.sql` | Index health across DBs | Deploy once |
| `sp_DBA_SecurityAudit.sql` | Security audit across DBs | Deploy once |
| `sp_DBA_BackupReview.sql` | Backup SLA and log chain | Deploy once |
| `sp_DBA_ActiveSessions.sql` | Real-time session monitor (DETAIL/SUMMARY/BLOCKING) | Deploy once |
| `sp_DBA_PlanCacheAnalyzer.sql` | Plan cache analysis with anti-pattern detection | Deploy once |
| `sp_DBA_BaselineCapture.sql` | Baseline snapshot persistence | Deploy once |
| `sp_DBA_SaveAssessmentRun.sql` | Assessment history save | Deploy once |
| `00_Install_Framework.sql` | Install order reminder | Reference only |
| `00_Deploy_Framework.sql` | T-SQL auto-deploy via xp_cmdshell + sqlcmd | Deploy all at once |
| `00_Deploy_Framework.ps1` | PowerShell auto-deploy (no xp_cmdshell needed) | Deploy all at once |

---

### `01_Server_OS/` -- Host & I/O pressure

| File | What it checks | Run when |
|------|----------------|----------|
| `cpu_utilization.sql` | Historical CPU from ring buffers, signal wait %, runnable tasks | High CPU, scheduler pressure |
| `memory_diagnostics.sql` | Target vs total memory, PLE per NUMA node, memory clerks, memory grants | Memory pressure, PLE alerts |
| `memory_bottleneck_deep_dive.sql` | Process memory, buffer pool, clerks, grants, RESOURCE_SEMAPHORE, bottleneck summary | Deep memory starvation / pressure analysis |
| `disk_latency.sql` | Read/write stalls per database file | Slow queries, PAGEIOLATCH waits |

---

### `02_Instance_Config/` -- Instance settings

| File | What it checks | Run when |
|------|----------------|----------|
| `server_configuration_audit.sql` | MAXDOP, CTFP, max memory, backup compression, DAC, etc. | Baseline audit, after migration |
| `os_integration_checks.sql` | Instant File Initialization, LPIM, trace flags | Slow file growth, memory paging |
| `database_compatibility_audit.sql` | Compatibility level vs instance, orphaned DB owner | Upgrade/migration review |

---

### `03_Storage_Engine/` -- Files & TempDB

| File | What it checks | Run when |
|------|----------------|----------|
| `database_files_growth.sql` | File size, used %, autogrowth settings (all user DBs) | Disk space alerts, autogrow events |
| `tempdb_configuration.sql` | File count, growth uniformity, PAGELATCH contention | TempDB contention, PAGELATCH waits |
| `vlf_fragmentation.sql` | VLF count per database (2016+ via `dm_db_log_info`) | Slow log backups, recovery, AG sync |
| `storage_latency_post_relocation.sql` | MDF/LDF path, per-file latency, volume placement, pending I/O | After moving data/log files to new storage |

---

### `04_Performance_Diagnostics/` -- Active bottlenecks

| File | What it checks | Run when |
|------|----------------|----------|
| `wait_statistics.sql` | Top 20 wait types with categories and recommendations | First script for "what is SQL waiting on?" |
| `wait_statistics_reference.sql` | Top 30 waits with root-cause notes and investigation commands | Learning / deep wait analysis |
| `blocking_and_deadlocks.sql` | Blocking chains, head blockers, recent deadlock XML | App timeouts, LCK% waits |
| `deadlock_analysis.sql` | Advanced deadlock analysis from XE with object contention map | Deadlock pattern investigation |
| `top_resource_queries.sql` | Top 20 queries by CPU (configurable sort in comments) | High CPU, need query text + plan |
| `plan_cache_deep_dive.sql` | Key lookups and implicit conversions in plan cache | SARGability, plan quality issues |

---

### `05_Index_Statistics/` -- Indexes & statistics (cross-database)

| File | What it checks | Run when |
|------|----------------|----------|
| `index_usage_efficiency.sql` | Missing index DMV (instance) + unused indexes (all DBs) | Write-heavy systems, index cleanup |
| `physical_stats_and_heaps.sql` | Fragmentation, forwarded records, maintenance recommendations | Index maintenance planning |
| `index_maintenance_online.sql` | Online REORGANIZE (5–30%) and REBUILD (>30%); dry-run default | Applying index maintenance |
| `statistics_freshness.sql` | Stale statistics by modification % | Plan regressions, skewed cardinality |
| `advanced_index_analysis.sql` | Lock contention per index, exact duplicate indexes | Blocking on indexes, redundant indexes |

---

### `06_HA_DR/` -- High availability & backups

| File | What it checks | Run when |
|------|----------------|----------|
| `alwayson_ag_monitor.sql` | AG replica health, sync state, send/redo queues, RPO estimate | AG not healthy, failover prep |
| `backup_verification.sql` | Last full/diff/log backup per database | Backup failures, RPO review |
| `backup_log_chain.sql` | Log backup LSN chain breaks (FULL recovery) | Log restore failures, broken chain |
| `restore_test_simulator.sql` | Restore chain validation, RPO/RTO estimation, restore command generation | DR drill, restore readiness check |

---

### `07_Security/` -- Hardening & compliance

| File | What it checks | Run when |
|------|----------------|----------|
| `authorization_audit.sql` | Trustworthy DBs, guest access, orphaned users/owners, sysadmin list | Security audit, compliance |
| `encryption_hardening.sql` | TDE status, connection encryption summary, SQL Audit config | SOC2/HIPAA prep |
| `login_audit.sql` | Sysadmin members, login policy, sa status, disabled logins | Login review |

---

### `08_Advanced/` -- Feature-specific monitoring

| File | What it checks | Run when |
|------|----------------|----------|
| `cdc_health.sql` | CDC capture latency, capture instances | CDC lag, log won't shrink |
| `query_store_health.sql` | QS state/size + true regressions + forced plans | Plan regressions, QS READ_ONLY |
| `replication_monitor.sql` | Replication agent status, undelivered commands | Replication lag (needs `distribution` DB) |
| `sql_agent_job_monitor.sql` | Failed jobs (24h), long-running vs historical avg | Job failures, backup job issues |
| `error_log_and_connectivity.sql` | Error log keywords, connectivity ring buffer | Hidden errors, login timeouts |
| `feature_deep_dive_audit.sql` | CDC jobs, QS policy, replication throughput, job owners | Deep feature config review |
| `inmemory_compression.sql` | Compression candidates + In-Memory OLTP memory | Storage optimization |
| `ultra_deep_internal_audit.sql` | TempDB breakdown, buffer pool by DB, parameter sniffing | Deep dive (can be expensive) |

---

### `09_Maintenance/` -- Operational hygiene

| File | What it checks | Run when |
|------|----------------|----------|
| `failed_jobs.sql` | Failed/cancelled SQL Agent jobs (24h), running jobs | Morning ops check |
| `last_checkdb_dates.sql` | Last CHECKDB from Ola `CommandLog` (if installed) | Corruption prevention audit |

---

### `10_Capacity_Planning/`

| File | What it checks | Run when |
|------|----------------|----------|
| `database_growth_forecast.sql` | Backup size trend (30d), autogrowth from default trace | Capacity planning, disk full risk |

---

### `11_Query_Store/`

| File | What it checks | Run when |
|------|----------------|----------|
| `regressed_queries.sql` | Wrapper for `sp_DBA_QueryStoreRegressions` | Single query suddenly slow |
| `01_multi_plan_queries.sql` | Queries with multiple plans, duration spread | Unstable performance, plan sniffing |
| `02_query_id_plan_breakdown.sql` | All plans and stats for one `query_id` | After picking a suspect from script 01 |
| `03_plan_comparison_and_force_candidate.sql` | Rank plans, flag best candidate, print FORCE command | Deciding which plan to force |
| `04_force_or_unforce_plan.sql` | `sp_query_store_force_plan` / `unforce_plan` (dry-run default) | Applying or removing a forced plan |
| `05_forced_plans_monitor.sql` | Forced plans, force failures, QS options | After forcing; periodic QS review |
| `06_query_store_wait_stats_by_plan.sql` | Wait stats per plan for one `query_id` | High elapsed but low CPU/reads |
| `07_query_plan_xml.sql` | Showplan XML for a `plan_id` | Visual plan comparison in SSMS |

---

### `12_Extended_Events/`

| File | What it checks | Run when |
|------|----------------|----------|
| `active_xe_sessions.sql` | Active XE sessions/targets, recent deadlocks from `system_health` | Deadlock investigation, XE audit |

---

### `13_Resource_Governor/`

| File | What it checks | Run when |
|------|----------------|----------|
| `resource_governor_config.sql` | RG enabled state, pools, workload groups | Workload isolation review |

---

### `14_Baselines/`

| File | What it checks | Run when |
|------|----------------|----------|
| `performance_snapshot.sql` | Point-in-time perf counters, wait stats, I/O file stats | Before/after change, incident capture |

---

### `preventive_measures/` -- Query protection & workload governance (Layered Automation)

A comprehensive preventive monitoring and enforcement framework for SQL Server production environments. Detects long-running queries, massive DML operations, and blocked applications with configurable thresholds and automatic response actions.

**Architecture: Layered Automation**
```
Layer 1: Extended Events (Always-On, Kernel-Level, Near-zero Overhead)
    ↓ Real-time event capture
Layer 2: Policy Enforcement (Stored Procedures)
    ↓ Process events and take action
Layer 3: Alert Management (Notifications)
    ↓ Email alerts to DBA team
Layer 4: Dashboard & Reporting
    ↓ Monitoring views
```

**Key Features:**
- **Real-time capture** via Extended Events (no polling delay)
- **Configurable thresholds** (default: 10s queries, 100K row DML)
- **Multiple action types**: WARN, LOG, ALERT, KILL, BLOCK
- **Email notifications** via Database Mail
- **Backward compatible**: SQL Server 2016, 2017, 2019, 2022

**Quick start (layered deployment):**
```sql
-- 1. Foundation: Create governance tables in DBARepository
:preventive_measures\01_Create_Governance_Database.sql

-- 2. Layer 1: Setup Extended Events (primary capture)
:preventive_measures\07_Setup_Extended_Events.sql

-- 3. Layer 2: Create stored procedures (02-06)
-- 4. Layer 3: Create alert management (08)
-- 5. Layer 4: Create dashboard views (09)

-- 6. Automation: Create SQL Agent jobs
:preventive_measures\10_Create_SQL_Agent_Jobs.sql

-- 7. Verify: Check XE sessions running
SELECT * FROM sys.dm_xe_session_sessions WHERE name LIKE 'Governance_%';

-- 8. Monitor: View alerts
EXEC [dbo].[sp_View_Alerts] @Hours_Back = 24;
```

| File | Layer | Description |
|------|-------|-------------|
| `01_Create_Governance_Database.sql` | Foundation | Creates governance tables in DBARepository |
| `07_Setup_Extended_Events.sql` | 1 | XE sessions for real-time capture |
| `02_Capture_Running_Queries.sql` | 2 | DMV snapshot (supplements XE) |
| `03_Check_Long_Running_Queries.sql` | 2 | Process XE + DMV for long queries |
| `04_Check_Massive_DML.sql` | 2 | Process XE + DMV for massive DML |
| `05_Check_Blocked_Applications.sql` | 2 | Check blocked applications |
| `06_Enforce_Query_Policy.sql` | 2 | Master enforcement orchestrator |
| `08_Alert_Management.sql` | 3 | Alert management and notifications |
| `09_Dashboard_Views.sql` | 4 | Monitoring views |
| `10_Create_SQL_Agent_Jobs.sql` | Automation | SQL Agent jobs |
| `11_Setup_Resource_Governor.sql` | Optional | RG configuration (Enterprise only) |

See [preventive_measures/README.md](preventive_measures/README.md) for full documentation.

---

## How to Run -- Patterns

### Pattern A: Standalone script (most files)

```sql
-- 1. Open .sql file in SSMS
-- 2. Connect to target instance
-- 3. Execute entire batch (F5)
```

> Each script header includes an **Action:** section with concrete next steps based on the output — check the header comments after running to know what to do.

### Pattern B: Stored procedure (after install)

```sql
USE DBARepository;
EXEC dbo.sp_DBA_HealthCheck @DeepDive = 0;
EXEC dbo.sp_DBA_WaitAnalysis @TopN = 20;
EXEC dbo.sp_DBA_IndexReview @DatabaseList = N'SalesDB';
EXEC dbo.sp_DBA_SecurityAudit;
EXEC dbo.sp_DBA_BackupReview @BackupHoursSLA = 24;
EXEC dbo.sp_DBA_BaselineCapture;
EXEC dbo.sp_DBA_QueryStoreRegressions @RegressionPctThreshold = 50;
EXEC dbo.sp_DBA_ForEachDatabase @Command = N'SELECT DB_NAME(), COUNT(*) FROM sys.tables;';
```

### Pattern C: Cross-database with parameters

Edit variables at the top of the script:

```sql
DECLARE @DatabaseList NVARCHAR(MAX) = N'ProdDB1,ProdDB2';
DECLARE @StalePctThreshold DECIMAL(5,2) = 20.0;
-- ... rest of script runs automatically
```

### Pattern D: sqlcmd automation

```bash
# Note: Add -C to trust server certificate (required for ODBC Driver 18+)
sqlcmd -S ProdServer -d DBARepository -i "04_Performance_Diagnostics/wait_statistics.sql" -o waits.txt -C
```

### Pattern F: Deploy framework objects in one command

```powershell
# PowerShell (no xp_cmdshell required)
.\00_Framework\00_Deploy_Framework.ps1 -ServerInstance "ProdServer" -Database "DBARepository"

# T-SQL (requires xp_cmdshell)
-- Open 00_Framework/00_Deploy_Framework.sql in SSMS, set @TargetDB, and execute
```

### Pattern E: PowerShell HTML report

```powershell
cd powershell
.\Invoke-SqlOptimaAssessment.ps1 -SqlInstance 'PROD-SQL01' -Profile Standard -OutputPath '.\output'
```

---

## Safety Notes

- Scripts are designed to be **read-only** (DMVs, catalog views, `msdb` history). They do not modify data or settings.
- `sp_DBA_HealthCheck` may suggest remediation commands in output -- **review before executing** any `ALTER` or `EXEC sp_configure`.
- `physical_stats_and_heaps.sql` and `index_maintenance_online.sql` (collection phase) and `ultra_deep_internal_audit.sql` can be **expensive** on large databases -- prefer off-peak or scope with `@DatabaseList`.
- Do not create indexes solely from `dm_db_missing_index_*` DMVs -- always validate overlap and write overhead.
- Do not drop "unused" indexes without confirming uptime since last restart and business sign-off.
- `sp_DBA_BaselineCapture` writes to `dbo.BaselineSnapshot` -- ensure the persistence table exists (run `DBARepository_Persistence.sql`).
- All scripts use **dynamic SQL** for version-conditional DMV queries. This is necessary because SQL Server validates all branches at compile time, even branches that won't execute. The `@MajorVersion` variable is derived from `SERVERPROPERTY('ProductVersion')` and branches use `IF @MajorVersion >= 16 EXEC(N'...')` pattern.

---

## Related Documentation

| File | Contents |
|------|----------|
| [00_Framework/README.md](00_Framework/README.md) | Framework install order and cross-DB script list |
| [00_Repository/README.md](00_Repository/README.md) | DBARepository DDL, deploy scripts, persistence tables |
| [powershell/README.md](powershell/README.md) | Automated assessment and HTML report generation |

---

## Contributing & Customization

Common customizations:

1. **Thresholds** -- Most scripts use variables at the top (`@StalePctThreshold`, `@BackupHoursSLA`, etc.).
2. **SLA values** -- Adjust backup and CHECKDB day thresholds for your environment.
3. **Database scope** -- Use `@DatabaseList` to limit heavy scripts to specific databases.
4. **Scheduling** -- Automate `sp_DBA_HealthCheck` and `sp_DBA_BaselineCapture` via SQL Agent jobs.
5. **Assessment config** -- Edit `powershell/config/assessment.config.json` to toggle sections and profiles.

---

## License

Copyright (c) Ravi Sharma. All rights reserved. See individual script headers for attribution notes.
