/*
================================================================================
00_Install_Framework.sql - Deploy shared DBA framework objects
================================================================================
Execute in order against your admin database:

    1. fn_DBA_ExcludedWaitTypes.sql
    2. fn_DBA_AgentRunDurationSeconds.sql
    3. sp_DBA_ForEachDatabase.sql          (00_Framework/)
    4. sp_DBA_QueryStoreRegressions.sql    (00_Framework/)
    5. sp_DBA_HealthCheck.sql              (00_Framework/)
    6. sp_DBA_WaitAnalysis.sql             (00_Framework/)
    7. sp_DBA_IndexReview.sql              (00_Framework/)
    8. sp_DBA_SecurityAudit.sql            (00_Framework/)
    9. sp_DBA_BackupReview.sql             (00_Framework/)
    10. sp_DBA_ActiveSessions.sql          (00_Framework/)
    11. sp_DBA_PlanCacheAnalyzer.sql       (00_Framework/)
    12. sp_DBA_BaselineCapture.sql         (00_Framework/)
    13. sp_DBA_SaveAssessmentRun.sql       (00_Framework/)
================================================================================
*/
PRINT N'Deploy framework objects from 00_Framework and repo root .sql files (see README.md).';
GO
