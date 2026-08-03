# SQL Server Schema Compare & Sync

Compare the schema of two SQL Server databases and generate a **reviewable T-SQL sync
script** that brings the *Target* in line with the *Source*. Built for promoting schema
changes along a **Dev → UAT → Prod** pipeline.

A desktop GUI that wraps this engine ships under `schema_compare_GUI\` (see that folder's
`README.md`). The engine can also be run directly from PowerShell.

Entry points:

| Script | Purpose |
|--------|---------|
| `Compare-SqlSchema.ps1` | Compare one source/target pair, report diffs, generate (and optionally apply) a sync script. |
| `Invoke-SchemaSyncPipeline.ps1` | Drive multiple promotion hops (Dev→UAT→Prod) from `config/environments.json`. |
| `Test-SqlSchemaConnection.ps1` | Test instance, protocol, port, and SQL/Windows auth before running a compare. |

---

## What it compares

All **user** objects (system objects and the schemas in `-ExcludeSchema` are skipped):

- **Schemas**
- **User-Defined Data Types** and **User-Defined Table Types**
- **Sequences**
- **Synonyms**
- **Tables** — column adds/alters/drops, **indexes**, **foreign keys**, **check constraints**, and **table triggers**
- **Views**
- **Stored Procedures**
- **User-Defined Functions**
- **Database-level DDL triggers**

For each object the tool determines one of: `Missing in Target`, `Extra in Target`, or
`Definition Mismatch`.

---

## Prerequisites

```powershell
Install-Module dbatools -Scope CurrentUser -Force
```

- PowerShell 5.1+ (Windows PowerShell) or PowerShell 7+.
- Network reachability to both SQL Server instances (TCP port open for remote hosts).
- A login on **each** server with sufficient database permissions (see [Authentication & permissions](#authentication--permissions) below).

---

## Authentication & permissions

### Windows auth vs SQL auth

By default, if you omit `-SourceCredential` and `-TargetCredential`, the tool uses **Windows
Integrated Authentication** (your current Windows login).

| Scenario | Recommended auth |
|----------|------------------|
| Same domain / trusted forest | Windows integrated (no credentials needed) |
| Workgroup PC → remote IP / different domain | **SQL login** (`-SourceCredential` / `-TargetCredential`) |
| `sa` or dedicated service account on both servers | **SQL login** on source and target |

### "Untrusted domain" error (Windows auth to a remote server)

If TCP is open but login fails with:

```text
Login failed. The login is from an untrusted domain and cannot be used with Integrated authentication.
```

| What it means | What to do |
|---------------|------------|
| Network is OK (port reachable) | Authentication method is wrong for this hop |
| Your PC is not in a domain trusted by the remote SQL Server | Do **not** use Windows integrated auth to that server |
| sqlcmd / dbatools are sending your Windows identity | Pass a **SQL login** via `-Credential` or `-TargetCredential` |

This is common when connecting from a workgroup machine (e.g. `HOME-PC`) to a remote
IP such as `192.168.1.1`.

### Enable SQL Server authentication (both servers)

On **each** instance (source and target):

1. SSMS → right-click server → **Properties** → **Security**
2. **Server authentication**: **SQL Server and Windows Authentication mode**
3. Restart the **SQL Server** service

### Create a dedicated SQL login (recommended over `sa`)

Run on **source** and **target** (use the same login name/password on both if you prefer one account):

```sql
-- 1) Server login (adjust password)
CREATE LOGIN [schema_sync] WITH PASSWORD = 'YourStrongPassword!123',
    CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
GO

USE [ERP_System];   -- repeat for each database you compare
GO

CREATE USER [schema_sync] FOR LOGIN [schema_sync];

-- Compare only (read metadata)
ALTER ROLE [db_datareader] ADD MEMBER [schema_sync];
GRANT VIEW DEFINITION TO [schema_sync];

-- Generate + apply sync scripts on TARGET (DDL — required beyond db_datawriter)
ALTER ROLE [db_ddladmin] ADD MEMBER [schema_sync];
-- OR full control on that database:
-- ALTER ROLE [db_owner] ADD MEMBER [schema_sync];
GO
```

### Permission reference

| Permission | Compare (read) | Generate scripts | `-Apply` on target |
|------------|----------------|------------------|---------------------|
| `CONNECT` + `db_datareader` | Yes | — | — |
| `VIEW DEFINITION` | Yes (recommended) | — | — |
| `db_datawriter` | — | **No** (data DML only, not DDL) | **No** |
| `db_ddladmin` or `db_owner` | — | Yes | Yes |

`db_datawriter` allows **INSERT/UPDATE/DELETE on table data** only. Schema sync needs
**DDL** (`CREATE` / `ALTER` / `DROP` on tables, indexes, procedures, etc.) — use
`db_ddladmin` or `db_owner` on the **target** database at minimum.

### Use SQL credentials in PowerShell

```powershell
# Prompt for credentials (once per account, or reuse the same object for both)
$srcCred = Get-Credential -Message 'Source SQL login (e.g. schema_sync or sa)'
$tgtCred = Get-Credential -Message 'Target SQL login (e.g. schema_sync or sa)'

# Or sa explicitly:
$sa = Get-Credential -UserName sa -Message 'SA password'
```

**Test before compare** with `Test-SqlSchemaConnection.ps1`:

```powershell
# Local source (Named Pipes if TCP/1433 is disabled locally)
.\Test-SqlSchemaConnection.ps1 `
    -SqlInstance . `
    -NetworkProtocol NamedPipes `
    -Database ERP_System `
    -Credential $srcCred

# Remote target (TCP + SQL auth)
.\Test-SqlSchemaConnection.ps1 `
    -SqlInstance 192.168.1.1 `
    -Port 1433 `
    -Database ERP_System `
    -Credential $tgtCred
```

**Compare with SQL auth on both sides:**

```powershell
.\Compare-SqlSchema.ps1 `
    -SourceSqlInstance . `
    -NetworkProtocol NamedPipes `
    -SourceCredential $srcCred `
    -TargetSqlInstance 192.168.1.1 `
    -TargetPort 1433 `
    -TargetCredential $tgtCred `
    -Database ERP_System `
    -GenerateSyncScript
```

Same SQL login on source and target:

```powershell
$cred = Get-Credential -Message 'SQL login for source and target'
.\Compare-SqlSchema.ps1 `
    -SourceSqlInstance . `
    -NetworkProtocol NamedPipes `
    -SourceCredential $cred `
    -TargetSqlInstance 192.168.1.1 `
    -TargetPort 1433 `
    -TargetCredential $cred `
    -Database ERP_System `
    -GenerateSyncScript
```

### Pipeline with SQL authentication

Set `"Auth": "Sql"` per environment in `config/environments.json` and pass `-Credential`:

```jsonc
{
  "Environments": {
    "Dev":  { "SqlInstance": ".",               "Auth": "Sql", "Databases": ["ERP_System"] },
    "Uat":  { "SqlInstance": "192.168.1.1",  "Auth": "Sql", "Databases": ["ERP_System"] }
  },
  "Promotions": [
    { "Source": "Dev", "Target": "Uat", "IncludeDrops": false, "AutoApply": false }
  ]
}
```

```powershell
$cred = Get-Credential
.\Invoke-SchemaSyncPipeline.ps1 -Credential $cred
```

---

## Connectivity & troubleshooting

Use `Test-SqlSchemaConnection.ps1` to validate instance name, protocol, port, and credentials
before running a full compare.

### Instance names

| Installation | `-SqlInstance` value |
|--------------|----------------------|
| Local default instance | `.` or `localhost` (not always the PC name) |
| Local named instance | `.\SQLEXPRESS` or `MACHINE\INSTANCENAME` |
| Remote default on port 1433 | `192.168.1.1` with `-Port 1433` |
| Remote static port | `host,51433` or `-SqlInstance host -Port 51433` |

### Network protocol

| Protocol | When to use |
|----------|-------------|
| `TcpIp` (default) | Remote servers, or local when TCP/IP is enabled |
| `NamedPipes` | Local default instance when TCP/1433 is closed/disabled |
| `SharedMemory` | Local only (rare) |

```powershell
# Local with TCP disabled — use Named Pipes
.\Compare-SqlSchema.ps1 -SourceSqlInstance . -NetworkProtocol NamedPipes ...

# Remote over TCP
.\Compare-SqlSchema.ps1 -TargetSqlInstance 192.168.1.1 -TargetPort 1433 -NetworkProtocol TcpIp ...
```

### ODBC Driver 18 / certificate errors

If sqlcmd reports *certificate chain … not trusted*, the diagnostic script and compare tool
default to `TrustServerCertificate=True`. You can also pass `-TrustServerCertificate` explicitly,
or use sqlcmd `-C` when testing manually.

### Enable TCP/IP (optional, for local or remote TCP access)

1. **SQL Server Configuration Manager**
2. **SQL Server Network Configuration** → **Protocols for MSSQLSERVER**
3. Enable **TCP/IP** → **IP Addresses** → **IPAll** → **TCP Port** = `1433`
4. Restart **SQL Server (MSSQLSERVER)** and allow the port in Windows Firewall on the server

### Common diagnostic outcomes

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| TCP port CLOSED on `localhost` | TCP/IP disabled locally | `-NetworkProtocol NamedPipes` or enable TCP/IP |
| TCP port OPEN, login untrusted domain | Windows auth to untrusted remote | `-TargetCredential` with SQL login |
| ODBC SSL / certificate error | Driver 18 encryption | `-TrustServerCertificate` (default in tool) |
| Login failed for user 'x' | Wrong password or login missing on server | Create login; verify mixed mode |
| Cannot open database | User not mapped in database | `CREATE USER` in target database |

---

## Quick start

```powershell
cd .\schema_compare\

# 1) Compare only — see what differs (console + HTML report)
.\Compare-SqlSchema.ps1 -SourceSqlInstance SQL-DEV-01 -TargetSqlInstance SQL-UAT-01 -Database Sales

# 2) Compare + generate a sync script (nothing is executed)
.\Compare-SqlSchema.ps1 -SourceSqlInstance SQL-DEV-01 -TargetSqlInstance SQL-UAT-01 `
    -Database Sales -GenerateSyncScript

# 3) Generate + apply after a confirmation prompt (includes destructive drops)
.\Compare-SqlSchema.ps1 -SourceSqlInstance SQL-DEV-01 -TargetSqlInstance SQL-UAT-01 `
    -Database Sales -GenerateSyncScript -IncludeDrops -Apply
```

Scripts and reports are written to `.\output\` by default.

---

## One-to-many: one source DB → many destination databases

Use this when a **single source database** (template / golden schema) should be synced to
**many databases on one target server** (multi-tenant hosts, regional copies, etc.).

The destination list comes from a file (`.txt` / `.json` / `.yml`) or from `-TargetDatabase`
with multiple names. Sync scripts are prepared **per destination database**.

### List file formats

**JSON** (`config/destination_databases.json`):

```json
{ "DestinationDatabases": [ "Tenant_Alpha", "Tenant_Beta", "Tenant_Gamma" ] }
```

Also accepts a plain array, or keys `TargetDatabases` / `Databases`.

**YAML** (`config/destination_databases.yml`):

```yaml
DestinationDatabases:
  - Tenant_Alpha
  - Tenant_Beta
  - Tenant_Gamma
```

**Text** (`config/destination_databases.txt`) — one name per line; `#` comments allowed.

### CLI examples

```powershell
# Preferred: list file
.\Compare-SqlSchema.ps1 `
    -SourceSqlInstance SQL-DEV-01 `
    -TargetSqlInstance SQL-TENANT-01 `
    -Database TemplateDb `
    -TargetDatabaseListFile .\config\destination_databases.json `
    -GenerateSyncScript

# Same fan-out without a file (1 source, N targets)
.\Compare-SqlSchema.ps1 `
    -SourceSqlInstance SQL-DEV-01 `
    -TargetSqlInstance SQL-TENANT-01 `
    -Database TemplateDb `
    -TargetDatabase Tenant_Alpha,Tenant_Beta,Tenant_Gamma `
    -GenerateSyncScript
```

Rules:

| Rule | Detail |
|------|--------|
| Source | Exactly **one** database in `-Database` when using a list file or N targets |
| Target server | Still a **single** `-TargetSqlInstance` |
| Missing DB | Run fails fast if any listed destination DB is missing on the target |
| Mutual exclusion | Do not pass both `-TargetDatabase` and `-TargetDatabaseListFile` |

### Output layout (multi-DB)

```
output/SchemaSync_<stamp>/
├── _manifest.csv                 # all destinations (includes RelativeFolder)
├── _README_MULTI_DB_INDEX.txt    # per-DB sqlcmd cheat sheet
├── SchemaCompare_<stamp>.html
├── Tenant_Alpha/
│   ├── auto_Tenant_Alpha__...sql
│   ├── _master_auto_only.sql
│   ├── _master_migration.sql
│   └── _README_RUN_ON_TARGET.txt
└── Tenant_Beta/
    └── ...
```

Run each destination’s master script **from inside that subfolder** (so `:r` paths resolve).

### Pipeline config

Point the target environment at a list file (path relative to `config/` or the script root):

```jsonc
{
  "Environments": {
    "Template": {
      "SqlInstance": "SQL-DEV-01",
      "Auth": "Windows",
      "Databases": [ "TemplateDb" ]
    },
    "Tenants": {
      "SqlInstance": "SQL-TENANT-01",
      "Auth": "Windows",
      "DestinationDatabaseListFile": "destination_databases.json"
    }
  },
  "Promotions": [
    { "Source": "Template", "Target": "Tenants", "IncludeDrops": false, "AutoApply": false }
  ]
}
```

```powershell
.\Invoke-SchemaSyncPipeline.ps1 -Only Tenants
```

---

## `Compare-SqlSchema.ps1` parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SourceSqlInstance` | string | *required* | Source ("source of truth") instance. |
| `-TargetSqlInstance` | string | *required* | Target instance to be synced. |
| `-Database` | string[] | *required* | One or more source databases. For one-to-many, supply exactly one name. |
| `-TargetDatabase` | string[] | = `-Database` | Target DB names. Same count = 1:1 pairing; one source + many names = 1:N fan-out. |
| `-TargetDatabaseListFile` | string | — | `.txt` / `.json` / `.yml` list of destination DBs (one-to-many; requires one source DB). |
| `-SourceCredential` | PSCredential | — | SQL auth for source (Windows auth if omitted). |
| `-TargetCredential` | PSCredential | — | SQL auth for target. |
| `-SourcePort` | int | `0` | TCP port for source (`server,port` when not 1433). |
| `-TargetPort` | int | `0` | TCP port for target (e.g. `1433` on `192.168.1.1`). |
| `-ConnectionTimeout` | int | `30` | Connection timeout in seconds. |
| `-TrustServerCertificate` | switch | on* | Trust server TLS cert (ODBC 18 / dev instances). *Default when switch omitted. |
| `-NetworkProtocol` | string | `TcpIp` | `TcpIp`, `NamedPipes`, or `SharedMemory` (`Tcp`/`Np` aliases accepted). |
| `-IncludeObjectType` | string[] | all | Restrict to specific object types. |
| `-ExcludeSchema` | string[] | `sys,INFORMATION_SCHEMA,guest` | Schemas to skip. |
| `-GenerateSyncScript` | switch | off | Emit per-object/per-purpose `auto_`/`manual_` `.sql` scripts + manifest. |
| `-IncludeDrops` | switch | off | Also generate drops for objects/indexes/constraints that exist only in target (destructive; table/column drops are always `manual_`). |
| `-Apply` | switch | off | Execute the `auto_` scripts against the target, in run-order (needs `-GenerateSyncScript`). Continues on script failure (per-database status + remaining scripts). Re-compares after apply for verification. `manual_` scripts are never auto-applied. |
| `-OutputPath` | string | `.\output` | Output directory. |
| `-ReportFormat` | string[] | `Console,Html` | Any of `Console`, `GridView`, `Html`, `None`. |
| `-Quiet` | switch | off | Suppress progress chatter. |

### Direction / "source of truth"

The **Source is always the source of truth** — the Target is changed to match it. To flip
direction, simply swap the `-SourceSqlInstance` and `-TargetSqlInstance` values (this
replaces the `$IsServerASource` toggle from the original scratch script).

---

## Dev → UAT → Prod pipeline

Edit `config/environments.json` to describe your tiers and the promotion hops:

```jsonc
{
  "Environments": {
    "Dev":  { "SqlInstance": "SQL-DEV-01",  "Auth": "Windows", "Databases": ["Sales","HR"] },
    "Uat":  { "SqlInstance": "SQL-UAT-01",  "Auth": "Windows", "Databases": ["Sales","HR"] },
    "Prod": { "SqlInstance": "SQL-PROD-01", "Auth": "Windows", "Databases": ["Sales","HR"] }
  },
  "Promotions": [
    { "Source": "Dev", "Target": "Uat",  "IncludeDrops": false, "AutoApply": false },
    { "Source": "Uat", "Target": "Prod", "IncludeDrops": false, "AutoApply": false }
  ],
  "Options": {
    "ExcludeSchema": ["sys","INFORMATION_SCHEMA","guest","staging"],
    "IncludeObjectType": ["Schemas","Tables","Views","StoredProcedures","UserDefinedFunctions"]
  }
}
```

Run the pipeline:

```powershell
# Generate review scripts for every hop, apply nothing
.\Invoke-SchemaSyncPipeline.ps1

# Only the Dev->Uat hop, and apply it (prompts for confirmation)
.\Invoke-SchemaSyncPipeline.ps1 -Only Uat -Apply

# Force "scripts only" even if a hop has AutoApply:true
.\Invoke-SchemaSyncPipeline.ps1 -WhatIfScriptsOnly
```

**Recommended promotion flow:** let Dev→UAT auto-apply in a scheduled job, keep UAT→Prod
as *script-only* and apply the reviewed script manually during a change window.

### Automating with SQL Agent / Task Scheduler

```powershell
pwsh -NoProfile -File "D:\...\schema_compare\Invoke-SchemaSyncPipeline.ps1" -Only Uat -Apply -Confirm:$false
```

---

## Generated scripts: `auto_` vs `manual_`

Instead of one big file, the tool writes **one script per object, per purpose**, into a
timestamped run folder (`output\SchemaSync_<stamp>\`). Each file is named:

```
<auto|manual>_<Database>__<schema.object>__<purpose>.sql
```

Examples:

```
auto_Sales__dbo.Customer__table_create.sql
auto_Sales__dbo.Customer__column_add.sql
auto_Sales__dbo.Customer__index.sql
auto_Sales__dbo.Customer__constraints.sql
manual_Sales__dbo.Customer__pk_change.sql
manual_Sales__dbo.Customer__column_update.sql   (e.g. a data-type shrink)
```

Purposes: `schema`, `type`, `sequence`, `synonym`, `table_create`, `column_add`,
`column_update`, `index`, `constraints`, `trigger`, `view`, `function`,
`stored_procedure`, `db_trigger`, plus manual ones `pk_change`, `pk_datatype_change`,
`column_remove`, `cleanup_drop`.

### `auto_` scripts (safe, run-at-once)

- Contain a **metadata header** listing the table/object and every change (new columns
  with types, indexes created/rebuilt, constraints added, etc.).
- Are **self-contained and idempotent** — every statement is guarded with existence
  validation (`IF COL_LENGTH(...) IS NULL`, `IF NOT EXISTS (sys.indexes ...)`, etc.), so
  re-running is safe.
- Wrapped in `SET XACT_ABORT ON` + `BEGIN TRY / BEGIN TRAN … COMMIT … END TRY / CATCH …
  ROLLBACK; THROW` so the whole file either fully applies or cleanly rolls back — **no
  syntax errors, runnable in one shot** in SSMS or via the tool.
- Programmable objects (views/functions/procs/triggers) use **`CREATE OR ALTER`** (SQL
  Server 2016 SP1+) so they apply whether or not the object already exists.
- **Index changes drop the existing index and create the new one** (`DROP INDEX` +
  `CREATE INDEX`) inside the guarded batch.
- New tables are created **without** their foreign keys first (`table_create`), then FKs
  are added in the `constraints` step, so referenced tables always exist first.

### `manual_` scripts (careful review required)

Changes that can lose data or need orchestration are written to `manual_` files with a
prominent warning banner and a per-item **RISK** note. They are **never auto-applied**.
These include:

- **Primary-key changes** — add/drop/modify PK, PK column changes/renames
  (`pk_change`): needs dependent FKs dropped, possible dedupe and clustered-index rebuild.
- **PK column datatype changes** (`pk_datatype_change`) — orchestrated as one manual
  script in this order: drop referencing FKs → drop parent PK (and related parent indexes)
  → alter parent PK column → drop child FK indexes → alter child FK columns → recreate
  parent PK / indexes → recreate child indexes → recreate FKs. The HTML report and GUI
  Manual Actions tab document the same sequence.
- **Column data-type shrink / type-family change / `NULL`→`NOT NULL`** (`column_update`).
- **Computed / IDENTITY column changes** (require a table rebuild).
- **Column removals** and **table drops** (`column_remove`, `cleanup_drop`) — destructive.
- **Unique-constraint** and **user-defined type** rebuilds.

### Apply order & manifest

A `_manifest.csv` in the run folder lists every generated file with **Phase**, **run order**,
**Blockers** (manual scripts that must complete first), and **Prerequisites** (auto scripts
that should already be applied). Two master catalogs are also emitted:

| File | Purpose |
|------|---------|
| `_master_auto_only.sql` | **Run on TARGET** — one-shot apply of all `auto_` scripts (safe changes only). Use when no `manual_` scripts exist, or after manual steps are done. |
| `_master_migration.sql` | **Run on TARGET** — full runbook with `/* MANUAL ACTION REQUIRED */` checkpoints. Use for UAT/Prod when `manual_` scripts exist. |
| `_README_RUN_ON_TARGET.txt` | Plain-text copy/paste instructions (which file, sqlcmd commands). |
| `_manifest.csv` | Full file list with run order, blockers, and prerequisites. |
| `_deploy_report.csv` | Written when `-Apply` runs — per-database apply status, applied/failed counts, failed scripts, and post-apply verification / remaining diffs. |

When `-Apply` is used, each target database is processed independently: a failed script is
recorded and remaining auto scripts (and remaining databases in multi-target runs) continue.
After apply, the engine re-compares that database and records whether it is synchronized.
The HTML report includes a **Deployment & verification** section when apply was performed.

Run on the **TARGET** server only (never source). `cd` to the `SchemaSync_<stamp>` folder first so `:r` paths resolve.

**Which file?**

| Situation | File |
|-----------|------|
| No `manual_*.sql` files, or all manual steps already completed | `_master_auto_only.sql` |
| `manual_*.sql` exist (PK changes, risky alters) — UAT/Prod promotion | `_master_migration.sql` |

```powershell
cd "D:\...\schema_compare\output\SchemaSync_<stamp>"

# SQL login
sqlcmd -S 192.168.10.200 -d ERP_System -U schema_sync -P "YourPassword" -C -i ".\_master_auto_only.sql"

# Windows auth
sqlcmd -S 192.168.10.200 -d ERP_System -E -C -i ".\_master_auto_only.sql"
```

Each generated `.sql` file also has these commands in its header comment block. See `_README_RUN_ON_TARGET.txt` in the same folder.

---

## Limitations & safety notes

- **Always review generated scripts** and test against a restored copy before running on
  Prod. This tool automates the diff and first-draft script, not your change control.
- Table changes requiring a data-moving rebuild are flagged for manual handling, not
  auto-generated.
- Data (rows), permissions/logins, and server-level objects are **out of scope** — this is
  a *schema* compare. Use dbatools (`Copy-DbaLogin`, `Copy-DbaDbTableData`, etc.) for those.
- Cross-version scripting (e.g. comparing SQL 2016 → 2022) works but validate any
  version-specific syntax the source may emit.

---

## Implementation notes (peer-review hardening)

| Area | Behaviour |
|------|-----------|
| **Large CREATE TABLE** | DDL is assigned via chunked `SET @sql = @sql + N'...'` (3 000-char blocks) to avoid the implicit `nvarchar(4000)` literal cap |
| **Drift comparison** | `Get-CanonicalScript` strips block/line comments, `SET` noise and collapses whitespace (case-insensitive) to reduce false positives |
| **IDENTITY columns** | Seed and increment drift is flagged as `manual_` (not just add/remove identity) |
| **SMO performance** | `SetDefaultInitFields` limits enumeration payload; child objects lazy-load on access |
| **Dependency order** | Manifest maps blockers/prerequisites; `_master_migration.sql` inserts manual checkpoints before blocked phases |

---

## Folder structure

```
schema_compare/
├── Compare-SqlSchema.ps1          # Core compare + per-purpose script generator
├── Invoke-SchemaSyncPipeline.ps1  # Dev->UAT->Prod / one-to-many orchestrator
├── Test-SqlSchemaConnection.ps1   # Connection / auth / protocol diagnostic
├── config/
│   ├── environments.json          # Pipeline definition
│   ├── destination_databases.json # Sample one-to-many destination list (JSON)
│   ├── destination_databases.yml  # Sample one-to-many destination list (YAML)
│   └── destination_databases.txt  # Sample one-to-many destination list (text)
├── output/
│   └── SchemaSync_<stamp>/        # One run:
│       ├── auto_<db>__<obj>__<purpose>.sql   # (single-DB runs: flat)
│       ├── manual_<db>__<obj>__<purpose>.sql
│       ├── _manifest.csv
│       ├── _README_RUN_ON_TARGET.txt
│       ├── _master_migration.sql
│       ├── _master_auto_only.sql
│       ├── SchemaCompare_<stamp>.html
│       ├── _README_MULTI_DB_INDEX.txt        # multi-DB / one-to-many only
│       └── <TargetDb>/                       # multi-DB: per-destination scripts + masters
└── README.md
```

---

## Troubleshooting

| Error / symptom | Cause | Fix |
|---------------|-------|-----|
| `Cannot find module 'dbatools'` | Module not installed | `Install-Module dbatools -Scope CurrentUser` |
| `untrusted domain` / Integrated auth failed | Windows auth to remote or untrusted host | `-SourceCredential` / `-TargetCredential` with SQL login; enable mixed mode on SQL Server |
| TCP port 1433 CLOSED (local) | TCP/IP disabled on local instance | `-NetworkProtocol NamedPipes -SourceSqlInstance .` or enable TCP/IP in Configuration Manager |
| ODBC certificate / SSL error | ODBC Driver 18 encrypts by default | `-TrustServerCertificate` (on by default) or sqlcmd `-C` |
| `Login failed for user` | Wrong password or login missing | Create login on server; verify SQL + Windows auth mode |
| DDL fails despite `db_datawriter` | Role is data-only, not schema | Grant `db_ddladmin` or `db_owner` on target database |
| Access denied / metadata read fails | Insufficient read permissions | `db_datareader` + `GRANT VIEW DEFINITION` on source |
| `NetworkProtocol` validation error | Invalid protocol name | Use `TcpIp`, `NamedPipes`, or `SharedMemory` (not `Tcp`) |
| Connection to PC name fails locally | Default instance not listening on hostname | Use `.` or `localhost` instead of machine name |
