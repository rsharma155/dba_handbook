/*
================================================================================
10_Create_SQL_Agent_Jobs.sql - Layer 2 & 3: SQL Agent Automation
================================================================================
Purpose:    Creates SQL Agent jobs for the preventive measures framework.

Version:    2.0
Author:     DBA Team
Created:    2026-06-19
Updated:    2026-06-19 - Modified to use DBARepository database
Compatible: SQL Server 2016, 2017, 2019, 2022

Usage:      Run this script to create automation jobs.
================================================================================
*/

USE [msdb];
GO

-- Create job category
IF NOT EXISTS (SELECT 1 FROM syscategories WHERE name = N'Governance Monitoring')
BEGIN
    EXEC sp_add_category @class = N'JOB', @type = N'LOCAL', @name = N'Governance Monitoring';
    PRINT N'Created Governance Monitoring job category.';
END
GO

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
GO

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
GO

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
GO

PRINT N'=====================================================';
PRINT N'SQL Agent jobs created successfully!';
PRINT N'=====================================================';
GO