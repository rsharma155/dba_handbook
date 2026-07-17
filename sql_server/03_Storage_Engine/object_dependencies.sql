/*
================================================================================
Purpose:        Lists dependency details for one or more objects (tables, views,
                TVFs, functions, procedures): who references them and, for tables,
                FKs / indexes / triggers / constraints.
Provides:       Target object identity, direction, dependency type, referencing
                object names/types, match source, and when filtering by column:
                Usage_Type (SELECT_ONLY / FILTER / JOIN) plus Usage_Snippet.
Importance:     Use before DROP, RENAME, ALTER COLUMN, archive, or refactor work.
Interpretation: Module column usage uses sql_modules + referencing/referenced DMVs
                + sql_expression_dependencies. Clause classification is heuristic.
Action:         Set @ObjectList (comma-separated schema.object names) and optional
                @ColumnName / @DatabaseName. Run in the target database context.
                Incoming referencers scanned: views, procs, TVFs/functions,
                triggers, plus tables/check/defaults that bind via expression deps.
Criticality:    Medium
Author:         Ravi Sharma
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

/*------------------------------------------------------------------------------
  Parameters — edit these before execution

  IMPORTANT: Run this in the database that owns the objects (SSMS database
  dropdown, or USE [YourDatabase];). Catalog views are database-scoped;
  running in [master] will not find user objects.

  @DatabaseName   Optional guard. If set, script aborts unless DB_NAME() matches.
                  Example: N'YourAppDb'. NULL = accept whatever DB you are in.
  @ObjectList     One or many objects, comma-separated.
                  Forms: schema.object  |  object (uses @DefaultSchema)
                  Examples:
                    N'dbo.Orders'
                    N'dbo.Orders, dbo.vOrders, dbo.tvf_GetOrderLines'
                    N'Orders, vOrders'   -- both under @DefaultSchema
  @DefaultSchema  Used when an entry has no schema prefix.
  @ColumnName     Optional. Applied per target that has the column; targets
                  without the column are analyzed without column filtering.
------------------------------------------------------------------------------*/
DECLARE @DatabaseName  SYSNAME       = NULL;                 -- e.g. N'YourAppDb'; NULL = current DB
DECLARE @ObjectList    NVARCHAR(MAX) = N'dbo.YourTableName';  -- CHANGE THIS to real object(s)
DECLARE @DefaultSchema SYSNAME       = N'dbo';
DECLARE @ColumnName    SYSNAME       = NULL;                 -- e.g. N'OrderId'; NULL = all

DECLARE @CurrentDatabase SYSNAME = DB_NAME();
DECLARE @WantColumnFilter BIT = CASE
    WHEN @ColumnName IS NULL OR LTRIM(RTRIM(@ColumnName)) = N'' THEN 0
    ELSE 1
END;
DECLARE @ColumnNameClean SYSNAME = NULL;

/* Referencing object types that can depend on the target (Incoming).
   Modules with sql_modules text: V,P,PC,FN,IF,TF,FS,FT,AF,TR
   Catalog-only expression binds also: U (computed cols), C/D (check/default calling UDFs) */
DECLARE @RefModuleTypes TABLE (type CHAR(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
INSERT INTO @RefModuleTypes (type) VALUES
    (N'V'), (N'P'), (N'PC'), (N'X'),
    (N'FN'), (N'IF'), (N'TF'), (N'FS'), (N'FT'), (N'AF'),
    (N'TR');

DECLARE @RefCatalogTypes TABLE (type CHAR(2) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
INSERT INTO @RefCatalogTypes (type) VALUES
    (N'V'), (N'P'), (N'PC'), (N'X'),
    (N'FN'), (N'IF'), (N'TF'), (N'FS'), (N'FT'), (N'AF'),
    (N'TR'),
    (N'U'), (N'C'), (N'D');

IF @DatabaseName IS NOT NULL AND LTRIM(RTRIM(@DatabaseName)) <> N''
BEGIN
    IF @CurrentDatabase <> @DatabaseName
    BEGIN
        RAISERROR(
            N'Wrong database context: connected to [%s], but @DatabaseName is [%s]. Select [%s] in SSMS (or run USE %s;) then re-execute this script.',
            16, 1, @CurrentDatabase, @DatabaseName, @DatabaseName, @DatabaseName);
        RETURN;
    END;
END;

IF @CurrentDatabase IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    PRINT N'WARNING: You are connected to system database [' + @CurrentDatabase
        + N']. User tables/views are usually in a user database. '
        + N'Set the SSMS database dropdown (or USE [YourDatabase];) before running.';
END;

IF @WantColumnFilter = 1
    SET @ColumnNameClean = REPLACE(REPLACE(LTRIM(RTRIM(@ColumnName)), N'[', N''), N']', N'');

IF @ObjectList IS NULL OR LTRIM(RTRIM(@ObjectList)) = N''
BEGIN
    RAISERROR(N'@ObjectList is required. Provide one or more objects, e.g. N''dbo.Orders'' or N''dbo.Orders, dbo.vOrders''.', 16, 1);
    RETURN;
END;

IF @ObjectList = N'dbo.YourTableName'
BEGIN
    RAISERROR(
        N'@ObjectList is still the placeholder dbo.YourTableName. Set it to your real object name(s), and run in the correct user database (currently [%s]).',
        16, 1, @CurrentDatabase);
    RETURN;
END;

/*------------------------------------------------------------------------------
  Parse @ObjectList into #Targets (tables, views, TVFs, functions, procedures)
------------------------------------------------------------------------------*/
IF OBJECT_ID(N'tempdb..#Targets') IS NOT NULL DROP TABLE #Targets;
CREATE TABLE #Targets
(
    Target_Id           INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    Input_Token         NVARCHAR(512) COLLATE DATABASE_DEFAULT NOT NULL,
    Schema_Name         SYSNAME COLLATE DATABASE_DEFAULT NULL,
    Object_Name         SYSNAME COLLATE DATABASE_DEFAULT NULL,
    Object_Id           INT NULL,
    Object_Type         CHAR(2) COLLATE DATABASE_DEFAULT NULL,
    Object_Type_Desc    NVARCHAR(60) COLLATE DATABASE_DEFAULT NULL,
    Two_Part_Name       NVARCHAR(517) COLLATE DATABASE_DEFAULT NULL,
    Filter_By_Column    BIT NOT NULL DEFAULT (0),
    Column_Id           INT NULL,
    Column_Name_Actual  SYSNAME COLLATE DATABASE_DEFAULT NULL,
    Resolve_Status      NVARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
    Create_Date         DATETIME NULL,
    Modify_Date         DATETIME NULL,
    Is_Ms_Shipped       BIT NULL
);

IF OBJECT_ID(N'tempdb..#RawTokens') IS NOT NULL DROP TABLE #RawTokens;
CREATE TABLE #RawTokens
(
    Token NVARCHAR(512) COLLATE DATABASE_DEFAULT NOT NULL
);

INSERT INTO #RawTokens (Token)
SELECT LTRIM(RTRIM(value))
FROM STRING_SPLIT(@ObjectList, N',')
WHERE LTRIM(RTRIM(value)) <> N'';

DECLARE @Tok NVARCHAR(512);
DECLARE @TokClean NVARCHAR(512);
DECLARE @DotPos INT;
DECLARE @Sch SYSNAME;
DECLARE @Obj SYSNAME;
DECLARE @Oid INT;
DECLARE @OType CHAR(2);
DECLARE @OTypeDesc NVARCHAR(60);
DECLARE @TwoPart NVARCHAR(517);
DECLARE @ColId INT;
DECLARE @FilterThis BIT;
DECLARE @Msg NVARCHAR(400);

DECLARE token_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT Token FROM #RawTokens;

OPEN token_cursor;
FETCH NEXT FROM token_cursor INTO @Tok;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @TokClean = REPLACE(REPLACE(LTRIM(RTRIM(@Tok)), N'[', N''), N']', N'');
    SET @DotPos = CHARINDEX(N'.', @TokClean);

    IF @DotPos > 0
    BEGIN
        SET @Sch = LEFT(@TokClean, @DotPos - 1);
        SET @Obj = SUBSTRING(@TokClean, @DotPos + 1, 512);
    END;
    ELSE
    BEGIN
        SET @Sch = @DefaultSchema;
        SET @Obj = @TokClean;
    END;

    SET @Sch = NULLIF(LTRIM(RTRIM(@Sch)), N'');
    SET @Obj = NULLIF(LTRIM(RTRIM(@Obj)), N'');
    SET @Oid = NULL;
    SET @OType = NULL;
    SET @OTypeDesc = NULL;
    SET @TwoPart = NULL;
    SET @ColId = NULL;
    SET @FilterThis = 0;

    IF @Sch IS NULL OR @Obj IS NULL
    BEGIN
        INSERT INTO #Targets (Input_Token, Resolve_Status)
        VALUES (@Tok, N'Invalid token (need schema.object or object name)');
    END;
    ELSE
    BEGIN
        SET @TwoPart = QUOTENAME(@Sch) + N'.' + QUOTENAME(@Obj);

        SELECT
            @Oid = o.object_id,
            @OType = o.type COLLATE DATABASE_DEFAULT,
            @OTypeDesc = o.type_desc COLLATE DATABASE_DEFAULT
        FROM sys.objects AS o
        INNER JOIN sys.schemas AS s
            ON o.schema_id = s.schema_id
        WHERE s.name = @Sch COLLATE DATABASE_DEFAULT
          AND o.name = @Obj COLLATE DATABASE_DEFAULT
          AND o.type COLLATE DATABASE_DEFAULT IN (N'U', N'V', N'IF', N'TF', N'FN', N'FS', N'FT', N'P', N'PC', N'AF');

        IF @Oid IS NULL
        BEGIN
            /* Distinguish: missing entirely vs unsupported type */
            SELECT
                @Oid = o.object_id,
                @OType = o.type COLLATE DATABASE_DEFAULT,
                @OTypeDesc = o.type_desc COLLATE DATABASE_DEFAULT
            FROM sys.objects AS o
            INNER JOIN sys.schemas AS s
                ON o.schema_id = s.schema_id
            WHERE s.name = @Sch COLLATE DATABASE_DEFAULT
              AND o.name = @Obj COLLATE DATABASE_DEFAULT;

            IF @Oid IS NOT NULL
            BEGIN
                SET @Msg = N'Found in [' + @CurrentDatabase + N'] but type ['
                    + RTRIM(@OType) + N' / ' + ISNULL(@OTypeDesc, N'?')
                    + N'] is not supported (allowed: U,V,IF,TF,FN,FS,FT,P,PC,AF)';
                SET @Oid = NULL;
            END;
            ELSE
            BEGIN
                SET @Msg = N'Not found in database [' + @CurrentDatabase
                    + N']. If the object lives elsewhere, USE that database (or set SSMS dropdown) and retry.';
            END;

            INSERT INTO #Targets
            (
                Input_Token, Schema_Name, Object_Name, Two_Part_Name, Resolve_Status
            )
            VALUES
            (
                @Tok, @Sch, @Obj, @TwoPart, @Msg
            );
        END;
        ELSE
        BEGIN
            IF @WantColumnFilter = 1
            BEGIN
                SELECT @ColId = c.column_id,
                       @ColumnNameClean = c.name
                FROM sys.columns AS c
                WHERE c.object_id = @Oid
                  AND c.name = @ColumnNameClean;

                IF @ColId IS NOT NULL
                    SET @FilterThis = 1;
            END;

            INSERT INTO #Targets
            (
                Input_Token, Schema_Name, Object_Name, Object_Id, Object_Type, Object_Type_Desc,
                Two_Part_Name, Filter_By_Column, Column_Id, Column_Name_Actual, Resolve_Status,
                Create_Date, Modify_Date, Is_Ms_Shipped
            )
            SELECT
                @Tok,
                @Sch,
                @Obj,
                @Oid,
                @OType,
                @OTypeDesc,
                @TwoPart,
                @FilterThis,
                @ColId,
                CASE WHEN @FilterThis = 1 THEN @ColumnNameClean ELSE NULL END,
                CASE
                    WHEN @WantColumnFilter = 1 AND @FilterThis = 0
                        THEN N'Resolved; column filter skipped (column not on this object)'
                    ELSE N'Resolved'
                END,
                o.create_date,
                o.modify_date,
                o.is_ms_shipped
            FROM sys.objects AS o
            WHERE o.object_id = @Oid;
        END;
    END;

    FETCH NEXT FROM token_cursor INTO @Tok;
END;

CLOSE token_cursor;
DEALLOCATE token_cursor;

DROP TABLE #RawTokens;

IF NOT EXISTS (SELECT 1 FROM #Targets WHERE Object_Id IS NOT NULL)
BEGIN
    SELECT
        @CurrentDatabase AS [Connected_Database],
        Input_Token,
        Schema_Name,
        Object_Name,
        Resolve_Status
    FROM #Targets;

    RAISERROR(
        N'No resolvable objects in @ObjectList for database [%s]. You are likely in the wrong database (e.g. master) or the names are incorrect. USE [YourUserDatabase]; set @ObjectList to real names; optionally set @DatabaseName as a guard.',
        16, 1, @CurrentDatabase);
    DROP TABLE #Targets;
    RETURN;
END;

/*------------------------------------------------------------------------------
  Working tables
------------------------------------------------------------------------------*/
IF OBJECT_ID(N'tempdb..#Deps') IS NOT NULL DROP TABLE #Deps;
CREATE TABLE #Deps
(
    Target_Schema        SYSNAME       COLLATE DATABASE_DEFAULT NULL,
    Target_Name          SYSNAME       COLLATE DATABASE_DEFAULT NULL,
    Target_Type          CHAR(2)       COLLATE DATABASE_DEFAULT NULL,
    Target_Type_Desc     NVARCHAR(60)  COLLATE DATABASE_DEFAULT NULL,
    Target_Object_Id     INT NULL,
    Direction            NVARCHAR(20)  COLLATE DATABASE_DEFAULT NOT NULL,
    Dependency_Type      NVARCHAR(40)  COLLATE DATABASE_DEFAULT NOT NULL,
    Object_Schema        SYSNAME       COLLATE DATABASE_DEFAULT NULL,
    Object_Name          SYSNAME       COLLATE DATABASE_DEFAULT NULL,
    Object_Type          NVARCHAR(10)  COLLATE DATABASE_DEFAULT NULL,
    Object_Type_Desc     NVARCHAR(60)  COLLATE DATABASE_DEFAULT NULL,
    Related_Schema       SYSNAME       COLLATE DATABASE_DEFAULT NULL,
    Related_Name         SYSNAME       COLLATE DATABASE_DEFAULT NULL,
    Detail               NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    Usage_Type           NVARCHAR(20)  COLLATE DATABASE_DEFAULT NULL,
    Usage_Snippet        NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    Is_Caller_Dependent  BIT NULL,
    Is_Ambiguous         BIT NULL,
    Sort_Group           INT NOT NULL,
    Match_Source         NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL
);

IF OBJECT_ID(N'tempdb..#ModuleHits') IS NOT NULL DROP TABLE #ModuleHits;
CREATE TABLE #ModuleHits
(
    Object_Id        INT NOT NULL PRIMARY KEY,
    Object_Schema    SYSNAME COLLATE DATABASE_DEFAULT NULL,
    Object_Name      SYSNAME COLLATE DATABASE_DEFAULT NULL,
    Object_Type      CHAR(2) COLLATE DATABASE_DEFAULT NULL,
    Object_Type_Desc NVARCHAR(60) COLLATE DATABASE_DEFAULT NULL,
    Match_Source     NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
    Detail           NVARCHAR(400) COLLATE DATABASE_DEFAULT NULL
);

IF OBJECT_ID(N'tempdb..#Referencing') IS NOT NULL DROP TABLE #Referencing;
CREATE TABLE #Referencing
(
    Object_Id        INT NOT NULL PRIMARY KEY,
    Object_Schema    SYSNAME COLLATE DATABASE_DEFAULT NULL,
    Object_Name      SYSNAME COLLATE DATABASE_DEFAULT NULL,
    Object_Type      CHAR(2) COLLATE DATABASE_DEFAULT NULL,
    Object_Type_Desc NVARCHAR(60) COLLATE DATABASE_DEFAULT NULL,
    Processed        BIT NOT NULL DEFAULT (0)
);

IF OBJECT_ID(N'tempdb..#ModuleUsages') IS NOT NULL DROP TABLE #ModuleUsages;
CREATE TABLE #ModuleUsages
(
    Object_Id     INT NOT NULL,
    Usage_Type    NVARCHAR(20)  COLLATE DATABASE_DEFAULT NOT NULL,
    Usage_Snippet NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL,
    Line_No       INT NOT NULL
);

IF OBJECT_ID(N'tempdb..#ModuleWork') IS NOT NULL DROP TABLE #ModuleWork;
CREATE TABLE #ModuleWork
(
    Object_Id        INT NOT NULL PRIMARY KEY,
    Object_Schema    SYSNAME COLLATE DATABASE_DEFAULT NULL,
    Object_Name      SYSNAME COLLATE DATABASE_DEFAULT NULL,
    Object_Type      CHAR(2) COLLATE DATABASE_DEFAULT NULL,
    Object_Type_Desc NVARCHAR(60) COLLATE DATABASE_DEFAULT NULL,
    Match_Source     NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
    Processed        BIT NOT NULL DEFAULT (0)
);

/* Loop variables (declared once for the batch) */
DECLARE @ObjectId INT;
DECLARE @SchemaName SYSNAME;
DECLARE @ObjectName SYSNAME;
DECLARE @ObjectType CHAR(2);
DECLARE @ObjectTypeDesc NVARCHAR(60);
DECLARE @TwoPartName NVARCHAR(517);
DECLARE @FilterByColumn BIT;
DECLARE @ColumnId INT;
DECLARE @ColActual SYSNAME;

DECLARE @RefId INT;
DECLARE @RefSchema SYSNAME;
DECLARE @RefName SYSNAME;
DECLARE @RefType CHAR(2);
DECLARE @RefTypeDesc NVARCHAR(60);
DECLARE @RefTwoPart NVARCHAR(517);

DECLARE @ModId INT;
DECLARE @ModSchema SYSNAME;
DECLARE @ModName SYSNAME;
DECLARE @ModType CHAR(2);
DECLARE @ModTypeDesc NVARCHAR(60);
DECLARE @ModSource NVARCHAR(100);
DECLARE @Def NVARCHAR(MAX);
DECLARE @Remaining NVARCHAR(MAX);
DECLARE @Line NVARCHAR(MAX);
DECLARE @LineDetect NVARCHAR(MAX);
DECLARE @Padded NVARCHAR(MAX);
DECLARE @Ctx NVARCHAR(20);
DECLARE @PrevCtx NVARCHAR(20);
DECLARE @LineNo INT;
DECLARE @NlPos INT;
DECLARE @HasCol BIT;
DECLARE @MappedUsage NVARCHAR(20);
DECLARE @HasSelect BIT;
DECLARE @HasFilter BIT;
DECLARE @HasJoin BIT;

/*------------------------------------------------------------------------------
  1) Target summary
------------------------------------------------------------------------------*/
SELECT
    DB_NAME() AS [Database_Name],
    Target_Id,
    Input_Token,
    Schema_Name,
    Object_Name,
    Object_Id,
    Object_Type,
    Object_Type_Desc,
    CASE WHEN Filter_By_Column = 1 THEN Column_Name_Actual ELSE NULL END AS [Filter_Column],
    Column_Id AS [Filter_Column_Id],
    Resolve_Status,
    Create_Date,
    Modify_Date,
    Is_Ms_Shipped
FROM #Targets
ORDER BY Target_Id;

/*------------------------------------------------------------------------------
  2) Process each resolved target
------------------------------------------------------------------------------*/
DECLARE target_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT
        Object_Id,
        Schema_Name,
        Object_Name,
        Object_Type,
        Object_Type_Desc,
        Two_Part_Name,
        Filter_By_Column,
        Column_Id,
        Column_Name_Actual
    FROM #Targets
    WHERE Object_Id IS NOT NULL
    ORDER BY Target_Id;

OPEN target_cursor;
FETCH NEXT FROM target_cursor INTO
    @ObjectId, @SchemaName, @ObjectName, @ObjectType, @ObjectTypeDesc,
    @TwoPartName, @FilterByColumn, @ColumnId, @ColActual;

WHILE @@FETCH_STATUS = 0
BEGIN
    TRUNCATE TABLE #ModuleHits;
    TRUNCATE TABLE #Referencing;
    TRUNCATE TABLE #ModuleUsages;
    TRUNCATE TABLE #ModuleWork;

    /*--------------------------------------------------------------------
      2a) Incoming module dependencies (views / procs / functions)
    --------------------------------------------------------------------*/
    IF @FilterByColumn = 0
    BEGIN
        INSERT INTO #Deps
        (
            Target_Schema, Target_Name, Target_Type, Target_Type_Desc, Target_Object_Id,
            Direction, Dependency_Type, Object_Schema, Object_Name, Object_Type, Object_Type_Desc,
            Related_Schema, Related_Name, Detail, Is_Caller_Dependent, Is_Ambiguous, Sort_Group, Match_Source
        )
        SELECT DISTINCT
            @SchemaName,
            @ObjectName,
            @ObjectType,
            @ObjectTypeDesc,
            @ObjectId,
            N'Incoming',
            CASE o.type COLLATE DATABASE_DEFAULT
                WHEN N'V'  THEN N'View'
                WHEN N'P'  THEN N'StoredProcedure'
                WHEN N'PC' THEN N'StoredProcedure'
                WHEN N'X'  THEN N'StoredProcedure'
                WHEN N'FN' THEN N'Function'
                WHEN N'IF' THEN N'Function'
                WHEN N'TF' THEN N'Function'
                WHEN N'FS' THEN N'Function'
                WHEN N'FT' THEN N'Function'
                WHEN N'AF' THEN N'Function'
                WHEN N'TR' THEN N'Trigger'
                WHEN N'U'  THEN N'Table'
                WHEN N'C'  THEN N'CheckConstraint'
                WHEN N'D'  THEN N'DefaultConstraint'
                ELSE N'Expression'
            END,
            OBJECT_SCHEMA_NAME(sed.referencing_id),
            OBJECT_NAME(sed.referencing_id),
            o.type COLLATE DATABASE_DEFAULT,
            o.type_desc COLLATE DATABASE_DEFAULT,
            NULL,
            NULL,
            CASE
                WHEN sed.referenced_minor_id > 0
                    THEN (N'Column: ' COLLATE DATABASE_DEFAULT)
                         + (COL_NAME(@ObjectId, sed.referenced_minor_id) COLLATE DATABASE_DEFAULT)
                ELSE N'References target object' COLLATE DATABASE_DEFAULT
            END,
            sed.is_caller_dependent,
            sed.is_ambiguous,
            10,
            N'sys.sql_expression_dependencies'
        FROM sys.sql_expression_dependencies AS sed
        INNER JOIN sys.objects AS o
            ON sed.referencing_id = o.object_id
        WHERE sed.referenced_id = @ObjectId
          AND o.type COLLATE DATABASE_DEFAULT IN (SELECT type FROM @RefCatalogTypes)
          AND sed.referencing_id <> @ObjectId;
    END;
    ELSE
    BEGIN
        INSERT INTO #Referencing (Object_Id, Object_Schema, Object_Name, Object_Type, Object_Type_Desc)
        SELECT DISTINCT
            o.object_id,
            OBJECT_SCHEMA_NAME(o.object_id),
            o.name,
            o.type COLLATE DATABASE_DEFAULT,
            o.type_desc COLLATE DATABASE_DEFAULT
        FROM sys.sql_expression_dependencies AS sed
        INNER JOIN sys.objects AS o
            ON sed.referencing_id = o.object_id
        WHERE sed.referenced_id = @ObjectId
          AND o.type COLLATE DATABASE_DEFAULT IN (SELECT type FROM @RefCatalogTypes)
          AND sed.referencing_id <> @ObjectId;

        BEGIN TRY
            INSERT INTO #Referencing (Object_Id, Object_Schema, Object_Name, Object_Type, Object_Type_Desc)
            SELECT DISTINCT
                o.object_id,
                re.referencing_schema_name,
                re.referencing_entity_name,
                o.type COLLATE DATABASE_DEFAULT,
                o.type_desc COLLATE DATABASE_DEFAULT
            FROM sys.dm_sql_referencing_entities(@TwoPartName, N'OBJECT') AS re
            INNER JOIN sys.objects AS o
                ON o.object_id = re.referencing_id
            WHERE o.type COLLATE DATABASE_DEFAULT IN (SELECT type FROM @RefCatalogTypes)
              AND o.object_id <> @ObjectId
              AND NOT EXISTS (SELECT 1 FROM #Referencing AS x WHERE x.Object_Id = o.object_id);
        END TRY
        BEGIN CATCH
            SET @Msg = ERROR_MESSAGE();
            PRINT N'Warning: sys.dm_sql_referencing_entities skipped for '
                + @TwoPartName + N': ' + @Msg;
        END CATCH;

        /* Text search in modules that can contain T-SQL (views/procs/functions/triggers) */
        INSERT INTO #ModuleHits
        (
            Object_Id, Object_Schema, Object_Name, Object_Type, Object_Type_Desc, Match_Source, Detail
        )
        SELECT
            o.object_id,
            OBJECT_SCHEMA_NAME(o.object_id),
            o.name,
            o.type COLLATE DATABASE_DEFAULT,
            o.type_desc COLLATE DATABASE_DEFAULT,
            N'sys.sql_modules',
            N'Column found in module definition'
        FROM sys.sql_modules AS m
        INNER JOIN sys.objects AS o
            ON m.object_id = o.object_id
        WHERE o.is_ms_shipped = 0
          AND o.type COLLATE DATABASE_DEFAULT IN (SELECT type FROM @RefModuleTypes)
          AND o.object_id <> @ObjectId
          AND m.definition IS NOT NULL
          AND (
                   m.definition LIKE N'%[[]' + @ColActual + N']%'
                OR m.definition LIKE N'%.' + @ColActual + N'[^A-Za-z0-9_]%'
                OR m.definition LIKE N'%[^A-Za-z0-9_]' + @ColActual + N'[^A-Za-z0-9_]%'
                OR m.definition LIKE @ColActual + N'[^A-Za-z0-9_]%'
                OR m.definition LIKE N'%[^A-Za-z0-9_]' + @ColActual
                OR m.definition = @ColActual
              )
          AND (
                EXISTS (SELECT 1 FROM #Referencing AS r WHERE r.Object_Id = o.object_id)
                OR m.definition LIKE N'%[[]' + @ObjectName + N']%'
                OR m.definition LIKE N'%[^A-Za-z0-9_]' + @ObjectName + N'[^A-Za-z0-9_]%'
                OR m.definition LIKE N'%.' + @ObjectName + N'[^A-Za-z0-9_]%'
                OR m.definition LIKE @ObjectName + N'[^A-Za-z0-9_]%'
                OR m.definition LIKE N'%[^A-Za-z0-9_]' + @ObjectName
              );

        WHILE EXISTS (SELECT 1 FROM #Referencing WHERE Processed = 0)
        BEGIN
            SELECT TOP (1)
                @RefId = Object_Id,
                @RefSchema = Object_Schema,
                @RefName = Object_Name,
                @RefType = Object_Type,
                @RefTypeDesc = Object_Type_Desc
            FROM #Referencing
            WHERE Processed = 0
            ORDER BY Object_Id;

            UPDATE #Referencing SET Processed = 1 WHERE Object_Id = @RefId;

            SET @RefTwoPart = QUOTENAME(@RefSchema) + N'.' + QUOTENAME(@RefName);

            BEGIN TRY
                IF EXISTS (
                    SELECT 1
                    FROM sys.dm_sql_referenced_entities(@RefTwoPart, N'OBJECT') AS re
                    WHERE (
                            re.referenced_id = @ObjectId
                            OR (
                                re.referenced_entity_name = @ObjectName
                                AND (re.referenced_schema_name = @SchemaName OR re.referenced_schema_name IS NULL)
                            )
                          )
                      AND (
                            re.referenced_minor_id = @ColumnId
                            OR re.referenced_minor_name = @ColActual
                          )
                )
                BEGIN
                    IF NOT EXISTS (SELECT 1 FROM #ModuleHits AS h WHERE h.Object_Id = @RefId)
                    BEGIN
                        INSERT INTO #ModuleHits
                        (
                            Object_Id, Object_Schema, Object_Name, Object_Type, Object_Type_Desc, Match_Source, Detail
                        )
                        VALUES
                        (
                            @RefId, @RefSchema, @RefName, @RefType, @RefTypeDesc,
                            N'sys.dm_sql_referenced_entities',
                            N'Column-level referenced entity bind'
                        );
                    END;
                    ELSE
                    BEGIN
                        UPDATE #ModuleHits
                        SET Match_Source = Match_Source + N'+dm_sql_referenced_entities',
                            Detail = N'Column confirmed by dm_sql_referenced_entities'
                        WHERE Object_Id = @RefId;
                    END;
                END;
                ELSE IF NOT EXISTS (SELECT 1 FROM #ModuleHits AS h WHERE h.Object_Id = @RefId)
                     AND OBJECT_DEFINITION(@RefId) IS NOT NULL
                     AND (
                            OBJECT_DEFINITION(@RefId) LIKE N'%[[]' + @ColActual + N']%'
                         OR OBJECT_DEFINITION(@RefId) LIKE N'%.' + @ColActual + N'[^A-Za-z0-9_]%'
                         OR OBJECT_DEFINITION(@RefId) LIKE N'%[^A-Za-z0-9_]' + @ColActual + N'[^A-Za-z0-9_]%'
                         OR OBJECT_DEFINITION(@RefId) LIKE @ColActual + N'[^A-Za-z0-9_]%'
                         OR OBJECT_DEFINITION(@RefId) LIKE N'%[^A-Za-z0-9_]' + @ColActual
                     )
                BEGIN
                    INSERT INTO #ModuleHits
                    (
                        Object_Id, Object_Schema, Object_Name, Object_Type, Object_Type_Desc, Match_Source, Detail
                    )
                    VALUES
                    (
                        @RefId, @RefSchema, @RefName, @RefType, @RefTypeDesc,
                        N'dm_sql_referencing_entities+definition',
                        N'Target referencer; column found in definition'
                    );
                END;
            END TRY
            BEGIN CATCH
                IF NOT EXISTS (SELECT 1 FROM #ModuleHits AS h WHERE h.Object_Id = @RefId)
                   AND OBJECT_DEFINITION(@RefId) IS NOT NULL
                   AND (
                          OBJECT_DEFINITION(@RefId) LIKE N'%[[]' + @ColActual + N']%'
                       OR OBJECT_DEFINITION(@RefId) LIKE N'%.' + @ColActual + N'[^A-Za-z0-9_]%'
                       OR OBJECT_DEFINITION(@RefId) LIKE N'%[^A-Za-z0-9_]' + @ColActual + N'[^A-Za-z0-9_]%'
                       OR OBJECT_DEFINITION(@RefId) LIKE @ColActual + N'[^A-Za-z0-9_]%'
                       OR OBJECT_DEFINITION(@RefId) LIKE N'%[^A-Za-z0-9_]' + @ColActual
                   )
                BEGIN
                    INSERT INTO #ModuleHits
                    (
                        Object_Id, Object_Schema, Object_Name, Object_Type, Object_Type_Desc, Match_Source, Detail
                    )
                    VALUES
                    (
                        @RefId, @RefSchema, @RefName, @RefType, @RefTypeDesc,
                        N'definition_fallback',
                        N'dm_sql_referenced_entities failed; matched via definition'
                    );
                END;
            END CATCH;
        END;

        INSERT INTO #ModuleHits
        (
            Object_Id, Object_Schema, Object_Name, Object_Type, Object_Type_Desc, Match_Source, Detail
        )
        SELECT DISTINCT
            o.object_id,
            OBJECT_SCHEMA_NAME(o.object_id),
            o.name,
            o.type COLLATE DATABASE_DEFAULT,
            o.type_desc COLLATE DATABASE_DEFAULT,
            N'sys.sql_expression_dependencies',
            N'Column-level catalog dependency (referenced_minor_id)'
        FROM sys.sql_expression_dependencies AS sed
        INNER JOIN sys.objects AS o
            ON sed.referencing_id = o.object_id
        WHERE sed.referenced_id = @ObjectId
          AND sed.referenced_minor_id = @ColumnId
          AND o.type COLLATE DATABASE_DEFAULT IN (SELECT type FROM @RefCatalogTypes)
          AND o.object_id <> @ObjectId
          AND NOT EXISTS (SELECT 1 FROM #ModuleHits AS h WHERE h.Object_Id = o.object_id);

        /* Check / default constraints (not in sql_modules) that mention the column */
        INSERT INTO #ModuleHits
        (
            Object_Id, Object_Schema, Object_Name, Object_Type, Object_Type_Desc, Match_Source, Detail
        )
        SELECT
            r.Object_Id,
            r.Object_Schema,
            r.Object_Name,
            r.Object_Type,
            r.Object_Type_Desc,
            N'sys.check_constraints',
            N'Column found in check constraint definition'
        FROM #Referencing AS r
        INNER JOIN sys.check_constraints AS cc
            ON cc.object_id = r.Object_Id
        WHERE r.Object_Type COLLATE DATABASE_DEFAULT = N'C'
          AND cc.definition IS NOT NULL
          AND (
                   cc.definition LIKE N'%[[]' + @ColActual + N']%'
                OR cc.definition LIKE N'%[^A-Za-z0-9_]' + @ColActual + N'[^A-Za-z0-9_]%'
                OR cc.definition LIKE N'%.' + @ColActual + N'%'
              )
          AND NOT EXISTS (SELECT 1 FROM #ModuleHits AS h WHERE h.Object_Id = r.Object_Id);

        INSERT INTO #ModuleHits
        (
            Object_Id, Object_Schema, Object_Name, Object_Type, Object_Type_Desc, Match_Source, Detail
        )
        SELECT
            r.Object_Id,
            r.Object_Schema,
            r.Object_Name,
            r.Object_Type,
            r.Object_Type_Desc,
            N'sys.default_constraints',
            N'Column found in default constraint definition'
        FROM #Referencing AS r
        INNER JOIN sys.default_constraints AS dc
            ON dc.object_id = r.Object_Id
        WHERE r.Object_Type COLLATE DATABASE_DEFAULT = N'D'
          AND dc.definition IS NOT NULL
          AND (
                   dc.definition LIKE N'%[[]' + @ColActual + N']%'
                OR dc.definition LIKE N'%[^A-Za-z0-9_]' + @ColActual + N'[^A-Za-z0-9_]%'
                OR dc.definition LIKE N'%.' + @ColActual + N'%'
              )
          AND NOT EXISTS (SELECT 1 FROM #ModuleHits AS h WHERE h.Object_Id = r.Object_Id);

        /* Classify SELECT_ONLY / FILTER / JOIN from module text */
        INSERT INTO #ModuleWork
        (
            Object_Id, Object_Schema, Object_Name, Object_Type, Object_Type_Desc, Match_Source, Processed
        )
        SELECT
            Object_Id, Object_Schema, Object_Name, Object_Type, Object_Type_Desc, Match_Source, 0
        FROM #ModuleHits;

        WHILE EXISTS (SELECT 1 FROM #ModuleWork WHERE Processed = 0)
        BEGIN
            SELECT TOP (1)
                @ModId = Object_Id,
                @ModSchema = Object_Schema,
                @ModName = Object_Name,
                @ModType = Object_Type,
                @ModTypeDesc = Object_Type_Desc,
                @ModSource = Match_Source
            FROM #ModuleWork
            WHERE Processed = 0
            ORDER BY Object_Id;

            UPDATE #ModuleWork SET Processed = 1 WHERE Object_Id = @ModId;

            SET @Def = NULL;
            SELECT @Def = m.definition
            FROM sys.sql_modules AS m
            WHERE m.object_id = @ModId;

            IF @Def IS NULL AND @ModType COLLATE DATABASE_DEFAULT = N'C'
                SELECT @Def = cc.definition
                FROM sys.check_constraints AS cc
                WHERE cc.object_id = @ModId;

            IF @Def IS NULL AND @ModType COLLATE DATABASE_DEFAULT = N'D'
                SELECT @Def = dc.definition
                FROM sys.default_constraints AS dc
                WHERE dc.object_id = @ModId;

            IF @Def IS NULL
            BEGIN
                INSERT INTO #ModuleUsages (Object_Id, Usage_Type, Usage_Snippet, Line_No)
                VALUES (@ModId, N'UNKNOWN', N'Encrypted or unavailable module definition', 0);
            END;
            ELSE
            BEGIN
                SET @Remaining = REPLACE(@Def, CHAR(13), N'');
                SET @Ctx = N'UNKNOWN';
                SET @LineNo = 0;

                WHILE LEN(@Remaining) > 0
                BEGIN
                    SET @NlPos = CHARINDEX(CHAR(10), @Remaining);
                    IF @NlPos = 0
                    BEGIN
                        SET @Line = @Remaining;
                        SET @Remaining = N'';
                    END;
                    ELSE
                    BEGIN
                        SET @Line = LEFT(@Remaining, @NlPos - 1);
                        SET @Remaining = SUBSTRING(@Remaining, @NlPos + 1, LEN(@Remaining));
                    END;

                    SET @LineNo = @LineNo + 1;
                    SET @Line = LTRIM(RTRIM(REPLACE(@Line, CHAR(9), N' ')));

                    IF NOT (@Line = N'' OR LEFT(@Line, 2) = N'--')
                    BEGIN
                        SET @LineDetect = UPPER(@Line);
                        WHILE CHARINDEX(N'  ', @LineDetect) > 0
                            SET @LineDetect = REPLACE(@LineDetect, N'  ', N' ');

                        SET @PrevCtx = @Ctx;

                        IF @LineDetect LIKE N'SELECT %'
                           OR @LineDetect = N'SELECT'
                           OR @LineDetect LIKE N'SELECT[%'
                            SET @Ctx = N'SELECT';
                        ELSE IF @LineDetect LIKE N'FROM %'
                                OR @LineDetect = N'FROM'
                            SET @Ctx = N'FROM';
                        ELSE IF @LineDetect LIKE N'%INNER JOIN%'
                                OR @LineDetect LIKE N'%LEFT JOIN%'
                                OR @LineDetect LIKE N'%RIGHT JOIN%'
                                OR @LineDetect LIKE N'%FULL JOIN%'
                                OR @LineDetect LIKE N'%CROSS JOIN%'
                                OR @LineDetect LIKE N'%OUTER JOIN%'
                                OR @LineDetect LIKE N'JOIN %'
                                OR @LineDetect LIKE N'% JOIN %'
                            SET @Ctx = N'JOIN';
                        ELSE IF (
                                    @LineDetect LIKE N'ON %'
                                 OR @LineDetect LIKE N'% ON %'
                                 OR @LineDetect = N'ON'
                                )
                                AND @Ctx IN (N'JOIN', N'JOIN_ON', N'FROM')
                            SET @Ctx = N'JOIN_ON';
                        ELSE IF @LineDetect LIKE N'WHERE %'
                                OR @LineDetect = N'WHERE'
                                OR @LineDetect LIKE N'WHERE[%'
                            SET @Ctx = N'WHERE';
                        ELSE IF @LineDetect LIKE N'HAVING %'
                                OR @LineDetect = N'HAVING'
                            SET @Ctx = N'HAVING';
                        ELSE IF @LineDetect LIKE N'GROUP BY%'
                            SET @Ctx = N'GROUP_BY';
                        ELSE IF @LineDetect LIKE N'ORDER BY%'
                            SET @Ctx = N'ORDER_BY';
                        ELSE IF @LineDetect LIKE N'SET %'
                                OR @LineDetect LIKE N'SET[%'
                            SET @Ctx = N'SET';

                        IF (
                                @LineDetect LIKE N'AND %'
                             OR @LineDetect LIKE N'OR %'
                             OR @LineDetect = N'AND'
                             OR @LineDetect = N'OR'
                            )
                           AND @PrevCtx IN (N'WHERE', N'HAVING', N'JOIN_ON')
                            SET @Ctx = @PrevCtx;

                        SET @Padded = N' ' + UPPER(REPLACE(REPLACE(REPLACE(@Line, N'[', N' '), N']', N' '), N'.', N' ')) + N' ';
                        WHILE CHARINDEX(N'  ', @Padded) > 0
                            SET @Padded = REPLACE(@Padded, N'  ', N' ');

                        SET @HasCol = CASE
                            WHEN CHARINDEX(N' ' + UPPER(@ColActual) + N' ', @Padded) > 0 THEN 1
                            ELSE 0
                        END;

                        IF @HasCol = 1
                        BEGIN
                            SET @MappedUsage = CASE @Ctx
                                WHEN N'JOIN_ON' THEN N'JOIN'
                                WHEN N'JOIN' THEN N'JOIN'
                                WHEN N'WHERE' THEN N'FILTER'
                                WHEN N'HAVING' THEN N'FILTER'
                                WHEN N'SELECT' THEN N'SELECT'
                                WHEN N'GROUP_BY' THEN N'OTHER'
                                WHEN N'ORDER_BY' THEN N'OTHER'
                                WHEN N'SET' THEN N'OTHER'
                                ELSE N'OTHER'
                            END;

                            IF @MappedUsage = N'JOIN' AND @Ctx = N'JOIN'
                               AND @LineDetect NOT LIKE N'% ON %'
                               AND @LineDetect NOT LIKE N'ON %'
                                SET @MappedUsage = N'OTHER';

                            IF NOT EXISTS (
                                SELECT 1
                                FROM #ModuleUsages AS u
                                WHERE u.Object_Id = @ModId
                                  AND u.Usage_Type = @MappedUsage
                                  AND ISNULL(u.Usage_Snippet, N'') = @Line
                            )
                            BEGIN
                                INSERT INTO #ModuleUsages (Object_Id, Usage_Type, Usage_Snippet, Line_No)
                                VALUES (@ModId, @MappedUsage, @Line, @LineNo);
                            END;
                        END;
                    END;
                END;

                SET @HasSelect = 0;
                SET @HasFilter = 0;
                SET @HasJoin = 0;

                SELECT
                    @HasSelect = MAX(CASE WHEN Usage_Type = N'SELECT' THEN 1 ELSE 0 END),
                    @HasFilter = MAX(CASE WHEN Usage_Type = N'FILTER' THEN 1 ELSE 0 END),
                    @HasJoin   = MAX(CASE WHEN Usage_Type = N'JOIN' THEN 1 ELSE 0 END)
                FROM #ModuleUsages
                WHERE Object_Id = @ModId;

                IF ISNULL(@HasSelect, 0) = 1
                   AND ISNULL(@HasFilter, 0) = 0
                   AND ISNULL(@HasJoin, 0) = 0
                BEGIN
                    DELETE FROM #ModuleUsages
                    WHERE Object_Id = @ModId
                      AND Usage_Type = N'SELECT';

                    INSERT INTO #ModuleUsages (Object_Id, Usage_Type, Usage_Snippet, Line_No)
                    VALUES (@ModId, N'SELECT_ONLY', NULL, 0);
                END;
                ELSE IF ISNULL(@HasFilter, 0) = 1 OR ISNULL(@HasJoin, 0) = 1
                BEGIN
                    DELETE FROM #ModuleUsages
                    WHERE Object_Id = @ModId
                      AND Usage_Type = N'SELECT';
                END;

                IF NOT EXISTS (SELECT 1 FROM #ModuleUsages AS u WHERE u.Object_Id = @ModId)
                BEGIN
                    INSERT INTO #ModuleUsages (Object_Id, Usage_Type, Usage_Snippet, Line_No)
                    VALUES (@ModId, N'UNKNOWN', N'Column matched module but clause context was not detected', 0);
                END;
            END;
        END;

        INSERT INTO #Deps
        (
            Target_Schema, Target_Name, Target_Type, Target_Type_Desc, Target_Object_Id,
            Direction, Dependency_Type, Object_Schema, Object_Name, Object_Type, Object_Type_Desc,
            Related_Schema, Related_Name, Detail, Usage_Type, Usage_Snippet,
            Is_Caller_Dependent, Is_Ambiguous, Sort_Group, Match_Source
        )
        SELECT
            @SchemaName,
            @ObjectName,
            @ObjectType,
            @ObjectTypeDesc,
            @ObjectId,
            N'Incoming',
            CASE h.Object_Type
                WHEN N'V'  THEN N'View'
                WHEN N'P'  THEN N'StoredProcedure'
                WHEN N'PC' THEN N'StoredProcedure'
                WHEN N'X'  THEN N'StoredProcedure'
                WHEN N'FN' THEN N'Function'
                WHEN N'IF' THEN N'Function'
                WHEN N'TF' THEN N'Function'
                WHEN N'FS' THEN N'Function'
                WHEN N'FT' THEN N'Function'
                WHEN N'AF' THEN N'Function'
                WHEN N'TR' THEN N'Trigger'
                WHEN N'U'  THEN N'Table'
                WHEN N'C'  THEN N'CheckConstraint'
                WHEN N'D'  THEN N'DefaultConstraint'
                ELSE N'Module'
            END,
            h.Object_Schema,
            h.Object_Name,
            h.Object_Type,
            h.Object_Type_Desc,
            NULL,
            @ColActual,
            CASE u.Usage_Type
                WHEN N'SELECT_ONLY' THEN N'SELECT only - column not used in JOIN/WHERE/HAVING'
                WHEN N'FILTER' THEN N'FILTER condition'
                WHEN N'JOIN' THEN N'JOIN condition'
                WHEN N'OTHER' THEN N'Other usage (GROUP BY / ORDER BY / SET / unresolved clause)'
                ELSE N'Usage could not be classified'
            END,
            u.Usage_Type,
            CASE
                WHEN u.Usage_Type IN (N'FILTER', N'JOIN', N'OTHER') THEN u.Usage_Snippet
                ELSE NULL
            END,
            0,
            0,
            CASE h.Object_Type
                WHEN N'V' THEN 11
                WHEN N'P' THEN 12
                WHEN N'PC' THEN 12
                WHEN N'X' THEN 12
                WHEN N'TR' THEN 14
                WHEN N'C' THEN 15
                WHEN N'D' THEN 15
                ELSE 13
            END
                + CASE u.Usage_Type
                      WHEN N'JOIN' THEN 0
                      WHEN N'FILTER' THEN 1
                      WHEN N'SELECT_ONLY' THEN 2
                      ELSE 3
                  END,
            h.Match_Source
        FROM #ModuleHits AS h
        INNER JOIN #ModuleUsages AS u
            ON u.Object_Id = h.Object_Id;
    END;

    /*--------------------------------------------------------------------
      2b) Outgoing: what this object references (useful for views/TVFs/procs)
    --------------------------------------------------------------------*/
    IF @FilterByColumn = 0
    BEGIN
        INSERT INTO #Deps
        (
            Target_Schema, Target_Name, Target_Type, Target_Type_Desc, Target_Object_Id,
            Direction, Dependency_Type, Object_Schema, Object_Name, Object_Type, Object_Type_Desc,
            Related_Schema, Related_Name, Detail, Is_Caller_Dependent, Is_Ambiguous, Sort_Group, Match_Source
        )
        SELECT DISTINCT
            @SchemaName,
            @ObjectName,
            @ObjectType,
            @ObjectTypeDesc,
            @ObjectId,
            N'Outgoing',
            CASE ISNULL(ro.type COLLATE DATABASE_DEFAULT, N'?')
                WHEN N'U'  THEN N'Table'
                WHEN N'V'  THEN N'View'
                WHEN N'P'  THEN N'StoredProcedure'
                WHEN N'PC' THEN N'StoredProcedure'
                WHEN N'FN' THEN N'Function'
                WHEN N'IF' THEN N'Function'
                WHEN N'TF' THEN N'Function'
                WHEN N'FS' THEN N'Function'
                WHEN N'FT' THEN N'Function'
                ELSE N'ReferencedObject'
            END,
            ISNULL(OBJECT_SCHEMA_NAME(sed.referenced_id), sed.referenced_schema_name),
            ISNULL(OBJECT_NAME(sed.referenced_id), sed.referenced_entity_name),
            ISNULL(ro.type COLLATE DATABASE_DEFAULT, N'?'),
            ISNULL(ro.type_desc COLLATE DATABASE_DEFAULT, N'UNKNOWN'),
            NULL,
            CASE
                WHEN sed.referenced_minor_id > 0
                    THEN COL_NAME(sed.referenced_id, sed.referenced_minor_id)
                ELSE NULL
            END,
            CASE
                WHEN sed.referenced_minor_id > 0
                    THEN (N'References column: ' COLLATE DATABASE_DEFAULT)
                         + (ISNULL(COL_NAME(sed.referenced_id, sed.referenced_minor_id), N'?') COLLATE DATABASE_DEFAULT)
                ELSE N'References object' COLLATE DATABASE_DEFAULT
            END,
            sed.is_caller_dependent,
            sed.is_ambiguous,
            15,
            N'sys.sql_expression_dependencies'
        FROM sys.sql_expression_dependencies AS sed
        LEFT JOIN sys.objects AS ro
            ON sed.referenced_id = ro.object_id
        WHERE sed.referencing_id = @ObjectId
          AND (
                sed.referenced_id IS NULL
                OR sed.referenced_id <> @ObjectId
              );
    END;

    /*--------------------------------------------------------------------
      2c) Table/view catalog dependencies (FK, index, trigger, constraints)
    --------------------------------------------------------------------*/
    IF @ObjectType COLLATE DATABASE_DEFAULT = N'U'
    BEGIN
        INSERT INTO #Deps
        (
            Target_Schema, Target_Name, Target_Type, Target_Type_Desc, Target_Object_Id,
            Direction, Dependency_Type, Object_Schema, Object_Name, Object_Type, Object_Type_Desc,
            Related_Schema, Related_Name, Detail, Is_Caller_Dependent, Is_Ambiguous, Sort_Group, Match_Source
        )
        SELECT
            @SchemaName, @ObjectName, @ObjectType, @ObjectTypeDesc, @ObjectId,
            N'Incoming',
            N'ForeignKey',
            OBJECT_SCHEMA_NAME(fk.parent_object_id),
            OBJECT_NAME(fk.parent_object_id),
            N'F',
            N'FOREIGN_KEY_CONSTRAINT',
            OBJECT_SCHEMA_NAME(fk.object_id),
            fk.name,
            (
                (N'FK columns: ' COLLATE DATABASE_DEFAULT)
                + (STUFF((
                    SELECT
                        (N', ' COLLATE DATABASE_DEFAULT)
                        + (QUOTENAME(pc.name) COLLATE DATABASE_DEFAULT)
                        + (N' -> ' COLLATE DATABASE_DEFAULT)
                        + (QUOTENAME(rc.name) COLLATE DATABASE_DEFAULT)
                    FROM sys.foreign_key_columns AS fkc
                    INNER JOIN sys.columns AS pc
                        ON fkc.parent_object_id = pc.object_id
                       AND fkc.parent_column_id = pc.column_id
                    INNER JOIN sys.columns AS rc
                        ON fkc.referenced_object_id = rc.object_id
                       AND fkc.referenced_column_id = rc.column_id
                    WHERE fkc.constraint_object_id = fk.object_id
                    ORDER BY fkc.constraint_column_id
                    FOR XML PATH(N''), TYPE
                ).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N'') COLLATE DATABASE_DEFAULT)
                + (N'; delete=' COLLATE DATABASE_DEFAULT)
                + (fk.delete_referential_action_desc COLLATE DATABASE_DEFAULT)
                + (N'; update=' COLLATE DATABASE_DEFAULT)
                + (fk.update_referential_action_desc COLLATE DATABASE_DEFAULT)
            ),
            0, 0, 20, N'sys.foreign_keys'
        FROM sys.foreign_keys AS fk
        WHERE fk.referenced_object_id = @ObjectId
          AND (
                @FilterByColumn = 0
                OR EXISTS (
                    SELECT 1
                    FROM sys.foreign_key_columns AS fkc
                    WHERE fkc.constraint_object_id = fk.object_id
                      AND fkc.referenced_object_id = @ObjectId
                      AND fkc.referenced_column_id = @ColumnId
                )
              );

        INSERT INTO #Deps
        (
            Target_Schema, Target_Name, Target_Type, Target_Type_Desc, Target_Object_Id,
            Direction, Dependency_Type, Object_Schema, Object_Name, Object_Type, Object_Type_Desc,
            Related_Schema, Related_Name, Detail, Is_Caller_Dependent, Is_Ambiguous, Sort_Group, Match_Source
        )
        SELECT
            @SchemaName, @ObjectName, @ObjectType, @ObjectTypeDesc, @ObjectId,
            N'Outgoing',
            N'ForeignKey',
            OBJECT_SCHEMA_NAME(fk.referenced_object_id),
            OBJECT_NAME(fk.referenced_object_id),
            N'U',
            N'USER_TABLE',
            OBJECT_SCHEMA_NAME(fk.object_id),
            fk.name,
            (
                (N'FK columns: ' COLLATE DATABASE_DEFAULT)
                + (STUFF((
                    SELECT
                        (N', ' COLLATE DATABASE_DEFAULT)
                        + (QUOTENAME(pc.name) COLLATE DATABASE_DEFAULT)
                        + (N' -> ' COLLATE DATABASE_DEFAULT)
                        + (QUOTENAME(rc.name) COLLATE DATABASE_DEFAULT)
                    FROM sys.foreign_key_columns AS fkc
                    INNER JOIN sys.columns AS pc
                        ON fkc.parent_object_id = pc.object_id
                       AND fkc.parent_column_id = pc.column_id
                    INNER JOIN sys.columns AS rc
                        ON fkc.referenced_object_id = rc.object_id
                       AND fkc.referenced_column_id = rc.column_id
                    WHERE fkc.constraint_object_id = fk.object_id
                    ORDER BY fkc.constraint_column_id
                    FOR XML PATH(N''), TYPE
                ).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N'') COLLATE DATABASE_DEFAULT)
                + (N'; delete=' COLLATE DATABASE_DEFAULT)
                + (fk.delete_referential_action_desc COLLATE DATABASE_DEFAULT)
                + (N'; update=' COLLATE DATABASE_DEFAULT)
                + (fk.update_referential_action_desc COLLATE DATABASE_DEFAULT)
            ),
            0, 0, 30, N'sys.foreign_keys'
        FROM sys.foreign_keys AS fk
        WHERE fk.parent_object_id = @ObjectId
          AND (
                @FilterByColumn = 0
                OR EXISTS (
                    SELECT 1
                    FROM sys.foreign_key_columns AS fkc
                    WHERE fkc.constraint_object_id = fk.object_id
                      AND fkc.parent_object_id = @ObjectId
                      AND fkc.parent_column_id = @ColumnId
                )
              );

        INSERT INTO #Deps
        (
            Target_Schema, Target_Name, Target_Type, Target_Type_Desc, Target_Object_Id,
            Direction, Dependency_Type, Object_Schema, Object_Name, Object_Type, Object_Type_Desc,
            Related_Schema, Related_Name, Detail, Is_Caller_Dependent, Is_Ambiguous, Sort_Group, Match_Source
        )
        SELECT
            @SchemaName, @ObjectName, @ObjectType, @ObjectTypeDesc, @ObjectId,
            N'OnObject',
            N'CheckConstraint',
            OBJECT_SCHEMA_NAME(cc.parent_object_id),
            cc.name,
            N'C',
            N'CHECK_CONSTRAINT',
            NULL,
            NULL,
            LEFT(cc.definition, 4000),
            0, 0, 60, N'sys.check_constraints'
        FROM sys.check_constraints AS cc
        WHERE cc.parent_object_id = @ObjectId
          AND (
                @FilterByColumn = 0
                OR cc.parent_column_id = @ColumnId
                OR (
                    cc.definition IS NOT NULL
                    AND @ColActual IS NOT NULL
                    AND (
                           cc.definition LIKE N'%[[]' + @ColActual + N']%'
                        OR cc.definition LIKE N'%[^A-Za-z0-9_]' + @ColActual + N'[^A-Za-z0-9_]%'
                        OR cc.definition LIKE N'%.' + @ColActual + N'%'
                    )
                )
              );

        INSERT INTO #Deps
        (
            Target_Schema, Target_Name, Target_Type, Target_Type_Desc, Target_Object_Id,
            Direction, Dependency_Type, Object_Schema, Object_Name, Object_Type, Object_Type_Desc,
            Related_Schema, Related_Name, Detail, Is_Caller_Dependent, Is_Ambiguous, Sort_Group, Match_Source
        )
        SELECT
            @SchemaName, @ObjectName, @ObjectType, @ObjectTypeDesc, @ObjectId,
            N'OnObject',
            N'DefaultConstraint',
            OBJECT_SCHEMA_NAME(dc.parent_object_id),
            dc.name,
            N'D',
            N'DEFAULT_CONSTRAINT',
            NULL,
            COL_NAME(dc.parent_object_id, dc.parent_column_id),
            LEFT(dc.definition, 4000),
            0, 0, 70, N'sys.default_constraints'
        FROM sys.default_constraints AS dc
        WHERE dc.parent_object_id = @ObjectId
          AND (
                @FilterByColumn = 0
                OR dc.parent_column_id = @ColumnId
              );

        IF @FilterByColumn = 1 AND @ColActual IS NOT NULL
        BEGIN
            INSERT INTO #Deps
            (
                Target_Schema, Target_Name, Target_Type, Target_Type_Desc, Target_Object_Id,
                Direction, Dependency_Type, Object_Schema, Object_Name, Object_Type, Object_Type_Desc,
                Related_Schema, Related_Name, Detail, Is_Caller_Dependent, Is_Ambiguous, Sort_Group, Match_Source
            )
            SELECT
                @SchemaName, @ObjectName, @ObjectType, @ObjectTypeDesc, @ObjectId,
                N'OnObject',
                N'ComputedColumn',
                @SchemaName,
                c.name,
                N'CC',
                N'COMPUTED_COLUMN',
                NULL,
                NULL,
                LEFT(cc.definition, 4000),
                0, 0, 80, N'sys.computed_columns'
            FROM sys.columns AS c
            INNER JOIN sys.computed_columns AS cc
                ON c.object_id = cc.object_id
               AND c.column_id = cc.column_id
            WHERE c.object_id = @ObjectId
              AND c.column_id <> @ColumnId
              AND cc.definition IS NOT NULL
              AND (
                       cc.definition LIKE N'%[[]' + @ColActual + N']%'
                    OR cc.definition LIKE N'%[^A-Za-z0-9_]' + @ColActual + N'[^A-Za-z0-9_]%'
                    OR cc.definition LIKE N'%.' + @ColActual + N'%'
                  );
        END;
    END;

    /* Indexes: tables and indexed views */
    IF @ObjectType COLLATE DATABASE_DEFAULT IN (N'U', N'V')
    BEGIN
        INSERT INTO #Deps
        (
            Target_Schema, Target_Name, Target_Type, Target_Type_Desc, Target_Object_Id,
            Direction, Dependency_Type, Object_Schema, Object_Name, Object_Type, Object_Type_Desc,
            Related_Schema, Related_Name, Detail, Is_Caller_Dependent, Is_Ambiguous, Sort_Group, Match_Source
        )
        SELECT
            @SchemaName, @ObjectName, @ObjectType, @ObjectTypeDesc, @ObjectId,
            N'OnObject',
            N'Index',
            OBJECT_SCHEMA_NAME(i.object_id),
            i.name,
            N'IX',
            i.type_desc,
            NULL,
            NULL,
            (
                (N'index_id=' COLLATE DATABASE_DEFAULT)
                + (CONVERT(NVARCHAR(11), i.index_id) COLLATE DATABASE_DEFAULT)
                + (N'; is_unique=' COLLATE DATABASE_DEFAULT)
                + ((CASE WHEN i.is_unique = 1 THEN N'1' ELSE N'0' END) COLLATE DATABASE_DEFAULT)
                + (N'; is_primary_key=' COLLATE DATABASE_DEFAULT)
                + ((CASE WHEN i.is_primary_key = 1 THEN N'1' ELSE N'0' END) COLLATE DATABASE_DEFAULT)
                + (N'; column_usage=' COLLATE DATABASE_DEFAULT)
                + (STUFF((
                    SELECT
                        (N', ' COLLATE DATABASE_DEFAULT)
                        + (QUOTENAME(c.name) COLLATE DATABASE_DEFAULT)
                        + ((CASE WHEN ic.is_included_column = 1 THEN N' (INCLUDE)' ELSE N' (KEY)' END) COLLATE DATABASE_DEFAULT)
                    FROM sys.index_columns AS ic
                    INNER JOIN sys.columns AS c
                        ON ic.object_id = c.object_id
                       AND ic.column_id = c.column_id
                    WHERE ic.object_id = i.object_id
                      AND ic.index_id = i.index_id
                      AND (@FilterByColumn = 0 OR ic.column_id = @ColumnId)
                    ORDER BY ic.is_included_column, ic.key_ordinal, ic.index_column_id
                    FOR XML PATH(N''), TYPE
                ).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N'') COLLATE DATABASE_DEFAULT)
            ),
            0, 0, 35, N'sys.indexes'
        FROM sys.indexes AS i
        WHERE i.object_id = @ObjectId
          AND i.index_id > 0
          AND i.name IS NOT NULL
          AND (
                @FilterByColumn = 0
                OR EXISTS (
                    SELECT 1
                    FROM sys.index_columns AS ic
                    WHERE ic.object_id = i.object_id
                      AND ic.index_id = i.index_id
                      AND ic.column_id = @ColumnId
                )
              );
    END;

    /* Triggers: tables and views */
    IF @ObjectType COLLATE DATABASE_DEFAULT IN (N'U', N'V')
    BEGIN
        INSERT INTO #Deps
        (
            Target_Schema, Target_Name, Target_Type, Target_Type_Desc, Target_Object_Id,
            Direction, Dependency_Type, Object_Schema, Object_Name, Object_Type, Object_Type_Desc,
            Related_Schema, Related_Name, Detail, Is_Caller_Dependent, Is_Ambiguous, Sort_Group, Match_Source
        )
        SELECT
            @SchemaName, @ObjectName, @ObjectType, @ObjectTypeDesc, @ObjectId,
            N'OnObject',
            N'Trigger',
            OBJECT_SCHEMA_NAME(tr.object_id),
            tr.name,
            N'TR',
            N'SQL_TRIGGER',
            NULL,
            NULL,
            (N'is_disabled=' COLLATE DATABASE_DEFAULT)
                + ((CASE WHEN tr.is_disabled = 1 THEN N'1' ELSE N'0' END) COLLATE DATABASE_DEFAULT)
                + (N'; is_instead_of=' COLLATE DATABASE_DEFAULT)
                + ((CASE WHEN tr.is_instead_of_trigger = 1 THEN N'1' ELSE N'0' END) COLLATE DATABASE_DEFAULT),
            0, 0, 40, N'sys.triggers'
        FROM sys.triggers AS tr
        WHERE tr.parent_id = @ObjectId
          AND (
                @FilterByColumn = 0
                OR (
                    @ColActual IS NOT NULL
                    AND OBJECT_DEFINITION(tr.object_id) IS NOT NULL
                    AND (
                           OBJECT_DEFINITION(tr.object_id) LIKE N'%[[]' + @ColActual + N']%'
                        OR OBJECT_DEFINITION(tr.object_id) LIKE N'%.' + @ColActual + N'[^A-Za-z0-9_]%'
                        OR OBJECT_DEFINITION(tr.object_id) LIKE N'%[^A-Za-z0-9_]' + @ColActual + N'[^A-Za-z0-9_]%'
                        OR OBJECT_DEFINITION(tr.object_id) LIKE @ColActual + N'[^A-Za-z0-9_]%'
                        OR OBJECT_DEFINITION(tr.object_id) LIKE N'%[^A-Za-z0-9_]' + @ColActual
                    )
                )
              );
    END;

    /* Synonyms pointing at this object */
    IF @FilterByColumn = 0
    BEGIN
        INSERT INTO #Deps
        (
            Target_Schema, Target_Name, Target_Type, Target_Type_Desc, Target_Object_Id,
            Direction, Dependency_Type, Object_Schema, Object_Name, Object_Type, Object_Type_Desc,
            Related_Schema, Related_Name, Detail, Is_Caller_Dependent, Is_Ambiguous, Sort_Group, Match_Source
        )
        SELECT
            @SchemaName, @ObjectName, @ObjectType, @ObjectTypeDesc, @ObjectId,
            N'Incoming',
            N'Synonym',
            OBJECT_SCHEMA_NAME(sy.object_id),
            sy.name,
            N'SN',
            N'SYNONYM',
            NULL,
            NULL,
            (N'base_object_name=' COLLATE DATABASE_DEFAULT)
                + (sy.base_object_name COLLATE DATABASE_DEFAULT),
            0, 0, 50, N'sys.synonyms'
        FROM sys.synonyms AS sy
        WHERE OBJECT_ID(sy.base_object_name) = @ObjectId;
    END;

    FETCH NEXT FROM target_cursor INTO
        @ObjectId, @SchemaName, @ObjectName, @ObjectType, @ObjectTypeDesc,
        @TwoPartName, @FilterByColumn, @ColumnId, @ColActual;
END;

CLOSE target_cursor;
DEALLOCATE target_cursor;

/*------------------------------------------------------------------------------
  3) Dependency detail
------------------------------------------------------------------------------*/
SELECT
    Target_Schema,
    Target_Name,
    Target_Type,
    Target_Type_Desc,
    Direction,
    Dependency_Type,
    Object_Schema,
    Object_Name,
    Object_Type,
    Object_Type_Desc,
    Related_Schema,
    Related_Name,
    Usage_Type,
    Usage_Snippet,
    Detail,
    Match_Source,
    Is_Caller_Dependent,
    Is_Ambiguous
FROM #Deps
ORDER BY
    Target_Schema,
    Target_Name,
    Sort_Group,
    Dependency_Type,
    Object_Schema,
    Object_Name,
    Usage_Type,
    Related_Name;

/*------------------------------------------------------------------------------
  4) Counts
------------------------------------------------------------------------------*/
SELECT
    Target_Schema,
    Target_Name,
    Direction,
    Dependency_Type,
    Usage_Type,
    COUNT(*) AS Dependency_Count
FROM #Deps
GROUP BY Target_Schema, Target_Name, Direction, Dependency_Type, Usage_Type
ORDER BY Target_Schema, Target_Name, Direction, Dependency_Type, Usage_Type;

DROP TABLE #Deps;
DROP TABLE #ModuleHits;
DROP TABLE #Referencing;
DROP TABLE #ModuleUsages;
DROP TABLE #ModuleWork;
DROP TABLE #Targets;
