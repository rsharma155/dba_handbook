/*
================================================================================
Purpose:        Analyzes active requests to construct a hierarchy of blocking 
                sessions and retrieves recent deadlock events from system health.
Provides:       Lead blockers, suspended sessions, blocking hierarchy (tree), 
                and detailed XML deadlock reports for the last 5 events.
Importance:     Critical for resolving real-time concurrency issues and 
                diagnosing recurring deadlocks that impact application availability.
Interpretation: Root blockers have a Blocking_Session_ID = 0. Target these first. 
                 Analyze Deadlock_XML to identify the specific resources contested.
Action: For active blocking (Blocking_Session_ID > 0), evaluate terminating the head blocker only as a last resort: KILL <session_id>. Investigate the head blocker's query (Open Session_ID query in SSMS) to understand why it holds locks for prolonged periods. For recurring deadlocks, use the Deadlock_XML to identify the objects and lock modes in conflict, then redesign the access pattern.
Criticality:    Critical
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-- 1. Identify Lead Blockers and Suspended Sessions
SELECT 
    r.session_id AS [Session_ID],
    r.blocking_session_id AS [Blocking_Session_ID],
    s.login_name AS [Login_Name],
    s.host_name AS [Client_Host],
    r.wait_time AS [Wait_Time_ms],
    r.wait_type AS [Wait_Type],
    r.wait_resource AS [Wait_Resource],
    st.text AS [SQL_Statement_Text],
    CAST('Active blocking trace. ' + 
         'Threshold: Wait_Time_ms > 5000ms represents a user-visible slowdown. Blocking_Session_ID = 0 is the root blocker. ' +
         'Recommendation: Target the root blocker session. Evaluate its transaction scope, index design (avoid scans causing lock escalations), and verify lock-avoidance strategies like snapshot isolation.'
         AS VARCHAR(1000)) AS [Metric_Context]
FROM sys.dm_exec_requests AS r WITH (NOLOCK)
INNER JOIN sys.dm_exec_sessions AS s WITH (NOLOCK) ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.blocking_session_id <> 0 
   OR r.session_id IN (SELECT DISTINCT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0)
ORDER BY r.blocking_session_id, r.session_id;

-- 2. Head Blocker & Blocking Chain Hierarchy
PRINT '--- Head Blocker & Blocking Chain Hierarchy ---';
WITH [BlockingTree] AS (
    SELECT 
        session_id,
        blocking_session_id,
        0 AS [Level],
        CAST(session_id AS VARCHAR(MAX)) AS [Path]
    FROM sys.dm_exec_requests
    WHERE (blocking_session_id = 0 OR blocking_session_id IS NULL)
      AND session_id IN (SELECT DISTINCT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0)
    
    UNION ALL
    
    SELECT 
        r.session_id,
        r.blocking_session_id,
        bt.[Level] + 1,
        bt.[Path] + ' -> ' + CAST(r.session_id AS VARCHAR(MAX))
    FROM sys.dm_exec_requests r
    JOIN [BlockingTree] bt ON r.blocking_session_id = bt.session_id
)
SELECT 
    REPLICATE(' | ', [Level]) + CAST(session_id AS VARCHAR) AS [Blocking_Hierarchy],
    [Path],
    [Level],
    CASE WHEN [Level] = 0 THEN '🔴 HEAD BLOCKER' ELSE '🟡 Waiting' END AS [Role]
FROM [BlockingTree]
ORDER BY [Path];

-- 3. Recent Deadlock Events from System Health Session (last 5 deadlocks)
SELECT TOP (5)
    deadlock_event.value('(//deadlock/victim-list/victimProcess/@id)[1]', 'NVARCHAR(50)') AS [Victim_Process_ID],
    deadlock_event.value('(//deadlock/process-list/process[1]/@spid)[1]', 'INT') AS [Victim_SPID],
    deadlock_event.value('(//deadlock/process-list/process[1]/@loginname)[1]', 'NVARCHAR(256)') AS [Victim_Login],
    deadlock_event.value('(//deadlock/process-list/process[1]/@hostname)[1]', 'NVARCHAR(256)') AS [Victim_Host],
    deadlock_event.value('(//deadlock/process-list/process[1]/@waittime)[1]', 'BIGINT') AS [Victim_Wait_Time_ms],
    deadlock_event.value('(//deadlock/process-list/process[2]/@spid)[1]', 'INT') AS [Perpetrator_SPID],
    deadlock_event.value('(//deadlock/process-list/process[2]/@loginname)[1]', 'NVARCHAR(256)') AS [Perpetrator_Login],
    deadlock_event.value('(//deadlock/process-list/process[2]/@hostname)[1]', 'NVARCHAR(256)') AS [Perpetrator_Host],
    deadlock_event AS [Deadlock_XML],
    CAST('Deadlock event details parsed from system_health session. ' +
         'Threshold: Any deadlock is a concern. Frequent deadlocks indicate transaction contention issues. ' +
         'Recommendation: Analyze Deadlock_XML to identify the object/resource involved. Common fixes: index tuning, consistent access order, reduced transaction scope, or enabling RCSI.'
         AS VARCHAR(1000)) AS [Metric_Context]
FROM (
    SELECT 
        x.query('.') AS deadlock_event,
        x.value('(./@timestamp)[1]', 'DATETIME2') AS deadlock_time
    FROM (
        SELECT CAST(target_data AS XML) AS target_data
        FROM sys.dm_xe_session_targets AS st WITH (NOLOCK)
        INNER JOIN sys.dm_xe_sessions AS s WITH (NOLOCK)
            ON st.event_session_address = s.address
        WHERE s.name = 'system_health'
          AND st.target_name = 'ring_buffer'
    ) AS ring_data
    CROSS APPLY target_data.nodes('/RingBuffer/event[@name="xml_deadlock_report"]') AS DeadlockEvent(x)
) AS deadlocks
ORDER BY deadlock_time DESC;
