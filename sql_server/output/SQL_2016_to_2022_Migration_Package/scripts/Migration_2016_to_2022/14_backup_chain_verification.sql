/*
    Migration 2016 -> 2022 | Backup chain verification
    Risk: Read-only

    Note: device_type / physical_device_name live on msdb.dbo.backupmediafamily,
    not msdb.dbo.backupset.
*/
SET NOCOUNT ON;

-- Most recent backup per database (any type) + device path
SELECT
    d.name AS [DatabaseName],
    d.recovery_model_desc,
    b.type AS [BackupType],
    CASE b.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        ELSE b.type
    END AS [BackupTypeDesc],
    b.backup_start_date,
    b.backup_finish_date,
    b.expiration_date,
    b.compressed_backup_size / 1024.0 / 1024 AS [CompressedSizeMB],
    b.backup_size / 1024.0 / 1024 AS [BackupSizeMB],
    b.user_name,
    mf.device_type,
    mf.physical_device_name
FROM sys.databases AS d
OUTER APPLY (
    SELECT TOP (1)
        bs.type,
        bs.backup_start_date,
        bs.backup_finish_date,
        bs.expiration_date,
        bs.compressed_backup_size,
        bs.backup_size,
        bs.user_name,
        bs.media_set_id
    FROM msdb.dbo.backupset AS bs
    WHERE bs.database_name = d.name
    ORDER BY bs.backup_finish_date DESC
) AS b
OUTER APPLY (
    SELECT TOP (1)
        bmf.device_type,
        bmf.physical_device_name
    FROM msdb.dbo.backupmediafamily AS bmf
    WHERE bmf.media_set_id = b.media_set_id
) AS mf
WHERE d.database_id > 4
  AND d.state = 0
ORDER BY d.name;

-- Last full / diff / log backup timestamps per database
SELECT
    d.name AS [DatabaseName],
    MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END) AS [LastFullBackup],
    MAX(CASE WHEN bs.type = 'I' THEN bs.backup_finish_date END) AS [LastDiffBackup],
    MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END) AS [LastLogBackup]
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS bs
    ON d.name = bs.database_name
WHERE d.database_id > 4
  AND d.state = 0
GROUP BY d.name
ORDER BY d.name;
