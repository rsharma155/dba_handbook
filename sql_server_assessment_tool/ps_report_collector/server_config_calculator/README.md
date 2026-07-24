# Server Config Calculator

Offline web calculator for:

1. **DB configuration tuner** — enter current server hardware (vCPU, RAM, storage, CPU type, storage type) and get recommended **SQL Server** and/or **PostgreSQL** settings (best-practice formulas).
2. **Server sizing from app flow** — when hardware is unknown, enter users, inserts, tables, volumes, and app type; get recommended **server tier**, CPU, RAM, storage, network, **HADR**, plus matching DB settings.

## How to open

Open `index.html` in a browser (double-click or serve the folder). No install or server required.

```powershell
cd D:\Mac_bak\SQL_Helps\Arhant\ps_report_collector\server_config_calculator
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

## Feature 2 — App flow → server size

### Inputs

- Application type (rules below)
- What the app is about (free text, shown on the result)
- Total users / concurrent users
- Tables, rows inserted per day
- Data volume daily / weekly / monthly (GB)
- Criticality + target RPO
- Target engine (SQL Server / Postgres / both)

### Workload score

Components (soft-capped) from concurrent users, daily insert rows, monthly GB, and table count, then multiplied by the app-type resource weights. Score maps to tier:

| Score | Tier | Baseline shape |
|------:|------|----------------|
| &lt; 20 | Small | 4 vCPU / 16 GB / 250 GB |
| &lt; 45 | Mid | 8 vCPU / 64 GB / 1 TB |
| &lt; 70 | Large | 16 vCPU / 128 GB / 4 TB |
| ≥ 70 | X-Large | 32 vCPU / 256 GB / 10 TB |

Final vCPU/RAM are snapped to common cloud sizes and boosted for high concurrency. Storage uses:

`max(tier base, monthly GB × 12 × 1.6 indexes/temp × 1.4 headroom)`

If concurrent users are omitted: `concurrent ≈ users × 10%`.  
If monthly GB omitted: `weekly × 4.3` (or `daily × 30` via weekly default).

### Application-type rules

Defined in `js/rules.js` (`APP_TYPES`):

| Type | Bias |
|------|------|
| OLTP / Transactional | High IOPS, high HADR, premium SSD |
| E-commerce | Peak-oriented CPU/network, high HADR |
| SaaS / Multi-tenant | Higher RAM weight, pooling, high HADR |
| Reporting / Analytics | CPU/RAM/storage heavy, throughput SSD |
| Mixed OLTP + Reporting | Balanced uplift; replica guidance |
| IoT / Telemetry | Storage + ingest IOPS dominant |
| CMS / Content | Lower DB weight if cache/CDN assumed |
| Batch / ETL | Throughput disk; lower HADR if restartable |

**HADR** uses app bias + criticality + RPO (≤15 min → high/sync-oriented recommendation).

After sizing, the tool runs the same SQL/Postgres recommenders against the suggested hardware.

## Project layout

```
server_config_calculator/
  index.html          UI
  css/styles.css
  js/rules.js         App-type rules, tiers, sizing formulas
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
