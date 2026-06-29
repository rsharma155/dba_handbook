/*
================================================================================
Extended Events — Single Query Wait Capture
================================================================================
Purpose:
    Industry-standard proof of what a query waits on when DMVs are inconclusive.
    Captures rpc_completed/sql_batch_completed with wait_info and plan.

How to use:
    1. Run SECTION A to create XE session (once)
    2. Run SECTION B to start session
    3. Execute your slow query
    4. Run SECTION C to review captured waits
    5. Run SECTION D to stop and drop when done

Interpretation:
    wait_info event shows wait_type and duration per execution phase
    Compare total waits to elapsed time — should account for gap

If XE shows mostly LCK_* :
    → blocking confirmed — 05_Concurrency/01_blocking_and_locks.sql

If XE shows PAGEIOLATCH / WRITELOG:
    → storage — 08_Storage_OS/01_io_latency_deep_dive.sql

If no significant waits but high duration:
    → client-side or rare scheduler issue — test sqlcmd -W -b

Criticality: High — use when hints and plan tuning failed
================================================================================
*/

SET NOCOUNT ON;

DECLARE @XeName SYSNAME = N'DBA_PostMigration_QueryWaits';
DECLARE @XePath NVARCHAR(260) = N'C:\Temp\XE_PostMigration_QueryWaits.xel';  -- CHANGE PATH

PRINT '=== SECTION A: CREATE SESSION (run once) ===';
DECLARE @sql NVARCHAR(MAX) = N'
CREATE EVENT SESSION [' + @XeName + N'] ON SERVER
ADD EVENT sqlserver.rpc_completed(
    ACTION(
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.client_app_name,
        sqlserver.username,
        sqlserver.query_hash_signed,
        sqlserver.plan_handle
    )
    WHERE ([sqlserver].[equal_i_sql_unicode_string]([sqlserver].[database_name], N''master'') = 0)  -- adjust filter
),
ADD EVENT sqlserver.sql_batch_completed(
    ACTION(
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.client_app_name,
        sqlserver.username
    )
),
ADD EVENT sqlserver.wait_info(
    ACTION(sqlserver.session_id, sqlserver.sql_text)
    WHERE ([duration] > (1000000))  -- waits > 1 second (microseconds)
),
ADD EVENT sqlserver.sp_statement_completed(
    SET collect_statement = 1
    ACTION(sqlserver.session_id, sqlserver.database_name)
)
ADD TARGET package0.event_file(SET filename = N''' + @XePath + N''', max_file_size = 50, max_rollover_files = 5)
WITH (MAX_MEMORY = 64 MB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS, STARTUP_STATE = OFF);
';

-- Uncomment to create:
-- EXEC sp_executesql @sql;

PRINT 'Uncomment SECTION A create block after setting @XePath and database filter.';

PRINT '=== SECTION B: START SESSION ===';
-- ALTER EVENT SESSION [' + @XeName + N'] ON SERVER STATE = START;

PRINT '=== SECTION C: READ CAPTURED DATA (after running slow query) ===';
SELECT
    CAST(event_data AS XML) AS event_xml
FROM sys.fn_xe_file_target_read_file(@XePath + N'*', NULL, NULL, NULL);

-- Parsed view (SQL 2012+):
/*
SELECT
    x.event_data.value('(event/@name)[1]', 'varchar(50)') AS event_name,
    x.event_data.value('(event/@timestamp)[1]', 'datetime2') AS event_time,
    x.event_data.value('(event/action[@name="session_id"]/value)[1]', 'int') AS session_id,
    x.event_data.value('(event/data[@name="wait_type"]/text)[1]', 'varchar(60)') AS wait_type,
    x.event_data.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000 AS wait_ms,
    x.event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text
FROM (
    SELECT CAST(event_data AS XML) AS event_data
    FROM sys.fn_xe_file_target_read_file('C:\Temp\XE_PostMigration_QueryWaits*.xel', NULL, NULL, NULL)
) AS x
WHERE x.event_data.value('(event/@name)[1]', 'varchar(50)') IN ('wait_info', 'rpc_completed', 'sql_batch_completed')
ORDER BY event_time;
*/

PRINT '=== SECTION D: STOP AND DROP ===';
/*
ALTER EVENT SESSION [' + @XeName + N'] ON SERVER STATE = STOP;
DROP EVENT SESSION [' + @XeName + N'] ON SERVER;
*/

PRINT '=== ALTERNATIVE: Live ring buffer (no file path) for quick test ===';
/*
CREATE EVENT SESSION [DBA_QuickWaits] ON SERVER
ADD EVENT sqlserver.wait_info(Where duration > 500000)
ADD TARGET package0.ring_buffer
WITH (MAX_MEMORY = 16 MB);
ALTER EVENT SESSION [DBA_QuickWaits] ON SERVER STATE = START;
-- run query
SELECT CAST(target_data AS XML) FROM sys.dm_xe_session_targets st
JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
WHERE s.name = 'DBA_QuickWaits';
*/
