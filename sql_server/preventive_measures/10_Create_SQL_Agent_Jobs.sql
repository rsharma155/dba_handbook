/*
================================================================================
10_Create_SQL_Agent_Jobs.sql - Layer 2 & 3: SQL Agent Automation
================================================================================
Purpose:    Creates SQL Agent jobs for the preventive measures framework.

Version:    2.1
Author:     DBA Team
Created:    2026-06-19
Updated:    2026-06-19 - Modified to use DBARepository database
            2026-07-09 - Confirmed dry-run gate, prerequisites, and safety notes
Compatible: SQL Server 2016, 2017, 2019, 2022

Prerequisites:
            - SQL Server Agent must be installed and running.
            - DBARepository and governance procedures must be deployed first.
            - Execute from a login authorized to create/replace jobs in msdb.

Usage:      Review the job definitions, then set @ExecuteMaintenance = 1 and
            @AllowProductionChanges = 1 to create automation jobs.

Safety:     Defaults to dry run; no jobs, schedules, categories, or job
            assignments are created/deleted unless @ExecuteMaintenance = 1
            and @AllowProductionChanges = 1.

Persistence: Creates or replaces SQL Agent jobs in msdb when explicitly enabled.
             Job schedules and server assignments persist until changed or dropped.
================================================================================
*/

USE [msdb];

DECLARE @ExecuteMaintenance BIT = 0;      -- 1 = create/replace SQL Agent jobs
DECLARE @AllowProductionChanges BIT = 0;  -- must also be 1 to mutate msdb

PRINT N'=== SQL AGENT JOB DEPLOYMENT ===';
PRINT N'Mode: '
    + CASE WHEN @ExecuteMaintenance = 1 AND @AllowProductionChanges = 1 THEN N'EXECUTE'
           ELSE N'DRY RUN - set @ExecuteMaintenance = 1 and @AllowProductionChanges = 1 to apply' END;

IF @ExecuteMaintenance <> 1 OR @AllowProductionChanges <> 1
BEGIN
    PRINT N'DRY RUN complete. No action was taken; no SQL Agent jobs, schedules, categories, or job assignments were created, deleted, or changed.';
    SELECT
        v.JobName,
        v.ScheduleName,
        v.EnabledOnCreate,
        v.TargetDatabase
    FROM (VALUES
        (N'Governance_Query_Capture', N'Every 1 Minute', CONVERT(BIT, 1), N'DBARepository'),
        (N'Governance_Enforcement', N'Every 1 Minute', CONVERT(BIT, 1), N'DBARepository'),
        (N'Governance_Data_Cleanup', N'Daily at 2 AM', CONVERT(BIT, 1), N'DBARepository')
    ) AS v(JobName, ScheduleName, EnabledOnCreate, TargetDatabase);
    RETURN;
END;

-- Create job category
IF NOT EXISTS (SELECT 1 FROM syscategories WHERE name = N'Governance Monitoring')
BEGIN
    EXEC sp_add_category @class = N'JOB', @type = N'LOCAL', @name = N'Governance Monitoring';
    PRINT N'Created Governance Monitoring job category.';
END

--------------------------------------------------------------------------------
-- Job 1: Query Capture (every 1 minute)
--------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sysjobs WHERE name = N'Governance_Query_Capture')
    EXEC sp_delete_job @job_name = N'Governance_Query_Capture';

EXEC sp_add_job 
    @job_name = N'Governance_Query_Capture',
    @enabled = 1,
    @description = N'Lightweight DMV capture for query trending.',
    @category_name = N'Governance Monitoring',
    @owner_login_name = N'sa';

EXEC sp_add_jobstep 
    @job_name = N'Governance_Query_Capture',
    @step_name = N'Capture Queries',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'EXEC [dbo].[sp_Capture_Running_Queries] @Min_Duration_ms = 5000;',
    @database_name = N'DBARepository';

EXEC sp_add_jobschedule 
    @job_name = N'Governance_Query_Capture',
    @name = N'Every 1 Minute',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 1,
    @active_start_time = 0;

EXEC sp_add_jobserver @job_name = N'Governance_Query_Capture', @server_name = N'(LOCAL)';
PRINT N'Created Governance_Query_Capture job.';

--------------------------------------------------------------------------------
-- Job 2: Enforcement (every 1 minute)
--------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sysjobs WHERE name = N'Governance_Enforcement')
    EXEC sp_delete_job @job_name = N'Governance_Enforcement';

EXEC sp_add_job 
    @job_name = N'Governance_Enforcement',
    @enabled = 1,
    @description = N'Main enforcement job for policy checks.',
    @category_name = N'Governance Monitoring',
    @owner_login_name = N'sa';

EXEC sp_add_jobstep 
    @job_name = N'Governance_Enforcement',
    @step_name = N'Enforce Policies',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'EXEC [dbo].[sp_Check_Long_Running_Queries];',
    @database_name = N'DBARepository';

EXEC sp_add_jobschedule 
    @job_name = N'Governance_Enforcement',
    @name = N'Every 1 Minute',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 1,
    @active_start_time = 0;

EXEC sp_add_jobserver @job_name = N'Governance_Enforcement', @server_name = N'(LOCAL)';
PRINT N'Created Governance_Enforcement job.';

--------------------------------------------------------------------------------
-- Job 3: Data Cleanup (daily at 2 AM)
--------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sysjobs WHERE name = N'Governance_Data_Cleanup')
    EXEC sp_delete_job @job_name = N'Governance_Data_Cleanup';

EXEC sp_add_job 
    @job_name = N'Governance_Data_Cleanup',
    @enabled = 1,
    @description = N'Daily cleanup of old data.',
    @category_name = N'Governance Monitoring',
    @owner_login_name = N'sa';

EXEC sp_add_jobstep 
    @job_name = N'Governance_Data_Cleanup',
    @step_name = N'Purge Old Data',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'EXEC [dbo].[sp_Purge_Old_Alerts] @Days_to_Keep = 30;',
    @database_name = N'DBARepository';

EXEC sp_add_jobschedule 
    @job_name = N'Governance_Data_Cleanup',
    @name = N'Daily at 2 AM',
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 20000;

EXEC sp_add_jobserver @job_name = N'Governance_Data_Cleanup', @server_name = N'(LOCAL)';
PRINT N'Created Governance_Data_Cleanup job.';

PRINT N'=====================================================';
PRINT N'SQL Agent jobs created successfully!';
PRINT N'=====================================================';