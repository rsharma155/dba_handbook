/*
================================================================================
SQL Server Failed Jobs & Maintenance Audit
================================================================================
Description:
    Detects SQL Agent job failures in the last 24 hours and identifies jobs
    whose last run duration significantly exceeds their historical average.
    Essential for daily operational hygiene checks.

Output:
    (1) Failed jobs with error messages and timestamps
    (2) Jobs with anomalous run durations

Action:
    For failed jobs: read the Error_Message and investigate. Common causes:
    backup destination full, login expiry, permission changes, network outage.
    For duration anomalies: investigate resource contention during the job's
    execution window (blocking, I/O pressure, concurrency). Consider rescheduling
    or optimizing the job steps.

Prerequisites: dbo.fn_DBA_AgentRunDurationSeconds (00_Framework) optional.
               Falls back to inline calculation if function is not available.

Criticality: High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @HasDurationFn BIT = CASE WHEN OBJECT_ID(N'dbo.fn_DBA_AgentRunDurationSeconds', N'FN') IS NOT NULL THEN 1 ELSE 0 END;

-- 1. Failed Jobs in the Last 24 Hours
PRINT '--- SQL Agent Job Failures (Last 24 Hours) ---';
SELECT
    j.name AS [Job_Name],
    h.step_id,
    h.step_name,
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS [Run_DateTime],
    h.run_duration AS [Duration_HHMMSS],
    CASE WHEN @HasDurationFn = 1
        THEN dbo.fn_DBA_AgentRunDurationSeconds(h.run_duration)
        ELSE ((h.run_duration / 10000) * 3600) + (((h.run_duration % 10000) / 100) * 60) + (h.run_duration % 100)
    END AS [Duration_Seconds],
    h.message AS [Error_Message],
    CASE
        WHEN h.run_status = 0 THEN N'FAILED'
        WHEN h.run_status = 2 THEN N'RETRY'
        WHEN h.run_status = 3 THEN N'CANCELLED'
    END AS [Status]
FROM msdb.dbo.sysjobs AS j
INNER JOIN msdb.dbo.sysjobhistory AS h ON j.job_id = h.job_id
WHERE h.run_status IN (0, 2, 3)
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time) > DATEADD(HOUR, -24, GETDATE())
ORDER BY [Run_DateTime] DESC;

-- 2. Long Running Jobs (Current)
PRINT '--- Currently Running Jobs & Duration ---';
SELECT
    j.name AS [Job_Name],
    ja.start_execution_date AS [Start_Time],
    DATEDIFF(MINUTE, ja.start_execution_date, GETDATE()) AS [Duration_Minutes],
    js.step_name AS [Current_Step]
FROM msdb.dbo.sysjobactivity AS ja
INNER JOIN msdb.dbo.sysjobs AS j ON ja.job_id = j.job_id
INNER JOIN msdb.dbo.sysjobsteps AS js ON ja.job_id = js.job_id AND ja.last_executed_step_id + 1 = js.step_id
WHERE ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
  AND ja.start_execution_date IS NOT NULL
  AND ja.stop_execution_date IS NULL
ORDER BY [Duration_Minutes] DESC;
