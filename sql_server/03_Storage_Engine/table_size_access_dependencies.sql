/*
================================================================================
Purpose:        Lists user tables across databases sorted by size, with row counts,
                space usage, last access timestamps, and dependency details.
Provides:       Database, schema, table, row count, reserved/used/data/index space,
                last SELECT access, last DML access, usage counters, and referencing
                stored procedures, views, functions, and triggers.
Importance:     Helps identify the largest tables, stale tables, unused objects,
                and objects that depend on a table before archive/drop/refactor work.
Interpretation: SQL Server exposes last SELECT through seek/scan/lookup timestamps
                and last INSERT/UPDATE/DELETE as one combined last_user_update value
                in sys.dm_db_index_usage_stats. These DMV values reset on restart,
                database detach, AUTO_CLOSE, or index metadata recreation.
Action:         Review large, low-access tables for retention/archive candidates.
                Check dependency columns before changing or dropping a table.
Criticality:    Medium
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = '_DTRG_Dev_Hospital'; -- e.g. N'SalesDB,HRDB'; NULL = all online user DBs
DECLARE @IncludeSystemShipped BIT = 0;

IF OBJECT_ID(N'tempdb..#DbTargets') IS NOT NULL DROP TABLE #DbTargets;
CREATE TABLE #DbTargets (database_name SYSNAME NOT NULL PRIMARY KEY);

IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
BEGIN
    INSERT INTO #DbTargets (database_name)
    SELECT LTRIM(RTRIM(value))
    FROM STRING_SPLIT(@DatabaseList, N',')
    WHERE LTRIM(RTRIM(value)) <> N'';
END;
ELSE
BEGIN
    INSERT INTO #DbTargets (database_name)
    SELECT name
    FROM sys.databases
    WHERE name NOT IN (N'master', N'model', N'msdb', N'tempdb', N'mssqlsystemresource')
      AND state = 0
      AND is_in_standby = 0;
END;

IF OBJECT_ID(N'tempdb..#TableInventory') IS NOT NULL DROP TABLE #TableInventory;
CREATE TABLE #TableInventory
(
    Database_Name SYSNAME NULL,
    Schema_Name SYSNAME NULL,
    Table_Name SYSNAME NULL,
    Object_Id INT NULL,
    Row_Count BIGINT NULL,
    Reserved_MB DECIMAL(19,2) NULL,
    Used_MB DECIMAL(19,2) NULL,
    Data_MB DECIMAL(19,2) NULL,
    Index_MB DECIMAL(19,2) NULL,
    Unused_MB DECIMAL(19,2) NULL,
    Last_Select_Access DATETIME NULL,
    Last_Insert_Update_Delete_Access DATETIME NULL,
    User_Seeks BIGINT NULL,
    User_Scans BIGINT NULL,
    User_Lookups BIGINT NULL,
    User_Updates BIGINT NULL,
    Referencing_Stored_Procedures NVARCHAR(MAX) NULL,
    Referencing_Views NVARCHAR(MAX) NULL,
    Referencing_Functions NVARCHAR(MAX) NULL,
    Referencing_Triggers NVARCHAR(MAX) NULL,
    Metric_Context VARCHAR(1000) NULL
);

DECLARE @db_name SYSNAME;
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT database_name FROM #DbTargets ORDER BY database_name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'USE ' + QUOTENAME(@db_name) + N';
WITH SpaceStats AS
(
    SELECT
        dps.object_id,
        SUM(CASE WHEN dps.index_id IN (0, 1) THEN dps.row_count ELSE 0 END) AS Row_Count,
        SUM(dps.reserved_page_count) AS Reserved_Pages,
        SUM(dps.used_page_count) AS Used_Pages,
        SUM(
            CASE
                WHEN dps.index_id IN (0, 1)
                    THEN dps.in_row_data_page_count + dps.lob_used_page_count + dps.row_overflow_used_page_count
                ELSE 0
            END
        ) AS Data_Pages
    FROM sys.dm_db_partition_stats AS dps
    GROUP BY dps.object_id
),
UsageStats AS
(
    SELECT
        ius.object_id,
        MAX(ius.last_user_seek) AS Last_User_Seek,
        MAX(ius.last_user_scan) AS Last_User_Scan,
        MAX(ius.last_user_lookup) AS Last_User_Lookup,
        MAX(ius.last_user_update) AS Last_Insert_Update_Delete_Access,
        SUM(CONVERT(BIGINT, ius.user_seeks)) AS User_Seeks,
        SUM(CONVERT(BIGINT, ius.user_scans)) AS User_Scans,
        SUM(CONVERT(BIGINT, ius.user_lookups)) AS User_Lookups,
        SUM(CONVERT(BIGINT, ius.user_updates)) AS User_Updates
    FROM sys.dm_db_index_usage_stats AS ius
    WHERE ius.database_id = DB_ID()
    GROUP BY ius.object_id
)
INSERT INTO #TableInventory
SELECT
    DB_NAME() AS [Database_Name],
    s.name AS [Schema_Name],
    t.name AS [Table_Name],
    t.object_id AS [Object_Id],
    ISNULL(ss.Row_Count, 0) AS [Row_Count],
    CAST(ISNULL(ss.Reserved_Pages, 0) * 8.0 / 1024 AS DECIMAL(19,2)) AS [Reserved_MB],
    CAST(ISNULL(ss.Used_Pages, 0) * 8.0 / 1024 AS DECIMAL(19,2)) AS [Used_MB],
    CAST(ISNULL(ss.Data_Pages, 0) * 8.0 / 1024 AS DECIMAL(19,2)) AS [Data_MB],
    CAST((ISNULL(ss.Used_Pages, 0) - ISNULL(ss.Data_Pages, 0)) * 8.0 / 1024 AS DECIMAL(19,2)) AS [Index_MB],
    CAST((ISNULL(ss.Reserved_Pages, 0) - ISNULL(ss.Used_Pages, 0)) * 8.0 / 1024 AS DECIMAL(19,2)) AS [Unused_MB],
    last_select.Last_Select_Access AS [Last_Select_Access],
    us.Last_Insert_Update_Delete_Access AS [Last_Insert_Update_Delete_Access],
    ISNULL(us.User_Seeks, 0) AS [User_Seeks],
    ISNULL(us.User_Scans, 0) AS [User_Scans],
    ISNULL(us.User_Lookups, 0) AS [User_Lookups],
    ISNULL(us.User_Updates, 0) AS [User_Updates],
    deps.Referencing_Stored_Procedures,
    deps.Referencing_Views,
    deps.Referencing_Functions,
    deps.Referencing_Triggers,
    CAST(''Size source: sys.dm_db_partition_stats. Access source: sys.dm_db_index_usage_stats; last_user_update is combined INSERT/UPDATE/DELETE and resets with DMV lifecycle.'' AS VARCHAR(1000)) AS [Metric_Context]
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
LEFT JOIN SpaceStats AS ss
    ON t.object_id = ss.object_id
LEFT JOIN UsageStats AS us
    ON t.object_id = us.object_id
OUTER APPLY
(
    SELECT MAX(v.Last_Select_Access) AS Last_Select_Access
    FROM (VALUES (us.Last_User_Seek), (us.Last_User_Scan), (us.Last_User_Lookup)) AS v(Last_Select_Access)
) AS last_select
OUTER APPLY
(
    SELECT
        Referencing_Stored_Procedures = STUFF((
            SELECT DISTINCT N''; '' + QUOTENAME(OBJECT_SCHEMA_NAME(sed.referencing_id)) + N''.'' + QUOTENAME(OBJECT_NAME(sed.referencing_id))
            FROM sys.sql_expression_dependencies AS sed
            INNER JOIN sys.objects AS ro
                ON sed.referencing_id = ro.object_id
            WHERE sed.referenced_id = t.object_id
              AND ro.type IN (N''P'', N''PC'', N''X'')
            FOR XML PATH(N''''), TYPE
        ).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N''''),
        Referencing_Views = STUFF((
            SELECT DISTINCT N''; '' + QUOTENAME(OBJECT_SCHEMA_NAME(sed.referencing_id)) + N''.'' + QUOTENAME(OBJECT_NAME(sed.referencing_id))
            FROM sys.sql_expression_dependencies AS sed
            INNER JOIN sys.objects AS ro
                ON sed.referencing_id = ro.object_id
            WHERE sed.referenced_id = t.object_id
              AND ro.type = N''V''
            FOR XML PATH(N''''), TYPE
        ).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N''''),
        Referencing_Functions = STUFF((
            SELECT DISTINCT N''; '' + QUOTENAME(OBJECT_SCHEMA_NAME(sed.referencing_id)) + N''.'' + QUOTENAME(OBJECT_NAME(sed.referencing_id))
            FROM sys.sql_expression_dependencies AS sed
            INNER JOIN sys.objects AS ro
                ON sed.referencing_id = ro.object_id
            WHERE sed.referenced_id = t.object_id
              AND ro.type IN (N''FN'', N''IF'', N''TF'', N''FS'', N''FT'', N''AF'')
            FOR XML PATH(N''''), TYPE
        ).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N''''),
        Referencing_Triggers = STUFF((
            SELECT DISTINCT N''; '' + trigger_list.Trigger_Name
            FROM
            (
                SELECT QUOTENAME(OBJECT_SCHEMA_NAME(tr.object_id)) + N''.'' + QUOTENAME(tr.name) AS Trigger_Name
                FROM sys.triggers AS tr
                WHERE tr.parent_id = t.object_id

                UNION

                SELECT QUOTENAME(OBJECT_SCHEMA_NAME(sed.referencing_id)) + N''.'' + QUOTENAME(OBJECT_NAME(sed.referencing_id)) AS Trigger_Name
                FROM sys.sql_expression_dependencies AS sed
                INNER JOIN sys.objects AS ro
                    ON sed.referencing_id = ro.object_id
                WHERE sed.referenced_id = t.object_id
                  AND ro.type = N''TR''
            ) AS trigger_list
            FOR XML PATH(N''''), TYPE
        ).value(N''.'', N''NVARCHAR(MAX)''), 1, 2, N'''')
) AS deps
WHERE (@IncludeSystemShipped = 1 OR t.is_ms_shipped = 0);';

    BEGIN TRY
        EXEC sys.sp_executesql
            @sql,
            N'@IncludeSystemShipped BIT',
            @IncludeSystemShipped = @IncludeSystemShipped;
    END TRY
    BEGIN CATCH
        INSERT INTO #TableInventory
        (
            Database_Name,
            Metric_Context
        )
        VALUES
        (
            @db_name,
            CAST('Database scan skipped: ' + ERROR_MESSAGE() AS VARCHAR(1000))
        );
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @db_name;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT
    Database_Name,
    Schema_Name,
    Table_Name,
    Row_Count,
    Reserved_MB,
    Used_MB,
    Data_MB,
    Index_MB,
    Unused_MB,
    Last_Select_Access,
    Last_Insert_Update_Delete_Access,
    User_Seeks,
    User_Scans,
    User_Lookups,
    User_Updates,
    Referencing_Stored_Procedures,
    Referencing_Views,
    Referencing_Functions,
    Referencing_Triggers,
    Metric_Context
FROM #TableInventory
ORDER BY Used_MB DESC, Row_Count DESC, Database_Name, Schema_Name, Table_Name;

DROP TABLE #TableInventory;
DROP TABLE #DbTargets;
