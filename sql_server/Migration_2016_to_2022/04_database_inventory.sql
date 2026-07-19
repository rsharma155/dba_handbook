/*
    Migration 2016 -> 2022 | Database inventory
    Risk: Read-only
*/
SET NOCOUNT ON;

SELECT
    d.name AS [DatabaseName],
    d.database_id,
    d.state_desc,
    d.recovery_model_desc,
    d.compatibility_level,
    d.collation_name,
    d.is_read_only,
    d.is_auto_close_on,
    d.is_auto_shrink_on,
    d.page_verify_option_desc,
    d.log_reuse_wait_desc,
    d.create_date,
    CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size END) * 8.0 / 1024 AS DECIMAL(18,2)) AS [DataSizeMB],
    CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size END) * 8.0 / 1024 AS DECIMAL(18,2)) AS [LogSizeMB],
    CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(18,2)) AS [TotalSizeMB]
FROM sys.databases AS d
JOIN sys.master_files AS mf ON d.database_id = mf.database_id
WHERE d.database_id > 4
GROUP BY
    d.name, d.database_id, d.state_desc, d.recovery_model_desc, d.compatibility_level,
    d.collation_name, d.is_read_only, d.is_auto_close_on, d.is_auto_shrink_on,
    d.page_verify_option_desc, d.log_reuse_wait_desc, d.create_date
ORDER BY [TotalSizeMB] DESC;
