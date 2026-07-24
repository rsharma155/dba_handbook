/* SQL_Server_Assessment */
;WITH b AS (
    SELECT database_name,
      MAX(CASE WHEN type='D' AND is_copy_only=0 THEN backup_finish_date END) AS LastFullBackup,
      MAX(CASE WHEN type='I' AND is_copy_only=0 THEN backup_finish_date END) AS LastDiffBackup,
      MAX(CASE WHEN type='L' THEN backup_finish_date END) AS LastLogBackup
    FROM msdb.dbo.backupset GROUP BY database_name
)
SELECT d.name AS DatabaseName, d.recovery_model_desc AS RecoveryModel,
       b.LastFullBackup, DATEDIFF(HOUR,b.LastFullBackup,GETDATE()) AS FullAgeHours,
       b.LastDiffBackup, DATEDIFF(HOUR,b.LastDiffBackup,GETDATE()) AS DiffAgeHours,
       b.LastLogBackup, DATEDIFF(MINUTE,b.LastLogBackup,GETDATE()) AS LogAgeMinutes
FROM sys.databases d LEFT JOIN b ON b.database_name=d.name
WHERE d.database_id > 4 AND d.source_database_id IS NULL
ORDER BY d.name;
