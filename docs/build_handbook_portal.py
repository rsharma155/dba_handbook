#!/usr/bin/env python3
"""Build the website-ready DBA handbook portal (repo-root index.html).

Scans the repository for browsable files, converts README.md into HTML,
and writes a self-contained portal you can open locally or embed on a site.

Usage (from repo root):
    python docs/build_handbook_portal.py
    python docs/build_handbook_portal.py --github-repo rsharma155/dba_handbook --github-branch main
"""

from __future__ import annotations

import argparse
import html
import json
import re
from datetime import datetime, timezone
from pathlib import Path

SKIP_DIR_NAMES = {
    ".git",
    ".vs",
    ".idea",
    "__pycache__",
    "bin",
    "obj",
    "node_modules",
    "adhoc",
}

SKIP_PATH_PARTS = {
    "unified_console/dist",
    "sql_server_assessment_tool/ps_report_collector/output",
    "sql_server/SQL_Server_Assesment_Report/output",
}

SKIP_SUFFIXES = {
    ".dll",
    ".exe",
    ".pdb",
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".ico",
    ".zip",
    ".jar",
    ".dylib",
    ".so",
    ".class",
    ".dat",
    ".cache",
}

TEXT_SUFFIXES = {
    ".sql",
    ".md",
    ".ps1",
    ".sh",
    ".cmd",
    ".bat",
    ".py",
    ".json",
    ".yml",
    ".yaml",
    ".txt",
    ".html",
    ".css",
    ".js",
    ".xml",
    ".cs",
    ".go",
    ".csv",
}

MAX_PREVIEW_BYTES = 350_000

FOLDER_BLURB = {
    "sql_server": "SQL Server production handbook: layered T-SQL diagnostics, framework procedures, PowerShell reports, migration playbooks.",
    "postgres": "PostgreSQL production handbook: layered SQL diagnostics, dba schema framework, HTML handbook generator.",
    "sql_server_assessment_tool": "Phase-1 architectural assessment collectors (detailed + minimal) with HTML/Excel output.",
    "prod_stats_report": "Production health, missing-index, and duplicate-index reporting scripts.",
    "sql_server/00_Framework": "Deploy-once functions and procedures (HealthCheck, waits, indexes, security, backups).",
    "sql_server/00_Repository": "DBARepository database, persistence tables, assessment history.",
    "sql_server/powershell": "HTML assessment reports and DBA handbook generator.",
    "sql_server/preventive_measures": "Query governance: Extended Events, policies, alerts, Agent jobs.",
    "sql_server/docs": "Requirements, HADR/install checklists, migration plans, toolkit comparison.",
    "sql_server/Prod_Migration": "Cutover and post-upgrade validation playbooks.",
    "sql_server/Migration_2016_to_2022": "Scripted 2016→2022 migration package.",
    "postgres/00_Framework": "dba.* functions: health check, sessions, waits, indexes, security, backups.",
    "postgres/shell": "Generate the offline PostgreSQL DBA_Production_Handbook.html.",
    "docs": "This portal builder and shared documentation.",
}


def should_skip(rel: str) -> bool:
    parts = rel.replace("\\", "/").split("/")
    if any(p in SKIP_DIR_NAMES for p in parts):
        return True
    posix = "/".join(parts)
    return any(posix.startswith(prefix) for prefix in SKIP_PATH_PARTS)


def file_kind(path: Path) -> str:
    suffix = path.suffix.lower()
    mapping = {
        ".sql": "SQL",
        ".md": "Markdown",
        ".ps1": "PowerShell",
        ".sh": "Shell",
        ".cmd": "Batch",
        ".bat": "Batch",
        ".py": "Python",
        ".json": "JSON",
        ".html": "HTML",
        ".js": "JavaScript",
        ".css": "CSS",
        ".cs": "C#",
        ".yml": "YAML",
        ".yaml": "YAML",
        ".txt": "Text",
    }
    return mapping.get(suffix, suffix.lstrip(".").upper() or "File")


def extract_blurb(text: str) -> str:
    desc = re.search(
        r"(?im)^\s*(?:--\s*)?Description:\s*(.+)$",
        text,
    )
    if desc:
        return " ".join(desc.group(1).split())[:180]
    for line in text.splitlines():
        stripped = line.strip().lstrip("-").lstrip("*").strip()
        if stripped and not stripped.startswith("==") and not stripped.startswith("/*"):
            if stripped.lower() in {"synopsis", "description"}:
                continue
            return stripped[:180]
    return ""


def collect_files(root: Path) -> list[dict]:
    files: list[dict] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if should_skip(rel):
            continue
        if path.suffix.lower() in SKIP_SUFFIXES:
            continue
        if path.name.startswith(".") and path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        try:
            size = path.stat().st_size
        except OSError:
            continue
        kind = file_kind(path)
        blurb = ""
        if path.suffix.lower() in TEXT_SUFFIXES and size <= MAX_PREVIEW_BYTES:
            try:
                sample = path.read_text(encoding="utf-8", errors="replace")[:4000]
                blurb = extract_blurb(sample)
            except OSError:
                blurb = ""
        files.append(
            {
                "path": rel,
                "name": path.name,
                "dir": str(Path(rel).parent).replace("\\", "/") if Path(rel).parent.as_posix() != "." else "",
                "size": size,
                "kind": kind,
                "blurb": blurb,
                "text": path.suffix.lower() in TEXT_SUFFIXES,
            }
        )
    return files


def md_inline(text: str) -> str:
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def markdown_to_html(source: str) -> str:
    lines = source.replace("\r\n", "\n").split("\n")
    out: list[str] = []
    i = 0
    in_code = False
    code_lang = ""
    code_buf: list[str] = []
    in_ul = False
    in_ol = False
    in_table = False
    table_rows: list[list[str]] = []

    def close_lists() -> None:
        nonlocal in_ul, in_ol
        if in_ul:
            out.append("</ul>")
            in_ul = False
        if in_ol:
            out.append("</ol>")
            in_ol = False

    def flush_table() -> None:
        nonlocal in_table, table_rows
        if not table_rows:
            in_table = False
            return
        header = table_rows[0]
        body = table_rows[2:] if len(table_rows) > 1 else []
        out.append("<div class='table-wrap'><table>")
        out.append("<thead><tr>" + "".join(f"<th>{md_inline(c.strip())}</th>" for c in header) + "</tr></thead>")
        out.append("<tbody>")
        for row in body:
            cells = row + [""] * (len(header) - len(row))
            out.append("<tr>" + "".join(f"<td>{md_inline(c.strip())}</td>" for c in cells[: len(header)]) + "</tr>")
        out.append("</tbody></table></div>")
        table_rows = []
        in_table = False

    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            close_lists()
            flush_table()
            if not in_code:
                in_code = True
                code_lang = line[3:].strip()
                code_buf = []
            else:
                out.append(
                    f"<pre class='code-block' data-lang='{html.escape(code_lang)}'><code>"
                    + html.escape("\n".join(code_buf))
                    + "</code></pre>"
                )
                in_code = False
            i += 1
            continue
        if in_code:
            code_buf.append(line)
            i += 1
            continue

        if re.match(r"^\s*\|.+\|\s*$", line) and "---" not in line[:8]:
            close_lists()
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not in_table:
                in_table = True
                table_rows = [cells]
            else:
                table_rows.append(cells)
            i += 1
            continue
        if in_table and re.match(r"^\s*\|?\s*:?-{3,}", line):
            table_rows.append([])
            i += 1
            continue
        if in_table:
            flush_table()

        if not line.strip():
            close_lists()
            i += 1
            continue
        if line.startswith("# "):
            close_lists()
            out.append(f"<h1>{md_inline(line[2:])}</h1>")
        elif line.startswith("## "):
            close_lists()
            out.append(f"<h2>{md_inline(line[3:])}</h2>")
        elif line.startswith("### "):
            close_lists()
            out.append(f"<h3>{md_inline(line[4:])}</h3>")
        elif line.startswith("> "):
            close_lists()
            out.append(f"<blockquote>{md_inline(line[2:])}</blockquote>")
        elif re.match(r"^\s*[-*]\s+", line):
            if in_ol:
                out.append("</ol>")
                in_ol = False
            if not in_ul:
                out.append("<ul>")
                in_ul = True
            out.append(f"<li>{md_inline(re.sub(r'^\s*[-*]\s+', '', line))}</li>")
        elif re.match(r"^\s*\d+\.\s+", line):
            if in_ul:
                out.append("</ul>")
                in_ul = False
            if not in_ol:
                out.append("<ol>")
                in_ol = True
            out.append(f"<li>{md_inline(re.sub(r'^\s*\d+\.\s+', '', line))}</li>")
        else:
            close_lists()
            out.append(f"<p>{md_inline(line)}</p>")
        i += 1

    close_lists()
    flush_table()
    if in_code:
        out.append("<pre class='code-block'><code>" + html.escape("\n".join(code_buf)) + "</code></pre>")
    return "\n".join(out)


def load_template(root: Path) -> str:
    path = root / "docs" / "templates" / "handbook_portal.html"
    return path.read_text(encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the DBA handbook portal HTML.")
    parser.add_argument("--github-repo", default="rsharma155/dba_handbook")
    parser.add_argument("--github-branch", default="main")
    parser.add_argument("--output", default="index.html")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    files = collect_files(root)
    folders = sorted({f["dir"] for f in files if f["dir"]})
    readme = (root / "README.md").read_text(encoding="utf-8")
    handbook_html = markdown_to_html(readme)
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    html_out = load_template(root)
    html_out = html_out.replace("__GENERATED_AT__", generated)
    html_out = html_out.replace("__FILE_COUNT__", str(len(files)))
    html_out = html_out.replace("__FOLDER_COUNT__", str(len(folders)))
    html_out = html_out.replace("__GITHUB_REPO__", html.escape(args.github_repo))
    html_out = html_out.replace("__GITHUB_BRANCH__", html.escape(args.github_branch))
    html_out = html_out.replace("__HANDBOOK_HTML__", handbook_html)
    html_out = html_out.replace(
        "__CATALOG_JSON__",
        json.dumps(files, ensure_ascii=False).replace("<", "\\u003c"),
    )
    html_out = html_out.replace(
        "__FOLDER_BLURB_JSON__",
        json.dumps(FOLDER_BLURB, ensure_ascii=False).replace("<", "\\u003c"),
    )

    output = root / args.output
    output.write_text(html_out, encoding="utf-8")
    print(f"Wrote {output} ({len(files)} files, {len(folders)} folders, {output.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
