/*
================================================================================
SQL Server Backup Log Chain Integrity
================================================================================
Description:
    Detects breaks in the transaction log backup chain for FULL recovery model
    databases. A broken log chain prevents point-in-time recovery and can make
    restore operations fail after the break point.

Output:
    Sequential log backup listing with LSN ranges, highlighting gaps where
    first_lsn of the next backup does not match last_lsn of the previous backup.

Action:
    If a log chain break is detected (missing LSN continuity), immediately take
    a new full backup followed by regular log backups. Investigate why the break
    occurred — common causes: log backup failure, database switched to SIMPLE
    recovery, or manual log shrink (SHRINKFILE). Run weekly to catch breaks early.

Criticality: Critical
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

;WITH LogBackups AS (
    SELECT
        bs.database_name,
        bs.backup_start_date,
        bs.backup_finish_date,
        bs.first_lsn,
        bs.last_lsn,
        bs.database_backup_lsn,
        ROW_NUMBER() OVER (PARTITION BY bs.database_name ORDER BY bs.backup_start_date) AS rn
    FROM msdb.dbo.backupset AS bs
    WHERE bs.type = N'L'
),
ChainCheck AS (
    SELECT
        curr.database_name,
        prev.backup_finish_date AS [Previous_Log_Backup],
        curr.backup_finish_date AS [Current_Log_Backup],
        prev.last_lsn AS [Previous_Last_LSN],
        curr.first_lsn AS [Current_First_LSN],
        CASE
            WHEN prev.last_lsn <> curr.first_lsn THEN N'BREAK'
            ELSE N'OK'
        END AS [Chain_Status]
    FROM LogBackups AS curr
    INNER JOIN LogBackups AS prev
        ON curr.database_name = prev.database_name
       AND curr.rn = prev.rn + 1
)
SELECT
    d.name AS [Database_Name],
    d.recovery_model_desc,
    cc.Previous_Log_Backup,
    cc.Current_Log_Backup,
    cc.Previous_Last_LSN,
    cc.Current_First_LSN,
    cc.Chain_Status
FROM ChainCheck AS cc
INNER JOIN sys.databases AS d ON d.name = cc.database_name
WHERE cc.Chain_Status = N'BREAK'
  AND d.recovery_model_desc = N'FULL'
  AND d.database_id > 4
ORDER BY cc.Current_Log_Backup DESC;

IF @@ROWCOUNT = 0
    PRINT 'No log chain breaks detected in msdb backup history.';
