USE [DBARepository];
GO

IF OBJECT_ID(N'dbo.sp_Check_Blocked_Applications', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_Check_Blocked_Applications];
GO

CREATE PROCEDURE [dbo].[sp_Check_Blocked_Applications]
    @Auto_Kill BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @Action_Type VARCHAR(20) = 'ALERT';
    DECLARE @Actions_Taken INT = 0;

    SELECT TOP 1 @Action_Type = [Action_Type]
    FROM [dbo].[Policy_Config] WHERE [Enabled] = 1;

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

    SELECT @Actions_Taken AS [Alerts_Generated];
END
GO

PRINT N'Created dbo.sp_Check_Blocked_Applications procedure.';
GO