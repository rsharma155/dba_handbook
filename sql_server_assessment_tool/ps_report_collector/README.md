# SQL Server Initial Assessment Collector

`Invoke-SqlInitialAssessment.ps1` connects to a SQL Server instance, collects Phase-1 / initial architectural assessment evidence, and writes:

- a self-contained **HTML report**
- a matching **audit log**

It is intended for insurance/V2 modernization engagements where you need current-state facts before proposing architecture, sync strategy, migration approach, and remediation.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- SQL Server 2016+ recommended (2017+ preferred for modern feature inventory)
- Network access to the SQL endpoint
- [dbatools](https://dbatools.io) module
- SQL login with broad read access (`VIEW SERVER STATE`, database access, `msdb` backup history). `sysadmin` gives the most complete result.

```powershell
Install-Module dbatools -Scope CurrentUser
```

## Package layout

```text
ps_report_collector\
|-- Invoke-SqlInitialAssessment.ps1
|-- demo.ps1
|-- README.md
|-- sql_scripts\
|   |-- 01_current_state\
|   |-- 02_schema_data_model\
|   |-- 03_indexes\
|   |-- 04_code_quality\
|   |-- 05_deprecated_compat\
|   |-- 06_performance_baseline\
|   |-- 07_ha_dr_sync\
|   |-- 08_security\
|   |-- 08_statistics\
|   |-- 09_capacity\
|   `-- 10_maintenance_ops\
`-- output\
```

Copy the PowerShell script and the entire `sql_scripts` folder together.

## Quick start

```powershell
$sqlCredential = Get-Credential -UserName sa
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100' -Credential $sqlCredential -OpenReport
```

Named instance / custom port:

```powershell
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100\SQL2022' -Credential $sqlCredential
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100,1433' -Credential $sqlCredential
```

Single database only:

```powershell
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100' -Credential $sqlCredential -Database 'PolicyCore'
```

Or run the interactive demo:

```powershell
.\demo.ps1
```

Outputs land in `.\output`:

```text
SQL_Initial_Assessment_<server>_<timestamp>.html
SQL_Initial_Assessment_<server>_<timestamp>.log
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ServerIP` | required | Host, `host\instance`, or `host,port` |
| `Credential` | required | SQL `PSCredential` (never written to the log) |
| `OutputPath` | `.\output` | Report/log directory |
| `DaysToAnalyze` | `90` | Lookback for capacity growth / autogrowth / job failures |
| `FullBackupSlaHours` | `24` | Full backup SLA for findings |
| `LogBackupSlaMinutes` | `30` | Log backup SLA for FULL/BULK_LOGGED DBs |
| `Database` | all user DBs | Limit per-database collectors to one DB |
| `OpenReport` | off | Open HTML when finished |

## HTML report structure

Sidebar groups match the enterprise assessment flow:

1. Executive Summary (findings + health score)
2. Current Architecture / Landscape
3. SQL Server Instance (config, trace flags, DB scoped config, Agent/mail)
4. Database Design (schema, code, naming, cross-DB deps)
5. Storage (files, VLF, autogrowth, compression, TempDB)
6. Tables / Indexes / Objects (indexes, hot tables, statistics)
7. Performance
8. Security
9. HA/DR and Synchronization
10. Scalability / Capacity
11. Migration / Modernization Signals
12. Assessment Scope (automated vs heuristic vs workshop matrix)

## What is collected automatically

| Area | Evidence |
|------|----------|
| Landscape / instance | Version/edition, CPU/memory/NUMA, services, volumes, database landscape, `sp_configure`, **trace flags**, **database scoped configurations** |
| Schema / design | Object counts, table structure, data types, constraints, FK index coverage, nullability/defaults, identity/sequences, special features, design risks, **naming heuristics**, **cross-database dependencies** |
| Indexes / statistics | Inventory, usage, **hot tables**, many indexes, missing/duplicate, fragmentation, **stats options**, **statistics health** |
| Code quality | SP/function/view/trigger inventory, scalar UDF risk, triggers, smells |
| Performance | Waits, top queries, **implicit-conversion candidates**, Query Store status / **forced plans**, TempDB, blocking, memory pressure |
| Storage / capacity | Filegroups/files, **VLF assessment**, **autogrowth events**, **compression opportunities**, capacity growth trends |
| Security | Logins/sysadmins, **server role membership**, TDE/trustworthy/surface area, principals, **orphaned users** |
| HA/DR / sync signals | Always On, CDC/CT/replication, backup age, linked servers/broker |
| Maintenance ops | **Agent jobs**, **job failures**, **alerts/operators**, **Database Mail** |
| Migration signals | Compatibility levels, deprecated features |

## Partial / heuristic only

These sections are useful evidence but not complete proofs:

- Cross-database dependency map (catalog references, not full app call graph)
- Naming convention review (pattern heuristics)
- Implicit conversion candidates (plan-cache / text heuristic)
- Hot table access (index usage since restart)
- Compression opportunities (size signals; sample before change)
- Backup strategy (age/SLA signals; restore tests are workshop work)

## What still needs interviews / workshops

Listed in **Assessment Scope** and intentionally **not** scored as readiness:

- Architecture diagrams / module ownership mapping
- RPO/RTO / SLA targets and business criticality
- Multi-tenant strategy and master-data ownership
- Kafka / Debezium / outbox readiness (CDC flags are signals only)
- ORM / EF / N+1 application review
- Restore-test / DR drill evidence
- Cost/benefit and roadmap costing
- Target architecture narrative / Azure MI-DB scoring beyond capability signals
- Document storage strategy (DB vs object storage)

## Notes

- Connections use `-TrustServerCertificate` (encrypted, certificate validation skipped) for common internal/self-signed setups.
- Collector failures are isolated per section/database and listed under **Collection Errors**.
- Index usage and plan-cache metrics reset on restart; treat them as ranking evidence.
- Missing-index rows are suggestions, not ready-to-run `CREATE INDEX` scripts.
- HTML includes grouped sidebar navigation, database/schema/table filters, sortable/paginated tables, and a client-side **Export to Excel** button.
