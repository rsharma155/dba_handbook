# SQL Server 2016 → 2022 Post-Migration Performance Playbook

> Documentation lives in `docs/`. SQL script paths below are relative to the **package root** (parent of `docs/`), unless prefixed with `../`.

**Scenario:** Database restored from SQL Server 2016 to SQL Server 2022. App is fine at **compatibility level 130** (2016). Switching to **160** (2022) causes application slowness.

**Root cause (most common):** Compatibility level 160 enables a newer **Cardinality Estimator (CE)**, different **optimizer transformations**, and **Intelligent Query Processing (IQP)** features. Plans that were "good enough" under CE 130 often get worse row estimates under CE 160, leading to hash joins instead of nested loops, serial instead of parallel (or the reverse), spills, and parameter-sensitive plans.

---

## Executive Summary — What To Do First

| Priority | Action | Risk | Folder |
|----------|--------|------|--------|
| 1 | Keep prod at 130 until Query Store baselines exist | None | `03_QueryStore_PlanForce` |
| 2 | Enable Query Store + capture plans at 130, then flip to 160 in a lower env | Low | `03_*` |
| 3 | Identify regressing queries (Query Store / DMVs) | None | `01_Diagnostics` |
| 4 | Force last-good plan or use CE feedback / hints | Low–Med | `03_*`, `05_*` |
| 5 | Update stats (FULLSCAN where needed), rebuild indexes | Low | `04_*` |
| 6 | Instance/DB config alignment (MAXDOP, CTFP, memory, TF) | Med | `02_Configuration` |
| 7 | Targeted T-SQL rewrites for CE-sensitive patterns | Med | `06_Code_Rewrite_Patterns` |
| 8 | Gradual cutover to 160 with monitoring | Controlled | `07_Monitoring_Baseline` |

**Do not** flip production to 160 without Query Store (or equivalent A/B capture). That is the #1 mistake after restore-based upgrades.

### Backup/restore nuances (record for future cases)

Even when stats/indexes/MAXDOP are already handled on the current engagement, keep these as checklist items for the next restore migration:

1. **Post-restore:** `DBCC UPDATEUSAGE(0)` + `UPDATE STATISTICS ... WITH FULLSCAN` before CL 160 - see `../04_Statistics_Indexes/05_Post_Restore_Maintenance_Before_CL160.sql` and `BACKUP_RESTORE_NUANCES_2016_to_2022.md`.
2. **Skip-release IQP:** Moving 2016 CL 130 -> 2022 CL 160 turns on UDF inlining, batch mode on rowstore (2019), and PSP (2022) at once - see `05_Compatibility_CE_Controls/04_SQL2022_IQP_and_CE_Feedback_Notes.sql`.
3. **New host:** Raise CTFP from default 5 to 30-50; set MAXDOP to NUMA physical cores; enable optimize for ad hoc - see `02_Configuration/01_Recommended_Instance_Settings_2022.sql`.

---

## Why Compatibility 160 Is Slower (Technical Drivers)

1. **Cardinality Estimator change** — Estimates for joins, filters, density, and multi-predicate selectivity differ from CE 70/120/130 behavior.
2. **New optimizer features under 160** — Memory grant feedback, degree of parallelism feedback, CE feedback, interleaved execution refinements, etc. Feedback can help *or* temporarily worsen plans.
3. **Parameter Sensitivity / Parameter Sniffing** — New CE can amplify sniffing problems on skewed data.
4. **Stale / sampling-based statistics** — After restore, stats may look "current" but were built under different engine assumptions; FULLSCAN often stabilizes estimates.
5. **Implicit conversion / SARGability** — Same code, different plan choices under new CE expose old anti-patterns.
6. **Instance settings differ from old box** — MAXDOP, cost threshold, max server memory, Instant File Init, TempDB, trace flags.
7. **Legacy Cardinality Estimation OFF** — At 160, `LEGACY_CARDINALITY_ESTIMATION` is OFF by default; turning it ON can temporarily restore 130-like estimates while you fix queries.

---

## Phased Troubleshooting Steps

### Phase 0 — Stabilize (Production stays at 130)

1. Confirm current compatibility and options:

```sql
SELECT name, compatibility_level, is_query_store_on
FROM sys.databases WHERE name = DB_NAME();
```

2. Capture instance vs database config baseline → `01_Diagnostics\01_Capture_Environment_Baseline.sql`
3. Enable Query Store (Read Write) → `03_QueryStore_PlanForce\01_Enable_QueryStore.sql`
4. Let the app run 3–7 days at **130** so Query Store holds a "golden" plan set.

### Phase 1 — Prove the regression (non-prod first)

1. Restore a recent copy to a test/UAT instance matching prod hardware ratio (CPU/RAM/storage as close as practical).
2. Replay or run top workloads.
3. Switch test DB to 160:

```sql
ALTER DATABASE [YourDB] SET COMPATIBILITY_LEVEL = 160;
```

4. Compare Query Store regressions → `03_QueryStore_PlanForce\02_Find_Regressed_Queries.sql`
5. For each top regressor, capture actual plans at 130 vs 160 → `01_Diagnostics\02_Compare_Plans_CE130_vs_CE160.sql`

### Phase 2 — Quick wins (often restore SLA same day)

Apply **in order**, measuring after each:

1. **Update statistics** (FULLSCAN on hot tables) → `04_Statistics_Indexes\01_Update_Statistics_PostMigration.sql`
2. **Query Store force last good plan** for confirmed regressions → `03_QueryStore_PlanForce\03_Force_Last_Good_Plan.sql`
3. **Database-scoped config** (temporary bridges):
   - `LEGACY_CARDINALITY_ESTIMATION = ON` (whole DB behaves closer to old CE)
   - Or per-query: `OPTION (USE HINT('FORCE_LEGACY_CARDINALITY_ESTIMATION'))`
   - Or `QUERY_OPTIMIZER_HOTFIXES`, `PARAMETER_SNIFFING`, etc.
   → `05_Compatibility_CE_Controls\*`
4. Align **MAXDOP / Cost Threshold / Max Memory / TempDB** → `02_Configuration\*`

### Phase 3 — Permanent fix (remove temporary bridges)

1. Rewrite CE-sensitive SQL patterns → `06_Code_Rewrite_Patterns\*`
2. Fix parameter sniffing with `OPTIMIZE FOR`, `OPTIMIZE FOR UNKNOWN`, local variables carefully, or **Parameter Sensitive Plan (PSP)** awareness on 2022.
3. Ensure covering indexes match new operators (look for key lookups, scans with residual predicates).
4. Re-test with `LEGACY_CARDINALITY_ESTIMATION = OFF` and compat 160.
5. Monitor 1–2 weeks → `07_Monitoring_Baseline\*`

### Phase 4 — Production cutover checklist

- [ ] Query Store ON, enough space, stale query threshold tuned
- [ ] Top N queries validated at 160 in UAT
- [ ] Forced plans documented with owner + expiry review date
- [ ] Stats jobs updated (Ola Hallengren / custom) for 2022
- [ ] Instant File Initialization enabled (service account)
- [ ] TempDB: multiple data files, equal size, no autogrowth storms
- [ ] Max server memory leaves OS headroom
- [ ] Compatibility 160 change window + rollback (`SET COMPATIBILITY_LEVEL = 130`) rehearsed
- [ ] Application timeouts / connection pooling unchanged and measured

---

## Recommended Decision Tree

```
App slow only when compat = 160?
├─ YES → CE / optimizer plan regression (this playbook)
│   ├─ Few queries? → Force plans / query hints / rewrite those
│   ├─ Many queries? → LEGACY_CARDINALITY_ESTIMATION = ON temporarily
│   │                  + systematic Query Store remediation
│   └─ Also slow at 130 on new hardware? → Instance/storage/config (not CE)
└─ NO → Not a compat issue; check blocking, IO, CPU, wait stats separately
```

---

## Folder Map

| Folder | Contents |
|--------|----------|
| `docs/` | All markdown guides (playbook, quick start, checklists, source troubleshooting notes) |
| `01_Diagnostics` | Baselines, waits, top queries, plan compare helpers |
| `02_Configuration` | Instance & DB recommended settings for 2022 |
| `03_QueryStore_PlanForce` | Enable QS, find regressions, force/unforce plans |
| `04_Statistics_Indexes` | Stats update, fragmentation, missing index review |
| `05_Compatibility_CE_Controls` | Legacy CE, scoped configs, hints, TF notes |
| `06_Code_Rewrite_Patterns` | T-SQL anti-patterns → modern rewrites (SQL examples) |
| `07_Monitoring_Baseline` | Before/after metrics, health checks |
| `Compat160_Targeted_Fixes.html` | Interactive playbook (guided approach + embedded scripts) |

---

## Rollback (always ready)

```sql
-- Emergency rollback to 2016-like optimizer behavior
ALTER DATABASE [YourDB] SET COMPATIBILITY_LEVEL = 130;
-- Optional if you had enabled it:
-- ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF;
```

Clear procedure cache only if needed after config changes (causes compile storm — prefer Query Store / targeted `DBCC FREEPROCCACHE (plan_handle)`):

```sql
-- Prefer: ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;  -- SQL 2016+
```

---

## Engagement Notes for the Client

1. **Compat 130 on SQL 2022 is supported** and is a valid interim state — not a failure.
2. Goal is **compat 160 with equal or better performance**, not "flip and hope."
3. Expect 1–3 weeks of Query Store–driven remediation for a typical OLTP app; heavier analytical workloads may need more rewrite work.
4. Keep a living list of forced plans; treat them as technical debt with review dates.

---

*Prepared as a DBA consulting package for restore-based upgrades from SQL Server 2016 to SQL Server 2022.*
