/*
================================================================================
01_Capture_Environment_Baseline.sql
Purpose : Capture instance + database configuration after 2016→2022 restore.
Use     : Run on OLD (if still available) and NEW servers; save outputs for diff.
Replace : @DBName
================================================================================
*/
SET NOCOUNT ON;
DECLARE @DBName sysname = N'YourDB'; -- <<< change

PRINT '=== SERVER / INSTANCE ===';
SELECT
    SERVERPROPERTY('ProductVersion')   AS ProductVersion,
    SERVERPROPERTY('ProductLevel')     AS ProductLevel,
    SERVERPROPERTY('Edition')          AS Edition,
    SERVERPROPERTY('EngineEdition')    AS EngineEdition,
    SERVERPROPERTY('MachineName')      AS MachineName,
    SERVERPROPERTY('ServerName')       AS ServerName,
    cpu_count,
    hyperthread_ratio,
    physical_memory_kb / 1024          AS physical_memory_mb,
    committed_kb / 1024                AS committed_mb,
    committed_target_kb / 1024         AS committed_target_mb
FROM sys.dm_os_sys_info;

PRINT '=== IMPORTANT sp_configure ===';
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
SELECT name, value, value_in_use, description
FROM sys.configurations
WHERE name IN (
    N'max degree of parallelism',
    N'cost threshold for parallelism',
    N'max server memory (MB)',
    N'min server memory (MB)',
    N'optimize for ad hoc workloads',
    N'backup compression default',
    N'remote admin connections',
    N'XP_cmdshell'  -- should usually be 0
)
ORDER BY name;

PRINT '=== DATABASE PROPERTIES ===';
SELECT
    d.name,
    d.compatibility_level,
    d.collation_name,
    d.is_auto_create_stats_on,
    d.is_auto_update_stats_on,
    d.is_auto_update_stats_async_on,
    d.is_auto_shrink_on,          -- should be 0
    d.page_verify_option_desc,   -- CHECKSUM
    d.is_query_store_on,
    d.is_parameterization_forced,
    d.snapshot_isolation_state_desc,
    d.is_read_committed_snapshot_on,
    d.target_recovery_time_in_seconds,
    d.delayed_durability_desc
FROM sys.databases d
WHERE d.name = @DBName;

PRINT '=== DATABASE SCOPED CONFIGURATIONS ===';
DECLARE @sql nvarchar(max) = N'
USE ' + QUOTENAME(@DBName) + N';
SELECT name, value, value_for_secondary, is_value_default
FROM sys.database_scoped_configurations
ORDER BY name;';
EXEC (@sql);

PRINT '=== FILES / SIZE / GROWTH ===';
SELECT
    DB_NAME(database_id) AS db_name,
    type_desc,
    name AS logical_name,
    physical_name,
    CAST(size AS bigint) * 8 / 1024 AS size_mb,
    CASE WHEN max_size = -1 THEN CAST(-1 AS bigint) ELSE CAST(max_size AS bigint) * 8 / 1024 END AS max_size_mb,
    growth,
    is_percent_growth
FROM sys.master_files
WHERE database_id = DB_ID(@DBName)
ORDER BY type_desc, file_id;

PRINT '=== TEMPDB FILES ===';
SELECT name, type_desc, CAST(size AS bigint) * 8 / 1024 AS size_mb, growth, is_percent_growth, physical_name
FROM tempdb.sys.database_files;

PRINT '=== GLOBAL TRACE FLAGS (STATUS) ===';
DBCC TRACESTATUS(-1);

PRINT '=== QUERY STORE OPTIONS (if on) ===';
SET @sql = N'
USE ' + QUOTENAME(@DBName) + N';
SELECT actual_state_desc, readonly_reason, current_storage_size_mb, max_storage_size_mb,
       interval_length_minutes, query_capture_mode_desc, size_based_cleanup_mode_desc,
       stale_query_threshold_days, max_plans_per_query
FROM sys.database_query_store_options;';
EXEC (@sql);

PRINT 'Baseline capture complete.';
