/*
================================================================================
01_Enable_QueryStore.sql
Purpose : Enable & size Query Store — mandatory before flipping to compat 160.
================================================================================
*/
USE [YourDB]; -- <<< change
GO

ALTER DATABASE CURRENT SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 2048,          -- increase for busy systems (4-10 GB+)
    QUERY_CAPTURE_MODE = AUTO,           -- ALL if you need exhaustive capture briefly
    SIZE_BASED_CLEANUP_MODE = AUTO,
    MAX_PLANS_PER_QUERY = 200
);

-- WAIT_STATS_CAPTURE_MODE: separate ALTER (SQL 2017+; not valid in all builds inside initial ON block)
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS int) >= 14
BEGIN
    ALTER DATABASE CURRENT SET QUERY_STORE (WAIT_STATS_CAPTURE_MODE = ON);
END
ELSE
    PRINT 'WAIT_STATS_CAPTURE_MODE requires SQL Server 2017+. Skipped.';

-- Optional: capture waits deeper during migration week
-- ALTER DATABASE CURRENT SET QUERY_STORE = ON (QUERY_CAPTURE_MODE = ALL);

SELECT actual_state_desc, readonly_reason, current_storage_size_mb, max_storage_size_mb,
       interval_length_minutes, query_capture_mode_desc, stale_query_threshold_days,
       wait_stats_capture_mode_desc
FROM sys.database_query_store_options;

/*
WORKFLOW
1) Enable QS at compat 130; run production workload 3–7 days.
2) In UAT, set compat 160; run same workload.
3) Use 02_Find_Regressed_Queries.sql
4) Force good plans / fix queries
5) Only then change production to 160
*/
