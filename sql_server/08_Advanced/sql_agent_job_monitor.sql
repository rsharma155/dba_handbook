/*
================================================================================
SQL Server Agent Job Monitor: Failures & Duration Anomalies
================================================================================
Description:
    Detects SQL Agent job failures in the last 24 hours and flags jobs whose
    last run duration significantly exceeds their historical average duration.

Output:
    Two result sets: (1) Failed jobs with error messages, (2) Jobs with
    duration anomalies (current run much longer than average).

Action:
    For failed jobs: review the Error_Message and investigate the root cause.
    Common issues: backup destination full, login failures, unavailable databases.
    For duration anomalies: investigate if the job is waiting on blocking, running
    during peak load, or processing more data than usual. Consider rescheduling
    long-running jobs to off-peak hours.

Prerequisites: dbo.fn_DBA_AgentRunDurationSeconds (00_Framework) optional.

Criticality: High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @HasDurationFn BIT = CASE WHEN OBJECT_ID(N'dbo.fn_DBA_AgentRunDurationSeconds', N'FN') IS NOT NULL THEN 1 ELSE 0 END;

-- 1. Failed Jobs in Last 24 Hours
PRINT 'Checking for failed SQL Agent jobs (Last 24h)...';
SELECT
    j.name AS [Job_Name],
    s.step_id AS [Step_ID],
    s.step_name AS [Step_Name],
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS [Run_DateTime],
    h.message AS [Error_Message],
    CAST(N'Failed SQL Agent Job detection. Any failure in a critical production job requires investigation.' AS NVARCHAR(1000)) AS [Metric_Context]
FROM msdb.dbo.sysjobs AS j
INNER JOIN msdb.dbo.sysjobhistory AS h ON j.job_id = h.job_id
INNER JOIN msdb.dbo.sysjobsteps AS s ON j.job_id = s.job_id AND h.step_id = s.step_id
WHERE h.run_status = 0
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time) > DATEADD(DAY, -1, GETDATE())
ORDER BY [Run_DateTime] DESC;

-- 2. Long Running Jobs (Running > 2x their average duration)
PRINT 'Checking for jobs with duration anomalies...';
;WITH JobStats AS (
    SELECT
        job_id,
        AVG(
            CASE WHEN @HasDurationFn = 1
                THEN dbo.fn_DBA_AgentRunDurationSeconds(run_duration)
                ELSE ((run_duration / 10000) * 3600) + (((run_duration % 10000) / 100) * 60) + (run_duration % 100)
            END
        ) AS [Avg_Duration_s]
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0
      AND run_status = 1
    GROUP BY job_id
)
SELECT
    j.name AS [Job_Name],
    ja.run_requested_date AS [Start_Time],
    DATEDIFF(SECOND, ja.run_requested_date, GETDATE()) AS [Current_Duration_s],
    CAST(js.Avg_Duration_s AS INT) AS [Historical_Avg_s],
    CAST(N'Current duration > 2x historical average indicates blocking or abnormal data volume.' AS NVARCHAR(1000)) AS [Metric_Context]
FROM msdb.dbo.sysjobactivity AS ja
INNER JOIN msdb.dbo.sysjobs AS j ON ja.job_id = j.job_id
INNER JOIN JobStats AS js ON j.job_id = js.job_id
WHERE ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
  AND ja.start_execution_date IS NOT NULL
  AND ja.stop_execution_date IS NULL
  AND js.Avg_Duration_s > 0
  AND DATEDIFF(SECOND, ja.run_requested_date, GETDATE()) > (js.Avg_Duration_s * 2)
ORDER BY [Current_Duration_s] DESC;
