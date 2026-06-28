/*
================================================================================
08_Alert_Management.sql - Layer 3: Alert Management & Notifications
================================================================================
Purpose:    LAYER 3 ALERT MANAGEMENT - Handles alert processing, notifications,
            and acknowledgment.

Version:    2.0
Author:     DBA Team
Created:    2026-06-19
Updated:    2026-06-19 - Modified to use DBARepository database
Compatible: SQL Server 2016, 2017, 2019, 2022

Usage:      
    EXEC [dbo].[sp_View_Alerts] @Hours_Back = 24;
    EXEC [dbo].[sp_Acknowledge_Alert] @Alert_ID = 123;
    EXEC [dbo].[sp_Get_Alert_Summary] @Hours_Back = 24;
    EXEC [dbo].[sp_Purge_Old_Alerts] @Days_to_Keep = 30;
================================================================================
*/

USE [DBARepository];
GO

IF OBJECT_ID(N'dbo.sp_View_Alerts', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE [dbo].[sp_View_Alerts] AS RETURN 0;');
GO

ALTER PROCEDURE [dbo].[sp_View_Alerts]
    @Hours_Back INT = 24,
    @Severity VARCHAR(20) = NULL,
    @Alert_Type VARCHAR(100) = NULL,
    @Unacknowledged_Only BIT = 0,
    @Max_Results INT = 1000
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SELECT TOP (@Max_Results)
        [Alert_ID], [Alert_Type], [Severity], [Session_ID], [Login_Name],
        [Host_Name], [Program_Name], [Database_Name], [Message],
        CASE WHEN LEN([Query_Text]) > 500 THEN LEFT([Query_Text], 500) + N'...'
             ELSE [Query_Text] END AS [Query_Text_Preview],
        [Action_Taken], [Created_Date], [Acknowledged], [Acknowledged_By], [Acknowledged_Date]
    FROM [dbo].[Alert_Log]
    WHERE [Created_Date] > DATEADD(HOUR, -@Hours_Back, SYSDATETIME())
      AND (@Severity IS NULL OR [Severity] = @Severity)
      AND (@Alert_Type IS NULL OR [Alert_Type] = @Alert_Type)
      AND (@Unacknowledged_Only = 0 OR [Acknowledged] = 0)
    ORDER BY [Created_Date] DESC;
END
GO

IF OBJECT_ID(N'dbo.sp_Acknowledge_Alert', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE [dbo].[sp_Acknowledge_Alert] AS RETURN 0;');
GO

ALTER PROCEDURE [dbo].[sp_Acknowledge_Alert]
    @Alert_ID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM [dbo].[Alert_Log] WHERE [Alert_ID] = @Alert_ID)
    BEGIN
        RAISERROR(N'Alert ID %d not found.', 16, 1, @Alert_ID);
        RETURN;
    END
    UPDATE [dbo].[Alert_Log]
    SET [Acknowledged] = 1, [Acknowledged_By] = SYSTEM_USER, [Acknowledged_Date] = SYSDATETIME()
    WHERE [Alert_ID] = @Alert_ID;
    PRINT N'Alert ' + CAST(@Alert_ID AS NVARCHAR(20)) + N' acknowledged.';
END
GO

IF OBJECT_ID(N'dbo.sp_Acknowledge_Multiple_Alerts', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE [dbo].[sp_Acknowledge_Multiple_Alerts] AS RETURN 0;');
GO

ALTER PROCEDURE [dbo].[sp_Acknowledge_Multiple_Alerts]
    @Alert_Type VARCHAR(100) = NULL,
    @Severity VARCHAR(20) = NULL,
    @Older_Than_Hours INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rows_Updated INT;
    UPDATE [dbo].[Alert_Log]
    SET [Acknowledged] = 1, [Acknowledged_By] = SYSTEM_USER, [Acknowledged_Date] = SYSDATETIME()
    WHERE [Acknowledged] = 0
      AND (@Alert_Type IS NULL OR [Alert_Type] = @Alert_Type)
      AND (@Severity IS NULL OR [Severity] = @Severity)
      AND (@Older_Than_Hours IS NULL OR [Created_Date] < DATEADD(HOUR, -@Older_Than_Hours, SYSDATETIME()));
    SET @Rows_Updated = @@ROWCOUNT;
    PRINT N'Acknowledged ' + CAST(@Rows_Updated AS NVARCHAR(20)) + N' alerts.';
    SELECT @Rows_Updated AS [Alerts_Acknowledged];
END
GO

IF OBJECT_ID(N'dbo.sp_Get_Alert_Summary', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE [dbo].[sp_Get_Alert_Summary] AS RETURN 0;');
GO

ALTER PROCEDURE [dbo].[sp_Get_Alert_Summary]
    @Hours_Back INT = 24
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SELECT 
        COUNT(*) AS [Total_Alerts],
        SUM(CASE WHEN [Severity] = 'CRITICAL' THEN 1 ELSE 0 END) AS [Critical_Count],
        SUM(CASE WHEN [Severity] = 'WARNING' THEN 1 ELSE 0 END) AS [Warning_Count],
        SUM(CASE WHEN [Severity] = 'INFO' THEN 1 ELSE 0 END) AS [Info_Count],
        SUM(CASE WHEN [Acknowledged] = 1 THEN 1 ELSE 0 END) AS [Acknowledged_Count],
        SUM(CASE WHEN [Acknowledged] = 0 THEN 1 ELSE 0 END) AS [Unacknowledged_Count],
        SUM(CASE WHEN [Action_Taken] = 'KILLED' THEN 1 ELSE 0 END) AS [Sessions_Killed]
    FROM [dbo].[Alert_Log]
    WHERE [Created_Date] > DATEADD(HOUR, -@Hours_Back, SYSDATETIME());

    SELECT [Alert_Type], [Severity], COUNT(*) AS [Count],
           MIN([Created_Date]) AS [First_Occurrence], MAX([Created_Date]) AS [Last_Occurrence]
    FROM [dbo].[Alert_Log]
    WHERE [Created_Date] > DATEADD(HOUR, -@Hours_Back, SYSDATETIME())
    GROUP BY [Alert_Type], [Severity]
    ORDER BY [Count] DESC;
END
GO

IF OBJECT_ID(N'dbo.sp_Purge_Old_Alerts', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE [dbo].[sp_Purge_Old_Alerts] AS RETURN 0;');
GO

ALTER PROCEDURE [dbo].[sp_Purge_Old_Alerts]
    @Days_to_Keep INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Rows_Deleted INT;
    DECLARE @Cutoff_Date DATETIME2 = DATEADD(DAY, -@Days_to_Keep, SYSDATETIME());
    DELETE FROM [dbo].[Alert_Log] WHERE [Created_Date] < @Cutoff_Date;
    SET @Rows_Deleted = @@ROWCOUNT;
    PRINT N'Deleted ' + CAST(@Rows_Deleted AS NVARCHAR(20)) + N' old alerts.';
    SELECT @Rows_Deleted AS [Alerts_Deleted];
END
GO

PRINT N'Created Layer 3 alert management procedures.';
GO