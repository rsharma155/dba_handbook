/*
    Migration 2016 -> 2022 | Post-migration day-1 validation
    Run on TARGET 2022 within first 24 hours after go-live.
    Risk: Read-only
*/
SET NOCOUNT ON;

SELECT GETDATE() AS [ValidationTime], @@SERVERNAME AS [Instance], @@VERSION AS [Version];

SELECT name, state_desc, compatibility_level, recovery_model_desc, is_read_only
FROM sys.databases WHERE database_id > 4 ORDER BY name;

SELECT name, value_in_use
FROM sys.configurations
WHERE name IN (
    N'max server memory (MB)', N'max degree of parallelism',
    N'cost threshold for parallelism', N'backup compression default'
)
ORDER BY name;

SELECT
    SUM(CASE WHEN wait_time_ms > 0 THEN 1 ELSE 0 END) AS [WaitTypesWithTime],
    SUM(wait_time_ms) AS [TotalWaitTimeMs]
FROM sys.dm_os_wait_stats
WHERE wait_type NOT LIKE N'SLEEP%';

SELECT TOP (10)
    qs.total_elapsed_time / NULLIF(qs.execution_count, 0) AS [avg_elapsed_us],
    qs.total_worker_time / NULLIF(qs.execution_count, 0) AS [avg_cpu_us],
    qs.execution_count,
    SUBSTRING(st.text, 1, 200) AS [query_text]
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY qs.total_elapsed_time DESC;

SELECT
    j.name,
    h.run_date,
    h.run_time,
    h.run_status,
    h.message
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobhistory AS h ON j.job_id = h.job_id
WHERE h.step_id = 0
  AND h.run_date >= CONVERT(INT, CONVERT(VARCHAR(8), DATEADD(DAY, -1, GETDATE()), 112))
ORDER BY h.run_date DESC, h.run_time DESC;
