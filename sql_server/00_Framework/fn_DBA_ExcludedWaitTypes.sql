/*
================================================================================
fn_DBA_ExcludedWaitTypes - Centralized benign wait type filter
================================================================================
Usage:
    WHERE wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes())
================================================================================
*/
IF OBJECT_ID(N'dbo.fn_DBA_ExcludedWaitTypes', N'IF') IS NOT NULL
    DROP FUNCTION dbo.fn_DBA_ExcludedWaitTypes;
GO

CREATE FUNCTION dbo.fn_DBA_ExcludedWaitTypes()
RETURNS TABLE
AS
RETURN
(
    SELECT wait_type
    FROM (VALUES
        (N'CLR_SEMAPHORE'),
        (N'LAZYWRITER_SLEEP'),
        (N'RESOURCE_QUEUE'),
        (N'SLEEP_TASK'),
        (N'SLEEP_SYSTEMTASK'),
        (N'SQLTRACE_BUFFER_FLUSH'),
        (N'WAITFOR'),
        (N'LOGMGR_QUEUE'),
        (N'CHECKPOINT_QUEUE'),
        (N'REQUEST_FOR_DEADLOCK_SEARCH'),
        (N'XE_TIMER_EVENT'),
        (N'XE_DISPATCHER_JOIN'),
        (N'XE_DISPATCHER_WAIT'),
        (N'FT_IFTS_SCHEDULER_VAL_KEEP_ALIVE'),
        (N'DIRTY_PAGE_TABLE_RELEASE'),
        (N'SP_SERVER_DIAGNOSTICS_SLEEP'),
        (N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP'),
        (N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP'),
        (N'REDO_THREAD_PENDING_WORK'),
        (N'WAIT_FOR_RESULTS'),
        (N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'),
        (N'BROKER_EVENTHANDLER'),
        (N'BROKER_RECEIVE_WAITFOR'),
        (N'BROKER_TRANSMITTER'),
        (N'BROKER_TO_FLUSH'),
        (N'ONDEMAND_TASK_QUEUE'),
        (N'PREEMPTIVE_OS_AUTHENTICATIONOPS'),
        (N'HADR_FABRIC_CALLBACK_EVENT'),
        (N'HADR_NOTIFICATION_DEQUEUE'),
        (N'HADR_TIMER_TASK'),
        (N'HADR_LOGCAPTURE_WAIT')
    ) AS excluded(wait_type)
);
GO
