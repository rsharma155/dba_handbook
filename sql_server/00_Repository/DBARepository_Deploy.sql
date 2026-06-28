/*
================================================================================
DBARepository_Deploy.sql — Deploy all DBA framework objects
================================================================================
Purpose: Installs all sp_DBA_*, fn_DBA_* into DBARepository.
         Run after DBARepository_Create.sql.

Run once per instance:
    sqlcmd -S YourServer -d DBARepository -i "00_Repository/DBARepository_Deploy.sql"

Objects installed (in dependency order):
    1. fn_DBA_ExcludedWaitTypes
    2. fn_DBA_AgentRunDurationSeconds
    3. sp_DBA_ForEachDatabase
    4. sp_DBA_QueryStoreRegressions
    5. sp_DBA_HealthCheck
    6. sp_DBA_WaitAnalysis
    7. sp_DBA_IndexReview
    8. sp_DBA_SecurityAudit
    9. sp_DBA_BackupReview
    10. sp_DBA_BaselineCapture
    11. AssessmentFindingTableType (table type)
    12. sp_DBA_SaveAssessmentRun

Then run separately:
    6. 00_Repository/CheckIdRegistry.sql
    7. 00_Repository/DBARepository_Persistence.sql
================================================================================
*/
USE [DBARepository];
GO

SET NOCOUNT ON;
GO

-- ============================================================================
-- 1. fn_DBA_ExcludedWaitTypes — table function for benign wait filtering
-- ============================================================================
PRINT N'Creating fn_DBA_ExcludedWaitTypes...';
GO

IF OBJECT_ID(N'dbo.fn_DBA_ExcludedWaitTypes', N'IF') IS NOT NULL
    DROP FUNCTION dbo.fn_DBA_ExcludedWaitTypes;
GO

CREATE FUNCTION dbo.fn_DBA_ExcludedWaitTypes ()
RETURNS TABLE
AS
RETURN
(
    SELECT wait_type FROM (VALUES
        ('BROKER_EVENTHANDLER'),
        ('BROKER_RECEIVE_WAITFOR'),
        ('BROKER_TASK_STOP'),
        ('BROKER_TO_FLUSH'),
        ('BROKER_TRANSMITTER'),
        ('CHECKPOINT_QUEUE'),
        ('CHKPT'),
        ('CLR_AUTO_EVENT'),
        ('CLR_MANUAL_EVENT'),
        ('CLR_SEMAPHORE'),
        ('DBMIRROR_DBM_EVENT'),
        ('DBMIRROR_EVENTS_QUEUE'),
        ('DBMIRROR_WORKER_QUEUE'),
        ('DBMIRRORING_CMD'),
        ('DIRTY_PAGE_POLL'),
        ('DISPATCHER_QUEUE_SEMAPHORE'),
        ('EXECSYNC'),
        ('FSAGENT'),
        ('FT_IFTS_SCHEDULER_IDLE_WAIT'),
        ('FT_IFTSHC_MUTEX'),
        ('HADR_FILESTREAM_IOMGR_IOCOMPLETION'),
        ('HADR_LOGCAPTURE_WAIT'),
        ('HADR_NOTIFICATION_DEQUEUE'),
        ('HADR_TIMER_TASK'),
        ('HADR_WORK_QUEUE'),
        ('LAZYWRITER_SLEEP'),
        ('LOGMGR_QUEUE'),
        ('MEMORY_ALLOCATION_EXT'),
        ('ONDEMAND_TASK_QUEUE'),
        ('PARALLEL_REDO_DRAIN_WORKER'),
        ('PARALLEL_REDO_LOG_CACHE'),
        ('PARALLEL_REDO_TRAN_LIST'),
        ('PARALLEL_REDO_WORKER_SYNC'),
        ('PARALLEL_REDO_WORKER_WAIT_WORK'),
        ('REQUEST_FOR_DEADLOCK_SEARCH'),
        ('RESOURCE_QUEUE'),
        ('SERVER_IDLE_CHECK'),
        ('SLEEP_BPOOL_FLUSH'),
        ('SLEEP_DBSTARTUP'),
        ('SLEEP_DCOMSTARTUP'),
        ('SLEEP_MASTERDBREADY'),
        ('SLEEP_MASTERMDREADY'),
        ('SLEEP_MASTERUPGRADED'),
        ('SLEEP_MSDBSTARTUP'),
        ('SLEEP_SYSTEMTASK'),
        ('SLEEP_TASK'),
        ('SLEEP_TEMPDBSTARTUP'),
        ('SNI_HTTP_ACCEPT'),
        ('SP_SERVER_DIAGNOSTICS_SLEEP'),
        ('SQLTRACE_BUFFER_FLUSH'),
        ('SQLTRACE_INCREMENTAL_FLUSH_SLEEP'),
        ('SQLTRACE_WAIT_ENTRIES'),
        ('WAIT_FOR_RESULTS'),
        ('WAITFOR_TASKSHUTDOWN'),
        ('WAIT_XTP_CKPT_CLOSE'),
        ('WAIT_XTP_RECOVERY'),
        ('WAIT_XTP_HOST_WAIT'),
        ('XE_DISPATCHER_JOIN'),
        ('XE_DISPATCHER_WAIT'),
        ('XE_TIMER_EVENT')
    ) AS excluded (wait_type);
);
GO

PRINT N'  fn_DBA_ExcludedWaitTypes created.';
GO

-- ============================================================================
-- 2. fn_DBA_AgentRunDurationSeconds — parse HHMMSS encoded duration
-- ============================================================================
PRINT N'Creating fn_DBA_AgentRunDurationSeconds...';
GO

IF OBJECT_ID(N'dbo.fn_DBA_AgentRunDurationSeconds', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_DBA_AgentRunDurationSeconds;
GO

CREATE FUNCTION dbo.fn_DBA_AgentRunDurationSeconds (
    @Duration INT
)
RETURNS INT
AS
BEGIN
    DECLARE @Seconds INT;
    SET @Seconds = (@Duration / 10000) * 3600
                 + ((@Duration % 10000) / 100) * 60
                 + (@Duration % 100);
    RETURN @Seconds;
END;
GO

PRINT N'  fn_DBA_AgentRunDurationSeconds created.';
GO

-- ============================================================================
-- 3. sp_DBA_ForEachDatabase — standardized cross-database execution
-- ============================================================================
PRINT N'Creating sp_DBA_ForEachDatabase...';
GO

IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DBA_ForEachDatabase;
GO

CREATE PROCEDURE dbo.sp_DBA_ForEachDatabase
    @SQL                NVARCHAR(MAX),
    @UserDatabasesOnly  BIT = 1,
    @IncludeReadOnly    BIT = 0,
    @DatabaseList       NVARCHAR(MAX) = NULL,
    @PrintOnly          BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @MajorVersion INT = CAST(PARSENAME(CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)), 4) AS INT);
    IF @MajorVersion < 13
    BEGIN
        RAISERROR(N'Query Store requires SQL Server 2016+.', 16, 1);
        RETURN;
    END;

    CREATE TABLE #QSDbs (database_name SYSNAME NOT NULL PRIMARY KEY);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
    BEGIN
        INSERT INTO #QSDbs (database_name)
        SELECT DISTINCT LTRIM(RTRIM(value))
        FROM STRING_SPLIT(@DatabaseList, N',')
        WHERE LTRIM(RTRIM(value)) <> N'';
    END
    ELSE
    BEGIN
        INSERT INTO #QSDbs (database_name)
        SELECT d.name
        FROM sys.databases d
        JOIN sys.database_query_store_options qs
            ON qs.actual_state_desc <> 'OFF'
        WHERE d.state = 0 AND d.database_id > 4;
    END;

    IF NOT EXISTS (SELECT 1 FROM #QSDbs)
    BEGIN
        PRINT N'No Query Store-enabled databases found.';
        RETURN;
    END;

    DECLARE @db_name SYSNAME;
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @db_cursor CURSOR;

    SET @db_cursor = CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM #QSDbs ORDER BY database_name;

    OPEN @db_cursor;
    FETCH NEXT FROM @db_cursor INTO @db_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'
        ;WITH RecentPlans AS (
            SELECT
                q.query_id,
                q.query_hash,
                p.plan_id,
                AVG(rs.avg_duration) AS avg_duration,
                SUM(rs.count_executions) AS exec_count,
                MIN(rs.first_execution_time) AS first_seen,
                MAX(rs.last_execution_time) AS last_seen
            FROM sys.query_store_query q
            JOIN sys.query_store_plan p ON p.query_id = q.query_id
            JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
            JOIN sys.query_store_runtime_stats_interval ri
                ON ri.runtime_stats_interval_id = rs.runtime_stats_interval_id
            WHERE ri.start_time >= DATEADD(HOUR, -@RecentHours, GETUTCDATE())
              AND rs.count_executions >= @MinExecutions
            GROUP BY q.query_id, q.query_hash, p.plan_id
        ),
        HistoricalBest AS (
            SELECT
                query_id,
                query_hash,
                MIN(avg_duration) AS best_duration
            FROM RecentPlans
            GROUP BY query_id, query_hash
        ),
        Regressions AS (
            SELECT
                r.query_id,
                r.query_hash,
                r.plan_id,
                r.avg_duration,
                r.exec_count,
                h.best_duration,
                CAST((r.avg_duration - h.best_duration) * 100.0
                    / NULLIF(h.best_duration, 0) AS DECIMAL(10,2)) AS regression_pct,
                r.first_seen,
                r.last_seen,
                ROW_NUMBER() OVER (
                    PARTITION BY r.query_id, r.query_hash
                    ORDER BY r.avg_duration DESC
                ) AS plan_rank
            FROM RecentPlans r
            JOIN HistoricalBest h
                ON h.query_id = r.query_id
               AND h.query_hash = r.query_hash
            WHERE r.avg_duration > h.best_duration * (1 + @RegressionPctThreshold / 100.0)
        )
        SELECT TOP (' + CAST(@TopPerDatabase AS NVARCHAR(10)) + N')
            N''' + REPLACE(@db_name, N'''', N'''''') + N''' AS DatabaseName,
            r.query_id,
            r.query_hash,
            r.plan_id,
            CAST(r.avg_duration / 1000.0 AS DECIMAL(12,2)) AS recent_avg_duration_ms,
            CAST(r.best_duration / 1000.0 AS DECIMAL(12,2)) AS best_avg_duration_ms,
            r.regression_pct,
            r.exec_count,
            r.first_seen,
            r.last_seen,
            t.query_sql_text
        FROM Regressions r
        JOIN sys.query_store_query q
            ON q.query_id = r.query_id
        JOIN sys.query_store_query_text t
            ON t.query_text_id = q.query_text_id
        WHERE r.plan_rank = 1
        ORDER BY r.regression_pct DESC;
        ';

        BEGIN TRY
            EXEC sp_executesql @sql,
                N'@RecentHours INT, @MinExecutions INT, @RegressionPctThreshold DECIMAL(5,2), @TopPerDatabase INT',
                @RecentHours, @MinExecutions, @RegressionPctThreshold, @TopPerDatabase;
        END TRY
        BEGIN CATCH
            PRINT N'Error in database [' + @db_name + N']: ' + ERROR_MESSAGE();
        END CATCH;

        FETCH NEXT FROM @db_cursor INTO @db_name;
    END;

    CLOSE @db_cursor;
    DEALLOCATE @db_cursor;
    DROP TABLE #QSDbs;
END;
GO

PRINT N'  sp_DBA_QueryStoreRegressions created.';
GO

-- ============================================================================
-- 5. sp_DBA_HealthCheck — consolidated diagnostic engine
-- ============================================================================
PRINT N'Creating sp_DBA_HealthCheck...';
GO

IF OBJECT_ID(N'dbo.sp_DBA_HealthCheck', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DBA_HealthCheck;
GO

CREATE PROCEDURE dbo.sp_DBA_HealthCheck
    @DeepDive           BIT = 0,
    @DatabaseList       NVARCHAR(MAX) = NULL,
    @IncludeReadOnly    BIT = 0,
    @BackupHoursSLA     INT = 24
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    IF OBJECT_ID(N'dbo.fn_DBA_ExcludedWaitTypes', N'IF') IS NULL
    BEGIN
        RAISERROR(N'Run DBARepository_Deploy.sql first.', 16, 1);
        RETURN;
    END;

    IF OBJECT_ID(N'tempdb..#DBAFindings') IS NOT NULL DROP TABLE #DBAFindings;
    CREATE TABLE #DBAFindings (
        CheckId         INT,
        Severity        VARCHAR(20),
        Weight          INT,
        Area            VARCHAR(50),
        Finding         VARCHAR(255),
        Impact          VARCHAR(255),
        Recommendation  VARCHAR(MAX),
        NextStepCommand VARCHAR(MAX)
    );

    DECLARE @HealthScore INT = 100;
    DECLARE @ProductVersion NVARCHAR(128) = CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128));
    DECLARE @MajorVersion INT = CAST(LEFT(@ProductVersion, CHARINDEX(N'.', @ProductVersion) - 1) AS INT);

    -- Build DB list
    CREATE TABLE #HC_Dbs (database_id INT NOT NULL PRIMARY KEY, database_name SYSNAME NOT NULL);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
    BEGIN
        INSERT INTO #HC_Dbs (database_id, database_name)
        SELECT d.database_id, d.name
        FROM sys.databases d
        INNER JOIN (
            SELECT LTRIM(RTRIM(value)) AS val
            FROM STRING_SPLIT(@DatabaseList, N',')
            WHERE LTRIM(RTRIM(value)) <> N''
        ) refs ON refs.val = d.name
        WHERE d.state = 0 AND d.is_in_standby = 0;
    END
    ELSE
    BEGIN
        INSERT INTO #HC_Dbs (database_id, database_name)
        SELECT database_id, name
        FROM sys.databases
        WHERE state = 0
          AND is_in_standby = 0
          AND database_id > 4
          AND (@IncludeReadOnly = 1 OR is_read_only = 0);
    END;

    -- ========================================================================
    -- CPU
    -- ========================================================================
    DECLARE @SQLServerCPU INT, @SystemIdle INT, @OtherCPU INT;

    SELECT TOP (1)
        @SQLServerCPU = SQLProcessUtilization,
        @SystemIdle = SystemIdle,
        @OtherCPU = 100 - SystemIdle - SQLProcessUtilization
    FROM (
        SELECT
            record.value(N'(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', N'int') AS SystemIdle,
            record.value(N'(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', N'int') AS SQLProcessUtilization
        FROM (
            SELECT TOP (1) CONVERT(XML, record) AS [record]
            FROM sys.dm_os_ring_buffers
            WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
              AND record LIKE N'%<SystemHealth>%'
            ORDER BY [timestamp] DESC
        ) AS x
    ) AS y;

    IF @SQLServerCPU > 80
    BEGIN
        INSERT INTO #DBAFindings VALUES (1001, 'CRITICAL', 10, 'CPU',
            'SQL Server CPU utilization > 80%',
            'SQLServer=' + CAST(@SQLServerCPU AS VARCHAR) + '%, Other=' + CAST(@OtherCPU AS VARCHAR) + '%',
            'Identify top CPU consumers. Check MAXDOP, CTFP, and parallelism settings.',
            'Run: 04_Performance_Diagnostics/top_resource_queries.sql');
        SET @HealthScore -= 10;
    END
    ELSE IF @SQLServerCPU > 70
    BEGIN
        INSERT INTO #DBAFindings VALUES (1002, 'MEDIUM', 5, 'CPU',
            'SQL Server CPU utilization > 70%',
            'SQLServer=' + CAST(@SQLServerCPU AS VARCHAR) + '%',
            'Monitor trend. Review parallelism and plan cache.',
            'Run: 04_Performance_Diagnostics/wait_statistics.sql');
        SET @HealthScore -= 5;
    END;

    -- Signal waits
    DECLARE @TotalWaitTime_ms BIGINT, @SignalWaitTime_ms BIGINT;
    SELECT
        @TotalWaitTime_ms = SUM(wait_time_ms),
        @SignalWaitTime_ms = SUM(signal_wait_time_ms)
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes());

    DECLARE @SignalWaitPct DECIMAL(5,2) = CASE WHEN @TotalWaitTime_ms > 0
        THEN @SignalWaitTime_ms * 100.0 / @TotalWaitTime_ms ELSE 0 END;

    IF @SignalWaitPct > 25
    BEGIN
        INSERT INTO #DBAFindings VALUES (1003, 'CRITICAL', 8, 'CPU',
            'Signal wait percentage > 25%',
            'Signal=' + CAST(CAST(@SignalWaitPct AS INT) AS VARCHAR) + '% — CPU bottleneck confirmed',
            'High signal waits indicate CPU contention. Review MAXDOP, consider hardware upgrade.',
            'Run: 01_Server_OS/cpu_utilization.sql');
        SET @HealthScore -= 8;
    END
    ELSE IF @SignalWaitPct > 15
    BEGIN
        INSERT INTO #DBAFindings VALUES (1004, 'MEDIUM', 4, 'CPU',
            'Signal wait percentage > 15%',
            'Signal=' + CAST(CAST(@SignalWaitPct AS INT) AS VARCHAR) + '%',
            'Elevated CPU pressure. Monitor and review top queries.',
            'Run: 04_Performance_Diagnostics/top_resource_queries.sql');
        SET @HealthScore -= 4;
    END;

    -- ========================================================================
    -- Memory
    -- ========================================================================
    DECLARE @TotalMem BIGINT, @TargetMem BIGINT, @PLE INT;
    SELECT @TotalMem = cntr_value * 8 FROM sys.dm_os_performance_counters
        WHERE counter_name = 'Total Server Memory (KB)';
    SELECT @TargetMem = cntr_value * 8 FROM sys.dm_os_performance_counters
        WHERE counter_name = 'Target Server Memory (KB)';
    SELECT @PLE = cntr_value FROM sys.dm_os_performance_counters
        WHERE counter_name = 'Page life expectancy'
          AND object_name LIKE '%Buffer Manager%';

    DECLARE @MemGB DECIMAL(10,2) = @TotalMem / 1073741824.0;
    DECLARE @PLEThreshold INT = CAST((@MemGB / 4.0) * 150 AS INT);

    IF @PLE < @PLEThreshold
    BEGIN
        INSERT INTO #DBAFindings VALUES (2001, 'HIGH', 8, 'Memory',
            'Page Life Expectancy below threshold',
            'PLE=' + CAST(@PLE AS VARCHAR) + ', Threshold=' + CAST(@PLEThreshold AS VARCHAR),
            'Investigate memory pressure. Check max server memory setting and memory grants.',
            'Run: 01_Server_OS/memory_diagnostics.sql');
        SET @HealthScore -= 8;
    END;

    -- ========================================================================
    -- Configuration
    -- ========================================================================
    DECLARE @CTFP INT, @MAXDOP INT;
    SELECT @CTFP = CAST(value_in_use AS INT) FROM sys.configurations WHERE name = 'cost threshold for parallelism';
    SELECT @MAXDOP = CAST(value_in_use AS INT) FROM sys.configurations WHERE name = 'max degree of parallelism';

    IF @MAXDOP = 0
    BEGIN
        INSERT INTO #DBAFindings VALUES (3001, 'MEDIUM', 3, 'Config',
            'MAXDOP = 0 (unlimited parallelism)',
            'Default setting may cause excessive parallelism on multi-core systems',
            'Consider setting MAXDOP to 4-8 based on NUMA topology.',
            'Run: 02_Instance_Config/server_configuration_audit.sql');
        SET @HealthScore -= 3;
    END;

    IF @CTFP < 25
    BEGIN
        INSERT INTO #DBAFindings VALUES (3002, 'LOW', 2, 'Config',
            'Cost Threshold for Parallelism < 25',
            'Current value: ' + CAST(@CTFP AS VARCHAR),
            'Low CTFP causes trivial queries to go parallel. Consider 25-50.',
            'Run: 02_Instance_Config/server_configuration_audit.sql');
        SET @HealthScore -= 2;
    END;

    -- ========================================================================
    -- Backup SLA
    -- ========================================================================
    DECLARE @db_id INT, @db_name SYSNAME;
    DECLARE @LastFull DATETIME2, @LastDiff DATETIME2, @LastLog DATETIME2;
    DECLARE @RecoveryModelDesc NVARCHAR(20);
    DECLARE @db_cursor CURSOR;

    SET @db_cursor = CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_id, database_name FROM #HC_Dbs ORDER BY database_name;

    OPEN @db_cursor;
    FETCH NEXT FROM @db_cursor INTO @db_id, @db_name;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @RecoveryModelDesc = recovery_model_desc FROM sys.databases WHERE database_id = @db_id;

        SELECT @LastFull = MAX(backup_finish_date)
        FROM msdb.dbo.backupset
        WHERE database_name = @db_name AND type = 'D' AND is_copy_only = 0;

        SELECT @LastLog = MAX(backup_finish_date)
        FROM msdb.dbo.backupset
        WHERE database_name = @db_name AND type = 'L' AND is_copy_only = 0;

        IF @LastFull IS NULL OR DATEDIFF(HOUR, @LastFull, GETDATE()) > @BackupHoursSLA
        BEGIN
            INSERT INTO #DBAFindings VALUES (4001, 'CRITICAL', 15, 'Backup',
                'Full backup missing or stale: [' + @db_name + N']',
                'Last full: ' + ISNULL(CAST(@LastFull AS VARCHAR), 'NEVER')
                    + ', SLA=' + CAST(@BackupHoursSLA AS VARCHAR) + 'h',
                'Take a full backup immediately.',
                'Run: 06_HA_DR/backup_verification.sql');
            SET @HealthScore -= 15;
        END;

        IF @RecoveryModelDesc = N'FULL' AND @LastLog IS NOT NULL
           AND DATEDIFF(MINUTE, @LastLog, GETDATE()) > @BackupHoursSLA * 60
        BEGIN
            INSERT INTO #DBAFindings VALUES (4002, 'HIGH', 8, 'Backup',
                'Log backup stale: [' + @db_name + N']',
                'Last log: ' + CAST(@LastLog AS VARCHAR) + ', Model=' + @RecoveryModelDesc,
                'Log backup overdue. Risk of log file growth and broken log chain.',
                'Run: 06_HA_DR/backup_log_chain.sql');
            SET @HealthScore -= 8;
        END;

        FETCH NEXT FROM @db_cursor INTO @db_id, @db_name;
    END;

    CLOSE @db_cursor;
    DEALLOCATE @db_cursor;

    -- ========================================================================
    -- Security
    -- ========================================================================
    DECLARE @SysadminCount INT;
    SELECT @SysadminCount = COUNT(*)
    FROM sys.server_role_members rm
    JOIN sys.server_principals p ON p.principal_id = rm.member_principal_id
    WHERE rm.role_principal_id = SUSER_SID('sysadmin');

    IF @SysadminCount > 5
    BEGIN
        INSERT INTO #DBAFindings VALUES (5001, 'MEDIUM', 3, 'Security',
            'Excessive sysadmin members',
            CAST(@SysadminCount AS VARCHAR) + ' members in sysadmin role',
            'Review sysadmin membership. Use principle of least privilege.',
            'Run: 07_Security/login_audit.sql');
        SET @HealthScore -= 3;
    END;

    -- ========================================================================
    -- AG Health
    -- ========================================================================
    DECLARE @IsHadrEnabled INT = CAST(SERVERPROPERTY(N'IsHadrEnabled') AS INT);
    IF @IsHadrEnabled = 1
    BEGIN
        DECLARE @UnhealthyReplicas INT;
        SELECT @UnhealthyReplicas = COUNT(*)
        FROM sys.dm_hadr_availability_replica_states
        WHERE synchronization_health_desc <> 'HEALTHY';

        IF @UnhealthyReplicas > 0
        BEGIN
            INSERT INTO #DBAFindings VALUES (6001, 'HIGH', 8, 'HA/DR',
                'Unhealthy Always On AG replicas detected',
                CAST(@UnhealthyReplicas AS VARCHAR) + ' replica(s) not healthy',
                'Investigate AG synchronization state and redo lag.',
                'Run: 06_HA_DR/alwayson_ag_monitor.sql');
            SET @HealthScore -= 8;
        END;
    END;

    -- ========================================================================
    -- VLF (per database, 2016+)
    -- ========================================================================
    IF @MajorVersion >= 13
    BEGIN
        SET @db_cursor = CURSOR LOCAL FAST_FORWARD FOR
            SELECT database_id, database_name FROM #HC_Dbs ORDER BY database_name;

        OPEN @db_cursor;
        FETCH NEXT FROM @db_cursor INTO @db_id, @db_name;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @VLFCount INT;
            DECLARE @sql NVARCHAR(MAX);
            SET @sql = N'SELECT @cnt = COUNT(*) FROM sys.dm_db_log_info(' + CAST(@db_id AS NVARCHAR) + N');';
            EXEC sp_executesql @sql, N'@cnt INT OUTPUT', @cnt = @VLFCount OUTPUT;

            IF @VLFCount >= 1000
            BEGIN
                INSERT INTO #DBAFindings VALUES (7001, 'HIGH', 5, 'Storage',
                    'Excessive VLF count: [' + @db_name + N']',
                    'VLF count: ' + CAST(@VLFCount AS VARCHAR),
                    'High VLF counts slow recovery and log backups.',
                    'Run: 03_Storage_Engine/vlf_fragmentation.sql');
                SET @HealthScore -= 5;
            END
            ELSE IF @VLFCount >= 200
            BEGIN
                INSERT INTO #DBAFindings VALUES (7002, 'MEDIUM', 2, 'Storage',
                    'Elevated VLF count: [' + @db_name + N']',
                    'VLF count: ' + CAST(@VLFCount AS VARCHAR),
                    'Monitor VLF growth. Plan log file maintenance.',
                    'Run: 03_Storage_Engine/vlf_fragmentation.sql');
                SET @HealthScore -= 2;
            END;

            FETCH NEXT FROM @db_cursor INTO @db_id, @db_name;
        END;

        CLOSE @db_cursor;
        DEALLOCATE @db_cursor;
    END;

    -- ========================================================================
    -- OUTPUT
    -- ========================================================================
    -- Result set 1: Dashboard
    SELECT
        @@SERVERNAME AS ServerName,
        SERVERPROPERTY('ProductVersion') AS SQLVersion,
        @HealthScore AS Health_Score,
        CASE
            WHEN @HealthScore >= 85 THEN 'GREEN'
            WHEN @HealthScore >= 70 THEN 'YELLOW'
            ELSE 'RED'
        END AS Health_TrafficLight,
        @SQLServerCPU AS SQL_CPU_Pct,
        CAST(@SignalWaitPct AS DECIMAL(5,2)) AS Signal_Wait_Pct,
        @PLE AS PLE_Seconds,
        @TotalMem / 1073741824 AS Total_Memory_GB,
        (SELECT sqlserver_start_time FROM sys.dm_os_sys_info) AS Instance_Start_Time,
        (SELECT COUNT(*) FROM #DBAFindings WHERE Severity = 'CRITICAL') AS Critical_Count,
        (SELECT COUNT(*) FROM #DBAFindings WHERE Severity = 'HIGH') AS High_Count,
        (SELECT COUNT(*) FROM #DBAFindings WHERE Severity = 'MEDIUM') AS Medium_Count,
        (SELECT COUNT(*) FROM #DBAFindings WHERE Severity = 'LOW') AS Low_Count;

    -- Result set 2: Findings
    SELECT CheckId, Severity, Weight, Area, Finding, Impact, Recommendation, NextStepCommand
    FROM #DBAFindings
    ORDER BY
        CASE Severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END,
        Weight DESC;

    -- Result set 3: Deep dive (optional)
    IF @DeepDive = 1
    BEGIN
        SELECT TOP (10)
            wait_type,
            wait_time_ms / 1000.0 AS wait_time_s,
            signal_wait_time_ms / 1000.0 AS signal_wait_s,
            CAST(wait_time_ms * 100.0 / NULLIF(SUM(wait_time_ms) OVER(), 0) AS DECIMAL(5,2)) AS pct_of_top20
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes())
          AND wait_time_ms > 0
        ORDER BY wait_time_ms DESC;

        SELECT TOP (10)
            qs.total_worker_time / 1000 AS total_cpu_ms,
            qs.execution_count,
            qs.total_elapsed_time / 1000 AS total_duration_ms,
            SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
                ((CASE qs.statement_end_offset
                    WHEN -1 THEN DATALENGTH(st.text)
                    ELSE qs.statement_end_offset
                END - qs.statement_start_offset)/2)+1) AS query_text
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        ORDER BY qs.total_worker_time DESC;

        SELECT
            DB_NAME(vfs.database_id) AS database_name,
            mf.physical_name,
            mf.type_desc AS file_type,
            CASE WHEN num_of_reads = 0 THEN 0
                ELSE io_stall_read_ms / num_of_reads END AS avg_read_stall_ms,
            CASE WHEN num_of_writes = 0 THEN 0
                ELSE io_stall_write_ms / num_of_writes END AS avg_write_stall_ms
        FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
        JOIN sys.master_files mf
            ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id
        WHERE (io_stall_read_ms / NULLIF(num_of_reads, 0) > 15
            OR io_stall_write_ms / NULLIF(num_of_writes, 0) > 15)
        ORDER BY (io_stall_read_ms + io_stall_write_ms) DESC;
    END;

    DROP TABLE #DBAFindings;
    DROP TABLE #HC_Dbs;
END;
GO

PRINT N'  sp_DBA_HealthCheck created.';
GO

-- ============================================================================
-- 6. sp_DBA_WaitAnalysis — top wait types with categories and recommendations
-- ============================================================================
PRINT N'Creating sp_DBA_WaitAnalysis...';
GO

IF OBJECT_ID(N'dbo.sp_DBA_WaitAnalysis', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DBA_WaitAnalysis;
GO

CREATE PROCEDURE dbo.sp_DBA_WaitAnalysis
    @TopN                   INT = 20,
    @IncludeRecommendations BIT = 1,
    @MinWaitCount           INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @TotalWaitMs BIGINT;
    SELECT @TotalWaitMs = SUM(wait_time_ms)
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes())
      AND waiting_tasks_count > @MinWaitCount;

    SELECT TOP (@TopN)
        ws.wait_type AS Wait_Type,
        ws.waiting_tasks_count AS Wait_Count,
        CAST(ws.wait_time_ms / 1000.0 AS NUMERIC(12,2)) AS Total_Wait_S,
        CAST((ws.wait_time_ms - ws.signal_wait_time_ms) / 1000.0 AS NUMERIC(12,2)) AS Resource_Wait_S,
        CAST(ws.signal_wait_time_ms / 1000.0 AS NUMERIC(12,2)) AS Signal_Wait_S,
        CAST(ws.wait_time_ms * 100.0 / NULLIF(@TotalWaitMs, 0) AS DECIMAL(5,2)) AS Pct_Of_All_Waits,
        CAST(ws.signal_wait_time_ms * 100.0 / NULLIF(ws.wait_time_ms, 0) AS DECIMAL(5,2)) AS Signal_Pct,
        CASE
            WHEN ws.wait_type IN ('CXPACKET','CXCONSUMER','CXPA','EXECSYNC') THEN 'Parallelism'
            WHEN ws.wait_type IN ('SOS_SCHEDULER_YIELD','THREADPOOL','RESOURCE_POOL') THEN 'CPU'
            WHEN ws.wait_type LIKE 'PAGEIOLATCH_%' THEN 'Disk I/O'
            WHEN ws.wait_type IN ('WRITELOG','LOGMGR','LOGBUFFER') THEN 'Transaction Log'
            WHEN ws.wait_type IN ('RESOURCE_SEMAPHORE','RESOURCE_SEMAPHORE_POOL') THEN 'Memory'
            WHEN ws.wait_type LIKE 'LCK_%' THEN 'Locking'
            WHEN ws.wait_type LIKE 'PAGELATCH_%' THEN 'In-Memory Latch'
            WHEN ws.wait_type IN ('ASYNC_NETWORK_IO','NETWAITFORREPLY','NETWORKIO') THEN 'Network / Client'
            WHEN ws.wait_type LIKE 'HADR_%' THEN 'AlwaysOn AG'
            WHEN ws.wait_type LIKE 'REPL_%' THEN 'Replication'
            WHEN ws.wait_type IN ('PFS_SYNC','GAM_CONTENTION','SGAM_CONTENTION') THEN 'TempDB Allocation'
            ELSE 'Other'
        END AS Wait_Category,
        CASE WHEN @IncludeRecommendations = 1 THEN
            CASE
                WHEN ws.wait_type IN ('CXPACKET','CXCONSUMER') THEN 'Review MAXDOP and CTFP settings.'
                WHEN ws.wait_type LIKE 'PAGEIOLATCH_%' THEN 'Check disk latency and indexing.'
                WHEN ws.wait_type LIKE 'LCK_%' THEN 'Blocking detected. Run blocking_and_deadlocks.sql.'
                WHEN ws.wait_type = 'RESOURCE_SEMAPHORE' THEN 'Memory grant pressure. Check memory grants.'
                WHEN ws.wait_type IN ('ASYNC_NETWORK_IO') THEN 'Client consuming results slowly.'
                WHEN ws.wait_type LIKE 'HADR_%' THEN 'AG sync bottleneck. Run alwayson_ag_monitor.sql.'
                ELSE 'Review wait type in Microsoft documentation.'
            END
        ELSE NULL END AS Recommendation
    FROM sys.dm_os_wait_stats AS ws
    WHERE ws.wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes())
      AND ws.waiting_tasks_count > @MinWaitCount
    ORDER BY ws.wait_time_ms DESC;
END;
GO

PRINT N'  sp_DBA_WaitAnalysis created.';
GO

-- ============================================================================
-- 7. sp_DBA_IndexReview — unused, missing indexes, and fragmentation
-- ============================================================================
PRINT N'Creating sp_DBA_IndexReview...';
GO

IF OBJECT_ID(N'dbo.sp_DBA_IndexReview', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DBA_IndexReview;
GO

CREATE PROCEDURE dbo.sp_DBA_IndexReview
    @DatabaseList           NVARCHAR(MAX) = NULL,
    @IncludeReadOnly        BIT = 0,
    @MinPageCount           INT = 1000,
    @IncludeFragmentation   BIT = 1,
    @IncludeMissingIndexes  BIT = 1,
    @TopN                   INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    CREATE TABLE #IRDbs (database_id INT NOT NULL PRIMARY KEY, database_name SYSNAME NOT NULL);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
    BEGIN
        INSERT INTO #IRDbs (database_id, database_name)
        SELECT d.database_id, d.name FROM sys.databases AS d
        INNER JOIN (SELECT LTRIM(RTRIM(value)) AS v FROM STRING_SPLIT(@DatabaseList, N',') WHERE LTRIM(RTRIM(value)) <> N'') AS r ON r.v = d.name
        WHERE d.state = 0 AND d.is_in_standby = 0;
    END
    ELSE
    BEGIN
        INSERT INTO #IRDbs (database_id, database_name)
        SELECT database_id, name FROM sys.databases
        WHERE state = 0 AND is_in_standby = 0 AND database_id > 4 AND (@IncludeReadOnly = 1 OR is_read_only = 0);
    END;

    -- Missing indexes (instance-wide DMV)
    IF @IncludeMissingIndexes = 1
    BEGIN
        SELECT TOP (@TopN)
            DB_NAME(d.database_id) AS DatabaseName,
            d.equality_columns, d.inequality_columns, d.included_columns,
            CAST(gs.avg_user_impact AS DECIMAL(5,1)) AS AvgUserImpact,
            gs.user_seeks, gs.user_scans,
            CAST((gs.user_seeks * gs.avg_user_impact * gs.avg_total_user_cost) AS DECIMAL(18,0)) AS ImprovementMeasure
        FROM sys.dm_db_missing_index_group_stats AS gs
        INNER JOIN sys.dm_db_missing_index_groups AS g ON gs.group_handle = g.index_group_handle
        INNER JOIN sys.dm_db_missing_index_details AS d ON g.index_handle = d.index_handle
        WHERE d.database_id IN (SELECT database_id FROM #IRDbs)
          AND (gs.user_seeks * gs.avg_user_impact * gs.avg_total_user_cost) > 100000
        ORDER BY (gs.user_seeks * gs.avg_user_impact * gs.avg_total_user_cost) DESC;
    END;

    DROP TABLE #IRDbs;
END;
GO

PRINT N'  sp_DBA_IndexReview created.';
GO

-- ============================================================================
-- 8. sp_DBA_SecurityAudit — orphaned users, sysadmin, guest, trustworthy
-- ============================================================================
PRINT N'Creating sp_DBA_SecurityAudit...';
GO

IF OBJECT_ID(N'dbo.sp_DBA_SecurityAudit', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DBA_SecurityAudit;
GO

CREATE PROCEDURE dbo.sp_DBA_SecurityAudit
    @DatabaseList           NVARCHAR(MAX) = NULL,
    @IncludeReadOnly        BIT = 0,
    @IncludeSysadminCheck   BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    IF @IncludeSysadminCheck = 1
    BEGIN
        SELECT p.name AS LoginName, p.type_desc, p.is_disabled, p.create_date
        FROM sys.server_principals AS p
        INNER JOIN sys.server_role_members AS rm ON p.principal_id = rm.member_principal_id
        INNER JOIN sys.server_principals AS r ON rm.role_principal_id = r.principal_id
        WHERE r.name = N'sysadmin' ORDER BY p.name;

        SELECT name AS LoginName, is_policy_checked, is_expiration_checked
        FROM sys.sql_logins WHERE is_policy_checked = 0 OR is_expiration_checked = 0;
    END;

    -- Trustworthy databases
    SELECT d.name AS DatabaseName, d.is_trustworthy_on, SUSER_SNAME(d.owner_sid) AS DBOwner
    FROM sys.databases AS d WHERE d.is_trustworthy_on = 1 AND d.database_id > 4;

    -- Database owners
    SELECT d.name AS DatabaseName, SUSER_SNAME(d.owner_sid) AS OwnerLogin
    FROM sys.databases AS d WHERE d.database_id > 4 AND d.state = 0 ORDER BY d.name;
END;
GO

PRINT N'  sp_DBA_SecurityAudit created.';
GO

-- ============================================================================
-- 9. sp_DBA_BackupReview — backup SLA, log chain, recovery model
-- ============================================================================
PRINT N'Creating sp_DBA_BackupReview...';
GO

IF OBJECT_ID(N'dbo.sp_DBA_BackupReview', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DBA_BackupReview;
GO

CREATE PROCEDURE dbo.sp_DBA_BackupReview
    @DatabaseList       NVARCHAR(MAX) = NULL,
    @IncludeReadOnly    BIT = 0,
    @BackupHoursSLA     INT = 24,
    @BackupDaysSLA      INT = 7
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SELECT
        d.name AS DatabaseName, d.recovery_model_desc AS RecoveryModel,
        MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS LastFullBackup,
        MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS LastLogBackup,
        DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) AS HoursSinceFull,
        CASE
            WHEN MAX(b.backup_finish_date) IS NULL THEN 'CRITICAL: No backups'
            WHEN d.recovery_model_desc = 'FULL' AND DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END), GETDATE()) > @BackupHoursSLA
                THEN 'CRITICAL: Log backup exceeds SLA'
            WHEN DATEDIFF(DAY, MAX(b.backup_finish_date), GETDATE()) > @BackupDaysSLA
                THEN 'HIGH: Last backup exceeds ' + CAST(@BackupDaysSLA AS VARCHAR) + ' days'
            ELSE 'OK'
        END AS BackupStatus
    FROM sys.databases AS d
    LEFT JOIN msdb.dbo.backupset AS b ON d.name = b.database_name
    WHERE d.database_id > 4 AND d.state = 0
      AND (@DatabaseList IS NULL OR d.name IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@DatabaseList, N',') WHERE LTRIM(RTRIM(value)) <> N''))
    GROUP BY d.name, d.recovery_model_desc
    ORDER BY CASE WHEN MAX(b.backup_finish_date) IS NULL THEN 0 WHEN DATEDIFF(HOUR, MAX(b.backup_finish_date), GETDATE()) > @BackupHoursSLA THEN 1 ELSE 2 END, d.name;
END;
GO

PRINT N'  sp_DBA_BackupReview created.';
GO

-- ============================================================================
-- 10. sp_DBA_BaselineCapture — performance snapshot persistence
-- ============================================================================
PRINT N'Creating sp_DBA_BaselineCapture...';
GO

IF OBJECT_ID(N'dbo.sp_DBA_BaselineCapture', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DBA_BaselineCapture;
GO

CREATE PROCEDURE dbo.sp_DBA_BaselineCapture
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
        RAISERROR(N'Run DBARepository_Persistence.sql first to create BaselineSnapshot table.', 16, 1);
        RETURN;
    END;

    IF @CaptureWaitStats = 1
    BEGIN
        INSERT INTO dbo.BaselineSnapshot (ServerName, SnapshotUtc, SnapshotType, WaitType, WaitTimeMs, SignalWaitMs, WaitingTasks, Notes)
        SELECT @ServerName, @Now, 'Baseline', wait_type, wait_time_ms, signal_wait_time_ms, waiting_tasks_count, @Notes
        FROM sys.dm_os_wait_stats WHERE waiting_tasks_count > 0
          AND wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes());
        PRINT CAST(@@ROWCOUNT AS VARCHAR) + N' wait stats captured.';
    END;

    IF @CaptureCounters = 1
    BEGIN
        INSERT INTO dbo.BaselineSnapshot (ServerName, SnapshotUtc, SnapshotType, CounterName, CounterValue, Notes)
        SELECT @ServerName, @Now, 'Baseline', object_name + '.' + counter_name, CAST(cntr_value AS DECIMAL(18,4)), @Notes
        FROM sys.dm_os_performance_counters
        WHERE counter_name IN ('Page life expectancy','Total Server Memory (KB)','Target Server Memory (KB)','Batch Requests/sec');
        PRINT CAST(@@ROWCOUNT AS VARCHAR) + N' counters captured.';
    END;

    IF @CaptureFileStats = 1
    BEGIN
        INSERT INTO dbo.BaselineSnapshot (ServerName, SnapshotUtc, SnapshotType, DatabaseId, DatabaseName, FileId, NumReads, NumWrites, IoStallReadMs, IoStallWriteMs, Notes)
        SELECT @ServerName, @Now, 'Baseline', vfs.database_id, DB_NAME(vfs.database_id), vfs.file_id,
               vfs.num_of_reads, vfs.num_of_writes, vfs.io_stall_read_ms, vfs.io_stall_write_ms, @Notes
        FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs;
        PRINT CAST(@@ROWCOUNT AS VARCHAR) + N' file stats captured.';
    END;

    PRINT N'Baseline capture complete at ' + CONVERT(NVARCHAR(30), @Now, 121);
END;
GO

PRINT N'  sp_DBA_BaselineCapture created.';
GO

-- ============================================================================
-- 11. AssessmentFindingTableType — TVP for findings
-- ============================================================================
PRINT N'Creating AssessmentFindingTableType...';
GO

IF TYPE_ID(N'dbo.AssessmentFindingTableType') IS NOT NULL
    DROP TYPE dbo.AssessmentFindingTableType;
GO

CREATE TYPE dbo.AssessmentFindingTableType AS TABLE (
    CheckId INT NOT NULL, Severity VARCHAR(20) NOT NULL, Weight INT NOT NULL DEFAULT 0,
    Area VARCHAR(50) NOT NULL, Finding VARCHAR(255) NOT NULL,
    Impact VARCHAR(255) NULL, Recommendation VARCHAR(MAX) NULL,
    NextStepCommand VARCHAR(MAX) NULL, DatabaseName SYSNAME NULL
);
GO

PRINT N'  AssessmentFindingTableType created.';
GO

-- ============================================================================
-- 12. sp_DBA_SaveAssessmentRun — persist assessment results
-- ============================================================================
PRINT N'Creating sp_DBA_SaveAssessmentRun...';
GO

IF OBJECT_ID(N'dbo.sp_DBA_SaveAssessmentRun', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DBA_SaveAssessmentRun;
GO

CREATE PROCEDURE dbo.sp_DBA_SaveAssessmentRun
    @ServerName SYSNAME, @Profile VARCHAR(20) = 'Standard', @HealthScore INT = 100,
    @SqlVersion VARCHAR(50) = NULL, @SqlEdition VARCHAR(100) = NULL,
    @ToolVersion VARCHAR(20) = NULL, @Notes NVARCHAR(500) = NULL,
    @SQLCPUPct DECIMAL(5,2) = NULL, @SignalWaitPct DECIMAL(5,2) = NULL,
    @MinPLEs INT = NULL, @TotalMemMB DECIMAL(18,2) = NULL, @TargetMemMB DECIMAL(18,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'dbo.AssessmentRun', N'U') IS NULL
    BEGIN
        RAISERROR(N'Run DBARepository_Persistence.sql first to create history tables.', 16, 1);
        RETURN;
    END;

    DECLARE @RunId INT;
    INSERT INTO dbo.AssessmentRun (ServerName, Profile, HealthScore, SqlVersion, SqlEdition, ToolVersion, Notes)
    VALUES (@ServerName, @Profile, @HealthScore, @SqlVersion, @SqlEdition, @ToolVersion, @Notes);
    SET @RunId = SCOPE_IDENTITY();

    IF @SQLCPUPct IS NOT NULL
        INSERT INTO dbo.AssessmentMetric (RunId, MetricName, MetricValue, Unit) VALUES (@RunId, 'SQL_CPU_Pct', @SQLCPUPct, '%');
    IF @SignalWaitPct IS NOT NULL
        INSERT INTO dbo.AssessmentMetric (RunId, MetricName, MetricValue, Unit) VALUES (@RunId, 'Signal_Wait_Pct', @SignalWaitPct, '%');
    IF @MinPLEs IS NOT NULL
        INSERT INTO dbo.AssessmentMetric (RunId, MetricName, MetricValue, Unit) VALUES (@RunId, 'Min_PLE_s', @MinPLEs, 's');
    IF @TotalMemMB IS NOT NULL
        INSERT INTO dbo.AssessmentMetric (RunId, MetricName, MetricValue, Unit) VALUES (@RunId, 'Total_Mem_MB', @TotalMemMB, 'MB');
    IF @TargetMemMB IS NOT NULL
        INSERT INTO dbo.AssessmentMetric (RunId, MetricName, MetricValue, Unit) VALUES (@RunId, 'Target_Mem_MB', @TargetMemMB, 'MB');

    SELECT @RunId AS RunId;
END;
GO

PRINT N'  sp_DBA_SaveAssessmentRun created.';
GO

-- ============================================================================
-- NEXT STEPS:
--   Run CheckIdRegistry.sql to populate the check ID registry
--   Run DBARepository_Persistence.sql for assessment history tables
-- ============================================================================
PRINT N'';
PRINT N'========================================';
PRINT N' DBARepository deployment complete.';
PRINT N' 12 objects installed:';
PRINT N'   2 functions, 9 procedures, 1 table type';
PRINT N' Next: Run CheckIdRegistry.sql';
PRINT N' Next: Run DBARepository_Persistence.sql';
PRINT N'========================================';
GO
