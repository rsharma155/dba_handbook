/* SQL_Server_Assessment */
;WITH sizes AS (
    SELECT database_id,
           SUM(CASE WHEN type = 0 THEN size ELSE 0 END) * 8.0 / 1024 AS DataSizeMB,
           SUM(CASE WHEN type = 1 THEN size ELSE 0 END) * 8.0 / 1024 AS LogSizeMB
    FROM sys.master_files GROUP BY database_id
)
SELECT d.name AS DatabaseName, d.state_desc AS Status, d.user_access_desc AS UserAccess,
       d.recovery_model_desc AS RecoveryModel, d.compatibility_level AS CompatibilityLevel,
       SUSER_SNAME(d.owner_sid) AS Owner, d.page_verify_option_desc AS PageVerify,
       d.is_auto_close_on AS AutoClose, d.is_auto_shrink_on AS AutoShrink,
       d.is_read_only AS IsReadOnly, d.is_query_store_on AS QueryStoreEnabled,
       d.source_database_id AS SourceDatabaseId, HAS_DBACCESS(d.name) AS HasDbAccess,
       CAST(ISNULL(s.DataSizeMB,0) AS decimal(18,1)) AS DataSizeMB,
       CAST(ISNULL(s.LogSizeMB,0) AS decimal(18,1)) AS LogSizeMB,
       CAST(ISNULL(s.DataSizeMB,0)+ISNULL(s.LogSizeMB,0) AS decimal(18,1)) AS TotalSizeMB,
       d.create_date AS CreateDate
FROM sys.databases d LEFT JOIN sizes s ON d.database_id=s.database_id
ORDER BY d.database_id;
