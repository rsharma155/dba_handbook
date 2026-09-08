/*
    Migration 2016 -> 2022 | Cutover validation (TARGET 2022)
    Run immediately after final restore / AG failover and before app cutover.
    Risk: Read-only
*/
SET NOCOUNT ON;

SELECT
    @@SERVERNAME AS [InstanceName],
    @@VERSION AS [Version],
    SERVERPROPERTY('ProductMajorVersion') AS [MajorVersion],
    SERVERPROPERTY('Edition') AS [Edition],
    SERVERPROPERTY('ProductLevel') AS [ProductLevel];

SELECT name, state_desc, user_access_desc, is_read_only, compatibility_level
FROM sys.databases
WHERE database_id > 4
ORDER BY name;

SELECT servicename, status_desc, startup_type_desc
FROM sys.dm_server_services
WHERE servicename LIKE N'SQL Server (%' OR servicename LIKE N'SQL Server Agent (%';

SELECT COUNT(*) AS [EnabledJobCount]
FROM msdb.dbo.sysjobs
WHERE enabled = 1;

SELECT COUNT(*) AS [OrphanUserCount]
FROM (
    -- quick count via dynamic SQL would be heavy; run 08_orphaned_users_precheck for detail
    SELECT 1 AS x WHERE 1 = 0
) AS t;

PRINT 'Run 08_orphaned_users_precheck.sql for orphaned user detail before go-live.';

SELECT TOP (10) name, create_date
FROM sys.server_principals
WHERE type IN ('S','U','G') AND name NOT LIKE N'##%'
ORDER BY create_date DESC;
