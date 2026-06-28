/*
================================================================================
sp_DBA_HealthCheck - One-Stop Diagnostic Engine (Enterprise Edition)
================================================================================
Prerequisites: Deploy framework objects first (00_Framework/00_Deploy_Framework.ps1).

Usage:
    EXEC dbo.sp_DBA_HealthCheck @DeepDive = 0;
    EXEC dbo.sp_DBA_HealthCheck @DeepDive = 1, @DatabaseList = N'SalesDB,HRDB';
    EXEC dbo.sp_DBA_HealthCheck @BackupHoursSLA = 48;
================================================================================
*/
IF OBJECT_ID(N'dbo.sp_DBA_HealthCheck', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DBA_HealthCheck AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_DBA_HealthCheck
    @DeepDive           BIT = 0,
    @DatabaseList       NVARCHAR(MAX) = NULL,
    @IncludeReadOnly    BIT = 0,
    @BackupHoursSLA     INT = 24
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    IF OBJECT_ID(N'dbo.fn_DBA_ExcludedWaitTypes', N'IF') IS NULL
    BEGIN
        RAISERROR(N'Run 00_Framework/00_Deploy_Framework.ps1 (-ServerInstance . -Database master) to auto-deploy all required objects, or deploy sp_DBA_HealthCheck and fn_DBA_ExcludedWaitTypes manually.', 16, 1);
        RETURN;
    END;

    IF OBJECT_ID(N'tempdb..#DBAFindings') IS NOT NULL DROP TABLE #DBAFindings;
    CREATE TABLE #DBAFindings (
        [CheckId] INT,
        [Severity] VARCHAR(20),
        [Weight] INT,
        [Area] VARCHAR(50),
        [Finding] VARCHAR(255),
        [Impact] VARCHAR(255),
        [Recommendation] VARCHAR(MAX),
        [NextStepCommand] VARCHAR(MAX)
    );

    DECLARE @SQLServerCPU INT, @SystemIdle INT, @OtherCPU INT;
    DECLARE @SignalWaitPct DECIMAL(5,2);
    DECLARE @PLE INT, @TargetMem BIGINT, @TotalMem BIGINT;
    DECLARE @CTFP INT, @MAXDOP INT;
    DECLARE @ProductVersion NVARCHAR(128) = CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128));
    DECLARE @MajorVersion INT = CAST(LEFT(@ProductVersion, CHARINDEX(N'.', @ProductVersion) - 1) AS INT);
    DECLARE @db_id_loop INT;
    DECLARE @db_name_loop SYSNAME;
    DECLARE @DynamicSQL_Loop NVARCHAR(MAX);
    DECLARE @DbQuoted NVARCHAR(260);

    IF OBJECT_ID(N'tempdb..#HealthCheckDbs') IS NOT NULL DROP TABLE #HealthCheckDbs;
    CREATE TABLE #HealthCheckDbs (database_id INT NOT NULL PRIMARY KEY, database_name SYSNAME NOT NULL);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
    BEGIN
        INSERT INTO #HealthCheckDbs (database_id, database_name)
        SELECT d.database_id, d.name
        FROM sys.databases AS d
        INNER JOIN (
            SELECT LTRIM(RTRIM(value)) AS database_name
            FROM STRING_SPLIT(@DatabaseList, N',')
            WHERE LTRIM(RTRIM(value)) <> N''
        ) AS requested ON requested.database_name = d.name
        WHERE d.state = 0 AND d.is_in_standby = 0;
    END
    ELSE
    BEGIN
        INSERT INTO #HealthCheckDbs (database_id, database_name)
        SELECT database_id, name
        FROM sys.databases
        WHERE state = 0
          AND is_in_standby = 0
          AND database_id > 4
          AND (@IncludeReadOnly = 1 OR is_read_only = 0);
    END;

    ----------------------------------------------------------------------------
    -- 1. CPU Utilization & Scheduling
    ----------------------------------------------------------------------------
    DECLARE @ts_now BIGINT = (SELECT cpu_ticks / (cpu_ticks / ms_ticks) FROM sys.dm_os_sys_info);

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

    IF EXISTS (SELECT 1 FROM sys.dm_os_schedulers WHERE runnable_tasks_count > 10 AND status = N'VISIBLE ONLINE')
        INSERT INTO #DBAFindings VALUES (101, N'High', 15, N'CPU', N'High Runnable Task Count', N'Queries are waiting for CPU cycles.', N'Check sys.dm_os_schedulers for specific hotspots.', N'SELECT * FROM sys.dm_os_schedulers WHERE status = ''VISIBLE ONLINE'';');

    SELECT @SignalWaitPct = CAST(CAST(SUM(signal_wait_time_ms) AS NUMERIC(18,2)) / NULLIF(SUM(wait_time_ms), 0) * 100 AS DECIMAL(5,2))
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes());

    IF @SQLServerCPU > 80
        INSERT INTO #DBAFindings VALUES (102, N'High', 20, N'CPU', N'High SQL Server CPU Utilization (' + CAST(@SQLServerCPU AS VARCHAR(10)) + N'%)', N'Query performance degradation.', N'Historical CPU from ring buffers. Threshold > 80%.', N'SELECT TOP 10 * FROM sys.dm_exec_query_stats ORDER BY total_worker_time DESC;');

    IF @OtherCPU > 20
        INSERT INTO #DBAFindings VALUES (103, N'Medium', 10, N'CPU', N'High External CPU Usage (' + CAST(@OtherCPU AS VARCHAR(10)) + N'%)', N'Steals cycles from SQL Server.', N'Check antivirus, backup agents, or other host processes.', NULL);

    IF @SignalWaitPct > 25
        INSERT INTO #DBAFindings VALUES (104, N'High', 15, N'CPU', N'High Signal Waits (' + CAST(@SignalWaitPct AS VARCHAR(10)) + N'%)', N'Severe CPU scheduling pressure.', N'Target signal waits < 25%. Review MAXDOP and CTFP.', NULL);

    DECLARE @AdHocPlanMB DECIMAL(10,2);
    SELECT @AdHocPlanMB = SUM(CAST(size_in_bytes AS BIGINT)) / 1024.0 / 1024.0
    FROM sys.dm_exec_cached_plans
    WHERE objtype = N'Adhoc' AND usecounts = 1;

    IF @AdHocPlanMB > 500
        INSERT INTO #DBAFindings VALUES (105, N'Low', 5, N'Performance', N'Plan Cache Bloat Detected (' + CAST(@AdHocPlanMB AS VARCHAR(20)) + N' MB)', N'Wasting memory on single-use plans.', N'Enable optimize for ad hoc workloads.', N'EXEC sp_configure ''optimize for ad hoc workloads'', 1; RECONFIGURE;');

    ----------------------------------------------------------------------------
    -- 2. Cross-Database Security & Best Practices
    ----------------------------------------------------------------------------
    SELECT @db_id_loop = MIN(database_id) FROM #HealthCheckDbs;

    WHILE @db_id_loop IS NOT NULL
    BEGIN
        SELECT @db_name_loop = database_name FROM #HealthCheckDbs WHERE database_id = @db_id_loop;
        SET @DbQuoted = QUOTENAME(@db_name_loop);

        BEGIN TRY
            IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id = @db_id_loop AND is_trustworthy_on = 1)
                INSERT INTO #DBAFindings VALUES (201, N'High', 15, N'Security', N'Trustworthy Database: ' + @db_name_loop, N'Privilege escalation risk.', N'Disable TRUSTWORTHY unless required.', N'ALTER DATABASE ' + @DbQuoted + N' SET TRUSTWORTHY OFF;');

            SET @DynamicSQL_Loop = N'USE ' + @DbQuoted + N';
                IF EXISTS (
                    SELECT 1 FROM sys.database_permissions AS p
                    INNER JOIN sys.database_principals AS pr ON p.grantee_principal_id = pr.principal_id
                    WHERE pr.name = N''guest'' AND p.permission_name = N''CONNECT'' AND p.state = N''G''
                )
                INSERT INTO #DBAFindings VALUES (202, N''Medium'', 10, N''Security'', N''Guest User Enabled in '' + DB_NAME(), N''Lateral movement risk.'', N''Revoke CONNECT from guest.'', N''USE ' + @DbQuoted + N'; REVOKE CONNECT FROM guest;'');';
            EXEC sys.sp_executesql @DynamicSQL_Loop;

            IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id = @db_id_loop AND page_verify_option_desc <> N'CHECKSUM')
                INSERT INTO #DBAFindings VALUES (203, N'Critical', 25, N'Best Practice', N'Page Verification not CHECKSUM: ' + @db_name_loop, N'Undetected corruption risk.', N'Set PAGE_VERIFY to CHECKSUM.', N'ALTER DATABASE ' + @DbQuoted + N' SET PAGE_VERIFY CHECKSUM;');

            IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id = @db_id_loop AND (is_auto_shrink_on = 1 OR is_auto_close_on = 1))
                INSERT INTO #DBAFindings VALUES (204, N'Critical', 20, N'Best Practice', N'Auto-Shrink/Close Enabled: ' + @db_name_loop, N'Performance spikes and fragmentation.', N'Disable AUTO_SHRINK and AUTO_CLOSE.', N'ALTER DATABASE ' + @DbQuoted + N' SET AUTO_SHRINK OFF, AUTO_CLOSE OFF;');

            SET @DynamicSQL_Loop = N'USE ' + @DbQuoted + N';
                IF EXISTS (
                    SELECT 1 FROM sys.dm_db_index_usage_stats AS s
                    INNER JOIN sys.indexes AS i ON s.object_id = i.object_id AND s.index_id = i.index_id
                    WHERE s.database_id = DB_ID() AND i.index_id > 1
                      AND s.user_updates > 10000
                      AND (s.user_seeks + s.user_scans + s.user_lookups) = 0
                )
                INSERT INTO #DBAFindings VALUES (205, N''Low'', 5, N''Indexes'', N''Unused Indexes in '' + DB_NAME(), N''Write overhead without read benefit.'', N''Validate since last restart before dropping.'', NULL);';
            EXEC sys.sp_executesql @DynamicSQL_Loop;

            IF @MajorVersion >= 11
            BEGIN
                SET @DynamicSQL_Loop = N'USE ' + @DbQuoted + N';
                    IF EXISTS (
                        SELECT 1 FROM sys.stats AS s
                        CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
                        WHERE OBJECTPROPERTY(s.object_id, N''IsUserTable'') = 1
                          AND CAST(sp.modification_counter AS DECIMAL(18,2)) / NULLIF(sp.rows, 0) > 0.2
                    )
                    INSERT INTO #DBAFindings VALUES (206, N''Medium'', 10, N''Statistics'', N''Stale Statistics in '' + DB_NAME(), N''Poor execution plans.'', N''UPDATE STATISTICS on affected tables.'', NULL);';
                EXEC sys.sp_executesql @DynamicSQL_Loop;
            END;

            IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id = @db_id_loop AND is_query_store_on = 1)
            BEGIN
                SET @DynamicSQL_Loop = N'USE ' + @DbQuoted + N';
                    IF EXISTS (SELECT 1 FROM sys.database_query_store_options WHERE actual_state_desc = N''READ_ONLY'')
                    INSERT INTO #DBAFindings VALUES (207, N''Medium'', 10, N''Advanced'', N''Query Store READ_ONLY: '' + DB_NAME(), N''Plan history capture stopped.'', N''Increase max_storage_size_mb or clean up Query Store.'', NULL);';
                EXEC sys.sp_executesql @DynamicSQL_Loop;
            END;

            IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id = @db_id_loop AND is_cdc_enabled = 1)
            BEGIN
                SET @DynamicSQL_Loop = N'USE ' + @DbQuoted + N';
                    IF EXISTS (SELECT 1 FROM sys.dm_cdc_log_scan_sessions WHERE latency > 3600)
                    INSERT INTO #DBAFindings VALUES (208, N''Medium'', 10, N''Advanced'', N''High CDC Latency in '' + DB_NAME(), N''Transaction log may not reuse.'', N''Review CDC job parameters and log reader throughput.'', NULL);';
                EXEC sys.sp_executesql @DynamicSQL_Loop;
            END;
        END TRY
        BEGIN CATCH
            INSERT INTO #DBAFindings VALUES (
                209, N'Medium', 5, N'Security',
                N'Could not audit database: ' + @db_name_loop,
                LEFT(ERROR_MESSAGE(), 200),
                N'Verify CONNECT permission and database accessibility.',
                NULL
            );
        END CATCH;

        SELECT @db_id_loop = MIN(database_id) FROM #HealthCheckDbs WHERE database_id > @db_id_loop;
    END;

    SELECT @CTFP = CAST(value_in_use AS INT) FROM sys.configurations WHERE name = N'cost threshold for parallelism';
    SELECT @MAXDOP = CAST(value_in_use AS INT) FROM sys.configurations WHERE name = N'max degree of parallelism';

    IF @CTFP = 5
        INSERT INTO #DBAFindings VALUES (301, N'Medium', 10, N'Config', N'Default Cost Threshold for Parallelism (5)', N'Trivial queries may parallelize.', N'Increase CTFP to at least 50.', N'EXEC sp_configure ''cost threshold for parallelism'', 50; RECONFIGURE;');

    IF @MAXDOP = 0
        INSERT INTO #DBAFindings VALUES (302, N'Medium', 10, N'Config', N'MAXDOP is 0', N'Single query may use all CPUs.', N'Set MAXDOP per NUMA (often capped at 8).', NULL);

    IF (SELECT value_in_use FROM sys.configurations WHERE name = N'optimize for ad hoc workloads') = 0
        INSERT INTO #DBAFindings VALUES (303, N'Low', 5, N'Config', N'Optimize for Ad Hoc Workloads is OFF', N'Plan cache bloat risk.', N'Enable optimize for ad hoc workloads.', N'EXEC sp_configure ''optimize for ad hoc workloads'', 1; RECONFIGURE;');

    IF (SELECT value_in_use FROM sys.configurations WHERE name = N'backup compression default') = 0
        INSERT INTO #DBAFindings VALUES (304, N'Low', 5, N'Config', N'Backup Compression Default is OFF', N'Larger, slower backups.', N'Enable backup compression default.', N'EXEC sp_configure ''backup compression default'', 1; RECONFIGURE;');

    IF (SELECT value_in_use FROM sys.configurations WHERE name = N'remote admin connections') = 0
        INSERT INTO #DBAFindings VALUES (305, N'Medium', 10, N'Config', N'Dedicated Admin Connection (DAC) is OFF', N'Cannot connect when instance is hung.', N'Enable remote admin connections.', N'EXEC sp_configure ''remote admin connections'', 1; RECONFIGURE;');

    IF COL_LENGTH(N'sys.dm_server_services', N'instant_file_initialization_enabled') IS NOT NULL
       AND EXISTS (
            SELECT 1 FROM sys.dm_server_services
            WHERE instant_file_initialization_enabled = N'N'
              AND (servicename LIKE N'SQL Server (%)' OR servicename = N'MSSQLSERVER')
        )
        INSERT INTO #DBAFindings VALUES (306, N'Medium', 10, N'OS', N'Instant File Initialization (IFI) is DISABLED', N'Slow file growth and restores.', N'Grant Perform Volume Maintenance Tasks to service account.', NULL);

    IF COL_LENGTH(N'sys.dm_os_sys_info', N'sql_memory_model_desc') IS NOT NULL
       AND EXISTS (SELECT 1 FROM sys.dm_os_sys_info WHERE sql_memory_model_desc = N'CONVENTIONAL')
        INSERT INTO #DBAFindings VALUES (307, N'Medium', 10, N'OS', N'Locked Pages in Memory (LPIM) not active', N'OS may page SQL Server memory.', N'Consider Lock Pages in Memory if memory pressure occurs.', NULL);

    ----------------------------------------------------------------------------
    -- 3. Memory
    ----------------------------------------------------------------------------
    SELECT @TargetMem = cntr_value / 1024 FROM sys.dm_os_performance_counters WHERE counter_name = N'Target Server Memory (KB)';
    SELECT @TotalMem = cntr_value / 1024 FROM sys.dm_os_performance_counters WHERE counter_name = N'Total Server Memory (KB)';
    SELECT @PLE = MIN(cntr_value) FROM sys.dm_os_performance_counters WHERE object_name LIKE N'%Buffer Manager%' AND counter_name = N'Page life expectancy';

    IF @TotalMem < (@TargetMem * 0.9)
        INSERT INTO #DBAFindings VALUES (401, N'High', 15, N'Memory', N'SQL Server not reaching Target Memory', N'Possible OS memory pressure.', N'Review max server memory and host RAM.', NULL);

    DECLARE @PLEThreshold INT = CASE WHEN @TotalMem > 0 THEN (@TotalMem / 1024 / 4) * 150 ELSE 300 END;
    IF @PLE < @PLEThreshold
        INSERT INTO #DBAFindings VALUES (402, N'Medium', 10, N'Memory', N'Low Page Life Expectancy (' + CAST(@PLE AS VARCHAR(10)) + N's)', N'Buffer pool churn.', N'Check scans, missing indexes, memory grants.', NULL);

    IF EXISTS (SELECT 1 FROM sys.dm_exec_query_memory_grants)
        INSERT INTO #DBAFindings VALUES (403, N'High', 20, N'Memory', N'Active Memory Grant Waits', N'Queries waiting for memory to execute.', N'Optimize sorts/hashes or add RAM.', N'SELECT * FROM sys.dm_exec_query_memory_grants;');

    ----------------------------------------------------------------------------
    -- 4. Wait Statistics (Top 30)
    ----------------------------------------------------------------------------
    IF OBJECT_ID(N'tempdb..#TopWaits') IS NOT NULL DROP TABLE #TopWaits;
    SELECT TOP (30)
        wait_type,
        wait_time_ms / 1000.0 AS [Wait_S],
        (wait_time_ms - signal_wait_time_ms) / 1000.0 AS [Resource_S],
        signal_wait_time_ms / 1000.0 AS [Signal_S],
        waiting_tasks_count AS [Wait_Count],
        CAST(wait_time_ms * 100.0 / SUM(wait_time_ms) OVER() AS DECIMAL(5,2)) AS [Percentage],
        CASE
            -- Parallelism
            WHEN wait_type = N'CXPACKET' THEN N'Parallelism coordinator waiting on worker threads. Normal when mixed with CXCONSUMER. If dominant, check cost threshold for parallelism (default 5). Consider raising CTFP to 50-200 to reduce unnecessary parallelism.'
            WHEN wait_type = N'CXCONSUMER' THEN N'Parallelism consumer waiting on producers. Often benign — a row is being passed between parallel operators. Investigate only when CXPACKET+CXCONSUMER together exceed 30% of total waits.'
            WHEN wait_type = N'EXECSYNC' THEN N'Parallel thread waiting for another thread to produce rows. High values suggest a single slow parallel operator. Check the plan for expensive sorts, hashes, or scans feeding the gather.'
            -- CPU / Scheduling
            WHEN wait_type = N'SOS_SCHEDULER_YIELD' THEN N'Thread voluntarily yielded its 4ms quantum — normal under CPU-bound workloads. Investigate when > 25% of total waits. Check for query plan regressions, missing indexes, or CPU-hungry cursors.'
            WHEN wait_type = N'THREADPOOL' THEN N'No worker thread available to run a task. Classic symptom of max worker thread starvation. Check sys.dm_os_schedulers for runnable_task_count. May need to increase max worker threads or fix a parallelism leak.'
            WHEN wait_type = N'RESOURCE_POOL' THEN N'Task waiting for a resource pool to yield capacity. Common with Resource Governor throttling. Review RG workload group limits or disable temporarily for testing.'
            WHEN wait_type = N'PREEMPTIVE_OS_AUTHENTICATIONOPS' THEN N'Waiting on Windows/AD authentication (LogonUser, NegotiateSecurityContext). Indicates slow domain controller or Kerberos issues. Check network latency to DC and DNS resolution.'
            WHEN wait_type = N'PREEMPTIVE_OS_WRITEFILE' THEN N'Waiting on an OS-level WriteFile call outside SQL scheduler control. Typically backup/restore or file initialization. Check I/O subsystem and Enable Instant File Initialization.'
            -- Disk I/O
            WHEN wait_type = N'PAGEIOLATCH_SH' THEN N'Shared latch on a data page being read from disk into buffer pool. High values indicate slow disk I/O or memory pressure causing excessive page reads. Run disk_latency.sql to identify hot files.'
            WHEN wait_type = N'PAGEIOLATCH_EX' THEN N'Exclusive latch on a data page during physical read. Often seen with large table scans or poor indexing. Check for missing clustered indexes and large table scans in plan cache.'
            WHEN wait_type = N'PAGEIOLATCH_UP' THEN N'Latch while modifying a page that is currently being read from disk. Indicates I/O subsystem contention. Check disk latency and review write-heavy operations.'
            WHEN wait_type = N'WRITELOG' THEN N'Waiting for transaction log records to be flushed to disk. High values suggest log file on slow storage, large VLF count, or heavy DML. Move log to fast storage and check VLF count.'
            WHEN wait_type = N'LOGBUFFER' THEN N'Waiting for space in the log buffer to write log records. Indicates log contention — often from very large transactions or autogrowth events. Split large transactions and pre-grow the log file.'
            WHEN wait_type = N'LOGMGR' THEN N'Waiting for log buffer flush to complete. Related to WRITELOG. Check log file location, VLF count, and whether log autogrowth is occurring frequently.'
            -- Memory
            WHEN wait_type = N'RESOURCE_SEMAPHORE' THEN N'Query is waiting for a memory grant to execute a memory-consuming operator (sort/hash). High values mean large queries are starving each other. Check sys.dm_exec_query_memory_grants and consider query optimization or adding RAM.'
            WHEN wait_type = N'RESOURCE_SEMAPHORE_POOL' THEN N'Query waiting for a thread pool grant. Often caused by max degree of parallelism set too high. Review DOP settings and check for plans that request excessive parallelism.'
            WHEN wait_type = N'MEMORY_ALLOCATION_EXTENSIONS' THEN N'Waiting for extended memory allocation beyond normal pool. Seen on servers with max server memory configured too low or during large memory grant requests.'
            -- Locking / Blocking
            WHEN wait_type = N'LCK_M_X' THEN N'Exclusive lock waiting to modify a row/page/table. Indicates blocking — find the head blocker using sys.dm_exec_requests joined to sys.dm_tran_locks. Check for long-running transactions and missing indexes.'
            WHEN wait_type = N'LCK_M_S' THEN N'Shared lock waiting for a resource held by an exclusive lock. Common with update operations blocking reads. Consider NOLOCK hints, snapshot isolation, or reducing transaction duration.'
            WHEN wait_type = N'LCK_M_U' THEN N'Update lock waiting for a shared lock held by another session. Often a precursor to deadlocks. Check for concurrent update patterns on the same rows.'
            WHEN wait_type = N'PAGELATCH_EX' THEN N'Exclusive in-memory latch on a buffer page. High values indicate hot-page contention — most commonly TempDB allocation pages (PFS/GAM/SGAM). Check tempdb_configuration.sql.'
            WHEN wait_type = N'PAGELATCH_SH' THEN N'Shared in-memory latch contention on a buffer page. Multiple sessions reading the same page simultaneously. If in tempdb, check allocation contention. If in user DB, review hot-page access patterns.'
            -- Network / Client
            WHEN wait_type = N'ASYNC_NETWORK_IO' THEN N'SQL Server has results ready but the client is slow to consume them. Check application-side fetch patterns, cursor usage, or network latency. Common with SSMS result grid rendering or large unbounded result sets.'
            WHEN wait_type = N'NETWAITFORREPLY' THEN N'Waiting for a network reply from a linked server or Service Broker. Indicates linked server latency. Check linked server connectivity and query the remote server health.'
            -- AlwaysOn AG
            WHEN wait_type = N'HADR_SYNC_COMMIT' THEN N'Primary replica waiting for secondary replica(s) to confirm log hardening. Indicates secondary replica lagging behind. Check secondary disk I/O, redo thread speed, and network latency between replicas.'
            WHEN wait_type = N'HADR_FILESTREAM_IOMGR_IOCOMPLETION' THEN N'FILESTREAM I/O completion wait in AlwaysOn AG. Indicates FILESTREAM data being synchronized to secondaries. Check FILESTREAM filegroup I/O performance on both primary and secondary.'
            WHEN wait_type = N'HADR_LOGCAPTURE_WAIT' THEN N'Log capture thread waiting for new log records. Normal during idle periods. If high during active workload, check log send queue size and secondary redo rate.'
            WHEN wait_type = N'HADR_WORK_QUEUE' THEN N'AG redo thread waiting for work from the log redo queue. If the redo queue is large, the secondary may be falling behind. Check secondary resource contention and network bandwidth.'
            WHEN wait_type = N'WAITFOR' THEN N'Session explicitly waiting via WAITFOR command or Service Broker dialog. If unexpected, check for application WAITFOR DELAY patterns or idle Service Broker conversations.'
            WHEN wait_type = N'BROKER_EVENTHANDLER' THEN N'Service Broker internal event handler waiting. Usually normal. If excessive, check for stuck or orphaned Service Broker conversations using sys.conversation_endpoints.'
            ELSE N'Check Microsoft Docs: https://learn.microsoft.com/en-us/sql/relational-databases/system-dm-views/sys-dm-os-wait-stats'
        END AS [Expert_Note]
    INTO #TopWaits
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (SELECT wait_type FROM dbo.fn_DBA_ExcludedWaitTypes())
      AND waiting_tasks_count > 0
    ORDER BY wait_time_ms DESC;

    IF EXISTS (SELECT 1 FROM #TopWaits WHERE wait_type LIKE N'LCK%' AND Percentage > 10)
        INSERT INTO #DBAFindings VALUES (501, N'Critical', 25, N'Performance', N'High Locking/Blocking Waits', N'Application timeouts likely.', N'Identify head blocker and tune transactions.', N'-- Run 04_Performance_Diagnostics/blocking_and_deadlocks.sql');

    IF EXISTS (SELECT 1 FROM #TopWaits WHERE wait_type = N'PAGEIOLATCH_SH' AND Percentage > 20)
        INSERT INTO #DBAFindings VALUES (502, N'High', 15, N'Performance', N'High Disk Read Waits (PAGEIOLATCH_SH)', N'Slow I/O or memory pressure.', N'Check disk latency and indexing.', N'-- Run 01_Server_OS/disk_latency.sql');

    IF EXISTS (SELECT 1 FROM #TopWaits WHERE wait_type = N'RESOURCE_SEMAPHORE')
        INSERT INTO #DBAFindings VALUES (503, N'High', 20, N'Memory', N'Query Memory Grant Starvation', N'Large queries waiting for grants.', N'Optimize memory-heavy plans.', NULL);

    ----------------------------------------------------------------------------
    -- 5. Storage Engine
    ----------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM sys.dm_io_virtual_file_stats(NULL, NULL)
        WHERE (io_stall_read_ms / NULLIF(num_of_reads, 0) > 20)
           OR (io_stall_write_ms / NULLIF(num_of_writes, 0) > 20)
    )
        INSERT INTO #DBAFindings VALUES (601, N'High', 15, N'I/O', N'High Disk Latency Detected (>20ms)', N'Slow query response.', N'Analyze per-file stalls.', N'-- Run 01_Server_OS/disk_latency.sql');

    IF @MajorVersion >= 13
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM sys.databases AS d
            INNER JOIN #HealthCheckDbs AS hc ON hc.database_id = d.database_id
            CROSS APPLY (SELECT COUNT(*) AS vlf_count FROM sys.dm_db_log_info(d.database_id)) AS v
            WHERE v.vlf_count >= 1000
        )
            INSERT INTO #DBAFindings VALUES (602, N'High', 15, N'Storage', N'Critical VLF Count (>=1000)', N'Slow recovery and log backups.', N'Rebuild log with large growth increments.', N'-- Run 03_Storage_Engine/vlf_fragmentation.sql');

        IF EXISTS (
            SELECT 1
            FROM sys.databases AS d
            INNER JOIN #HealthCheckDbs AS hc ON hc.database_id = d.database_id
            CROSS APPLY (SELECT COUNT(*) AS vlf_count FROM sys.dm_db_log_info(d.database_id)) AS v
            WHERE v.vlf_count BETWEEN 200 AND 999
        )
            INSERT INTO #DBAFindings VALUES (603, N'Medium', 10, N'Storage', N'Elevated VLF Count (200-999)', N'Log operations may slow.', N'Plan log file maintenance.', N'-- Run 03_Storage_Engine/vlf_fragmentation.sql');
    END;

    IF (SELECT COUNT(*) FROM sys.master_files WHERE database_id = 2 AND type = 0) < 4
        INSERT INTO #DBAFindings VALUES (604, N'Medium', 10, N'TempDB', N'Few TempDB Data Files', N'Possible PAGELATCH contention.', N'Use 4-8 equal data files; add only if contention proven.', NULL);

    IF EXISTS (
        SELECT 1 FROM sys.master_files
        WHERE database_id = 2 AND type = 0
          AND growth <> (SELECT TOP (1) growth FROM sys.master_files WHERE database_id = 2 AND type = 0 ORDER BY file_id)
    )
        INSERT INTO #DBAFindings VALUES (605, N'High', 15, N'TempDB', N'Uneven TempDB File Growths', N'Proportional fill imbalance.', N'Equalize growth increments for all TempDB data files.', NULL);

    IF EXISTS (SELECT 1 FROM sys.master_files WHERE is_percent_growth = 1 AND database_id IN (SELECT database_id FROM #HealthCheckDbs))
        INSERT INTO #DBAFindings VALUES (606, N'Medium', 10, N'Storage', N'Percentage-based Autogrowth Enabled', N'Unpredictable growth pauses.', N'Switch to fixed MB growth.', NULL);

    ----------------------------------------------------------------------------
    -- 6. Missing Indexes (instance-wide DMV)
    ----------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM sys.dm_db_missing_index_group_stats AS gs
        INNER JOIN sys.dm_db_missing_index_groups AS g ON g.index_group_handle = gs.group_handle
        INNER JOIN sys.dm_db_missing_index_details AS d ON d.index_handle = g.index_handle
        INNER JOIN #HealthCheckDbs AS hc ON hc.database_id = d.database_id
        WHERE (gs.user_seeks * gs.avg_user_impact * gs.avg_total_user_cost) > 1000000
    )
        INSERT INTO #DBAFindings VALUES (701, N'Low', 5, N'Indexes', N'High-Impact Missing Indexes Detected', N'Optimizer sees large potential gains.', N'Validate manually before creating indexes.', N'-- Run 05_Index_Statistics/index_usage_efficiency.sql');

    ----------------------------------------------------------------------------
    -- 7. Backups
    ----------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM sys.databases AS d
        INNER JOIN #HealthCheckDbs AS hc ON hc.database_name = d.name
        LEFT JOIN (
            SELECT database_name, MAX(backup_finish_date) AS last_backup
            FROM msdb.dbo.backupset
            GROUP BY database_name
        ) AS b ON d.name = b.database_name
        WHERE d.state = 0
          AND (b.last_backup IS NULL OR DATEDIFF(HOUR, b.last_backup, GETDATE()) > @BackupHoursSLA)
    )
        INSERT INTO #DBAFindings VALUES (801, N'Critical', 30, N'Backups', N'Databases missing recent backups', N'Data loss risk.', N'Verify backup jobs and msdb history.', N'-- Run 06_HA_DR/backup_verification.sql');

    ----------------------------------------------------------------------------
    -- 8. Always On
    ----------------------------------------------------------------------------
    IF SERVERPROPERTY(N'IsHadrEnabled') = 1
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.dm_hadr_availability_replica_states WHERE synchronization_health_desc <> N'HEALTHY')
            INSERT INTO #DBAFindings VALUES (901, N'Critical', 25, N'AlwaysOn', N'Availability Group Replica Not Healthy', N'Failover or data loss risk.', N'Check sync state and redo/send queues.', N'-- Run 06_HA_DR/alwayson_ag_monitor.sql');
    END;

    ----------------------------------------------------------------------------
    -- Output
    ----------------------------------------------------------------------------
    DECLARE @HealthScore INT = 100 - (SELECT ISNULL(SUM(Weight), 0) FROM #DBAFindings);
    IF @HealthScore < 0 SET @HealthScore = 0;

    SELECT
        CheckId,
        CASE Severity
            WHEN N'Critical' THEN N'CRITICAL'
            WHEN N'High' THEN N'HIGH'
            WHEN N'Medium' THEN N'MEDIUM'
            WHEN N'Low' THEN N'LOW'
            ELSE N'INFO'
        END AS [Status],
        Area, Finding, Impact, Recommendation, NextStepCommand
    FROM #DBAFindings
    ORDER BY CASE Severity WHEN N'Critical' THEN 1 WHEN N'High' THEN 2 WHEN N'Medium' THEN 3 WHEN N'Low' THEN 4 ELSE 5 END, CheckId;

    SELECT
        @HealthScore AS [Health_Score],
        @SQLServerCPU AS [SQL_CPU_Pct],
        @SystemIdle AS [Sys_Idle_Pct],
        @SignalWaitPct AS [Signal_Wait_Pct],
        @PLE AS [Min_PLE_s],
        @PLEThreshold AS [PLE_Threshold_s],
        @TotalMem AS [Total_Mem_MB],
        @TargetMem AS [Target_Mem_MB],
        sqlserver_start_time AS [Instance_Start_Time]
    FROM sys.dm_os_sys_info;

    IF @DeepDive = 1 OR EXISTS (SELECT 1 FROM #TopWaits WHERE Percentage > 10)
    BEGIN
        SELECT N'WAIT STATISTICS ENCYCLOPEDIA (TOP 30)' AS [Category];
        SELECT wait_type, [Wait_S], [Percentage], Expert_Note FROM #TopWaits ORDER BY [Wait_S] DESC;
    END;

    IF @DeepDive = 1 OR @SQLServerCPU > 80 OR @SignalWaitPct > 25
    BEGIN
        SELECT N'TOP CPU CONSUMING QUERIES' AS [Category];
        SELECT TOP (10)
            qs.execution_count,
            qs.total_worker_time / 1000 AS [Total_CPU_ms],
            (qs.total_worker_time / NULLIF(qs.execution_count, 0)) / 1000 AS [Avg_CPU_ms],
            SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
                ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS [Query_Text],
            qp.query_plan
        FROM sys.dm_exec_query_stats AS qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
        CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
        ORDER BY qs.total_worker_time DESC;
    END;

    IF @DeepDive = 1 OR EXISTS (SELECT 1 FROM sys.dm_io_virtual_file_stats(NULL, NULL) WHERE io_stall_read_ms / NULLIF(num_of_reads, 0) > 20)
    BEGIN
        SELECT N'DISK LATENCY PER FILE (TOP 10)' AS [Category];
        SELECT TOP (10)
            DB_NAME(vfs.database_id) AS [DB],
            mf.name,
            CAST(vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) AS NUMERIC(10,1)) AS [Read_Stall_ms],
            CAST(vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) AS NUMERIC(10,1)) AS [Write_Stall_ms]
        FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
        INNER JOIN sys.master_files AS mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
        ORDER BY (vfs.io_stall / NULLIF(vfs.num_of_reads + vfs.num_of_writes, 0)) DESC;
    END;

    DROP TABLE #DBAFindings;
    DROP TABLE #HealthCheckDbs;
    IF OBJECT_ID(N'tempdb..#TopWaits') IS NOT NULL DROP TABLE #TopWaits;
END;
GO
