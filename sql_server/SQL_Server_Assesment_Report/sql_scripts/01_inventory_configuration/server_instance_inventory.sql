/* SQL_Server_Assessment */
SELECT
    CAST(SERVERPROPERTY('ServerName') AS nvarchar(128)) AS ServerName,
    CAST(SERVERPROPERTY('MachineName') AS nvarchar(128)) AS MachineName,
    CAST(SERVERPROPERTY('InstanceName') AS nvarchar(128)) AS InstanceName,
    CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(30)) AS ProductVersion,
    CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(30)) AS ProductLevel,
    CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(30)) AS ProductUpdateLevel,
    CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS Edition,
    CAST(SERVERPROPERTY('EngineEdition') AS int) AS EngineEdition,
    CAST(SERVERPROPERTY('IsClustered') AS int) AS IsClustered,
    CAST(SERVERPROPERTY('IsHadrEnabled') AS int) AS IsHadrEnabled,
    sqlserver_start_time AS LastRestart,
    DATEDIFF(MINUTE, sqlserver_start_time, GETDATE()) AS UptimeMinutes,
    cpu_count AS LogicalCpuCount,
    physical_memory_kb / 1024 AS PhysicalMemoryMB,
    sql_memory_model_desc AS SqlMemoryModel
FROM sys.dm_os_sys_info;
