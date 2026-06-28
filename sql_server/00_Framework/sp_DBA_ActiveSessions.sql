/*
================================================================================
sp_DBA_ActiveSessions — Real-time active session monitor
================================================================================
Shows what queries are running RIGHT NOW, how long they've been running, what
they're waiting on, and how much CPU/memory/IO they've consumed. Think of this
as a "live snapshot" of your server's current workload.

Key differences from sp_who2 / sp_whoisactive:
  - Includes memory grants, tempdb usage, and wait chain visualization
  - Groups sessions by wait type so you can see patterns at a glance
  - Provides blocking hierarchy with visual tree
  - Shows per-session CPU, reads, writes, and duration in human-readable format

Usage:
    EXEC dbo.sp_DBA_ActiveSessions;
    EXEC dbo.sp_DBA_ActiveSessions @FilterDatabase = N'SalesDB';
    EXEC dbo.sp_DBA_ActiveSessions @FilterWaitType = N'LCK%';
    EXEC dbo.sp_DBA_ActiveSessions @MinCPUSeconds = 10;
    EXEC dbo.sp_DBA_ActiveSessions @IncludeSystemSessions = 1;
    EXEC dbo.sp_DBA_ActiveSessions @OutputMode = 'DETAIL';  -- DETAIL | SUMMARY | BLOCKING
================================================================================
*/
IF OBJECT_ID(N'dbo.sp_DBA_ActiveSessions', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DBA_ActiveSessions AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_DBA_ActiveSessions
    @FilterDatabase       NVARCHAR(128) = NULL,
    @FilterWaitType       NVARCHAR(128) = NULL,
    @MinCPUSeconds        INT = 0,
    @IncludeSystemSessions BIT = 0,
    @OutputMode           VARCHAR(20) = 'DETAIL'
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    ------------------------------------------------------------
    -- Parameter validation
    ------------------------------------------------------------
    IF @OutputMode NOT IN ('DETAIL', 'SUMMARY', 'BLOCKING')
    BEGIN
        RAISERROR(N'@OutputMode must be DETAIL, SUMMARY, or BLOCKING.', 16, 1);
        RETURN;
    END;

    ------------------------------------------------------------
    -- SECTION 1: DETAIL MODE — Every active session with context
    ------------------------------------------------------------
    IF @OutputMode = 'DETAIL'
    BEGIN
        SELECT
            r.session_id                                          AS [Session_ID],
            s.login_name                                          AS [Login_Name],
            s.host_name                                           AS [Client_Host],
            s.program_name                                        AS [Program_Name],
            DB_NAME(r.database_id)                                AS [Database_Name],
            r.status                                              AS [Status],
            r.command                                             AS [Command_Type],
            r.start_time                                          AS [Request_Start_Time],
            DATEDIFF(SECOND, r.start_time, SYSUTCDATETIME())     AS [Duration_Seconds],
            r.wait_type                                           AS [Wait_Type],
            r.wait_time                                           AS [Wait_Time_ms],
            r.wait_resource                                       AS [Wait_Resource],
            r.blocking_session_id                                 AS [Blocking_Session_ID],
            CASE
                WHEN r.blocking_session_id = 0 OR r.blocking_session_id IS NULL THEN NULL
                ELSE (
                    SELECT TOP (1) s2.login_name + N' (' + CAST(r.blocking_session_id AS NVARCHAR(10)) + N')'
                    FROM sys.dm_exec_sessions s2
                    WHERE s2.session_id = r.blocking_session_id
                )
            END AS [Blocking_Source],
            r.cpu_time                                            AS [CPU_ms],
            r.reads * 8 / 1024                                   AS [Reads_MB],
            r.writes * 8 / 1024                                  AS [Writes_MB],
            r.total_elapsed_time / 1000                           AS [Total_Elapsed_Sec],
            r.granted_query_memory * 8 / 1024                    AS [Memory_Grant_MB],
            r.open_transaction_count                              AS [Open_Tran_Count],
            r.transaction_isolation_level                         AS [Isolation_Level],
            SUBSTRING(st.text, (r.statement_start_offset / 2) + 1,
                ((CASE r.statement_end_offset
                    WHEN -1 THEN DATALENGTH(st.text)
                    ELSE r.statement_end_offset
                 END - r.statement_start_offset) / 2) + 1)      AS [Current_Statement],
            -- Blocked session info
            CASE
                WHEN r.blocking_session_id <> 0 AND r.blocking_session_id IS NOT NULL
                THEN (
                    SELECT SUBSTRING(st2.text, (r2.statement_start_offset / 2) + 1,
                        ((CASE r2.statement_end_offset
                            WHEN -1 THEN DATALENGTH(st2.text)
                            ELSE r2.statement_end_offset
                         END - r2.statement_start_offset) / 2) + 1)
                    FROM sys.dm_exec_requests r2
                    CROSS APPLY sys.dm_exec_sql_text(r2.sql_handle) st2
                    WHERE r2.session_id = r.blocking_session_id
                )
                ELSE NULL
            END AS [Blocking_Statement],
            qp.query_plan                                        AS [Query_Plan]
        FROM sys.dm_exec_requests AS r
        INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
        OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
        OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) AS qp
        WHERE r.session_id <> @@SPID
          AND (@IncludeSystemSessions = 1 OR s.is_user_process = 1)
          AND (@FilterDatabase IS NULL OR DB_NAME(r.database_id) LIKE @FilterDatabase)
          AND (@FilterWaitType IS NULL OR r.wait_type LIKE @FilterWaitType)
          AND (r.cpu_time / 1000) >= @MinCPUSeconds
        ORDER BY r.cpu_time DESC;
    END;

    ------------------------------------------------------------
    -- SECTION 2: SUMMARY MODE — Aggregated by wait type + database
    ------------------------------------------------------------
    IF @OutputMode = 'SUMMARY'
    BEGIN
        -- 2a. Wait type distribution
        SELECT N'WAIT TYPE DISTRIBUTION' AS [Section];
        SELECT
            r.wait_type                                         AS [Wait_Type],
            COUNT(*)                                            AS [Session_Count],
            SUM(r.cpu_time) / 1000                              AS [Total_CPU_Sec],
            SUM(r.wait_time) / 1000                             AS [Total_Wait_Sec],
            SUM(r.granted_query_memory * 8 / 1024)             AS [Total_Memory_Grant_MB],
            SUM(r.blocking_session_id) AS [Blocking_Sessions_Agg],
            CASE
                WHEN r.wait_type LIKE 'LCK_%' THEN 'Blocking — check blocking_and_deadlocks.sql'
                WHEN r.wait_type = 'CXPACKET' THEN 'Parallelism — review MAXDOP/CTFP settings'
                WHEN r.wait_type = 'PAGEIOLATCH_%' THEN 'Disk I/O — run disk_latency.sql'
                WHEN r.wait_type = 'RESOURCE_SEMAPHORE' THEN 'Memory — check memory grants'
                WHEN r.wait_type = 'ASYNC_NETWORK_IO' THEN 'Client — app consuming slowly'
                WHEN r.wait_type LIKE 'HADR_%' THEN 'AlwaysOn AG — check sync latency'
                WHEN r.wait_type = 'SOS_SCHEDULER_YIELD' THEN 'CPU — check top CPU queries'
                ELSE 'Review Microsoft Docs for this wait type'
            END AS [Investigation_Note]
        FROM sys.dm_exec_requests AS r
        INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
        WHERE r.session_id <> @@SPID
          AND (@IncludeSystemSessions = 1 OR s.is_user_process = 1)
          AND r.wait_type IS NOT NULL
        GROUP BY r.wait_type
        ORDER BY COUNT(*) DESC;

        -- 2b. Database workload distribution
        SELECT N'DATABASE WORKLOAD DISTRIBUTION' AS [Section];
        SELECT
            DB_NAME(r.database_id)                              AS [Database_Name],
            COUNT(*)                                            AS [Active_Sessions],
            SUM(r.cpu_time) / 1000                              AS [Total_CPU_Sec],
            SUM(r.reads * 8 / 1024)                             AS [Total_Reads_MB],
            SUM(r.writes * 8 / 1024)                            AS [Total_Writes_MB],
            SUM(r.granted_query_memory * 8 / 1024)             AS [Total_Memory_Grant_MB],
            MAX(DATEDIFF(SECOND, r.start_time, SYSUTCDATETIME())) AS [Longest_Running_Sec]
        FROM sys.dm_exec_requests AS r
        INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
        WHERE r.session_id <> @@SPID
          AND (@IncludeSystemSessions = 1 OR s.is_user_process = 1)
        GROUP BY r.database_id
        ORDER BY SUM(r.cpu_time) DESC;

        -- 2c. Client application distribution
        SELECT N'APPLICATION WORKLOAD DISTRIBUTION' AS [Section];
        SELECT
            s.program_name                                      AS [Application_Name],
            COUNT(*)                                            AS [Active_Sessions],
            SUM(r.cpu_time) / 1000                              AS [Total_CPU_Sec],
            SUM(r.reads * 8 / 1024)                             AS [Total_Reads_MB],
            SUM(r.granted_query_memory * 8 / 1024)             AS [Total_Memory_Grant_MB],
            MAX(DATEDIFF(SECOND, r.start_time, SYSUTCDATETIME())) AS [Longest_Running_Sec]
        FROM sys.dm_exec_requests AS r
        INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
        WHERE r.session_id <> @@SPID
          AND (@IncludeSystemSessions = 1 OR s.is_user_process = 1)
        GROUP BY s.program_name
        ORDER BY SUM(r.cpu_time) DESC;
    END;

    ------------------------------------------------------------
    -- SECTION 3: BLOCKING MODE — Visual blocking tree
    ------------------------------------------------------------
    IF @OutputMode = 'BLOCKING'
    BEGIN
        -- Check if there is any active blocking
        IF NOT EXISTS (
            SELECT 1 FROM sys.dm_exec_requests
            WHERE blocking_session_id <> 0 AND blocking_session_id IS NOT NULL
        )
        BEGIN
            PRINT N'No active blocking detected. All sessions are running freely.';
            RETURN;
        END;

        -- 3a. Blocking hierarchy tree
        SELECT N'BLOCKING HIERARCHY TREE' AS [Section];
        WITH BlockingTree AS (
            SELECT
                r.session_id,
                r.blocking_session_id,
                0 AS [Level],
                CAST(CAST(r.session_id AS NVARCHAR(10)) AS NVARCHAR(MAX)) AS [Path]
            FROM sys.dm_exec_requests r
            WHERE (r.blocking_session_id = 0 OR r.blocking_session_id IS NULL)
              AND r.session_id IN (
                  SELECT DISTINCT blocking_session_id
                  FROM sys.dm_exec_requests
                  WHERE blocking_session_id <> 0 AND blocking_session_id IS NOT NULL
              )

            UNION ALL

            SELECT
                r.session_id,
                r.blocking_session_id,
                bt.[Level] + 1,
                bt.[Path] + N' -> ' + CAST(CAST(r.session_id AS NVARCHAR(10)) AS NVARCHAR(MAX))
            FROM sys.dm_exec_requests r
            INNER JOIN BlockingTree bt ON r.blocking_session_id = bt.session_id
        )
        SELECT
            REPLICATE(N'  ', [Level]) + N'[' + CAST(session_id AS NVARCHAR(10)) + N']'
                + CASE WHEN [Level] = 0 THEN N' <-- ROOT BLOCKER' ELSE N'' END  AS [Blocking_Tree],
            [Path] AS [Full_Chain],
            [Level] AS [Depth]
        FROM BlockingTree
        ORDER BY [Path];

        -- 3b. Root blocker details
        SELECT N'ROOT BLOCKER DETAILS' AS [Section];
        SELECT
            r.session_id                                        AS [Root_Blocker_Session],
            s.login_name                                        AS [Login_Name],
            s.host_name                                         AS [Client_Host],
            s.program_name                                      AS [Program_Name],
            DB_NAME(r.database_id)                              AS [Database_Name],
            r.start_time                                        AS [Request_Start_Time],
            DATEDIFF(SECOND, r.start_time, SYSUTCDATETIME())   AS [Duration_Seconds],
            r.cpu_time / 1000                                   AS [CPU_Sec],
            r.open_transaction_count                            AS [Open_Tran_Count],
            SUBSTRING(st.text, (r.statement_start_offset / 2) + 1,
                ((CASE r.statement_end_offset
                    WHEN -1 THEN DATALENGTH(st.text)
                    ELSE r.statement_end_offset
                 END - r.statement_start_offset) / 2) + 1)    AS [Blocking_Statement]
        FROM sys.dm_exec_requests r
        INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
        CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
        WHERE r.session_id IN (
            SELECT DISTINCT blocking_session_id
            FROM sys.dm_exec_requests
            WHERE blocking_session_id <> 0 AND blocking_session_id IS NOT NULL
        );

        -- 3c. All blocked sessions
        SELECT N'BLOCKED SESSIONS (victims)' AS [Section];
        SELECT
            r.session_id                                        AS [Blocked_Session],
            r.blocking_session_id                               AS [Blocked_By],
            s.login_name                                        AS [Blocked_Login],
            DB_NAME(r.database_id)                              AS [Database_Name],
            r.wait_type                                         AS [Wait_Type],
            r.wait_time                                         AS [Wait_Time_ms],
            r.wait_resource                                     AS [Wait_Resource],
            DATEDIFF(SECOND, r.start_time, SYSUTCDATETIME())   AS [Duration_Seconds],
            SUBSTRING(st.text, (r.statement_start_offset / 2) + 1,
                ((CASE r.statement_end_offset
                    WHEN -1 THEN DATALENGTH(st.text)
                    ELSE r.statement_end_offset
                 END - r.statement_start_offset) / 2) + 1)    AS [Blocked_Statement]
        FROM sys.dm_exec_requests r
        INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
        CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
        WHERE r.blocking_session_id <> 0 AND r.blocking_session_id IS NOT NULL
        ORDER BY r.wait_time DESC;
    END;
END;
GO
