/*
================================================================================
Missing Index Report (Production Collector)
================================================================================
Description:
    Collects missing index recommendations from the instance DMVs across online
    user databases. Returns estimated benefit metrics and a generated CREATE
    INDEX statement for each recommendation.

    Missing index DMVs are instance-scoped; this script filters by a target
    database list built from sys.databases and processed with a WHILE loop
    (no cursors).

Output:
    Database, Schema, Table, equality/inequality/included columns, cost and
    impact metrics, user seeks/scans, improvement measure, CREATE INDEX script.

Action:
    Never create indexes blindly from this DMV. Validate overlap with existing
    indexes, write overhead, and business workload before deploying.

Parameters:
    @DatabaseList           - comma-separated names or NULL for all user DBs
    @IncludeReadOnly        - include read-only databases
    @MinImprovementMeasure  - minimum improvement score to include (default 1000)
    @TopN                   - max rows returned (NULL = all)

Note:
    Index usage stats and missing-index stats reset on instance restart.

Prerequisites: SQL Server 2016+ (STRING_SPLIT)
Criticality: Medium (read-only, metadata/DMV only)
Author:        Ravi Sharma
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-------------------------------------------------------------------------------
-- Parameters
-------------------------------------------------------------------------------
DECLARE @DatabaseList           NVARCHAR(MAX) = NULL;
DECLARE @IncludeReadOnly        BIT = 0;
DECLARE @MinImprovementMeasure  BIGINT = 1000;
DECLARE @TopN                   INT = NULL;

DECLARE @ReportStart            DATETIME2(0) = SYSDATETIME();

SELECT
    osi.sqlserver_start_time AS [Instance_Start_Time],
    N'Missing-index and usage stats are cumulative since instance start.' AS [Metric_Context]
FROM sys.dm_os_sys_info AS osi;

-------------------------------------------------------------------------------
-- Target database list (WHILE loop driver — no cursors)
-------------------------------------------------------------------------------
IF OBJECT_ID(N'tempdb..#DbWork') IS NOT NULL DROP TABLE #DbWork;
CREATE TABLE #DbWork (
    row_id          INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
    database_id     INT NOT NULL,
    database_name   SYSNAME NOT NULL
);

IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
BEGIN
    INSERT INTO #DbWork (database_id, database_name)
    SELECT d.database_id, d.name
    FROM sys.databases AS d
    INNER JOIN (
        SELECT LTRIM(RTRIM(value)) AS database_name
        FROM STRING_SPLIT(@DatabaseList, N',')
        WHERE LTRIM(RTRIM(value)) <> N''
    ) AS req ON req.database_name = d.name
    WHERE d.state = 0
      AND d.is_in_standby = 0
      AND d.database_id > 4;
END
ELSE
BEGIN
    INSERT INTO #DbWork (database_id, database_name)
    SELECT d.database_id, d.name
    FROM sys.databases AS d
    WHERE d.state = 0
      AND d.is_in_standby = 0
      AND d.database_id > 4
      AND (@IncludeReadOnly = 1 OR d.is_read_only = 0);
END;

IF OBJECT_ID(N'tempdb..#MissingIndexes') IS NOT NULL DROP TABLE #MissingIndexes;
CREATE TABLE #MissingIndexes (
    database_name           SYSNAME NOT NULL,
    schema_name             SYSNAME NULL,
    table_name              SYSNAME NULL,
    table_path              NVARCHAR(776) NOT NULL,
    equality_columns        NVARCHAR(4000) NULL,
    inequality_columns      NVARCHAR(4000) NULL,
    included_columns        NVARCHAR(4000) NULL,
    avg_user_cost           DECIMAL(18, 4) NOT NULL,
    avg_user_impact         DECIMAL(8, 2) NOT NULL,
    user_seeks              BIGINT NOT NULL,
    user_scans              BIGINT NOT NULL,
    improvement_measure     DECIMAL(18, 2) NOT NULL,
    estimated_improvements  DECIMAL(18, 2) NOT NULL,
    create_index_statement  NVARCHAR(MAX) NOT NULL,
    collection_error        NVARCHAR(4000) NULL
);

IF OBJECT_ID(N'tempdb..#CollectionErrors') IS NOT NULL DROP TABLE #CollectionErrors;
CREATE TABLE #CollectionErrors (
    database_name   SYSNAME NOT NULL,
    error_message   NVARCHAR(4000) NOT NULL,
    error_time      DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

DECLARE @RowId          INT = 1;
DECLARE @MaxRow         INT = (SELECT ISNULL(MAX(row_id), 0) FROM #DbWork);
DECLARE @DbId           INT;
DECLARE @DbName         SYSNAME;
DECLARE @InsertSql      NVARCHAR(MAX);

WHILE @RowId <= @MaxRow
BEGIN
    SELECT
        @DbId = database_id,
        @DbName = database_name
    FROM #DbWork
    WHERE row_id = @RowId;

    BEGIN TRY
        SET @InsertSql = N'
        INSERT INTO #MissingIndexes (
            database_name, schema_name, table_name, table_path,
            equality_columns, inequality_columns, included_columns,
            avg_user_cost, avg_user_impact, user_seeks, user_scans,
            improvement_measure, estimated_improvements, create_index_statement
        )
        SELECT
            @pDbName,
            CASE
                WHEN LEN(REPLACE(REPLACE(d.statement, N''['', N''''), N'']'', N''''))
                     - LEN(REPLACE(REPLACE(REPLACE(d.statement, N''['', N''''), N'']'', N''''), N''.'', N'''')) >= 2
                THEN PARSENAME(REPLACE(REPLACE(d.statement, N''['', N''''), N'']'', N''''), 2)
                ELSE N''dbo''
            END,
            PARSENAME(REPLACE(REPLACE(d.statement, N''['', N''''), N'']'', N''''), 1),
            d.statement,
            d.equality_columns,
            d.inequality_columns,
            d.included_columns,
            CAST(gs.avg_total_user_cost AS DECIMAL(18, 4)),
            CAST(gs.avg_user_impact AS DECIMAL(8, 2)),
            CAST(gs.user_seeks AS BIGINT),
            CAST(gs.user_scans AS BIGINT),
            CAST(gs.user_seeks * gs.avg_user_impact * gs.avg_total_user_cost AS DECIMAL(18, 2)),
            CAST((gs.user_seeks + gs.user_scans) * gs.avg_user_impact * gs.avg_total_user_cost AS DECIMAL(18, 2)),
            N''CREATE NONCLUSTERED INDEX [IX_'' +
                REPLACE(REPLACE(REPLACE(
                    ISNULL(PARSENAME(REPLACE(REPLACE(d.statement, N''['', N''''), N'']'', N''''), 1), N''Table''),
                    N'' '', N''_''), N''.'', N''_''), N''-'', N''_'') +
                N''_Missing_'' + CAST(g.index_group_handle AS NVARCHAR(20)) + N''] ON '' +
                d.statement + N'' ('' +
                STUFF(
                    COALESCE(N'', '' + NULLIF(d.equality_columns, N''''), N'''') +
                    COALESCE(N'', '' + NULLIF(d.inequality_columns, N''''), N''''),
                    1, 2, N'''') +
                N'')'' +
                CASE
                    WHEN d.included_columns IS NOT NULL AND LTRIM(RTRIM(d.included_columns)) <> N''''
                    THEN N'' INCLUDE ('' + d.included_columns + N'')''
                    ELSE N''''
                END + N'';'' AS create_index_statement
        FROM sys.dm_db_missing_index_group_stats AS gs
        INNER JOIN sys.dm_db_missing_index_groups AS g
            ON g.index_group_handle = gs.group_handle
        INNER JOIN sys.dm_db_missing_index_details AS d
            ON d.index_handle = g.index_handle
        WHERE d.database_id = @pDbId
          AND CAST(gs.user_seeks * gs.avg_user_impact * gs.avg_total_user_cost AS BIGINT) >= @pMinImprovement;';

        EXEC sys.sp_executesql
            @InsertSql,
            N'@pDbId INT, @pDbName SYSNAME, @pMinImprovement BIGINT',
            @pDbId = @DbId,
            @pDbName = @DbName,
            @pMinImprovement = @MinImprovementMeasure;
    END TRY
    BEGIN CATCH
        INSERT INTO #CollectionErrors (database_name, error_message)
        VALUES (@DbName, ERROR_MESSAGE());
    END CATCH;

    SET @RowId += 1;
END;

-------------------------------------------------------------------------------
-- Report
-------------------------------------------------------------------------------
PRINT REPLICATE(N'=', 80);
PRINT N'Missing Index Report';
PRINT REPLICATE(N'=', 80);

IF EXISTS (SELECT 1 FROM #CollectionErrors)
BEGIN
    PRINT N'--- Collection Errors ---';
    SELECT database_name AS [Database], error_message AS [Error], error_time AS [Error_Time]
    FROM #CollectionErrors
    ORDER BY database_name;
END;

IF @TopN IS NULL
BEGIN
    SELECT
        database_name           AS [Database],
        schema_name             AS [Schema],
        table_name              AS [Table],
        equality_columns        AS [Equality_Columns],
        inequality_columns      AS [Inequality_Columns],
        included_columns        AS [Included_Columns],
        improvement_measure     AS [Estimated_Impact],
        avg_user_cost           AS [Avg_User_Cost],
        avg_user_impact         AS [Avg_User_Impact],
        user_seeks              AS [User_Seeks],
        user_scans              AS [User_Scans],
        estimated_improvements  AS [Estimated_Improvements],
        create_index_statement  AS [Create_Index_Statement]
    FROM #MissingIndexes
    ORDER BY improvement_measure DESC, database_name, schema_name, table_name;
END
ELSE
BEGIN
    SELECT TOP (@TopN)
        database_name           AS [Database],
        schema_name             AS [Schema],
        table_name              AS [Table],
        equality_columns        AS [Equality_Columns],
        inequality_columns      AS [Inequality_Columns],
        included_columns        AS [Included_Columns],
        improvement_measure     AS [Estimated_Impact],
        avg_user_cost           AS [Avg_User_Cost],
        avg_user_impact         AS [Avg_User_Impact],
        user_seeks              AS [User_Seeks],
        user_scans              AS [User_Scans],
        estimated_improvements  AS [Estimated_Improvements],
        create_index_statement  AS [Create_Index_Statement]
    FROM #MissingIndexes
    ORDER BY improvement_measure DESC, database_name, schema_name, table_name;
END;

PRINT REPLICATE(N'=', 80);
DECLARE @RowCount INT = (SELECT COUNT(*) FROM #MissingIndexes);
PRINT N'Rows returned: ' + CAST(@RowCount AS NVARCHAR(20))
    + N' | Elapsed seconds: ' + CAST(DATEDIFF(SECOND, @ReportStart, SYSDATETIME()) AS NVARCHAR(20));
PRINT REPLICATE(N'=', 80);

DROP TABLE #DbWork;
DROP TABLE #MissingIndexes;
DROP TABLE #CollectionErrors;
