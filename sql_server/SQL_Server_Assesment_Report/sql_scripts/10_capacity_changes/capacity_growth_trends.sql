/* SQL_Server_Assessment */
;WITH fulls AS (
 SELECT database_name, backup_start_date, backup_size/1048576.0 AS BackupSizeMB,
        FIRST_VALUE(backup_size/1048576.0) OVER(PARTITION BY database_name ORDER BY backup_start_date) AS FirstSizeMB,
        FIRST_VALUE(backup_size/1048576.0) OVER(PARTITION BY database_name ORDER BY backup_start_date DESC) AS LastSizeMB,
        MIN(backup_start_date) OVER(PARTITION BY database_name) AS FirstDate,
        MAX(backup_start_date) OVER(PARTITION BY database_name) AS LastDate
 FROM msdb.dbo.backupset
 WHERE type='D' AND is_copy_only=0 AND backup_start_date>=DATEADD(DAY,-{{DaysToAnalyze}},GETDATE())
), one_row AS (
 SELECT *,ROW_NUMBER() OVER(PARTITION BY database_name ORDER BY backup_start_date DESC) rn FROM fulls
)
SELECT database_name AS DatabaseName, CAST(FirstSizeMB AS decimal(18,1)) AS FirstBackupSizeMB,
       CAST(LastSizeMB AS decimal(18,1)) AS CurrentBackupSizeMB,
       DATEDIFF(DAY,FirstDate,LastDate) AS DaysObserved,
       CAST((LastSizeMB-FirstSizeMB)/NULLIF(DATEDIFF(DAY,FirstDate,LastDate),0) AS decimal(18,1)) AS GrowthMBPerDay,
       CAST(LastSizeMB+90*((LastSizeMB-FirstSizeMB)/NULLIF(DATEDIFF(DAY,FirstDate,LastDate),0)) AS decimal(18,1)) AS Projected90DayMB
FROM one_row WHERE rn=1 ORDER BY GrowthMBPerDay DESC;
