/*
================================================================================
sp_DBA_BackupReview — Backup health and log chain integrity
================================================================================
Reviews last backup dates by type (full/diff/log), checks recovery model
alignment, detects potential log chain breaks, and flags databases missing
required backups based on SLA.

Usage:
    EXEC dbo.sp_DBA_BackupReview;
    EXEC dbo.sp_DBA_BackupReview @BackupHoursSLA = 48;
    EXEC dbo.sp_DBA_BackupReview @DatabaseList = N'SalesDB,HRDB';
================================================================================
*/
IF OBJECT_ID(N'dbo.sp_DBA_BackupReview', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DBA_BackupReview AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_DBA_BackupReview
    @DatabaseList       NVARCHAR(MAX) = NULL,
    @IncludeReadOnly    BIT = 0,
    @BackupHoursSLA     INT = 24,
    @BackupDaysSLA      INT = 7
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    -- Section 1: Backup Summary per Database
    PRINT '--- Backup Summary by Database ---';
    SELECT
        d.name AS DatabaseName,
        d.recovery_model_desc AS RecoveryModel,
        d.state_desc AS State,
        MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS LastFullBackup,
        MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS LastDiffBackup,
        MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS LastLogBackup,
        MAX(b.backup_finish_date) AS LastAnyBackup,
        DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) AS HoursSinceFull,
        DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END), GETDATE()) AS HoursSinceLog,
        CASE
            WHEN MAX(b.backup_finish_date) IS NULL THEN 'CRITICAL: No backups found'
            WHEN d.recovery_model_desc = 'FULL'
                 AND DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END), GETDATE()) > @BackupHoursSLA
                THEN 'CRITICAL: Log backup exceeds SLA'
            WHEN d.recovery_model_desc = 'FULL'
                 AND MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) IS NULL
                THEN 'HIGH: FULL recovery but no log backups'
            WHEN DATEDIFF(DAY, MAX(b.backup_finish_date), GETDATE()) > @BackupDaysSLA
                THEN 'HIGH: Last backup exceeds ' + CAST(@BackupDaysSLA AS VARCHAR) + ' days'
            ELSE 'OK'
        END AS BackupStatus
    FROM sys.databases AS d
    LEFT JOIN msdb.dbo.backupset AS b ON d.name = b.database_name
    WHERE d.database_id > 4
      AND d.state = 0
      AND (
          @DatabaseList IS NULL
          OR d.name IN (
              SELECT LTRIM(RTRIM(value))
              FROM STRING_SPLIT(@DatabaseList, N',')
              WHERE LTRIM(RTRIM(value)) <> N''
          )
      )
    GROUP BY d.name, d.recovery_model_desc, d.state_desc
    ORDER BY
        CASE
            WHEN MAX(b.backup_finish_date) IS NULL THEN 0
            WHEN DATEDIFF(HOUR, MAX(b.backup_finish_date), GETDATE()) > @BackupHoursSLA THEN 1
            ELSE 2
        END,
        d.name;

    -- Section 2: Backup Types & Compression
    PRINT '--- Backup Type Distribution (Last 7 Days) ---';
    SELECT
        database_name AS DatabaseName,
        type AS BackupType,
        COUNT(*) AS BackupCount,
        SUM(CASE WHEN compressed_backup_size > 0 THEN 1 ELSE 0 END) AS CompressedCount,
        CAST(AVG(backup_size / 1024.0 / 1024.0) AS NUMERIC(10,2)) AS AvgSizeMB,
        CAST(AVG(compressed_backup_size / 1024.0 / 1024.0) AS NUMERIC(10,2)) AS AvgCompressedMB,
        MIN(backup_finish_date) AS EarliestBackup,
        MAX(backup_finish_date) AS LatestBackup
    FROM msdb.dbo.backupset
    WHERE backup_finish_date > DATEADD(DAY, -7, GETDATE())
      AND database_name <> N'master'
    GROUP BY database_name, type
    ORDER BY database_name, type;

    -- Section 3: Databases Missing Required Backups
    PRINT '--- Databases Without Recent Full Backups ---';
    SELECT
        d.name AS DatabaseName,
        d.recovery_model_desc AS RecoveryModel,
        MAX(b.backup_finish_date) AS LastFullBackup,
        DATEDIFF(DAY, MAX(b.backup_finish_date), GETDATE()) AS DaysSinceFullBackup
    FROM sys.databases AS d
    LEFT JOIN msdb.dbo.backupset AS b
        ON d.name = b.database_name AND b.type = 'D'
    WHERE d.database_id > 4
      AND d.state = 0
    GROUP BY d.name, d.recovery_model_desc
    HAVING (MAX(b.backup_finish_date) IS NULL OR DATEDIFF(DAY, MAX(b.backup_finish_date), GETDATE()) > @BackupDaysSLA)
    ORDER BY DaysSinceFullBackup DESC;

    -- Section 4: Log Chain Risk (FULL recovery without recent log backup)
    PRINT '--- Log Chain Risk Assessment ---';
    SELECT
        d.name AS DatabaseName,
        CASE WHEN MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) IS NULL
            THEN 'NO LOG BACKUPS'
            ELSE CAST(DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END), GETDATE()) AS VARCHAR) + ' hours since last log'
        END AS LogBackupStatus,
        CASE
            WHEN MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) IS NULL THEN 'CRITICAL'
            WHEN DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END), GETDATE()) > @BackupHoursSLA THEN 'HIGH'
            ELSE 'OK'
        END AS RiskLevel
    FROM sys.databases AS d
    LEFT JOIN msdb.dbo.backupset AS b ON d.name = b.database_name
    WHERE d.recovery_model_desc = 'FULL'
      AND d.database_id > 4
      AND d.state = 0
    GROUP BY d.name
    ORDER BY
        CASE
            WHEN MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) IS NULL THEN 0
            WHEN DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END), GETDATE()) > @BackupHoursSLA THEN 1
            ELSE 2
        END;
END;
GO
