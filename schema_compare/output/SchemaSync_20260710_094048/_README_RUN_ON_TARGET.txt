SCHEMA SYNC — RUN ON TARGET SERVER ONLY
========================================
Target instance : 192.168.10.200
Target database : ERP_System
Source (ref)    : .
Generated (UTC) : 2026-07-10 03:56:05
Run folder      : D:\Mac_bak\AI_Code\sql_optima\dba_essential_scripts\schema_compare\output\SchemaSync_20260710_094048

WHICH FILE TO RUN ON TARGET?

  _master_auto_only.sql
    -> One-shot apply of ALL auto_ scripts (safe changes only).
    -> Use when NO manual_ scripts exist, OR manual_ scripts are already done.
    -> Best for CI / dev->uat when everything is auto-safe.

  _master_migration.sql
    -> Guided runbook with MANUAL ACTION checkpoints between phases.
    -> Use for UAT/Prod when manual_*.sql files exist (PK changes, etc.).
    -> Stop at each checkpoint, run listed manual_ files, then continue.

COPY/PASTE (PowerShell — cd to this folder first):

  cd "D:\Mac_bak\AI_Code\sql_optima\dba_essential_scripts\schema_compare\output\SchemaSync_20260710_094048"

  sqlcmd -S 192.168.10.200 -d ERP_System -U YourSqlLogin -P "YourPassword" -C -i ".\_master_auto_only.sql"

  sqlcmd -S 192.168.10.200 -d ERP_System -E -C -i ".\_master_auto_only.sql"

See _manifest.csv for run order. Never run on source.
