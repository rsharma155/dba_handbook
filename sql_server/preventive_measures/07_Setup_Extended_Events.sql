/*
================================================================================
07_Setup_Extended_Events.sql - Layer 1: Extended Events (Optional)
================================================================================
Purpose:    Extended Events for real-time capture (OPTIONAL - DMV monitoring works without this)
Version:    2.0
Author:     DBA Team
Created:    2026-06-19
Compatible: SQL Server 2016, 2017, 2019, 2022

Usage:      OPTION A: Run this script in SSMS (recommended)
            OPTION B: Use the sp_executesql versions below

Note:       The core monitoring framework works without XE sessions.
            XE provides additional real-time capture but is optional.
================================================================================
*/

USE [master];
GO

PRINT N'=====================================================';
PRINT N'Extended Events Setup - Two Options';
PRINT N'=====================================================';
PRINT N'';
PRINT N'OPTION A: Run in SSMS (copy/paste each CREATE statement)';
PRINT N'OPTION B: The framework works without XE - skip this file';
PRINT N'';
PRINT N'The DMV-based monitoring in Layer 2 provides full functionality.';
PRINT N'XE sessions are an optional enhancement for real-time capture.';
PRINT N'=====================================================';
GO

-- Create helper function in DBARepository
USE [DBARepository];
GO

IF OBJECT_ID(N'dbo.fn_Get_XE_Events', N'TF') IS NOT NULL
    DROP FUNCTION [dbo].[fn_Get_XE_Events];
GO

CREATE FUNCTION [dbo].[fn_Get_XE_Events]
(
    @Session_Name VARCHAR(128),
    @Max_Events INT = 100
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (@Max_Events)
        event_data.value('(event/@name)[1]', 'VARCHAR(128)') AS Event_Name,
        event_data.value('(event/@timestamp)[1]', 'DATETIME2') AS Timestamp,
        event_data.value('(event/data[@name="duration"]/value)[1]', 'BIGINT') / 1000 AS Duration_ms,
        event_data.value('(event/data[@name="cpu_time"]/value)[1]', 'BIGINT') / 1000 AS CPU_Time_ms,
        event_data.value('(event/data[@name="logical_reads"]/value)[1]', 'BIGINT') AS Logical_Reads,
        event_data.value('(event/data[@name="row_count"]/value)[1]', 'BIGINT') AS Row_Count,
        event_data.value('(event/action[@name="database_name"]/value)[1]', 'SYSNAME') AS Database_Name,
        event_data.value('(event/action[@name="username"]/value)[1]', 'SYSNAME') AS Login_Name,
        event_data.value('(event/action[@name="client_hostname"]/value)[1]', 'NVARCHAR(128)') AS Host_Name,
        event_data.value('(event/action[@name="client_app_name"]/value)[1]', 'NVARCHAR(128)') AS Program_Name,
        event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') AS SQL_Text,
        event_data.value('(event/action[@name="session_id"]/value)[1]', 'INT') AS Session_ID
    FROM (
        SELECT CAST(target_data AS XML) AS target_data
        FROM sys.dm_xe_session_targets st
        INNER JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
        WHERE s.name = @Session_Name AND st.target_name = 'ring_buffer'
    ) AS Data
    CROSS APPLY target_data.nodes('RingBufferTarget/event') AS XEvent(event_data)
);
GO

PRINT N'Created dbo.fn_Get_XE_Events function.';
GO

/*
-- ============================================================
-- OPTIONAL: Run these in SSMS to create XE sessions manually
-- ============================================================

-- Session 1: Long Queries
CREATE EVENT SESSION [Governance_Long_Queries] ON SERVER
ADD EVENT sqlserver.sql_statement_completed(
    ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_name, sqlserver.sql_text, sqlserver.username, sqlserver.session_id)
    WHERE duration > 10000000 AND sqlserver.is_system = 0
),
ADD EVENT sqlserver.rpc_completed(
    ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_name, sqlserver.sql_text, sqlserver.username, sqlserver.session_id)
    WHERE duration > 10000000 AND sqlserver.is_system = 0
)
ADD TARGET package0.ring_buffer(SET max_memory=(8192))
ADD TARGET package0.event_file(SET filename=N'C:\XE\Governance_Long_Queries.xel', max_file_size=(100), max_rollover_files=(10))
WITH (max_memory=(16384), event_retention_mode=allow_single_loss, max_dispatch_latency=(5) seconds, memory_partition_mode=none, track_causality=on, startup_state=on);
GO

-- Session 2: Massive DML
CREATE EVENT SESSION [Governance_Massive_DML] ON SERVER
ADD EVENT sqlserver.sql_statement_completed(
    ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_name, sqlserver.sql_text, sqlserver.username, sqlserver.session_id)
    WHERE row_count > 100000 AND sqlserver.is_system = 0
),
ADD EVENT sqlserver.rpc_completed(
    ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_name, sqlserver.sql_text, sqlserver.username, sqlserver.session_id)
    WHERE row_count > 100000 AND sqlserver.is_system = 0
)
ADD TARGET package0.ring_buffer(SET max_memory=(4096))
ADD TARGET package0.event_file(SET filename=N'C:\XE\Governance_Massive_DML.xel', max_file_size=(100), max_rollover_files=(5))
WITH (max_memory=(8192), event_retention_mode=allow_single_loss, max_dispatch_latency=(5) seconds, memory_partition_mode=none, track_causality=on, startup_state=on);
GO

-- Session 3: Blocking
CREATE EVENT SESSION [Governance_Blocking] ON SERVER
ADD EVENT sqlserver.blocked_process_report(
    ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_name, sqlserver.sql_text, sqlserver.username, sqlserver.session_id)
    WHERE duration > 5000
),
ADD EVENT sqlserver.xml_deadlock_report(
    ACTION(sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.database_name, sqlserver.sql_text, sqlserver.username, sqlserver.session_id)
)
ADD TARGET package0.ring_buffer(SET max_memory=(4096))
ADD TARGET package0.event_file(SET filename=N'C:\XE\Governance_Blocking.xel', max_file_size=(100), max_rollover_files=(5))
WITH (max_memory=(8192), event_retention_mode=allow_single_loss, max_dispatch_latency=(5) seconds, memory_partition_mode=none, track_causality=on, startup_state=on);
GO

-- Start sessions
ALTER EVENT SESSION [Governance_Long_Queries] ON SERVER STATE = START;
ALTER EVENT SESSION [Governance_Massive_DML] ON SERVER STATE = START;
ALTER EVENT SESSION [Governance_Blocking] ON SERVER STATE = START;
GO
*/

PRINT N'Layer 1 setup complete!';
PRINT N'The fn_Get_XE_Events function is ready for when XE sessions are created.';
GO