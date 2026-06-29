/*
================================================================================
RUN FIRST — Post-Migration Performance Triage Playbook
================================================================================
Purpose:
    Single-pass snapshot when an application is slow immediately after a SQL
    Server upgrade/migration (e.g. 2019 Express → 2025 Developer).

When to run:
    First 5 minutes of investigation. Run on the PRODUCTION instance during
    slowness (or reproduce slowness first).

What it checks:
    (1) Instance identity — version, edition, uptime, build
    (2) sys.dm_os_sys_info — schedulers, runnable tasks, memory model
    (3) Memory configuration — max/min server memory vs physical RAM
    (4) Database compatibility levels vs instance default
    (5) Active blocking chains
    (6) Top 15 non-benign wait types since startup
    (7) Sessions currently waiting (not running on CPU)

Interpretation:
    - Runnable_Tasks > 0 on multiple schedulers  → CPU scheduling pressure
    - Blocking_Session_ID > 0 anywhere           → concurrency issue (hints won't help)
    - Top waits LATCH_METADATA_*               → metadata/SSMS slowness likely
    - Top waits PAGEIOLATCH_WRITELOG           → storage / log I/O
    - Max_Server_Memory_MB << Physical_RAM_GB    → Express-era cap still in place

Next action if this script does not reveal the cause:
    → 03_Elapsed_Time_Diagnostics/01_elapsed_vs_worker_time_gap.sql
    → 04_Wait_Stats/01_wait_stats_delta_capture.sql (reproduce issue, capture delta)

Criticality: Critical — run before changing any settings or applying hints.
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

PRINT '=== 1. INSTANCE IDENTITY ===';
SELECT
    CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128))   AS [Product_Version],
    CAST(SERVERPROPERTY(N'ProductLevel') AS NVARCHAR(128))       AS [Product_Level],
    CAST(SERVERPROPERTY(N'Edition') AS NVARCHAR(256))          AS [Edition],
    CAST(SERVERPROPERTY(N'EngineEdition') AS INT)              AS [Engine_Edition_ID],
    CAST(SERVERPROPERTY(N'ProductMajorVersion') AS INT)        AS [Major_Version],
    si.sqlserver_start_time                                    AS [SQL_Start_Time],
    DATEDIFF(MINUTE, si.sqlserver_start_time, SYSDATETIME()) AS [Uptime_Minutes],
  CASE
        WHEN COL_LENGTH(N'sys.dm_os_sys_info', N'sql_memory_model_desc') IS NOT NULL
            THEN (SELECT sql_memory_model_desc FROM sys.dm_os_sys_info)
        ELSE N'N/A — check LPIM via service account policy'
    END AS [SQL_Memory_Model]
FROM sys.dm_os_sys_info AS si;

PRINT '=== 2. OS / SCHEDULER PRESSURE (dm_os_sys_info + schedulers) ===';
SELECT
    os.cpu_count              AS [Logical_CPU_Count],
    os.hyperthread_ratio      AS [Hyperthread_Ratio],
    os.physical_memory_kb / 1024 AS [Physical_RAM_MB],
    os.virtual_memory_kb / 1024   AS [Virtual_Memory_MB],
    os.committed_target_kb / 1024 AS [Target_Memory_Committed_MB],
    --os.availability_group_id AS [AG_ID_If_Not_Zero],
    SUM(CASE WHEN sched.status = N'VISIBLE ONLINE' THEN 1 ELSE 0 END) AS [Online_Schedulers],
    SUM(sched.runnable_tasks_count) AS [Total_Runnable_Tasks],
    SUM(sched.current_tasks_count)  AS [Total_Current_Tasks],
    MAX(sched.runnable_tasks_count) AS [Max_Runnable_On_Any_Scheduler],
    CAST(
        N'Runnable_Tasks > 0 sustained = CPU queue. ' +
        N'With LOW CPU on queries, check blocking/latches/IO instead.'
    AS NVARCHAR(500)) AS [Interpretation]
FROM sys.dm_os_sys_info AS os
CROSS JOIN sys.dm_os_schedulers AS sched
WHERE sched.scheduler_id < 255
GROUP BY os.cpu_count, os.hyperthread_ratio, os.physical_memory_kb, os.virtual_memory_kb,
         os.committed_target_kb; --, os.availability_group_id;

PRINT '=== 3. MEMORY CONFIGURATION ===';
SELECT
    c.name AS [Setting],
    c.value_in_use AS [Value],
    (SELECT physical_memory_kb / 1024 FROM sys.dm_os_sys_info) AS [Physical_RAM_MB],
    CAST(
        CASE c.name
            WHEN N'max server memory (MB)' THEN
                CASE
                    WHEN c.value_in_use < (SELECT physical_memory_kb / 1024 * 0.5 FROM sys.dm_os_sys_info)
                        THEN N'WARNING: max server memory may still reflect Express-era or conservative cap. Post-upgrade Developer edition can use more RAM.'
                    ELSE N'Review — ensure OS reserve of 4-8 GB on large servers.'
                END
            ELSE N'Review 07_Instance_Config/01_post_migration_config_audit.sql'
        END AS NVARCHAR(500)
    ) AS [Post_Migration_Note]
FROM sys.configurations AS c
WHERE c.name IN (N'max server memory (MB)', N'min server memory (MB)', N'max degree of parallelism', N'cost threshold for parallelism');

PRINT '=== 4. DATABASE COMPATIBILITY (common post-migration gap) ===';
DECLARE @InstanceCompat INT =
    COALESCE(
        CAST(SERVERPROPERTY(N'ProductMajorVersion') AS INT),
        CAST(PARSENAME(CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)), 4) AS INT)
    ) * 10;

SELECT
    d.name AS [Database_Name],
    d.compatibility_level AS [Compat_Level],
    @InstanceCompat AS [Instance_Default_Compat],
    d.is_auto_close_on AS [Auto_Close],
    d.is_auto_shrink_on AS [Auto_Shrink],
    d.state_desc AS [State],
    CASE
        WHEN d.compatibility_level < @InstanceCompat THEN N'ACTION: Test upgrade compat in lower env'
        WHEN d.is_auto_close_on = 1 OR d.is_auto_shrink_on = 1 THEN N'CRITICAL: Disable auto_close/auto_shrink'
        ELSE N'OK'
    END AS [Action]
FROM sys.databases AS d
WHERE d.database_id > 4
ORDER BY d.compatibility_level, d.name;

PRINT '=== 5. ACTIVE BLOCKING (if any row returns, hints will NOT fix app slowness) ===';
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
        CASE WHEN r.statement_end_offset = -1 THEN LEN(st.text)
             ELSE (r.statement_end_offset - r.statement_start_offset) / 2 + 1 END) AS [Current_Statement]
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.blocking_session_id <> 0
   OR r.session_id IN (SELECT DISTINCT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0)
ORDER BY r.wait_time DESC;

IF @@ROWCOUNT = 0
    PRINT 'No active blocking detected at this moment. Capture waits during slow query execution.';

PRINT '=== 6. TOP 15 WAIT TYPES (since startup — use delta script for cleaner signal) ===';
SELECT TOP (15)
    ws.wait_type,
    ws.waiting_tasks_count AS [Wait_Count],
    ws.wait_time_ms / 1000.0 AS [Total_Wait_Sec],
    (ws.wait_time_ms - ws.signal_wait_time_ms) / 1000.0 AS [Resource_Wait_Sec],
    ws.signal_wait_time_ms / 1000.0 AS [Signal_Wait_Sec],
    CAST(ws.wait_time_ms * 1.0 / NULLIF(ws.waiting_tasks_count, 0) AS DECIMAL(18,2)) AS [Avg_Wait_ms],
    CASE
        WHEN ws.wait_type LIKE N'LCK%' THEN N'→ 05_Concurrency/01_blocking_and_locks.sql'
        WHEN ws.wait_type LIKE N'LATCH%' OR ws.wait_type LIKE N'PAGELATCH%' OR ws.wait_type LIKE N'METADATA%' THEN N'→ 04_Wait_Stats/03_latch_metadata_waits.sql'
        WHEN ws.wait_type LIKE N'PAGEIOLATCH%' OR ws.wait_type IN (N'WRITELOG', N'IO_COMPLETION') THEN N'→ 08_Storage_OS/01_io_latency_deep_dive.sql'
        WHEN ws.wait_type LIKE N'RESOURCE_SEMAPHORE%' THEN N'→ 07_Instance_Config/01_post_migration_config_audit.sql'
        WHEN ws.wait_type LIKE N'PREEMPTIVE_OS%' THEN N'→ 08_Storage_OS/02_os_integration_post_migration.sql'
        WHEN ws.wait_type = N'THREADPOOL' THEN N'CRITICAL — worker exhaustion'
        ELSE N'→ 04_Wait_Stats/02_post_migration_wait_decoder.sql'
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
    N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'QDS_SHUTDOWN_QUEUE', N'QDS_ASYNC_QUEUE',
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

PRINT '=== 7. SESSIONS CURRENTLY WAITING (not actively on CPU) ===';
SELECT TOP (25)
    r.session_id,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time AS [Wait_ms],
    r.cpu_time AS [CPU_ms],
    r.logical_reads,
    r.reads AS [Physical_Reads],
    r.writes,
    s.login_name,
    s.host_name,
    s.program_name,
    CASE
        WHEN r.wait_type LIKE N'LCK%' THEN N'Blocked — find head blocker'
        WHEN r.wait_type LIKE N'LATCH%' OR r.wait_type LIKE N'PAGELATCH%' THEN N'Metadata/buffer latch — see latch script'
        WHEN r.wait_type LIKE N'PAGEIOLATCH%' THEN N'Disk read wait — check storage latency'
        WHEN r.wait_type LIKE N'PREEMPTIVE%' THEN N'OS call — AV/AD/filesystem'
        ELSE N'Correlate with 02_capture_live_session_waits.sql'
    END AS [Interpretation]
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
WHERE r.session_id <> @@SPID
  AND r.status = N'suspended'
ORDER BY r.wait_time DESC;

PRINT '=== TRIAGE COMPLETE ===';
PRINT 'Next: 03_Elapsed_Time_Diagnostics/01_elapsed_vs_worker_time_gap.sql on your slow query.';
