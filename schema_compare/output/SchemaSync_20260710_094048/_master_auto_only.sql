/* ============================================================
 *  AUTO-ONLY RUNNER  (_master_auto_only.sql)
 *  Database : ERP_System
 *  Source   : .  (reference only — do not run scripts there)
 *  Target   : 192.168.10.200  (run all scripts here)
 *  Generated: 2026-07-10 03:56:05 UTC
 *  Auto scripts included: 4
 *
 *  WHERE TO RUN: TARGET server only (never on source).
 *  TARGET     : 192.168.10.200
 *  DATABASE   : ERP_System
 *  RUN FOLDER : D:\Mac_bak\AI_Code\sql_optima\dba_essential_scripts\schema_compare\output\SchemaSync_20260710_094048
 *
 *  WHICH FILE : _master_auto_only.sql  <-- use this for one-shot auto apply
 *  PURPOSE    : Applies all auto_ scripts in order (safe changes only).
 *               Does NOT run manual_ scripts. Use when no manual_ files exist,
 *               or after you have already executed every manual_ script.
 *
 *  PREREQUISITE: cd to the run folder so :r includes resolve (master files only).
 *
 *  --- Copy/paste: PowerShell (run from any machine that reaches TARGET SQL) ---
 *
 *  cd "D:\Mac_bak\AI_Code\sql_optima\dba_essential_scripts\schema_compare\output\SchemaSync_20260710_094048"
 *
 *  # SQL login (replace user/password):
 *  sqlcmd -S 192.168.10.200 -d ERP_System -U YourSqlLogin -P "YourPassword" -C -i ".\_master_auto_only.sql"
 *
 *  # Windows auth (if TARGET trusts your Windows account):
 *  sqlcmd -S 192.168.10.200 -d ERP_System -E -C -i ".\_master_auto_only.sql"
 *
 *  --- SSMS alternative (single .sql file, not master :r runner) ---
 *  Open the .sql file in SSMS -> connect to TARGET -> execute.
 *  For _master_*.sql, sqlcmd is required (:r includes). SSMS: enable Query -> SQLCMD Mode.
 * ============================================================ */

USE [ERP_System];
GO

:r auto_ERP_System__dbo.newtable__table_create.sql
GO

:r auto_ERP_System__dbo.testCompanies__table_create.sql
GO

:r auto_ERP_System__dbo.Companies__column_add.sql
GO

:r auto_ERP_System__dbo.Companies__index.sql
GO

