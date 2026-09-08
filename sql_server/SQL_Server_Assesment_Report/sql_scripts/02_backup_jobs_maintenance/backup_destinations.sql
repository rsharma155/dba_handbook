/* SQL_Server_Assessment */
CREATE TABLE #drives (Drive char(1), FreeMB int);
INSERT #drives EXEC master.dbo.xp_fixeddrives;
;WITH destinations AS (
 SELECT DISTINCT
   CASE WHEN bmf.physical_device_name LIKE '[A-Z]:\%' THEN LEFT(bmf.physical_device_name,1) END AS Drive,
   LEFT(bmf.physical_device_name,260) AS BackupDestination
 FROM msdb.dbo.backupmediafamily bmf
 JOIN msdb.dbo.backupset bs ON bmf.media_set_id=bs.media_set_id
 WHERE bs.backup_finish_date >= DATEADD(DAY,-30,GETDATE())
)
SELECT d.BackupDestination, d.Drive, x.FreeMB,
       CAST(x.FreeMB/1024.0 AS decimal(18,2)) AS FreeGB
FROM destinations d LEFT JOIN #drives x ON d.Drive=x.Drive
ORDER BY d.BackupDestination;
