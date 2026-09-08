# Comparison: Kendal Van Dyke SQL-Server-Scripts vs Local DBA Handbook

**Remote source:** [kendalvandyke/SQL-Server-Scripts](https://github.com/kendalvandyke/SQL-Server-Scripts)  
**Local handbook:** `sql_server/` (DBA Essential Scripts)  
**Compared:** 2026-07-23  
**Remote scope:** 24 T-SQL scripts (Performance, Replication, Security)  
**License (repo):** MIT (Copyright 2019 Kendal Van Dyke). Individual script headers also request attribution be preserved.

---

## Executive summary

Your handbook already covers **day-to-day production ops** more broadly than Kendal’s repo (waits, blocking, AG, backups, Query Store, capacity, assessment HTML, migration kits, etc.). Kendal’s repo is a **focused specialist kit** with unique depth in:

1. Plan-XML operator extraction (lookups / scans with columns)
2. Advanced missing-index consolidation (density reorder + overlap vs existing)
3. Overlapping auto-created statistics cleanup
4. Deep transactional replication diagnostics
5. Permission **scripting** and login-deletion hangup analysis

| Area | Remote | Already covered locally | Partial | Missing → integrated |
|------|-------:|------------------------:|--------:|----------------------:|
| Performance | 9 | 2 | 5 | 5 integrated (2 were full gaps) |
| Replication | 10 | 0 (basic monitor only) | 1 | 10 integrated |
| Security | 5 | 0 (posture audits only) | 1 | 5 integrated |
| **Total** | **24** | **2 skipped (covered)** | — | **21 integrated** |

**Not integrated (already equivalent or better locally):**
- `Identify Overlapping Rowstore Disk Indexes` → covered by `05_Index_Statistics/duplicate_index_analysis.sql`
- `Index Size, Rowcounts, Fragmentation & Usage` → covered by `physical_stats_and_heaps.sql` + `index_usage_efficiency.sql` + assessment scripts

---

## What was integrated

All integrated scripts keep Kendal’s original header/license text and add a handbook wrapper (purpose, action, criticality, source attribution).

### Performance / Indexes (`04_`, `05_`)

| New local path | From remote | Gap filled |
|----------------|-------------|------------|
| `04_Performance_Diagnostics/key_lookup_columns_from_plans.sql` | Find Key Lookups | Lookup target index + **column list** (local `plan_cache_deep_dive` only flagged lookups) |
| `04_Performance_Diagnostics/table_scans_from_plans.sql` | Find Table Scans | Dedicated TableScan extraction with cost/query text |
| `04_Performance_Diagnostics/index_operators_from_plans.sql` | Find Index Seeks/Scans/Lookups | Plan→index mapping with query context |
| `05_Index_Statistics/missing_index_consolidation.sql` | Identify Missing Rowstore Disk Indexes | Density reorder, consolidate requests, overlap vs existing |
| `05_Index_Statistics/overlapping_statistics.sql` | Identify Overlapping Statistics (2008+) | Auto-stats overlapping index/user stats + DROP script |
| `05_Index_Statistics/statistics_autoupdate_forecast.sql` | Show Statistics Information For Table | Mods/min + projected auto-update time |

### Security (`07_`)

| New local path | From remote | Gap filled |
|----------------|-------------|------------|
| `07_Security/script_database_permissions.sql` | Script Database Level Permissions | Runnable CREATE USER / role / GRANT (migration/DR) |
| `07_Security/script_server_permissions.sql` | Script Server Level Permissions | Runnable server role + GRANT scripts |
| `07_Security/show_database_permissions.sql` | Show Database Level Permissions | Object-level permission inventory |
| `07_Security/login_deletion_blockers.sql` | Show Logins/Users/Schemas/Jobs for Principal | Login-deletion hangup analysis + HelperScript |
| `07_Security/effective_permissions_for_login.sql` | Show Permissions For Login | EXECUTE AS + `fn_my_permissions` + `xp_logininfo` |

### Replication (`08_Advanced`)

Local previously had agent status + undelivered commands only (`replication_monitor.sql`). Added:

| New local path | From remote |
|----------------|-------------|
| `replication_articles_and_columns.sql` | Show Articles and Columns |
| `replication_command_counts.sql` | Show Command Counts At Distributor |
| `replication_subscriptions_topology.sql` | Subscriptions/Articles at Distributor |
| `replication_subscriber_at_publisher.sql` | Subscriptions for Subscriber at Publisher |
| `replication_distribution_agent_profiles.sql` | Distribution Agent Profiles |
| `replication_logreader_agent_profiles.sql` | Logreader Agent Profiles |
| `replication_distribution_volume_by_day.sql` | Distribution Volume By Day |
| `replication_logreader_volume_by_day.sql` | Logreader Volume By Day |
| `replication_replicate_ddl_toggle.sql` | Enable/disable replicate_ddl |
| `replication_merge_identity_ranges.sql` | Validate Merge Identity Ranges |

`_MASTER_INDEX.sql` was updated to catalog all of the above.

---

## Detailed comparison (all 24 remote scripts)

### Performance

| Remote script | Verdict | Local equivalent (before) | Notes |
|---------------|---------|---------------------------|-------|
| Find Index Seeks, Scans, & Lookups | PARTIAL → integrated | `index_usage_efficiency.sql`, `sp_DBA_PlanCacheAnalyzer.sql` | Usage DMVs lack plan→index+query mapping |
| Find Key Lookups | PARTIAL → integrated | `plan_cache_deep_dive.sql` | Local flagged lookups; missing column extraction |
| Find Table Scans | PARTIAL → integrated | `sp_DBA_PlanCacheAnalyzer` (`Has_TableScan`) | Boolean only before |
| Identify Missing Rowstore Disk Indexes | PARTIAL → integrated | `index_usage_efficiency`, `sp_DBA_IndexReview`, assessment missing-index scripts | Raw DMVs yes; density/consolidate/overlap no |
| Identify Overlapping Rowstore Disk Indexes | **COVERED** (skipped) | `duplicate_index_analysis.sql` (+ advanced/UQ scripts) | Local stronger (keep/drop, multi-DB) |
| Identify Overlapping Statistics (2005) | MISSING | — | Superseded by 2008+ variant integrated |
| Identify Overlapping Statistics (2008+) | MISSING → integrated | — | True gap |
| Index Size / Frag / Usage | **COVERED** (skipped) | `physical_stats_and_heaps`, `index_usage_efficiency` | Same DMVs, split across scripts |
| Show Statistics Information For Table | PARTIAL → integrated | `statistics_freshness.sql` | Freshness yes; forecast/thresholds no |

### Replication

| Remote script | Verdict | Local equivalent (before) |
|---------------|---------|---------------------------|
| Generate replicate_ddl enable/disable | MISSING → integrated | None |
| Show Articles and Columns | MISSING → integrated | None |
| Show Command Counts At Distributor | PARTIAL → integrated | `replication_monitor` (subscription pending only) |
| Distribution Agent Profiles | MISSING → integrated | None |
| Distribution Volume By Day | MISSING → integrated | Latest history only in `feature_deep_dive_audit` |
| Logreader Agent Profiles | MISSING → integrated | None |
| Logreader Volume By Day | MISSING → integrated | None |
| Subscriptions/Articles at Distributor | MISSING → integrated | Assessment flags only |
| Subscriptions for Subscriber at Publisher | MISSING → integrated | None |
| Validate Merge Identity Ranges | MISSING → integrated | None (niche unless merge is used) |

### Security

| Remote script | Verdict | Local equivalent (before) |
|---------------|---------|---------------------------|
| Script Database Level Permissions | MISSING → integrated | `authorization_audit` (audit only) |
| Script Server Level Permissions | MISSING → integrated | Assessment / migration inventory SELECT only |
| Show Database Level Permissions | PARTIAL → integrated | Posture checks, not full object ACL inventory |
| Login deletion hangups | MISSING → integrated | None |
| Effective permissions for login | MISSING → integrated | None |

---

## What your handbook already had that Kendal does not

Kendal’s repo does **not** include equivalents for large parts of your handbook, including:

- Wait stats / blocking / deadlocks / CPU / memory / disk latency
- Always On AG monitoring, backup chain, restore testing
- Query Store regression / plan force workflow
- Extended Events, Resource Governor, baselines
- Framework procs (`sp_DBA_HealthCheck`, wait/index/security wrappers)
- PowerShell HTML assessment report
- Migration 2016→2022 / post-migration CE/IQP kits
- Preventive governance jobs and policy enforcement

**Net:** Your handbook remains the broader operations playbook; Kendal filled specialist gaps in indexes, security scripting, and replication depth.

---

## Usage notes after integration

1. **Plan-cache scripts** (`key_lookup_*`, `table_scans_*`, `index_operators_*`): expensive — run off-peak; consider limiting with TOP in the source insert.
2. **`missing_index_consolidation.sql`**: uses `DBCC SHOW_STATISTICS`; do not blindly create every index.
3. **Permission scripting**: review output before applying on a destination; pair with login scripting.
4. **`login_deletion_blockers.sql`**: set `@PrincipalName`; apply HelperScript suggestions bottom-up after ownership decisions.
5. **Replication scripts**: run on the correct role (publisher vs distributor); set `@SubscriberName` where required.
6. **`effective_permissions_for_login.sql`**: edit `DOMAIN\account` placeholders; needs IMPERSONATE.

---

## Attribution

Integrated content adapted from [Kendal Van Dyke – SQL-Server-Scripts](https://github.com/kendalvandyke/SQL-Server-Scripts) (MIT). Original author headers are preserved inside each integrated `.sql` file.
