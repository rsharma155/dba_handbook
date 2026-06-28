#!/usr/bin/env python3
"""Embed SQL Server + PostgreSQL scripts into DBA_Console.html."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
UI_DIR = Path(__file__).resolve().parent.parent / "ui"

SKIP_PARTS = {
    "output",
    "powershell",
    "docs",
    "shell",
    ".git",
    "__pycache__",
}

PG_FOLDER_CATEGORY = {
    "00_Framework": "Framework",
    "00_Repository": "Framework",
    "01_Server_OS": "Server_OS",
    "02_Instance_Config": "Instance_Config",
    "03_Storage": "Storage",
    "04_Performance_Diagnostics": "Performance",
    "05_Index_Statistics": "Index_Statistics",
    "06_HA_DR": "HA_DR",
    "07_Security": "Security",
    "08_Advanced": "Advanced",
    "09_Maintenance": "Maintenance",
    "10_Capacity_Planning": "Capacity",
    "11_Query_Analysis": "Query_Analysis",
    "12_Extensions": "Extensions",
    "13_Connection_Pooling": "Connection_Pooling",
    "14_Baselines": "Baselines",
    "preventive_measures": "Preventive",
}

MSSQL_FOLDER_CATEGORY = {
    "00_Framework": "Framework",
    "00_Repository": "Framework",
    "01_Server_OS": "Server_OS",
    "02_Instance_Config": "Instance_Config",
    "03_Storage": "Storage",
    "04_Performance_Diagnostics": "Performance",
    "05_Index_Statistics": "Index_Statistics",
    "06_HA_DR": "HA_DR",
    "07_Security": "Security",
    "08_Advanced": "Advanced",
    "09_Maintenance": "Maintenance",
    "10_Capacity_Planning": "Capacity",
    "11_Query_Analysis": "Query_Analysis",
    "preventive_measures": "Preventive",
}

WRITE_HINTS = (
    "deploy",
    "create_repository",
    "dbarepository_create",
    "dbarepository_deploy",
    "dbarepository_persistence",
    "create_governance",
    "governance",
    "install_framework",
    "setup_",
    "enforce_",
    "alert_",
    "dashboard_views",
    "agent_jobs",
    "resource_governor",
    "extended_events",
    "capture_running",
    "capture_long",
    "blocking_detection",
    "statement_timeout_policy",
    "alert_views",
    "sp_dba_",
    "sp_dba",
    "fn_dba_",
    "fn_dba",
)

DESCRIPTION_RE = re.compile(
    r"(?:Description:|Purpose:)\s*\n\s*(.+?)(?:\n\s*\n|\n\s*(?:Output|Usage|Action|Provides|Importance|Criticality):)",
    re.IGNORECASE | re.DOTALL,
)

DEFAULT_DB = {
    ("postgres", "00_Framework"): "dba_repository",
    ("postgres", "00_Repository"): "dba_repository",
    ("postgres", "preventive_measures"): "dba_repository",
    ("mssql", "00_Framework"): "DBARepository",
    ("mssql", "00_Repository"): "DBARepository",
    ("mssql", "preventive_measures"): "DBARepository",
}


def parse_description(text: str) -> str:
    match = DESCRIPTION_RE.search(text)
    if match:
        return " ".join(match.group(1).split())[:160]
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith(("/*", "=", "--")):
            return line[:120]
    return "Diagnostic script"


def classify_risk(rel_path: str, name: str) -> str:
    lower = (rel_path + name).lower()
    if any(h in lower for h in WRITE_HINTS):
        return "Write"
    return "Read Only"


def category_for(engine: str, rel_path: str) -> str:
    top = rel_path.split("/", 2)[1] if "/" in rel_path else rel_path
    if engine == "postgres":
        return PG_FOLDER_CATEGORY.get(top, "Other")
    return MSSQL_FOLDER_CATEGORY.get(top, "Other")


def suggest_database(engine: str, rel_path: str) -> str | None:
    parts = rel_path.split("/")
    if len(parts) < 2:
        return None
    folder = parts[1]
    return DEFAULT_DB.get((engine, folder))


def should_skip(path: Path) -> bool:
    if any(part in SKIP_PARTS for part in path.parts):
        return True
    if path.name.startswith("_"):
        return True
    return False


def collect_engine_scripts(engine: str, root: Path) -> list[dict]:
    scripts: list[dict] = []
    prefix = root.name

    for path in sorted(root.rglob("*.sql")):
        if should_skip(path):
            continue
        rel = f"{prefix}/{path.relative_to(root).as_posix()}"
        text = path.read_text(encoding="utf-8", errors="replace")
        name = path.name
        scripts.append(
            {
                "engine": engine,
                "name": name,
                "cat": category_for(engine, rel),
                "desc": parse_description(text),
                "risk": classify_risk(rel, name),
                "path": rel,
                "database": suggest_database(engine, rel),
                "content": text,
            }
        )
    return scripts


def json_for_html(payload: object) -> str:
    text = json.dumps(payload, ensure_ascii=False)
    return text.replace("</", "<\\/")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--template",
        type=Path,
        default=UI_DIR / "DBA_Console.template.html",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=UI_DIR / "DBA_Console.html",
    )
    args = parser.parse_args()

    if not args.template.is_file():
        print(f"Template not found: {args.template}", file=sys.stderr)
        return 1

    pg_root = REPO_ROOT / "postgres"
    mssql_root = REPO_ROOT / "sql_server"
    scripts = collect_engine_scripts("postgres", pg_root) + collect_engine_scripts(
        "mssql", mssql_root
    )
    if not scripts:
        print("No scripts found.", file=sys.stderr)
        return 1

    contents = {s["path"]: s["content"] for s in scripts}
    catalog = [
        {k: s[k] for k in ("engine", "name", "cat", "desc", "risk", "path", "database")}
        for s in scripts
    ]
    payload = {
        "contents": contents,
        "catalog": catalog,
        "count": len(scripts),
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "postgresCount": sum(1 for s in scripts if s["engine"] == "postgres"),
        "mssqlCount": sum(1 for s in scripts if s["engine"] == "mssql"),
    }

    html = args.template.read_text(encoding="utf-8")
    html = html.replace("/*__SCRIPT_JSON__*/", json_for_html(payload))
    html = html.replace("__SCRIPT_COUNT__", str(len(scripts)))
    html = html.replace("__GENERATED_AT__", payload["generatedAt"])

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(html, encoding="utf-8")
    print(f"Generated {args.output} ({len(scripts)} scripts)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
