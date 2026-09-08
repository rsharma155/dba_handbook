# SQL Server Initial Assessment Collector

Two PowerShell collectors share the same `sql_scripts` folder and write the same kinds of artifacts (HTML, Excel, audit log). Pick the script that matches how deep you want the run:

| Script | Use when | What is different |
|--------|----------|-------------------|
| `Invoke-SqlInitialAssessment.ps1` | Full Phase-1 / architectural assessment | **Detailed report.** Comma-separated `-Database` / `-DatabaseList` with fail-fast validation; instance queries are filtered to that list; HTML includes database/object filters and scope metadata; Excel is category-prefixed with Summary charts. |
| `Invoke-SqlInitialAssessment_minimal.ps1` | Faster / lighter share | **Limited-detail report.** Optional **single** `-Database` only; instance-wide collectors are not filtered to a DB list; Excel is a simpler Summary + one sheet per populated section (no category prefixes or charts). |

Both connect with SQL authentication, collect current-state evidence, and always write an **audit log**. HTML and Excel are optional — choose with `-OutputFormat` / `-o`:

| `-OutputFormat` / `-o` | HTML `.html` | Excel `.xlsx` | Log `.log` |
|------------------------|--------------|---------------|------------|
| `Html` (default) | yes | no | always |
| `Excel` | no | yes (ImportExcel required) | always |
| `Both` | yes | yes | always |
| `-ExportExcel` (legacy switch, default Html) | yes | yes | always |

It is intended for insurance/V2 modernization engagements where you need current-state facts before proposing architecture, sync strategy, migration approach, and remediation.

Use `-o Excel` when you want a shareable Excel-first artifact instead of HTML. The HTML report (when generated) opens on an Executive Summary and uses a fixed left sidebar for evidence sections.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- SQL Server 2016+ recommended (2017+ preferred for modern feature inventory)
- Network access to the SQL endpoint
- [dbatools](https://dbatools.io) module
- The **`ImportExcel`** module (required for `-OutputFormat Excel` / `Both` or `-ExportExcel`; optional for HTML-only runs; no Microsoft Excel/COM required)
- SQL login with broad read access (`VIEW SERVER STATE`, database access, `msdb` backup history). `sysadmin` gives the most complete result.

```powershell
Install-Module dbatools -Scope CurrentUser
Install-Module ImportExcel -Scope CurrentUser   # required for -o Excel / -OutputFormat Both
```

## Package layout

```text
ps_report_collector\
|-- Invoke-SqlInitialAssessment.ps1
|-- Invoke-SqlInitialAssessment_minimal.ps1
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

Copy the PowerShell script you want to run and the entire `sql_scripts` folder together.

## Quick start

Detailed collector (HTML by default):

```powershell
$sqlCredential = Get-Credential -UserName sa
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100' -Credential $sqlCredential -OpenReport
```

Limited collector (same output-format flags):

```powershell
.\Invoke-SqlInitialAssessment_minimal.ps1 -ServerIP '192.168.1.100' -Credential $sqlCredential -OpenReport
.\Invoke-SqlInitialAssessment_minimal.ps1 -ServerIP '192.168.1.100' -Credential $sqlCredential -o Excel
.\Invoke-SqlInitialAssessment_minimal.ps1 -ServerIP '192.168.1.100' -Credential $sqlCredential -OutputFormat Both
```

Named instance / custom port:

```powershell
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100\SQL2022' -Credential $sqlCredential
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100,1433' -Credential $sqlCredential
```

Single database or a comma-separated list:

```powershell
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100' -Credential $sqlCredential -Database 'PolicyCore'
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100' -Credential $sqlCredential `
    -Database 'AdventureWorks2025,ETLWorkshopDB' -o Excel
```
Excel-first share (no HTML file):

```powershell
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100' -Credential $sqlCredential -o Excel -OpenReport
```

HTML + Excel:

```powershell
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100' -Credential $sqlCredential -OutputFormat Both
# equivalent:
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '192.168.1.100' -Credential $sqlCredential -ExportExcel
```

Or run the interactive demo:

```powershell
.\demo.ps1
```

Outputs land in `.\output`:

```text
SQL_Initial_Assessment_<server>_<timestamp>.html   # Html or Both
SQL_Initial_Assessment_<server>_<timestamp>.xlsx   # Excel or Both (or -ExportExcel)
SQL_Initial_Assessment_<server>_<timestamp>.log    # always
```

## Parameters

Shared by both scripts unless noted:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ServerIP` | required | Host, `host\instance`, or `host,port` |
| `Credential` | required | SQL `PSCredential` (never written to the log) |
| `OutputPath` | `.\output` | Report/log/Excel directory |
| `DaysToAnalyze` | `90` | Lookback for capacity growth / autogrowth / job failures |
| `FullBackupSlaHours` | `24` | Full backup SLA for findings |
| `LogBackupSlaMinutes` | `30` | Log backup SLA for FULL/BULK_LOGGED DBs |
| `Database` | all user DBs | **Detailed script:** one name or a comma-separated list (`DatabaseList` alias); fail-fast if a name is missing, offline, a system DB/snapshot, or inaccessible. **Minimal script:** optional **single** user database name only. |
| `OutputFormat` | `Html` | Primary artifact(s): `Html`, `Excel`, or `Both`. Alias: `-o` |
| `ExportExcel` | *(off)* | With default `Html`, behaves as `-OutputFormat Both` |
| `OpenReport` | off | Open HTML when produced; otherwise open the `.xlsx` |

Both scripts return an object with `Server`, `OutputFormat`, `ReportPath` (HTML path or `$null` for Excel-only), `ExcelReportPath`, `LogFilePath`, `HealthScore`, `HealthStatus`, `CriticalIssues`, `WarningIssues`, `InformationItems`, `CollectionErrors`, and `DatabasesAssessed`.

Scoped examples:

```powershell
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '...' -Credential $cred -Database 'ERP_System'
.\Invoke-SqlInitialAssessment.ps1 -ServerIP '...' -Credential $cred `
    -Database 'AdventureWorks2025,ETLWorkshopDB' -o Excel
```

### Database scope: what is filtered vs instance-wide

On **`Invoke-SqlInitialAssessment.ps1`**, when `-Database` / `-DatabaseList` is set:

**Scoped** — all `Invoke-PerDatabaseAssessmentQuery` collectors (schema, indexes, code, Query Store, principals, orphaned users, VLFs, filegroups, compression, deprecated DB features, etc.), plus DatabaseName-filtered instance queries: backups, capacity trends, autogrowth, top consumers, implicit conversions, blocking/long-running, compatibility levels, replication/CDC/CT landscape. Database Landscape / findings for the selected databases only.

**Still instance-wide** — server inventory, services, volumes, instance config, trace flags, wait stats, CPU/memory pressure, TempDB, AG replica topology (no per-DB rows in this collector), linked servers/broker, server security/roles/encryption surface, Agent jobs/failures/alerts/Database Mail, deprecated instance features.

On **`Invoke-SqlInitialAssessment_minimal.ps1`**, `-Database` only scopes **per-database** collectors (the same `Invoke-PerDatabaseAssessmentQuery` set). Wait stats, top consumers, backups, capacity, autogrowth, compatibility, and similar instance queries stay instance-wide.

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

## Excel workbook export (`-OutputFormat` / `-o` / `-ExportExcel`)

Both scripts honor the same format switch. The **detailed** collector (`Invoke-SqlInitialAssessment.ps1`) writes the category-prefixed workbook described below. The **minimal** collector writes Summary (findings) plus one worksheet per populated evidence section, using the section name as the sheet title.

| Invocation | HTML | Excel `.xlsx` | Notes |
|------------|------|---------------|-------|
| *(default)* / `-OutputFormat Html` | yes | no | Current default; unchanged behavior. |
| `-o Excel` / `-OutputFormat Excel` | no | yes | Excel-first share; ImportExcel **required**. Log still written. |
| `-OutputFormat Both` | yes | yes | Full dual output. |
| `-ExportExcel` (legacy) | yes | yes | With default Html, treated as `Both`. |

On the detailed collector, the workbook is always the **complete** assessment (not filtered by the HTML database selector). Sheet layout:

1. **Summary** — server/timestamp, health KPIs, prioritized findings, charts (severity doughnut, findings-by-category bar, optional disk free % and top waits).
2. **Contents** — table of Category / Worksheet / Section / RowCount for every populated sheet.
3. **ChartData** (hidden) — chart source tables.
4. **Category-grouped evidence sheets** — one worksheet per non-empty collector, named with a short prefix.

### Category → section mapping

**SQL Landscape** (`SL-*`) — estate footprint
- Server and Instance Inventory → `SL-Inventory`
- SQL Services → `SL-Services`
- Infrastructure Volumes → `SL-Volumes`
- Database Landscape → `SL-DB Landscape`

**SQL Instance** (`SI-*`) — configuration and ops plumbing
- Instance Configuration → `SI-Config`
- Trace Flags → `SI-Trace Flags`
- Database Scoped Configurations → `SI-DB Scoped Config`
- Agent Jobs / Failures / Alerts / Database Mail → `SI-Agent Jobs` / `SI-Job Failures` / `SI-Alerts` / `SI-DB Mail`
- Collection Errors (when present) → `SI-Collection Errs`

**DB Design** (`DB-*`) — schema, data model, and code quality
- Object Inventory, Table Structure, Data Types, Constraints, FK Indexes, Nullability, Identity/Sequences, Special Features → `DB-*`
- Schema Design Risks, Cross-DB Dependencies, Naming → `DB-Schema Risks` / `DB-Cross-DB Deps` / `DB-Naming`
- Code Object Inventory, Function Risk, Triggers, Code Smells → `DB-Code Inventory` / `DB-Function Risk` / `DB-Triggers` / `DB-Code Smells`

**Storage** (`ST-*`) — files, growth, TempDB
- Filegroups and Files → `ST-Filegroups`
- VLF Assessment → `ST-VLF`
- Autogrowth Events → `ST-Autogrowth`
- Compression Opportunities → `ST-Compression`
- TempDB Health → `ST-TempDB`

**Tables, Index, Objects** (`IDX-*`) — indexes and statistics
- Index Inventory / Usage / Hot Tables / Many Indexes → `IDX-Inventory` / `IDX-Usage` / `IDX-Hot Tables` / `IDX-Many Indexes`
- Missing / Duplicate / Fragmentation → `IDX-Missing` / `IDX-Duplicates` / `IDX-Fragmentation`
- Statistics Database Options / Statistics Health → `IDX-Stats Options` / `IDX-Stats Health`

**Performance** (`PERF-*`) — current-state runtime pressure
- Wait Statistics → `PERF-Wait Stats`
- Top Resource Consumers → `PERF-Top Consumers`
- Implicit Conversion Candidates → `PERF-Implicit Conv`
- Query Store Status / Forced Plans → `PERF-Query Store` / `PERF-QS Forced`
- Blocking and Long Running → `PERF-Blocking`
- CPU Memory Pressure → `PERF-CPU Memory`

**Security** (`SEC-*`)
- Server Security / Role Membership / Encryption / Principals / Orphaned Users → `SEC-*`

**Architecture / HA-DR** (`Arch-*`)
- Availability Group Status → `Arch-AG Status`
- Replication CDC Change Tracking → `Arch-CDC CT Repl`
- Backup Status → `Arch-Backup Status`
- Linked Servers and Broker → `Arch-Linked Broker`

**Capacity** (`CAP-*`)
- Capacity Growth Trends → `CAP-Growth Trends`

**Migration** (`MIG-*`)
- Compatibility Levels → `MIG-Compat Levels`
- Deprecated Features → `MIG-Deprecated`

Every evidence sheet uses a standard layout: sky-blue title row (`#87CEFA`), subtitle with server + timestamp, Excel Table with AutoFilter, frozen header row, thin borders, and wrapped long-text columns. Empty sections are omitted (same rule as HTML).

**Two Excel-related outputs compared:**

| Feature | HTML button (SpreadsheetML `.xls`) | `-o Excel` / ImportExcel `.xlsx` |
|---------|-------------------------------------|-----------------------------------|
| When | After opening the HTML in a browser | At generation time |
| Needs ImportExcel | No | Yes |
| Charts | No | Yes (Summary) |
| Category prefixes | No (flat section names) | Yes (`SL-` / `SI-` / `DB-` / `ST-` / `IDX-` / `PERF-` / `SEC-` / `Arch-` / `CAP-` / `MIG-`) |
| Excel open warning | Mild extension mismatch prompt | Native `.xlsx`, no prompt |

If ImportExcel is missing on `Both` / `-ExportExcel`, the HTML report is still produced and a warning is logged. On `-o Excel`, missing ImportExcel is a terminating error with an install hint (`Install-Module ImportExcel -Scope CurrentUser`).

## What is collected automatically

| Area | Evidence |
|------|----------|
| Landscape / instance | Version/edition, CPU/memory/NUMA, services, volumes, database landscape, `sp_configure`, **trace flags**, **database scoped configurations** |
| Schema / design | Object counts, table structure, data types, constraints, FK index coverage, nullability/defaults, identity/sequences, special features, design risks, **naming heuristics**, **cross-database dependencies** |
| Indexes / statistics | Inventory, usage, **hot tables**, many indexes, missing/duplicate, fragmentation, **stats options**, **statistics health** |
| Code quality | SP/function/view/trigger inventory, scalar UDF risk, triggers, smells |
| Performance | Top non-idle waits (resource/signal, recommendations), top queries, **implicit-conversion candidates**, Query Store status / **forced plans**, TempDB, blocking, memory pressure |
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
- HTML includes grouped sidebar navigation, database/schema/table filters, sortable/paginated tables, and a client-side **Export to Excel** button (SpreadsheetML `.xls`). That in-page button is distinct from the server-side ImportExcel `.xlsx` produced by `-o Excel` / `-OutputFormat Both` on either script.
