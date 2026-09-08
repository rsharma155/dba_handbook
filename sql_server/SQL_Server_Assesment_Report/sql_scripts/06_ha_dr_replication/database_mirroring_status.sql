/* SQL_Server_Assessment */
SELECT DB_NAME(database_id) AS DatabaseName, mirroring_role_desc AS Role,
       mirroring_state_desc AS State, mirroring_safety_level_desc AS SafetyLevel,
       mirroring_partner_name AS Partner, mirroring_witness_name AS Witness
FROM sys.database_mirroring WHERE mirroring_guid IS NOT NULL;
