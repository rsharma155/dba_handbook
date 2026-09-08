/* SQL_Server_Assessment */
SELECT TOP (100) j.name AS JobName,
       msdb.dbo.agent_datetime(h.run_date,h.run_time) AS RunDate,
       CASE h.run_status WHEN 0 THEN 'Failed' WHEN 2 THEN 'Retry' WHEN 3 THEN 'Canceled' END AS Status,
       h.step_name AS StepName, LEFT(h.message,2000) AS Message
FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON h.job_id=j.job_id
WHERE h.run_status IN (0,2,3)
AND msdb.dbo.agent_datetime(h.run_date,h.run_time) >= DATEADD(DAY,-{{DaysToAnalyze}},GETDATE())
ORDER BY h.instance_id DESC;
