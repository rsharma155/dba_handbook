# SQL Optima — Schema Compare

A **Windows desktop application** (WinForms, .NET 8) for comparing SQL Server schemas
and generating reviewable sync scripts — inspired by
[OpenDBDiff](https://github.com/OpenDBDiff/OpenDBDiff), powered by the bundled
`schema_compare` PowerShell engine (dbatools/SMO).

**Self-contained:** everything the tool needs — the GUI, the PowerShell compare
engine, launchers, and config samples — lives in this one folder. Zip it, share it,
extract it anywhere, and run it. No sibling folders required.

---

## What it does

- Connects to a **Source** ("source of truth") and a **Target** SQL Server database.
- Extracts metadata for all user objects — schemas, tables (columns, indexes, FKs,
  check constraints, triggers), views, stored procedures, functions, UDTs/UDTTs,
  sequences, synonyms, and DDL triggers — and diffs them.
- Shows differences color-coded as **Added / Removed / Changed / Identical / Ignored**
  in an Object Explorer tree with search and object-type filters.
- Generates an ordered, **self-contained deployable `.sql` script** (no `:r` includes)
  to bring the Target in line with the Source — plus a separate **Manual Actions**
  list for risky changes that must be reviewed and run by hand.
- Supports **One-to-Many**: one source database fanned out to multiple target
  databases (checked list or a `.json` / `.yml` / `.txt` list file).
- Produces an **HTML report** and a full run folder per comparison under
  `schema_compare\output\SchemaSync_*`.

Nothing is ever applied automatically unless you explicitly enable **Apply**.

---

## How it works

```text
┌─────────────────────────────────────────────┐
│  SqlOptima.SchemaCompare.exe (WinForms UI)  │  connections, options, results,
│  nav rail · workflow steps · object explorer│  script preview, progress log
└──────────────────────┬──────────────────────┘
                       │  request.json  (passwords only via process env vars)
                       ▼
        tools\Invoke-CompareForGui.ps1          ← JSON bridge (request → result)
                       │
                       ▼
     schema_compare\Compare-SqlSchema.ps1       ← compare engine (dbatools/SMO)
                       │
                       ▼
   schema_compare\output\SchemaSync_*\          ← scripts + HTML report + result JSON
```

1. The GUI writes a `request.json` describing the comparison (servers, databases,
   options) to a temp folder and launches the bridge script in a child PowerShell.
2. The bridge calls the engine script with the equivalent parameters, captures its
   log for the **Progress Log** tab, and writes a structured `result.json`.
3. The GUI parses the result into the difference tree, badges, script preview, and
   manual-actions tabs. Child processes are tracked and killed on cancel/close.
4. SQL passwords are passed only through process environment variables for the
   bridge run — never written to disk. Session settings (no passwords) live under
   `%AppData%\SqlOptima\SchemaCompare\`.

---

## Folder layout (self-contained)

```text
schema_compare_GUI/                        ← share this whole folder as a zip
├── SqlOptima.SchemaCompare.sln            ← solution
├── SqlOptima.SchemaCompare/               ← desktop app (WinForms, .NET 8)
├── SqlOptima.SchemaCompare.Tests/         ← xUnit test suite (98 tests)
├── schema_compare/                        ← bundled PowerShell compare engine
│   ├── Compare-SqlSchema.ps1              ← core engine
│   ├── Test-SqlSchemaConnection.ps1       ← connectivity diagnostics
│   ├── Invoke-SchemaSyncPipeline.ps1      ← Dev → UAT → Prod pipeline runner
│   ├── config/                            ← sample destination lists + environments
│   └── output/                            ← comparison run folders land here
├── tools/
│   ├── Invoke-CompareForGui.ps1           ← GUI ↔ engine JSON bridge
│   └── Test-CompareBridge.ps1             ← bridge dry-run regression harness
├── scripts/                               ← launchers & legacy PowerShell GUI
│   ├── Launch-DesktopApp.cmd              ← double-click to build + run the app
│   ├── Run-Tests.cmd                      ← run the full test suite
│   ├── Start-SchemaCompareGui.ps1         ← legacy PowerShell-forms GUI
│   ├── SchemaCompareGui.Helpers.ps1       ← shared PS helpers
│   └── Launch-SchemaCompareGui.cmd        ← launcher for the legacy GUI
├── docs/                                  ← review feedback / design notes
└── README.md
```

The root contains only project-level code and the solution file; all loose
scripts live in `scripts/`, the engine in `schema_compare/`, docs in `docs/`.

### Path discovery

The app locates the engine automatically: it first looks for the **bundled**
`schema_compare\` folder under the install root (zip layout, works even if you
rename the extracted folder), and falls back to a sibling `schema_compare` folder
(legacy monorepo layout). No configuration needed.

---

## Prerequisites

1. **.NET 8 Desktop Runtime** (or the SDK to build) —
   https://dotnet.microsoft.com/download/dotnet/8.0
2. **PowerShell 5.1+** (or PowerShell 7) and **dbatools**:

```powershell
Install-Module dbatools -Scope CurrentUser -Force
```

---

## Launch

**Recommended:** double-click

```text
scripts\Launch-DesktopApp.cmd
```

It builds the app on first run and starts it. Or run the exe directly after a build:

```text
SqlOptima.SchemaCompare\bin\Release\net8.0-windows\SqlOptima.SchemaCompare.exe
```

**Legacy PowerShell form** (simpler UI): `scripts\Launch-SchemaCompareGui.cmd`

---

## The redesigned UI

The window follows a guided **Connect → Compare → Review → Deploy** workflow:

| Area | What it does |
|------|--------------|
| Header bar | Brand, workflow step indicator, Presets, Save Script, Settings, Help, and the **Compare Schemas** call-to-action |
| Left nav rail | **Compare** workspace · **History** (SchemaSync runs) · **Scripts** (preview / output root) · **Reports** (latest HTML) · **Settings** |
| Connection card | Collapsible "1. Connect to Source and Target" card — server, port, auth, database pickers, Test Connection with inline status, password show/hide, and a **swap** button; auto-collapses when a comparison starts |
| Action bar | Comparison profile, ignore rules, object-type filters, **Compare Now** |
| Object Explorer | Category tree with search (`table:customer`, `added`, `schema:dbo`…) and refresh |
| Results | **Overview** dashboard, **Object Details**, **Script Preview** (dark editor), **Manual Actions**, **Progress Log**, with Added / Removed / Changed / Identical / Ignored count badges |
| Status bar | Source / Target / object count / elapsed time |

No text is truncated anywhere — buttons and badges auto-size to their captions.

---

## Typical workflow

1. Enter **Source** server → **Test Connection** → **Browse** → pick the source database
2. Enter **Target** server → Test → pick target database(s)
3. For **One-to-Many**: pick one source DB, then check multiple target DBs or browse a
   list file (samples in `schema_compare\config\`)
4. Optionally adjust **Options** (sync script generation, drops, apply, protocol, output)
5. Click **Compare Now** — the connection card collapses and progress streams live
6. Review the difference tree and Overview badges
7. Open **Script Preview** — a self-contained `.sql` ready to run on the TARGET
8. If **Manual Actions** shows entries, review those scripts and run them by hand
9. **Save Script** to export `Deploy_AutoChanges_*.sql` (plus `*_MANUAL.sql` when needed)
10. Open the **HTML report** / output folder for the full run

Leave **Apply** off until scripts have been reviewed.

### Deployable vs manual scripts

| Output | Safe to auto-run? | How to use |
|--------|-------------------|------------|
| Deployable script (`auto_` changes, inlined) | Yes, after review | SSMS / sqlcmd on the TARGET |
| Manual actions (`manual_` changes) | **No** | Review, back up, execute by hand |

Manual scripts are never auto-applied; the GUI warns whenever they are produced.

---

## Sharing as a zip

```powershell
# Optional: prune build output first
dotnet clean SqlOptima.SchemaCompare.sln -c Release

Compress-Archive -Path .\* -DestinationPath ..\SqlOptima.SchemaCompare.zip
```

The recipient extracts the zip anywhere (any folder name works), installs the
prerequisites above, and double-clicks `scripts\Launch-DesktopApp.cmd`.

---

## Build & test

```powershell
# Build / run
dotnet build SqlOptima.SchemaCompare.sln -c Release
dotnet run --project SqlOptima.SchemaCompare -c Release

# Tests (98 xUnit tests) — or scripts\Run-Tests.cmd
dotnet test SqlOptima.SchemaCompare.sln -c Release

# Bridge dry-run harness (no SQL Server needed)
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-CompareBridge.ps1

# Optional single-file publish
dotnet publish SqlOptima.SchemaCompare -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true
```

Test coverage includes connection strings, diff filtering, one-to-many target
resolution, bundled-engine path discovery (including renamed zip folders), capped
log buffers, child-process kill, temp cleanup, settings persistence (no passwords),
shell components (nav rail, badges, collapsible card), metadata headers on every
source file, and MainForm construct/shutdown lifecycle.

---

## Reliability & clean exit

| Concern | How it is handled |
|---------|-------------------|
| Orphan PowerShell | `ChildProcessTracker` + `Kill(entireProcessTree)` on cancel/close |
| Temp request files | Deleted after each run; old folders purged on exit |
| SQL passwords in env | Cleared after each bridge run and on `ApplicationExit` |
| Large logs/scripts | Capped buffers + script preview size limit |
| UI thread | Async compare with marshalled log updates; busy flag blocks re-entry |
| Unhandled errors | `ThreadException` / `UnhandledException` handlers show a dialog |
| App close | Cancels compare → kills children → clears buffers → graceful shutdown |

Closing the window asks to cancel an in-flight compare, then shuts down all tracked
child processes — no leftover `powershell.exe` instances.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| App won't start | Install .NET 8 Desktop Runtime; `scripts\Launch-DesktopApp.cmd` auto-builds |
| "Cannot locate the Schema Compare install" | Keep the folder intact — `tools\` and `schema_compare\` must stay next to the solution |
| Compare fails / dbatools missing | `Install-Module dbatools -Scope CurrentUser` |
| Browse databases fails | Check firewall/auth; type DB names manually if needed |
| No scripts in tab | Enable **Generate sync scripts** in Options |
| Connectivity diagnosis | `schema_compare\Test-SqlSchemaConnection.ps1 -SqlInstance <server>` |

---

## License / credit

UI concept inspired by [OpenDBDiff](https://github.com/OpenDBDiff/OpenDBDiff).
Compare engine: the bundled `schema_compare` PowerShell toolkit.
Copyright (c) 2026 Ravi Sharma — MIT (SPDX: MIT).
