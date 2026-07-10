/*
================================================================================
11_Setup_Resource_Governor.sql - Resource Governor (Enterprise Only)
================================================================================
Purpose:    Configures Resource Governor for workload management.

Version:    2.1
Author:     DBA Team
Created:    2026-06-19
Updated:    2026-07-09 - Confirmed dry-run gate, prerequisites, and safety notes
Compatible: SQL Server 2016, 2017, 2019, 2022 (Enterprise only)

Prerequisites:
            - SQL Server Enterprise Edition with Resource Governor available.
            - Execute from a login authorized to alter Resource Governor in master.
            - Review pool/group limits with application owners before applying.

Usage:      Run on Enterprise Edition only. Review the planned Resource Governor
            configuration, then set @ExecuteMaintenance = 1 and
            @AllowProductionChanges = 1 to deploy the setup procedure.

Safety:     Defaults to dry run; no procedure is replaced unless
            @ExecuteMaintenance = 1 and @AllowProductionChanges = 1.
            The deployed procedure also defaults to no-op unless its
            @ApplyChanges and @AllowProductionChanges parameters are both 1.

Persistence: Replaces dbo.sp_Setup_Resource_Governor in master when explicitly
             enabled. Executing that procedure with both opt-in parameters set
             creates Resource Governor pools/groups and reconfigures Resource
             Governor until changed.
================================================================================
*/

USE [master];

DECLARE @ExecuteMaintenance BIT = 0;      -- 1 = replace setup procedure
DECLARE @AllowProductionChanges BIT = 0;  -- must also be 1 to mutate master
DECLARE @Edition VARCHAR(50);
SET @Edition = CAST(SERVERPROPERTY('Edition') AS VARCHAR(50));

PRINT N'=== RESOURCE GOVERNOR SETUP DEPLOYMENT ===';
PRINT N'Mode: '
    + CASE WHEN @ExecuteMaintenance = 1 AND @AllowProductionChanges = 1 THEN N'EXECUTE'
           ELSE N'DRY RUN - set @ExecuteMaintenance = 1 and @AllowProductionChanges = 1 to apply' END;

IF @ExecuteMaintenance <> 1 OR @AllowProductionChanges <> 1
BEGIN
    PRINT N'DRY RUN complete. No action was taken; dbo.sp_Setup_Resource_Governor was not created, dropped, or changed.';
    PRINT N'If deployed and later executed, the setup procedure also requires @ApplyChanges = 1 and @AllowProductionChanges = 1.';
    RETURN;
END;

-- Check for Enterprise Edition
IF @Edition NOT LIKE '%Enterprise%'
BEGIN
    RAISERROR(N'Resource Governor requires SQL Server Enterprise Edition. Current: %s', 16, 1, @Edition);
    RETURN;
END

IF OBJECT_ID(N'dbo.sp_Setup_Resource_Governor', N'P') IS NOT NULL
BEGIN
    DROP PROCEDURE [dbo].[sp_Setup_Resource_Governor];
    PRINT N'Dropped existing dbo.sp_Setup_Resource_Governor procedure.';
END;

EXEC(N'
CREATE PROCEDURE [dbo].[sp_Setup_Resource_Governor]
    @ApplyChanges BIT = 0,
    @AllowProductionChanges BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @ApplyChanges <> 1 OR @AllowProductionChanges <> 1
    BEGIN
        PRINT N''DRY RUN complete. No action was taken; no Resource Governor pools, workload groups, or reconfiguration changes were applied.'';
        PRINT N''Set @ApplyChanges = 1 and @AllowProductionChanges = 1 to configure Resource Governor.'';

        SELECT
            v.ObjectType,
            v.ObjectName,
            v.IntendedConfiguration
        FROM (VALUES
            (N''RESOURCE POOL'', N''Production_Pool'', N''MIN_CPU_PERCENT = 20, MAX_CPU_PERCENT = 50, MIN_MEMORY_PERCENT = 20, MAX_MEMORY_PERCENT = 40''),
            (N''RESOURCE POOL'', N''Developer_Pool'', N''MIN_CPU_PERCENT = 0, MAX_CPU_PERCENT = 30, MIN_MEMORY_PERCENT = 0, MAX_MEMORY_PERCENT = 30''),
            (N''WORKLOAD GROUP'', N''Production_Group'', N''IMPORTANCE = HIGH USING Production_Pool''),
            (N''WORKLOAD GROUP'', N''Developer_Group'', N''IMPORTANCE = LOW USING Developer_Pool'')
        ) AS v(ObjectType, ObjectName, IntendedConfiguration);

        RETURN;
    END;

    -- Create Resource Pools
    IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = N''Production_Pool'')
    BEGIN
        CREATE RESOURCE POOL [Production_Pool] WITH (MIN_CPU_PERCENT = 20, MAX_CPU_PERCENT = 50, MIN_MEMORY_PERCENT = 20, MAX_MEMORY_PERCENT = 40);
        PRINT N''Created Production_Pool.'';
    END

    IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = N''Developer_Pool'')
    BEGIN
        CREATE RESOURCE POOL [Developer_Pool] WITH (MIN_CPU_PERCENT = 0, MAX_CPU_PERCENT = 30, MIN_MEMORY_PERCENT = 0, MAX_MEMORY_PERCENT = 30);
        PRINT N''Created Developer_Pool.'';
    END

    -- Create Workload Groups
    IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = N''Production_Group'')
    BEGIN
        CREATE WORKLOAD GROUP [Production_Group] WITH (IMPORTANCE = HIGH) USING [Production_Pool];
        PRINT N''Created Production_Group.'';
    END

    IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = N''Developer_Group'')
    BEGIN
        CREATE WORKLOAD GROUP [Developer_Group] WITH (IMPORTANCE = LOW) USING [Developer_Pool];
        PRINT N''Created Developer_Group.'';
    END

    ALTER RESOURCE GOVERNOR RECONFIGURE;
    PRINT N''Resource Governor configured.'';
END;
');

PRINT N'Created dbo.sp_Setup_Resource_Governor procedure.';