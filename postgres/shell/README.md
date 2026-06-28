# PostgreSQL Handbook Generator (Linux / macOS)

Generates a self-contained **PostgreSQL DBA Production Handbook** HTML file with all SQL scripts embedded for offline use.

## Requirements

- `bash` 4+
- `python3` (stdlib only — no pip packages)

## Quick Start

```bash
cd postgres/shell
./generate-dba-handbook.sh
```

Output: `postgres/output/DBA_Production_Handbook.html`

Custom output path:

```bash
./generate-dba-handbook.sh /tmp/pg-dba-handbook.html
```

Open in a browser:

```bash
xdg-open ../output/DBA_Production_Handbook.html    # Linux
open ../output/DBA_Production_Handbook.html      # macOS
```

**Important:** Open `postgres/output/DBA_Production_Handbook.html` (the generated file). Do **not** open `postgres/shell/templates/handbook.html` directly — that file is a build template without embedded scripts. If you open the template by mistake, you will see a yellow banner and an empty Script Explorer (no `scriptCatalog` data).

If your IDE preview shows a `file://` frame security warning, open the generated HTML in a normal browser tab instead (`open` / `xdg-open` above). Icons load from a CDN; use network access or ignore missing icons when fully offline.

## What It Generates

- 14 operational playbook sections with checklists (localStorage persistence)
- Script Explorer with all repository `.sql` files embedded
- Click-to-view SQL source with syntax highlighting and copy
- Global search (Ctrl+K)
- Dark / light theme toggle
- Junior / Senior DBA mode (hides `senior-only` items in Junior mode)
- Print / PDF via browser print
- Incident summary export

## Files

| File | Purpose |
|------|---------|
| `generate-dba-handbook.sh` | Entry point — calls Python builder |
| `build_handbook.py` | Scans SQL files, embeds content, writes HTML |
| `templates/handbook.html` | HTML/CSS/JS template |

## Regenerating After Script Changes

Re-run the generator whenever you add or modify scripts under `postgres/`:

```bash
./generate-dba-handbook.sh
```

The handbook auto-discovers all `*.sql` files (excluding `shell/` and `output/`).
