/*
    Migration 2016 -> 2022 | Enhanced Rollback Evidence Capture
    Run during high-priority triage / rollback decision window.
    Risk: Read-only

    Captures instance health plus database scoped configurations that explain
    CE / parameter sniffing / PSP optimizer regressions.
*/
SET NOCOUNT ON;
SET LOCK_TIMEOUT 3000;

PRINT '=== INSTANCE METRICS ===';
SELECT
    @@SERVERNAME AS [Instance],
    @@VERSION AS [EngineVersion],
    SERVERPROPERTY('ProductLevel') AS [ProductLevel],
    SERVERPROPERTY('ProductUpdateLevel') AS [ProductUpdateLevel],
    CONVERT(NVARCHAR(30), GETDATE(), 120) AS [CaptureTime];

PRINT '=== DATABASE STATE ===';
SELECT name, state_desc, user_access_desc, is_read_only, compatibility_level
FROM sys.databases
WHERE database_id > 4
ORDER BY name;

PRINT '=== DATABASE SCOPED CONFIGURATIONS (optimizer-critical) ===';
IF OBJECT_ID('tempdb..#ScopedCfg') IS NOT NULL DROP TABLE #ScopedCfg;
CREATE TABLE #ScopedCfg (
    DatabaseName SYSNAME NOT NULL,
    ConfigName   SYSNAME NOT NULL,
    Value        SQL_VARIANT NULL,
    ValueForSecondary SQL_VARIANT NULL,
    ScanNote     NVARCHAR(400) NULL
);

IF OBJECT_ID('tempdb..#DbList') IS NOT NULL DROP TABLE #DbList;
CREATE TABLE #DbList (
    RowId INT IDENTITY(1,1) PRIMARY KEY,
    DatabaseName SYSNAME NOT NULL
);

INSERT INTO #DbList (DatabaseName)
SELECT name
FROM sys.databases
WHERE database_id > 4
  AND state = 0
ORDER BY name;

DECLARE @i INT = 1, @max INT = (SELECT COUNT(*) FROM #DbList);
DECLARE @db SYSNAME, @sql NVARCHAR(MAX);

WHILE @i <= @max
BEGIN
    SELECT @db = DatabaseName FROM #DbList WHERE RowId = @i;

    SET @sql = N'
USE ' + QUOTENAME(@db) + N';
IF OBJECT_ID(''sys.database_scoped_configurations'') IS NOT NULL
BEGIN
    INSERT INTO #ScopedCfg (DatabaseName, ConfigName, Value, ValueForSecondary, ScanNote)
    SELECT DB_NAME(), name, value, value_for_secondary, NULL
    FROM sys.database_scoped_configurations
    WHERE name IN (
        N''LEGACY_CARDINALITY_ESTIMATION'',
        N''PARAMETER_SNIFFING'',
        N''QUERY_OPTIMIZER_HOTFIXES'',
        N''PARAMETER_SENSITIVE_PLAN_OPTIMIZATION'',
        N''BATCH_MODE_ON_ROWSTORE'',
        N''DEFERRED_COMPILATION_TV'',
        N''INTERLEAVED_EXECUTION_TVF'',
        N''ROW_MODE_MEMORY_GRANT_FEEDBACK'',
        N''BATCH_MODE_MEMORY_GRANT_FEEDBACK'',
        N''BATCH_MODE_ADAPTIVE_JOINS'',
        N''DOP_FEEDBACK'',
        N''CE_FEEDBACK'',
        N''OPTIMIZED_PLAN_FORCING''
    );
END;';

    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #ScopedCfg (DatabaseName, ConfigName, Value, ValueForSecondary, ScanNote)
        VALUES (@db, N'(scan skipped)', NULL, NULL, LEFT(ERROR_MESSAGE(), 400));
    END CATCH;

    SET @i += 1;
END;

SELECT DatabaseName, ConfigName, Value, ValueForSecondary, ScanNote
FROM #ScopedCfg
ORDER BY DatabaseName, ConfigName;

PRINT '=== ACTIVE HIGH-PRIORITY WAITS ===';
SELECT TOP (15)
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms - signal_wait_time_ms AS [resource_wait_ms]
FROM sys.dm_os_wait_stats
WHERE wait_type NOT LIKE N'SLEEP%'
  AND wait_type NOT IN (
      N'WAITFOR', N'REQUEST_FOR_DEADLOCK_SEARCH', N'LAZYWRITER_SLEEP',
      N'LOGMGR_QUEUE', N'CHECKPOINT_QUEUE', N'BROKER_TO_FLUSH',
      N'XE_TIMER_EVENT', N'XE_DISPATCHER_WAIT'
  )
  AND wait_time_ms > 0
ORDER BY wait_time_ms DESC;

PRINT '=== BLOCKING ===';
SELECT
    r.session_id, r.blocking_session_id, r.wait_type, r.wait_time,
    DB_NAME(r.database_id) AS db_name, r.status,
    SUBSTRING(st.text, 1, 200) AS stmt
FROM sys.dm_exec_requests AS r
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.blocking_session_id <> 0
   OR r.session_id IN (
        SELECT blocking_session_id
        FROM sys.dm_exec_requests
        WHERE blocking_session_id <> 0
   );

PRINT '=== FAILED AGENT JOBS (24H) ===';
SELECT j.name, h.run_date, h.run_time, h.run_status, LEFT(h.message, 500) AS msg
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobhistory AS h ON j.job_id = h.job_id
WHERE h.step_id <> 0
  AND h.run_status <> 1
  AND h.run_date >= CONVERT(INT, CONVERT(VARCHAR(8), DATEADD(DAY, -1, GETDATE()), 112))
ORDER BY h.run_date DESC, h.run_time DESC;

PRINT '=== AG HEALTH ===';
IF SERVERPROPERTY('IsHadrEnabled') = 1
    SELECT ag.name, ar.replica_server_name, ars.role_desc, ars.connected_state_desc,
           ars.synchronization_health_desc, DB_NAME(drs.database_id) AS [database_name], drs.synchronization_state_desc
    FROM sys.availability_groups AS ag
    JOIN sys.availability_replicas AS ar ON ag.group_id = ar.group_id
    JOIN sys.dm_hadr_availability_replica_states AS ars ON ar.replica_id = ars.replica_id
    LEFT JOIN sys.dm_hadr_database_replica_states AS drs ON ar.replica_id = drs.replica_id;
ELSE
    SELECT N'AG not enabled' AS [Note];

PRINT '=== RECENT ERROR LOG (newest first) ===';
BEGIN TRY
    EXEC sys.xp_readerrorlog 0, 1, NULL, NULL, NULL, NULL, N'desc';
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE() AS [ErrorLogReadFailed];
END CATCH;
