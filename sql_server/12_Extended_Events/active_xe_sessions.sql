/*
================================================================================
SQL Server Extended Events (XE) Monitoring
================================================================================
Description:
    Lists all active Extended Event sessions and their targets across the
    instance, and extracts recent deadlock events from the system_health session.
    Useful for auditing XE usage and investigating deadlocks.

Output:
    (1) Active XE sessions with target details
    (2) Recent deadlock events (last 5) from system_health with XML graph

Action:
    Review active sessions to ensure no runaway XE sessions are consuming
    resources. For deadlock events: analyze the Deadlock_Graph XML to identify
    the victim process, contested objects, and lock modes. Use the process IDs
    and query text to locate and fix the deadlocking code. Consider adding
    custom XE sessions for targeted monitoring (e.g., long-running queries,
    login failures).

Criticality: Low
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-- 1. Active Extended Event Sessions and Targets
PRINT '--- Active Extended Event Sessions ---';
SELECT
    s.name AS [Session_Name],
    s.create_time,
    t.target_name,
    p.name AS target_package_name,
  CASE
        WHEN s.name = N'system_health' THEN N'SYSTEM DEFAULT'
        WHEN s.name = N'AlwaysOn_health' THEN N'AG MONITOR'
        ELSE N'USER DEFINED'
    END AS [Session_Type]
FROM sys.dm_xe_sessions AS s
LEFT JOIN sys.dm_xe_session_targets AS t
    ON s.address = t.event_session_address
LEFT JOIN sys.dm_xe_packages AS p
    ON t.target_package_guid = p.guid
ORDER BY s.name, t.target_name;

-- 2. Deadlock Extraction from System Health (Last 5)
PRINT '--- Recent Deadlocks (from system_health session) ---';
IF EXISTS (SELECT 1 FROM sys.dm_xe_sessions WHERE name = N'system_health')
BEGIN
    SELECT TOP (5)
        event_data.value(N'(event/@timestamp)[1]', N'datetime2') AS [Event_Time],
        event_data.query(N'(event/data[@name="xml_report"]/value/deadlock)') AS [Deadlock_Graph]
    FROM sys.dm_xe_session_targets AS st
    INNER JOIN sys.dm_xe_sessions AS s
        ON s.address = st.event_session_address
    CROSS APPLY (SELECT CAST(st.target_data AS XML) AS target_data_xml) AS t
    CROSS APPLY t.target_data_xml.nodes(N'RingBufferTarget/event[@name="xml_deadlock_report"]') AS x(event_data)
    WHERE s.name = N'system_health'
      AND st.target_name = N'ring_buffer'
    ORDER BY [Event_Time] DESC;
END
ELSE
    PRINT 'system_health session is not running.';
