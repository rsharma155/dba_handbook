/* ============================================================
 *  MASTER MIGRATION CATALOG  (_master_migration.sql)
 *  Database : ERP_System
 *  Source   : .  (reference only — do not run scripts there)
 *  Target   : 192.168.10.200  (run all scripts here)
 *  Generated: 2026-07-10 03:56:05 UTC
 *  Auto scripts  : 4
 *  Manual scripts: 0
 *
 *  WHERE TO RUN: TARGET server only (never on source).
 *  TARGET     : 192.168.10.200
 *  DATABASE   : ERP_System
 *  RUN FOLDER : D:\Mac_bak\AI_Code\sql_optima\dba_essential_scripts\schema_compare\output\SchemaSync_20260710_094048
 *
 *  WHICH FILE : _master_migration.sql  <-- use this for guided promotion
 *  PURPOSE    : Full runbook: auto_ phases + MANUAL ACTION checkpoints.
 *               Stop at each checkpoint, run listed manual_ files, then continue.
 *               Prefer this for UAT/Prod when manual_ scripts exist.
 *
 *  PREREQUISITE: cd to the run folder so :r includes resolve (master files only).
 *
 *  --- Copy/paste: PowerShell (run from any machine that reaches TARGET SQL) ---
 *
 *  cd "D:\Mac_bak\AI_Code\sql_optima\dba_essential_scripts\schema_compare\output\SchemaSync_20260710_094048"
 *
 *  # SQL login (replace user/password):
 *  sqlcmd -S 192.168.10.200 -d ERP_System -U YourSqlLogin -P "YourPassword" -C -i ".\_master_migration.sql"
 *
 *  # Windows auth (if TARGET trusts your Windows account):
 *  sqlcmd -S 192.168.10.200 -d ERP_System -E -C -i ".\_master_migration.sql"
 *
 *  --- SSMS alternative (single .sql file, not master :r runner) ---
 *  Open the .sql file in SSMS -> connect to TARGET -> execute.
 *  For _master_*.sql, sqlcmd is required (:r includes). SSMS: enable Query -> SQLCMD Mode.
 * ============================================================ */

USE [ERP_System];
GO

/* === PHASE: 2 - Tables & Columns === */
-- auto_ERP_System__dbo.newtable__table_create.sql  ([dbo].[newtable] / table_create)
:r auto_ERP_System__dbo.newtable__table_create.sql
GO

-- auto_ERP_System__dbo.testCompanies__table_create.sql  ([dbo].[testCompanies] / table_create)
:r auto_ERP_System__dbo.testCompanies__table_create.sql
GO

-- auto_ERP_System__dbo.Companies__column_add.sql  ([dbo].[Companies] / column_add)
:r auto_ERP_System__dbo.Companies__column_add.sql
GO

/* === PHASE: 3 - Indexes & Constraints === */
-- auto_ERP_System__dbo.Companies__index.sql  ([dbo].[Companies] / index)
:r auto_ERP_System__dbo.Companies__index.sql
GO

