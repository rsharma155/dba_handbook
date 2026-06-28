/*
================================================================================
Purpose:        Reports the last full, differential, and transaction log backup 
                timestamps for all online user databases on the instance.
Provides:       Recovery model, database state, last backup dates, hours since 
                last backup, and a calculated backup health status.
Importance:     The most critical script for ensuring disaster recovery readiness, 
                meeting RPO/RTO SLAs, and data protection compliance.
Interpretation: Look for "CRITICAL" or "WARNING" in Backup_Status. Ensure log 
backups are frequent (e.g., < 1hr) for FULL recovery databases.
Action: For databases with Backup_Status = "CRITICAL" (no backup within SLA), take an immediate backup:
    BACKUP DATABASE [DBName] TO DISK = N'path';
    For FULL recovery databases with long gaps since last log backup (< 1 hour is recommended), increase log backup frequency via a SQL Agent job. Schedule daily verification using this script in a monitoring job.
Criticality:    Critical
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

WITH LastBackups AS (
    SELECT 
        database_name,
        MAX(CASE WHEN type = 'D' THEN backup_finish_date END) AS [Last_Full_Backup],
        MAX(CASE WHEN type = 'I' THEN backup_finish_date END) AS [Last_Differential_Backup],
        MAX(CASE WHEN type = 'L' THEN backup_finish_date END) AS [Last_Log_Backup],
        MAX(backup_finish_date) AS [Last_Any_Backup]
    FROM msdb.dbo.backupset WITH (NOLOCK)
    GROUP BY database_name
)
SELECT 
    d.name AS [Database_Name],
    d.recovery_model_desc AS [Recovery_Model],
    d.state_desc AS [Database_State],
    lb.Last_Full_Backup AS [Last_Full_Backup],
    lb.Last_Differential_Backup AS [Last_Differential_Backup],
    lb.Last_Log_Backup AS [Last_Log_Backup],
    DATEDIFF(HOUR, lb.Last_Any_Backup, GETDATE()) AS [Hours_Since_Last_Backup],
    CASE 
        WHEN d.state = 0 THEN -- ONLINE
            CASE 
                WHEN lb.Last_Any_Backup IS NULL THEN 'CRITICAL: No backup ever found'
                WHEN DATEDIFF(HOUR, lb.Last_Any_Backup, GETDATE()) > 48 THEN 'WARNING: Last backup > 48 hours ago'
                WHEN d.recovery_model_desc = 'FULL' AND lb.Last_Log_Backup IS NULL THEN 'WARNING: Full recovery mode with no log backup'
                WHEN d.recovery_model_desc = 'FULL' AND DATEDIFF(HOUR, lb.Last_Log_Backup, GETDATE()) > 24 THEN 'WARNING: Log backup > 24 hours old'
                ELSE 'OK'
            END
        ELSE 'N/A (database not online)'
    END AS [Backup_Status],
    CAST('Backup verification audit. ' +
         'Threshold: Full backups should be taken daily (or weekly for very large databases), log backups every 15-60 minutes for FULL recovery model. ' +
         'Recommendation: Schedule regular full, differential, and log backups to meet RPO requirements. ' +
         'Databases in FULL recovery model without recent log backups are at risk of massive log file growth and data loss.'
         AS VARCHAR(1000)) AS [Metric_Context]
FROM sys.databases AS d WITH (NOLOCK)
LEFT JOIN LastBackups AS lb ON d.name = lb.database_name
WHERE d.database_id > 4 -- Exclude system databases
ORDER BY [Hours_Since_Last_Backup] DESC;
