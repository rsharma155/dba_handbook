/*
================================================================================
11_Setup_Resource_Governor.sql - Resource Governor (Enterprise Only)
================================================================================
Purpose:    Configures Resource Governor for workload management.

Version:    2.0
Author:     DBA Team
Created:    2026-06-19
Compatible: SQL Server 2016, 2017, 2019, 2022 (Enterprise only)

Usage:      Run this script on Enterprise Edition only.
================================================================================
*/

USE [master];
GO

-- Check for Enterprise Edition
DECLARE @Edition VARCHAR(50);
SET @Edition = CAST(SERVERPROPERTY('Edition') AS VARCHAR(50));

IF @Edition NOT LIKE '%Enterprise%'
BEGIN
    RAISERROR(N'Resource Governor requires SQL Server Enterprise Edition. Current: %s', 16, 1, @Edition);
    RETURN;
END
GO

IF OBJECT_ID(N'dbo.sp_Setup_Resource_Governor', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_Setup_Resource_Governor];
GO

CREATE PROCEDURE [dbo].[sp_Setup_Resource_Governor]
AS
BEGIN
    SET NOCOUNT ON;

    -- Create Resource Pools
    IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = N'Production_Pool')
    BEGIN
        CREATE RESOURCE POOL [Production_Pool] WITH (MIN_CPU_PERCENT = 20, MAX_CPU_PERCENT = 50, MIN_MEMORY_PERCENT = 20, MAX_MEMORY_PERCENT = 40);
        PRINT N'Created Production_Pool.';
    END

    IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = N'Developer_Pool')
    BEGIN
        CREATE RESOURCE POOL [Developer_Pool] WITH (MIN_CPU_PERCENT = 0, MAX_CPU_PERCENT = 30, MIN_MEMORY_PERCENT = 0, MAX_MEMORY_PERCENT = 30);
        PRINT N'Created Developer_Pool.';
    END

    -- Create Workload Groups
    IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = N'Production_Group')
    BEGIN
        CREATE WORKLOAD GROUP [Production_Group] WITH (IMPORTANCE = HIGH) USING [Production_Pool];
        PRINT N'Created Production_Group.';
    END

    IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = N'Developer_Group')
    BEGIN
        CREATE WORKLOAD GROUP [Developer_Group] WITH (IMPORTANCE = LOW) USING [Developer_Pool];
        PRINT N'Created Developer_Group.';
    END

    ALTER RESOURCE GOVERNOR RECONFIGURE;
    PRINT N'Resource Governor configured.';
END;
GO

PRINT N'Created dbo.sp_Setup_Resource_Governor procedure.';
GO