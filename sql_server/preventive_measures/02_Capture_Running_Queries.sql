/*
================================================================================
02_Capture_Running_Queries.sql - Layer 2: DMV Snapshot Capture
================================================================================
Purpose:    LIGHTWEIGHT DMV CAPTURE - Supplements Extended Events (Layer 1).
            XE captures events in real-time; this procedure captures point-in-time
            snapshots for trending and historical analysis.

Version:    2.1
Author:     Ravi Sharma
Created:    2026-06-19
Updated:    2026-06-19 - Modified to use DBARepository database
            2026-07-09 - Added report-only mode and persistence governance notes
Compatible: SQL Server 2016, 2017, 2019, 2022

Usage:      EXEC [dbo].[sp_Capture_Running_Queries];
            EXEC [dbo].[sp_Capture_Running_Queries] @Report_Only = 1;
            Scheduled via SQL Agent job every 60 seconds.

Prerequisites:
            - DBARepository database and dbo.Query_History from 01_Create_Governance_Database.sql.
            - VIEW SERVER STATE permission for DMV access.

Notes:      - Lightweight query (runs in < 100ms on most systems)
            - Captures CURRENT state, not historical events
            - Supplements XE data for trending analysis

Safety/Persistence:
            - Default mode persists rows to dbo.Query_History and should be deployed
              through the approved governance/change-control process.
            - @Report_Only = 1 is ad-hoc safe: returns current DMV rows only and
              does not insert, purge, or otherwise modify repository data.
================================================================================
*/

USE [DBARepository];
GO

IF OBJECT_ID(N'dbo.sp_Capture_Running_Queries', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE [dbo].[sp_Capture_Running_Queries] AS RETURN 0;');
GO

ALTER PROCEDURE [dbo].[sp_Capture_Running_Queries]
    @Min_Duration_ms INT = 5000,
    @Max_History_Rows BIGINT = 500000,
    @Report_Only BIT = 0,
    @Max_Report_Rows INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @Current_Row_Count BIGINT;
    DECLARE @Capture_Count INT;

    IF @Report_Only = 1
    BEGIN
        SELECT TOP (@Max_Report_Rows)
            r.[session_id] AS [Session_ID],
            s.[login_name] AS [Login_Name],
            s.[host_name] AS [Host_Name],
            s.[program_name] AS [Program_Name],
            DB_NAME(r.[database_id]) AS [Database_Name],
            CASE 
                WHEN r.[sql_handle] IS NOT NULL THEN
                    SUBSTRING(t.[text], (r.[statement_start_offset] / 2) + 1,
                        ((CASE r.[statement_end_offset]
                            WHEN -1 THEN DATALENGTH(t.[text])
                            ELSE r.[statement_end_offset]
                        END - r.[statement_start_offset]) / 2) + 1)
                ELSE NULL
            END AS [Query_Text],
            r.[total_elapsed_time] AS [Duration_ms],
            r.[cpu_time] AS [CPU_Time],
            r.[logical_reads] AS [Logical_Reads],
            r.[writes] AS [Writes],
            r.[row_count] AS [Row_Count],
            r.[command] AS [Command_Type],
            SYSDATETIME() AS [Report_Time]
        FROM [sys].[dm_exec_requests] r
        INNER JOIN [sys].[dm_exec_sessions] s ON r.[session_id] = s.[session_id]
        OUTER APPLY [sys].[dm_exec_sql_text](r.[sql_handle]) t
        WHERE r.[session_id] > 50
          AND r.[session_id] <> @@SPID
          AND s.[is_user_process] = 1
          AND r.[total_elapsed_time] >= @Min_Duration_ms
          AND r.[status] <> 'sleeping'
          AND r.[sql_handle] IS NOT NULL
        ORDER BY r.[total_elapsed_time] DESC;

        RETURN;
    END

    INSERT INTO [dbo].[Query_History] (
        [Session_ID], [Login_Name], [Host_Name], [Program_Name],
        [Database_Name], [Query_Text], [Duration_ms], [CPU_Time],
        [Logical_Reads], [Writes], [Row_Count], [Command_Type], [Captured_Time]
    )
    SELECT 
        r.[session_id],
        s.[login_name],
        s.[host_name],
        s.[program_name],
        DB_NAME(r.[database_id]),
        CASE 
            WHEN r.[sql_handle] IS NOT NULL THEN
                SUBSTRING(t.[text], (r.[statement_start_offset] / 2) + 1,
                    ((CASE r.[statement_end_offset]
                        WHEN -1 THEN DATALENGTH(t.[text])
                        ELSE r.[statement_end_offset]
                    END - r.[statement_start_offset]) / 2) + 1)
            ELSE NULL
        END,
        r.[total_elapsed_time],
        r.[cpu_time],
        r.[logical_reads],
        r.[writes],
        r.[row_count],
        r.[command],
        SYSDATETIME()
    FROM [sys].[dm_exec_requests] r
    INNER JOIN [sys].[dm_exec_sessions] s ON r.[session_id] = s.[session_id]
    OUTER APPLY [sys].[dm_exec_sql_text](r.[sql_handle]) t
    WHERE r.[session_id] > 50
      AND r.[session_id] <> @@SPID
      AND s.[is_user_process] = 1
      AND r.[total_elapsed_time] >= @Min_Duration_ms
      AND r.[status] <> 'sleeping'
      AND r.[sql_handle] IS NOT NULL;

    SET @Capture_Count = @@ROWCOUNT;

    SELECT @Current_Row_Count = COUNT(*) FROM [dbo].[Query_History];
    
    IF @Current_Row_Count > @Max_History_Rows
    BEGIN
        WITH CTE_Delete AS (
            SELECT TOP (@Current_Row_Count - @Max_History_Rows)
                [History_ID]
            FROM [dbo].[Query_History]
            ORDER BY [Captured_Time] ASC
        )
        DELETE FROM CTE_Delete;
    END

    SELECT @Capture_Count AS [Queries_Captured],
           @Current_Row_Count AS [Total_Rows],
           SYSDATETIME() AS [Capture_Time];
END
GO

PRINT N'Created dbo.sp_Capture_Running_Queries procedure.';
GO