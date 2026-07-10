/*
================================================================================
05_Check_Blocked_Applications.sql - Layer 2: Blocked Application Detection
================================================================================
Purpose:    Detects active user sessions whose application name matches the
            configured blocked application list and records alerts for monitoring.

Version:    2.1
Author:     DBA Team
Created:    2026-06-19
Updated:    2026-07-09 - Added governance header and report-only mode
Compatible: SQL Server 2016, 2017, 2019, 2022

Prerequisites:
            - DBARepository database and dbo.Policy_Config / dbo.Alert_Log /
              dbo.Blocked_Applications from 01_Create_Governance_Database.sql.
            - VIEW SERVER STATE permission for DMV access.

Usage:      EXEC [dbo].[sp_Check_Blocked_Applications];
            EXEC [dbo].[sp_Check_Blocked_Applications] @Report_Only = 1;
            Scheduled through the governance SQL Agent enforcement job.

Safety/Persistence:
            - Default mode inserts matching alerts into dbo.Alert_Log and should
              be deployed through the approved governance/change-control process.
            - @Report_Only = 1 is ad-hoc safe: returns current candidates only
              and does not write to dbo.Alert_Log.
            - @Auto_Kill is retained for SQL Agent/orchestrator compatibility;
              this script does not terminate sessions.
================================================================================
*/

USE [DBARepository];
GO

IF OBJECT_ID(N'dbo.sp_Check_Blocked_Applications', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_Check_Blocked_Applications];
GO

CREATE PROCEDURE [dbo].[sp_Check_Blocked_Applications]
    @Auto_Kill BIT = 0,
    @Report_Only BIT = 0,
    @Max_Report_Rows INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @Action_Type VARCHAR(20) = 'ALERT';
    DECLARE @Actions_Taken INT = 0;

    SELECT TOP 1 @Action_Type = [Action_Type]
    FROM [dbo].[Policy_Config] WHERE [Enabled] = 1;

    IF @Report_Only = 1
    BEGIN
        SELECT TOP (@Max_Report_Rows)
            'BLOCKED_APPLICATION' AS [Alert_Type],
            'WARNING' AS [Severity],
            s.[session_id] AS [Session_ID],
            s.[login_name] AS [Login_Name],
            s.[host_name] AS [Host_Name],
            s.[program_name] AS [Program_Name],
            DB_NAME(ISNULL(r.[database_id], 0)) AS [Database_Name],
            ba.[Application_Name],
            ba.[Reason],
            CASE WHEN EXISTS (
                SELECT 1 FROM [dbo].[Alert_Log] a
                WHERE a.[Session_ID] = s.[session_id]
                  AND a.[Alert_Type] = 'BLOCKED_APPLICATION'
                  AND a.[Created_Date] > DATEADD(MINUTE, -5, SYSDATETIME())
            ) THEN 1 ELSE 0 END AS [Recent_Alert_Exists],
            @Action_Type AS [Configured_Action],
            @Auto_Kill AS [Auto_Kill_Requested]
        FROM [sys].[dm_exec_sessions] s
        LEFT JOIN [sys].[dm_exec_requests] r ON s.[session_id] = r.[session_id]
        INNER JOIN [dbo].[Blocked_Applications] ba
            ON s.[program_name] COLLATE SQL_Latin1_General_CP1_CI_AS = ba.[Application_Name] COLLATE SQL_Latin1_General_CP1_CI_AS
        WHERE s.[session_id] > 50
          AND s.[session_id] <> @@SPID
          AND s.[is_user_process] = 1
          AND ba.[Enabled] = 1
        ORDER BY s.[session_id];

        RETURN;
    END

    INSERT INTO [dbo].[Alert_Log] ([Alert_Type], [Severity], [Session_ID], [Login_Name],
        [Host_Name], [Program_Name], [Database_Name], [Message], [Query_Text], [Action_Taken])
    SELECT 
        'BLOCKED_APPLICATION',
        'WARNING',
        s.[session_id],
        s.[login_name],
        s.[host_name],
        s.[program_name],
        DB_NAME(ISNULL(r.[database_id], 0)),
        N'Blocked application: ' + ba.[Application_Name] + N'. Reason: ' + ba.[Reason],
        NULL,
        @Action_Type
    FROM [sys].[dm_exec_sessions] s
    LEFT JOIN [sys].[dm_exec_requests] r ON s.[session_id] = r.[session_id]
    INNER JOIN [dbo].[Blocked_Applications] ba
        ON s.[program_name] COLLATE SQL_Latin1_General_CP1_CI_AS = ba.[Application_Name] COLLATE SQL_Latin1_General_CP1_CI_AS
    WHERE s.[session_id] > 50
      AND s.[session_id] <> @@SPID
      AND s.[is_user_process] = 1
      AND ba.[Enabled] = 1
      AND NOT EXISTS (
          SELECT 1 FROM [dbo].[Alert_Log] a
          WHERE a.[Session_ID] = s.[session_id]
            AND a.[Alert_Type] = 'BLOCKED_APPLICATION'
            AND a.[Created_Date] > DATEADD(MINUTE, -5, SYSDATETIME())
      );

    SET @Actions_Taken = @@ROWCOUNT;

    SELECT @Actions_Taken AS [Alerts_Generated],
           @Auto_Kill AS [Auto_Kill_Requested],
           CAST(0 AS BIT) AS [Sessions_Killed];
END
GO

PRINT N'Created dbo.sp_Check_Blocked_Applications procedure.';
GO