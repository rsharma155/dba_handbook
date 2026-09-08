/*
    Migration 2016 -> 2022 | Linked servers, SQL Agent jobs, TRUSTWORTHY
    Risk: Read-only

    Notes:
    - T-SQL Agent job steps remain fully supported on SQL Server 2022.
    - ActiveX Scripting subsystem is discontinued - convert those steps to CmdExec/PowerShell.
    - Remote DAC (remote admin connections) is NOT removed - still configured via sp_configure.
*/
SET NOCOUNT ON;

SELECT
    s.server_id,
    s.name AS [LinkedServer],
    s.product,
    s.provider,
    s.data_source,
    s.is_linked,
    s.is_remote_login_enabled,
    s.modify_date
FROM sys.servers AS s
WHERE s.is_linked = 1
ORDER BY s.name;

SELECT
    j.job_id,
    j.name AS [JobName],
    j.enabled,
    j.description,
    j.date_created,
    j.date_modified,
    SUSER_SNAME(j.owner_sid) AS [Owner],
    c.name AS [Category]
FROM msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.syscategories AS c ON j.category_id = c.category_id
ORDER BY j.name;

SELECT
    j.name AS [JobName],
    js.step_id,
    js.step_name,
    js.subsystem,
    js.database_name,
    js.on_success_action,
    js.on_fail_action,
    js.last_run_outcome,
    js.last_run_date,
    js.last_run_time,
    CASE
        WHEN js.subsystem IN (N'ActiveScripting', N'ACTIVESCRIPTING')
            THEN N'BLOCKER - ActiveX subsystem discontinued; convert to CmdExec or PowerShell'
        WHEN js.subsystem = N'TSQL'
            THEN N'OK - T-SQL job steps remain fully supported on SQL Server 2022'
        ELSE N'Review on target'
    END AS [MigrationNote]
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobsteps AS js ON j.job_id = js.job_id
ORDER BY
    CASE WHEN js.subsystem IN (N'ActiveScripting', N'ACTIVESCRIPTING') THEN 0 ELSE 1 END,
    j.name,
    js.step_id;

-- Explicit ActiveX inventory (must remediate before/at 2022)
SELECT
    j.name AS [JobName],
    js.step_id,
    js.step_name,
    js.subsystem,
    LEFT(js.command, 400) AS [CommandPreview]
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobsteps AS js ON j.job_id = js.job_id
WHERE js.subsystem IN (N'ActiveScripting', N'ACTIVESCRIPTING')
ORDER BY j.name, js.step_id;

-- TRUSTWORTHY / cross-db ownership chaining (still supported; review security posture)
SELECT
    name AS [DatabaseName],
    is_trustworthy_on,
    is_db_chaining_on,
    CASE
        WHEN is_trustworthy_on = 1
            THEN N'REVIEW - TRUSTWORTHY ON increases risk; validate if still required on 2022'
        ELSE N'OK'
    END AS [MigrationNote]
FROM sys.databases
WHERE database_id > 4
ORDER BY is_trustworthy_on DESC, name;
