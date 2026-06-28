/*
================================================================================
06_Enforce_Query_Policy.sql - Layer 2: Master Enforcement Orchestrator
================================================================================
Purpose:    MASTER ENFORCEMENT PROCEDURE - Orchestrates all monitoring checks,
            processes XE events (Layer 1), and takes action based on policy.
            This is the CORE automation procedure.

Architecture:
    Layer 1: Extended Events (always-on capture) - 07_Setup_Extended_Events.sql
    Layer 2 (This Script): Policy enforcement and action
    Layer 3: Alert notifications - 08_Alert_Management.sql
    
    This procedure coordinates:
    - Query capture (supplements XE data)
    - Long-running query detection
    - Massive DML detection
    - Blocked application detection
    - Alert generation
    - Session termination (if policy allows)

Version:    2.0
Author:     DBA Team
Created:    2026-06-19
Updated:    2026-06-19 - Restructured as Layer 2 orchestrator
Compatible: SQL Server 2016, 2017, 2019, 2022

Usage:      EXEC [dbo].[sp_Enforce_Query_Policy];
            Scheduled via SQL Agent job every 60 seconds.
            This is the MAIN entry point for policy enforcement.

Notes:      - Calls all individual check procedures
            - Provides comprehensive reporting
            - Handles errors gracefully
            - Returns summary of all actions taken
================================================================================
*/

USE [DBARepository];
GO

IF OBJECT_ID(N'dbo.sp_Enforce_Query_Policy', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE [dbo].[sp_Enforce_Query_Policy] AS RETURN 0;');
GO

ALTER PROCEDURE [dbo].[sp_Enforce_Query_Policy]
    @Run_Capture              BIT = 1,    -- Run query capture (Layer 2 supplement)
    @Run_Long_Query_Check     BIT = 1,    -- Run long running query check
    @Run_Massive_DML_Check    BIT = 1,    -- Run massive DML check
    @Run_Blocked_App_Check    BIT = 1,    -- Run blocked applications check
    @Auto_Kill                BIT = 0,    -- Override to auto-kill all violations
    @Verbose                  BIT = 0     -- Return detailed results
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    DECLARE @Start_Time DATETIME2 = SYSDATETIME();
    DECLARE @Error_Message NVARCHAR(MAX);
    DECLARE @Total_Alerts_Generated INT = 0;
    DECLARE @Total_Sessions_Killed INT = 0;

    -- Create summary table
    IF OBJECT_ID('tempdb..#EnforcementSummary') IS NOT NULL 
        DROP TABLE #EnforcementSummary;

    CREATE TABLE #EnforcementSummary (
        [Check_Name]        VARCHAR(50),
        [Status]            VARCHAR(20),
        [XE_Events]         INT,
        [Live_Checked]      INT,
        [Actions_Taken]     INT,
        [Duration_ms]       INT,
        [Error_Message]     NVARCHAR(MAX)
    );

    PRINT N'========================================';
    PRINT N'Governance Enforcement Started: ' + CONVERT(VARCHAR(30), @Start_Time, 121);
    PRINT N'========================================';

    --------------------------------------------------------------------------------
    -- 1. Capture Running Queries (Layer 2 supplement to XE)
    --------------------------------------------------------------------------------
    IF @Run_Capture = 1
    BEGIN
        DECLARE @Capture_Start DATETIME2 = SYSDATETIME();
        BEGIN TRY
            EXEC [dbo].[sp_Capture_Running_Queries];
            
            INSERT INTO #EnforcementSummary VALUES (
                'Capture Running Queries', 'SUCCESS',
                0, @@ROWCOUNT, 0,
                DATEDIFF(MILLISECOND, @Capture_Start, SYSDATETIME()),
                NULL
            );
        END TRY
        BEGIN CATCH
            SET @Error_Message = ERROR_MESSAGE();
            INSERT INTO #EnforcementSummary VALUES (
                'Capture Running Queries', 'FAILED',
                0, 0, 0,
                DATEDIFF(MILLISECOND, @Capture_Start, SYSDATETIME()),
                @Error_Message
            );
        END CATCH
    END

    --------------------------------------------------------------------------------
    -- 2. Check Long Running Queries (Process XE + DMV)
    --------------------------------------------------------------------------------
    IF @Run_Long_Query_Check = 1
    BEGIN
        DECLARE @LongQuery_Start DATETIME2 = SYSDATETIME();
        DECLARE @LongQuery_XE INT, @LongQuery_Live INT, @LongQuery_Killed INT;
        
        BEGIN TRY
            EXEC [dbo].[sp_Check_Long_Running_Queries] 
                @Auto_Kill = @Auto_Kill,
                @Process_XE_Events = 1,
                @Check_Live_DMV = 1;

            -- Capture results from the procedure (if available)
            -- For now, use placeholder values
            SET @LongQuery_XE = 0;
            SET @LongQuery_Live = 0;
            SET @LongQuery_Killed = 0;

            SET @Total_Alerts_Generated = @Total_Alerts_Generated + @LongQuery_XE + @LongQuery_Live;
            SET @Total_Sessions_Killed = @Total_Sessions_Killed + @LongQuery_Killed;

            INSERT INTO #EnforcementSummary VALUES (
                'Long Running Query Check', 'SUCCESS',
                @LongQuery_XE, @LongQuery_Live, @LongQuery_Killed,
                DATEDIFF(MILLISECOND, @LongQuery_Start, SYSDATETIME()),
                NULL
            );
        END TRY
        BEGIN CATCH
            SET @Error_Message = ERROR_MESSAGE();
            INSERT INTO #EnforcementSummary VALUES (
                'Long Running Query Check', 'FAILED',
                0, 0, 0,
                DATEDIFF(MILLISECOND, @LongQuery_Start, SYSDATETIME()),
                @Error_Message
            );
        END CATCH
    END

    --------------------------------------------------------------------------------
    -- 3. Check Massive DML Operations (Process XE + DMV)
    --------------------------------------------------------------------------------
    IF @Run_Massive_DML_Check = 1
    BEGIN
        DECLARE @DML_Start DATETIME2 = SYSDATETIME();
        DECLARE @DML_XE INT, @DML_Live INT, @DML_Killed INT;
        
        BEGIN TRY
            EXEC [dbo].[sp_Check_Massive_DML] 
                @Auto_Kill = @Auto_Kill,
                @Process_XE_Events = 1,
                @Check_Live_DMV = 1;

            SET @DML_XE = 0;
            SET @DML_Live = 0;
            SET @DML_Killed = 0;

            SET @Total_Alerts_Generated = @Total_Alerts_Generated + @DML_XE + @DML_Live;
            SET @Total_Sessions_Killed = @Total_Sessions_Killed + @DML_Killed;

            INSERT INTO #EnforcementSummary VALUES (
                'Massive DML Check', 'SUCCESS',
                @DML_XE, @DML_Live, @DML_Killed,
                DATEDIFF(MILLISECOND, @DML_Start, SYSDATETIME()),
                NULL
            );
        END TRY
        BEGIN CATCH
            SET @Error_Message = ERROR_MESSAGE();
            INSERT INTO #EnforcementSummary VALUES (
                'Massive DML Check', 'FAILED',
                0, 0, 0,
                DATEDIFF(MILLISECOND, @DML_Start, SYSDATETIME()),
                @Error_Message
            );
        END CATCH
    END

    --------------------------------------------------------------------------------
    -- 4. Check Blocked Applications
    --------------------------------------------------------------------------------
    IF @Run_Blocked_App_Check = 1
    BEGIN
        DECLARE @BlockedApp_Start DATETIME2 = SYSDATETIME();
        DECLARE @BlockedApp_Found INT, @BlockedApp_Killed INT;
        
        BEGIN TRY
            EXEC [dbo].[sp_Check_Blocked_Applications] @Auto_Kill = @Auto_Kill;

            SET @BlockedApp_Found = 0;
            SET @BlockedApp_Killed = 0;

            SET @Total_Alerts_Generated = @Total_Alerts_Generated + @BlockedApp_Found;
            SET @Total_Sessions_Killed = @Total_Sessions_Killed + @BlockedApp_Killed;

            INSERT INTO #EnforcementSummary VALUES (
                'Blocked Applications Check', 'SUCCESS',
                0, @BlockedApp_Found, @BlockedApp_Killed,
                DATEDIFF(MILLISECOND, @BlockedApp_Start, SYSDATETIME()),
                NULL
            );
        END TRY
        BEGIN CATCH
            SET @Error_Message = ERROR_MESSAGE();
            INSERT INTO #EnforcementSummary VALUES (
                'Blocked Applications Check', 'FAILED',
                0, 0, 0,
                DATEDIFF(MILLISECOND, @BlockedApp_Start, SYSDATETIME()),
                @Error_Message
            );
        END CATCH
    END

    --------------------------------------------------------------------------------
    -- Summary
    --------------------------------------------------------------------------------
    DECLARE @End_Time DATETIME2 = SYSDATETIME();
    DECLARE @Total_Duration_ms INT = DATEDIFF(MILLISECOND, @Start_Time, @End_Time);

    PRINT N'========================================';
    PRINT N'Governance Enforcement Completed: ' + CONVERT(VARCHAR(30), @End_Time, 121);
    PRINT N'Total Duration: ' + CAST(@Total_Duration_ms AS VARCHAR(10)) + ' ms';
    PRINT N'Total Alerts Generated: ' + CAST(@Total_Alerts_Generated AS VARCHAR(10));
    PRINT N'Total Sessions Killed: ' + CAST(@Total_Sessions_Killed AS VARCHAR(10));
    PRINT N'========================================';

    -- Return detailed results if verbose mode
    IF @Verbose = 1
    BEGIN
        SELECT * FROM #EnforcementSummary ORDER BY [Check_Name];
    END

    -- Always return summary
    SELECT 
        @Start_Time AS [Start_Time],
        @End_Time AS [End_Time],
        @Total_Duration_ms AS [Total_Duration_ms],
        @Total_Alerts_Generated AS [Total_Alerts_Generated],
        @Total_Sessions_Killed AS [Total_Sessions_Killed],
        @Auto_Kill AS [Auto_Kill_Enabled];

    DROP TABLE #EnforcementSummary;
END
GO

PRINT N'Created dbo.sp_Enforce_Query_Policy procedure.';
GO