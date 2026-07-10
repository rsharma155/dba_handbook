# Production Database Health Report

SQL Server scripts that generate a consolidated **Production Database Health Assessment** across all online user databases on an instance.

Based on the requirements in [`db_prod_statis.md`](../db_prod_statis.md).

## Scripts

| File | Purpose |
|------|---------|
| [`production_database_health_report.sql`](production_database_health_report.sql) | Full assessment with 10 report sections |
| [`missing_index_report.sql`](missing_index_report.sql) | Missing index collector with generated `CREATE INDEX` statements |
| [`duplicate_index_report.sql`](duplicate_index_report.sql) | Duplicate and redundant index analyzer with usage stats |

## What it produces

One row per database in the summary, plus ranked detail reports:

| Report | Description |
|--------|-------------|
| 1 | Database health summary (size, tables, fragmentation, statistics, status) |
| 1b | Full detail row with all metrics |
| 2 | Top 20 largest databases |
| 3 | Top fragmented tables |
| 4 | Top fragmented indexes (>30% by default) |
| 5 | Outdated statistics by modification counter |
| 6 | Missing indexes (instance DMV) |
| 7 | Duplicate indexes |
| 8 | Unused indexes |
| 9 | Health score (0–100) and status |
| 10 | Maintenance recommendations |

### Health status thresholds

| Status | Condition |
|--------|-----------|
| **Healthy** | Fragmentation < 5%, outdated stats < 5% |
| **Warning** | Fragmentation 5–30%, or outdated stats 5–15% |
| **Critical** | Fragmentation > 30%, or outdated stats > 15% |

### Statistics staleness

A statistic is flagged outdated when either:

- `modification_counter > SQRT(rows × 1000)` (default, configurable), or
- `modification_counter > 20% of rows` (configurable via `@StatsStalePct`)

## Usage

```sql
-- Run in SSMS or sqlcmd against the target instance (master context recommended)
:r production_database_health_report.sql
```

Edit parameters at the top of the script before running:

```sql
DECLARE @DatabaseList           NVARCHAR(MAX) = NULL;          -- or N'ERPProd,CRM,HR'
DECLARE @IncludeReadOnly        BIT = 0;
DECLARE @MinPageCount           INT = 1000;
DECLARE @FragWarningPct         DECIMAL(5, 2) = 5.0;
DECLARE @FragCriticalPct        DECIMAL(5, 2) = 30.0;
DECLARE @StatsStalePct          DECIMAL(5, 2) = 20.0;
```

## Prerequisites

- SQL Server 2016+ (`STRING_SPLIT`)
- Read access to all target databases
- `msdb` access for backup metadata
- Optional: `dbo.sp_DBA_ForEachDatabase` from [`sql_server/00_Framework`](../sql_server/00_Framework/) for cleaner cross-database execution

## Performance notes

`sys.dm_db_index_physical_stats` runs in **LIMITED** mode per database but can still be expensive on large production databases. Run during off-peak hours.

Index usage stats (`sys.dm_db_index_usage_stats`) reset on instance restart — treat unused-index findings as advisory until sufficient uptime has elapsed.

## Index analysis scripts

### Missing Index Report (`missing_index_report.sql`)

Iterates online user databases with a **WHILE loop** (no cursors), collects instance missing-index DMVs per database, and returns:

- Database, schema, table, equality/inequality/included columns
- Avg user cost, avg user impact, user seeks/scans
- Estimated impact and improvement measure
- Generated `CREATE NONCLUSTERED INDEX` statement

```sql
DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @MinImprovementMeasure BIGINT = 1000;
DECLARE @TopN INT = 50;
```

### Duplicate Index Report (`duplicate_index_report.sql`)

Iterates each database with a **WHILE loop**, compares index definitions (not names), and detects:

| Type | Description |
|------|-------------|
| Exact Duplicate | Identical keys, includes, and filter |
| Left-Prefix Redundant | Shorter index is a key prefix of a longer one |
| Overlapping Redundant | One index key set covers another |
| Duplicate Filtered Index | Same keys/includes, different filters |
| Duplicate Unique Index | Same definition on unique indexes |
| Unused Duplicate Pair | Exact duplicate with zero reads since restart |

Returns last seek/scan/lookup/update, total reads/writes, and a **Keep / Review / Drop Candidate** recommendation.

**Note:** SQL Server does not expose index creation timestamps in catalog views or DMVs. No `CreatedDate` column is included (see `chatgpt_conversation.txt`).

## Related scripts

- [`sql_server/05_Index_Statistics/physical_stats_and_heaps.sql`](../sql_server/05_Index_Statistics/physical_stats_and_heaps.sql) — per-object fragmentation with maintenance actions
- [`sql_server/05_Index_Statistics/statistics_freshness.sql`](../sql_server/05_Index_Statistics/statistics_freshness.sql) — stale statistics detail
- [`sql_server/00_Framework/sp_DBA_IndexReview.sql`](../sql_server/00_Framework/sp_DBA_IndexReview.sql) — stored procedure index review
