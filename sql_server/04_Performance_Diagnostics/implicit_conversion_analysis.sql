/*
================================================================================
Purpose:        Finds SQL Server queries with implicit conversions captured in
                cached execution plans and Query Store plans.
Provides:       Database name, module name/type when available, execution metrics,
                statement text, conversion expression, referenced column details,
                and Query Store identifiers.
Importance:     Implicit conversions can make predicates non-SARGable, prevent
                index seeks, increase CPU, and cause poor cardinality estimates.
Interpretation: Prioritize rows with high Total_CPU_ms, Total_Logical_Reads, or
                PlanAffectingConvert = 1. Inspect the conversion expression to find
                mismatched parameter, literal, or column types.
Action:         Align parameter/literal data types with column data types, fix join
                column mismatches, and avoid wrapping indexed columns in conversions.
Output:         Cached plan implicit-conversion findings, plus optional Query Store
                implicit-conversion findings when enabled.
Parameters:     @TopRows, @CandidatePlanCount, @IncludeQueryStore,
                @QueryStoreCandidatePlanCount, @DatabaseList.
Criticality:    High
Author:        Ravi Sharma
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @TopRows INT = 100;
DECLARE @CandidatePlanCount INT = 500; -- Inspect only top cached plans by CPU/reads to avoid long XML scans.
DECLARE @IncludeQueryStore BIT = 0; -- Set to 1 for historical evidence; can be slower on large Query Stores.
DECLARE @QueryStoreCandidatePlanCount INT = 250;
DECLARE @DatabaseList NVARCHAR(MAX) = NULL; -- e.g. N'userdb'; NULL = all online user DBs

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

IF OBJECT_ID(N'tempdb..#ModuleMap') IS NOT NULL DROP TABLE #ModuleMap;
CREATE TABLE #ModuleMap
(
    Database_Id INT NOT NULL,
    Database_Name SYSNAME NOT NULL,
    Object_Id INT NOT NULL,
    Module_Schema SYSNAME NOT NULL,
    Module_Name SYSNAME NOT NULL,
    Module_Type NVARCHAR(60) NOT NULL,
    CONSTRAINT PK_ModuleMap PRIMARY KEY (Database_Id, Object_Id)
);

DECLARE @module_db_name SYSNAME;
DECLARE @module_sql NVARCHAR(MAX);

DECLARE module_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT database_name FROM #DbTargets ORDER BY database_name;

OPEN module_cursor;
FETCH NEXT FROM module_cursor INTO @module_db_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @module_sql = N'USE ' + QUOTENAME(@module_db_name) + N';
INSERT INTO #ModuleMap
(
    Database_Id,
    Database_Name,
    Object_Id,
    Module_Schema,
    Module_Name,
    Module_Type
)
SELECT
    DB_ID(),
    DB_NAME(),
    o.object_id,
    s.name,
    o.name,
    CASE o.type
        WHEN N''P'' THEN N''Stored Procedure''
        WHEN N''PC'' THEN N''CLR Stored Procedure''
        WHEN N''X'' THEN N''Extended Stored Procedure''
        WHEN N''FN'' THEN N''Scalar Function''
        WHEN N''IF'' THEN N''Inline Table-Valued Function''
        WHEN N''TF'' THEN N''Table-Valued Function''
        WHEN N''FS'' THEN N''CLR Scalar Function''
        WHEN N''FT'' THEN N''CLR Table-Valued Function''
        WHEN N''V'' THEN N''View''
        WHEN N''TR'' THEN N''Trigger''
        ELSE o.type_desc
    END
FROM sys.objects AS o
INNER JOIN sys.schemas AS s
    ON o.schema_id = s.schema_id
WHERE o.type IN (N''P'', N''PC'', N''X'', N''FN'', N''IF'', N''TF'', N''FS'', N''FT'', N''V'', N''TR'')
  AND o.is_ms_shipped = 0;';

    BEGIN TRY
        EXEC sys.sp_executesql @module_sql;
    END TRY
    BEGIN CATCH
        PRINT 'Module map skipped for ' + QUOTENAME(@module_db_name) + ': ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM module_cursor INTO @module_db_name;
END;

CLOSE module_cursor;
DEALLOCATE module_cursor;

PRINT 'Searching cached execution plans for CONVERT_IMPLICIT...';

WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'),
CandidatePlans AS
(
    SELECT TOP (@CandidatePlanCount)
        qs.sql_handle,
        qs.plan_handle,
        qs.statement_start_offset,
        qs.statement_end_offset,
        qs.execution_count,
        qs.total_worker_time,
        qs.total_logical_reads,
        qs.total_elapsed_time,
        qs.last_execution_time
    FROM sys.dm_exec_query_stats AS qs
    ORDER BY qs.total_worker_time DESC, qs.total_logical_reads DESC
)
SELECT TOP (@TopRows)
    N'Cached Plan Implicit Conversions' AS [Result_Set],
    COALESCE(ref.Referenced_Column_Database, ctx.Plan_Context_Database, N'<unknown>') AS [Database_Name],
    ctx.Plan_Context_Database AS [Plan_Context_Database],
    qs.execution_count AS [Execution_Count],
    qs.total_worker_time / 1000 AS [Total_CPU_ms],
    (qs.total_worker_time / NULLIF(qs.execution_count, 0)) / 1000 AS [Avg_CPU_ms],
    qs.total_logical_reads AS [Total_Logical_Reads],
    qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS [Avg_Logical_Reads],
    qs.total_elapsed_time / 1000 AS [Total_Duration_ms],
    (qs.total_elapsed_time / NULLIF(qs.execution_count, 0)) / 1000 AS [Avg_Duration_ms],
    qs.last_execution_time AS [Last_Execution_Time],
    CASE
        WHEN filtered_plan.query_plan.exist('//Warnings/PlanAffectingConvert') = 1 THEN 1
        ELSE 0
    END AS [PlanAffectingConvert],
    conversion_node.n.value('@ScalarString[1]', 'NVARCHAR(4000)') AS [Conversion_Expression],
    ref.Referenced_Column_Database AS [Referenced_Column_Database],
    ref.Referenced_Column_Schema AS [Referenced_Column_Schema],
    ref.Referenced_Column_Table AS [Referenced_Column_Table],
    ref.Referenced_Column_Name AS [Referenced_Column_Name],
    CASE
        WHEN conversion_node.n.exist('(Convert/@DataType)[1]') = 1
            THEN conversion_node.n.value('(Convert/@DataType)[1]', 'NVARCHAR(128)')
        ELSE NULL
    END AS [Convert_To_Data_Type],
    CASE
        WHEN conversion_node.n.exist('(Convert/@Length)[1]') = 1
            THEN conversion_node.n.value('(Convert/@Length)[1]', 'INT')
        ELSE NULL
    END AS [Convert_To_Length],
    SUBSTRING(
        st.text,
        (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
          END - qs.statement_start_offset) / 2) + 1
    ) AS [Statement_Text],
    st.text AS [Batch_Text],
    mm.Database_Name AS [Module_Database_Name],
    mm.Module_Schema AS [Module_Schema_Name],
    mm.Module_Name AS [Module_Object_Name],
    mm.Module_Type AS [Module_Object_Type]
FROM CandidatePlans AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
CROSS APPLY
(
    SELECT qp.query_plan
    WHERE qp.query_plan IS NOT NULL
      AND qp.query_plan.exist('//ScalarOperator[contains(@ScalarString, "CONVERT_IMPLICIT")]') = 1
) AS filtered_plan
OUTER APPLY (
    SELECT CONVERT(INT, pa.value) AS database_id
    FROM sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
    WHERE pa.attribute = N'dbid'
) AS plan_db
CROSS APPLY filtered_plan.query_plan.nodes('//ScalarOperator[contains(@ScalarString, "CONVERT_IMPLICIT")]') AS conversion_node(n)
OUTER APPLY
(
    SELECT COALESCE(
        CASE WHEN st.dbid IS NOT NULL THEN DB_NAME(st.dbid) END,
        CASE WHEN plan_db.database_id IS NOT NULL THEN DB_NAME(plan_db.database_id) END
    ) AS Plan_Context_Database
) AS ctx
OUTER APPLY
(
    SELECT
        NULLIF(REPLACE(REPLACE(conversion_node.n.value('(descendant::ColumnReference[1]/@Database)[1]', 'NVARCHAR(258)'), N'[', N''), N']', N''), N'') AS Referenced_Column_Database,
        NULLIF(REPLACE(REPLACE(conversion_node.n.value('(descendant::ColumnReference[1]/@Schema)[1]', 'NVARCHAR(258)'), N'[', N''), N']', N''), N'') AS Referenced_Column_Schema,
        NULLIF(REPLACE(REPLACE(conversion_node.n.value('(descendant::ColumnReference[1]/@Table)[1]', 'NVARCHAR(258)'), N'[', N''), N']', N''), N'') AS Referenced_Column_Table,
        NULLIF(REPLACE(REPLACE(conversion_node.n.value('(descendant::ColumnReference[1]/@Column)[1]', 'NVARCHAR(258)'), N'[', N''), N']', N''), N'') AS Referenced_Column_Name
) AS ref
LEFT JOIN #ModuleMap AS mm
    ON mm.Database_Id = st.dbid
   AND mm.Object_Id = st.objectid
WHERE COALESCE(ref.Referenced_Column_Database, ctx.Plan_Context_Database, N'<unknown>') NOT IN (N'master', N'model', N'msdb', N'tempdb', N'mssqlsystemresource')
ORDER BY qs.total_worker_time DESC, qs.total_logical_reads DESC;

IF @IncludeQueryStore = 1
BEGIN
    PRINT 'Searching Query Store plans for CONVERT_IMPLICIT...';

    IF OBJECT_ID(N'tempdb..#QueryStoreImplicitConversions') IS NOT NULL DROP TABLE #QueryStoreImplicitConversions;
    CREATE TABLE #QueryStoreImplicitConversions
    (
        Database_Name SYSNAME NULL,
        Query_Id BIGINT NULL,
        Plan_Id BIGINT NULL,
        Execution_Count BIGINT NULL,
        Total_CPU_ms DECIMAL(19,2) NULL,
        Avg_CPU_ms DECIMAL(19,2) NULL,
        Total_Logical_Reads BIGINT NULL,
        Avg_Logical_Reads DECIMAL(19,2) NULL,
        Last_Execution_Time DATETIMEOFFSET NULL,
        PlanAffectingConvert BIT NULL,
        Conversion_Expression NVARCHAR(4000) NULL,
        Referenced_Column_Database NVARCHAR(258) NULL,
        Referenced_Column_Schema NVARCHAR(258) NULL,
        Referenced_Column_Table NVARCHAR(258) NULL,
        Referenced_Column_Name NVARCHAR(258) NULL,
        Convert_To_Data_Type NVARCHAR(128) NULL,
        Convert_To_Length INT NULL,
        Query_Text NVARCHAR(MAX) NULL,
        Module_Database_Name SYSNAME NULL,
        Module_Schema_Name SYSNAME NULL,
        Module_Object_Name SYSNAME NULL,
        Module_Object_Type NVARCHAR(60) NULL
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
IF OBJECT_ID(N''sys.query_store_plan'') IS NOT NULL
   AND EXISTS (SELECT 1 FROM sys.database_query_store_options WHERE actual_state_desc <> N''OFF'')
BEGIN
    WITH XMLNAMESPACES (DEFAULT ''http://schemas.microsoft.com/sqlserver/2004/07/showplan''),
    RuntimeStats AS
    (
        SELECT
            qrs.plan_id,
            SUM(CONVERT(BIGINT, qrs.count_executions)) AS Execution_Count,
            CAST(SUM(qrs.avg_cpu_time * qrs.count_executions) / 1000.0 AS DECIMAL(19,2)) AS Total_CPU_ms,
            CAST(SUM(qrs.avg_cpu_time * qrs.count_executions) / NULLIF(SUM(qrs.count_executions), 0) / 1000.0 AS DECIMAL(19,2)) AS Avg_CPU_ms,
            SUM(CONVERT(BIGINT, qrs.avg_logical_io_reads * qrs.count_executions)) AS Total_Logical_Reads,
            CAST(SUM(qrs.avg_logical_io_reads * qrs.count_executions) / NULLIF(SUM(qrs.count_executions), 0) AS DECIMAL(19,2)) AS Avg_Logical_Reads,
            MAX(qrs.last_execution_time) AS Last_Execution_Time
        FROM sys.query_store_runtime_stats AS qrs
        GROUP BY qrs.plan_id
    ),
    CandidatePlans AS
    (
        SELECT TOP (@QueryStoreCandidatePlanCount)
            qsq.query_id,
            qsq.object_id,
            qsp.plan_id,
            qsp.query_plan,
            qst.query_sql_text,
            rs.Execution_Count,
            rs.Total_CPU_ms,
            rs.Avg_CPU_ms,
            rs.Total_Logical_Reads,
            rs.Avg_Logical_Reads,
            rs.Last_Execution_Time
        FROM sys.query_store_plan AS qsp
        INNER JOIN RuntimeStats AS rs
            ON qsp.plan_id = rs.plan_id
        INNER JOIN sys.query_store_query AS qsq
            ON qsp.query_id = qsq.query_id
        INNER JOIN sys.query_store_query_text AS qst
            ON qsq.query_text_id = qst.query_text_id
        ORDER BY rs.Total_CPU_ms DESC, rs.Total_Logical_Reads DESC
    )
    INSERT INTO #QueryStoreImplicitConversions
    SELECT TOP (@TopRows)
        DB_NAME() AS [Database_Name],
        cp.query_id AS [Query_Id],
        cp.plan_id AS [Plan_Id],
        cp.Execution_Count,
        cp.Total_CPU_ms,
        cp.Avg_CPU_ms,
        cp.Total_Logical_Reads,
        cp.Avg_Logical_Reads,
        cp.Last_Execution_Time,
        CASE WHEN filtered_qs_xml.query_plan_xml.exist(''//Warnings/PlanAffectingConvert'') = 1 THEN 1 ELSE 0 END AS [PlanAffectingConvert],
        conversion_node.n.value(''@ScalarString[1]'', ''NVARCHAR(4000)'') AS [Conversion_Expression],
        NULLIF(REPLACE(REPLACE(conversion_node.n.value(''(descendant::ColumnReference[1]/@Database)[1]'', ''NVARCHAR(258)''), N''['', N''''), N'']'', N''''), N'''') AS [Referenced_Column_Database],
        NULLIF(REPLACE(REPLACE(conversion_node.n.value(''(descendant::ColumnReference[1]/@Schema)[1]'', ''NVARCHAR(258)''), N''['', N''''), N'']'', N''''), N'''') AS [Referenced_Column_Schema],
        NULLIF(REPLACE(REPLACE(conversion_node.n.value(''(descendant::ColumnReference[1]/@Table)[1]'', ''NVARCHAR(258)''), N''['', N''''), N'']'', N''''), N'''') AS [Referenced_Column_Table],
        NULLIF(REPLACE(REPLACE(conversion_node.n.value(''(descendant::ColumnReference[1]/@Column)[1]'', ''NVARCHAR(258)''), N''['', N''''), N'']'', N''''), N'''') AS [Referenced_Column_Name],
        CASE
            WHEN conversion_node.n.exist(''(Convert/@DataType)[1]'') = 1
                THEN conversion_node.n.value(''(Convert/@DataType)[1]'', ''NVARCHAR(128)'')
            ELSE NULL
        END AS [Convert_To_Data_Type],
        CASE
            WHEN conversion_node.n.exist(''(Convert/@Length)[1]'') = 1
                THEN conversion_node.n.value(''(Convert/@Length)[1]'', ''INT'')
            ELSE NULL
        END AS [Convert_To_Length],
        cp.query_sql_text AS [Query_Text],
        DB_NAME() AS [Module_Database_Name],
        OBJECT_SCHEMA_NAME(cp.object_id) AS [Module_Schema_Name],
        OBJECT_NAME(cp.object_id) AS [Module_Object_Name],
        CASE o.type
            WHEN N''P'' THEN N''Stored Procedure''
            WHEN N''PC'' THEN N''CLR Stored Procedure''
            WHEN N''X'' THEN N''Extended Stored Procedure''
            WHEN N''FN'' THEN N''Scalar Function''
            WHEN N''IF'' THEN N''Inline Table-Valued Function''
            WHEN N''TF'' THEN N''Table-Valued Function''
            WHEN N''FS'' THEN N''CLR Scalar Function''
            WHEN N''FT'' THEN N''CLR Table-Valued Function''
            WHEN N''V'' THEN N''View''
            WHEN N''TR'' THEN N''Trigger''
            ELSE o.type_desc
        END AS [Module_Object_Type]
    FROM CandidatePlans AS cp
    LEFT JOIN sys.objects AS o
        ON cp.object_id = o.object_id
    CROSS APPLY (SELECT TRY_CONVERT(XML, cp.query_plan) AS query_plan_xml) AS qs_xml
    CROSS APPLY
    (
        SELECT qs_xml.query_plan_xml
        WHERE qs_xml.query_plan_xml IS NOT NULL
          AND qs_xml.query_plan_xml.exist(''//ScalarOperator[contains(@ScalarString, "CONVERT_IMPLICIT")]'') = 1
    ) AS filtered_qs_xml
    CROSS APPLY filtered_qs_xml.query_plan_xml.nodes(''//ScalarOperator[contains(@ScalarString, "CONVERT_IMPLICIT")]'') AS conversion_node(n)
    ORDER BY cp.Total_CPU_ms DESC, cp.Total_Logical_Reads DESC;
END;';

        BEGIN TRY
            EXEC sys.sp_executesql
                @sql,
                N'@TopRows INT, @QueryStoreCandidatePlanCount INT',
                @TopRows = @TopRows,
                @QueryStoreCandidatePlanCount = @QueryStoreCandidatePlanCount;
        END TRY
        BEGIN CATCH
            PRINT 'Query Store scan skipped for ' + QUOTENAME(@db_name) + ': ' + ERROR_MESSAGE();
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @db_name;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    SELECT
        N'Query Store Implicit Conversions' AS [Result_Set],
        [Database_Name],
        [Query_Id],
        [Plan_Id],
        [Execution_Count],
        [Total_CPU_ms],
        [Avg_CPU_ms],
        [Total_Logical_Reads],
        [Avg_Logical_Reads],
        [Last_Execution_Time],
        [PlanAffectingConvert],
        [Conversion_Expression],
        [Referenced_Column_Database],
        [Referenced_Column_Schema],
        [Referenced_Column_Table],
        [Referenced_Column_Name],
        [Convert_To_Data_Type],
        [Convert_To_Length],
        [Query_Text],
        [Module_Database_Name],
        [Module_Schema_Name],
        [Module_Object_Name],
        [Module_Object_Type]
    FROM #QueryStoreImplicitConversions
    ORDER BY Total_CPU_ms DESC, Total_Logical_Reads DESC, Database_Name, Query_Id, Plan_Id;

    DROP TABLE #QueryStoreImplicitConversions;
END;

IF OBJECT_ID(N'tempdb..#ModuleMap') IS NOT NULL DROP TABLE #ModuleMap;
IF OBJECT_ID(N'tempdb..#DbTargets') IS NOT NULL DROP TABLE #DbTargets;
