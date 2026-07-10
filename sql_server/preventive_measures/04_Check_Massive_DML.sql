/*
================================================================================
04_Check_Massive_DML.sql - Layer 2: Massive DML Detection
================================================================================
Purpose:    Detects active user INSERT/UPDATE/DELETE/MERGE operations whose row
            counts exceed the configured governance threshold and records alerts.

Version:    2.1
Author:     DBA Team
Created:    2026-06-19
Updated:    2026-07-09 - Added governance header, report-only mode, and
                         orchestrator-compatible parameters
Compatible: SQL Server 2016, 2017, 2019, 2022

Prerequisites:
            - DBARepository database and dbo.Policy_Config / dbo.Alert_Log from
              01_Create_Governance_Database.sql.
            - VIEW SERVER STATE permission for DMV access.

Usage:      EXEC [dbo].[sp_Check_Massive_DML];
            EXEC [dbo].[sp_Check_Massive_DML] @Report_Only = 1;
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

IF OBJECT_ID(N'dbo.sp_Check_Massive_DML', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_Check_Massive_DML];
GO

CREATE PROCEDURE [dbo].[sp_Check_Massive_DML]
    @Auto_Kill BIT = 0,
    @Process_XE_Events BIT = 1,
    @Check_Live_DMV BIT = 1,
    @Report_Only BIT = 0,
    @Max_Report_Rows INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @Large_DML_Row_Count BIGINT = 100000;
    DECLARE @Action_Type VARCHAR(20) = 'ALERT';
    DECLARE @Actions_Taken INT = 0;

    SELECT TOP 1 @Large_DML_Row_Count = [Large_DML_Row_Count], @Action_Type = [Action_Type]
    FROM [dbo].[Policy_Config] WHERE [Enabled] = 1;

    IF @Check_Live_DMV = 0
    BEGIN
        SELECT 0 AS [Alerts_Generated],
               @Large_DML_Row_Count AS [Threshold],
               CAST(0 AS BIT) AS [Live_DMV_Checked],
               @Report_Only AS [Report_Only];
        RETURN;
    END

    IF @Report_Only = 1
    BEGIN
        SELECT TOP (@Max_Report_Rows)
            'MASSIVE_DML' AS [Alert_Type],
            CASE WHEN r.[row_count] > (@Large_DML_Row_Count * 10) THEN 'CRITICAL'
                 WHEN r.[row_count] > (@Large_DML_Row_Count * 5) THEN 'WARNING' ELSE 'INFO' END AS [Severity],
            r.[session_id] AS [Session_ID],
            s.[login_name] AS [Login_Name],
            s.[host_name] AS [Host_Name],
            s.[program_name] AS [Program_Name],
            DB_NAME(r.[database_id]) AS [Database_Name],
            r.[command] AS [Command],
            r.[row_count] AS [Row_Count],
            @Large_DML_Row_Count AS [Threshold],
            SUBSTRING(t.[text], (r.[statement_start_offset] / 2) + 1,
                ((CASE r.[statement_end_offset] WHEN -1 THEN DATALENGTH(t.[text]) ELSE r.[statement_end_offset] END - r.[statement_start_offset]) / 2) + 1) AS [Query_Text],
            CASE WHEN EXISTS (
                SELECT 1 FROM [dbo].[Alert_Log] a
                WHERE a.[Session_ID] = r.[session_id]
                  AND a.[Alert_Type] = 'MASSIVE_DML'
                  AND a.[Created_Date] > DATEADD(MINUTE, -5, SYSDATETIME())
            ) THEN 1 ELSE 0 END AS [Recent_Alert_Exists],
            @Action_Type AS [Configured_Action],
            @Auto_Kill AS [Auto_Kill_Requested],
            @Process_XE_Events AS [Process_XE_Events_Requested]
        FROM [sys].[dm_exec_requests] r
        INNER JOIN [sys].[dm_exec_sessions] s ON r.[session_id] = s.[session_id]
        OUTER APPLY [sys].[dm_exec_sql_text](r.[sql_handle]) t
        WHERE r.[session_id] > 50
          AND r.[session_id] <> @@SPID
          AND s.[is_user_process] = 1
          AND r.[command] IN ('INSERT', 'UPDATE', 'DELETE', 'MERGE')
          AND r.[row_count] > @Large_DML_Row_Count
        ORDER BY r.[row_count] DESC;

        RETURN;
    END

    INSERT INTO [dbo].[Alert_Log] ([Alert_Type], [Severity], [Session_ID], [Login_Name],
        [Host_Name], [Program_Name], [Database_Name], [Message], [Query_Text], [Action_Taken])
    SELECT 
        'MASSIVE_DML',
        CASE WHEN r.[row_count] > (@Large_DML_Row_Count * 10) THEN 'CRITICAL'
             WHEN r.[row_count] > (@Large_DML_Row_Count * 5) THEN 'WARNING' ELSE 'INFO' END,
        r.[session_id],
        s.[login_name],
        s.[host_name],
        s.[program_name],
        DB_NAME(r.[database_id]),
        r.[command] + N' affected ' + CAST(r.[row_count] AS VARCHAR(20)) + N' rows',
        SUBSTRING(t.[text], (r.[statement_start_offset] / 2) + 1,
            ((CASE r.[statement_end_offset] WHEN -1 THEN DATALENGTH(t.[text]) ELSE r.[statement_end_offset] END - r.[statement_start_offset]) / 2) + 1),
        @Action_Type
    FROM [sys].[dm_exec_requests] r
    INNER JOIN [sys].[dm_exec_sessions] s ON r.[session_id] = s.[session_id]
    OUTER APPLY [sys].[dm_exec_sql_text](r.[sql_handle]) t
    WHERE r.[session_id] > 50
      AND r.[session_id] <> @@SPID
      AND s.[is_user_process] = 1
      AND r.[command] IN ('INSERT', 'UPDATE', 'DELETE', 'MERGE')
      AND r.[row_count] > @Large_DML_Row_Count
      AND NOT EXISTS (
          SELECT 1 FROM [dbo].[Alert_Log] a
          WHERE a.[Session_ID] = r.[session_id]
            AND a.[Alert_Type] = 'MASSIVE_DML'
            AND a.[Created_Date] > DATEADD(MINUTE, -5, SYSDATETIME())
      );

    SET @Actions_Taken = @@ROWCOUNT;

    SELECT @Actions_Taken AS [Alerts_Generated],
           @Large_DML_Row_Count AS [Threshold],
           @Auto_Kill AS [Auto_Kill_Requested],
           @Process_XE_Events AS [Process_XE_Events_Requested],
           CAST(0 AS BIT) AS [Sessions_Killed];
END
GO

PRINT N'Created dbo.sp_Check_Massive_DML procedure.';
GO