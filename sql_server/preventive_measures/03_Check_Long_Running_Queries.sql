/*
================================================================================
03_Check_Long_Running_Queries.sql - Layer 2: Long-Running Query Detection
================================================================================
Purpose:    Detects currently running user queries that exceed the configured
            governance duration threshold and records alerts for monitoring.

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

Usage:      EXEC [dbo].[sp_Check_Long_Running_Queries];
            EXEC [dbo].[sp_Check_Long_Running_Queries] @Report_Only = 1;
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

IF OBJECT_ID(N'dbo.sp_Check_Long_Running_Queries', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_Check_Long_Running_Queries];
GO

CREATE PROCEDURE [dbo].[sp_Check_Long_Running_Queries]
    @Auto_Kill BIT = 0,
    @Process_XE_Events BIT = 1,
    @Check_Live_DMV BIT = 1,
    @Report_Only BIT = 0,
    @Max_Report_Rows INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @Threshold_Seconds INT = 10;
    DECLARE @Action_Type VARCHAR(20) = 'ALERT';
    DECLARE @Actions_Taken INT = 0;

    SELECT TOP 1
        @Threshold_Seconds = [Long_Query_Threshold_Seconds],
        @Action_Type = [Action_Type]
    FROM [dbo].[Policy_Config]
    WHERE [Enabled] = 1;

    IF @Check_Live_DMV = 0
    BEGIN
        SELECT 0 AS [Alerts_Generated],
               @Threshold_Seconds AS [Threshold_Seconds],
               CAST(0 AS BIT) AS [Live_DMV_Checked],
               @Report_Only AS [Report_Only];
        RETURN;
    END

    IF @Report_Only = 1
    BEGIN
        SELECT TOP (@Max_Report_Rows)
            'LONG_RUNNING_QUERY' AS [Alert_Type],
            CASE WHEN r.[total_elapsed_time] > (@Threshold_Seconds * 3000) THEN 'CRITICAL'
                 WHEN r.[total_elapsed_time] > (@Threshold_Seconds * 2000) THEN 'WARNING' ELSE 'INFO' END AS [Severity],
            r.[session_id] AS [Session_ID],
            s.[login_name] AS [Login_Name],
            s.[host_name] AS [Host_Name],
            s.[program_name] AS [Program_Name],
            DB_NAME(r.[database_id]) AS [Database_Name],
            r.[total_elapsed_time] / 1000 AS [Duration_Seconds],
            @Threshold_Seconds AS [Threshold_Seconds],
            SUBSTRING(t.[text], (r.[statement_start_offset] / 2) + 1,
                ((CASE r.[statement_end_offset] WHEN -1 THEN DATALENGTH(t.[text]) ELSE r.[statement_end_offset] END - r.[statement_start_offset]) / 2) + 1) AS [Query_Text],
            CASE WHEN EXISTS (
                SELECT 1 FROM [dbo].[Alert_Log] a
                WHERE a.[Session_ID] = r.[session_id]
                  AND a.[Alert_Type] = 'LONG_RUNNING_QUERY'
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
          AND r.[total_elapsed_time] > (@Threshold_Seconds * 1000)
          AND r.[status] <> 'sleeping'
        ORDER BY r.[total_elapsed_time] DESC;

        RETURN;
    END

    INSERT INTO [dbo].[Alert_Log] ([Alert_Type], [Severity], [Session_ID], [Login_Name],
        [Host_Name], [Program_Name], [Database_Name], [Message], [Query_Text], [Action_Taken])
    SELECT 
        'LONG_RUNNING_QUERY',
        CASE WHEN r.[total_elapsed_time] > (@Threshold_Seconds * 3000) THEN 'CRITICAL'
             WHEN r.[total_elapsed_time] > (@Threshold_Seconds * 2000) THEN 'WARNING' ELSE 'INFO' END,
        r.[session_id],
        s.[login_name],
        s.[host_name],
        s.[program_name],
        DB_NAME(r.[database_id]),
        N'Query running for ' + CAST(r.[total_elapsed_time] / 1000 AS VARCHAR(20)) + N' seconds',
        SUBSTRING(t.[text], (r.[statement_start_offset] / 2) + 1,
            ((CASE r.[statement_end_offset] WHEN -1 THEN DATALENGTH(t.[text]) ELSE r.[statement_end_offset] END - r.[statement_start_offset]) / 2) + 1),
        @Action_Type
    FROM [sys].[dm_exec_requests] r
    INNER JOIN [sys].[dm_exec_sessions] s ON r.[session_id] = s.[session_id]
    OUTER APPLY [sys].[dm_exec_sql_text](r.[sql_handle]) t
    WHERE r.[session_id] > 50
      AND r.[session_id] <> @@SPID
      AND s.[is_user_process] = 1
      AND r.[total_elapsed_time] > (@Threshold_Seconds * 1000)
      AND r.[status] <> 'sleeping'
      AND NOT EXISTS (
          SELECT 1 FROM [dbo].[Alert_Log] a
          WHERE a.[Session_ID] = r.[session_id]
            AND a.[Alert_Type] = 'LONG_RUNNING_QUERY'
            AND a.[Created_Date] > DATEADD(MINUTE, -5, SYSDATETIME())
      );

    SET @Actions_Taken = @@ROWCOUNT;

    SELECT @Actions_Taken AS [Alerts_Generated],
           @Threshold_Seconds AS [Threshold_Seconds],
           @Auto_Kill AS [Auto_Kill_Requested],
           @Process_XE_Events AS [Process_XE_Events_Requested],
           CAST(0 AS BIT) AS [Sessions_Killed];
END
GO

PRINT N'Created dbo.sp_Check_Long_Running_Queries procedure.';
GO