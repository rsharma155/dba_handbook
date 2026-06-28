/*
================================================================================
Purpose:        Advanced deadlock analysis from Extended Events sessions.
                Extracts and parses deadlock XML from system_health and any
                custom deadlock XE session, providing victim identification,
                process details, resource contention, and query text.
Provides:       - Deadlock summary with timestamps, victims, and wait times
                - Per-process details: login, host, database, isolation level,
                  wait type, wait time, and the exact statement that deadlocked
                - Resource contention map: objects, indexes, and lock modes
                - Blocking chain visualization within each deadlock
                - Historical deadlock frequency trend (last 7 days)
Importance:     Deadlocks are inevitable in well-concurrent systems. This script
                moves beyond "there was a deadlock" to "why it happened and what
                resources were contested," enabling targeted fixes.
Interpretation: Focus on the OBJECT involved (table/index) and the lock mode
                 (X vs S). If the same object appears repeatedly, redesign the
                 access pattern or index strategy for that object.
Action: Identify the most contested object (table/index) from the Resource_Contention_Map. If the same object appears repeatedly, consider: (1) reducing transaction scope, (2) accessing the object in the same order across transactions, (3) adding covering indexes to reduce lock duration, or (4) enabling READ_COMMITTED_SNAPSHOT if acceptable. For historical trend, check deadlock_frequency to see if the pattern is worsening.
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @DeadlockCount INT;

------------------------------------------------------------
-- 1. Recent Deadlock Events (last 20 from system_health)
------------------------------------------------------------
SELECT TOP (20)
    xdr.value('(event/@timestamp)[1]', 'DATETIME2')             AS [Event_Timestamp],
    xdr.value('(//deadlock/@priority)[1]', 'INT')               AS [Priority],
    xdr.value('(//deadlock/victim-list/victimProcess/@id)[1]', 'NVARCHAR(100)') AS [Victim_Process_ID],
    xdr.value('(//deadlock/process-list/process/@spid)[1]', 'INT')             AS [SPID_1],
    xdr.value('(//deadlock/process-list/process/@loginname)[1]', 'NVARCHAR(128)') AS [SPID_1_Login],
    xdr.value('(//deadlock/process-list/process/@hostname)[1]', 'NVARCHAR(128)') AS [SPID_1_Host],
    xdr.value('(//deadlock/process-list/process/@clientapp)[1]', 'NVARCHAR(128)') AS [SPID_1_App],
    xdr.value('(//deadlock/process-list/process/@currentdb)[1]', 'INT')        AS [SPID_1_DBID],
    xdr.value('(//deadlock/process-list/process/@isolationlevel)[1]', 'NVARCHAR(50)') AS [SPID_1_Isolation],
    xdr.value('(//deadlock/process-list/process/@waittime)[1]', 'INT')         AS [SPID_1_WaitTime_ms],
    xdr.value('(//deadlock/process-list/process/@lastbatchstarted)[1]', 'NVARCHAR(30)') AS [SPID_1_LastBatch],
    xdr.value('(//deadlock/process-list/process/@status)[1]', 'NVARCHAR(30)')  AS [SPID_1_Status],
    xdr.value('(//deadlock/process-list/process/@trancount)[1]', 'INT')        AS [SPID_1_TranCount],
    -- SPID 2
    xdr.value('(//deadlock/process-list/process[2]/@spid)[1]', 'INT')          AS [SPID_2],
    xdr.value('(//deadlock/process-list/process[2]/@loginname)[1]', 'NVARCHAR(128)') AS [SPID_2_Login],
    xdr.value('(//deadlock/process-list/process[2]/@hostname)[1]', 'NVARCHAR(128)') AS [SPID_2_Host],
    xdr.value('(//deadlock/process-list/process[2]/@clientapp)[1]', 'NVARCHAR(128)') AS [SPID_2_App],
    xdr.value('(//deadlock/process-list/process[2]/@currentdb)[1]', 'INT')     AS [SPID_2_DBID],
    xdr.value('(//deadlock/process-list/process[2]/@waittime)[1]', 'INT')      AS [SPID_2_WaitTime_ms],
    -- SPID 3 (if present)
    xdr.value('(//deadlock/process-list/process[3]/@spid)[1]', 'INT')          AS [SPID_3],
    xdr.value('(//deadlock/process-list/process[3]/@loginname)[1]', 'NVARCHAR(128)') AS [SPID_3_Login]
FROM (
    SELECT
        XEvent.query('.') AS xdr
    FROM (
        SELECT CAST(target_data AS XML) AS target_data
        FROM sys.dm_xe_session_targets st
        INNER JOIN sys.dm_xe_sessions s ON st.event_session_address = s.address
        WHERE s.name = N'system_health'
          AND st.target_name = N'event_file'
    ) AS data
    CROSS APPLY target_data.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEvent(XEvent)
) AS DeadlockEvents
ORDER BY xdr.value('(event/@timestamp)[1]', 'DATETIME2') DESC;

------------------------------------------------------------
-- 2. Process Details: What each session was doing
------------------------------------------------------------
SELECT N'PROCESS DETAILS (from last 5 deadlocks)' AS [Section];
SELECT TOP (10)
    xdr.value('(event/@timestamp)[1]', 'DATETIME2')             AS [Deadlock_Time],
    proc_node.value('@spid', 'INT')                              AS [SPID],
    proc_node.value('@loginname', 'NVARCHAR(128)')               AS [Login_Name],
    proc_node.value('@hostname', 'NVARCHAR(128)')                AS [Host_Name],
    proc_node.value('@clientapp', 'NVARCHAR(128)')               AS [Application],
    proc_node.value('@currentdb', 'INT')                         AS [Database_ID],
    DB_NAME(proc_node.value('@currentdb', 'INT'))                AS [Database_Name],
    proc_node.value('@isolationlevel', 'NVARCHAR(50)')           AS [Isolation_Level],
    proc_node.value('@status', 'NVARCHAR(30)')                   AS [Status],
    proc_node.value('@trancount', 'INT')                         AS [Transaction_Count],
    proc_node.value('@waittime', 'INT')                          AS [Wait_Time_ms],
    proc_node.value('@lastbatchstarted', 'NVARCHAR(30)')         AS [Last_Batch_Started],
    -- Execution stack (procedure + line)
    proc_node.value('(executionStack/frame[1]/@procname)[1]', 'NVARCHAR(256)') AS [Top_Proc],
    proc_node.value('(executionStack/frame[1]/@line)[1]', 'INT')              AS [Line_Number],
    proc_node.value('(executionStack/frame[1]/@sqlhandle)[1]', 'NVARCHAR(256)') AS [SQL_Handle],
    -- Input buffer (the actual statement)
    proc_node.value('(inputbuf)[1]', 'NVARCHAR(MAX)')           AS [Input_Buffer]
FROM (
    SELECT
        XEvent.query('.') AS xdr
    FROM (
        SELECT CAST(target_data AS XML) AS target_data
        FROM sys.dm_xe_session_targets st
        INNER JOIN sys.dm_xe_sessions s ON st.event_session_address = s.address
        WHERE s.name = N'system_health'
          AND st.target_name = N'event_file'
    ) AS data
    CROSS APPLY target_data.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEvent(XEvent)
) AS DeadlockEvents
CROSS APPLY xdr.nodes('//deadlock/process-list/process') AS ProcessNode(proc_node)
ORDER BY xdr.value('(event/@timestamp)[1]', 'DATETIME2') DESC;

------------------------------------------------------------
-- 3. Resource Contention: What objects were locked
------------------------------------------------------------
SELECT N'OBJECTS CONTENDED (last 5 deadlocks)' AS [Section];
SELECT TOP (15)
    xdr.value('(event/@timestamp)[1]', 'DATETIME2')             AS [Deadlock_Time],
    obj_node.value('@dbid', 'INT')                               AS [Database_ID],
    DB_NAME(obj_node.value('@dbid', 'INT'))                      AS [Database_Name],
    obj_node.value('@objectname', 'NVARCHAR(256)')               AS [Object_Name],
    obj_node.value('@indexname', 'NVARCHAR(256)')                AS [Index_Name],
    obj_node.value('@indexid', 'INT')                            AS [Index_ID],
    obj_node.value('@mode', 'NVARCHAR(20)')                      AS [Lock_Mode],
    CASE obj_node.value('@mode', 'NVARCHAR(20)')
        WHEN 'X'  THEN 'Exclusive — WRITE conflict. Check for concurrent updates on same rows.'
        WHEN 'S'  THEN 'Shared — READ contention. Multiple readers blocked by a writer.'
        WHEN 'U'  THEN 'Update — transitioning to X. Deadlock between UPDATE and SELECT.'
        WHEN 'IX' THEN 'Intent Exclusive — table-level lock for page/row exclusive.'
        WHEN 'IS' THEN 'Intent Shared — table-level lock for page/row shared.'
        ELSE 'Review lock escalation patterns.'
    END AS [Interpretation]
FROM (
    SELECT
        XEvent.query('.') AS xdr
    FROM (
        SELECT CAST(target_data AS XML) AS target_data
        FROM sys.dm_xe_session_targets st
        INNER JOIN sys.dm_xe_sessions s ON st.event_session_address = s.address
        WHERE s.name = N'system_health'
          AND st.target_name = N'event_file'
    ) AS data
    CROSS APPLY target_data.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEvent(XEvent)
) AS DeadlockEvents
CROSS APPLY xdr.nodes('//deadlock/resource-list/*') AS ObjNode(obj_node)
WHERE obj_node.value('@objectname', 'NVARCHAR(256)') IS NOT NULL
ORDER BY xdr.value('(event/@timestamp)[1]', 'DATETIME2') DESC;

------------------------------------------------------------
-- 4. Deadlock Frequency Trend (last 7 days by day)
------------------------------------------------------------
SELECT N'DEADLOCK FREQUENCY TREND (last 7 days)' AS [Section];
;WITH DeadlockDates AS (
    SELECT
        CAST(xdr.value('(event/@timestamp)[1]', 'DATETIME2') AS DATE) AS [Deadlock_Date],
        CASE WHEN xdr.value('(//deadlock/victim-list/victimProcess/@id)[1]', 'NVARCHAR(100)') IS NOT NULL THEN 1 ELSE 0 END AS IsVictim
    FROM (
        SELECT
            XEvent.query('.') AS xdr
        FROM (
            SELECT CAST(target_data AS XML) AS target_data
            FROM sys.dm_xe_session_targets st
            INNER JOIN sys.dm_xe_sessions s ON st.event_session_address = s.address
            WHERE s.name = N'system_health'
              AND st.target_name = N'event_file'
        ) AS data
        CROSS APPLY target_data.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEvent(XEvent)
    ) AS DeadlockEvents
    WHERE xdr.value('(event/@timestamp)[1]', 'DATETIME2') >= DATEADD(DAY, -7, SYSUTCDATETIME())
)
SELECT
    [Deadlock_Date],
    COUNT(*) AS [Deadlock_Count],
    SUM(IsVictim) AS [Victims]
FROM DeadlockDates
GROUP BY [Deadlock_Date]
ORDER BY Deadlock_Date DESC;

------------------------------------------------------------
-- 5. Top Deadlock-Prone Objects (last 7 days)
------------------------------------------------------------
SELECT N'TOP DEADLOCK-PRONE OBJECTS (last 7 days)' AS [Section];
;WITH DeadlockObjects AS (
    SELECT
        obj_node.value('@objectname', 'NVARCHAR(256)')               AS [Object_Name],
        DB_NAME(obj_node.value('@dbid', 'INT'))                      AS [Database_Name],
        xdr.value('(event/@timestamp)[1]', 'DATETIME2')             AS [Event_Time]
    FROM (
        SELECT
            XEvent.query('.') AS xdr
        FROM (
            SELECT CAST(target_data AS XML) AS target_data
            FROM sys.dm_xe_session_targets st
            INNER JOIN sys.dm_xe_sessions s ON st.event_session_address = s.address
            WHERE s.name = N'system_health'
              AND st.target_name = N'event_file'
        ) AS data
        CROSS APPLY target_data.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEvent(XEvent)
    ) AS DeadlockEvents
    CROSS APPLY xdr.nodes('//deadlock/resource-list/*') AS ObjNode(obj_node)
    WHERE obj_node.value('@objectname', 'NVARCHAR(256)') IS NOT NULL
      AND xdr.value('(event/@timestamp)[1]', 'DATETIME2') >= DATEADD(DAY, -7, SYSUTCDATETIME())
)
SELECT TOP (10)
    [Object_Name],
    [Database_Name],
    COUNT(*)                   AS [Deadlock_Involvements],
    MIN([Event_Time])          AS [First_Seen],
    MAX([Event_Time])          AS [Last_Seen]
FROM DeadlockObjects
GROUP BY [Object_Name], [Database_Name]
ORDER BY COUNT(*) DESC;

------------------------------------------------------------
-- 6. Custom XE Session Check (if user has a dedicated deadlock session)
------------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.dm_xe_sessions
    WHERE name LIKE N'%Deadlock%' AND name <> N'system_health'
)
BEGIN
    DECLARE @CustomSession NVARCHAR(128);
    SELECT TOP (1) @CustomSession = name FROM sys.dm_xe_sessions
    WHERE name LIKE N'%Deadlock%' AND name <> N'system_health';

    DECLARE @SQL NVARCHAR(MAX) = N'
        SELECT TOP (10)
            xdr.value(''(event/@timestamp)[1]'', ''DATETIME2'') AS [Event_Timestamp],
            xdr.value(''(//deadlock/victim-list/victimProcess/@id)[1]'', ''NVARCHAR(100)'') AS [Victim],
            xdr.value(''(//deadlock/process-list/process/@spid)[1]'', ''INT'') AS [SPID_1],
            xdr.value(''(//deadlock/process-list/process/@loginname)[1]'', ''NVARCHAR(128)'') AS [Login_1],
            xdr.value(''(//deadlock/process-list/process[2]/@spid)[1]'', ''INT'') AS [SPID_2],
            xdr.value(''(//deadlock/process-list/process[2]/@loginname)[1]'', ''NVARCHAR(128)'') AS [Login_2]
        FROM (
            SELECT XEvent.query(''.'') AS xdr
            FROM (
                SELECT CAST(target_data AS XML) AS target_data
                FROM sys.dm_xe_session_targets st
                INNER JOIN sys.dm_xe_sessions s ON st.event_session_address = s.address
                WHERE s.name = N''' + @CustomSession + N'''
                  AND st.target_name = N''event_file''
            ) AS data
            CROSS APPLY target_data.nodes(''RingBufferTarget/event[@name="xml_deadlock_report"]'') AS XEvent(XEvent)
        ) AS CustomDeadlocks
        ORDER BY xdr.value(''(event/@timestamp)[1]'', ''DATETIME2'') DESC;';

    PRINT N'--- Deadlocks from custom XE session: ' + @CustomSession + N' ---';
    EXEC(@SQL);
END;

PRINT N'--- Analysis complete. Focus on objects that appear repeatedly in section 5. ---';
PRINT N'--- Common fixes: add covering indexes, reduce transaction scope, use SNAPSHOT isolation. ---';
GO
