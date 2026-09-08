/*
    Migration 2016 -> 2022 | Always On AG health check
    Risk: Read-only
*/
SET NOCOUNT ON;

IF SERVERPROPERTY('IsHadrEnabled') <> 1
BEGIN
    SELECT N'Always On is not enabled on this instance.' AS [Message];
    RETURN;
END

SELECT
    ag.name AS [AvailabilityGroup],
    ag.failure_condition_level,
    ag.health_check_timeout,
    ag.automated_backup_preference_desc
FROM sys.availability_groups AS ag;

SELECT
    ar.replica_server_name,
    ar.endpoint_url,
    ar.availability_mode_desc,
    ar.failover_mode_desc,
    ar.secondary_role_allow_connections_desc,
    ars.role_desc,
    ars.operational_state_desc,
    ars.connected_state_desc,
    ars.recovery_health_desc,
    ars.synchronization_health_desc
FROM sys.availability_replicas AS ar
JOIN sys.dm_hadr_availability_replica_states AS ars ON ar.replica_id = ars.replica_id
ORDER BY ar.replica_server_name;

SELECT
    DB_NAME(drs.database_id) AS [database_name],
    ar.replica_server_name,
    drs.synchronization_state_desc,
    drs.is_suspended,
    drs.suspend_reason_desc,
    drs.log_send_queue_size,
    drs.redo_queue_size,
    drs.last_commit_time
FROM sys.dm_hadr_database_replica_states AS drs
JOIN sys.availability_replicas AS ar ON drs.replica_id = ar.replica_id
ORDER BY DB_NAME(drs.database_id), ar.replica_server_name;
