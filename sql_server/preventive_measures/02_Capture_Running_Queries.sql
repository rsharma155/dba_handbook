/*
================================================================================
02_Capture_Running_Queries.sql - Layer 2: DMV Snapshot Capture
================================================================================
Purpose:    LIGHTWEIGHT DMV CAPTURE - Supplements Extended Events (Layer 1).
            XE captures events in real-time; this procedure captures point-in-time
            snapshots for trending and historical analysis.

Version:    2.0
Author:     DBA Team
Created:    2026-06-19
Updated:    2026-06-19 - Modified to use DBARepository database
Compatible: SQL Server 2016, 2017, 2019, 2022

Usage:      EXEC [dbo].[sp_Capture_Running_Queries];
            Scheduled via SQL Agent job every 60 seconds.

Notes:      - Lightweight query (runs in < 100ms on most systems)
            - Captures CURRENT state, not historical events
            - Supplements XE data for trending analysis
================================================================================
*/

USE [DBARepository];
GO

IF OBJECT_ID(N'dbo.sp_Capture_Running_Queries', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE [dbo].[sp_Capture_Running_Queries] AS RETURN 0;');
GO

ALTER PROCEDURE [dbo].[sp_Capture_Running_Queries]
    @Min_Duration_ms INT = 5000,
    @Max_History_Rows BIGINT = 500000
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @Current_Row_Count BIGINT;
    DECLARE @Capture_Count INT;

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