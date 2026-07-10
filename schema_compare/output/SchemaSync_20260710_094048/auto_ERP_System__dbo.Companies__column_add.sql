/* ============================================================
 *  AUTO schema change script
 *  Database : ERP_System
 *  Object   : [dbo].[Companies]
 *  Purpose  : column_add
 *  Source   : . / ERP_System
 *  Target   : 192.168.10.200 / ERP_System
 *  Generated: 2026-07-10 03:56:05 UTC
 *  Run order: 60  (apply auto_ scripts in ascending run-order)
 *
 *  Changes (1):
 *    - Add column [newcol] [int]
 *
 *  WHERE TO RUN: TARGET server only (never on source).
 *  TARGET     : 192.168.10.200
 *  DATABASE   : ERP_System
 *  RUN FOLDER : D:\Mac_bak\AI_Code\sql_optima\dba_essential_scripts\schema_compare\output\SchemaSync_20260710_094048
 *
 *  FILE       : auto_ERP_System__dbo.Companies__column_add.sql
 *  PURPOSE    : Single object/purpose change. Run after lower run-order scripts.
 *               Or use _master_auto_only.sql / _master_migration.sql instead.
 *
 *  PREREQUISITE: cd to the run folder so :r includes resolve (master files only).
 *
 *  --- Copy/paste: PowerShell (run from any machine that reaches TARGET SQL) ---
 *
 *  cd "D:\Mac_bak\AI_Code\sql_optima\dba_essential_scripts\schema_compare\output\SchemaSync_20260710_094048"
 *
 *  # SQL login (replace user/password):
 *  sqlcmd -S 192.168.10.200 -d ERP_System -U YourSqlLogin -P "YourPassword" -C -i ".\auto_ERP_System__dbo.Companies__column_add.sql"
 *
 *  # Windows auth (if TARGET trusts your Windows account):
 *  sqlcmd -S 192.168.10.200 -d ERP_System -E -C -i ".\auto_ERP_System__dbo.Companies__column_add.sql"
 *
 *  --- SSMS alternative (single .sql file, not master :r runner) ---
 *  Open the .sql file in SSMS -> connect to TARGET -> execute.
 *  For _master_*.sql, sqlcmd is required (:r includes). SSMS: enable Query -> SQLCMD Mode.
 * ============================================================ */

USE [ERP_System];
GO

SET XACT_ABORT ON;
SET NOCOUNT ON;
BEGIN TRY
    BEGIN TRANSACTION;

    -- Add column [newcol] [int]
    IF COL_LENGTH(N'[dbo].[Companies]', N'newcol') IS NULL
        ALTER TABLE [dbo].[Companies] ADD [newcol] [int] NULL;

    COMMIT TRANSACTION;
    PRINT 'SUCCESS: [ERP_System] [dbo].[Companies] column_add applied.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'FAILED: [ERP_System] [dbo].[Companies] column_add -> ' + ERROR_MESSAGE();
    THROW;
END CATCH
GO
