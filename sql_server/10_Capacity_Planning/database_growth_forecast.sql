/*
================================================================================
SQL Server Database Capacity & Growth Forecasting
================================================================================
Description:
    Estimates database growth trends based on backup size history from msdb.
    Identifies databases with rapid growth rates that may exceed available
    storage capacity.

Output:
    Database name, average size, growth over last 30 days, growth percentage,
    and a growth status indicator.

Action:
    For databases with "WARNING: High Growth (>10%)" in 30 days, calculate
    when the database will exhaust available disk space:
        (Free_Disk_Space_GB) / (Daily_Growth_GB) = Days_Remaining
    Add storage or archive old data before the disk fills. Schedule this script
    monthly and track growth trends over multiple months for more accurate
    forecasting.

Criticality: Medium
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

-- 1. Database Size & Growth Trend (Last 30 Days from Backup History)
PRINT '--- Database Size Growth Trend (Last 30 Days) ---';
SELECT 
    database_name,
    CAST(AVG(backup_size/1024/1024/1024) AS DECIMAL(10,2)) AS [Avg_Size_GB],
    CAST(MAX(backup_size/1024/1024/1024) - MIN(backup_size/1024/1024/1024) AS DECIMAL(10,2)) AS [Growth_GB_30D],
    CASE 
        WHEN (MAX(backup_size) - MIN(backup_size)) / NULLIF(MIN(backup_size), 0) > 0.1 THEN '🟡 WARNING: High Growth (>10%)'
        ELSE '🟢 NORMAL'
    END AS [Growth_Status]
FROM msdb.dbo.backupset
WHERE type = 'D' -- Full Backups
  AND backup_finish_date > DATEADD(DAY, -30, GETDATE())
GROUP BY database_name
ORDER BY [Growth_GB_30D] DESC;

-- 2. Data File Autogrowth Events
PRINT '--- Recent Autogrowth Events (Default Trace) ---';
DECLARE @filename NVARCHAR(1000);
SELECT @filename = path FROM sys.traces WHERE is_default = 1;

IF @filename IS NOT NULL
BEGIN
    SELECT 
        DatabaseName,
        [FileName],
        (Duration / 1000) AS [Duration_ms],
        StartTime,
        ((IntegerData * 8.0) / 1024.0) AS [Growth_MB],
        TextData AS [Event_Type]
    FROM sys.fn_trace_gettable(CAST(SUBSTRING(@filename, 1, LEN(@filename) - CHARINDEX('\', REVERSE(@filename))) + '\log.trc' AS NVARCHAR(1000)), DEFAULT)
    WHERE EventClass IN (92, 93) -- Data/Log File Auto Grow
      AND StartTime > DATEADD(DAY, -7, GETDATE())
    ORDER BY StartTime DESC;
END
ELSE
    PRINT 'Default trace is disabled. Autogrowth events cannot be audited via this method.';
