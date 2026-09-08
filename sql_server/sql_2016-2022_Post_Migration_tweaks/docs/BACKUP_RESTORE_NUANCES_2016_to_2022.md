# Backup/Restore Nuances: SQL Server 2016 -> 2022

> For the record when stats/indexes/MAXDOP are already done on the current engagement.
> These steps remain mandatory for future restore-based migrations.

## Why restore migrations are special

Restoring a 2016 database onto SQL Server 2022 does **not** rebuild statistics or usage metadata for the new engine. Jumping to **compatibility level 160** also skips SQL Server 2017 and 2019, so multiple Intelligent Query Processing (IQP) features turn on at once.

## 1. Post-restore maintenance gaps

| Gap | Risk | Action |
|-----|------|--------|
| Stale 2016 stats headers / histograms | Wrong CE estimates under CL 160 | `UPDATE STATISTICS ... WITH FULLSCAN` on user tables |
| Stale page/row counts | CE and space metadata wrong | `DBCC UPDATEUSAGE(0) WITH COUNT_ROWS` |
| Legacy modification counters | Auto-update may not fire when expected | FULLSCAN resets quality |

**Script (package root):** `04_Statistics_Indexes/05_Post_Restore_Maintenance_Before_CL160.sql`  
*(from this `docs/` folder: `../04_Statistics_Indexes/05_Post_Restore_Maintenance_Before_CL160.sql`)*

Run this **before** enabling CL 160 (keep CL 130 during maintenance). Prefer generated per-table scripts or Ola Hallengren over undocumented `sp_MSforeachtable` in production.

## 2. IQP regressions introduced between 2016 and 2022

| Feature | First appears | Common regression | Bridge |
|---------|---------------|-------------------|--------|
| Scalar UDF inlining | 2019 / CL 150 | Compile CPU spikes; bad plans on complex UDFs | `TSQL_SCALAR_UDF_INLINING = OFF` |
| Batch mode on rowstore | 2019 / CL 150 | TempDB spills; CXPACKET/CXCONSUMER | Fix CE/stats; raise CTFP; optionally disable batch mode |
| PSP optimization | 2022 / CL 160 | Variant boundary thrash / QS overhead | Isolate PSP OFF only if proven |

**Scripts (package root):** `05_Compatibility_CE_Controls/04_SQL2022_IQP_and_CE_Feedback_Notes.sql`, `05_Compatibility_CE_Controls/05_IQP_Feature_Isolation_Toggles.sql`

## 3. Server configuration baseline shift

New host often means different core count / NUMA:

- **CTFP:** default 5 is too low; use **30-50** (package default recommendation: 50)
- **MAXDOP:** match physical cores per NUMA node (often 4-8 for OLTP)
- **Optimize for ad hoc workloads:** ON to reduce plan cache bloat

**Script (package root):** `02_Configuration/01_Recommended_Instance_Settings_2022.sql`

## 4. Recommended step order (future engagements)

```
1. Post-restore: DBCC UPDATEUSAGE + stats FULLSCAN + instance CTFP/MAXDOP/ad hoc
2. Stay at CL 130; enable Query Store; capture 3-7 days
3. Flip CL 160 in UAT; clear proc cache; run workload
4. Automatic regression report (duration/CPU/IO/waits)
5A. Few queries  -> QS hints / plan force
5B. Widespread   -> isolate IQP / Legacy CE / optimizer hotfixes (keep CL 160)
6. Code rewrites; remove bridges; production cutover
```

## 5. Emergency scoped bridges (keep CL 160)

```sql
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;
ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = OFF;
ALTER DATABASE SCOPED CONFIGURATION SET QUERY_OPTIMIZER_HOTFIXES = ON;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
```

See `../05_Compatibility_CE_Controls/01_Database_Scoped_CE_and_Optimizer_Controls.sql`.
