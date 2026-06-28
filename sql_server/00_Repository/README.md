# DBARepository — Deployment & Reference

## What Is This?

`DBARepository` is a dedicated admin database for the DBA assessment framework. It stores:

- All `sp_DBA_*` and `fn_DBA_*` framework objects
- (Future) Assessment history tables for trending
- (Future) Baseline snapshots

Create it **once per SQL Server instance** using the scripts below.

## Deployment

### Step 1: Create the database

```bash
sqlcmd -S YourServer -d master -i "DBARepository_Create.sql"
```

This creates a `DBARepository` database with SIMPLE recovery, `dba` schema, and safe defaults.

### Step 2: Deploy framework objects

```bash
sqlcmd -S YourServer -d DBARepository -i "DBARepository_Deploy.sql"
```

This installs all framework objects in dependency order:

| Order | Object | Type |
|-------|--------|------|
| 1 | `fn_DBA_ExcludedWaitTypes` | Scalar function |
| 2 | `fn_DBA_AgentRunDurationSeconds` | Scalar function |
| 3 | `sp_DBA_ForEachDatabase` | Stored procedure |
| 4 | `sp_DBA_QueryStoreRegressions` | Stored procedure |
| 5 | `sp_DBA_HealthCheck` | Stored procedure |

### Step 3: Verify

```sql
USE DBARepository;

-- List all DBA objects
SELECT name, type_desc FROM sys.objects WHERE name LIKE '%DBA%' ORDER BY type_desc, name;

-- Run health check
EXEC dbo.sp_DBA_HealthCheck @DeepDive = 0;
```

## PowerShell Automation

After deployment, use the PowerShell assessment framework for automated HTML reports:

```powershell
cd powershell
.\Invoke-SqlOptimaAssessment.ps1 -SqlInstance 'YourServer' -Profile Quick
```

See [powershell/README.md](../powershell/README.md) for full usage.

## Permissions

The service account or user running assessments needs:

| Permission | Purpose |
|------------|---------|
| `VIEW SERVER STATE` | All DMV queries |
| `VIEW ANY DEFINITION` | Security, encryption, XE, RG |
| `CONNECT` + DB access | Cross-database scripts |
| `msdb` read access | Backup history, job history |
| `CREATE FUNCTION` / `CREATE PROCEDURE` | Initial deployment only |

## Future: History Tables (Phase 3)

When persistence is enabled, these tables will store assessment history:

```sql
-- AssessmentRun: tracks each assessment execution
-- AssessmentFinding: findings per run
-- AssessmentMetric: dashboard metrics per run
-- BaselineSnapshot: performance baseline captures
```

See [cursor_review.md](../docs/cursor_review.md#part-2--assessment-framework--powershell-automation-cursor-review-addendum) for Phase 3 design.
