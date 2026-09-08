# Server Config Calculator

Offline web calculator for:

1. **DB configuration tuner** — enter current server hardware (vCPU, RAM, storage, CPU type, storage type) and get recommended **SQL Server** and/or **PostgreSQL** settings (best-practice formulas).
2. **Server sizing from workload** — pick **market reach** plus dropdowns for transactions/day, active users, tables, and current vs estimated DB size; get recommended **server tier**, CPU, RAM, storage, network, **HADR**, plus matching DB settings.

## Local market (default)

Sized for mid-sized / local deployments — not hyperscale cloud:

| Resource | Typical local range |
|----------|---------------------|
| CPU | 8–16 cores (common max ~16) |
| RAM | 32–64 GB |
| Storage | 512 GB–1 TB SSD |
| Workload | Light–moderate OLTP, often **&lt; ~10k row transactions/day** |

**Market reach** dropdown:

| Profile | Caps |
|---------|------|
| **Local market (mid-sized)** | ≤16 cores / 64 GB / 1 TB |
| Regional / growing | ≤24 cores / 96 GB / 2 TB |
| Enterprise / high-scale | Up to 64 cores / 512 GB / 10 TB |

## How to open

Open `index.html` in a browser (double-click or serve the folder). No install or server required.

```powershell
cd D:\Mac_bak\AI_Code\sql_optima\dba_essential_scripts\sql_server_assessment_tool\ps_report_collector\server_config_calculator
start index.html
```

## Feature 1 — Hardware → DB settings

| Input | Used for |
|--------|----------|
| vCPU / logical cores | MAXDOP, TempDB files, Postgres parallel workers |
| RAM (GB) | SQL `max server memory`, Postgres `shared_buffers` / `work_mem` / etc. |
| NUMA nodes | SQL MAXDOP NUMA-aware cap |
| Storage GB + type (SSD/NVMe/HDD) | WAL/checkpoint hints, `random_page_cost`, warnings |
| CPU type | Guidance notes (general / compute / memory) |
| Workload | OLTP vs reporting knobs (cost threshold, parallel gather, connections) |

### SQL Server formulas (summary)

- **OS reserve**: ~20% (≤16 GB RAM) down to ~6% on large hosts (min floors apply).
- **max server memory** = `(RAM − OS reserve) × 1024` MB.
- **MAXDOP** = `min(8, cores per NUMA)`; OLTP further capped at 4.
- **cost threshold for parallelism**: 50 (OLTP), 25–40 otherwise (not the default 5).
- **TempDB data files**: one per logical CPU up to 8.

Also suggests: optimize for ad hoc, backup compression, IFI, equal-sized TempDB growth.

### PostgreSQL formulas (summary)

- **shared_buffers** ≈ 25% RAM (tempered on very large hosts).
- **effective_cache_size** ≈ 65–75% RAM.
- **work_mem** ≈ `(RAM × 0.2) / max_connections` (clamped).
- **maintenance_work_mem** ≈ 5% RAM (cap 2 GB).
- **random_page_cost / effective_io_concurrency**: SSD/NVMe vs HDD.
- Parallel worker settings derived from vCPU and workload.

Outputs include starter **T-SQL** `sp_configure` and **postgresql.conf** snippets.

## Feature 2 — Workload → server size

### Primary inputs (dropdowns)

- **Market reach** (Local / Regional / Enterprise)
- **Transactions per day (avg)** — local typical &lt;10k
- **Active users** (peak concurrent)
- **Number of tables**
- **Current DB size** vs **Estimated DB size to start** (planning uses the larger)
- Application type, target engine, criticality
- Optional: daily/monthly growth GB, RPO, free-text description

### Workload score

Components from active users, daily txn rows, table count, and planning DB size, weighted by app type and market scale. Score maps to tier (local market never exceeds **Upper local**):

| Tier | Baseline shape | When (local) |
|------|----------------|--------------|
| Starter | 4 vCPU / 16 GB / 256 GB | Very light |
| Standard (local mid) | 8 vCPU / 32 GB / 512 GB | Typical mid-sized |
| Upper local | 16 vCPU / 64 GB / 1 TB | Busier local max |
| Growth | 24 vCPU / 96 GB / 2 TB | Regional/Enterprise only |

Final vCPU/RAM/storage are snapped to common local sizes and **capped by market profile**. Storage uses:

`max(tier base, planning DB×1.6×1.5, monthly×12×1.6×1.4)` then snap to SSD sizes.

### Application-type rules

Defined in `js/rules.js` (`APP_TYPES`): OLTP, E-commerce, SaaS, Reporting, Mixed, IoT, CMS, Batch — each with CPU/RAM/storage/IOPS weights and HADR bias.

**HADR** uses app bias + criticality + RPO. Local market prefers strong backups (+ optional async replica) unless criticality/RPO demands sync HA.

After sizing, the tool runs the same SQL/Postgres recommenders against the suggested hardware.

## Project layout

```
server_config_calculator/
  index.html          UI
  css/styles.css
  js/rules.js         Market profiles, app rules, tiers, sizing formulas
  js/sql-config.js    SQL Server recommendations
  js/postgres-config.js
  js/sizing.js        Sizing facade + bridge to DB config
  js/app.js           UI wiring
  README.md
```

## Notes / caveats

- Starting-point guidance only — not a substitute for vendor sizing or load testing.
- Licensing (SQL Server edition/cores), cloud IOPS SKUs, and exact NUMA topology need human review.
- Prefer connection poolers in front of PostgreSQL; keep `max_connections` modest.
- Export JSON from the sizing tab if you want to archive a recommendation.
