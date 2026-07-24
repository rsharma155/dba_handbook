# SQL Schema Compare — Desktop GUI

OpenDBDiff-inspired **Windows desktop application** for comparing SQL Server schemas and
generating sync scripts. More robust and user-friendly than a basic form, while reusing
the existing **`schema_compare`** PowerShell engine (unchanged).

Inspired by [OpenDBDiff](https://github.com/OpenDBDiff/OpenDBDiff).

---

## What you get (vs OpenDBDiff)

| Area | OpenDBDiff-like | Extra in this app |
|------|-----------------|-------------------|
| Layout | Source / Destination cards, Compare, Options | Clear “source of truth” labeling + modern high-contrast theme |
| Results | Difference tree + Synchronized script tab | Color-coded Add / Update / Extra |
| Script | Sync script view + copy | **Self-contained deployable `.sql`** (no `:r` includes) + **Manual actions** warning tab |
| Scope | One source DB ↔ one dest DB | **One-to-Many** (check multiple dest DBs / list file) |
| UX | Classic WinForms | Test connection, Refresh DBs, Select all / Clear, filter tree, HTML report, progress log |
| Engine | Built-in .NET differ | Existing hardened `Compare-SqlSchema.ps1` (dbatools/SMO) |

---

## Launch

**Recommended — desktop app:**

```text
schema_compare_GUI\Launch-DesktopApp.cmd
```

Or after build:

```text
schema_compare_GUI\SqlOptima.SchemaCompare\bin\Release\net8.0-windows\SqlOptima.SchemaCompare.exe
```

**Legacy PowerShell form** (simpler UI):

```text
schema_compare_GUI\Launch-SchemaCompareGui.cmd
```

---

## Prerequisites

1. **.NET 8 Desktop Runtime** (or SDK to build)  
   https://dotnet.microsoft.com/download/dotnet/8.0
2. **PowerShell 5.1+** and **dbatools** (same as `schema_compare`):

```powershell
Install-Module dbatools -Scope CurrentUser -Force
```

3. Folder layout (keep these siblings):

```text
dba_essential_scripts/
├── schema_compare/          ← engine (do not move)
└── schema_compare_GUI/      ← this GUI
```

---

## Typical workflow

1. Enter **Source** server → **Test** → **Refresh DBs** → pick source database  
2. Enter **Destination** server → Test → Refresh → **check one or more** target databases (use **Select all** / **Clear**)  
3. Optional: **Options** (generate scripts, include drops, apply, protocol, output folder)  
4. Click **Compare**  
5. Browse the **difference tree** (filter box supported)  
6. Open the **Deployable script** tab — a self-contained `.sql` ready to run on the TARGET  
7. If the **Manual actions** tab shows a warning, review those scripts and run them by hand  
8. Click **Save deploy script** to export `Deploy_AutoChanges_*.sql` (plus `*_MANUAL.sql` when needed)  
9. Review **HTML report** / **Open output** for the full run folder  

Leave **Apply** off until scripts are reviewed.

### Deployable vs manual scripts

| Output | Safe to auto-run? | How to use |
|--------|-------------------|------------|
| **Deployable script** (`auto_` changes, inlined) | Yes (after review) | SSMS / sqlcmd on TARGET — no `:r` includes needed |
| **Manual actions** (`manual_` changes) | **No** | Review carefully, take a backup, execute by hand |

The GUI warns you whenever manual scripts are produced. They are never auto-applied.

### One-to-Many

1. Select **One-to-Many**  
2. Pick **one** source database  
3. On the destination card, **check multiple databases** (or browse a `.json` / `.yml` / `.txt` list file such as `schema_compare\config\destination_databases.json`)  
4. Compare — each destination gets its own scripts; the deployable export combines them into one file with per-database sections  

---

## Folder layout

```text
schema_compare_GUI/
├── Launch-DesktopApp.cmd
├── Run-Tests.cmd
├── SqlOptima.SchemaCompare.sln
├── SqlOptima.SchemaCompare/           ← desktop app
├── SqlOptima.SchemaCompare.Tests/     ← xUnit tests (46+)
├── tools/Invoke-CompareForGui.ps1
└── README.md
```

---

## Build from source

```powershell
cd schema_compare_GUI\SqlOptima.SchemaCompare
dotnet build -c Release
dotnet run -c Release
```

Optional single-file publish:

```powershell
dotnet publish -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true
```

---

## Testing

```powershell
cd schema_compare_GUI
dotnet test SqlOptima.SchemaCompare.sln -c Release
```

Or:

```text
schema_compare_GUI\Run-Tests.cmd
```

Coverage includes connection strings, diff filtering, one-to-many target resolution,
capped log buffers, child-process kill, temp cleanup, settings (no password persistence),
script preview helpers, Options/Connection panels, and MainForm construct/shutdown lifecycle.

---

## Memory, responsiveness, and clean exit

| Concern | How it is handled |
|---------|-------------------|
| Orphan PowerShell | `ChildProcessTracker` + `Kill(entireProcessTree)` on cancel/close |
| Temp request files | Deleted after each run; old folders purged on exit |
| SQL passwords in env | Cleared after each bridge run and on `ApplicationExit` |
| Large logs/scripts | `CappedStringBuffer` + script preview size limit |
| GDI / ImageList | Owned bitmaps disposed with the form |
| UI thread | Async compare with `BeginInvoke` log updates; busy flag blocks re-entry |
| Unhandled errors | `ThreadException` / `UnhandledException` handlers show a dialog instead of crashing silently |
| App close | Cancels compare → kills children → clears buffers → GC reclaim |

Closing the window asks to cancel an in-flight compare, then shuts down all tracked child processes so Task Manager should not keep leftover `powershell.exe` / app instances from this tool.

---

## Architecture

```text
[ Desktop WinForms UI ]
        │
        ▼
[ tools/Invoke-CompareForGui.ps1 ]   ← request/result JSON bridge
        │
        ▼
[ schema_compare/Compare-SqlSchema.ps1 ]  ← unchanged engine
        │
        ▼
   output/SchemaSync_*/  + HTML report + result JSON for the tree
```

Passwords for SQL auth are passed only via process environment variables for the bridge
run and are not saved to disk. Session settings live under `%AppData%\SqlOptima\SchemaCompare\`
(without passwords).

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| App won’t start | Install .NET 8 Desktop Runtime; run `Launch-DesktopApp.cmd` to auto-build |
| “Cannot locate schema_compare_GUI” | Keep `schema_compare_GUI` next to `schema_compare` |
| Compare fails / dbatools missing | `Install-Module dbatools -Scope CurrentUser` |
| Refresh DBs fails | Check firewall/auth; type DB names manually if needed |
| No scripts in tab | Enable **Generate sync scripts** in Options |

---

## License / credit

UI concept inspired by [OpenDBDiff](https://github.com/OpenDBDiff/OpenDBDiff).  
Compare engine: this repository’s `schema_compare` toolkit.
