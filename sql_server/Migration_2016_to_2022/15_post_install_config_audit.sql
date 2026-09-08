/*
    Migration 2016 -> 2022 | Post-install configuration audit (TARGET 2022)
    Compare results with source 2016 baseline. See also Prod_Migration scripts.
    Risk: Read-only
*/
SET NOCOUNT ON;

SELECT N'Instance' AS [Section], @@VERSION AS [Detail]
UNION ALL
SELECT N'SQL Start Time', CONVERT(NVARCHAR(30), sqlserver_start_time, 120) FROM sys.dm_os_sys_info
UNION ALL
SELECT N'Max Server Memory (MB)', CAST(value_in_use AS NVARCHAR(20)) FROM sys.configurations WHERE name = N'max server memory (MB)'
UNION ALL
SELECT N'MAXDOP', CAST(value_in_use AS NVARCHAR(20)) FROM sys.configurations WHERE name = N'max degree of parallelism'
UNION ALL
SELECT N'CTFP', CAST(value_in_use AS NVARCHAR(20)) FROM sys.configurations WHERE name = N'cost threshold for parallelism'
UNION ALL
SELECT N'Backup Compression Default', CAST(value_in_use AS NVARCHAR(20)) FROM sys.configurations WHERE name = N'backup compression default';

SELECT
    name AS [DatabaseName],
    state_desc,
    compatibility_level,
    recovery_model_desc,
    page_verify_option_desc
FROM sys.databases
WHERE database_id > 4
ORDER BY name;

SELECT
    COUNT(*) AS [TempDBFileCount],
    SUM(size) * 8.0 / 1024 AS [TempDBTotalSizeMB],
    SUM(CASE WHEN growth = 0 THEN 1 ELSE 0 END) AS [FilesWithZeroGrowth]
FROM tempdb.sys.database_files;

SELECT
    servicename,
    status_desc,
    startup_type_desc,
    service_account,
    last_startup_time
FROM sys.dm_server_services
ORDER BY servicename;
