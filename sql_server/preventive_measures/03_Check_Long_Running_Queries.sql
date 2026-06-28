USE [DBARepository];
GO

IF OBJECT_ID(N'dbo.sp_Check_Long_Running_Queries', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_Check_Long_Running_Queries];
GO

CREATE PROCEDURE [dbo].[sp_Check_Long_Running_Queries]
    @Auto_Kill BIT = 0
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

    SELECT @Actions_Taken AS [Alerts_Generated];
END
GO

PRINT N'Created dbo.sp_Check_Long_Running_Queries procedure.';
GO