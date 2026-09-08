# SQL Server 2016 Enterprise → SQL Server 2022 Enterprise Migration Plan

**Document purpose:** Planning guide for migrating a production SQL Server 2016 Enterprise instance to SQL Server 2022 Enterprise.

**Target audience:** DBA team, infrastructure, application owners, change management, and project stakeholders.

**Last updated:** July 2026

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Support Lifecycle Context](#2-support-lifecycle-context)
3. [Features and Changes to Consider (2016 → 2022)](#3-features-and-changes-to-consider-2016--2022)
4. [Deprecated, Discontinued, and Breaking Changes](#4-deprecated-discontinued-and-breaking-changes)
5. [Migration Strategy Options](#5-migration-strategy-options)
6. [Detailed Migration Plan (Phased)](#6-detailed-migration-plan-phased)
7. [Pre-Migration Checklist](#7-pre-migration-checklist)
8. [Migration Execution Procedures](#8-migration-execution-procedures)
9. [Compatibility Level and Query Plan Strategy](#9-compatibility-level-and-query-plan-strategy)
10. [Testing Strategy](#10-testing-strategy)
11. [Cutover Plan](#11-cutover-plan)
12. [Post-Migration Validation](#12-post-migration-validation)
13. [Rollback Strategy](#13-rollback-strategy)
14. [Project Timeline Template](#14-project-timeline-template)
15. [Roles and Responsibilities](#15-roles-and-responsibilities)
16. [Tools and References](#16-tools-and-references)
17. [Repository Script Cross-Reference](#17-repository-script-cross-reference)
18. [Four Parallel Migration Tracks](#18-four-parallel-migration-tracks)
19. [Feature, Security, Agent, and Client Inventories](#19-feature-security-agent-and-client-inventories)
20. [HA/DR and Replication Deep Checklist](#20-hadr-and-replication-deep-checklist)
21. [Performance Baseline and Regression Playbook](#21-performance-baseline-and-regression-playbook)
22. [Common Field Issues (2016 → 2022)](#22-common-field-issues-2016--2022)

---

## 1. Executive Summary

SQL Server 2016 reached the end of extended support on **July 14, 2026**. Continuing on 2016 exposes the organization to unpatched security vulnerabilities, compliance risk, and lack of vendor support for critical incidents.

**Recommended target:** SQL Server 2022 Enterprise (16.x) on a supported Windows Server release (Windows Server 2019 or Windows Server 2022).

**Supported upgrade path:** Direct in-place upgrade from **SQL Server 2016 SP3 or later Enterprise** to **SQL Server 2022 Enterprise** is supported by Microsoft. Side-by-side migration (new instance + database restore/log shipping/AG) is often preferred for production because it reduces cutover risk and provides a clearer rollback path.

**Important:** A production migration is not only an engine upgrade. It is **four parallel migrations** — SQL Server Engine, Application, Infrastructure, and Operations. Large enterprise migrations usually fail in the last three tracks, not because `@@VERSION` changed. See [Section 18](#18-four-parallel-migration-tracks).

**Key planning themes:**

| Theme | Why it matters |
| --- | --- |
| Application certification | Third-party ERP/LOB apps must certify SQL Server 2022 and Windows version |
| Driver and client stack | SQL Server Native Client (SNAC) is removed in 2022; clients must use modern ODBC/OLE DB drivers |
| Compatibility level | Databases may remain at level 130 initially; level 160 enables 2022 optimizer features but can change plans |
| HA/DR redesign | Always On, log shipping, and replication must be reconfigured on the new instance |
| Security baseline | TLS 1.2+, TDS 8.0, Entra ID auth, and stricter encryption defaults may affect legacy apps |
| Feature inventory | Stretch Database, Hadoop PolyBase, Distributed Replay, and bundled ML runtimes changed or removed |
| Performance regression control | Cardinality Estimator / Query Store / staged compat is the #1 field issue after cutover |
| Multi-level rollback | Application, SQL, infrastructure, and data replay paths must be pre-defined |

---

## 2. Support Lifecycle Context

| Version | Release | Extended Support End | Status (July 2026) |
| --- | --- | --- | --- |
| SQL Server 2016 (13.x) | 2016 | **July 14, 2026** | **End of support** |
| SQL Server 2017 (14.x) | 2017 | October 12, 2027 | Supported (interim only — not recommended as long-term target) |
| SQL Server 2019 (15.x) | 2019 | January 8, 2030 | Supported |
| SQL Server 2022 (16.x) | 2022 | January 11, 2033 | **Recommended target** |

**Implication:** Migrating to 2022 provides the longest mainstream support runway and access to current security patches, cumulative updates, and Azure hybrid features.

---

## 3. Features and Changes to Consider (2016 → 2022)

Features below are cumulative across **2017**, **2019**, and **2022**. When planning, treat the jump as three major releases, not one.

### 3.1 Security and Compliance

| Feature / Change | Introduced | Migration Consideration |
| --- | --- | --- |
| **Microsoft Entra ID (Azure AD) authentication** | 2022 | Optional but recommended for hybrid/cloud identity; requires Azure Arc extension for some Purview/Defender integrations |
| **TDS 8.0 / mandatory encryption** | 2022 | New protocol makes encryption mandatory; legacy clients or network appliances may need updates |
| **TLS 1.3 support** | 2022 | Review client drivers, load balancers, and firewall SSL inspection |
| **Ledger (tamper-evident tables)** | 2022 | Optional post-migration feature for audit/compliance workloads |
| **Always Encrypted with secure enclaves** | 2019 (enhanced 2022) | If used, validate enclave host and driver versions on 2022 |
| **Granular permissions / new server roles** | 2022 | Review elevated `sysadmin` accounts; adopt least-privilege admin roles |
| **Dynamic Data Masking UNMASK granularity** | 2022 | Review masking policies if DDM is in use |
| **Row-Level Security** | 2016+ | Continues; verify app behavior under new compatibility levels |
| **Transparent Data Encryption (TDE)** | 2016+ | Certificates/keys migrate; validate backup of service master key and database encryption keys |
| **SQL Server Native Client (SNAC) removed** | 2022 | **Critical:** Audit all apps, SSIS, linked servers, and ODBC connections using SQLNCLI/SQLOLEDB |

### 3.2 High Availability and Disaster Recovery

| Feature / Change | Introduced | Migration Consideration |
| --- | --- | --- |
| **Contained Availability Groups** | 2022 | Optional; AG-level logins/jobs/metadata — evaluate for multi-tenant or simplified DR |
| **Distributed AG improvements** | 2022 | Multi-TCP connection for better WAN bandwidth on cross-site AG |
| **Link to Azure SQL Managed Instance** | 2022 | Near-zero-downtime DR/migration path to Azure MI |
| **Readable secondary Query Store** | 2022 | Enables plan regression detection on read-only replicas |
| **Automatic seeding / improved AG** | 2017–2019 | Rebuild AG topology on 2022; do not assume 2016 AG config transfers unchanged |
| **Accelerated Database Recovery (ADR)** | 2019 (improved 2022) | Enable post-migration after sizing Persistent Version Store (PVS) in the user DB or a dedicated filegroup; monitor PVS growth |
| **Backup/restore to S3-compatible storage** | 2022 | Optional modernization of backup target |
| **Improved snapshot backup (T-SQL freeze/thaw)** | 2022 | Simplifies VSS-free snapshot coordination for storage arrays |

### 3.3 Performance and Query Processing

| Feature / Change | Introduced | Migration Consideration |
| --- | --- | --- |
| **Intelligent Query Processing (IQP)** | 2017–2022 | Batch mode for rowstore, adaptive joins, memory grant feedback, interleaved execution (2017–2019); CE feedback, DOP feedback, PSP optimization (2022) |
| **Query Store** | 2016 (default ON for new DBs in 2022) | Enable before compat level change; use for regression detection |
| **Query Store hints** | 2022 | Plan shaping without code change (requires Query Store ON) |
| **Parameter Sensitive Plan (PSP) optimization** | 2022 | Can fix or change behavior for skewed parameters — test heavily; **require latest CU** (early CU edge bugs) |
| **Optimized locking** | 2022 (CU) | Reduces lock memory and blocking for some workloads — evaluate per database |
| **Memory-optimized TempDB metadata** | 2019 | Reduces TempDB latch contention; enable if TempDB is a bottleneck |
| **Buffer pool parallel scan** | 2022 | Benefits large-memory servers (>8 GB buffer pool) |
| **GAM/SGAM page latch improvements** | 2022 | Especially benefits TempDB-heavy workloads |
| **Instant File Initialization for log growth ≤64 MB** | 2022 | Reduces WRITELOG waits on log autogrowth |
| **VLF creation algorithm changes** | 2022 | Fewer VLFs on certain growth patterns; monitor `dm_db_log_info` post-migration |
| **Ordered clustered columnstore index** | 2022 | Columnstore workloads only |
| **Batch mode on rowstore (2019+)** | 2019 | Plan changes possible when compat ≥150 |

### 3.4 Manageability and Operations

| Feature / Change | Introduced | Migration Consideration |
| --- | --- | --- |
| **Automatic (Delayed Start) for SQL service** | 2022 | Service shows Automatic but starts delayed — document for DR runbooks |
| **Max server memory recommendation at setup** | 2022 | Setup suggests memory differently; validate against workload |
| **Resumable index/add constraint operations** | 2017–2022 | Useful for large-table maintenance windows |
| **Online index `WAIT_AT_LOW_PRIORITY`** | 2022 | Reduces blocking during index rebuilds |
| **`DBCC SHRINK` / stats `WAIT_AT_LOW_PRIORITY`** | 2022 | Safer shrink and async stats update concurrency |
| **XML compression** | 2022 | Capacity optimization for XML-heavy schemas |
| **Extended Events improvements** | 2017–2022 | Replace deprecated SQL Trace where still in use |

### 3.5 Analytics, Integration, and Data Platform

| Feature / Change | Introduced | Migration Consideration |
| --- | --- | --- |
| **Azure Synapse Link for SQL** | 2022 | Near-real-time analytics to Synapse without ETL jobs |
| **PolyBase enhancements / S3 data lake virtualization** | 2019–2022 | Hadoop HDFS **removed** in 2022 — migrate external data sources |
| **Stretch Database** | 2016 | **Discontinued July 2024** — must migrate stretched tables back on-premises before upgrade |
| **Machine Learning Services (R/Python/Java)** | 2016–2019 | Runtimes **not bundled** in 2022 setup — reinstall separately if needed |
| **Distributed Replay** | Pre-2022 | Deprecated; not in 2022 setup media — separate download if still required |
| **JSON, Graph, UTF-8, temporal tables** | 2016–2019 | Generally backward compatible; validate UTF-8 catalog collation choice at install |

### 3.6 T-SQL and Developer Features (Selected)

| Feature | Minimum Compat / Version | Notes |
| --- | --- | --- |
| `STRING_AGG`, `TRIM`, `CONCAT_WS` | 2017+ / 140+ | Widely used; verify if app targets 2016-only syntax |
| `GREATEST` / `LEAST` | 2022 / 160 | New in 2022 |
| `DATETRUNC`, `DATE_BUCKET`, `GENERATE_SERIES` | 2022 / 160 | Time-series helpers |
| `JSON_OBJECT`, `JSON_ARRAY`, `JSON_PATH_EXISTS` | 2022 / 160 | Enhanced JSON |
| `APPROX_PERCENTILE_CONT/DISC` | 2022 / 160 | Approximate aggregates |
| `SELECT ... WINDOW` clause | 2022 / 160 | Window function syntax sugar |
| `IS [NOT] DISTINCT FROM` | 2022 / 160 | NULL-safe comparison |
| Bit manipulation functions | 2022 / 160 | `LEFT_SHIFT`, `GET_BIT`, etc. |

### 3.7 Edition and Licensing (Enterprise → Enterprise)

Staying on **Enterprise** preserves:

- Always On Availability Groups (multi-database)
- Online indexing, partition switching, compression
- Resource Governor, advanced security features
- Larger compute and memory limits vs Standard

**Validate:** Core vs Server+CAL licensing, Software Assurance benefits, and whether any 2016 components (e.g., BI edition remnants) affect license compliance on 2022.

---

## 4. Deprecated, Discontinued, and Breaking Changes

Complete this inventory **before** signing off on the migration approach.

### 4.1 Discontinued in SQL Server 2022 (Must Remediate)

| Item | Action Required |
| --- | --- |
| **SQL Server Native Client (SQLNCLI11)** | Replace with [Microsoft ODBC Driver 18](https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server) or [OLE DB Driver 19](https://learn.microsoft.com/sql/connect/oledb/download-oledb-driver-for-sql-server) |
| **Legacy SQLOLEDB provider** | Same as above |
| **PolyBase Hadoop (HDFS) external data sources** | Recreate with supported connectors (S3, Azure, Oracle, etc.) |
| **PolyBase scale-out groups** | Use scale-up PolyBase only |
| **Stretch Database** | Unstretch all tables; feature discontinued |
| **SQL Server Big Data Clusters** | Retired; migrate workloads if present |
| **Bundled R/Python/Java ML runtimes in setup** | Install ML Services separately post-setup if needed |

### 4.2 Deprecated (Still Works but Plan Exit)

| Item | Notes |
| --- | --- |
| Distributed Replay | Separate download; plan alternative load testing |
| Machine Learning Server (standalone) | Deprecated |
| Stretch Database | Discontinued — do not defer remediation |
| SQL Server Profiler | Use Extended Events |
| `sp_configure` 'allow updates' | Do not use |
| Database Mirroring | Deprecated since 2012; migrate to Always On AG |

### 4.3 Behavior Changes That Often Surprise Migrations

| Area | Change | Mitigation |
| --- | --- | --- |
| **Cardinality Estimator** | Compat 130 vs 160 uses different CE models | Test with Query Store; use CE feedback or hints only after evidence |
| **Query Store default ON** | New databases only; upgraded DBs retain old settings | Explicitly enable Query Store on migrated databases before compat change |
| **Parallelism defaults** | 2022 setup may recommend different MAXDOP/CTFP | Run configuration audit post-migration |
| **TempDB** | 2022 benefits from multiple files, proper sizing | Pre-size TempDB; consider memory-optimized metadata (2019+) |
| **Trace flags** | Old TF from 2016 may hurt or be ignored on 2022 | Document and test each trace flag |
| **Linked servers** | Provider names must change if using SNAC | Update `MSDASQL`/OLE DB provider registration |
| **SSIS / SSRS / SSAS** | Separate install lifecycle | Upgrade BI stack in coordinated window |
| **Collation / UTF-8** | UTF-8 catalog collation is install-time choice | Cannot change catalog collation in-place; plan at install |
| **Replication / CDC** | Supported but must be reconfigured on new instance | Script publications, subscriptions, CDC jobs |

### 4.4 Deprecated Feature Detection Script (Run on Source)

```sql
-- Monitor deprecated feature usage on SQL Server 2016 source
SELECT *
FROM sys.dm_os_performance_counters
WHERE counter_name LIKE 'Deprecated%'
  AND cntr_value > 0;

-- Extended Events: capture deprecation_announcement and deprecation_final_support
-- Use SSMS Migration component or DMA for full assessment report
```

### 4.5 Source-Code Search for Deprecated T-SQL (Required)

Performance counters alone are incomplete. Search modules for legacy syntax:

```sql
-- Examples of patterns to hunt across databases (adjust LIKE patterns)
SELECT DB_NAME() AS db_name, OBJECT_SCHEMA_NAME(object_id) AS sch, OBJECT_NAME(object_id) AS obj_name
FROM sys.sql_modules
WHERE definition LIKE N'%TEXT%'
   OR definition LIKE N'%NTEXT%'
   OR definition LIKE N'%IMAGE%'
   OR definition LIKE N'%COMPUTE BY%'
   OR definition LIKE N'%FASTFIRSTROW%'
   OR definition LIKE N'%DBCC DBREINDEX%'
   OR definition LIKE N'%DBCC INDEXDEFRAG%'
   OR definition LIKE N'%*=%'
   OR definition LIKE N'%=*%';  -- old outer-join operators
```

Also review: `RAISERROR` severity patterns, `HOLDLOCK` misuse, Profiler traces still in use, Database Mail vs SQL Mail, and `xp_cmdshell` / OLE Automation usage.

---

## 5. Migration Strategy Options

### 5.1 Strategy Comparison

| Strategy | Downtime | Risk | Rollback | Best For |
| --- | --- | --- | --- | --- |
| **A. In-place upgrade** | Low–medium (single window) | Medium–high | Hard (restore full backup) | Dev/test, small instances, strict hardware reuse |
| **B. Side-by-side + backup/restore** | Medium | Low–medium | Easy (revert DNS/connection) | Most production Enterprise workloads |
| **C. Side-by-side + log shipping** | Low | Low | Easy | Large databases, minimal downtime |
| **D. Always On migration** | Very low | Medium | Moderate | Existing AG environments, HA required during migration |
| **E. Replication / CDC sync** | Low | Medium | Moderate | Very large DBs, selective cutover |
| **F. Azure MI Link / DMA migrate** | Varies | Low–medium | Varies | Hybrid cloud DR or future Azure path |

### 5.2 Recommended Approach for Enterprise Production

**Primary recommendation:** **Side-by-side migration (Strategy B or C)** onto new Windows Server 2022 + SQL Server 2022 Enterprise hardware/VM, with:

1. DMA / SSMS Upgrade Assessment on source
2. Full regression test on non-production clone
3. Log shipping or AG for cutover synchronization
4. Application connection string cutover via listener or DNS
5. Keep source instance powered off but recoverable for 30+ days

**In-place upgrade** is acceptable when:

- Source is already at **SQL Server 2016 SP3+**
- Hardware and OS are supported for 2022
- Downtime window is approved
- Full backup and tested restore exist
- No Stretch/Hadoop/SNAC blockers remain

---

## 6. Detailed Migration Plan (Phased)

### Phase -0 — Compatibility Assessment (Before Discovery)

Run automated assessment **before** deep manual discovery. These tools surface many blockers early:

| Tool | Purpose |
| --- | --- |
| **Microsoft Data Migration Assistant (DMA)** | Breaking changes, deprecated features, compatibility issues |
| **SSMS Migration / Upgrade Assessment** | Upgrade advisor report for objects and remediation |
| **SQL Assessment API** | Rule-based best-practice and risk findings |
| **dbatools `Test-DbaBuild`** | Build/CU currency and known issues |
| **First Responder Kit** (`sp_Blitz`, `sp_BlitzCache`, `sp_BlitzIndex`, `sp_BlitzFirst`) | Health, plan, index, and wait findings (if licensed/available in environment) |
| **Repository scripts** | `Migration_2016_to_2022/13_pre_migration_readiness.sql` and related inventory scripts |

**Exit criteria:** Assessment pack archived; P1/P2 blockers assigned owners before Phase 1 begins.

### Phase 0 — Initiation and Governance (Weeks 1–2)

| Task | Owner | Deliverable |
| --- | --- | --- |
| Executive approval and budget | Project sponsor | Signed charter |
| Identify application owners and dependency map | DBA + App teams | Application inventory |
| Confirm SQL 2022 Enterprise licensing | Licensing | License keys / volume activation |
| Open change management records | Change manager | CR/RFC numbers |
| Define RTO/RPO and downtime budget | DBA + Business | SLA document |
| Confirm vendor support for SQL 2022 | App vendors | Certification matrix |
| Assign owners for all four tracks (Engine / App / Infra / Ops) | PM | RACI for Section 18 |

### Phase 1 — Discovery and Assessment (Weeks 2–4)

| Task | Details |
| --- | --- |
| **Instance inventory** | Version, edition, patch level (must be SP3+), collation, trace flags, linked servers |
| **Database inventory** | Size, compatibility level, TDE, FileStream, memory-optimized objects, CDC, Change Tracking |
| **System database compatibility evaluation** | Native upgrade leaves `master` / `msdb` / `model` at compat **130** (supported). Inventory custom objects, login triggers, and DBA utility code in `master`; test thoroughly before any manual raise to 160 |
| **Full feature inventory** | Service Broker, Full-Text, CLR, XML/Spatial indexes, partitions, Resource Governor, audits, Database Mail, SSISDB — see [Section 19](#19-feature-security-agent-and-client-inventories) |
| **Hardware / OS assessment** | CPU/NUMA, power plan, VM generation, storage latency, IFI, LPIM, TLS/ciphers — see [Section 19.8](#198-hardware-and-os-assessment-checklist) |
| **Workload profiling** | Peak hours, batch windows, ETL schedules, maintenance jobs |
| **Performance baseline capture** | Waits, top CPU/reads/writes/duration, blocking, memory grants — see [Section 21](#21-performance-baseline-and-regression-playbook) |
| **HA/DR topology** | AG, mirroring (legacy), log shipping, replication, backup tools — see [Section 20](#20-hadr-and-replication-deep-checklist) |
| **Security audit** | Logins, server roles, orphaned users, certificates, SMK/DMK, credentials, audits, encryption hierarchy |
| **Integration audit** | SSIS packages, linked servers, PolyBase, ML, SQL Agent jobs, proxies, operators, alerts |
| **Client connectivity audit** | Dedicated SNAC/OLE DB/ODBC/DSN/Power BI/Excel/Access/SSRS inventory — see [Section 19.5](#195-snac--client-provider-checklist-critical) |
| **TLS / encryption connectivity tests** | Encrypt=True, TrustServerCertificate, Force Encryption, cert chain — see [Section 19.6](#196-tls--encryption-connectivity-checklist) |
| **Run DMA / SSMS Upgrade Assessment** | Breaking changes, deprecated features, compatibility issues |
| **Run SQL Assessment API / Blitz suite (if available)** | Automated health and risk findings |
| **Deprecated T-SQL code search** | `sys.sql_modules` pattern hunt (Section 4.5) |

**Exit criteria:** Assessment report signed off; blockers logged with remediation owners.

### Phase 2 — Target Environment Design (Weeks 3–5)

| Design Area | Recommendations for 2022 Enterprise |
| --- | --- |
| **OS** | Windows Server 2022 (preferred) or 2019; fully patched |
| **Hardware/VM** | Meet 2022 compute/storage guidance; separate volumes for data, log, TempDB, backup |
| **Instance naming** | Default or named instance; document connection abstraction (listener) |
| **Collation** | Match source server collation; decide UTF-8 catalog collation at install if greenfield benefit |
| **Storage** | 64 KB partition alignment; flash for log/TempDB if possible; test latency (<5 ms log ideal) |
| **TempDB** | 1 file per CPU up to 8 (then add in multiples of 4); equal size; large initial size |
| **Max server memory** | Leave 4–6 GB+ for OS; validate on load test |
| **MAXDOP / CTFP** | Follow Microsoft guidance (often MAXDOP 4–8 for OLTP; adjust per NUMA) |
| **Instant File Initialization** | Grant `Perform volume maintenance tasks` to SQL service account |
| **Antivirus exclusions** | SQL data/log/backup paths excluded |
| **Backup strategy** | Full/diff/log; test restore; optional S3 URL backup |
| **Monitoring** | Extended Events, Query Store, baseline alerts, third-party monitoring |
| **Security baseline** | TLS 1.2 minimum; disable sa; gMSA for service accounts; audit as required |

**Deliverable:** Target architecture diagram + build specification document.

### Phase 3 — Build and Configure Target (Weeks 5–7)

1. Provision Windows Server and join domain
2. Install SQL Server 2022 Enterprise (latest CU recommended)
3. Install latest cumulative update (CU) — never go live on RTM only
4. Apply post-install configuration:
   - `sp_configure` settings (max memory, MAXDOP, backup compression, optimize for ad hoc workloads)
   - Evaluate `ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON` (restart required) for high-concurrency TempDB
   - Enable Trace Flag 1118/1117 only if still justified (TempDB file strategy preferred over legacy TF)
   - Configure SQL Server Audit if required
   - Install SQL Server Agent jobs (non-DB-specific)
5. Install SSIS/SSRS/SSAS if applicable (matching or upgraded versions)
6. Install **ODBC Driver 18** and **OLE DB Driver 19** on application servers
7. Install SSMS 21+ (or current) on admin workstations
8. Configure firewall rules (1433, AG port 5022, etc.)
9. Validate backup to disk/share/S3
10. Plan **ADR** (Accelerated Database Recovery) per user database: size Persistent Version Store (PVS) in-DB or on a dedicated filegroup; do not enable day-one without PVS capacity plan

**Exit criteria:** Empty instance passes configuration audit; admin connectivity confirmed.

### Phase 4 — Non-Production Migration Pilot (Weeks 6–9)

| Step | Action |
| --- | --- |
| 1 | Restore production backup to **UAT** 2022 instance (or log-ship clone) |
| 2 | Migrate logins with **dbatools** `Export-DbaLogin` / `Import-DbaLogin` (preferred) or `sp_help_revlogin` |
| 3 | Fix orphaned users |
| 4 | Enable Query Store on UAT databases |
| 5 | Run application regression suite |
| 6 | Run SQL load tests (HammerDB, replay traces, or Distributed Replay if retained) |
| 7 | Test compat level 130 vs 140 vs 150 vs 160 incrementally |
| 8 | Document plan regressions and remediations |
| 9 | Validate SSIS/SSRS/reporting chain |
| 10 | Sign off UAT from application owners |

**Exit criteria:** UAT sign-off with zero P1/P2 open defects related to SQL upgrade.

### Phase 5 — Production Migration Preparation (Weeks 8–10)

| Task | Details |
| --- | --- |
| Final DMA assessment | Re-run on production (read-only) |
| Freeze schema changes | Change advisory 2 weeks before cutover |
| Pre-cutover full backup | Verified restore on target |
| Prepare runbook | Step-by-step with timings and rollback triggers |
| Prepare communication | User notification, war room, escalation tree |
| Configure log shipping or AG | Target secondary synchronized |
| Script cutover | Agent jobs, SQL Agent schedules, maintenance plans, operators, alerts |
| Prepare linked servers | Recreate on target with updated providers |
| Replication / CDC | Script and pre-stage if used |

### Phase 6 — Production Cutover (Migration Weekend)

See [Section 11 — Cutover Plan](#11-cutover-plan).

### Phase 7 — Stabilization (Weeks 11–14)

| Task | Frequency |
| --- | --- |
| Monitor blocking, waits, CPU, I/O | Daily (first 2 weeks) |
| Review Query Store regressions | Daily |
| Validate backups and restore test | Weekly |
| Tune MAXDOP, memory, TempDB | As needed |
| Increment compatibility level (if deferred) | After 2–4 weeks stable |
| Decommission source instance | After 30-day parallel retention |
| Post-implementation review | End of week 4 |

---

## 7. Pre-Migration Checklist

### 7.1 Source Instance Readiness

- [ ] SQL Server 2016 **SP3 or later** confirmed (`SELECT @@VERSION`)
- [ ] Latest 2016 security CU applied (final patch baseline documented)
- [ ] Phase -0 assessment pack complete (DMA / SSMS Upgrade Assessment / Assessment API)
- [ ] Full instance metadata documented (sp_configure, trace flags, collations)
- [ ] Full feature inventory complete (Section 19.1) including Service Broker, FTS, CLR
- [ ] All databases integrity-checked (`DBCC CHECKDB` within 30 days)
- [ ] Full backup chain verified (including TDE certs/master key backup)
- [ ] Encryption hierarchy backups verified (Section 19.7)
- [ ] No Stretch Database objects remain
- [ ] No PolyBase Hadoop external data sources (or remediation plan executed)
- [ ] SNAC-dependent applications identified and remediation scheduled (Section 19.5)
- [ ] Deprecated T-SQL code search completed (Section 4.5)
- [ ] DMA / SSMS assessment report reviewed and exceptions approved

### 7.2 Application and Client Readiness

- [ ] Vendor certification for SQL Server 2022 obtained
- [ ] Connection strings updated to ODBC 18 / OLE DB 19 / JDBC 12+
- [ ] DSNs, Power BI, Excel, Access, SSRS data sources inventoried and tested
- [ ] TLS 1.2+ / Encrypt / certificate tests passed from all app tiers (Section 19.6)
- [ ] Connection pool settings validated under load
- [ ] Linked server provider mappings updated (Section 19.4)

### 7.3 Infrastructure Readiness

- [ ] Target server meets hardware sizing (CPU, RAM, IOPS)
- [ ] Hardware/OS checklist complete (NUMA, power plan, IFI, LPIM, RSS) — Section 19.8
- [ ] Windows Server version supported for SQL 2022
- [ ] Service accounts (gMSA preferred) provisioned
- [ ] Firewall rules and AG endpoints configured
- [ ] Backup infrastructure capacity verified
- [ ] Monitoring and alerting extended to target

### 7.4 Organizational Readiness

- [ ] Change window approved
- [ ] Rollback Levels 1–5 documented and tabletop-tested (Section 13)
- [ ] Owners assigned for Engine / App / Infra / Ops tracks (Section 18)
- [ ] Runbook reviewed in dry-run tabletop exercise
- [ ] Support contacts (Microsoft, vendor, storage) confirmed for cutover window

### 7.5 SQL Agent / Operations Readiness

- [ ] Jobs, schedules, proxies, operators, alerts validated (Section 19.3)
- [ ] SSISDB / maintenance plans / job output paths ready on target
- [ ] Replication plan validated if used (Section 20.2)
- [ ] Pre-cutover performance baseline captured (Section 21)
---

## 8. Migration Execution Procedures

### 8.1 Option A — In-Place Upgrade (Single Instance)

**Prerequisites:** SQL Server 2016 SP3+ Enterprise; supported OS; full backup; rollback media available.

| Step | Action |
| --- | --- |
| 1 | Notify stakeholders; stop non-critical SQL Agent jobs |
| 2 | Capture pre-upgrade baseline (wait stats, top queries, config) |
| 3 | Take full backup of all user databases and system databases |
| 4 | Export logins (sp_help_revlogin) and document Agent jobs, SSIS, linked servers |
| 5 | Stop dependent services (SSIS, apps if required) |
| 6 | Run SQL Server 2022 Enterprise setup → **Upgrade** |
| 7 | Select same instance name; apply latest CU after upgrade |
| 8 | Verify `SELECT @@VERSION` shows 16.x |
| 9 | Run `DBCC UPDATEUSAGE` if recommended; update statistics on critical tables |
| 10 | Restart SQL Server; run post-upgrade configuration report |
| 11 | Smoke-test applications |
| 12 | Re-enable jobs and monitoring |

**Important:** In-place upgrade **does not** change database compatibility level automatically beyond what was set. Databases remain at 130 until explicitly altered.

### 8.2 Option B — Side-by-Side Backup/Restore

| Step | Action |
| --- | --- |
| 1 | Build SQL Server 2022 instance (Phase 3) |
| 2 | Migrate logins to target |
| 3 | Restore latest full backup of each database WITH RECOVERY |
| 4 | Restore differential (if any) and transaction log backups to point-in-time |
| 5 | Set database owner (`ALTER AUTHORIZATION`) |
| 6 | Map orphaned users |
| 7 | Enable SQL Agent jobs on target (disabled initially) |
| 8 | Validate AG/listener if applicable |
| 9 | Cutover connection strings |
| 10 | Disable source jobs; enable target jobs |

### 8.3 Option C — Log Shipping Cutover

| Step | Action |
| --- | --- |
| 1 | Configure log shipping: primary (2016) → secondary (2022) |
| 2 | Monitor latency until consistently low |
| 3 | At cutover: put apps in read-only mode on primary |
| 4 | Take final log backup; restore on secondary WITH RECOVERY |
| 5 | Run `DBCC CHECKDB` on secondary |
| 6 | Redirect applications to secondary (now primary) |
| 7 | Rebuild log shipping/AG in reverse if keeping old server as DR |

### 8.4 Option D — Always On Availability Group Migration

| Step | Action |
| --- | --- |
| 1 | Create WSFC on Windows Server 2022 nodes |
| 2 | Install SQL 2022 on primary and secondary nodes |
| 3 | Create AG on new cluster; add databases via automatic seeding or backup |
| 4 | Add read-only routing if used |
| 5 | Validate synchronization |
| 6 | Failover to 2022 replica during cutover |
| 7 | Remove old 2016 replica from AG; decommission |

---

## 9. Compatibility Level and Query Plan Strategy

### 9.1 Compatibility Level Reference

| SQL Server Version | Compatibility Level |
| --- | --- |
| SQL Server 2016 | 130 |
| SQL Server 2017 | 140 |
| SQL Server 2019 | 150 |
| SQL Server 2022 | 160 |

### 9.2 Recommended Staged Approach

**Do not jump to 160 on cutover day unless UAT proves zero regressions.**

| Stage | Timing | Action |
| --- | --- | --- |
| **Stage 1** | Cutover | Remain at **130** on 2022 engine; enable Query Store |
| **Stage 2** | Week 2–4 | Raise to **140** or **150** per database after Query Store baseline |
| **Stage 3** | Month 2+ | Raise to **160** to enable full 2022 IQP (PSP, DOP feedback, CE feedback) |

```sql
-- Enable Query Store before changing compatibility level
ALTER DATABASE [YourDatabase] SET QUERY_STORE = ON;
ALTER DATABASE [YourDatabase] SET QUERY_STORE (OPERATION_MODE = READ_WRITE);

-- Staged compatibility change (example — run only after UAT sign-off)
ALTER DATABASE [YourDatabase] SET COMPATIBILITY_LEVEL = 150;
-- Monitor Query Store for regressions for 1–2 weeks before 160
```

### 9.3 Intelligent Query Processing Database Scoped Configuration (2022)

Evaluate enabling after compat 160 and Query Store baseline:

```sql
ALTER DATABASE SCOPED CONFIGURATION SET DOP_FEEDBACK = ON;
ALTER DATABASE SCOPED CONFIGURATION SET OPTIMIZED_PLAN_FORCING = ON;
-- PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = ON is default in compat 160
-- MEMORY_GRANT_FEEDBACK = ON requires Query Store
```

### 9.4 Cardinality Estimator Control (Most Common Performance Issue)

| Mode | How enabled | When to use |
| --- | --- | --- |
| **Legacy CE** | Compat ≤120 or `LEGACY_CARDINALITY_ESTIMATION = ON` | Temporary mitigation for regressions while investigating |
| **Current CE** | Compat 130+ (default for 2016+) | Baseline on 2016; validate after raise |
| **CE Feedback** | Compat 160 + Query Store | Prefer over permanent legacy CE |

Controls and mitigations:

- Database scoped: `LEGACY_CARDINALITY_ESTIMATION`, `QUERY_OPTIMIZER_HOTFIXES`, `PARAMETER_SNIFFING`, `PARAMETER_SENSITIVE_PLAN_OPTIMIZATION`
- Query Store hints / plan forcing / `USE HINT` (evidence-based only)
- Trace flags such as **4199** (optimizer hotfixes) — re-evaluate on 2022; do not carry blindly
- Avoid permanent TF-only “fixes” without documenting why

**Community-reported CE pitfall (2016 → 2022):** Jumping from compat **130** straight to **160** is a common cause of severe plan regressions on complex queries. Prefer staged raises. When a regression is confirmed and CE Feedback / plan forcing is insufficient, temporary `LEGACY_CARDINALITY_ESTIMATION = ON` (database scoped) can restore 2016-era estimates while you remediate.

**PSP (Parameter Sensitive Plan) caveat:** PSP is a marquee SQL Server 2022 feature, but early Cumulative Updates had edge-case bugs (CPU spikes / timeouts). **Never run production on RTM-only** — install the **latest CU** on the 2022 target before UAT and cutover. Capture scoped configs during triage with `21_rollback_evidence_capture.sql`.

**MSDTC & Always On:** Workloads that use distributed transactions across Availability Group replicas need explicit validation on 2022 (DTC/AG transport differs from older engines). Inventory DTC usage, test cross-replica distributed transactions in UAT, and follow current Microsoft guidance / required trace flags for your CU before production cutover.

### 9.5 Query Store Operating Standards

Configure explicitly on every migrated database:

| Setting | Guidance |
| --- | --- |
| `OPERATION_MODE` | `READ_WRITE` before any compat raise |
| Capture mode | `AUTO` or `CUSTOM` (tune for overhead) |
| Max size / retention / cleanup | Size for 2–4 weeks of baseline + post-cutover |
| Forced plans | Document owner + expiry; review weekly |
| Automatic plan correction | Optional after stable capture; test in UAT first |
| Readable secondary QS | Enable if AG secondaries serve reporting |

**Baseline workflow:** Capture on 2016 (or keep 130 on 2022) → export/report top regressions → raise compat one step → observe → only then raise again. **Do not** set `COMPATIBILITY_LEVEL = 160` on cutover day.

### 9.6 Statistics and Indexes (Pre/Post Migration)

**Statistics checklist**

- [ ] Auto Update Statistics / Async settings documented
- [ ] Persisted sample percent and incremental stats on partitioned tables
- [ ] Filtered statistics inventory
- [ ] Outdated statistics remediated before UAT load tests
- [ ] `AUTO_DROP` statistics behavior understood on 2022

**Indexes checklist**

- [ ] Disabled / hypothetical indexes reviewed
- [ ] Filtered, columnstore, XML, spatial indexes inventoried
- [ ] Compression and partitioned indexes validated after restore
- [ ] Maintenance jobs (Ola/custom) re-pointed and tested on 2022

### 9.7 TempDB and Trace Flag Cleanup

| Item | 2016 habit | 2022 guidance |
| --- | --- | --- |
| TF 1117 / 1118 | Often used for TempDB | Generally **unnecessary** if multiple equal TempDB files configured |
| TF 2371 | Auto-stats threshold | Built into newer engines; re-evaluate need |
| TF 4199 | Optimizer hotfixes | Re-test; may change plans vs 2016 |
| TF 8048 / 834 | Memory / large pages | Hardware-specific; validate carefully |
| Memory-optimized TempDB metadata | Optional (2019+) | Enable if latch contention proven |
| Version store / PFS | Monitor after load increase | Watch ADR PVS if ADR enabled |

---

## 10. Testing Strategy

### 10.1 Test Categories

| Category | Scope | Pass Criteria |
| --- | --- | --- |
| **Functional** | CRUD, reports, batch jobs, integrations | 100% critical path pass |
| **Performance** | Top 50 queries by duration/CPU | ≤10% regression or remediated |
| **Failover** | AG/manual failover, restart | RTO met; apps reconnect |
| **Security** | Auth (Windows/SQL/Entra), encryption | All auth paths work |
| **Backup/restore** | Full restore to alternate server | RTO/RPO validated |
| **SSIS/ETL** | Package execution | Zero package failures |
| **Replication/CDC** | If applicable | Lag within SLA |

### 10.2 Performance Testing Methodology

1. Capture **full baseline** on 2016 (Section 21): waits, top CPU/reads/writes/duration, blocking, memory grants, Perfmon disk latency
2. Export Query Store / plan cache top queries for comparison
3. Replay same workload on 2022 UAT at same data volume
4. Compare: elapsed time, CPU, logical reads, waits, latch/spinlocks
5. For regressions: Query Store plan comparison → hints/force only with evidence → consider scoped CE controls → compat step-down if widespread
6. Document accepted regressions with business sign-off
7. Re-run baseline capture immediately before prod cutover (`16_pre_cutover_baseline.sql`)

### 10.3 Test Sign-Off Matrix

| Application | Owner | UAT Date | Prod Cutover Approved | Notes |
| --- | --- | --- | --- | --- |
| ERP System | | | | |
| Reporting | | | | |
| ETL/SSIS | | | | |
| Custom Apps | | | | |

---

## 11. Cutover Plan

### 11.1 Cutover Window Timeline (Example: 8-Hour Window)

| Time (T+) | Activity | Rollback Trigger |
| --- | --- | --- |
| T+0:00 | Go/No-Go decision; freeze changes | No-go if replication lag > SLA |
| T+0:15 | Notify users; disable non-critical jobs on source | |
| T+0:30 | Final transaction log backup / AG sync verify | |
| T+1:00 | Stop applications (or read-only mode) | |
| T+1:30 | Final log restore WITH RECOVERY / AG failover | |
| T+2:00 | `DBCC CHECKDB` on critical databases | Fail if corruption |
| T+2:30 | Enable Agent jobs on target; verify linked servers | |
| T+3:00 | Update connection strings / DNS / AG listener | |
| T+3:30 | Application smoke tests (login, critical transactions) | Rollback if P1 failure |
| T+4:30 | Extended functional validation | |
| T+6:00 | Performance spot-check (waits, blocking) | |
| T+7:00 | Go-live declaration or rollback decision | |
| T+8:00 | End of window; war room stand-down or rollback | |

### 11.2 Rollback Decision Criteria

Execute rollback if any occur within first 4 hours:

- P1 application failure affecting >50% users with no workaround
- Data corruption detected by CHECKDB
- Unrecoverable authentication failure for critical apps
- Replication/AG unable to establish stable target state

---

## 12. Post-Migration Validation

### 12.1 Immediate Validation (Day 1)

```sql
-- Version and patch level
SELECT
    @@VERSION AS [Version],
    SERVERPROPERTY('ProductLevel') AS [PatchLevel],
    SERVERPROPERTY('Edition') AS [Edition],
    SERVERPROPERTY('Collation') AS [ServerCollation];

-- Database state
SELECT name, state_desc, compatibility_level, recovery_model_desc, is_read_only
FROM sys.databases
WHERE database_id > 4;

-- Orphaned users
EXEC sp_MSforeachdb 'USE [?]; SELECT ''?'' AS DBName, name AS OrphanUser
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE dp.type = ''S'' AND dp.name NOT IN (''dbo'',''guest'',''INFORMATION_SCHEMA'',''sys'')
  AND sp.sid IS NULL';
```

| Check | Expected |
| --- | --- |
| SQL Server version | 16.x, latest CU applied |
| All databases ONLINE | No RESTORING/SUSPECT |
| SQL Agent running | Jobs enabled per schedule |
| Backups succeeding | First full backup post-migration OK |
| Errorlog clean | No recurring startup errors |
| TempDB sizing | No excessive autogrowth events |

### 12.2 Week 1 Validation

- Compare wait statistics vs 2016 baseline (allow for buffer pool warm-up)
- Review Query Store for plan regressions
- Validate maintenance plans: index rebuild, stats update, CHECKDB
- Confirm monitoring alerts firing correctly
- Review blocking and deadlock graphs

### 12.3 Use Repository Post-Migration Scripts

This repository includes a **Prod_Migration** playbook for troubleshooting post-upgrade performance. Run in order if slowness is observed:

| Order | Script | Purpose |
| --- | --- | --- |
| 1 | `sql_server/Prod_Migration/02_Upgrade_Validation/04_complete_post_upgrade_configuration_report.sql` | Full post-upgrade report |
| 2 | `sql_server/Prod_Migration/01_Quick_Triage/00_RUN_FIRST_triage_playbook.sql` | Version, memory, blocking, waits |
| 3 | `sql_server/Prod_Migration/07_Instance_Config/01_post_migration_config_audit.sql` | MAXDOP, memory, parallelism |
| 4 | `sql_server/Prod_Migration/06_Optimizer_Plans/03_query_store_regression.sql` | Plan regressions |
| 5 | `sql_server/Prod_Migration/04_Wait_Stats/02_post_migration_wait_decoder.sql` | Wait pattern analysis |

See `sql_server/Prod_Migration/README.md` for the complete triage workflow.

---

## 13. Rollback Strategy

### 13.0 What “rollback” really means (layers / levels)

In production migrations, rollback is rarely a single action. Define **rollback levels** before cutover and practice the decision tree in a tabletop:

| Level | Name | What you do | When |
| --- | --- | --- | --- |
| **Level 1** | Application rollback | DNS / listener / connection strings back to 2016; no SQL data restore | Connectivity/app failure; 2022 data not authoritative yet or writes not required |
| **Level 2** | SQL rollback | Stop apps; capture/apply final tail-log if needed; fail back log shipping/AG or restore log chain to 2016; bring 2016 online | Engine/data integrity issue while sync path still valid |
| **Level 3** | Infrastructure rollback | Power off / isolate 2022 host; bring old VM/host online; reverse DNS/firewall/routes | Target host unhealthy, storage/network broken |
| **Level 4** | Data rollback / reconciliation | If writes occurred on 2022 after cutover, decide how to replay or reconcile to 2016 (tail log, AG, log shipping, replication, or **manual reconciliation**) | Split-brain or post-write failback |
| **Level 5** | Disaster rollback | Target corrupt; restore from known-good backups; rebuild AG; recover certificates; rebuild logins | Catastrophic corruption / unusable target |

**Rule of thumb:** start with Level 1; escalate only with evidence. Level 4 is the hardest — answer “how are 2022 writes replayed?” **before** cutover day.

### 13.0.1 Architecture hard truth — you cannot restore 2022 databases back to 2016

**You cannot** detach or back up a user database from SQL Server 2022 and restore/attach it on SQL Server 2016. The database physical storage version advances when the database starts on the 2022 engine. Native Log Shipping and Always On Availability Groups also **cannot** replicate or fail over **downward** from 2022 to 2016.

Once live writes land on 2022, a true data-synchronized physical failback requires an **asymmetric** pattern planned **before** cutover:

| Option | Pattern | When to use |
| --- | --- | --- |
| **A — Phased Compatibility Isolation (safest backout)** | Keep databases on the **2022 engine** but locked at **COMPATIBILITY_LEVEL = 130** for the first **7–14 days**. “Rollback” for optimizer/syntax regressions is a fast scoped-config or compat change — **no** physical restore to 2016. | Preferred for most production migrations; covers the majority of app/optimizer failures. |
| **B — Active Transaction Sync (physical rollback path)** | Before cutover, stand up **transactional replication from 2022 → 2016** (or enterprise ETL/ELT using reliable row-version / change-tracking columns) so post-cutover writes can be replayed if you must abandon the 2022 host for an unresolvable engine bug. | Only when you truly need a physical return to 2016 after writes; high complexity — design and test in UAT. |

**Implication:** Level 1 connection rollback to a **frozen** 2016 copy is only safe if no (or negligible) writes occurred on 2022, or Option B is already catching those writes. Do not assume “restore the 2022 backup onto 2016” is possible — it is not.

Also think in operational layers inside each level:

1. **Connection rollback (fastest):** stop routing traffic to the 2022 instance.
2. **Workload rollback:** disable/stop SQL Agent jobs, maintenance plans, and app-side writers.
3. **Data rollback (slowest):** restore / fail back topology.
4. **Identity/security rollback:** revert login/user mapping, certificate, and permission changes.

### 13.1 General “Rollback Before You Roll Back” checklist (collect evidence fast)

Before switching traffic back, collect enough evidence to (a) prove the failure category and (b) prevent the same failure in the next attempt:

1. **SQL Server health**
   - Error log around cutover time (startup errors, permission failures, restore recovery issues).
   - Current status of databases (ONLINE/RESTORING/RECOVERING/SUSPECT).
   - TempDB status (autogrowth storms, file count, disk space).
2. **Workload evidence**
   - Top waits and top blocking sessions during the first affected hour.
   - Failing SQL Agent jobs (step error messages).
   - App symptom timeline (which feature broke first).
3. **Plan regression indicators**
   - Query Store regressions (new plan, increased duration, new forced hints) if enabled.
4. **Topology sync**
   - If AG/log shipping/replication is used: last sync time, latency, and error counters.
5. **Security**
   - Login failures: `Error 18456` state, database user mismatches, certificate/private key availability (TDE/Always Encrypted).

This evidence should fit into 15-30 minutes of focused capture so that rollback decisions are not “blind.”

### 13.2 Side-by-Side Migration Rollback (recommended model)

This section assumes Strategy B/C (new 2022 instance + restore/log shipping/AG), where rollback is feasible by re-pointing connections and reverting topology.

#### 13.2.1 Rollback triggers (what should cause a fast rollback)

Rollback immediately (within the cutover window) if any of the following occur:

- **Hard outage:** applications cannot connect (TLS/TDS, listener/DNS, firewall) and there is no workaround.
- **Data integrity / corruption signal:** `DBCC CHECKDB` fails, or repeated recovery errors occur that indicate unrecoverable database state.
- **Authentication outage:** critical logins fail permanently (e.g., certificate/private key missing for TDE/ce-encryption scenarios) and cannot be fixed within the SLA.
- **HA/DR topology failure:** AG cannot become stable primary/secondary in a way that keeps RPO within SLA.
- **Unbounded resource exhaustion:** CPU pegged due to a runaway query/maintenance + cannot stabilize with config changes (MAXDOP, job disabling) within SLA.

For “soft failures” (e.g., performance regression in a subset of queries), prefer workload rollback + parameter rollback/tuning first, then decide on connection rollback.

#### 13.2.2 Connection + workload rollback (typical within 0-30 minutes)

1. **Stop routing writes/critical traffic to 2022**
   - Switch DNS / listener / connection strings back to the SQL Server 2016 endpoint.
   - If apps use a connection pool, coordinate with pool drain (or temporarily block new connections).
2. **Revert SQL Agent workload**
   - Re-enable SQL Agent jobs on the 2016 instance.
   - Disable jobs on 2022 (especially maintenance plans, ETL writers, index rebuild/statistics jobs).
3. **Freeze changes**
   - Ensure application write operations are back on 2016 before you make any data restores on 2022.

#### 13.2.3 Data rollback decision (when to restore/fail back)

Use data rollback only when one of the following is proven:

- You took a **final log backup** and 2016 must be returned to the pre-cutover state.
- You have **data divergence** (e.g., replication/CDC lag exceeded SLA, then you cut over to a state that cannot be reconciled quickly).
- You detect **data integrity/recovery errors** (recovery stuck, recurring page/LSN restore errors).

##### Scenario: final log backup exists
- Restore 2016 to the appropriate pre-cutover state (or keep 2016 authoritative and revert topology).
- Avoid “manual replay” unless you absolutely have to; replay is error-prone and becomes a second incident.

##### Scenario: AG used
- Fail over back to 2016 replica (or re-establish 2016 as the primary) depending on your AG topology design.
- Validate that all databases are synchronized enough to meet RPO.

##### Scenario: log shipping used
- Restore 2016 for the desired point in time and keep the 2022 instance read-only until analysis completes.

#### 13.2.4 Rollback runbook steps (side-by-side)

1. **Announce rollback**
   - “Traffic back to 2016 now” and define who declares status when.
2. **Switch connections**
   - DNS/listener/connection string updates.
3. **Stabilize workload**
   - Disable 2022 jobs; re-enable 2016 jobs.
4. **Verify system health**
   - Confirm critical transactions succeed on 2016 within 5-15 minutes.
5. **Freeze 2022 forensics**
   - Do not keep applying fixes on 2022 while 2016 is serving business.
6. **Root cause analysis (RCA) before retry**
   - Categorize failure, then decide: “fix and retry” vs “redo cutover with altered plan.”

### 13.3 In-Place Upgrade Rollback (higher risk, reduced options)

Rollback is **not supported** by SQL Server setup. Practically, you have two options:

- **Restore instance-level backup/snapshot** taken immediately pre-upgrade (fastest if available).
- **Rebuild target and restore all databases** to a 2016 environment (high downtime).

**Therefore:** keep a viable 2016 instance (or VM snapshot that can boot the full stack) until the stabilization period ends.

### 13.4 Post-migration failure scenarios (brainstorm + expert response)

Below are realistic post-migration failure modes grouped by symptom. For each, the goal is: identify the category quickly, decide whether you can stabilize without rollback, and if rollback is required, execute the correct layer.

#### A) Connectivity / Login failures (first 5-60 minutes)

1. **All connections fail**
   - Likely causes: wrong endpoint/DNS, firewall/port not opened, TLS/cipher mismatch, TDS protocol issues, service did not start.
   - Immediate response: validate SQL service state, error log startup, port 1433/listener ports, TLS negotiation from a client host.
   - Rollback layer: **connection rollback** (almost always).
2. **Some apps fail, others work**
   - Likely causes: old drivers (SNAC references), ODBC/OLE DB mismatch, linked server provider issues.
   - Immediate response: compare driver versions; test from app tier; check job/proxy credentials.
   - Rollback layer: workload rollback (disable failing app modules / adjust connection strings) if possible; otherwise connection rollback.
3. **`Login failed for user` / orphaned users**
   - Likely causes: SID mismatch after restore, incorrect user mapping, missing contained database user mapping if used.
   - Immediate response: compare sys.database_principals users and fix mapping; validate server principals.
   - Rollback layer: identity/security rollback (only if fixes can be executed inside SLA).
4. **TDE / encryption related failures**
   - Likely causes: missing certificates/master keys, SKM not imported, backup/restore sequence error.
   - Immediate response: restore service master key, certificate, then database encryption keys; verify key hierarchy.
   - Rollback layer: connection rollback (if it becomes outage) + identity rollback.

#### B) Performance regressions / runaway workloads (minutes to 48 hours)

1. **High CPU / CPU pegged**
   - Likely causes: Query Store/plan regression, changed parameter sniffing behavior at new compat level, bad stats, unexpected maintenance job concurrency.
   - Immediate response: identify top CPU queries; check Query Store regressions; validate stats; temporarily cap MAXDOP; disable the newest job causing churn.
   - Rollback layer: workload rollback (disable jobs, stop specific batches) first; connection rollback if SLA breach persists.
2. **Low CPU, high elapsed time (waiting)**
   - Likely causes: IO latency, blocking/latches/TempDB contention, AV scanning after restore, security/metadata waits, network/storage back-end issues.
   - Immediate response: capture waits, top blockers, and TempDB metrics; compare to 2016 baseline; validate storage latency.
   - Rollback layer: connection rollback if waits cause application timeouts broadly; otherwise tune + fix.
3. **TempDB thrashing / autogrowth storms**
   - Likely causes: wrong number/size of TempDB files, insufficient disk space/IO for TempDB, enabling memory-optimized tempdb metadata without prerequisites (if applicable).
   - Immediate response: confirm TempDB file layout; pre-size correctly; stop jobs creating excessive temp objects.
   - Rollback layer: workload rollback (stop offending jobs) and possibly restart services; connection rollback if it remains unstable.
4. **Blocking/deadlocks spike**
   - Likely causes: concurrency changes driven by new Query Optimizer behavior, parallelism shift (MAXDOP recommendations), maintenance schedule overlap.
   - Immediate response: capture blocking graph; adjust job timing; reduce contention; consider targeted plan shaping only if evidence is strong.
   - Rollback layer: workload rollback first; connection rollback only if widespread.

#### C) Maintenance / SQL Agent / ETL failures

1. **SQL Agent jobs fail after cutover**
   - Likely causes: proxy credential mismatch, job step credential differences, path changes (SSIS package locations), SQL Agent not running, Agent alert operators misconfigured.
   - Immediate response: check job step errors; validate proxies and job ownership; re-point SSIS package paths.
   - Rollback layer: workload rollback by disabling the failing job category; connection rollback only if ETL is critical and fails catastrophically.
2. **SSIS jobs fail due to driver/provider**
   - Likely causes: SNAC removal effects, ODBC driver differences, linked server provider differences.
   - Immediate response: update connection managers to ODBC 18/OLE DB 19; test in SSIS catalog or designer with equivalent data.
   - Rollback layer: workload rollback of SSIS; connection rollback if apps cannot proceed.

#### D) HA/DR / replication / CDC failures

1. **AG synchronization not healthy**
   - Likely causes: log transport blocked, endpoint/permissions issues, insufficient redo/redo queue performance, network MTU issues.
   - Immediate response: check AG health DMV state, endpoint connectivity, redo queues/latency.
   - Rollback layer: data/topology rollback (fail back) if RPO is threatened.
2. **Replication/CDC lag explodes**
   - Likely causes: changes in log throughput, agent jobs broken, permission differences for capture/apply agents.
   - Immediate response: validate agents exist and are enabled on 2022; compare log throughput; ensure jobs are running.
   - Rollback layer: connection rollback or keep 2016 authoritative until lag is back inside SLA.

#### E) Data correctness / integrity failures

1. **CHECKDB fails**
   - Likely causes: restore corruption, interrupted restore/recovery, pre-existing corruption surfaced by new IO/parallelism, or broken backup chain.
   - Immediate response: do not “tune around” integrity. Stop further writes on the suspect instance.
   - Rollback layer: **data rollback** (restore from known-good backups or fail back topology).
2. **Unexpected data divergence (reports don't match)**
   - Likely causes: inconsistent cutover ordering, missed final log chain, CDC/replication not caught up.
   - Immediate response: compare LSN progression, validate final log backups, validate CDC watermarks.
   - Rollback layer: data/topology rollback + investigation; avoid making “blind” writes on 2022.

### 13.5 Stabilize first vs rollback: decision guidance

Use this quick decision policy:

- If you can restore service within **30-60 minutes** by connection + workload rollback, do that.
- If you need to restore data (or integrity is in question), treat it as a full rollback and start a post-incident review.
- If the failure is deterministic (e.g., missing keys/certs, broken AG ports, SNAC-related driver mismatch), fix it and do not retry with the same cutover configuration.

### 13.6 RCA artifacts to produce after rollback (prevents repeat incidents)

After you roll back, capture:

1. Timeline: cutover start/end, first symptom timestamp, first evidence timestamp.
2. Failure category: connectivity, auth, integrity, performance, HA/DR, workload/ETL.
3. Top evidence: error log excerpts, waits/blockers, job errors, Query Store regression notes.
4. Corrective action: what changed (drivers, keys, compat strategy, job scheduling, storage config).
5. Prevent recurrence: checklist item added (for next migration attempt).

---

## 14. Project Timeline Template

| Phase | Duration | Calendar |
| --- | --- | --- |
| Phase -0 — Compatibility assessment | 1 week | Week 0–1 |
| Phase 0 — Initiation | 2 weeks | Weeks 1–2 |
| Phase 1 — Discovery | 2–3 weeks | Weeks 2–5 |
| Phase 2 — Design | 2 weeks | Weeks 3–6 |
| Phase 3 — Build target | 2 weeks | Weeks 5–7 |
| Phase 4 — UAT pilot | 3 weeks | Weeks 6–9 |
| Phase 5 — Prod prep | 2 weeks | Weeks 8–10 |
| Phase 6 — Cutover | 1 weekend | Week 10–11 |
| Phase 7 — Stabilization | 4 weeks | Weeks 11–14 |

**Total estimated duration:** 11–16 weeks for a typical Enterprise production instance with UAT and change control.

Adjust for:

- Number of databases and total data size
- HA complexity (AG, replication)
- Application certification delays
- Regulatory audit requirements

---

## 15. Roles and Responsibilities

| Role | Responsibilities |
| --- | --- |
| **Project Manager** | Timeline, RAID log, stakeholder communication |
| **DBA Lead** | Assessment, build, migration execution, rollback decisions |
| **Infrastructure** | Windows, storage, network, firewall, VM/hardware |
| **Application Owner** | UAT sign-off, connection string updates, vendor coordination |
| **Security** | TDE keys, audits, Entra integration, vulnerability scan |
| **Change Manager** | CAB approval, change window enforcement |
| **Business Sponsor** | Go/no-go authority, downtime approval |

---

## 16. Tools and References

### 16.1 Microsoft Tools

| Tool | Purpose |
| --- | --- |
| [Data Migration Assistant (DMA)](https://learn.microsoft.com/sql/dma/dma-overview) | Compatibility and feature parity assessment |
| SSMS Migration Component (Upgrade Assessment) | Integrated in SSMS 19+ |
| SQL Assessment API | Rule-based health/risk assessment |
| [SqlPackage](https://learn.microsoft.com/sql/tools/sqlpackage) | Schema deploy/compare |
| [DBATools PowerShell](https://dbatools.io/) | `Export-DbaLogin` / `Import-DbaLogin`, AG, backups, `Test-DbaBuild` |
| [SqlServer PowerShell module](https://learn.microsoft.com/sql/powershell/sql-server-powershell) | Admin automation |
| First Responder Kit (`sp_Blitz*`) | Optional health/plan/index/wait analysis if available |

### 16.2 Official Documentation

- [Upgrade SQL Server](https://learn.microsoft.com/sql/database-engine/install-windows/upgrade-sql-server)
- [Supported version and edition upgrades (2022)](https://learn.microsoft.com/sql/database-engine/install-windows/supported-version-and-edition-upgrades-2022)
- [What's new in SQL Server 2022](https://learn.microsoft.com/sql/sql-server/what-s-new-in-sql-server-2022)
- [Deprecated features in SQL Server 2022](https://learn.microsoft.com/sql/database-engine/deprecated-database-engine-features-in-sql-server-2022)
- [Discontinued functionality](https://learn.microsoft.com/sql/database-engine/discontinued-database-engine-functionality-in-sql-server)
- [SQL Server 2022 release notes](https://learn.microsoft.com/sql/sql-server/sql-server-2022-release-notes)

### 16.3 Post-Install Baseline

Refer to `sql_server/docs/sqlserver_installation_checklist.md` for production-grade SQL Server installation hardening on Windows Server.

---

## 17. Repository Script Cross-Reference

| Migration Phase | Repository Asset |
| --- | --- |
| **Interactive migration checklist (HTML)** | `sql_server/output/SQL_2016_to_2022_Migration_Checklist.html` |
| **Migration SQL scripts (23 scripts)** | `sql_server/Migration_2016_to_2022/` |
| Regenerate HTML checklist | `sql_server/powershell/Generate-Migration2016To2022Checklist.ps1` |
| Pre-migration health baseline | `sql_server/` diagnostic scripts under `04_Performance_Diagnostics`, `05_Index_Statistics` |
| Schema drift (source vs target) | `schema_compare/` PowerShell pipeline |
| Post-migration validation | `sql_server/Prod_Migration/02_Upgrade_Validation/` |
| Performance troubleshooting | `sql_server/Prod_Migration/` (full playbook) |
| Dependency analysis | `sql_server/03_Storage_Engine/object_dependencies.sql`, `table_dependencies.sql` |
| Installation hardening | `sql_server/docs/sqlserver_installation_checklist.md` |

---

## 18. Four Parallel Migration Tracks

Enterprise migrations fail when treated as “SQL only.” Run these tracks in parallel with named owners:

| Track | Scope | Typical failure modes |
| --- | --- | --- |
| **1. SQL Server Engine** | Instance, databases, compat, Query Store, Agent, HA/DR, security keys | Plan regressions, orphaned users, TDE restore failures |
| **2. Application** | ERP certification, connection strings, drivers, SSRS/SSIS packages, batch jobs | SNAC/OLEDB breaks, TLS failures, uncertified ERP |
| **3. Infrastructure** | Windows build, VM/host, storage latency, NIC/RSS, firewall, DNS, AV exclusions | Slow I/O, power plan, missing IFI/LPIM, broken listeners |
| **4. Operations** | Monitoring, backups, runbooks, on-call, maintenance windows, alert routing | Silent backup failure, jobs pointing at old paths, no regression alerts |

**Exit criteria for each track** must be signed before Go/No-Go. Engine-ready + app-not-ready = abort cutover.

---

## 19. Feature, Security, Agent, and Client Inventories

### 19.1 Complete SQL Server Feature Inventory

Inventory **every** used feature on SOURCE (not only TDE/CDC/FileStream):

| Feature | Inventory method | Migration note |
| --- | --- | --- |
| CDC / Change Tracking | `sys.tables`, CT catalogs | Rebuild jobs/watermarks on target |
| TDE | `dm_database_encryption_keys` | Cert + SMK backup mandatory |
| FILESTREAM / FileTable | filegroups / tables | Paths and service account rights |
| In-Memory OLTP | memory-optimized tables/filegroups | Memory sizing on target |
| Service Broker | queues/services/routes | Often forgotten; test dialogs |
| Full-Text Search | catalogs/indexes | Reinstall FTS components; rebuild catalogs if needed |
| PolyBase | external data sources | Hadoop removed in 2022 |
| ML / R / external languages | external scripts | Runtimes not bundled in 2022 setup |
| SQL CLR (SAFE / EXTERNAL_ACCESS / UNSAFE) | assemblies | Trustworthy/`clr enabled`; retest permissions |
| XML indexes / Spatial indexes | index metadata | Validate after restore |
| Partitioned tables / partition switching | partition functions/schemes | Enterprise feature; test SWITCH |
| Resource Governor | classifier/pools | Recreate on target |
| Extended Events / SQL Trace | sessions/traces | Prefer XE; retire Profiler |
| SQL Audit / server audits | audit specs | Recreate paths and permissions |
| Database Mail | profiles/accounts | Recreate; test operators |
| Credentials / proxies | `sys.credentials`, Agent proxies | Passwords do not “come along” automatically |
| SSIS Catalog (SSISDB) | SSISDB | Backup/restore or redeploy projects |
| Master keys / DB scoped credentials | SMK/DMK/DSC | Backup and restore hierarchy |
| External scripts / languages | external language | Reinstall on 2022 |
| SQL Ledger | N/A on 2016 source | Optional adopt on 2022 only |

### 19.2 Login and Security Principal Migration

**Preferred:** dbatools

```powershell
Export-DbaLogin -SqlInstance SOURCE -Path C:\Migrate\Logins.sql
Import-DbaLogin -SqlInstance TARGET -Path C:\Migrate\Logins.sql
```

Also inventory and migrate:

- [ ] Server-level permissions / role memberships
- [ ] Credentials (and secret handling process)
- [ ] Certificates and asymmetric keys
- [ ] Linked-server remote passwords
- [ ] Proxy accounts
- [ ] Database scoped credentials
- [ ] Endpoint certificates (mirroring/AG)

### 19.3 SQL Agent Deep Checklist

Job list alone is insufficient. Validate:

- [ ] Job owner exists on target
- [ ] Schedules enabled intentionally
- [ ] Proxy exists and maps to credential
- [ ] Operator / notification exists
- [ ] Alerts and responses
- [ ] Token usage in steps
- [ ] CmdExec / PowerShell subsystems allowed and tested
- [ ] SSIS job steps (catalog vs file system)
- [ ] Replication agent jobs (if applicable)
- [ ] Maintenance plans vs Ola scripts
- [ ] Job output / log file paths exist on new server

### 19.4 Linked Server Deep Checklist

For each linked server, document and retest:

- [ ] Provider (MSOLEDBSQL19 / ODBC 18 — not SQLNCLI)
- [ ] Driver version on host
- [ ] Encryption / `TrustServerCertificate`
- [ ] Authentication mode (Windows vs SQL)
- [ ] Remote collation / collation compatible
- [ ] `RPC` / `RPC OUT` / `DATA ACCESS`
- [ ] Provider options and connection timeouts
- [ ] Four-part name queries and OPENQUERY samples

### 19.5 SNAC / Client Provider Checklist (Critical)

SQL Native Client and legacy SQLOLEDB are **removed** in SQL Server 2022 tooling/stack. Inventory every consumer:

| Consumer | Check |
| --- | --- |
| Custom applications | Connection string provider |
| SSIS | Connection managers |
| Linked servers | Provider name |
| OLE DB / ODBC DSN | System/User DSNs on app servers |
| Power BI / Excel / Access | Existing connections |
| SSRS | Data sources |
| Third-party ERP clients | Vendor matrix for ODBC 18 / OLE DB 19 |

Remediation: migrate to **Microsoft ODBC Driver 18** or **OLE DB Driver 19**, then UAT every critical path.

### 19.6 TLS / Encryption Connectivity Checklist

SQL 2022 environments commonly enforce modern TLS. Test from each app tier:

- [ ] `Encrypt=True` / mandatory encryption behavior
- [ ] `TrustServerCertificate` policy (prefer proper CA trust in prod)
- [ ] Certificate chain and expiration
- [ ] Self-signed vs enterprise PKI
- [ ] Force Encryption (instance) impact
- [ ] Legacy ERP clients that only speak older TLS — upgrade OS/.NET/driver or use approved bridge

### 19.7 Encryption Hierarchy Checklist

- [ ] Service Master Key backup
- [ ] Database Master Keys backup (where used)
- [ ] TDE certificates + private keys backup
- [ ] Symmetric keys inventory
- [ ] Always On / endpoint certificates
- [ ] Credential secrets rotation/export process documented

### 19.8 Hardware and OS Assessment Checklist

These cause as many failures as SQL itself:

- [ ] CPU count / sockets / **NUMA** / Soft NUMA
- [ ] Windows **Power Plan** = High Performance
- [ ] VM generation / Hyper-V or VMware version & tools
- [ ] Disk latency (log ideally low single-digit ms under load)
- [ ] Storage firmware / multipathing
- [ ] Windows patches current
- [ ] NIC speed, RSS, Receive Side Scaling, Jumbo Frames (if designed)
- [ ] **Instant File Initialization** granted
- [ ] **Lock Pages in Memory** (if policy/standard requires)
- [ ] PowerShell version for automation
- [ ] TLS version and cipher suites aligned with SQL 2022 clients

---

## 20. HA/DR and Replication Deep Checklist

### 20.1 Availability Groups

- [ ] Cluster validation report clean
- [ ] Quorum / witness model documented
- [ ] Listener / CNO (Cluster Name Object)
- [ ] Endpoints and certificates/permissions
- [ ] Availability mode / failover mode
- [ ] Automatic seeding vs backup/restore
- [ ] Read-only routing / read intent
- [ ] Backup preference
- [ ] Contained AG evaluation (optional on 2022)
- [ ] Distributed AG (if multi-site)
- [ ] Failover tested in UAT with app reconnect

### 20.2 Replication (Dedicated)

Replication frequently breaks across version moves. Checklist:

- [ ] Distributor / Publisher / Subscriber topology map
- [ ] Publications and subscriptions scripted
- [ ] Snapshot folder accessibility from new hosts
- [ ] Agent profiles and schedules
- [ ] Identity range management
- [ ] Replication agents running under correct proxies/credentials
- [ ] Post-cutover latency validation vs SLA
- [ ] Rollback plan if replication cannot catch up

---

## 21. Performance Baseline and Regression Playbook

### 21.1 What to Capture on SOURCE (and again on TARGET)

| Category | Examples |
| --- | --- |
| Wait stats | PAGEIOLATCH, WRITELOG, LCK_*, CXPACKET/CXCONSUMER, SOS_SCHEDULER_YIELD, THREADPOOL, RESOURCE_SEMAPHORE, PAGELATCH, spinlocks |
| Query store / plan cache | Top CPU, reads, writes, duration; parameterized plan variance |
| Blocking | Head blockers, deadlock graphs |
| Memory | Grants, clerks, buffer pool |
| Perfmon / infra | Disk latency, CPU queue, network |
| TempDB | File contention, version store |

### 21.2 Regression Handling Order

1. Confirm wait vs CPU (do not hint a waiting query)
2. Query Store plan compare / force previous good plan temporarily
3. Statistics / index sanity
4. Scoped config / CE feedback — not permanent legacy CE unless approved
5. Compat step rollback (160 → 150 → 130) if widespread
6. Escalate to Level 1 application rollback if SLA breached

Use repository: `Prod_Migration/` playbook + `Migration_2016_to_2022/16_pre_cutover_baseline.sql` / `18_post_migration_validation.sql`.

---

## 22. Common Field Issues (2016 → 2022)

Frequently reported in Microsoft guidance, community case studies (Brent Ozar, SQLSkills, Microsoft engineering), and migration engagements:

1. **Cardinality Estimator regressions** after raising compat 130 → 160 (mitigate with staged raise, Query Store, then temporary `LEGACY_CARDINALITY_ESTIMATION`)
2. **PSP optimization** edge bugs on early CUs — always deploy **latest CU**, never RTM-only
3. **MSDTC / distributed transactions across AGs** requiring 2022-specific validation
4. SQLNCLI / SQLOLEDB client failures → ODBC 18 / OLE DB 19 required
5. TLS 1.2+ enforcement breaking old ERP clients
6. Third-party software not certified for SQL 2022
7. Missing Agent proxies, credentials, or linked-server passwords
8. TDE certificate / SMK missing on restore
9. Orphaned users (SID mismatch) — especially on high-density multi-DB hosts
10. SSIS package failures from provider changes
11. Linked server failures (provider/encryption)
12. Replication needing full recreate/validation
13. Parameter-sensitive plan flips (Query Store invaluable)
14. AG listener / read-only routing / backup preference gaps after rebuild
15. **System databases** (`master` / `msdb` / `model`) remaining at compat 130 after upgrade — custom objects / login triggers in `master` must be tested before raising system DB compat
16. **ADR / PVS** undersized after enabling Accelerated Database Recovery
17. TempDB metadata latch contention — evaluate `MEMORY_OPTIMIZED TEMPDB_METADATA = ON` on 2022
18. Assuming a 2022 database can be restored back to 2016 (impossible — see §13.0.1)
19. **ActiveX** SQL Agent job steps (discontinued) — often confused with T-SQL steps, which still work
20. Apps relying on **silent string truncation** / ANSI_WARNINGS behavior during inserts
21. **TRUSTWORTHY** databases left enabled without security review after restore

Treat this list as the **minimum** UAT and cutover smoke-test matrix.

### Myth check — do not treat these as “removed in 2022”

| Claim | Reality |
| --- | --- |
| SQL Agent T-SQL subsystem removed (use CmdExec) | **False.** T-SQL job steps remain supported. **ActiveX** scripting subsystem is discontinued — convert those to CmdExec/PowerShell. |
| Remote Admin Connections via T-SQL removed | **False.** DAC / `remote admin connections` still exist. |
| Old-style `RAISERROR` formatting removed | **False.** Still works; prefer `THROW` for new code. |
| TRUSTWORTHY / cross-db access removed | **False.** Still supported; security posture should be reviewed. |

---

## Appendix A — SQL Server 2016 SP3 Requirement

Before **in-place upgrade**, confirm:

```sql
SELECT
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,
    SERVERPROPERTY('ProductUpdateLevel') AS UpdateLevel,
    SERVERPROPERTY('Edition') AS Edition;
```

**Required:** `ProductLevel` = SP3 (or later cumulative on 2016 SP3 baseline).

Download: [SQL Server 2016 Service Pack 3](https://www.microsoft.com/download/details.aspx?id=103849)

---

## Appendix B — Sample Post-Migration Configuration Audit

```sql
-- Key configuration values to verify after migration
SELECT name, value_in_use, [description]
FROM sys.configurations
WHERE name IN (
    'max server memory (MB)',
    'min server memory (MB)',
    'max degree of parallelism',
    'cost threshold for parallelism',
    'backup compression default',
    'optimize for ad hoc workloads',
    'remote admin connections'
)
ORDER BY name;
```

---

## Appendix C — Risk Register Template

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
| --- | --- | --- | --- | --- | --- |
| R01 | SNAC-dependent app fails | Medium | High | Driver upgrade in UAT | App team |
| R02 | Query plan regression at compat 160 | Medium | High | Staged compat + Query Store | DBA |
| R03 | Stretch DB blocks upgrade | Low | Critical | Unstretch before migration | DBA |
| R04 | Insufficient disk I/O on target | Medium | High | Storage perf test in UAT | Infra |
| R05 | Vendor not certified for 2022 | Medium | Critical | Obtain certification early | PM |
| R06 | TDE cert not migrated | Low | Critical | Backup cert + SKM before cutover | Security |

---

*End of document*
