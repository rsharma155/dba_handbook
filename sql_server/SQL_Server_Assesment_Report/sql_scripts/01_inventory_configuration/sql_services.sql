/* SQL_Server_Assessment */
SELECT servicename AS ServiceName, startup_type_desc AS StartupType,
       status_desc AS Status, service_account AS ServiceAccount,
       last_startup_time AS LastStartupTime, is_clustered AS IsClustered,
       cluster_nodename AS ClusterNodeName,
       instant_file_initialization_enabled AS InstantFileInitialization
FROM sys.dm_server_services
ORDER BY servicename;
