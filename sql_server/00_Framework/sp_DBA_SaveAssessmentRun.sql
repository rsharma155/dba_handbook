/*
================================================================================
sp_DBA_SaveAssessmentRun — Persist assessment results to history tables
================================================================================
Saves an assessment run, its findings, and dashboard metrics to the persistence
tables for historical trending and delta comparison.

Usage:
    EXEC dbo.sp_DBA_SaveAssessmentRun
        @ServerName = N'PROD-SQL01',
        @Profile = N'Standard',
        @HealthScore = 78;

    -- With findings via TVP (requires SQL 2008+):
    DECLARE @Findings dbo.AssessmentFindingTableType;
    INSERT INTO @Findings (CheckId, Severity, Weight, Area, Finding, Impact, Recommendation)
    VALUES (102, 'High', 20, 'CPU', 'High SQL CPU', 'Degradation', 'Review top queries');
    EXEC dbo.sp_DBA_SaveAssessmentRun
        @ServerName = N'PROD-SQL01',
        @Profile = N'Standard',
        @HealthScore = 78,
        @Findings = @Findings;
================================================================================
*/
IF OBJECT_ID(N'dbo.sp_DBA_SaveAssessmentRun', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DBA_SaveAssessmentRun AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_DBA_SaveAssessmentRun
    @ServerName     SYSNAME,
    @Profile        VARCHAR(20) = 'Standard',
    @HealthScore    INT = 100,
    @SqlVersion     VARCHAR(50) = NULL,
    @SqlEdition     VARCHAR(100) = NULL,
    @ToolVersion    VARCHAR(20) = NULL,
    @Notes          NVARCHAR(500) = NULL,
    -- Dashboard metrics
    @SQLCPUPct      DECIMAL(5,2) = NULL,
    @SignalWaitPct  DECIMAL(5,2) = NULL,
    @MinPLEs        INT = NULL,
    @TotalMemMB     DECIMAL(18,2) = NULL,
    @TargetMemMB    DECIMAL(18,2) = NULL,
    @InstanceStartTime DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Insert run record
    DECLARE @RunId INT;

    INSERT INTO dbo.AssessmentRun (
        ServerName, Profile, HealthScore, SqlVersion, SqlEdition,
        ToolVersion, Notes, FindingCount, CriticalCount, HighCount, MediumCount, LowCount
    )
    VALUES (
        @ServerName, @Profile, @HealthScore, @SqlVersion, @SqlEdition,
        @ToolVersion, @Notes, 0, 0, 0, 0, 0
    );

    SET @RunId = SCOPE_IDENTITY();

    -- Insert dashboard metrics
    IF @SQLCPUPct IS NOT NULL
        INSERT INTO dbo.AssessmentMetric (RunId, MetricName, MetricValue, Unit)
        VALUES (@RunId, 'SQL_CPU_Pct', @SQLCPUPct, '%');

    IF @SignalWaitPct IS NOT NULL
        INSERT INTO dbo.AssessmentMetric (RunId, MetricName, MetricValue, Unit)
        VALUES (@RunId, 'Signal_Wait_Pct', @SignalWaitPct, '%');

    IF @MinPLEs IS NOT NULL
        INSERT INTO dbo.AssessmentMetric (RunId, MetricName, MetricValue, Unit)
        VALUES (@RunId, 'Min_PLE_s', @MinPLEs, 's');

    IF @TotalMemMB IS NOT NULL
        INSERT INTO dbo.AssessmentMetric (RunId, MetricName, MetricValue, Unit)
        VALUES (@RunId, 'Total_Mem_MB', @TotalMemMB, 'MB');

    IF @TargetMemMB IS NOT NULL
        INSERT INTO dbo.AssessmentMetric (RunId, MetricName, MetricValue, Unit)
        VALUES (@RunId, 'Target_Mem_MB', @TargetMemMB, 'MB');

    IF @InstanceStartTime IS NOT NULL
        INSERT INTO dbo.AssessmentMetric (RunId, MetricName, MetricText)
        VALUES (@RunId, 'Instance_Start_Time', CAST(@InstanceStartTime AS NVARCHAR(30)));

    SELECT @RunId AS RunId;
END;
GO
