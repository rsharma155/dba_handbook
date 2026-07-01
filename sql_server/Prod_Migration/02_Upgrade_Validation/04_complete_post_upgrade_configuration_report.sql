/*
================================================================================
Complete Post-Upgrade Configuration & Performance Report
================================================================================
Purpose:
    Single-pass, read-only report for troubleshooting severe slowness after
    upgrading SQL Server — especially 2019 Express → 2025 Developer/Enterprise.

    Consolidates instance config, database settings, memory/CPU topology,
    waits, blocking, TempDB, I/O, OS integration, Query Store, and optimizer
    signals. Ends with prioritized findings, copy-paste remediation SQL, and
    a step-by-step action plan.

When to run:
    - First investigation on a slow post-upgrade server
    - Before changing any sp_configure or database settings
    - Save all result sets (Results to File) for support / change records

Sections:
    (1)–(16)  Diagnostic data collection
    (17)      Executive summary — findings with solutions
    (18)      Copy-paste remediation templates (review before executing)
    (19)      Step-by-step action plan

Criticality: Critical — run before changing settings
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @ReportTime DATETIME2(0) = SYSDATETIME();
DECLARE @Edition NVARCHAR(256) = CAST(SERVERPROPERTY(N'Edition') AS NVARCHAR(256));
DECLARE @EngineEdition INT = CAST(SERVERPROPERTY(N'EngineEdition') AS INT);
DECLARE @RAM_MB BIGINT = (SELECT physical_memory_kb / 1024 FROM sys.dm_os_sys_info);
DECLARE @CPU INT = (SELECT cpu_count FROM sys.dm_os_sys_info);
DECLARE @InstanceCompat INT =
    COALESCE(
        CAST(SERVERPROPERTY(N'ProductMajorVersion') AS INT),
        CAST(PARSENAME(CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)), 4) AS INT)
    ) * 10;
DECLARE @MaxServerMemoryMB INT = ISNULL(
    (SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = N'max server memory (MB)'), 0);
DECLARE @MaxDOP INT = ISNULL(
    (SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = N'max degree of parallelism'), 0);
DECLARE @CTFP INT = ISNULL(
    (SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = N'cost threshold for parallelism'), 5);
DECLARE @TempDBDataFiles INT = (SELECT COUNT(*) FROM tempdb.sys.database_files WHERE type = 0);
DECLARE @RecommendedTempDBFiles INT = CASE WHEN @CPU > 8 THEN 8 ELSE @CPU END;
DECLARE @SuggestedMaxMemMB INT = CAST(@RAM_MB * 0.85 AS INT);
DECLARE @SuggestedMAXDOP INT = CASE WHEN @CPU > 8 THEN 8 WHEN @CPU < 1 THEN 1 ELSE @CPU END;
DECLARE @OSReserveMB INT = CASE WHEN @RAM_MB >= 32768 THEN 8192 WHEN @RAM_MB >= 16384 THEN 4096 ELSE 2048 END;

CREATE TABLE #Findings (
    Sort_Order      INT             NOT NULL,
    Severity        NVARCHAR(20)    NOT NULL,
    Category        NVARCHAR(60)    NOT NULL,
    Finding         NVARCHAR(500)   NOT NULL,
    What_To_Do      NVARCHAR(1000)  NOT NULL,
    Solution_SQL    NVARCHAR(MAX)   NULL,
    Next_Script     NVARCHAR(200)   NULL
);

-- ============================================================================
PRINT '================================================================================';
PRINT '  COMPLETE POST-UPGRADE CONFIGURATION & PERFORMANCE REPORT';
PRINT '  Generated: ' + CONVERT(NVARCHAR(30), @ReportTime, 120);
PRINT '  Server:    ' + @@SERVERNAME;
PRINT '  Scenario:  2019 Express → 2025 Developer/Enterprise slowness triage';
PRINT '================================================================================';

-- ============================================================================
-- (1) INSTANCE IDENTITY
-- ============================================================================
PRINT '';
PRINT '=== (1) INSTANCE IDENTITY ===';
SELECT
    @ReportTime AS [Report_Time],
    @@SERVERNAME AS [Server_Name],
    CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)) AS [Product_Version],
    CAST(SERVERPROPERTY(N'ProductLevel') AS NVARCHAR(128)) AS [Product_Level],
    CAST(SERVERPROPERTY(N'ProductUpdateLevel') AS NVARCHAR(128)) AS [Update_Level],
    CAST(SERVERPROPERTY(N'ProductBuild') AS NVARCHAR(128)) AS [Build],
    @Edition AS [Edition],
    @EngineEdition AS [Engine_Edition_ID],
    CAST(SERVERPROPERTY(N'Collation') AS NVARCHAR(256)) AS [Instance_Collation],
    CAST(SERVERPROPERTY(N'IsClustered') AS INT) AS [Is_Clustered],
    si.sqlserver_start_time AS [SQL_Start_Time],
    DATEDIFF(MINUTE, si.sqlserver_start_time, SYSDATETIME()) AS [Uptime_Minutes],
    CASE
        WHEN COL_LENGTH(N'sys.dm_os_sys_info', N'sql_memory_model_desc') IS NOT NULL
            THEN (SELECT TOP (1) sql_memory_model_desc FROM sys.dm_os_sys_info)
        ELSE N'N/A'
    END AS [SQL_Memory_Model],
    N'Next: review section (17) findings, then section (19) action plan' AS [What_To_Do]
FROM sys.dm_os_sys_info AS si;

-- ============================================================================
-- (2) EXPRESS → DEVELOPER ARTIFACT CHECK
-- ============================================================================
PRINT '';
PRINT '=== (2) EXPRESS → DEVELOPER EDITION ARTIFACT CHECK ===';
SELECT
    @Edition AS [Current_Edition],
    @EngineEdition AS [Engine_Edition_ID],
    CASE @EngineEdition
        WHEN 4 THEN N'CRITICAL: Still Express — engine RAM/CPU caps active'
        ELSE N'Not Express — engine-level caps removed; check sp_configure artifacts'
    END AS [Edition_Status],
    @MaxServerMemoryMB AS [Max_Server_Memory_MB],
    @RAM_MB AS [Physical_RAM_MB],
    @SuggestedMaxMemMB AS [Suggested_Max_Server_Memory_MB],
    CAST(@MaxServerMemoryMB * 100.0 / NULLIF(@RAM_MB, 0) AS DECIMAL(6,1)) AS [Max_Mem_Pct_of_RAM],
    CASE
        WHEN @EngineEdition <> 4 AND @MaxServerMemoryMB < @RAM_MB * 0.4
            THEN N'LIKELY POST-EXPRESS CAP: increase max server memory (see section 18 template 1)'
        WHEN @EngineEdition = 4
            THEN N'Express enforces ~1.4 GB buffer pool — complete edition upgrade first'
        ELSE N'Review against workload working set'
    END AS [Memory_Artifact_Note],
    CASE
        WHEN @EngineEdition = 4
            THEN N'1) Finish migration off Express. 2) Re-run this report.'
        WHEN @MaxServerMemoryMB < @RAM_MB * 0.4
            THEN N'1) Apply section 18 template 1 during maintenance window. 2) Monitor PLE and PAGEIOLATCH waits. 3) Re-run report.'
        ELSE N'No edition/memory artifact detected — continue to waits and database checks.'
    END AS [What_To_Do]
;

IF @EngineEdition = 4
    INSERT INTO #Findings VALUES (
        10, N'CRITICAL', N'Edition', N'Instance is still SQL Server Express',
        N'1) Verify license/install completed. 2) Confirm PRODUCTVERSION and Edition in SSMS. 3) Re-run this report after migration.',
        N'-- Confirm edition after upgrade:' + CHAR(10) +
        N'SELECT SERVERPROPERTY(''Edition''), SERVERPROPERTY(''EngineEdition'');',
        N'02_express_to_developer_limits_check.sql'
    );

IF @EngineEdition <> 4 AND @MaxServerMemoryMB < @RAM_MB * 0.4
    INSERT INTO #Findings VALUES (
        20, N'CRITICAL', N'Memory',
        N'max server memory (' + CAST(@MaxServerMemoryMB AS NVARCHAR(20)) + N' MB) is far below physical RAM (' + CAST(@RAM_MB AS NVARCHAR(20)) + N' MB)',
        N'1) During maintenance window, run section 18 template 1. 2) Leave ' + CAST(@OSReserveMB AS NVARCHAR(10)) + N' MB for OS. 3) Monitor buffer pool and PAGEIOLATCH. 4) Re-run this report.',
        N'EXEC sp_configure ''show advanced options'', 1; RECONFIGURE;' + CHAR(10) +
        N'EXEC sp_configure ''max server memory (MB)'', ' + CAST(@SuggestedMaxMemMB AS NVARCHAR(20)) + N'; RECONFIGURE;' + CHAR(10) +
        N'-- Rollback: EXEC sp_configure ''max server memory (MB)'', ' + CAST(@MaxServerMemoryMB AS NVARCHAR(20)) + N'; RECONFIGURE;',
        N'07_Instance_Config/02_recommended_fixes_with_rollback.sql'
    );

-- ============================================================================
-- (3) MEMORY CONFIGURATION & BUFFER POOL
-- ============================================================================
PRINT '';
PRINT '=== (3) MEMORY CONFIGURATION & BUFFER POOL ===';
SELECT
    @MaxServerMemoryMB AS [Max_Server_Memory_MB],
    CAST((SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = N'min server memory (MB)') AS INT) AS [Min_Server_Memory_MB],
    os.physical_memory_kb / 1024 AS [Physical_RAM_MB],
    os.committed_kb / 1024 AS [SQL_Committed_Memory_MB],
    os.committed_target_kb / 1024 AS [SQL_Target_Memory_MB],
    buf.Buffer_Pool_MB,
    CAST(buf.Buffer_Pool_MB * 100.0 / NULLIF(os.physical_memory_kb / 1024, 0) AS DECIMAL(6,1)) AS [Buffer_Pool_Pct_of_RAM],
    @SuggestedMaxMemMB AS [Suggested_Max_Server_Memory_MB],
    CASE
        WHEN os.committed_kb / 1024 < os.physical_memory_kb / 1024 * 0.3
            THEN N'SQL under-utilizing RAM — likely config cap or recent restart'
        ELSE N'Review against workload'
    END AS [Memory_Utilization_Note],
    CASE
        WHEN buf.Buffer_Pool_MB < @RAM_MB * 0.2
            THEN N'Buffer pool small — apply section 18 template 1 if not done'
        ELSE N'Monitor Page life expectancy in section (16)'
    END AS [What_To_Do]
FROM sys.dm_os_sys_info AS os
CROSS JOIN (
    SELECT ISNULL(SUM(pages_kb) / 1024, 0) AS Buffer_Pool_MB
    FROM sys.dm_os_memory_clerks
    WHERE type = N'MEMORYCLERK_SQLBUFFERPOOL'
) AS buf;

-- ============================================================================
-- (4) CPU / NUMA / SCHEDULER PRESSURE
-- ============================================================================
PRINT '';
PRINT '=== (4) CPU / NUMA / SCHEDULER PRESSURE ===';
IF COL_LENGTH(N'sys.dm_os_sys_info', N'socket_count') IS NOT NULL
BEGIN
    SELECT
        cpu_count AS [Logical_CPUs],
        scheduler_count AS [Schedulers],
        socket_count AS [Sockets],
        numa_node_count AS [NUMA_Nodes],
        hyperthread_ratio,
        cpu_count / NULLIF(hyperthread_ratio, 0) AS [Physical_Cores_Approx],
        @MaxDOP AS [Configured_MAXDOP],
        @CTFP AS [Configured_CTFP],
        @SuggestedMAXDOP AS [Suggested_MAXDOP],
        CASE
            WHEN @MaxDOP = 0 AND numa_node_count > 1 THEN N'WARNING: MAXDOP 0 with multiple NUMA nodes — apply section 18 template 2'
            WHEN @CTFP <= 5 AND @CPU > 4 THEN N'WARNING: CTFP at default 5 — apply section 18 template 2'
            ELSE N'Review MAXDOP against NUMA layout'
        END AS [Parallelism_Note],
        CASE
            WHEN @CTFP <= 5 OR (@MaxDOP = 0 AND @CPU > 4)
                THEN N'1) Apply section 18 template 2. 2) Reproduce workload. 3) Check CXPACKET / PAGELATCH waits.'
            ELSE N'Parallelism settings look reasonable — focus on waits if still slow.'
        END AS [What_To_Do]
    FROM sys.dm_os_sys_info;
END
ELSE
BEGIN
    SELECT
        cpu_count AS [Logical_CPUs],
        scheduler_count AS [Schedulers],
        hyperthread_ratio,
        cpu_count / NULLIF(hyperthread_ratio, 0) AS [Physical_Cores_Approx],
        @MaxDOP AS [Configured_MAXDOP],
        @CTFP AS [Configured_CTFP],
        @SuggestedMAXDOP AS [Suggested_MAXDOP],
        CASE WHEN @CTFP <= 5 THEN N'Apply section 18 template 2' ELSE N'OK' END AS [What_To_Do]
    FROM sys.dm_os_sys_info;
END;

SELECT
    SUM(CASE WHEN sched.status = N'VISIBLE ONLINE' THEN 1 ELSE 0 END) AS [Online_Schedulers],
    SUM(sched.runnable_tasks_count) AS [Total_Runnable_Tasks],
    MAX(sched.runnable_tasks_count) AS [Max_Runnable_On_Any_Scheduler],
    SUM(sched.current_tasks_count) AS [Total_Current_Tasks],
    CASE
        WHEN MAX(sched.runnable_tasks_count) > 0
            THEN N'CPU queue pressure — check SOS_SCHEDULER_YIELD; also verify blocking is not the cause'
        ELSE N'No runnable task backlog at snapshot time'
    END AS [What_To_Do]
FROM sys.dm_os_schedulers AS sched
WHERE sched.scheduler_id < 255;

IF @CTFP <= 5
    INSERT INTO #Findings VALUES (
        30, N'CRITICAL', N'Parallelism',
        N'cost threshold for parallelism = ' + CAST(@CTFP AS NVARCHAR(10)) + N' (default 5)',
        N'1) Run section 18 template 2. 2) Re-test OLTP workload. 3) If CXPACKET still high, tune MAXDOP further.',
        N'EXEC sp_configure ''show advanced options'', 1; RECONFIGURE;' + CHAR(10) +
        N'EXEC sp_configure ''cost threshold for parallelism'', 50; RECONFIGURE;' + CHAR(10) +
        N'-- Rollback: EXEC sp_configure ''cost threshold for parallelism'', ' + CAST(@CTFP AS NVARCHAR(10)) + N'; RECONFIGURE;',
        N'07_Instance_Config/01_post_migration_config_audit.sql'
    );

IF @MaxDOP = 0 AND @CPU > 8
    INSERT INTO #Findings VALUES (
        35, N'WARNING', N'Parallelism',
        N'max degree of parallelism = 0 (unlimited) on ' + CAST(@CPU AS NVARCHAR(10)) + N' logical CPUs',
        N'1) Set MAXDOP to ' + CAST(@SuggestedMAXDOP AS NVARCHAR(10)) + N' (section 18 template 2). 2) Add TempDB files if PAGELATCH appears.',
        N'EXEC sp_configure ''max degree of parallelism'', ' + CAST(@SuggestedMAXDOP AS NVARCHAR(10)) + N'; RECONFIGURE;',
        N'02_Upgrade_Validation/03_cpu_numa_topology.sql'
    );

-- ============================================================================
-- (5) INSTANCE CONFIGURATION AUDIT
-- ============================================================================
PRINT '';
PRINT '=== (5) INSTANCE CONFIGURATION AUDIT (sp_configure) ===';
;WITH ConfigAudit AS (
    SELECT
        c.name AS [Setting],
        CAST(c.value AS INT) AS [Configured],
        CAST(c.value_in_use AS INT) AS [Running_Value],
        c.is_dynamic,
        c.is_advanced,
        CASE c.name
            WHEN N'max server memory (MB)' THEN
                CASE
                    WHEN CAST(c.value_in_use AS INT) < @RAM_MB * 0.4 THEN N'CRITICAL — likely Express-era cap'
                    WHEN CAST(c.value_in_use AS INT) > @RAM_MB * 0.95 THEN N'WARNING — may starve OS'
                    ELSE N'OK'
                END
            WHEN N'max degree of parallelism' THEN
                CASE
                    WHEN CAST(c.value_in_use AS INT) = 0 THEN N'WARNING — unlimited parallelism on OLTP'
                    WHEN CAST(c.value_in_use AS INT) = 1 THEN N'INFO — OK for test; verify CTFP if prod'
                    ELSE N'OK'
                END
            WHEN N'cost threshold for parallelism' THEN
                CASE WHEN CAST(c.value_in_use AS INT) <= 5 THEN N'CRITICAL — default 5' ELSE N'OK' END
            WHEN N'optimize for ad hoc workloads' THEN
                CASE WHEN CAST(c.value_in_use AS INT) = 0 THEN N'WARNING — plan cache bloat risk' ELSE N'OK' END
            WHEN N'priority boost' THEN
                CASE WHEN CAST(c.value_in_use AS INT) = 1 THEN N'CRITICAL — set to 0' ELSE N'OK' END
            WHEN N'remote admin connections' THEN
                CASE WHEN CAST(c.value_in_use AS INT) = 0 THEN N'WARNING — DAC disabled' ELSE N'OK' END
            ELSE N'Review'
        END AS [Status],
        CASE c.name
            WHEN N'max server memory (MB)' THEN N'Section 18 template 1'
            WHEN N'max degree of parallelism' THEN N'Section 18 template 2'
            WHEN N'cost threshold for parallelism' THEN N'Section 18 template 2'
            WHEN N'optimize for ad hoc workloads' THEN N'Section 18 template 3'
            WHEN N'priority boost' THEN N'EXEC sp_configure ''priority boost'', 0; RECONFIGURE;'
            ELSE N'See 07_Instance_Config/02_recommended_fixes_with_rollback.sql'
        END AS [What_To_Do]
    FROM sys.configurations AS c
    WHERE c.name IN (
        N'max server memory (MB)', N'min server memory (MB)', N'max degree of parallelism',
        N'cost threshold for parallelism', N'optimize for ad hoc workloads', N'backup compression default',
        N'backup checksum default', N'remote admin connections', N'priority boost', N'fill factor (%)',
        N'blocked process threshold (s)', N'max worker threads', N'affinity mask', N'affinity64 mask',
        N'clr enabled', N'contained database authentication'
    )
)
SELECT Setting, Configured, Running_Value, is_dynamic, is_advanced, Status, What_To_Do
FROM ConfigAudit
ORDER BY CASE WHEN Status LIKE N'CRITICAL%' THEN 1 WHEN Status LIKE N'WARNING%' THEN 2 ELSE 3 END, Setting;

IF EXISTS (SELECT 1 FROM sys.configurations WHERE name = N'priority boost' AND CAST(value_in_use AS INT) = 1)
    INSERT INTO #Findings VALUES (
        40, N'CRITICAL', N'Instance Config', N'priority boost is enabled',
        N'1) Disable immediately. 2) Restart not required (dynamic). 3) Re-run report.',
        N'EXEC sp_configure ''show advanced options'', 1; RECONFIGURE;' + CHAR(10) +
        N'EXEC sp_configure ''priority boost'', 0; RECONFIGURE;',
        N'07_Instance_Config/02_recommended_fixes_with_rollback.sql'
    );

-- ============================================================================
-- (6) DATABASE INVENTORY & SETTINGS
-- ============================================================================
PRINT '';
PRINT '=== (6) DATABASE INVENTORY & SETTINGS ===';
SELECT
    d.name AS [Database_Name],
    d.state_desc AS [State],
    d.recovery_model_desc AS [Recovery_Model],
    d.compatibility_level AS [Compat_Level],
    @InstanceCompat AS [Instance_Max_Compat],
    SUSER_SNAME(d.owner_sid) AS [Owner],
    d.is_auto_close_on AS [Auto_Close],
    d.is_auto_shrink_on AS [Auto_Shrink],
    d.is_query_store_on AS [Query_Store_On],
    CASE d.compatibility_level
        WHEN 150 THEN N'CE 150 — typical after 2019 Express'
        WHEN 160 THEN N'CE 160 (2022)'
        WHEN 170 THEN N'CE 170 (2025)'
        ELSE N'Legacy — review before changing'
    END AS [CE_Version],
    CASE
        WHEN d.state_desc <> N'ONLINE' THEN N'Bring database ONLINE or remove from monitoring scope'
        WHEN SUSER_SNAME(d.owner_sid) IS NULL THEN N'Run: ALTER AUTHORIZATION ON DATABASE::' + QUOTENAME(d.name) + N' TO [sa_or_login];'
        WHEN d.is_auto_close_on = 1 OR d.is_auto_shrink_on = 1
            THEN N'Run: ALTER DATABASE ' + QUOTENAME(d.name) + N' SET AUTO_CLOSE OFF, AUTO_SHRINK OFF;'
        WHEN d.compatibility_level < @InstanceCompat
            THEN N'Test compat upgrade in lower env before: ALTER DATABASE ... SET COMPATIBILITY_LEVEL = ' + CAST(@InstanceCompat AS NVARCHAR(10))
        ELSE N'OK'
    END AS [What_To_Do]
FROM sys.databases AS d
WHERE d.database_id > 4
ORDER BY CASE WHEN d.state_desc <> N'ONLINE' THEN 0 WHEN SUSER_SNAME(d.owner_sid) IS NULL THEN 1 ELSE 2 END, d.name;

IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id > 4 AND SUSER_SNAME(owner_sid) IS NULL)
    INSERT INTO #Findings VALUES (
        50, N'CRITICAL', N'Database', N'One or more databases have orphaned owner (owner_sid not resolved)',
        N'1) For each database in section (6) with NULL owner, run ALTER AUTHORIZATION. 2) Re-test SSMS Object Explorer. 3) See section 18 template 5.',
        N'-- Per database (replace names):' + CHAR(10) +
        N'ALTER AUTHORIZATION ON DATABASE::[YourDB] TO [sa];',
        N'05_Concurrency/02_ssms_metadata_slowness.sql'
    );

IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id > 4 AND (is_auto_close_on = 1 OR is_auto_shrink_on = 1))
    INSERT INTO #Findings VALUES (
        55, N'CRITICAL', N'Database', N'auto_close or auto_shrink enabled on user database(s)',
        N'1) Disable on every flagged DB (section 18 template 4). 2) Never enable on production user DBs.',
        N'ALTER DATABASE [YourDB] SET AUTO_CLOSE OFF, AUTO_SHRINK OFF;',
        N'02_Instance_Config/database_compatibility_audit.sql'
    );

-- ============================================================================
-- (7) DATABASE-SCOPED CONFIGURATION OVERRIDES
-- ============================================================================
PRINT '';
PRINT '=== (7) DATABASE-SCOPED CONFIGURATION OVERRIDES ===';
DECLARE @dsc_sql NVARCHAR(MAX) = N'';
SELECT @dsc_sql = @dsc_sql + N'
SELECT ''' + REPLACE(name, '''', '''''') + N''' AS [Database_Name],
       dsc.name AS [DSC_Name],
       dsc.value AS [DSC_Value],
       dsc.value_for_secondary AS [Secondary_Value],
       CASE dsc.name
           WHEN N''LEGACY_CARDINALITY_ESTIMATION'' THEN N''If CE test helps in non-prod: ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON''
           WHEN N''MAXDOP'' THEN N''Overrides instance MAXDOP — align with section 18 template 2''
           ELSE N''Review in non-prod before changing''
       END AS [What_To_Do]
FROM ' + QUOTENAME(name) + N'.sys.database_scoped_configurations AS dsc
WHERE dsc.name IN (
    N''LEGACY_CARDINALITY_ESTIMATION'', N''OPTIMIZE_FOR_AD_HOC_WORKLOADS'', N''MAXDOP'',
    N''PARAMETER_SNIFFING'', N''IDENTITY_CACHE'', N''INTERLEAVED_EXECUTION_TVF'',
    N''BATCH_MODE_MEMORY_GRANT_FEEDBACK'', N''BATCH_MODE_ADAPTIVE_JOINS''
);
'
FROM sys.databases
WHERE database_id > 4 AND state = 0;

IF LEN(@dsc_sql) > 0
    EXEC sys.sp_executesql @dsc_sql;
ELSE
    PRINT 'No online user databases for DSC scan.';

-- ============================================================================
-- (8) QUERY STORE STATUS & FORCED PLANS
-- ============================================================================
PRINT '';
PRINT '=== (8) QUERY STORE STATUS & FORCED PLANS ===';
SELECT
    d.name AS [Database_Name],
    d.is_query_store_on AS [QS_Enabled],
    CASE WHEN d.is_query_store_on = 0
         THEN N'Enable Query Store in non-prod to track regressions: ALTER DATABASE ... SET QUERY_STORE = ON'
         ELSE N'Review forced plans below; unforce bad plans from pre-migration'
    END AS [What_To_Do]
FROM sys.databases AS d
WHERE d.database_id > 4 AND d.state = 0
ORDER BY d.is_query_store_on DESC, d.name;

DECLARE @qs_sql NVARCHAR(MAX) = N'';
SELECT @qs_sql = @qs_sql + N'
SELECT ''' + REPLACE(d.name, '''', '''''') + N''' AS [Database_Name],
       qs.actual_state_desc,
       qs.desired_state_desc,
       qs.current_storage_size_mb,
       qs.max_storage_size_mb,
       qs.query_capture_mode_desc,
       (SELECT COUNT(*) FROM ' + QUOTENAME(d.name) + N'.sys.query_store_plan WHERE is_forced_plan = 1) AS [Forced_Plans],
       (SELECT COUNT(*) FROM ' + QUOTENAME(d.name) + N'.sys.query_store_plan WHERE is_forced_plan = 1 AND force_failure_count > 0) AS [Force_Failures],
       CASE WHEN (SELECT COUNT(*) FROM ' + QUOTENAME(d.name) + N'.sys.query_store_plan WHERE is_forced_plan = 1) > 0
            THEN N''Run 06_Optimizer_Plans/03_query_store_regression.sql; unforce bad plans (section 18 template 7)''
            ELSE N''OK''
       END AS [What_To_Do]
FROM ' + QUOTENAME(d.name) + N'.sys.database_query_store_options AS qs
UNION ALL
'
FROM sys.databases AS d
WHERE d.database_id > 4 AND d.state = 0 AND d.is_query_store_on = 1;

IF LEN(@qs_sql) > 0
BEGIN
    SET @qs_sql = LEFT(@qs_sql, LEN(@qs_sql) - 11);
    EXEC sys.sp_executesql @qs_sql;
END;

DECLARE @forced_total INT = 0;
DECLARE @force_fail_total INT = 0;
DECLARE @db SYSNAME;
DECLARE @cnt INT;

DECLARE forced_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0 AND is_query_store_on = 1;

OPEN forced_cursor;
FETCH NEXT FROM forced_cursor INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @qs_sql = N'SELECT @c = COUNT(*) FROM ' + QUOTENAME(@db) + N'.sys.query_store_plan WHERE is_forced_plan = 1';
    EXEC sys.sp_executesql @qs_sql, N'@c INT OUTPUT', @c = @cnt OUTPUT;
    SET @forced_total = @forced_total + ISNULL(@cnt, 0);

    SET @qs_sql = N'SELECT @c = COUNT(*) FROM ' + QUOTENAME(@db) + N'.sys.query_store_plan WHERE is_forced_plan = 1 AND force_failure_count > 0';
    EXEC sys.sp_executesql @qs_sql, N'@c INT OUTPUT', @c = @cnt OUTPUT;
    SET @force_fail_total = @force_fail_total + ISNULL(@cnt, 0);

    FETCH NEXT FROM forced_cursor INTO @db;
END;
CLOSE forced_cursor;
DEALLOCATE forced_cursor;

IF @forced_total > 0
    INSERT INTO #Findings VALUES (
        60, N'WARNING', N'Query Store',
        CAST(@forced_total AS NVARCHAR(10)) + N' forced plan(s) across Query Store databases',
        N'1) Run 06_Optimizer_Plans/03_query_store_regression.sql. 2) Unforce plans that regressed after upgrade. 3) Re-test application.',
        N'USE [YourDB];' + CHAR(10) +
        N'EXEC sys.sp_query_store_unforce_plan @query_id = 0, @plan_id = 0;  -- replace with actual IDs',
        N'06_Optimizer_Plans/03_query_store_regression.sql'
    );

IF @force_fail_total > 0
    INSERT INTO #Findings VALUES (
        62, N'WARNING', N'Query Store',
        CAST(@force_fail_total AS NVARCHAR(10)) + N' forced plan(s) with force failures',
        N'1) Unforce failing plans. 2) Update statistics. 3) Check for compile storms (RESOURCE_SEMAPHORE_QUERY_COMPILE).',
        N'USE [YourDB]; EXEC sys.sp_query_store_unforce_plan @query_id = 0, @plan_id = 0;',
        N'11_Query_Store/05_forced_plans_monitor.sql'
    );

-- ============================================================================
-- (9) PLAN INSTABILITY IN CACHE
-- ============================================================================
PRINT '';
PRINT '=== (9) PLAN INSTABILITY (multiple plans per query hash in cache) ===';
;WITH PlanInstability AS (
    SELECT
        DB_NAME(st.dbid) AS [Database_Name],
        qs.query_hash,
        COUNT(DISTINCT qs.plan_handle) AS [Distinct_Plans],
        SUM(qs.execution_count) AS [Total_Executions],
        MIN(qs.total_elapsed_time * 1.0 / NULLIF(qs.execution_count, 0)) / 1000.0 AS [Min_Avg_Elapsed_Sec],
        MAX(qs.total_elapsed_time * 1.0 / NULLIF(qs.execution_count, 0)) / 1000.0 AS [Max_Avg_Elapsed_Sec],
        SUBSTRING(MIN(CAST(st.text AS NVARCHAR(MAX))), 1, 120) AS [Query_Sample]
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
    WHERE st.dbid IS NOT NULL
    GROUP BY DB_NAME(st.dbid), qs.query_hash
    HAVING COUNT(DISTINCT qs.plan_handle) > 1
)
SELECT TOP (15)
    Database_Name, query_hash, Distinct_Plans, Total_Executions,
    Min_Avg_Elapsed_Sec, Max_Avg_Elapsed_Sec, Query_Sample,
    CAST(Max_Avg_Elapsed_Sec / NULLIF(Min_Avg_Elapsed_Sec, 0) AS DECIMAL(18,1)) AS [Plan_Variance_Ratio],
    N'Only act if CPU/logical reads are HIGH and waits are LOW. Otherwise focus on wait analysis.' AS [What_To_Do]
FROM PlanInstability
ORDER BY Max_Avg_Elapsed_Sec / NULLIF(Min_Avg_Elapsed_Sec, 0) DESC;

-- ============================================================================
-- (10) TOP WAIT TYPES
-- ============================================================================
PRINT '';
PRINT '=== (10) TOP 20 WAIT TYPES (cumulative since startup) ===';
SELECT TOP (20)
    ws.wait_type,
    ws.waiting_tasks_count AS [Wait_Count],
    ws.wait_time_ms / 1000.0 AS [Total_Wait_Sec],
    CAST(ws.wait_time_ms * 1.0 / NULLIF(ws.waiting_tasks_count, 0) AS DECIMAL(18,2)) AS [Avg_Wait_ms],
    CASE
        WHEN ws.wait_type LIKE N'LCK%' THEN N'1) Run 05_Concurrency/01_blocking_and_locks.sql during slowness. 2) Fix head blocker / long transactions.'
        WHEN ws.wait_type LIKE N'LATCH%' OR ws.wait_type LIKE N'PAGELATCH%' OR ws.wait_type LIKE N'METADATA%'
            THEN N'1) Fix orphaned owners + TempDB. 2) Run 04_Wait_Stats/03_latch_metadata_waits.sql.'
        WHEN ws.wait_type LIKE N'PAGEIOLATCH%' OR ws.wait_type IN (N'WRITELOG', N'IO_COMPLETION')
            THEN N'1) Increase max server memory if capped. 2) Run 08_Storage_OS/01_io_latency_deep_dive.sql. 3) Exclude AV from data paths.'
        WHEN ws.wait_type LIKE N'RESOURCE_SEMAPHORE%' THEN N'1) Increase memory. 2) Tune queries with large sorts/hashes. 3) Check section (3).'
        WHEN ws.wait_type LIKE N'PREEMPTIVE_OS%' THEN N'1) Enable IFI. 2) Exclude AV. 3) Run 08_Storage_OS/02_os_integration_post_migration.sql.'
        WHEN ws.wait_type = N'THREADPOOL' THEN N'CRITICAL: reduce load; check max worker threads; engage senior DBA.'
        WHEN ws.wait_type IN (N'CXPACKET', N'CXCONSUMER') THEN N'1) Section 18 template 2. 2) TempDB files. 3) CE script if CPU-bound.'
        ELSE N'1) Run 04_Wait_Stats/01_wait_stats_delta_capture.sql during repro. 2) Use wait decoder script.'
    END AS [What_To_Do],
    CASE
        WHEN ws.wait_type LIKE N'LCK%' THEN N'05_Concurrency/01_blocking_and_locks.sql'
        WHEN ws.wait_type LIKE N'LATCH%' OR ws.wait_type LIKE N'PAGELATCH%' OR ws.wait_type LIKE N'METADATA%' THEN N'04_Wait_Stats/03_latch_metadata_waits.sql'
        WHEN ws.wait_type LIKE N'PAGEIOLATCH%' OR ws.wait_type IN (N'WRITELOG', N'IO_COMPLETION') THEN N'08_Storage_OS/01_io_latency_deep_dive.sql'
        WHEN ws.wait_type LIKE N'PREEMPTIVE_OS%' THEN N'08_Storage_OS/02_os_integration_post_migration.sql'
        ELSE N'04_Wait_Stats/02_post_migration_wait_decoder.sql'
    END AS [Next_Script]
FROM sys.dm_os_wait_stats AS ws
WHERE ws.wait_type NOT IN (
    N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH',
    N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE', N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT',
    N'CLR_SEMAPHORE', N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE',
    N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE', N'EXECSYNC',
    N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
    N'HADR_LOGCAPTURE_WAIT', N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
    N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE', N'MEMORY_ALLOCATION_EXT',
    N'ONDEMAND_TASK_QUEUE', N'PARALLEL_REDO_DRAIN_WORKER', N'PARALLEL_REDO_LOG_CACHE',
    N'PARALLEL_REDO_TRAN_LIST', N'PARALLEL_REDO_WORKER_SYNC', N'PARALLEL_REDO_WORKER_WAIT_WORK',
    N'PREEMPTIVE_OS_FLUSHFILEBUFFERS', N'PREEMPTIVE_XE_GETTARGETSTATE', N'PVS_PREALLOCATE',
    N'PWAIT_ALL_COMPONENTS_INITIALIZED', N'PWAIT_DIRECTLOGCONSUMER_GETNEXT',
    N'QDS_ASYNC_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
    N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'QDS_SHUTDOWN_QUEUE',
    N'REDO_THREAD_PENDING_WORK', N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE',
    N'SERVER_IDLE_TASK', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP',
    N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY', N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP',
    N'SLEEP_SYSTEMTASK', N'SLEEP_TASK', N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT',
    N'SOS_WORK_DISPATCHER', N'SP_SERVER_DIAGNOSTICS_SLEEP', N'SQLTRACE_BUFFER_FLUSH',
    N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES', N'WAIT_FOR_RESULTS',
    N'WAIT_XTP_HOST_WAIT', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'WAIT_XTP_CKPT_CLOSE',
    N'XE_BUFFERMGR_ALLPROCESSED_EVENT', N'XE_DISPATCHER_JOIN', N'XE_DISPATCHER_WAIT',
    N'XE_FILE_TARGET_TVF', N'XE_LIVE_TARGET_TVF'
)
AND ws.waiting_tasks_count > 0
ORDER BY ws.wait_time_ms DESC;

IF EXISTS (SELECT 1 FROM sys.dm_os_wait_stats WHERE wait_type LIKE N'LCK%' AND wait_time_ms > 60000 AND waiting_tasks_count > 10)
    INSERT INTO #Findings VALUES (80, N'WARNING', N'Waits', N'Significant locking waits since startup',
        N'1) Reproduce slowness. 2) Run blocking script. 3) Fix long transactions / missing indexes on FKs.',
        NULL, N'05_Concurrency/01_blocking_and_locks.sql');

IF EXISTS (SELECT 1 FROM sys.dm_os_wait_stats WHERE (wait_type LIKE N'LATCH%' OR wait_type LIKE N'PAGELATCH%' OR wait_type LIKE N'METADATA%') AND wait_time_ms > 60000)
    INSERT INTO #Findings VALUES (82, N'WARNING', N'Waits', N'Significant latch/metadata waits',
        N'1) Fix orphaned DB owners. 2) Add TempDB files (section 18 template 6). 3) Run latch metadata script.',
        NULL, N'04_Wait_Stats/03_latch_metadata_waits.sql');

IF EXISTS (SELECT 1 FROM sys.dm_os_wait_stats WHERE wait_type LIKE N'PAGEIOLATCH%' AND wait_time_ms > 120000)
    INSERT INTO #Findings VALUES (84, N'WARNING', N'Waits', N'Significant PAGEIOLATCH waits',
        N'1) Increase max server memory. 2) Check disk latency section (13). 3) Verify buffer pool size section (3).',
        N'-- See section 18 template 1 for memory', N'08_Storage_OS/01_io_latency_deep_dive.sql');

IF EXISTS (SELECT 1 FROM sys.dm_os_wait_stats WHERE wait_type LIKE N'PREEMPTIVE_OS%' AND wait_time_ms > 60000)
    INSERT INTO #Findings VALUES (86, N'WARNING', N'Waits', N'Significant PREEMPTIVE_OS waits',
        N'1) Enable IFI (section 18 template 8). 2) Exclude SQL paths from antivirus. 3) Test SQL auth vs Windows auth.',
        NULL, N'08_Storage_OS/02_os_integration_post_migration.sql');

-- ============================================================================
-- (11) ACTIVE BLOCKING & SUSPENDED SESSIONS
-- ============================================================================
PRINT '';
PRINT '=== (11) ACTIVE BLOCKING ===';
SELECT
    r.session_id,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time AS [Wait_ms],
    r.wait_resource,
    s.login_name,
    s.host_name,
    s.program_name,
    SUBSTRING(st.text, (r.statement_start_offset / 2) + 1,
        CASE WHEN r.statement_end_offset = -1 THEN LEN(CONVERT(NVARCHAR(MAX), st.text))
             ELSE (r.statement_end_offset - r.statement_start_offset) / 2 + 1 END) AS [Current_Statement],
    N'Find head blocker (blocking_session_id chain). Do NOT kill without root cause. See 05_Concurrency/01_blocking_and_locks.sql' AS [What_To_Do]
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.blocking_session_id <> 0
   OR r.session_id IN (SELECT DISTINCT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0)
ORDER BY r.wait_time DESC;

IF @@ROWCOUNT > 0
    INSERT INTO #Findings VALUES (90, N'CRITICAL', N'Concurrency', N'Active blocking detected at report time',
        N'1) Identify head blocker session_id. 2) Review open transaction (DBCC OPENTRAN). 3) Fix app transaction scope — hints will NOT help.',
        N'-- Find head blocker: 05_Concurrency/01_blocking_and_locks.sql' + CHAR(10) +
        N'-- Emergency only: KILL <spid>;  -- after documenting cause',
        N'05_Concurrency/01_blocking_and_locks.sql');

PRINT '';
PRINT '=== (11b) TOP 15 SUSPENDED SESSIONS ===';
SELECT TOP (15)
    r.session_id, r.status, r.command, r.wait_type, r.wait_time AS [Wait_ms],
    r.cpu_time AS [CPU_ms], r.logical_reads,
    s.login_name, s.host_name, s.program_name,
    CASE
        WHEN r.wait_type LIKE N'LCK%' THEN N'Blocked — run blocking script'
        WHEN r.wait_type LIKE N'LATCH%' OR r.wait_type LIKE N'PAGELATCH%' THEN N'Latch — TempDB / metadata fixes'
        WHEN r.wait_type LIKE N'PAGEIOLATCH%' THEN N'I/O wait — memory + storage'
        WHEN r.wait_type LIKE N'PREEMPTIVE%' THEN N'OS wait — IFI / AV / AD'
        ELSE N'Run 03_Elapsed_Time_Diagnostics/02_capture_live_session_waits.sql on this SPID'
    END AS [What_To_Do]
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
WHERE r.session_id <> @@SPID AND r.status = N'suspended'
ORDER BY r.wait_time DESC;

-- ============================================================================
-- (12) TEMPDB
-- ============================================================================
PRINT '';
PRINT '=== (12) TEMPDB LAYOUT & CONTENTION ===';
SELECT
    file_id, name, physical_name,
    size * 8 / 1024 AS [Size_MB],
    growth AS [Growth_Value],
    is_percent_growth,
    CASE is_percent_growth WHEN 1 THEN N'Change to fixed MB growth (64–256 MB)' ELSE N'OK' END AS [What_To_Do]
FROM tempdb.sys.database_files
ORDER BY type_desc, file_id;

SELECT
    @CPU AS [Logical_CPUs],
    @TempDBDataFiles AS [TempDB_Data_Files],
    @RecommendedTempDBFiles AS [Recommended_Files],
    CASE
        WHEN @TempDBDataFiles = 1 AND @CPU > 4 THEN N'CRITICAL: Add TempDB files — section 18 template 6'
        WHEN @TempDBDataFiles < @RecommendedTempDBFiles THEN N'WARNING: Add more equal-sized data files'
        ELSE N'OK'
    END AS [TempDB_Status],
    CASE
        WHEN @TempDBDataFiles < @RecommendedTempDBFiles
            THEN N'1) Add files equal size to primary data file. 2) Fixed MB growth. 3) Restart SQL to activate new files at startup.'
        ELSE N'TempDB file count OK — check PAGELATCH in section (10) if still slow.'
    END AS [What_To_Do];

CREATE TABLE #TempDBSpace (
    Free_Space_MB BIGINT,
    User_Objects_MB BIGINT,
    Internal_Objects_MB BIGINT,
    Version_Store_MB BIGINT
);
INSERT INTO #TempDBSpace
EXEC(N'USE tempdb;
SELECT
    SUM(unallocated_extent_page_count) * 8 / 1024,
    SUM(user_object_reserved_page_count) * 8 / 1024,
    SUM(internal_object_reserved_page_count) * 8 / 1024,
    SUM(version_store_reserved_page_count) * 8 / 1024
FROM sys.dm_db_file_space_usage;');

SELECT * FROM #TempDBSpace;
DROP TABLE #TempDBSpace;

IF @TempDBDataFiles = 1 AND @CPU > 4
    INSERT INTO #Findings VALUES (
        100, N'CRITICAL', N'TempDB',
        N'Single TempDB data file on ' + CAST(@CPU AS NVARCHAR(10)) + N' logical CPUs',
        N'1) Add ' + CAST(@RecommendedTempDBFiles - 1 AS NVARCHAR(10)) + N' more equal-sized data files. 2) Use section 18 template 6. 3) Restart SQL Server.',
        N'-- See section 18 template 6 for ALTER DATABASE tempdb ADD FILE ...',
        N'08_Storage_OS/03_tempdb_autogrowth_audit.sql'
    );

-- ============================================================================
-- (13) I/O LATENCY SUMMARY
-- ============================================================================
PRINT '';
PRINT '=== (13) I/O LATENCY SUMMARY (worst files by avg read ms) ===';
SELECT TOP (20)
    DB_NAME(vfs.database_id) AS [Database_Name],
    mf.name AS [File_Name],
    mf.type_desc AS [File_Type],
    vfs.num_of_reads,
    vfs.num_of_writes,
    CASE WHEN vfs.num_of_reads = 0 THEN 0 ELSE vfs.io_stall_read_ms / vfs.num_of_reads END AS [Avg_Read_Latency_ms],
    CASE WHEN vfs.num_of_writes = 0 THEN 0 ELSE vfs.io_stall_write_ms / vfs.num_of_writes END AS [Avg_Write_Latency_ms],
    CASE
        WHEN vfs.num_of_reads > 100 AND vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) > 20
            THEN N'1) Check VM storage / SAN. 2) Exclude path from AV. 3) Increase memory to reduce reads.'
        WHEN vfs.num_of_writes > 100 AND vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) > 20
            THEN N'1) Check log file placement. 2) Review WRITELOG waits.'
        ELSE N'OK'
    END AS [What_To_Do]
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
INNER JOIN sys.master_files AS mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
WHERE vfs.num_of_reads + vfs.num_of_writes > 0
ORDER BY CASE WHEN vfs.num_of_reads = 0 THEN 0 ELSE vfs.io_stall_read_ms / vfs.num_of_reads END DESC;

IF EXISTS (
    SELECT 1 FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
    WHERE vfs.num_of_reads > 1000 AND vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) > 20
)
    INSERT INTO #Findings VALUES (110, N'WARNING', N'Storage', N'One or more files show avg read latency > 20ms',
        N'1) Engage infrastructure team for disk/SAN. 2) Move files to faster volume. 3) Exclude from AV real-time scan.',
        NULL, N'08_Storage_OS/01_io_latency_deep_dive.sql');

-- ============================================================================
-- (14) OS INTEGRATION
-- ============================================================================
PRINT '';
PRINT '=== (14) OS INTEGRATION (IFI, services, PREEMPTIVE waits) ===';
IF COL_LENGTH(N'sys.dm_server_services', N'instant_file_initialization_enabled') IS NOT NULL
BEGIN
    SELECT
        servicename, service_account, startup_type_desc, status_desc,
        instant_file_initialization_enabled,
        CASE instant_file_initialization_enabled
            WHEN N'Y' THEN N'OK'
            ELSE N'1) Grant Perform volume maintenance tasks to service account. 2) Restart SQL. 3) Section 18 template 8.'
        END AS [What_To_Do]
    FROM sys.dm_server_services
    WHERE servicename LIKE N'SQL Server (%' OR servicename = N'MSSQLSERVER';

    IF EXISTS (
        SELECT 1 FROM sys.dm_server_services
        WHERE (servicename LIKE N'SQL Server (%' OR servicename = N'MSSQLSERVER')
          AND instant_file_initialization_enabled <> N'Y'
    )
        INSERT INTO #Findings VALUES (120, N'WARNING', N'OS', N'Instant File Initialization is disabled',
            N'1) Windows: secpol.msc → Perform volume maintenance tasks → add SQL service account. 2) Restart SQL service. 3) Confirm IFI = Y in this section.',
            N'-- Windows GUI: Local Security Policy → User Rights Assignment → Perform volume maintenance tasks' + CHAR(10) +
            N'-- Then restart SQL Server service',
            N'08_Storage_OS/02_os_integration_post_migration.sql');
END
ELSE
    PRINT 'dm_server_services.IFI column not available on this version — check IFI via Windows policy manually.';

SELECT TOP (10)
    wait_type,
    wait_time_ms / 1000.0 AS [Total_Wait_Sec],
    CASE
        WHEN wait_type LIKE N'%WRITEFILEGATHER%' THEN N'Enable IFI (section 18 template 8)'
        WHEN wait_type LIKE N'%AUTHENTICATION%' OR wait_type LIKE N'%LOGON%' THEN N'Test SQL authentication; check AD latency'
        WHEN wait_type LIKE N'%FILE%' THEN N'Exclude SQL data/log/backup paths from AV'
        ELSE N'Review 08_Storage_OS/02_os_integration_post_migration.sql'
    END AS [What_To_Do]
FROM sys.dm_os_wait_stats
WHERE wait_type LIKE N'PREEMPTIVE%'
  AND waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;

-- ============================================================================
-- (15) TRACE FLAGS
-- ============================================================================
PRINT '';
PRINT '=== (15) GLOBAL TRACE FLAGS ===';
IF OBJECT_ID(N'tempdb..#TraceFlags') IS NOT NULL DROP TABLE #TraceFlags;
CREATE TABLE #TraceFlags (
    TraceFlag INT,
    [Status] INT,
    Global INT,
    Session INT
);

BEGIN TRY
    INSERT INTO #TraceFlags EXEC (N'DBCC TRACESTATUS(-1)');

    SELECT TraceFlag, [Status], Global, Session,
        CASE TraceFlag
            WHEN 4199 THEN N'Expected on recent versions — usually OK'
            WHEN 9481 THEN N'Legacy CE globally — test removing in lower env'
            WHEN 1117 THEN N'TempDB growth — review if still needed'
            WHEN 1118 THEN N'TempDB allocation — review if still needed'
            ELSE N'Review — may conflict with 2025 optimizer'
        END AS [Note],
        CASE TraceFlag
            WHEN 9481 THEN N'DBCC TRACEOFF(9481,-1);  -- test in non-prod first'
            ELSE N'Document purpose before disabling'
        END AS [What_To_Do]
    FROM #TraceFlags
    WHERE [Status] = 1;

    IF EXISTS (SELECT 1 FROM #TraceFlags WHERE TraceFlag IN (9481, 11064, 2312) AND [Status] = 1)
        INSERT INTO #Findings VALUES (130, N'INFO', N'Trace Flags', N'Legacy optimizer trace flag(s) active globally',
            N'1) Document why each TF was set. 2) Test disable in non-prod. 3) Compare plans before/after.',
            N'DBCC TRACEOFF(9481,-1);  -- example; verify TF number first',
            N'07_Instance_Config/01_post_migration_config_audit.sql');
END TRY
BEGIN CATCH
    PRINT N'Trace flag scan skipped: ' + ERROR_MESSAGE();
END CATCH;

IF OBJECT_ID(N'tempdb..#TraceFlags') IS NOT NULL DROP TABLE #TraceFlags;

-- ============================================================================
-- (16) KEY PERFORMANCE COUNTERS
-- ============================================================================
PRINT '';
PRINT '=== (16) KEY PERFORMANCE COUNTERS (cumulative since startup) ===';
SELECT
    counter_name,
    instance_name,
    CAST(cntr_value AS BIGINT) AS [cntr_value],
    CASE counter_name
        WHEN N'Page life expectancy' THEN
            CASE WHEN CAST(cntr_value AS BIGINT) < 300
                 THEN N'Low PLE — increase max server memory (section 18 template 1)'
                 ELSE N'OK'
            END
        WHEN N'Lock Waits/sec' THEN N'If high during slowness — run blocking script'
        ELSE N'Review trend after config changes'
    END AS [What_To_Do]
FROM sys.dm_os_performance_counters
WHERE counter_name IN (
    N'Page life expectancy', N'Batch Requests/sec', N'SQL Compilations/sec',
    N'SQL Re-Compilations/sec', N'User Connections', N'Lock Waits/sec',
    N'Buffer cache hit ratio', N'Buffer cache hit ratio base'
)
AND (object_name LIKE N'%Buffer Manager%' OR object_name LIKE N'%SQL Statistics%'
     OR object_name LIKE N'%General Statistics%' OR object_name LIKE N'%Locks%');

DECLARE @PLE BIGINT;
SELECT @PLE = CAST(cntr_value AS BIGINT)
FROM sys.dm_os_performance_counters
WHERE counter_name = N'Page life expectancy'
  AND object_name LIKE N'%Buffer Manager%'
  AND instance_name = N'';

IF @PLE IS NOT NULL AND @PLE < 300 AND @MaxServerMemoryMB < @RAM_MB * 0.5
    INSERT INTO #Findings VALUES (140, N'WARNING', N'Memory',
        N'Page life expectancy = ' + CAST(@PLE AS NVARCHAR(20)) + N' with conservative max server memory',
        N'1) Apply section 18 template 1. 2) Re-check PLE after 15–30 min workload. 3) Target PLE > 300 on OLTP.',
        N'EXEC sp_configure ''max server memory (MB)'', ' + CAST(@SuggestedMaxMemMB AS NVARCHAR(20)) + N'; RECONFIGURE;',
        N'07_Instance_Config/02_recommended_fixes_with_rollback.sql');

-- ============================================================================
-- (17) EXECUTIVE SUMMARY
-- ============================================================================
PRINT '';
PRINT '================================================================================';
PRINT '=== (17) EXECUTIVE SUMMARY — PRIORITIZED FINDINGS WITH SOLUTIONS ===';
PRINT '================================================================================';

IF NOT EXISTS (SELECT 1 FROM #Findings)
    INSERT INTO #Findings VALUES (
        999, N'INFO', N'General',
        N'No automatic CRITICAL/WARNING flags from configuration scan',
        N'1) If still slow: run 03_Elapsed_Time_Diagnostics/01_elapsed_vs_worker_time_gap.sql on slow query. 2) If elapsed >> CPU → wait analysis, not hints. 3) Capture wait delta during repro.',
        N'-- 04_Wait_Stats/01_wait_stats_delta_capture.sql (before repro)' + CHAR(10) +
        N'-- 04_Wait_Stats/02_wait_stats_delta_after_repro.sql (after repro)',
        N'03_Elapsed_Time_Diagnostics/01_elapsed_vs_worker_time_gap.sql'
    );

SELECT
    Sort_Order,
    Severity,
    Category,
    Finding,
    What_To_Do,
    Solution_SQL,
    Next_Script
FROM #Findings
ORDER BY CASE Severity WHEN N'CRITICAL' THEN 1 WHEN N'WARNING' THEN 2 ELSE 3 END, Sort_Order;

-- ============================================================================
-- (18) REMEDIATION TEMPLATES (review before executing)
-- ============================================================================
PRINT '';
PRINT '================================================================================';
PRINT '=== (18) REMEDIATION TEMPLATES — COPY, REVIEW, THEN EXECUTE ONE AT A TIME ===';
PRINT '================================================================================';

SELECT Template_ID, Title, When_To_Apply, TSQL_Template, Rollback_Note FROM (VALUES
    (1, N'Increase max server memory',
     N'Finding: max server memory << physical RAM (Express-era cap)',
     N'EXEC sp_configure ''show advanced options'', 1; RECONFIGURE;' + CHAR(10) +
     N'EXEC sp_configure ''max server memory (MB)'', ' + CAST(@SuggestedMaxMemMB AS NVARCHAR(20)) + N'; RECONFIGURE;',
     N'Rollback: EXEC sp_configure ''max server memory (MB)'', ' + CAST(@MaxServerMemoryMB AS NVARCHAR(20)) + N'; RECONFIGURE;'),

    (2, N'MAXDOP + cost threshold for parallelism',
     N'Finding: CTFP=5 and/or MAXDOP=0 on multi-core OLTP',
     N'EXEC sp_configure ''show advanced options'', 1; RECONFIGURE;' + CHAR(10) +
     N'EXEC sp_configure ''max degree of parallelism'', ' + CAST(@SuggestedMAXDOP AS NVARCHAR(10)) + N'; RECONFIGURE;' + CHAR(10) +
     N'EXEC sp_configure ''cost threshold for parallelism'', 50; RECONFIGURE;',
     N'Rollback: restore prior MAXDOP=' + CAST(@MaxDOP AS NVARCHAR(10)) + N' CTFP=' + CAST(@CTFP AS NVARCHAR(10))),

    (3, N'Optimize for ad hoc workloads',
     N'Finding: plan cache bloat / compile pressure from ad hoc SQL',
     N'EXEC sp_configure ''show advanced options'', 1; RECONFIGURE;' + CHAR(10) +
     N'EXEC sp_configure ''optimize for ad hoc workloads'', 1; RECONFIGURE;',
     N'Rollback: EXEC sp_configure ''optimize for ad hoc workloads'', 0; RECONFIGURE;'),

    (4, N'Disable auto_close / auto_shrink',
     N'Finding: auto_close or auto_shrink ON (section 6)',
     N'ALTER DATABASE [YourDB] SET AUTO_CLOSE OFF, AUTO_SHRINK OFF;',
     N'N/A — safe to apply'),

    (5, N'Fix orphaned database owner',
     N'Finding: NULL owner in section 6 — fixes SSMS/metadata slowness',
     N'ALTER AUTHORIZATION ON DATABASE::[YourDB] TO [sa];  -- or valid login',
     N'ALTER AUTHORIZATION ON DATABASE::[YourDB] TO [previous_owner];'),

    (6, N'Add TempDB data files',
     N'Finding: single TempDB file on multi-core (section 12)',
     N'-- Match size of tempdev; repeat for each additional file:' + CHAR(10) +
     N'ALTER DATABASE tempdb ADD FILE (NAME = tempdev2, FILENAME = N''C:\...\tempdev2.ndf'', SIZE = 1024MB, FILEGROWTH = 128MB);' + CHAR(10) +
     N'-- Recommended file count for this server: ' + CAST(@RecommendedTempDBFiles AS NVARCHAR(10)),
     N'New files take effect after SQL Server restart'),

    (7, N'Unforce Query Store plan',
     N'Finding: forced plans from pre-migration (section 8)',
     N'USE [YourDB];' + CHAR(10) +
     N'EXEC sys.sp_query_store_unforce_plan @query_id = 0, @plan_id = 0;',
     N'Re-force prior plan if needed: sp_query_store_force_plan'),

    (8, N'Enable Instant File Initialization',
     N'Finding: IFI disabled (section 14) — Windows change, not T-SQL',
     N'-- 1) secpol.msc → User Rights Assignment → Perform volume maintenance tasks' + CHAR(10) +
     N'-- 2) Add SQL Server service account' + CHAR(10) +
     N'-- 3) Restart SQL Server service' + CHAR(10) +
     N'-- 4) Re-run section (14) — instant_file_initialization_enabled should be Y',
     N'Remove right from service account to disable IFI'),

    (9, N'Enable DAC (Dedicated Admin Connection)',
     N'Finding: remote admin connections = 0',
     N'EXEC sp_configure ''remote admin connections'', 1; RECONFIGURE;',
     N'Rollback: EXEC sp_configure ''remote admin connections'', 0; RECONFIGURE;'),

    (10, N'Clear wait stats baseline (after major fix)',
     N'After applying fixes — need clean wait delta',
     N'DBCC SQLPERF(''sys.dm_os_wait_stats'', CLEAR);  -- document timestamp',
     N'Waits are cumulative — only clear when documenting a new baseline')
) AS t(Template_ID, Title, When_To_Apply, TSQL_Template, Rollback_Note)
ORDER BY Template_ID;

-- Per-database fix scripts for orphaned owners / auto_close
PRINT '';
PRINT '=== (18b) PER-DATABASE FIX SCRIPTS (generated from section 6) ===';
SELECT
    d.name AS [Database_Name],
    CASE WHEN SUSER_SNAME(d.owner_sid) IS NULL
         THEN N'ALTER AUTHORIZATION ON DATABASE::' + QUOTENAME(d.name) + N' TO [sa];'
         ELSE NULL END AS [Fix_Orphaned_Owner_SQL],
    CASE WHEN d.is_auto_close_on = 1 OR d.is_auto_shrink_on = 1
         THEN N'ALTER DATABASE ' + QUOTENAME(d.name) + N' SET AUTO_CLOSE OFF, AUTO_SHRINK OFF;'
         ELSE NULL END AS [Fix_AutoClose_Shrink_SQL]
FROM sys.databases AS d
WHERE d.database_id > 4
  AND (SUSER_SNAME(d.owner_sid) IS NULL OR d.is_auto_close_on = 1 OR d.is_auto_shrink_on = 1);

-- ============================================================================
-- (19) STEP-BY-STEP ACTION PLAN
-- ============================================================================
PRINT '';
PRINT '================================================================================';
PRINT '=== (19) STEP-BY-STEP ACTION PLAN ===';
PRINT '================================================================================';

SELECT Step_Num, Phase, Action, Success_Check FROM (VALUES
    (1,  N'NOW',        N'Review section (17) — fix all CRITICAL findings first', N'No CRITICAL items remain OR each has a change ticket'),
    (2,  N'NOW',        N'Apply section (18) templates one at a time (memory → parallelism → DB fixes)', N'Re-run this report; CRITICAL count drops'),
    (3,  N'NOW',        N'Run section (18b) per-database SQL for orphaned owners / auto_close', N'SSMS Object Explorer expands faster'),
    (4,  N'DURING SLOW', N'Reproduce app slowness; run 04_Wait_Stats/01_wait_stats_delta_capture.sql BEFORE', N'Baseline captured'),
    (5,  N'DURING SLOW', N'While slow, run 04_Wait_Stats/02_wait_stats_delta_after_repro.sql', N'Top wait type identified'),
    (6,  N'DURING SLOW', N'On the slow query: 03_Elapsed_Time_Diagnostics/01_elapsed_vs_worker_time_gap.sql', N'Know if wait-bound (elapsed >> CPU) or CPU-bound'),
    (7,  N'IF BLOCKED',  N'Run 05_Concurrency/01_blocking_and_locks.sql — fix head blocker / long txn', N'No active blocking during business hours'),
    (8,  N'IF LATCH/IO', N'Match top wait to script in section (10) What_To_Do column', N'Top wait time drops on delta capture'),
    (9,  N'IF PLANS',    N'Only if CPU-bound: 06_Optimizer_Plans/03_query_store_regression.sql', N'Bad forced plans removed'),
    (10, N'LAST RESORT', N'09_Extended_Events/01_xe_single_query_wait_capture.sql for proof-level waits', N'XE shows exact wait per statement'),
    (11, N'FINAL',       N'Re-run THIS report; save output as post-fix baseline', N'Section (17) clean; app acceptable')
) AS ActionPlan(Step_Num, Phase, Action, Success_Check)
ORDER BY Step_Num;

PRINT '';
PRINT '=== WHY 2025 CAN FEEL SLOWER THAN 2019 EXPRESS ===';
SELECT Issue, Why_It_Hurts, What_To_Do FROM (VALUES
    (N'Memory still capped', N'Express ~1.4 GB buffer pool; sp_configure may still be 2 GB', N'Section 18 template 1'),
    (N'More cores exposed', N'MAXDOP 0 + CTFP 5 → parallelism + TempDB latch storms', N'Section 18 template 2 + 6'),
    (N'Wait-bound not plan-bound', N'High elapsed + low CPU = waiting; hints do not help', N'Section 19 steps 4–8'),
    (N'Orphaned DB owners', N'SSMS/metadata security checks hang', N'Section 18 template 5 / 18b'),
    (N'Query Store forced plans', N'2019 plans bad on 2025 engine', N'Section 18 template 7'),
    (N'IFI / AV / storage', N'PREEMPTIVE_OS_WRITEFILEGATHER; slow reads', N'Section 18 template 8 + AV exclusions'),
    (N'TempDB single file', N'PAGELATCH on multi-core after upgrade', N'Section 18 template 6'),
    (N'Compat unchanged', N'CE 150 on 2025 engine — test before changing', N'06_Optimizer_Plans/01_compatibility_and_ce.sql')
) AS t(Issue, Why_It_Hurts, What_To_Do);

PRINT '';
PRINT '=== REPORT COMPLETE: ' + CONVERT(NVARCHAR(30), SYSDATETIME(), 120) + ' ===';
PRINT 'Save all result sets to file. Start with section (17), then section (19).';

DROP TABLE #Findings;
