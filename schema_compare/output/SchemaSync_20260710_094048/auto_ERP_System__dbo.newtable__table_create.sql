/* ============================================================
 *  AUTO schema change script
 *  Database : ERP_System
 *  Object   : [dbo].[newtable]
 *  Purpose  : table_create
 *  Source   : . / ERP_System
 *  Target   : 192.168.10.200 / ERP_System
 *  Generated: 2026-07-10 03:56:05 UTC
 *  Run order: 50  (apply auto_ scripts in ascending run-order)
 *
 *  Changes (1):
 *    - Create table [dbo].[newtable]
 *
 *  WHERE TO RUN: TARGET server only (never on source).
 *  TARGET     : 192.168.10.200
 *  DATABASE   : ERP_System
 *  RUN FOLDER : D:\Mac_bak\AI_Code\sql_optima\dba_essential_scripts\schema_compare\output\SchemaSync_20260710_094048
 *
 *  FILE       : auto_ERP_System__dbo.newtable__table_create.sql
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
 *  sqlcmd -S 192.168.10.200 -d ERP_System -U YourSqlLogin -P "YourPassword" -C -i ".\auto_ERP_System__dbo.newtable__table_create.sql"
 *
 *  # Windows auth (if TARGET trusts your Windows account):
 *  sqlcmd -S 192.168.10.200 -d ERP_System -E -C -i ".\auto_ERP_System__dbo.newtable__table_create.sql"
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

    -- Create table [dbo].[newtable]
    IF OBJECT_ID(N'[dbo].[newtable]', N'U') IS NULL
    BEGIN
        DECLARE @sql_create nvarchar(max) = N'';
    SET @sql_create = @sql_create + N'CREATE TABLE [dbo].[newtable](
    [CompanyID] [int] IDENTITY(1,1) NOT NULL,
    [CompanyName] [nvarchar](200) COLLATE Latin1_General_CI_AS NOT NULL,
    [LegalName] [nvarchar](200) COLLATE Latin1_General_CI_AS NULL,
    [TaxID] [nvarchar](50) COLLATE Latin1_General_CI_AS NOT NULL,
    [Address1] [nvarchar](200) COLLATE Latin1_General_CI_AS NULL,
    [Address2] [nvarchar](200) COLLATE Latin1_General_CI_AS NULL,
    [City] [nvarchar](100) COLLATE Latin1_General_CI_AS NULL,
    [State] [nvarchar](100) COLLATE Latin1_General_CI_AS NULL,
    [PostalCode] [nvarchar](20) COLLATE Latin1_General_CI_AS NULL,
    [Country] [nvarchar](100) COLLATE Latin1_General_CI_AS NULL,
    [Phone] [nvarchar](30) COLLATE Latin1_General_CI_AS NULL,
    [Email] [nvarchar](200) COLLATE Latin1_General_CI_AS NULL,
    [Website] [nvarchar](200) COLLATE Latin1_General_CI_AS NULL,
    [IsActive] [bit] NULL,
    [CreatedDate] [datetime2](7) NULL,
    [ModifiedDate] [datetime2](7) NULL
    ) ON [PRIMARY]';
        EXEC sys.sp_executesql @sql_create;
    END

    COMMIT TRANSACTION;
    PRINT 'SUCCESS: [ERP_System] [dbo].[newtable] table_create applied.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'FAILED: [ERP_System] [dbo].[newtable] table_create -> ' + ERROR_MESSAGE();
    THROW;
END CATCH
GO
