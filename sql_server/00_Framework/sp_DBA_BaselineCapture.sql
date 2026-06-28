/*
================================================================================
sp_DBA_BaselineCapture — Capture performance baseline snapshot
================================================================================
Captures current wait statistics, performance counters, and I/O file stats
into the BaselineSnapshot table for historical trending and delta comparison.

Run on a schedule (e.g., daily) to build baseline history. Compare snapshots
using the delta query in the header.

Delta comparison:
    WITH Latest AS (
        SELECT TOP (2) *
        FROM dbo.BaselineSnapshot
        WHERE ServerName = @@SERVERNAME AND WaitType IS NOT NULL
        ORDER BY SnapshotUtc DESC
    )
    SELECT
        a.WaitType,
        a.WaitTimeMs AS CurrentWait,
        b.WaitTimeMs AS PreviousWait,
        a.WaitTimeMs - b.WaitTimeMs AS DeltaWait
    FROM Latest a
    INNER JOIN Latest b ON a.WaitType = b.WaitType AND a.SnapshotId > b.SnapshotId;

Usage:
    EXEC dbo.sp_DBA_BaselineCapture;
    EXEC dbo.sp_DBA_BaselineCapture @CaptureWaitStats = 1, @CaptureCounters = 1;
================================================================================
*/
IF OBJECT_ID(N'dbo.sp_DBA_BaselineCapture', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DBA_BaselineCapture AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_DBA_BaselineCapture
    @CaptureWaitStats   BIT = 1,
    @CaptureCounters    BIT = 1,
    @CaptureFileStats   BIT = 1,
    @Notes              NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @ServerName SYSNAME = @@SERVERNAME;
    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();

    IF OBJECT_ID(N'dbo.BaselineSnapshot', N'U') IS NULL
    BEGIN
        RAISERROR(N'Run 00_Repository/DBARepository_Persistence.sql first to create BaselineSnapshot table.', 16, 1);
        RETURN;
    END;

    -- 1. Wait Statistics
    IF @CaptureWaitStats = 1
    BEGIN
        INSERT INTO dbo.BaselineSnapshot (
            ServerName, SnapshotUtc, SnapshotType, WaitType, WaitTimeMs, SignalWaitMs, WaitingTasks, Notes
        )
        SELECT
            @ServerName, @Now, 'Baseline',
            wait_type, wait_time_ms, signal_wait_time_ms, waiting_tasks_count, @Notes
        FROM sys.dm_os_wait_stats
        WHERE waiting_tasks_count > 0
          AND wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes());

        PRINT CAST(@@ROWCOUNT AS VARCHAR) + N' wait stats captured.';
    END;

    -- 2. Performance Counters
    IF @CaptureCounters = 1
    BEGIN
        INSERT INTO dbo.BaselineSnapshot (
            ServerName, SnapshotUtc, SnapshotType, CounterName, CounterValue, Notes
        )
        SELECT
            @ServerName, @Now, 'Baseline',
            object_name + '.' + counter_name,
            CAST(cntr_value AS DECIMAL(18,4)),
            @Notes
        FROM sys.dm_os_performance_counters
        WHERE cntr_value > 0
          AND counter_name IN (
              'Page life expectancy',
              'Buffer cache hit ratio',
              'Target Server Memory (KB)',
              'Total Server Memory (KB)',
              'SQL Compilations/sec',
              'SQL Re-Compilations/sec',
              'Batch Requests/sec',
              'Lock Waits/sec',
              'Number of Deadlocks/sec',
              'Transactions/sec'
          )
        ORDER BY object_name, counter_name;

        PRINT CAST(@@ROWCOUNT AS VARCHAR) + N' counters captured.';
    END;

    -- 3. I/O File Stats
    IF @CaptureFileStats = 1
    BEGIN
        INSERT INTO dbo.BaselineSnapshot (
            ServerName, SnapshotUtc, SnapshotType,
            DatabaseId, DatabaseName, FileId,
            NumReads, NumWrites, IoStallReadMs, IoStallWriteMs, Notes
        )
        SELECT
            @ServerName, @Now, 'Baseline',
            vfs.database_id, DB_NAME(vfs.database_id), vfs.file_id,
            vfs.num_of_reads, vfs.num_of_writes,
            vfs.io_stall_read_ms, vfs.io_stall_write_ms, @Notes
        FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
        ORDER BY vfs.database_id, vfs.file_id;

        PRINT CAST(@@ROWCOUNT AS VARCHAR) + N' file stats captured.';
    END;

    PRINT N'Baseline capture complete at ' + CONVERT(NVARCHAR(30), @Now, 121);
END;
GO
