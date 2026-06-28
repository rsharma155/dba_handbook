/*
================================================================================
Purpose:        Verifies Transparent Data Encryption (TDE) status, SSL/TLS 
                certificate configuration, and SQL Server Audit activation.
Provides:       TDE state, encryption percentage, connection encryption status, 
                and server-level audit configurations.
Importance:     Critical for ensuring data-at-rest and data-in-transit security 
                compliance (SOC2, HIPAA, PCI-DSS).
Interpretation: All production databases should have TDE enabled. All active 
                 connections should use encryption. Audits should be enabled.
Action: For databases with Is_TDE_Enabled = 0 and sensitive data, enable TDE:
    CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256 ENCRYPTION BY SERVER CERTIFICATE [CertName];
    ALTER DATABASE [DBName] SET ENCRYPTION ON;
    For connections without encryption, configure the server to force encryption via SQL Server Configuration Manager. For missing SQL Server Audits, create server and database audit specifications per compliance requirements.
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @MajorVersion INT = CAST(PARSENAME(CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)), 4) AS INT);

-- 1. Transparent Data Encryption (TDE) Status per Database
SELECT 
    d.name AS [Database_Name],
    d.is_encrypted AS [Is_TDE_Enabled],
    CASE 
        WHEN dek.encryptor_type IS NOT NULL THEN dek.encryptor_type
        ELSE N'N/A'
    END AS [Encryptor_Type],
    CASE 
        WHEN dek.encryption_state = 3 THEN N'ENCRYPTED'
        WHEN dek.encryption_state = 2 THEN N'ENCRYPTION_IN_PROGRESS'
        WHEN dek.encryption_state = 1 THEN N'UNENCRYPTED'
        WHEN dek.encryption_state = 0 THEN N'NO_DATABASE_KEY'
        ELSE N'UNKNOWN'
    END AS [Encryption_State],
    dek.percent_complete AS [Encryption_Pct]
FROM sys.databases AS d
LEFT JOIN sys.dm_database_encryption_keys AS dek ON d.database_id = dek.database_id
WHERE d.database_id > 4
  AND d.state = 0
  AND (
        @DatabaseList IS NULL
        OR d.name IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@DatabaseList, N',') WHERE LTRIM(RTRIM(value)) <> N'')
      )
ORDER BY d.name;

-- 2. SSL/TLS Connection Encryption (all active sessions)
PRINT N'--- Connection Encryption Summary ---';
SELECT
    encrypt_option AS [Encrypt_Option],
    COUNT(*) AS [Session_Count],
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) AS [Pct_Of_Sessions]
FROM sys.dm_exec_connections
WHERE session_id > 50
GROUP BY encrypt_option
ORDER BY [Session_Count] DESC;

SELECT TOP (20)
    c.session_id,
    s.login_name,
    c.encrypt_option,
    c.auth_scheme,
    c.net_transport,
    c.client_net_address
FROM sys.dm_exec_connections AS c
INNER JOIN sys.dm_exec_sessions AS s ON c.session_id = s.session_id
WHERE c.session_id > 50
ORDER BY c.session_id;

-- 3. SQL Server Audit Configuration
IF @MajorVersion >= 16
    EXEC(N'SELECT 
        aud.name AS [Audit_Name],
        aud.is_state_enabled AS [Is_Enabled],
        aud.type_desc AS [Audit_Type],
        aud.queue_delay AS [Queue_Delay_ms],
        aud.on_failure_desc AS [On_Failure_Action],
        aud.predicate AS [Audit_Predicate],
        CAST(N''SQL Server Audit configuration review. Threshold: Audits should be enabled (Is_Enabled = 1) for compliance with regulatory standards (SOC2, HIPAA, ISO27001). Recommendation: Create server and database audit specifications to log failed logins, permission changes, and DDL operations.'' AS VARCHAR(1000)) AS [Metric_Context]
    FROM sys.server_audits AS aud WITH (NOLOCK)
    ORDER BY aud.name;');
ELSE
    EXEC(N'SELECT 
        aud.name AS [Audit_Name],
        aud.is_state_enabled AS [Is_Enabled],
        aud.type_desc AS [Audit_Type],
        aud.destination_type_desc AS [Destination_Type],
        aud.path AS [Audit_File_Path],
        aud.max_files AS [Max_Files],
        aud.max_rollover_files AS [Max_Rollover],
        aud.retention_days AS [Retention_Days],
        aud.queue_delay AS [Queue_Delay_ms],
        aud.on_failure_desc AS [On_Failure_Action],
        aud.predicate AS [Audit_Predicate],
        CAST(N''SQL Server Audit configuration review. Threshold: Audits should be enabled (Is_Enabled = 1) for compliance with regulatory standards (SOC2, HIPAA, ISO27001). Recommendation: Create server and database audit specifications to log failed logins, permission changes, and DDL operations.'' AS VARCHAR(1000)) AS [Metric_Context]
    FROM sys.server_audits AS aud WITH (NOLOCK)
    ORDER BY aud.name;');

-- 4. Server-Level Audit Specifications
IF @MajorVersion >= 16
    EXEC(N'SELECT 
        aspec.name AS [Specification_Name],
        aspec.is_state_enabled AS [Is_Enabled],
        a.name AS [Parent_Audit],
        STUFF((SELECT N'', '' + adet.audit_action_name
              FROM sys.server_audit_specification_details AS adet
              WHERE adet.server_specification_id = aspec.server_specification_id
              ORDER BY adet.audit_action_id
              FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''') AS [Audit_Actions],
        CAST(N''Server audit specifications determine which actions are logged. Recommendation: Ensure audit specifications capture login failures (FAILED_LOGIN_GROUP), permission changes (SERVER_ROLE_MEMBER_CHANGE_GROUP), and database object changes.''
             AS VARCHAR(1000)) AS [Metric_Context]
    FROM sys.server_audit_specifications AS aspec WITH (NOLOCK)
    INNER JOIN sys.server_audits AS a WITH (NOLOCK)
        ON aspec.audit_guid = a.audit_guid
    ORDER BY aspec.name;');
ELSE
    EXEC(N'SELECT 
        aspec.name AS [Specification_Name],
        aspec.is_state_enabled AS [Is_Enabled],
        aspec.type_desc AS [Spec_Type],
        a.name AS [Parent_Audit],
        CASE 
            WHEN aspec.type = ''SL'' THEN aspec.name
            ELSE STUFF((SELECT N'', '' + adet.audit_action_name
                  FROM sys.server_audit_specification_details AS adet
                  WHERE adet.server_specification_id = aspec.server_specification_id
                  ORDER BY adet.audit_action_id
                  FOR XML PATH(N''''), TYPE).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''')
        END AS [Audit_Actions],
        CAST(N''Server audit specifications determine which actions are logged. Recommendation: Ensure audit specifications capture login failures (FAILED_LOGIN_GROUP), permission changes (SERVER_ROLE_MEMBER_CHANGE_GROUP), and database object changes.''
             AS VARCHAR(1000)) AS [Metric_Context]
    FROM sys.server_audit_specifications AS aspec WITH (NOLOCK)
    INNER JOIN sys.server_audits AS a WITH (NOLOCK)
        ON aspec.audit_guid = a.audit_guid
    ORDER BY aspec.name;');
