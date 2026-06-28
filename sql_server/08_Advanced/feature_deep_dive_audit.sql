/*
================================================================================
SQL Server Advanced Category: Detailed Feature Configuration Audit
================================================================================
Description:
    Exhaustive audit of CDC internal job parameters, Query Store current
    configuration, Replication throughput metrics, and SQL Agent job ownership.

Output:
    Multiple result sets covering CDC job configuration, Query Store settings,
    replication performance, and job owner audit.

Action:
    Review CDC job parameters (maxtrans, maxscans) — adjust for your latency
    requirements. Verify Query Store settings (max_storage_size_mb, data_flush_
    interval_seconds) against your recovery and monitoring needs. Check for jobs
    owned by disabled logins or service accounts that may cause failures after
    password changes.

Criticality: Medium
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @MajorVersion INT = CAST(PARSENAME(CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)), 4) AS INT);

-- 1. CDC Internal Job Configuration (msdb CDC jobs)
PRINT '--- CDC Job Parameters ---';
IF EXISTS (SELECT 1 FROM sys.databases WHERE is_cdc_enabled = 1)
BEGIN
    IF OBJECT_ID(N'msdb.dbo.cdc_jobs', N'U') IS NOT NULL
    BEGIN
        IF @MajorVersion >= 16
            EXEC(N'SELECT
                DB_NAME(j.database_id) AS [Database_Name],
                j.job_type AS [Job_Type],
                j.job_id AS [Job_Id],
                j.maxtrans AS [Max_Trans_Per_Cycle],
                j.maxscans AS [Max_Scan_Cycles],
                j.pollinginterval AS [Polling_Interval_s],
                j.retention AS [Cleanup_Retention_Minutes],
                CAST(N''CDC job parameters control log reader load. maxscans * maxtrans = max transactions per agent run. Low values with high volume cause lag.'' AS NVARCHAR(1000)) AS [Description]
            FROM msdb.dbo.cdc_jobs AS j
            ORDER BY j.database_id, j.job_type;');
        ELSE
            EXEC(N'SELECT
                j.database_name AS [Database_Name],
                j.job_type AS [Job_Type],
                j.job_name AS [Job_Name],
                j.maxtrans AS [Max_Trans_Per_Cycle],
                j.maxscans AS [Max_Scan_Cycles],
                j.pollinginterval AS [Polling_Interval_s],
                j.retention AS [Cleanup_Retention_Minutes],
                CAST(N''CDC job parameters control log reader load. maxscans * maxtrans = max transactions per agent run. Low values with high volume cause lag.'' AS NVARCHAR(1000)) AS [Description]
            FROM msdb.dbo.cdc_jobs AS j
            ORDER BY j.database_name, j.job_type;');
    END
    ELSE
    BEGIN
        PRINT 'msdb.dbo.cdc_jobs not found. Run on SQL Server 2016+ with CDC enabled.';
    END;

    PRINT '--- Recent CDC Errors ---';
    IF @MajorVersion >= 16
        EXEC(N'SELECT TOP (20)
            e.session_id,
            e.phase_number AS [Phase],
            e.entry_time,
            e.error_number AS [Error_Code],
            e.error_message
        FROM sys.dm_cdc_errors AS e
        ORDER BY e.entry_time DESC;');
    ELSE
        EXEC(N'SELECT TOP (20)
            e.database_id,
            DB_NAME(e.database_id) AS [Database_Name],
            e.session_id,
            e.phase,
            e.entry_time,
            e.error_code,
            e.error_message
        FROM sys.dm_cdc_errors AS e
        ORDER BY e.entry_time DESC;');
END
ELSE
    PRINT 'No CDC-enabled databases on this instance.';

-- 2. Query Store Granular Metrics
PRINT '--- Query Store Policy Audit ---';
BEGIN
    DECLARE @qs_db SYSNAME, @qs_cursor CURSOR;
    SET @qs_cursor = CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0;
    OPEN @qs_cursor;
    FETCH NEXT FROM @qs_cursor INTO @qs_db;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @qs_sql NVARCHAR(MAX) = N'USE ' + QUOTENAME(@qs_db) + N';
        SELECT
            N''' + REPLACE(@qs_db, N'''', N'''''') + N''' AS [DB],
            qs.actual_state_desc,
            qs.flush_interval_seconds AS [Flush_s],
            qs.interval_length_minutes AS [Aggregation_Interval_m],
            qs.max_plans_per_query,
            CAST(N''Query Store configuration determines performance data resolution. flush_interval_seconds controls disk persistence frequency.'' AS NVARCHAR(1000)) AS [Description]
        FROM sys.database_query_store_options AS qs;';
        BEGIN TRY EXEC sp_executesql @qs_sql; END TRY BEGIN CATCH END CATCH;
        FETCH NEXT FROM @qs_cursor INTO @qs_db;
    END;
    CLOSE @qs_cursor;
    DEALLOCATE @qs_cursor;
END;

-- 3. Replication Latency & Buffer Analysis
PRINT '--- Replication Agent Detailed Metrics ---';
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'distribution')
BEGIN
    SELECT
        h.agent_id,
        da.name AS [Agent_Name],
        h.delivery_rate AS [Commands_Per_Sec],
        h.delivery_latency AS [Total_Latency_ms],
        h.timestamp AS [Sample_Time],
        CAST(N'If delivery_rate is high but latency is also high, the subscriber is likely the bottleneck.' AS NVARCHAR(1000)) AS [Description]
    FROM distribution.dbo.MSdistribution_history AS h
    INNER JOIN distribution.dbo.MSdistribution_agents AS da ON da.id = h.agent_id
    WHERE h.timestamp = (
        SELECT MAX(h2.timestamp)
        FROM distribution.dbo.MSdistribution_history AS h2
        WHERE h2.agent_id = h.agent_id
    )
    ORDER BY h.delivery_latency DESC;
END
ELSE
    PRINT 'Distribution database not found. Replication may not be configured.';

-- 4. SQL Agent Job Owner Audit
PRINT '--- Agent Job Owner Analysis ---';
SELECT
    j.name AS [Job],
    l.name AS [Owner],
    j.enabled,
    CAST(N'Jobs should be owned by sa or a dedicated service account. Disabled owner logins cause job start failures.' AS NVARCHAR(1000)) AS [Description]
FROM msdb.dbo.sysjobs AS j
INNER JOIN sys.server_principals AS l ON j.owner_sid = l.sid
WHERE l.name <> N'sa'
ORDER BY j.name;
