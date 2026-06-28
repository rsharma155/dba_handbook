/*
================================================================================
fn_DBA_AgentRunDurationSeconds - Convert msdb sysjobhistory.run_duration to seconds
================================================================================
msdb stores run_duration as HHMMSS encoded integer (e.g. 000500 = 5 minutes).
================================================================================
*/
IF OBJECT_ID(N'dbo.fn_DBA_AgentRunDurationSeconds', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_DBA_AgentRunDurationSeconds;
GO

CREATE FUNCTION dbo.fn_DBA_AgentRunDurationSeconds (@run_duration INT)
RETURNS INT
AS
BEGIN
    IF @run_duration IS NULL OR @run_duration < 0
        RETURN NULL;

    RETURN ((@run_duration / 10000) * 3600)
         + (((@run_duration % 10000) / 100) * 60)
         + (@run_duration % 100);
END;
GO
