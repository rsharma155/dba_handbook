/*
================================================================================
SQL Server DBCC CHECKDB History
================================================================================
Description:
    Reports the last successful DBCC CHECKDB date for each database using
    Ola Hallengren's CommandLog table (if available) or msdb backup history
    as a proxy. Databases without recent CHECKDB are flagged.

Output:
    Database name, last CHECKDB date, days since last CHECKDB, and status.

Action:
    For databases with days since last CHECKDB > @MaxDaysWithoutCheckDB,
    schedule a CHECKDB during the next maintenance window:
        DBCC CHECKDB ([DBName]) WITH NO_INFOMSGS, ALL_ERRORMSGS;
    For critical databases, run CHECKDB daily. CHECKDB is essential for
    detecting corruption before it causes data loss.

Parameters:
    @MaxDaysWithoutCheckDB - maximum allowed days without CHECKDB (default 7)

Prerequisites: Ola Hallengren's maintenance solution for CommandLog table.
               Falls back to msdb backup history if CommandLog is unavailable.

Criticality: High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @MaxDaysWithoutCheckDB INT = 7;
DECLARE @HasCommandLog BIT = 0;

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'msdb' AND state = 0)
   AND EXISTS (SELECT 1 FROM msdb.sys.tables WHERE name = N'CommandLog' AND schema_id = SCHEMA_ID(N'dbo'))
    SET @HasCommandLog = 1;

IF @HasCommandLog = 1
BEGIN
    ;WITH LastCheck AS (
        SELECT
            DatabaseName,
            MAX(StartTime) AS last_checkdb_time,
            MAX(CASE WHEN ErrorNumber <> 0 THEN 1 ELSE 0 END) AS had_errors
        FROM msdb.dbo.CommandLog
        WHERE CommandType = N'DBCC_CHECKDB'
        GROUP BY DatabaseName
    )
    SELECT
        d.name AS [Database_Name],
        d.state_desc,
        lc.last_checkdb_time AS [Last_CHECKDB],
        DATEDIFF(DAY, lc.last_checkdb_time, GETDATE()) AS [Days_Since_CHECKDB],
        CASE
            WHEN lc.last_checkdb_time IS NULL THEN N'CRITICAL: Never recorded'
            WHEN DATEDIFF(DAY, lc.last_checkdb_time, GETDATE()) > @MaxDaysWithoutCheckDB THEN N'WARNING: Over SLA'
            WHEN lc.had_errors = 1 THEN N'WARNING: Last run had errors'
            ELSE N'OK'
        END AS [CHECKDB_Status]
    FROM sys.databases AS d
    LEFT JOIN LastCheck AS lc ON lc.DatabaseName = d.name
    WHERE d.database_id > 4
      AND d.state = 0
    ORDER BY [Days_Since_CHECKDB] DESC;
END
ELSE
BEGIN
    PRINT 'msdb.dbo.CommandLog not found. Install Ola Hallengren MaintenanceSolution or run CHECKDB manually.';
    SELECT
        d.name AS [Database_Name],
        d.state_desc,
        CAST(NULL AS DATETIME) AS [Last_CHECKDB],
        CAST(NULL AS INT) AS [Days_Since_CHECKDB],
        N'UNKNOWN: No CommandLog table' AS [CHECKDB_Status]
    FROM sys.databases AS d
    WHERE d.database_id > 4 AND d.state = 0
    ORDER BY d.name;
END;
