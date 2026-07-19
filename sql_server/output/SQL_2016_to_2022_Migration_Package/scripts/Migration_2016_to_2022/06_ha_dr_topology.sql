/*
    Migration 2016 -> 2022 | HA/DR topology inventory
    Run on: SOURCE (2016) and TARGET (2022)
    Risk: Read-only

    Every result set leads with DatabaseName for easy inventory/export.
    Column notes (2016-safe):
    - sys.availability_replicas has no seamless_update_status_desc on 2016
    - sys.dm_hadr_database_replica_states exposes database_id (use DB_NAME)
    - msdb.dbo.log_shipping_primary_databases uses backup_directory
    - primary_server / primary_database live on msdb.dbo.log_shipping_secondary
*/
SET NOCOUNT ON;

-- Always On Availability Groups
IF SERVERPROPERTY('IsHadrEnabled') = 1
BEGIN
    SELECT
        DB_NAME(drs.database_id) AS [DatabaseName],
        ag.name AS [AvailabilityGroup],
        ar.replica_server_name,
        ar.availability_mode_desc,
        ar.failover_mode_desc,
        ar.endpoint_url,
        ar.secondary_role_allow_connections_desc,
        ars.role_desc,
        ars.operational_state_desc,
        ars.connected_state_desc,
        ars.synchronization_health_desc,
        drs.synchronization_state_desc,
        drs.is_suspended,
        drs.suspend_reason_desc
    FROM sys.availability_groups AS ag
    JOIN sys.availability_replicas AS ar
        ON ag.group_id = ar.group_id
    JOIN sys.dm_hadr_availability_replica_states AS ars
        ON ar.replica_id = ars.replica_id
    LEFT JOIN sys.dm_hadr_database_replica_states AS drs
        ON ar.replica_id = drs.replica_id
    ORDER BY [DatabaseName], ag.name, ar.replica_server_name;

    -- AG database membership (cluster view) — one row per AG database
    SELECT
        adc.database_name AS [DatabaseName],
        ag.name AS [AvailabilityGroup],
        adc.group_database_id
    FROM sys.availability_databases_cluster AS adc
    JOIN sys.availability_groups AS ag
        ON adc.group_id = ag.group_id
    ORDER BY adc.database_name, ag.name;
END
ELSE
    SELECT
        CAST(NULL AS SYSNAME) AS [DatabaseName],
        N'Always On not enabled on this instance' AS [Note];

-- Database mirroring (legacy — plan migration to AG)
IF EXISTS (SELECT 1 FROM sys.database_mirroring WHERE mirroring_guid IS NOT NULL)
    SELECT
        DB_NAME(database_id) AS [DatabaseName],
        mirroring_state_desc,
        mirroring_role_desc,
        mirroring_partner_name,
        mirroring_safety_level_desc
    FROM sys.database_mirroring
    WHERE mirroring_guid IS NOT NULL
    ORDER BY [DatabaseName];
ELSE
    SELECT
        CAST(NULL AS SYSNAME) AS [DatabaseName],
        N'No database mirroring partners configured' AS [Note];

-- Log shipping (primary)
IF OBJECT_ID('msdb.dbo.log_shipping_primary_databases') IS NOT NULL
    AND EXISTS (SELECT 1 FROM msdb.dbo.log_shipping_primary_databases)
    SELECT
        primary_database AS [DatabaseName],
        backup_directory,
        backup_share,
        backup_job_id,
        last_backup_file,
        last_backup_date
    FROM msdb.dbo.log_shipping_primary_databases
    ORDER BY [DatabaseName];
ELSE
    SELECT
        CAST(NULL AS SYSNAME) AS [DatabaseName],
        N'No log shipping primary databases configured' AS [Note];

-- Log shipping (secondary)
IF OBJECT_ID('msdb.dbo.log_shipping_secondary_databases') IS NOT NULL
    AND OBJECT_ID('msdb.dbo.log_shipping_secondary') IS NOT NULL
    AND EXISTS (SELECT 1 FROM msdb.dbo.log_shipping_secondary_databases)
    SELECT
        lssd.secondary_database AS [DatabaseName],
        lss.primary_server,
        lss.primary_database AS [PrimaryDatabaseName],
        lss.backup_source_directory,
        lss.backup_destination_directory,
        lssd.last_restored_file,
        lssd.last_restored_date,
        lssd.restore_delay,
        lssd.restore_mode
    FROM msdb.dbo.log_shipping_secondary_databases AS lssd
    JOIN msdb.dbo.log_shipping_secondary AS lss
        ON lssd.secondary_id = lss.secondary_id
    ORDER BY [DatabaseName];
ELSE IF OBJECT_ID('msdb.dbo.log_shipping_secondary_databases') IS NOT NULL
    AND EXISTS (SELECT 1 FROM msdb.dbo.log_shipping_secondary_databases)
    SELECT
        secondary_database AS [DatabaseName],
        last_restored_file,
        last_restored_date
    FROM msdb.dbo.log_shipping_secondary_databases
    ORDER BY [DatabaseName];
ELSE
    SELECT
        CAST(NULL AS SYSNAME) AS [DatabaseName],
        N'No log shipping secondary databases configured' AS [Note];

-- Replication publisher / subscriber / distributor
IF EXISTS (
    SELECT 1
    FROM sys.databases
    WHERE is_published = 1
       OR is_subscribed = 1
       OR is_merge_published = 1
       OR is_distributor = 1
)
    SELECT
        name AS [DatabaseName],
        is_published,
        is_subscribed,
        is_merge_published,
        is_distributor
    FROM sys.databases
    WHERE is_published = 1
       OR is_subscribed = 1
       OR is_merge_published = 1
       OR is_distributor = 1
    ORDER BY [DatabaseName];
ELSE
    SELECT
        CAST(NULL AS SYSNAME) AS [DatabaseName],
        N'No replication publisher/subscriber/distributor databases detected' AS [Note];
