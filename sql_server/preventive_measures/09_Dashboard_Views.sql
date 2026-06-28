/*
================================================================================
09_Dashboard_Views.sql - Layer 4: Dashboard Views for Monitoring
================================================================================
Purpose:    Creates views for monitoring dashboards and reporting.

Version:    2.0
Author:     DBA Team
Created:    2026-06-19
Updated:    2026-06-19 - Modified to use DBARepository database
Compatible: SQL Server 2016, 2017, 2019, 2022

Usage:      
    SELECT * FROM [dbo].[vw_Current_Running_Queries];
    SELECT * FROM [dbo].[vw_Long_Running_Queries];
    SELECT * FROM [dbo].[vw_Alert_Summary];
================================================================================
*/

USE [DBARepository];
GO

IF OBJECT_ID(N'dbo.vw_Current_Running_Queries', N'V') IS NOT NULL
    DROP VIEW [dbo].[vw_Current_Running_Queries];
GO

CREATE VIEW [dbo].[vw_Current_Running_Queries]
AS
SELECT 
    r.[session_id] AS [Session_ID],
    s.[login_name] AS [Login_Name],
    s.[host_name] AS [Host_Name],
    s.[program_name] AS [Program_Name],
    DB_NAME(r.[database_id]) AS [Database_Name],
    r.[status] AS [Status],
    r.[command] AS [Command],
    r.[total_elapsed_time] / 1000 AS [Duration_Seconds],
    r.[cpu_time] / 1000 AS [CPU_Seconds],
    r.[logical_reads] AS [Reads],
    r.[writes] AS [Writes],
    r.[row_count] AS [Rows],
    r.[wait_type] AS [Wait_Type]
FROM [sys].[dm_exec_requests] r
INNER JOIN [sys].[dm_exec_sessions] s ON r.[session_id] = s.[session_id]
WHERE r.[session_id] > 50 AND s.[is_user_process] = 1;
GO

IF OBJECT_ID(N'dbo.vw_Long_Running_Queries', N'V') IS NOT NULL
    DROP VIEW [dbo].[vw_Long_Running_Queries];
GO

CREATE VIEW [dbo].[vw_Long_Running_Queries]
AS
SELECT 
    r.[session_id] AS [Session_ID],
    s.[login_name] AS [Login_Name],
    s.[host_name] AS [Host_Name],
    s.[program_name] AS [Program_Name],
    DB_NAME(r.[database_id]) AS [Database_Name],
    r.[command] AS [Command],
    r.[total_elapsed_time] / 1000 AS [Duration_Seconds],
    r.[cpu_time] / 1000 AS [CPU_Seconds],
    r.[logical_reads] AS [Reads],
    (SELECT TOP 1 [Long_Query_Threshold_Seconds] FROM [dbo].[Policy_Config] WHERE [Enabled] = 1) AS [Threshold_Seconds]
FROM [sys].[dm_exec_requests] r
INNER JOIN [sys].[dm_exec_sessions] s ON r.[session_id] = s.[session_id]
WHERE r.[session_id] > 50
  AND s.[is_user_process] = 1
  AND r.[total_elapsed_time] > (
      SELECT ISNULL([Long_Query_Threshold_Seconds] * 1000, 10000)
      FROM [dbo].[Policy_Config] WHERE [Enabled] = 1
  );
GO

IF OBJECT_ID(N'dbo.vw_Alert_Summary', N'V') IS NOT NULL
    DROP VIEW [dbo].[vw_Alert_Summary];
GO

CREATE VIEW [dbo].[vw_Alert_Summary]
AS
SELECT 
    [Alert_Type], [Severity], COUNT(*) AS [Total_Count],
    SUM(CASE WHEN [Acknowledged] = 0 THEN 1 ELSE 0 END) AS [Unacknowledged],
    MIN([Created_Date]) AS [First_Occurrence], MAX([Created_Date]) AS [Last_Occurrence]
FROM [dbo].[Alert_Log]
WHERE [Created_Date] > DATEADD(DAY, -7, SYSDATETIME())
GROUP BY [Alert_Type], [Severity];
GO

IF OBJECT_ID(N'dbo.vw_Query_History_Summary', N'V') IS NOT NULL
    DROP VIEW [dbo].[vw_Query_History_Summary];
GO

CREATE VIEW [dbo].[vw_Query_History_Summary]
AS
SELECT 
    [Login_Name], [Host_Name], [Program_Name], [Database_Name],
    COUNT(*) AS [Query_Count], AVG([Duration_ms]) / 1000 AS [Avg_Duration_s],
    MAX([Duration_ms]) / 1000 AS [Max_Duration_s], SUM([CPU_Time]) / 1000 AS [Total_CPU_s]
FROM [dbo].[Query_History]
WHERE [Captured_Time] > DATEADD(DAY, -1, SYSDATETIME())
GROUP BY [Login_Name], [Host_Name], [Program_Name], [Database_Name];
GO

IF OBJECT_ID(N'dbo.vw_Top_Resource_Users', N'V') IS NOT NULL
    DROP VIEW [dbo].[vw_Top_Resource_Users];
GO

CREATE VIEW [dbo].[vw_Top_Resource_Users]
AS
SELECT TOP 100
    [Login_Name], [Host_Name], [Program_Name],
    COUNT(*) AS [Query_Count], SUM([Duration_ms]) / 1000 AS [Total_Duration_s],
    SUM([CPU_Time]) / 1000 AS [Total_CPU_s]
FROM [dbo].[Query_History]
WHERE [Captured_Time] > DATEADD(DAY, -1, SYSDATETIME())
GROUP BY [Login_Name], [Host_Name], [Program_Name]
ORDER BY [Total_Duration_s] DESC;
GO

PRINT N'Created dashboard views.';
GO