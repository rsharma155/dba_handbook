/*
    Migration 2016 -> 2022 | Stretch Database blocker check
    Stretch was discontinued — must unstretch all tables before upgrade.
    Risk: Read-only
*/
SET NOCOUNT ON;

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + N'
USE ' + QUOTENAME(name) + N';
IF EXISTS (SELECT 1 FROM sys.tables WHERE is_remote_data_archive_enabled = 1)
BEGIN
    SELECT DB_NAME() AS DatabaseName, t.name AS TableName, t.is_remote_data_archive_enabled
    FROM sys.tables AS t
    WHERE t.is_remote_data_archive_enabled = 1;
END
'
FROM sys.databases
WHERE database_id > 4 AND state = 0;

IF LEN(@sql) = 0
    SELECT N'No online user databases to scan' AS [Note];
ELSE
    EXEC sys.sp_executesql @sql;
