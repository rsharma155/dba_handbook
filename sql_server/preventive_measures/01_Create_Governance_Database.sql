/*
================================================================================
01_Create_Governance_Database.sql - Create Governance Tables in DBARepository
================================================================================
Purpose:    Creates governance tables in the existing DBARepository database.
            Uses dbo schema to maintain consistency with other DBA framework objects.

Version:    2.0
Author:     DBA Team
Created:    2026-06-19
Updated:    2026-06-19 - Modified to use DBARepository database
Compatible: SQL Server 2016, 2017, 2019, 2022

Usage:      Run this script first to set up the governance repository.
            Requires DBARepository database to exist (run 00_Repository/DBARepository_Create.sql first).

Notes:      - This script is idempotent (safe to run multiple times)
            - Creates governance tables in existing DBARepository database
            - Uses dbo schema for consistency with other framework objects
================================================================================
*/

USE [DBARepository];
GO

--------------------------------------------------------------------------------
-- Policy Configuration Table
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.Policy_Config', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Policy_Config] (
        [Config_ID]                     INT IDENTITY(1,1)   NOT NULL,
        [Policy_Name]                   VARCHAR(100)        NOT NULL,
        [Long_Query_Threshold_Seconds]  INT                 NOT NULL DEFAULT 10,
        [Large_DML_Row_Count]           BIGINT              NOT NULL DEFAULT 100000,
        [Action_Type]                   VARCHAR(20)         NOT NULL DEFAULT 'ALERT',
        [Monitoring_Interval_Seconds]   INT                 NOT NULL DEFAULT 5,
        [Enabled]                       BIT                 NOT NULL DEFAULT 1,
        [Created_Date]                  DATETIME2           NOT NULL DEFAULT SYSDATETIME(),
        [Modified_Date]                 DATETIME2           NULL,
        [Created_By]                    SYSNAME             NOT NULL DEFAULT SYSTEM_USER,
        CONSTRAINT [PK_Policy_Config] PRIMARY KEY CLUSTERED ([Config_ID]),
        CONSTRAINT [CK_Policy_Config_Action_Type] 
            CHECK ([Action_Type] IN ('WARN', 'LOG', 'ALERT', 'KILL', 'BLOCK'))
    );
    PRINT N'Created dbo.Policy_Config table.';
END
GO

--------------------------------------------------------------------------------
-- Insert Default Policy
--------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [dbo].[Policy_Config] WHERE [Policy_Name] = 'Production Query Protection')
BEGIN
    INSERT INTO [dbo].[Policy_Config] (
        [Policy_Name],
        [Long_Query_Threshold_Seconds],
        [Large_DML_Row_Count],
        [Action_Type],
        [Monitoring_Interval_Seconds]
    )
    VALUES (
        'Production Query Protection',
        10,
        100000,
        'ALERT',
        5
    );
    PRINT N'Inserted default Production Query Protection policy.';
END
GO

--------------------------------------------------------------------------------
-- Query History Table
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.Query_History', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Query_History] (
        [History_ID]        BIGINT IDENTITY(1,1)    NOT NULL,
        [Session_ID]        INT                     NOT NULL,
        [Login_Name]        SYSNAME                 NOT NULL,
        [Host_Name]         NVARCHAR(128)           NULL,
        [Program_Name]      NVARCHAR(128)           NULL,
        [Database_Name]     SYSNAME                 NULL,
        [Query_Text]        NVARCHAR(MAX)           NULL,
        [Duration_ms]       BIGINT                  NOT NULL,
        [CPU_Time]          BIGINT                  NOT NULL,
        [Logical_Reads]     BIGINT                  NOT NULL,
        [Writes]            BIGINT                  NOT NULL,
        [Row_Count]         BIGINT                  NULL,
        [Command_Type]      NVARCHAR(32)            NULL,
        [Captured_Time]     DATETIME2               NOT NULL DEFAULT SYSDATETIME(),
        CONSTRAINT [PK_Query_History] PRIMARY KEY CLUSTERED ([History_ID])
    );
    
    CREATE NONCLUSTERED INDEX [IX_Query_History_Captured_Time] 
        ON [dbo].[Query_History] ([Captured_Time] DESC);
    CREATE NONCLUSTERED INDEX [IX_Query_History_Duration] 
        ON [dbo].[Query_History] ([Duration_ms] DESC) 
        INCLUDE ([Login_Name], [Database_Name]);
        
    PRINT N'Created dbo.Query_History table.';
END
GO

--------------------------------------------------------------------------------
-- Alert Log Table
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.Alert_Log', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Alert_Log] (
        [Alert_ID]          BIGINT IDENTITY(1,1)    NOT NULL,
        [Alert_Type]        VARCHAR(100)            NOT NULL,
        [Severity]          VARCHAR(20)             NOT NULL DEFAULT 'INFO',
        [Session_ID]        INT                     NULL,
        [Login_Name]        SYSNAME                 NULL,
        [Host_Name]         NVARCHAR(128)           NULL,
        [Program_Name]      NVARCHAR(128)           NULL,
        [Database_Name]     SYSNAME                 NULL,
        [Message]           NVARCHAR(MAX)           NOT NULL,
        [Query_Text]        NVARCHAR(MAX)           NULL,
        [Action_Taken]      VARCHAR(50)             NULL,
        [Created_Date]      DATETIME2               NOT NULL DEFAULT SYSDATETIME(),
        [Acknowledged]      BIT                     NOT NULL DEFAULT 0,
        [Acknowledged_By]   SYSNAME                 NULL,
        [Acknowledged_Date] DATETIME2               NULL,
        CONSTRAINT [PK_Alert_Log] PRIMARY KEY CLUSTERED ([Alert_ID]),
        CONSTRAINT [CK_Alert_Log_Severity] 
            CHECK ([Severity] IN ('INFO', 'WARNING', 'CRITICAL'))
    );
    
    CREATE NONCLUSTERED INDEX [IX_Alert_Log_Created_Date] 
        ON [dbo].[Alert_Log] ([Created_Date] DESC);
    CREATE NONCLUSTERED INDEX [IX_Alert_Log_Unacknowledged] 
        ON [dbo].[Alert_Log] ([Acknowledged], [Severity], [Created_Date] DESC)
        WHERE [Acknowledged] = 0;
        
    PRINT N'Created dbo.Alert_Log table.';
END
GO

--------------------------------------------------------------------------------
-- Blocked Applications Table
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.Blocked_Applications', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Blocked_Applications] (
        [Application_Name]  VARCHAR(200)        NOT NULL,
        [Reason]            VARCHAR(500)        NOT NULL,
        [Enabled]           BIT                 NOT NULL DEFAULT 1,
        [Created_Date]      DATETIME2           NOT NULL DEFAULT SYSDATETIME(),
        [Created_By]        SYSNAME             NOT NULL DEFAULT SYSTEM_USER,
        CONSTRAINT [PK_Blocked_Applications] PRIMARY KEY CLUSTERED ([Application_Name])
    );
    
    INSERT INTO [dbo].[Blocked_Applications] ([Application_Name], [Reason])
    SELECT 'SQLCMD', 'Production direct access not allowed'
    WHERE NOT EXISTS (SELECT 1 FROM [dbo].[Blocked_Applications] WHERE [Application_Name] = 'SQLCMD');
    
    INSERT INTO [dbo].[Blocked_Applications] ([Application_Name], [Reason])
    SELECT 'sqlcmd', 'Production direct access not allowed (case variant)'
    WHERE NOT EXISTS (SELECT 1 FROM [dbo].[Blocked_Applications] WHERE [Application_Name] = 'sqlcmd');
        
    PRINT N'Created dbo.Blocked_Applications table with defaults.';
END
GO

--------------------------------------------------------------------------------
-- Blocked Users Table
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.Blocked_Users', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Blocked_Users] (
        [Login_Name]        SYSNAME             NOT NULL,
        [Reason]            VARCHAR(500)        NOT NULL,
        [Enabled]           BIT                 NOT NULL DEFAULT 1,
        [Created_Date]      DATETIME2           NOT NULL DEFAULT SYSDATETIME(),
        [Created_By]        SYSNAME             NOT NULL DEFAULT SYSTEM_USER,
        CONSTRAINT [PK_Blocked_Users] PRIMARY KEY CLUSTERED ([Login_Name])
    );
    PRINT N'Created dbo.Blocked_Users table.';
END
GO

--------------------------------------------------------------------------------
-- Audit History Table
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.Audit_History', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Audit_History] (
        [Audit_ID]          BIGINT IDENTITY(1,1)    NOT NULL,
        [Table_Name]        VARCHAR(128)            NOT NULL,
        [Action]            VARCHAR(20)             NOT NULL,
        [Key_Value]         VARCHAR(255)            NOT NULL,
        [Old_Value]         NVARCHAR(MAX)           NULL,
        [New_Value]         NVARCHAR(MAX)           NULL,
        [Changed_By]        SYSNAME                 NOT NULL DEFAULT SYSTEM_USER,
        [Changed_Date]      DATETIME2               NOT NULL DEFAULT SYSDATETIME(),
        CONSTRAINT [PK_Audit_History] PRIMARY KEY CLUSTERED ([Audit_ID])
    );
    PRINT N'Created dbo.Audit_History table.';
END
GO

--------------------------------------------------------------------------------
-- XE Session Configuration Table
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.XE_Session_Config', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[XE_Session_Config] (
        [Session_Name]      VARCHAR(128)    NOT NULL,
        [Description]       VARCHAR(500)    NULL,
        [Is_Enabled]        BIT             NOT NULL DEFAULT 1,
        [Target_Type]       VARCHAR(20)     NOT NULL DEFAULT 'ring_buffer',
        [Max_File_Size_MB]  INT             NOT NULL DEFAULT 100,
        [Max_Rollover]      INT             NOT NULL DEFAULT 5,
        [Created_Date]      DATETIME2       NOT NULL DEFAULT SYSDATETIME(),
        [Last_Modified]     DATETIME2       NULL,
        CONSTRAINT [PK_XE_Session_Config] PRIMARY KEY CLUSTERED ([Session_Name])
    );
    PRINT N'Created dbo.XE_Session_Config table.';
END
GO

--------------------------------------------------------------------------------
-- XE Events Table
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.XE_Events', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[XE_Events] (
        [Event_ID]          BIGINT IDENTITY(1,1) NOT NULL,
        [Session_Name]      VARCHAR(128)    NOT NULL,
        [Event_Name]        VARCHAR(128)    NOT NULL,
        [Timestamp]         DATETIME2       NOT NULL,
        [Duration_ms]       BIGINT          NULL,
        [CPU_Time]          BIGINT          NULL,
        [Logical_Reads]     BIGINT          NULL,
        [Writes]            BIGINT          NULL,
        [Row_Count]         BIGINT          NULL,
        [Database_Name]     SYSNAME         NULL,
        [Login_Name]        SYSNAME         NULL,
        [Host_Name]         NVARCHAR(128)   NULL,
        [Program_Name]      NVARCHAR(128)   NULL,
        [SQL_Text]          NVARCHAR(MAX)   NULL,
        [Session_ID]        INT             NULL,
        [Statement]         NVARCHAR(MAX)   NULL,
        [Raw_Data]          XML             NULL,
        [Processed]         BIT             NOT NULL DEFAULT 0,
        CONSTRAINT [PK_XE_Events] PRIMARY KEY CLUSTERED ([Event_ID])
    );
    
    CREATE NONCLUSTERED INDEX [IX_XE_Events_Timestamp] 
        ON [dbo].[XE_Events] ([Timestamp] DESC);
    CREATE NONCLUSTERED INDEX [IX_XE_Events_Unprocessed] 
        ON [dbo].[XE_Events] ([Processed], [Timestamp] DESC)
        WHERE [Processed] = 0;
        
    PRINT N'Created dbo.XE_Events table.';
END
GO

PRINT N'=====================================================';
PRINT N'Governance tables created successfully in DBARepository!';
PRINT N'=====================================================';
GO