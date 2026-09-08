/* SQL_Server_Assessment */
SELECT ag.name AS AvailabilityGroup, ar.replica_server_name AS Replica,
       ars.role_desc AS Role, ars.operational_state_desc AS OperationalState,
       ars.connected_state_desc AS ConnectedState, ars.synchronization_health_desc AS SynchronizationHealth,
       adc.database_name AS DatabaseName, drs.synchronization_state_desc AS SynchronizationState,
       drs.synchronization_health_desc AS DatabaseHealth, drs.is_suspended AS IsSuspended,
       drs.log_send_queue_size AS LogSendQueueKB, drs.redo_queue_size AS RedoQueueKB
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id=ar.group_id
LEFT JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id=ars.replica_id
LEFT JOIN sys.availability_databases_cluster adc ON ag.group_id=adc.group_id
LEFT JOIN sys.dm_hadr_database_replica_states drs ON adc.group_database_id=drs.group_database_id AND ar.replica_id=drs.replica_id
ORDER BY ag.name,ar.replica_server_name,adc.database_name;
