/*
================================================================================
Purpose:        Automated restore testing simulator for disaster recovery 
                readiness validation. This script:
                1. Shows the last known backup chain for each database
                2. Calculates the estimated restore time based on backup sizes
                3. Generates the exact RESTORE commands needed for a point-in-time restore
                4. Identifies broken log chains or missing backups
                5. Validates recovery model alignment with backup strategy

                This is a READ-ONLY planning tool — it does NOT execute restores.
                Use it to verify your DR readiness before an actual disaster.

Provides:       - Backup chain completeness per database
                - Estimated restore time (full + diff + logs)
                - Generated RESTORE WITH RECOVERY commands
                - RPO/RTO estimation based on last backup age
                - Broken log chain detection
Importance:     A backup is useless if you can't restore. This script validates
                the entire restore chain and tells you exactly how long recovery
                would take — BEFORE you need it.
Interpretation: If Estimated_Restore_Minutes > your RTO target, you have a 
                problem. Fix backup frequency or restore procedures.
Action: If Estimated_Restore_Minutes exceeds your RTO, increase backup frequency or invest in faster storage. If broken log chains are detected, take a new full backup immediately to re-establish the chain. Save the generated RESTORE commands to a recovery document. Schedule this script weekly to verify DR readiness.
Criticality:    High (run weekly, before DR drills)
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

------------------------------------------------------------
-- 1. Backup Chain Completeness (per database)
------------------------------------------------------------
SELECT N'BACKUP CHAIN STATUS' AS [Section];
SELECT
    b.database_name                                           AS [Database_Name],
    b.recovery_model_desc                                     AS [Recovery_Model],
    b.backup_finish_date                                      AS [Last_Backup_Time],
    DATEDIFF(MINUTE, b.backup_finish_date, GETDATE())        AS [Age_Minutes],
    CASE
        WHEN DATEDIFF(MINUTE, b.backup_finish_date, GETDATE()) <= 60 THEN 'OK (< 1 hour)'
        WHEN DATEDIFF(MINUTE, b.backup_finish_date, GETDATE()) <= 1440 THEN 'WARNING (< 24 hours)'
        WHEN DATEDIFF(MINUTE, b.backup_finish_date, GETDATE()) <= 4320 THEN 'AT RISK (< 3 days)'
        ELSE 'CRITICAL (> 3 days)'
    END                                                       AS [Backup_Age_Status],
    b.type                                                   AS [Backup_Type],
    CASE b.type
        WHEN 'D' THEN 'FULL'
        WHEN 'I' THEN 'DIFFERENTIAL'
        WHEN 'L' THEN 'LOG'
        WHEN 'F' THEN 'FILE/DIFF'
        WHEN 'G' THEN 'FILEGROUP'
        ELSE b.type
    END                                                       AS [Backup_Type_Desc],
    b.backup_size / 1048576.0                                 AS [Backup_Size_MB],
    b.compressed_backup_size / 1048576.0                      AS [Compressed_Size_MB],
    b.physical_device_name                                    AS [Backup_File_Path],
    b.first_lsn                                              AS [First_LSN],
    b.last_lsn                                               AS [Last_LSN],
    DATEDIFF(SECOND, b.backup_start_date, b.backup_finish_date) AS [Backup_Duration_Sec],
    CASE
        WHEN b.backup_size > 0 AND DATEDIFF(SECOND, b.backup_start_date, b.backup_finish_date) > 0
        THEN (b.backup_size / 1048576.0) / DATEDIFF(SECOND, b.backup_start_date, b.backup_finish_date)
        ELSE 0
    END                                                       AS [Throughput_MB_per_Sec]
FROM (
    SELECT
        bs.database_name,
        CASE bs.recovery_model WHEN 'F' THEN 'FULL' WHEN 'S' THEN 'SIMPLE' WHEN 'B' THEN 'BULK_LOGGED' ELSE bs.recovery_model END AS recovery_model_desc,
        bs.backup_finish_date,
        bs.type,
        bs.backup_size,
        bs.compressed_backup_size,
        bs.first_lsn,
        bs.last_lsn,
        bs.backup_start_date,
        bmf.physical_device_name,
        ROW_NUMBER() OVER (PARTITION BY bs.database_name, bs.type ORDER BY bs.backup_finish_date DESC) AS rn
    FROM msdb.dbo.backupset bs
    INNER JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
    WHERE bs.database_name NOT IN ('tempdb', 'model')
) b
WHERE b.rn <= 3
ORDER BY b.database_name, b.backup_finish_date DESC;

------------------------------------------------------------
-- 2. Estimated Restore Chain (what you need for recovery)
------------------------------------------------------------
SELECT N'ESTIMATED RESTORE CHAIN (per database)' AS [Section];
SELECT
    db.database_name                                          AS [Database_Name],
    db.recovery_model_desc                                    AS [Recovery_Model],
    -- Last full backup
    full_b.backup_finish_date                                 AS [Last_Full_Backup],
    full_b.backup_size / 1048576.0                            AS [Full_Backup_MB],
    full_b.physical_device_name                               AS [Full_Backup_Path],
    -- Last diff backup (if any)
    diff_b.backup_finish_date                                 AS [Last_Diff_Backup],
    diff_b.backup_size / 1048576.0                            AS [Diff_Backup_MB],
    diff_b.physical_device_name                               AS [Diff_Backup_Path],
    -- Log backups
    log_b.log_count                                           AS [Log_Backups_After_Full],
    log_b.total_log_mb                                        AS [Total_Log_MB],
    -- Estimation
    ISNULL(full_b.backup_size, 0) / 1048576.0
        + ISNULL(diff_b.backup_size, 0) / 1048576.0
        + ISNULL(log_b.total_log_mb, 0)                     AS [Total_Restore_Size_MB],
    CASE
        WHEN full_b.backup_size IS NULL THEN 'MISSING FULL BACKUP'
        WHEN db.recovery_model_desc = 'SIMPLE' AND diff_b.backup_size IS NULL THEN 'FULL + LOG ONLY (no diff)'
        ELSE 'FULL + DIFF + ' + CAST(ISNULL(log_b.log_count, 0) AS VARCHAR(10)) + ' LOG(s)'
    END                                                       AS [Restore_Command_Summary],
    -- RPO estimate (how much data you could lose)
    DATEDIFF(MINUTE, ISNULL(log_b.last_log, diff_b.backup_finish_date), GETDATE()) AS [Minutes_Since_Last_Backup],
    CASE
        WHEN db.recovery_model_desc = 'SIMPLE'
        THEN 'RPO = time since last full/diff backup'
        ELSE 'RPO = time since last log backup'
    END                                                       AS [RPO_Explanation]
FROM (
    SELECT DISTINCT database_name, CASE recovery_model WHEN 'F' THEN 'FULL' WHEN 'S' THEN 'SIMPLE' WHEN 'B' THEN 'BULK_LOGGED' ELSE recovery_model END AS recovery_model_desc
    FROM msdb.dbo.backupset
    WHERE database_name NOT IN ('tempdb', 'model')
) db
-- Last full backup
LEFT JOIN (
    SELECT database_name, backup_finish_date, backup_size, physical_device_name
    FROM (
        SELECT bs.database_name, bs.backup_finish_date, bs.backup_size, bmf.physical_device_name,
               ROW_NUMBER() OVER (PARTITION BY bs.database_name ORDER BY bs.backup_finish_date DESC) AS rn
        FROM msdb.dbo.backupset bs
        INNER JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
        WHERE bs.type = 'D'
          AND bs.database_name NOT IN ('tempdb', 'model')
    ) ranked
    WHERE rn = 1
) full_b ON db.database_name = full_b.database_name
-- Last diff backup
LEFT JOIN (
    SELECT database_name, backup_finish_date, backup_size, physical_device_name
    FROM (
        SELECT bs.database_name, bs.backup_finish_date, bs.backup_size, bmf.physical_device_name,
               ROW_NUMBER() OVER (PARTITION BY bs.database_name ORDER BY bs.backup_finish_date DESC) AS rn
        FROM msdb.dbo.backupset bs
        INNER JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
        WHERE bs.type = 'I'
          AND bs.database_name NOT IN ('tempdb', 'model')
    ) ranked
    WHERE rn = 1
) diff_b ON db.database_name = diff_b.database_name
-- Log backup summary
LEFT JOIN (
    SELECT
        bs.database_name,
        COUNT(*) AS log_count,
        SUM(bs.backup_size) / 1048576.0 AS total_log_mb,
        MAX(bs.backup_finish_date) AS last_log
    FROM msdb.dbo.backupset bs
    WHERE bs.type = 'L'
      AND bs.database_name NOT IN ('tempdb', 'model')
    GROUP BY bs.database_name
) log_b ON db.database_name = log_b.database_name
ORDER BY db.database_name;

------------------------------------------------------------
-- 3. Generate RESTORE Commands (read-only, copy to use)
------------------------------------------------------------
SELECT N'GENERATED RESTORE COMMANDS (review before using!)' AS [Section];

-- For each database, generate the restore chain
SELECT
    bs.database_name                                          AS [Database_Name],
    'RESTORE DATABASE [' + bs.database_name + N'] FROM DISK = N''' + bmf.physical_device_name + N''' WITH NORECOVERY, REPLACE;' AS [Restore_Command],
    'FULL' AS [Backup_Type],
    bs.backup_finish_date                                     AS [Backup_Date],
    bs.backup_size / 1048576.0                                AS [Size_MB]
FROM (
    SELECT database_name, media_set_id, backup_finish_date, backup_size,
           ROW_NUMBER() OVER (PARTITION BY database_name ORDER BY backup_finish_date DESC) AS rn
    FROM msdb.dbo.backupset
    WHERE type = 'D' AND database_name NOT IN ('tempdb', 'model')
) bs
INNER JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE bs.rn = 1

UNION ALL

SELECT
    bs.database_name,
    'RESTORE LOG [' + bs.database_name + N'] FROM DISK = N''' + bmf.physical_device_name + N''' WITH NORECOVERY;',
    'LOG',
    bs.backup_finish_date,
    bs.backup_size / 1048576.0
FROM (
    SELECT database_name, media_set_id, backup_finish_date, backup_size,
           ROW_NUMBER() OVER (PARTITION BY database_name ORDER BY backup_finish_date DESC) AS rn
    FROM msdb.dbo.backupset
    WHERE type = 'L' AND database_name NOT IN ('tempdb', 'model')
) bs
INNER JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE bs.rn = 1

UNION ALL

-- Final recovery command
SELECT
    bs.database_name,
    'RESTORE DATABASE [' + bs.database_name + N'] WITH RECOVERY; -- Run this AFTER all restores complete',
    'FINAL_RECOVERY',
    NULL,
    NULL
FROM (
    SELECT database_name
    FROM msdb.dbo.backupset
    WHERE type = 'D' AND database_name NOT IN ('tempdb', 'model')
    GROUP BY database_name
) bs

ORDER BY bs.database_name, [Backup_Type];

------------------------------------------------------------
-- 4. Broken Log Chain Detection
------------------------------------------------------------
SELECT N'BROKEN LOG CHAIN CHECK' AS [Section];
WITH LogChains AS (
    SELECT
        bs.database_name,
        bs.backup_finish_date,
        bs.first_lsn,
        bs.last_lsn,
        LAG(bs.last_lsn) OVER (PARTITION BY bs.database_name ORDER BY bs.backup_finish_date) AS prev_last_lsn,
        LAG(bs.backup_finish_date) OVER (PARTITION BY bs.database_name ORDER BY bs.backup_finish_date) AS prev_backup_date
    FROM msdb.dbo.backupset bs
    WHERE bs.type IN ('D', 'L')
      AND bs.database_name NOT IN ('tempdb', 'model')
)
SELECT
    database_name                                              AS [Database_Name],
    backup_finish_date                                         AS [Backup_Time],
    first_lsn                                                 AS [First_LSN],
    last_lsn                                                  AS [Last_LSN],
    prev_last_lsn                                             AS [Previous_Last_LSN],
    CASE
        WHEN prev_last_lsn IS NULL THEN 'START of chain'
        WHEN first_lsn <= prev_last_lsn THEN 'CHAIN OK'
        ELSE 'CHAIN BREAK! LSN gap detected.'
    END                                                       AS [Chain_Status]
FROM LogChains
WHERE prev_last_lsn IS NOT NULL
  AND first_lsn > prev_last_lsn
ORDER BY database_name, backup_finish_date;

------------------------------------------------------------
-- 5. Recovery Model Alignment
------------------------------------------------------------
SELECT N'RECOVERY MODEL vs BACKUP STRATEGY' AS [Section];
SELECT
    db.name                                                  AS [Database_Name],
    db.recovery_model_desc                                    AS [Current_Recovery_Model],
    ISNULL(last_full.type, 'NONE')                           AS [Last_Full_Type],
    ISNULL(last_diff.type, 'NONE')                           AS [Last_Diff_Type],
    ISNULL(last_log.type, 'NONE')                            AS [Last_Log_Type],
    CASE
        WHEN db.recovery_model_desc = 'SIMPLE' AND last_log.type IS NOT NULL
        THEN 'WARNING: Log backups in SIMPLE recovery are ineffective (auto-truncated). Switch to FULL.'
        WHEN db.recovery_model_desc = 'FULL' AND last_log.type IS NULL
        THEN 'WARNING: No log backups in FULL recovery. Log file will grow unbounded. Take log backups.'
        WHEN db.recovery_model_desc = 'BULK_LOGGED' AND last_log.type IS NULL
        THEN 'WARNING: No log backups in BULK_LOGGED recovery. Switch to FULL for point-in-time recovery.'
        ELSE 'Alignment OK'
    END                                                       AS [Alignment_Status]
FROM sys.databases db
LEFT JOIN (
    SELECT database_name, type,
           ROW_NUMBER() OVER (PARTITION BY database_name ORDER BY backup_finish_date DESC) AS rn
    FROM msdb.dbo.backupset WHERE type = 'D'
) last_full ON db.name = last_full.database_name AND last_full.rn = 1
LEFT JOIN (
    SELECT database_name, type,
           ROW_NUMBER() OVER (PARTITION BY database_name ORDER BY backup_finish_date DESC) AS rn
    FROM msdb.dbo.backupset WHERE type = 'I'
) last_diff ON db.name = last_diff.database_name AND last_diff.rn = 1
LEFT JOIN (
    SELECT database_name, type,
           ROW_NUMBER() OVER (PARTITION BY database_name ORDER BY backup_finish_date DESC) AS rn
    FROM msdb.dbo.backupset WHERE type = 'L'
) last_log ON db.name = last_log.database_name AND last_log.rn = 1
WHERE db.name NOT IN ('tempdb', 'model')
ORDER BY db.name;

PRINT N'--- Restore testing complete. Review generated commands before execution. ---';
PRINT N'--- Tip: For automated restore tests, pipe the generated commands to a linked server ---';
PRINT N'--- or use sp_DBA_ForEachDatabase to run RESTORE ... WITH STOPAT on a test instance. ---';
GO
