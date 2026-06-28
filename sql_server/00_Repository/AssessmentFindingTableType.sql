/*
================================================================================
AssessmentFindingTableType — Table-valued parameter for assessment findings
================================================================================
Table type used by sp_DBA_SaveAssessmentRun to accept findings as a TVP.
================================================================================
*/
IF TYPE_ID(N'dbo.AssessmentFindingTableType') IS NULL
BEGIN
    CREATE TYPE dbo.AssessmentFindingTableType AS TABLE (
        CheckId         INT NOT NULL,
        Severity        VARCHAR(20) NOT NULL,
        Weight          INT NOT NULL DEFAULT 0,
        Area            VARCHAR(50) NOT NULL,
        Finding         VARCHAR(255) NOT NULL,
        Impact          VARCHAR(255) NULL,
        Recommendation  VARCHAR(MAX) NULL,
        NextStepCommand VARCHAR(MAX) NULL,
        DatabaseName    SYSNAME NULL
    );
    PRINT N'Type dbo.AssessmentFindingTableType created.';
END
ELSE
    PRINT N'Type dbo.AssessmentFindingTableType already exists. Skipping.';
GO
