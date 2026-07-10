/* ============================================================
 *  AUTO schema change script
 *  Database : ERP_System
 *  Object   : [dbo].[Companies]
 *  Purpose  : index
 *  Source   : . / ERP_System
 *  Target   : 192.168.10.200 / ERP_System
 *  Generated: 2026-07-10 03:56:05 UTC
 *  Run order: 80  (apply auto_ scripts in ascending run-order)
 *
 *  Changes (1):
 *    - Create index [ix_companies__city]
 *
 *  WHERE TO RUN: TARGET server only (never on source).
 *  TARGET     : 192.168.10.200
 *  DATABASE   : ERP_System
 *  RUN FOLDER : D:\Mac_bak\AI_Code\sql_optima\dba_essential_scripts\schema_compare\output\SchemaSync_20260710_094048
 *
 *  FILE       : auto_ERP_System__dbo.Companies__index.sql
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
 *  sqlcmd -S 192.168.10.200 -d ERP_System -U YourSqlLogin -P "YourPassword" -C -i ".\auto_ERP_System__dbo.Companies__index.sql"
 *
 *  # Windows auth (if TARGET trusts your Windows account):
 *  sqlcmd -S 192.168.10.200 -d ERP_System -E -C -i ".\auto_ERP_System__dbo.Companies__index.sql"
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

    -- Create index [ix_companies__city]
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_companies__city' AND object_id = OBJECT_ID(N'[dbo].[Companies]'))
    CREATE NONCLUSTERED INDEX [ix_companies__city] ON [dbo].[Companies]
    (
    [City] ASC
    )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY];

    COMMIT TRANSACTION;
    PRINT 'SUCCESS: [ERP_System] [dbo].[Companies] index applied.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'FAILED: [ERP_System] [dbo].[Companies] index -> ' + ERROR_MESSAGE();
    THROW;
END CATCH
GO
