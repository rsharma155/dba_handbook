/*
================================================================================
SQL Server Database Size and Configuration Inventory
================================================================================
Description:
    Reports database-level size, file counts, compatibility level, collation,
    current log reuse wait reason, recovery model, and key database options.
    The primary result set is sorted by total allocated database size descending.

Output:
    Result set 1: One row per database with total/data/log size, data/log file
                  counts, log space usage, compatibility, collation, owner, and
                  database option details.
    Result set 2: File-level details with current file size, max size, growth,
                  and physical path.

Action:
    Use this script for instance inventory, capacity reviews, migration planning,
    and upgrade readiness checks. Investigate databases with unexpected
    log_reuse_wait_desc values, old compatibility levels, percentage file growth,
    AUTO_CLOSE/AUTO_SHRINK enabled, or unusually large log/data files.

Parameters:
    @DatabaseList - comma-separated database names or NULL for all databases
    @IncludeSystemDatabases - 1 includes master/model/msdb/tempdb; 0 user DBs only

Criticality: Medium
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL; -- e.g. N'SalesDB,HRDB'
DECLARE @IncludeSystemDatabases BIT = 1;

DECLARE @InstanceCompat INT =
    COALESCE(
        CAST(SERVERPROPERTY(N'ProductMajorVersion') AS INT),
        CAST(PARSENAME(CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)), 4) AS INT)
    ) * 10;

IF OBJECT_ID(N'tempdb..#DbTargets') IS NOT NULL DROP TABLE #DbTargets;
CREATE TABLE #DbTargets (
    database_id INT NOT NULL PRIMARY KEY,
    database_name SYSNAME NOT NULL
);

IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
BEGIN
    DECLARE @DatabaseListXml XML;

    SET @DatabaseListXml = TRY_CAST(
        N'<db>' +
        REPLACE((SELECT @DatabaseList AS [*] FOR XML PATH(N'')), N',', N'</db><db>') +
        N'</db>' AS XML
    );

    INSERT INTO #DbTargets (database_id, database_name)
    SELECT d.database_id, d.name
    FROM sys.databases AS d
    INNER JOIN (
        SELECT DISTINCT LTRIM(RTRIM(T.C.value(N'.', N'sysname'))) AS database_name
        FROM @DatabaseListXml.nodes(N'/db') AS T(C)
        WHERE LTRIM(RTRIM(T.C.value(N'.', N'nvarchar(128)'))) <> N''
    ) AS requested
        ON requested.database_name = d.name;
END;
ELSE
BEGIN
    INSERT INTO #DbTargets (database_id, database_name)
    SELECT d.database_id, d.name
    FROM sys.databases AS d
    WHERE (@IncludeSystemDatabases = 1 OR d.database_id > 4);
END;

IF OBJECT_ID(N'tempdb..#LogSpace') IS NOT NULL DROP TABLE #LogSpace;
CREATE TABLE #LogSpace (
    DatabaseName SYSNAME NOT NULL,
    LogSizeMB DECIMAL(18,2) NULL,
    LogSpaceUsedPct DECIMAL(9,2) NULL,
    [Status] INT NULL
);

INSERT INTO #LogSpace (DatabaseName, LogSizeMB, LogSpaceUsedPct, [Status])
EXEC(N'DBCC SQLPERF(LOGSPACE) WITH NO_INFOMSGS;');

;WITH FileRollup AS (
    SELECT
        mf.database_id,
        COUNT(CASE WHEN mf.type = 0 THEN 1 END) AS DataFileCount,
        COUNT(CASE WHEN mf.type = 1 THEN 1 END) AS LogFileCount,
        CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size ELSE 0 END) * 8.0 / 1024 AS DECIMAL(18,2)) AS DataSizeMB,
        CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size ELSE 0 END) * 8.0 / 1024 AS DECIMAL(18,2)) AS LogSizeMB,
        CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(18,2)) AS TotalSizeMB
    FROM sys.master_files AS mf
    INNER JOIN #DbTargets AS t
        ON t.database_id = mf.database_id
    GROUP BY mf.database_id
)
SELECT
    @@SERVERNAME AS [Server_Name],
    d.name AS [Database_Name],
    --d.database_id AS [Database_Id],
    d.state_desc AS [State_Desc],
    d.recovery_model_desc AS [Recovery_Model_Desc],
    d.compatibility_level AS [Compatibility_Level],
    @InstanceCompat AS [Instance_Default_Compat_Level],
    --CASE
    --    WHEN d.compatibility_level < @InstanceCompat THEN N'WARNING: Below instance level'
    --    WHEN d.compatibility_level > @InstanceCompat THEN N'REVIEW: Above instance level'
    --    ELSE N'OK'
    --END AS [Compatibility_Status],
    d.collation_name AS [Collation_Name],
    d.log_reuse_wait_desc AS [Log_Reuse_Wait_Desc],
    fr.TotalSizeMB AS [Total_Database_Size_MB],
    CAST(fr.TotalSizeMB / 1024.0 AS DECIMAL(18,2)) AS [Total_Database_Size_GB],
    fr.DataSizeMB AS [Data_File_Size_MB],
    CAST(fr.DataSizeMB / 1024.0 AS DECIMAL(18,2)) AS [Data_File_Size_GB],
    fr.LogSizeMB AS [Log_File_Size_MB],
    CAST(fr.LogSizeMB / 1024.0 AS DECIMAL(18,2)) AS [Log_File_Size_GB],
    fr.DataFileCount AS [Data_File_Count],
    fr.LogFileCount AS [Log_File_Count],
    ls.LogSpaceUsedPct AS [Log_Space_Used_Pct],
    CAST(ls.LogSizeMB * ls.LogSpaceUsedPct / 100.0 AS DECIMAL(18,2)) AS [Log_Space_Used_MB],
    CAST(ls.LogSizeMB - (ls.LogSizeMB * ls.LogSpaceUsedPct / 100.0) AS DECIMAL(18,2)) AS [Log_Space_Free_MB],
    STUFF((
        SELECT N'; ' + mf.name + N'=' + CAST(CAST(mf.size * 8.0 / 1024 AS DECIMAL(18,2)) AS NVARCHAR(30)) + N' MB'
        FROM sys.master_files AS mf
        WHERE mf.database_id = d.database_id
          AND mf.type = 0
        ORDER BY mf.file_id
        FOR XML PATH(N''), TYPE
    ).value(N'.', N'nvarchar(max)'), 1, 2, N'') AS [Data_File_Size_Detail],
    STUFF((
        SELECT N'; ' + mf.name + N'=' + CAST(CAST(mf.size * 8.0 / 1024 AS DECIMAL(18,2)) AS NVARCHAR(30)) + N' MB'
        FROM sys.master_files AS mf
        WHERE mf.database_id = d.database_id
          AND mf.type = 1
        ORDER BY mf.file_id
        FOR XML PATH(N''), TYPE
    ).value(N'.', N'nvarchar(max)'), 1, 2, N'') AS [Log_File_Size_Detail],
    SUSER_SNAME(d.owner_sid) AS [Database_Owner],
    d.create_date AS [Create_Date],
    d.user_access_desc AS [User_Access_Desc],
    d.page_verify_option_desc AS [Page_Verify_Option_Desc],
    d.is_read_only AS [Is_Read_Only],
    d.is_auto_close_on AS [Is_Auto_Close_On],
    d.is_auto_shrink_on AS [Is_Auto_Shrink_On],
    d.is_encrypted AS [Is_Encrypted],
    d.is_query_store_on AS [Is_Query_Store_On],
    d.snapshot_isolation_state_desc AS [Snapshot_Isolation_State_Desc],
    d.is_read_committed_snapshot_on AS [Is_Read_Committed_Snapshot_On],
    d.is_broker_enabled AS [Is_Service_Broker_Enabled],
    d.target_recovery_time_in_seconds AS [Target_Recovery_Time_Seconds],
    d.containment_desc AS [Containment_Desc]
FROM sys.databases AS d
INNER JOIN #DbTargets AS t
    ON t.database_id = d.database_id
INNER JOIN FileRollup AS fr
    ON fr.database_id = d.database_id
LEFT JOIN #LogSpace AS ls
    ON ls.DatabaseName = d.name
ORDER BY fr.TotalSizeMB DESC, d.name;

SELECT
    DB_NAME(mf.database_id) AS [Database_Name],
    mf.file_id AS [File_Id],
    mf.name AS [Logical_File_Name],
    mf.type_desc AS [File_Type],
    CAST(mf.size * 8.0 / 1024 AS DECIMAL(18,2)) AS [Current_File_Size_MB],
    CAST(mf.size * 8.0 / 1024 / 1024 AS DECIMAL(18,2)) AS [Current_File_Size_GB],
    CASE
        WHEN mf.max_size = -1 THEN N'UNLIMITED'
        WHEN mf.max_size = 0 THEN N'NO_GROWTH'
        ELSE CAST(CAST(mf.max_size * 8.0 / 1024 AS DECIMAL(18,2)) AS NVARCHAR(30)) + N' MB'
    END AS [Max_Size],
    CASE
        WHEN mf.is_percent_growth = 1 THEN CAST(mf.growth AS NVARCHAR(30)) + N'%'
        WHEN mf.growth = 0 THEN N'NO_GROWTH'
        ELSE CAST(CAST(mf.growth * 8.0 / 1024 AS DECIMAL(18,2)) AS NVARCHAR(30)) + N' MB'
    END AS [Growth_Setting],
    mf.is_percent_growth AS [Is_Percent_Growth],
    mf.state_desc AS [File_State_Desc],
    mf.physical_name AS [Physical_File_Name]
FROM sys.master_files AS mf
INNER JOIN #DbTargets AS t
    ON t.database_id = mf.database_id
ORDER BY
    DB_NAME(mf.database_id),
    mf.type,
    mf.file_id;

DROP TABLE #LogSpace;
DROP TABLE #DbTargets;
