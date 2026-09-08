/* SQL_Server_Assessment */
;WITH last_run AS (
 SELECT job_id, run_status, run_date, run_time, message,
        ROW_NUMBER() OVER(PARTITION BY job_id ORDER BY instance_id DESC) AS rn
 FROM msdb.dbo.sysjobhistory WHERE step_id=0
)
SELECT j.name AS JobName, c.name AS Category, j.enabled AS Enabled,
       CASE lr.run_status WHEN 0 THEN 'Failed' WHEN 1 THEN 'Succeeded'
            WHEN 2 THEN 'Retry' WHEN 3 THEN 'Canceled' WHEN 4 THEN 'In Progress' ELSE 'Never' END AS LastRunStatus,
       CASE WHEN lr.run_date > 0 THEN msdb.dbo.agent_datetime(lr.run_date,lr.run_time) END AS LastRunDate,
       LEFT(lr.message,1000) AS LastMessage,
       CASE WHEN j.notify_level_email > 0 THEN 'Yes' ELSE 'No' END AS EmailNotification
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.syscategories c ON j.category_id=c.category_id
LEFT JOIN last_run lr ON j.job_id=lr.job_id AND lr.rn=1
ORDER BY j.name;
