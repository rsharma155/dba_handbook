# SQL Server DBA Assessment Report

`Invoke-DbaAssessmentReport.ps1` produces a self-contained, point-in-time SQL Server health assessment using [dbatools](https://dbatools.io) and SQL authentication. Every run writes:

- an interactive **HTML report** (single file, inline CSS/JS, no external dependencies), and
- a timestamped **audit log** of the run (errors, connection result, start/finish), and
- optionally, a formatted **Excel workbook** (`-ExportExcel`).

The HTML report opens on a **Summary of Findings** landing page and uses a fixed left sidebar to switch between **What Is Broken Now**, **What Is At Risk Soon**, scope notes, every populated evidence section, and Collection Errors.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- SQL Server 2016 or later (target instance)
- Network access to the SQL Server endpoint
- The **`dbatools`** PowerShell module (required)
- The **`ImportExcel`** module (optional — only for `-ExportExcel`; no Microsoft Excel/COM required)
- A SQL login with `VIEW SERVER STATE`, `VIEW DATABASE STATE`, access to each assessed user database, and read access to `msdb`; some security evidence also needs `VIEW ANY DEFINITION`. `sysadmin` gives the most complete result. With a least-privilege login, inaccessible databases or denied DMVs are recorded per item in **Collection Errors** (and the log) without stopping the report.

```powershell
Install-Module dbatools -Scope CurrentUser
Install-Module ImportExcel -Scope CurrentUser   # optional, for -ExportExcel
```

### Encryption and self-signed certificates

dbatools 2.x encrypts connections by default and validates the server certificate, which fails against instances using a self-signed certificate (*"The certificate chain was issued by an authority that is not trusted"*). Because this script targets internal assessments (server IP + `sa` credential), it connects with `-TrustServerCertificate`, so self-signed certificates are trusted automatically. The connection remains encrypted; only certificate validation is skipped.

## Package layout and deployment

The PowerShell script and its externalized SQL templates are **one deployable unit**:

```text
SQL_Server_Assesment_Report\
|-- Invoke-DbaAssessmentReport.ps1     # main script
|-- README.md
|-- demo.ps1
|-- sql_scripts\                       # all collector SQL (loaded at runtime)
|   |-- 01_inventory_configuration\
|   |-- 02_backup_jobs_maintenance\
|   |-- 03_storage_integrity\
|   |-- 04_performance_waits_queries\
|   |-- 05_tempdb_growth\
|   |-- 06_ha_dr_replication\
|   |-- 07_security_permissions\
|   |-- 08_statistics_indexes\
|   |-- 09_memory\
|   `-- 10_capacity_changes\
`-- output\                            # generated .html / .xlsx / .log
```

Copy `Invoke-DbaAssessmentReport.ps1` and the **entire** `sql_scripts` directory together, preserving their relative locations. If a required SQL file is missing or empty, the script stops early with the offending path before connecting.

### How SQL is loaded (manifest, tokens, marker)

- The script holds an **ordered manifest** (`$AssessmentSqlFiles`) mapping each logical collector name to a `.sql` file under `sql_scripts`. At startup the script validates that every mapped file exists and is non-empty.
- `Get-AssessmentSql` loads a file with `Get-Content -Raw -LiteralPath` relative to `$PSScriptRoot`.
- Dynamic values are injected **only** through explicit numeric tokens such as `{{DaysToAnalyze}}`, replaced with validated integer parameters. Any unresolved `{{token}}` is an error. There is no arbitrary string interpolation into SQL.
- Per-database collectors are database-agnostic (`DB_NAME()`, `DB_ID()`) and run through dbatools' `-Database` parameter — database names are never concatenated into SQL.
- Every SQL file begins with the marker comment `/* SQL_Server_Assessment */`, which lets cached-query reports exclude this assessment's own statements (see [Collector filtering](#collector-filtering-and-dmv-limitations)).

## Quick start

```powershell
$sqlCredential = Get-Credential -UserName sa
.\Invoke-DbaAssessmentReport.ps1 -ServerIP "192.168.1.100" -Credential $sqlCredential -OpenReport
```

Named instance or non-default port:

```powershell
.\Invoke-DbaAssessmentReport.ps1 -ServerIP "192.168.1.100\SQL2022" -Credential $sqlCredential
.\Invoke-DbaAssessmentReport.ps1 -ServerIP "192.168.1.100,1433"    -Credential $sqlCredential
```

Outputs are written (by default) to `.\output`:

```text
.\output\DBA_Assessment_<server>_<timestamp>.html
.\output\DBA_Assessment_<server>_<timestamp>.log
.\output\DBA_Assessment_<server>_<timestamp>.xlsx   # only with -ExportExcel
```

The three files share the same base name for easy correlation.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ServerIP` | *(required)* | SQL Server IP/name, `host\instance`, or `host,port`. Aliases: `ServerInstance`, `SqlInstance`. |
| `Credential` | *(required)* | SQL `PSCredential` (normally `sa`). Alias: `SqlCredential`. Never written to disk or the log. |
| `WindowsCredential` | *(none)* | Optional Windows credential for remote System/Application event-log collection. |
| `OutputPath` | `.\output` | Output directory for the HTML, log, and optional Excel file. |
| `DaysToAnalyze` | `30` | Historical lookback window in days (1–3650). |
| `FullBackupSlaHours` | `24` | Maximum acceptable full-backup age in hours (1–720). |
| `LogBackupSlaMinutes` | `30` | Maximum acceptable log-backup age for FULL/BULK_LOGGED databases (1–1440). |
| `DeepIndexCheck` | *(off)* | Adds `LIMITED` physical-fragmentation scans for indexes ≥ 1,000 pages. |
| `ExportExcel` | *(off)* | Also writes a formatted `.xlsx` beside the HTML (requires ImportExcel). |
| `OpenReport` | *(off)* | Opens the HTML report after generation. |

The script returns an object with `Server`, `ReportPath`, `ExcelReportPath`, `LogFilePath`, `HealthScore`, `CriticalIssues`, `WarningIssues`, and `CollectionErrors`.

Example with custom thresholds:

```powershell
.\Invoke-DbaAssessmentReport.ps1 `
    -ServerIP "192.168.1.100,1433" `
    -Credential $sqlCredential `
    -DaysToAnalyze 60 -FullBackupSlaHours 48 -LogBackupSlaMinutes 15 `
    -OutputPath "D:\DBAReports"
```

## How it works (end-to-end flow)

1. **Initialize** — resolve output paths, create the log file, and write a header (script version, server, parameters *excluding credentials*, start time, PowerShell and dbatools versions).
2. **Validate SQL** — confirm every manifest SQL file exists and is non-empty.
3. **Connect** — `Connect-DbaInstance` with `-TrustServerCertificate`; the result is logged (a failure is logged and then thrown).
4. **Collect** — run each collector via `Invoke-AssessmentQuery` (instance-scope) or `Invoke-PerDatabaseAssessmentQuery` (per user database). Each collector is isolated: a failure is captured to **Collection Errors** and the log, and the run continues.
5. **Analyze** — `Invoke-AssessmentAnalysis` turns raw evidence into prioritized findings (Critical / Warning / Info); analysis errors are isolated the same way.
6. **Render HTML** — build the Summary page, sidebar, and one panel per populated evidence section.
7. **Optional Excel** — when `-ExportExcel` is set and ImportExcel is available, write the workbook; failures never invalidate the HTML report.
8. **Finish** — write a final summary line to the log and return the result object.

## HTML report features

- **Sidebar navigation** with **Summary of Findings** active by default; sidebar badges show Critical/Warning counts.
- **Summary page**: health score/status, KPI cards (Critical, Warning, Info, Collection Errors), a severity doughnut and findings-by-category bars (pure CSS/JS), and a prioritized findings table.
- **Type-aware column sorting** on every table: dates sort chronologically, numbers numerically, everything else as text; blanks/`N/A` sort lowest. Headers are keyboard-accessible (`Enter`/`Space`) with `aria-sort`.
- **Pagination**: any table with more than 50 visible rows paginates automatically. Default page size **25**, selectable **20 / 25 / 30 / 50**. Previous/Next buttons disable at the ends. Order of operations is **filter → sort → paginate**; changing the filter, sort, or page size resets to page 1.
- **Global database filter** (sidebar): choose a database to filter every table that has a `DatabaseName` column; server-wide tables are unaffected. An active-filter indicator is shown, and a filtered-empty table shows *"No rows for selected database."* Summary findings are not filtered because findings do not carry structured per-database metadata in every area.
- **Empty-section omission**: evidence sections with zero rows are dropped from both the sidebar and the body. The two priority pages remain (a clean result is meaningful); Collection Errors appears only when errors exist.
- **Print**: printing reveals all filter-matched rows and hides pagination controls.
- **Export to Excel button** (fixed top-right, visible on every panel): a built-in client-side export that works offline in the browser with no external libraries. It downloads `DBA_Assessment_<server>_<timestamp>.xls` — a SpreadsheetML 2003 workbook with one worksheet per non-empty section (the prioritized findings summary first), sky-blue styled frozen header rows, and numeric cells typed as numbers. The export always contains **all rows of every section**, regardless of the active database filter, sort, or pagination page. Because the file is XML-based `.xls` rather than `.xlsx`, Excel shows a one-time *"file format and extension don't match"* prompt — click **Yes** to open; the content is safe plain XML. This is distinct from the server-side `-ExportExcel` option below, which produces a richer native `.xlsx` with charts but requires the ImportExcel module at generation time.

## Excel workbook export (`-ExportExcel`)

Add `-ExportExcel` to also write `DBA_Assessment_<server>_<timestamp>.xlsx`:

- a **Summary** sheet: server/timestamp, health score and status, finding counts, a prioritized findings table (Critical → Warning → Info), and charts — findings by severity (doughnut, severity colors), critical+warning findings by category (bar), and, when the data exists, disk free % by volume and top wait types;
- one formatted sheet **per populated evidence section** (empty sections omitted);
- a hidden **ChartData** sheet holding chart source tables;
- a **Collection Errors** sheet when errors exist;
- a light sky-blue theme with dark-blue headings, frozen header rows, autofilters, thin borders, and wrapped long-text columns.

The Excel workbook is always the **complete** assessment and is not affected by the HTML database selector — use each worksheet's Excel table filters instead. Excel export is opt-in and never blocks the HTML report: if ImportExcel is missing or the export fails, a warning is shown, the event is logged, and the HTML report is still produced. `ExcelReportPath` is `$null` when not exported.

If you only need the data in Excel after the fact, the HTML report's own **Export to Excel** button (see above) produces a multi-sheet `.xls` from any browser without rerunning the script — it just lacks the charts, themes, and native `.xlsx` format of `-ExportExcel`.

## Execution log (audit trail)

Every run writes `DBA_Assessment_<server>_<timestamp>.log` beside the HTML report (same base name).

- **Header**: script version, target server, start time, PowerShell version, dbatools version, and the parameter set — **with the credential explicitly redacted**. The `PSCredential` / password is never written.
- **Entry format** (one line per entry):

  ```text
  TIMESTAMP | SEVERITY | SECTION | DATABASE | MESSAGE
  2026-07-21 21:07:32.143 | ERROR | Backup Status | AppDb | Collector query failed. :: <message> [ExceptionType=...; SqlErrorNumber=4060; SqlState=1]
  ```

  `SEVERITY` is `INFO` / `WARN` / `ERROR`. `DATABASE` is populated for per-database collectors. For caught exceptions the message includes the exception type and, when the error is a SQL exception, its error number, state, and severity.
- **What is logged**: run start/finish, the connection result, every failure that lands in **Collection Errors** (instance collectors, per-database collectors, findings analysis, SQL error-log and Windows event-log collection, and Excel export), and a final summary line (health score and Critical/Warning/Info/Collection-Error counts).
- On a fully successful run the log still exists and contains INFO entries plus the final summary — it is an audit trail even with zero errors.
- Logging is best-effort: if the log cannot be written, the assessment continues normally.
- The log path is returned as `LogFilePath` and printed in the console summary.

## Collector filtering and DMV limitations

- **Live session/request collectors** (Current Blocking, Active/Long Running Queries, Active Memory Grants) exclude the assessment's own session (`@@SPID`) and sessions whose `program_name` starts with `dbatools PowerShell` (NULL program names are kept). Current Blocking applies the exclusion to both the blocked and the blocking session.
- **Cached query/plan DMVs** (`sys.dm_exec_query_stats`) do **not** retain a client `program_name`, so they cannot be filtered by dbatools client identity. Instead, Top Resource Consumers and Top Cached Query Memory Grants exclude cached text containing the `/* SQL_Server_Assessment */` marker, drop system-database contexts, keep legitimate ad-hoc rows (NULL `dbid`), and exclude MS-shipped objects where object metadata is available.
- **Stored Procedure Performance** excludes MS-shipped procedures; cached procedure stats also lack `program_name`, so results remain workload-wide (not attributable to a client program).
- All of this happens in the source SQL, so both the HTML and Excel outputs reflect the same filtered data — there is no synthetic client-program column.

## Deep index assessment

Standard runs collect lightweight statistics freshness/sampling, index status and usage, unused-index candidates, exact/same-key overlaps, and missing-index DMV indicators. `-DeepIndexCheck` additionally runs `sys.dm_db_index_physical_stats` in `LIMITED` mode, reports only indexes with ≥ 1,000 pages and ≥ 20% fragmentation, and caps results per database.

```powershell
.\Invoke-DbaAssessmentReport.ps1 -ServerIP "192.168.1.100" -Credential $sqlCredential -DeepIndexCheck
```

Run the deep check during a low-activity period. Fragmentation findings are investigation candidates: page count, page density, scan patterns, write load, edition, and maintenance windows should drive any reorganize/rebuild decision.

## Include Windows event logs

A SQL/`sa` credential cannot read Windows event logs. To include critical System and Application events, supply a Windows credential with remote event-log access:

```powershell
$windowsCredential = Get-Credential -Message "Windows credential for event logs"
.\Invoke-DbaAssessmentReport.ps1 -ServerIP "192.168.1.100" -Credential $sqlCredential -WindowsCredential $windowsCredential
```

Remote event-log collection also requires firewall/RPC access and the target's Remote Event Log Management rules. Without `-WindowsCredential`, this section is marked as skipped (and logged) rather than silently reported as healthy.

## Assessment coverage

The HTML sidebar and Excel workbook omit evidence sections that returned no rows. The report includes:

- server, build, edition, patch, CPU, memory, restart, and uptime inventory
- SQL Server and SQL Agent state/startup configuration
- database state, owner, recovery model, compatibility level, size, and key options
- full/differential/log backup age, backup destinations, and recent backup-related log errors
- SQL Agent job state, recent failures, maintenance jobs, operators, alerts, and notification configuration
- data/log/TempDB volume free space and backup destination free space
- last successful DBCC CHECKDB timestamps
- SQL error-log findings and optional Windows System/Application critical events
- active blocking, long-running requests, top waits, and high-risk wait categories
- CPU, memory grants, page life expectancy, file I/O latency (with color-coded latency verdicts), and top resource-consuming cached queries
- TempDB files, sizing, space use, and growth configuration
- auto-growth settings and recent default-trace growth events
- table statistics freshness, sample/modification percentages, and index status/usage
- unused-index review candidates and duplicate/same-key overlap analysis (ordered keys, INCLUDE columns, filters, uniqueness, and index type)
- missing-index indicators and optional `LIMITED` fragmentation scans for materially sized indexes
- top cached stored-procedure CPU/elapsed/read/write consumers per user database
- memory pressure snapshot, clerks, grants, buffer-cache distribution, RESOURCE_SEMAPHORE waits, and top cached query memory grants
- Availability Group, replication, and database mirroring inventory/health
- server logins, enabled sysadmins, `sa` status, disabled/locked accounts, and orphaned users
- instance configuration drift and recent default-trace object/configuration changes
- backup-history-based capacity trends and 90-day estimates

## Troubleshooting

| Symptom | Likely cause | Resolution |
|---------|--------------|------------|
| `Required assessment SQL file is missing/empty` | `sql_scripts` folder not copied alongside the script, or a file was moved | Deploy `Invoke-DbaAssessmentReport.ps1` and the full `sql_scripts` tree together. |
| `Excel export skipped: the ImportExcel module is not installed` | `-ExportExcel` used without ImportExcel | `Install-Module ImportExcel -Scope CurrentUser`. The HTML report is still generated. |
| `Cannot connect to '<server>'` | TCP/IP, port/instance, firewall, or credentials | Verify connectivity and the SQL login; check the log's `Connection` ERROR entry for the SQL error number. |
| Certificate trust error | Self-signed certificate on target | Handled automatically via `-TrustServerCertificate`; no action needed. |
| A section shows in Collection Errors | Permission denied, database offline/inaccessible, or version-specific DMV | Review the matching log ERROR entry (exception type + SQL error number); grant the missing permission or exclude the database. |
| Deep index section absent | `-DeepIndexCheck` not supplied | Re-run with `-DeepIndexCheck` during a low-activity window. |
| Windows Critical Events skipped | No `-WindowsCredential` | Supply a Windows credential with remote event-log access. |

## Important interpretation notes

- This is a point-in-time assessment, not continuous monitoring. DMV counters reset on SQL Server restart and can be distorted by short uptime.
- Index usage and unused-index results reset on restart/failover and may miss monthly/quarterly/DR workloads — they are review candidates only; the report never recommends an automatic `DROP INDEX`.
- Stored-procedure and cached-query metrics reset or disappear after restart, recompile, and plan-cache eviction; treat them as ranking evidence and compare with Query Store and an approved baseline.
- Memory waits are cumulative while grants and process flags are current snapshots. Correlate signals under representative peak load before changing max memory, DOP, or hardware.
- Missing-index DMVs are suggestions, not ready-to-run `CREATE INDEX` statements.
- Capacity projections use full-backup size history as an estimate; validate against retained file-size measurements.
- A collection failure appears in **Collection Errors** and the log. Missing evidence is not treated as a healthy result.
- Review recommendations with application owners and test configuration changes before applying them in production.
