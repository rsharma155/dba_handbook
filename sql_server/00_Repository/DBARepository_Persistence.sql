/*
================================================================================
DBARepository_Persistence.sql — Assessment history and baseline tables
================================================================================
Purpose: Creates tables to persist assessment runs, findings, metrics, and
         baseline snapshots for trending and delta comparison.

Run after DBARepository_Create.sql. This script is idempotent (IF NOT EXISTS).

    sqlcmd -S YourServer -d DBARepository -i "00_Repository/DBARepository_Persistence.sql"
================================================================================
*/
USE [DBARepository];
GO

PRINT N'Creating persistence tables...';
GO

-------------------------------------------------------------------------------
-- AssessmentRun: Each assessment execution
-------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.AssessmentRun', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AssessmentRun (
        RunId           INT IDENTITY(1,1) PRIMARY KEY,
        ServerName      SYSNAME NOT NULL,
        RunUtc          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        Profile         VARCHAR(20) NOT NULL DEFAULT 'Standard',
        HealthScore     INT NOT NULL DEFAULT 100,
        SqlVersion      VARCHAR(50) NULL,
        SqlEdition      VARCHAR(100) NULL,
        FindingCount    INT NOT NULL DEFAULT 0,
        CriticalCount   INT NOT NULL DEFAULT 0,
        HighCount       INT NOT NULL DEFAULT 0,
        MediumCount     INT NOT NULL DEFAULT 0,
        LowCount        INT NOT NULL DEFAULT 0,
        ToolVersion     VARCHAR(20) NULL,
        Notes           NVARCHAR(500) NULL
    );

    CREATE INDEX IX_AssessmentRun_Server_Run ON dbo.AssessmentRun (ServerName, RunUtc DESC);
    PRINT N'  Created dbo.AssessmentRun';
END
ELSE
    PRINT N'  dbo.AssessmentRun already exists. Skipping.';
GO

-------------------------------------------------------------------------------
-- AssessmentFinding: Findings per assessment run
-------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.AssessmentFinding', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AssessmentFinding (
        FindingId       INT IDENTITY(1,1) PRIMARY KEY,
        RunId           INT NOT NULL REFERENCES dbo.AssessmentRun(RunId),
        CheckId         INT NOT NULL,
        Severity        VARCHAR(20) NOT NULL,
        Weight          INT NOT NULL DEFAULT 0,
        Area            VARCHAR(50) NOT NULL,
        Finding         VARCHAR(255) NOT NULL,
        Impact          VARCHAR(255) NULL,
        Recommendation  VARCHAR(MAX) NULL,
        NextStepCommand VARCHAR(MAX) NULL,
        DatabaseName    SYSNAME NULL,
        IsNew           BIT NOT NULL DEFAULT 0,
        ResolvedRunId   INT NULL REFERENCES dbo.AssessmentRun(RunId)
    );

    CREATE INDEX IX_AssessmentFinding_Run ON dbo.AssessmentFinding (RunId);
    CREATE INDEX IX_AssessmentFinding_CheckId ON dbo.AssessmentFinding (CheckId, RunId);
    CREATE INDEX IX_AssessmentFinding_Severity ON dbo.AssessmentFinding (Severity, RunId);
    PRINT N'  Created dbo.AssessmentFinding';
END
ELSE
    PRINT N'  dbo.AssessmentFinding already exists. Skipping.';
GO

-------------------------------------------------------------------------------
-- AssessmentMetric: Dashboard metrics per run
-------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.AssessmentMetric', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AssessmentMetric (
        MetricId        INT IDENTITY(1,1) PRIMARY KEY,
        RunId           INT NOT NULL REFERENCES dbo.AssessmentRun(RunId),
        MetricName      VARCHAR(100) NOT NULL,
        MetricValue     DECIMAL(18,4) NULL,
        MetricText      NVARCHAR(500) NULL,
        Unit            VARCHAR(20) NULL
    );

    CREATE INDEX IX_AssessmentMetric_Run ON dbo.AssessmentMetric (RunId);
    CREATE INDEX IX_AssessmentMetric_Name ON dbo.AssessmentMetric (MetricName, RunId);
    PRINT N'  Created dbo.AssessmentMetric';
END
ELSE
    PRINT N'  dbo.AssessmentMetric already exists. Skipping.';
GO

-------------------------------------------------------------------------------
-- BaselineSnapshot: Performance baseline captures
-------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.BaselineSnapshot', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BaselineSnapshot (
        SnapshotId      INT IDENTITY(1,1) PRIMARY KEY,
        ServerName      SYSNAME NOT NULL,
        SnapshotUtc     DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        SnapshotType    VARCHAR(20) NOT NULL DEFAULT 'Manual',
        WaitType        VARCHAR(128) NULL,
        WaitTimeMs      BIGINT NULL,
        SignalWaitMs    BIGINT NULL,
        WaitingTasks    BIGINT NULL,
        CounterName     VARCHAR(200) NULL,
        CounterValue    DECIMAL(18,4) NULL,
        DatabaseId      INT NULL,
        DatabaseName    SYSNAME NULL,
        FileId          INT NULL,
        NumReads        BIGINT NULL,
        NumWrites       BIGINT NULL,
        IoStallReadMs   BIGINT NULL,
        IoStallWriteMs  BIGINT NULL,
        Notes           NVARCHAR(500) NULL
    );

    CREATE INDEX IX_BaselineSnapshot_Server_Time ON dbo.BaselineSnapshot (ServerName, SnapshotUtc DESC);
    CREATE INDEX IX_BaselineSnapshot_WaitType ON dbo.BaselineSnapshot (WaitType, SnapshotUtc DESC);
    CREATE INDEX IX_BaselineSnapshot_Counter ON dbo.BaselineSnapshot (CounterName, SnapshotUtc DESC);
    PRINT N'  Created dbo.BaselineSnapshot';
END
ELSE
    PRINT N'  dbo.BaselineSnapshot already exists. Skipping.';
GO

-------------------------------------------------------------------------------
-- View: Latest assessment per server
-------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.vw_LatestAssessment', N'V') IS NOT NULL
    DROP VIEW dbo.vw_LatestAssessment;
GO

CREATE VIEW dbo.vw_LatestAssessment AS
SELECT
    r.ServerName,
    r.RunId,
    r.RunUtc,
    r.Profile,
    r.HealthScore,
    r.FindingCount,
    r.CriticalCount,
    r.HighCount,
    r.MediumCount,
    r.LowCount,
    r.SqlVersion,
    r.SqlEdition,
    r.ToolVersion
FROM dbo.AssessmentRun AS r
INNER JOIN (
    SELECT ServerName, MAX(RunId) AS MaxRunId
    FROM dbo.AssessmentRun
    GROUP BY ServerName
) AS latest ON r.ServerName = latest.ServerName AND r.RunId = latest.MaxRunId;
GO

PRINT N'  Created dbo.vw_LatestAssessment';
GO

-------------------------------------------------------------------------------
-- View: Finding trends (new findings vs resolved)
-------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.vw_FindingTrend', N'V') IS NOT NULL
    DROP VIEW dbo.vw_FindingTrend;
GO

CREATE VIEW dbo.vw_FindingTrend AS
SELECT
    r.ServerName,
    r.RunUtc,
    r.HealthScore,
    f.CheckId,
    f.Severity,
    f.Area,
    f.Finding,
    f.IsNew,
    CASE WHEN f.ResolvedRunId IS NOT NULL THEN 1 ELSE 0 END AS IsResolved
FROM dbo.AssessmentFinding AS f
INNER JOIN dbo.AssessmentRun AS r ON f.RunId = r.RunId;
GO

PRINT N'  Created dbo.vw_FindingTrend';
GO

PRINT N'Persistence tables created successfully.';
PRINT N'';
PRINT N'Next step: Run sp_DBA_SaveAssessmentRun to persist assessment data.';
GO
