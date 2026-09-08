/*
    Migration 2016 -> 2022 | Database features (TDE, CDC, In-Memory, FileStream)
    Risk: Read-only
*/
SET NOCOUNT ON;

SELECT
    d.name AS [DatabaseName],
    d.is_encrypted,
    dek.encryption_state,
    dek.encryption_state_desc,
    dek.key_algorithm,
    dek.key_length,
    c.name AS [EncryptorName],
    c.pvt_key_last_backup_date AS [CertKeyLastBackupDate]
FROM sys.databases AS d
LEFT JOIN sys.dm_database_encryption_keys AS dek ON d.database_id = dek.database_id
LEFT JOIN sys.certificates AS c ON dek.encryptor_thumbprint = c.thumbprint
WHERE d.database_id > 4
ORDER BY d.name;

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql = @sql + N'
USE ' + QUOTENAME(name) + N';
IF OBJECT_ID(''sys.change_tracking_databases'') IS NOT NULL
    SELECT DB_NAME() AS DatabaseName, N''ChangeTracking'' AS Feature, ct.is_auto_cleanup_on
    FROM sys.change_tracking_databases AS ct;
IF EXISTS (SELECT 1 FROM sys.tables WHERE is_tracked_by_cdc = 1)
    SELECT DB_NAME() AS DatabaseName, N''CDC'' AS Feature, COUNT(*) AS CdcTableCount
    FROM sys.tables WHERE is_tracked_by_cdc = 1;
IF EXISTS (SELECT 1 FROM sys.filegroups WHERE type = N''FX'' OR type_desc LIKE N''%FILESTREAM%'')
    SELECT DB_NAME() AS DatabaseName, N''FileStream'' AS Feature, COUNT(*) AS FilegroupCount
    FROM sys.filegroups WHERE type = N''FX'' OR type_desc LIKE N''%FILESTREAM%'';
IF EXISTS (SELECT 1 FROM sys.tables WHERE is_memory_optimized = 1)
    SELECT DB_NAME() AS DatabaseName, N''InMemoryOLTP'' AS Feature, COUNT(*) AS MemOptTableCount
    FROM sys.tables WHERE is_memory_optimized = 1;
'
FROM sys.databases
WHERE database_id > 4 AND state = 0;

EXEC sys.sp_executesql @sql;
