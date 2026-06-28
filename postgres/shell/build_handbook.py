#!/usr/bin/env python3
"""Build self-contained PostgreSQL DBA Production Handbook HTML with embedded SQL scripts."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

FOLDER_CATEGORY = {
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

WRITE_HINTS = (
    "deploy",
    "create_repository",
    "create_governance",
    "governance_schema",
    "alert_views",
    "capture_long",
    "blocking_detection",
    "statement_timeout_policy",
)

DESCRIPTION_RE = re.compile(
    r"Description:\s*\n\s*(.+?)(?:\n\s*\n|\n\s*Output:|\n\s*Usage:|\n\s*Action:|\n\s*Criticality:)",
    re.IGNORECASE | re.DOTALL,
)


def parse_description(text: str) -> str:
    match = DESCRIPTION_RE.search(text)
    if not match:
        first = ""
        for line in text.splitlines():
            line = line.strip()
            if line and not line.startswith("/*") and not line.startswith("=") and not line.startswith("--"):
                first = line
                break
        return first[:120] if first else "PostgreSQL diagnostic script"
    desc = " ".join(match.group(1).split())
    return desc[:160]


def classify_risk(rel_path: str, name: str) -> str:
    lower = (rel_path + name).lower()
    if any(h in lower for h in WRITE_HINTS):
        return "Write"
    if "preventive" in lower and "policy" in lower:
        return "Write"
    return "Read Only"


def category_for(rel_path: str) -> str:
    top = rel_path.split("/", 1)[0]
    return FOLDER_CATEGORY.get(top, "Other")


def collect_scripts(repo_root: Path) -> list[dict]:
    skip_dirs = {"shell", "output", ".git", ".vs", "__pycache__"}
    scripts: list[dict] = []

    for path in sorted(repo_root.rglob("*.sql")):
        rel = path.relative_to(repo_root).as_posix()
        if any(part in skip_dirs for part in path.parts):
            continue
        if path.name.startswith("_"):
            continue

        text = path.read_text(encoding="utf-8", errors="replace")
        name = path.name
        scripts.append(
            {
                "name": name,
                "cat": category_for(rel),
                "desc": parse_description(text),
                "risk": classify_risk(rel, name),
                "path": rel,
                "content": text,
            }
        )
    return scripts


def json_for_html_script(payload: object) -> str:
    """Serialize JSON safe to embed inside HTML (avoids breaking </script>)."""
    text = json.dumps(payload, ensure_ascii=False)
    return text.replace("</", "<\\/")


def build_script_data_js(scripts: list[dict]) -> str:
    contents = {s["path"]: s["content"] for s in scripts}
    catalog = [
        {k: s[k] for k in ("name", "cat", "desc", "risk", "path")} for s in scripts
    ]
    payload = {"contents": contents, "catalog": catalog, "count": len(scripts)}
    return json_for_html_script(payload)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build PostgreSQL DBA handbook HTML")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="postgres/ repository root",
    )
    parser.add_argument(
        "--template",
        type=Path,
        default=Path(__file__).resolve().parent / "templates" / "handbook.html",
        help="HTML template path",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output HTML file (default: <root>/output/DBA_Production_Handbook.html)",
    )
    args = parser.parse_args()

    repo_root = args.root.resolve()
    output = args.output or (repo_root / "output" / "DBA_Production_Handbook.html")
    template_path = args.template.resolve()

    if not template_path.is_file():
        print(f"Template not found: {template_path}", file=sys.stderr)
        return 1

    scripts = collect_scripts(repo_root)
    if not scripts:
        print("No SQL scripts found.", file=sys.stderr)
        return 1

    template = template_path.read_text(encoding="utf-8")
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    html = (
        template.replace("/*__SCRIPT_JSON__*/", build_script_data_js(scripts))
        .replace("__GENERATED_AT__", generated_at)
        .replace("__SCRIPT_COUNT__", str(len(scripts)))
    )

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(html, encoding="utf-8")

    print(f"Generated: {output}")
    print(f"Embedded {len(scripts)} SQL scripts from {repo_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
