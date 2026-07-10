/*
================================================================================
Purpose:        Audits every user stored procedure across selected databases for
                implicit conversion risks (especially join/WHERE column pairs with
                mismatched data types), and common unoptimized or poorly written
                T-SQL patterns.
Provides:       (1) Executive summary per procedure, (2) join/column type mismatch
                details, (3) static anti-pattern findings, (4) runtime implicit
                conversions from cached plans when the procedure has been executed.
Importance:     Stored procedures are long-lived application code. Static review
                catches datatype mismatches before they hit production plans; runtime
                review confirms what SQL Server actually converts at execution time.
Interpretation: Start with Critical/High findings in the summary. Prioritize
                JOIN_TYPE_MISMATCH and RUNTIME_IMPLICIT_CONVERSION rows where both
                sides resolve to real table columns with different types. Treat
                static pattern hits as review candidates — regex-based scans can
                produce false positives in dynamic SQL or comments (comments are
                stripped before analysis).
Action:         Align join/WHERE column types (e.g. INT to INT, NVARCHAR to NVARCHAR),
                fix parameter types to match indexed columns, refactor cursors/WHILE
                loops to set-based logic, remove NOLOCK unless explicitly justified,
                and replace non-SARGable predicates (functions on columns, leading
                wildcards). Re-run after changes; enable Query Store for history.
Parameters:     @DatabaseList, @IncludeRuntimePlanAnalysis, @RuntimePlanTopPerProc,
                @MinSeverityFilter, @IncludeEncryptedProcedures.
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;          -- e.g. N'SalesDB,HRDB'; NULL = all online user DBs
DECLARE @IncludeRuntimePlanAnalysis BIT = 1;         -- Scan plan cache per procedure object_id
DECLARE @RuntimePlanTopPerProc INT = 5;              -- Max cached-plan conversion rows per procedure
DECLARE @MinSeverityFilter TINYINT = 1;              -- 1=All, 2=Medium+, 3=High+, 4=Critical only
DECLARE @IncludeEncryptedProcedures BIT = 0;         -- Encrypted modules have NULL definition

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

IF OBJECT_ID(N'tempdb..#SeverityRank') IS NOT NULL DROP TABLE #SeverityRank;
CREATE TABLE #SeverityRank (Severity NVARCHAR(20) NOT NULL PRIMARY KEY, RankValue TINYINT NOT NULL);
INSERT INTO #SeverityRank (Severity, RankValue)
VALUES
    (N'Critical', 4),
    (N'High', 3),
    (N'Medium', 2),
    (N'Low', 1),
    (N'Info', 0);

IF OBJECT_ID(N'tempdb..#StoredProcedures') IS NOT NULL DROP TABLE #StoredProcedures;
CREATE TABLE #StoredProcedures
(
    Database_Name SYSNAME NOT NULL,
    Schema_Name SYSNAME NOT NULL,
    Procedure_Name SYSNAME NOT NULL,
    Object_Id INT NOT NULL,
    Definition NVARCHAR(MAX) NULL,
    Definition_Length INT NOT NULL,
    Is_Encrypted BIT NOT NULL,
    Create_Date DATETIME NULL,
    Modify_Date DATETIME NULL,
    Parameter_Count INT NOT NULL,
    CONSTRAINT PK_StoredProcedures PRIMARY KEY (Database_Name, Object_Id)
);

IF OBJECT_ID(N'tempdb..#ColumnCatalog') IS NOT NULL DROP TABLE #ColumnCatalog;
CREATE TABLE #ColumnCatalog
(
    Database_Name SYSNAME NOT NULL,
    Schema_Name SYSNAME NOT NULL,
    Table_Name SYSNAME NOT NULL,
    Column_Name SYSNAME NOT NULL,
    Column_Id INT NOT NULL,
    System_Type_Id INT NOT NULL,
    Type_Name NVARCHAR(128) NOT NULL,
    Max_Length INT NOT NULL,
    Precision TINYINT NOT NULL,
    Scale TINYINT NOT NULL,
    Is_Computed BIT NOT NULL,
    Full_Type_Description NVARCHAR(256) NOT NULL,
    CONSTRAINT PK_ColumnCatalog PRIMARY KEY (Database_Name, Schema_Name, Table_Name, Column_Name)
);

IF OBJECT_ID(N'tempdb..#TableAliases') IS NOT NULL DROP TABLE #TableAliases;
CREATE TABLE #TableAliases
(
    Database_Name SYSNAME NOT NULL,
    Object_Id INT NOT NULL,
    Alias_Name SYSNAME NOT NULL,
    Schema_Name SYSNAME NULL,
    Table_Name SYSNAME NOT NULL,
    Source_Clause NVARCHAR(20) NOT NULL
);

IF OBJECT_ID(N'tempdb..#Findings') IS NOT NULL DROP TABLE #Findings;
CREATE TABLE #Findings
(
    Finding_Id INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
    Database_Name SYSNAME NOT NULL,
    Schema_Name SYSNAME NOT NULL,
    Procedure_Name SYSNAME NOT NULL,
    Object_Id INT NOT NULL,
    Finding_Category NVARCHAR(40) NOT NULL,
    Issue_Code NVARCHAR(60) NOT NULL,
    Severity NVARCHAR(20) NOT NULL,
    Issue_Title NVARCHAR(200) NOT NULL,
    Issue_Detail NVARCHAR(4000) NOT NULL,
    Recommendation NVARCHAR(4000) NOT NULL,
    Source_Context NVARCHAR(1000) NULL,
    Left_Object NVARCHAR(517) NULL,
    Left_Data_Type NVARCHAR(256) NULL,
    Right_Object NVARCHAR(517) NULL,
    Right_Data_Type NVARCHAR(256) NULL,
    Runtime_Execution_Count BIGINT NULL,
    Runtime_Total_CPU_ms BIGINT NULL,
    Runtime_Last_Execution DATETIME NULL
);

DECLARE @db_name SYSNAME;
DECLARE @sql NVARCHAR(MAX);

PRINT 'Collecting stored procedures and column metadata...';

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT database_name FROM #DbTargets ORDER BY database_name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'USE ' + QUOTENAME(@db_name) + N';

INSERT INTO #StoredProcedures
(
    Database_Name,
    Schema_Name,
    Procedure_Name,
    Object_Id,
    Definition,
    Definition_Length,
    Is_Encrypted,
    Create_Date,
    Modify_Date,
    Parameter_Count
)
SELECT
    DB_NAME(),
    s.name,
    p.name,
    p.object_id,
    m.definition,
    COALESCE(LEN(m.definition), 0),
    CASE WHEN m.definition IS NULL THEN 1 ELSE 0 END,
    p.create_date,
    p.modify_date,
    COALESCE(prm.Parameter_Count, 0)
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s
    ON p.schema_id = s.schema_id
INNER JOIN sys.sql_modules AS m
    ON p.object_id = m.object_id
OUTER APPLY
(
    SELECT COUNT(*) AS Parameter_Count
    FROM sys.parameters AS par
    WHERE par.object_id = p.object_id
) AS prm
WHERE p.is_ms_shipped = 0
  AND (@IncludeEncrypted = 0 OR m.definition IS NOT NULL);

INSERT INTO #ColumnCatalog
(
    Database_Name,
    Schema_Name,
    Table_Name,
    Column_Name,
    Column_Id,
    System_Type_Id,
    Type_Name,
    Max_Length,
    Precision,
    Scale,
    Is_Computed,
    Full_Type_Description
)
SELECT
    DB_NAME(),
    s.name,
    o.name,
    c.name,
    c.column_id,
    c.system_type_id,
    t.name,
    c.max_length,
    c.precision,
    c.scale,
    c.is_computed,
    CASE
        WHEN t.name IN (N''varchar'', N''char'', N''varbinary'', N''binary'', N''nvarchar'', N''nchar'')
            THEN t.name + N''('' + CASE WHEN c.max_length = -1 THEN N''MAX'' ELSE CAST(
                CASE WHEN t.name IN (N''nvarchar'', N''nchar'') THEN c.max_length / 2 ELSE c.max_length END AS NVARCHAR(20)) END + N'')''
        WHEN t.name IN (N''decimal'', N''numeric'')
            THEN t.name + N''('' + CAST(c.precision AS NVARCHAR(10)) + N'','' + CAST(c.scale AS NVARCHAR(10)) + N'')''
        WHEN t.name IN (N''datetime2'', N''datetimeoffset'', N''time'')
            THEN t.name + N''('' + CAST(c.scale AS NVARCHAR(10)) + N'')''
        ELSE t.name
    END
FROM sys.objects AS o
INNER JOIN sys.schemas AS s
    ON o.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON o.object_id = c.object_id
INNER JOIN sys.types AS t
    ON c.user_type_id = t.user_type_id
WHERE o.type IN (N''U'', N''V'')
  AND o.is_ms_shipped = 0;';

    BEGIN TRY
        EXEC sys.sp_executesql
            @sql,
            N'@IncludeEncrypted BIT',
            @IncludeEncrypted = @IncludeEncryptedProcedures;
    END TRY
    BEGIN CATCH
        PRINT 'Skipped database ' + QUOTENAME(@db_name) + ': ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @db_name;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

PRINT 'Analyzing stored procedure definitions (static review)...';

DECLARE
    @sp_db SYSNAME,
    @sp_schema SYSNAME,
    @sp_name SYSNAME,
    @sp_object_id INT,
    @sp_definition NVARCHAR(MAX),
    @normalized NVARCHAR(MAX),
    @search NVARCHAR(MAX),
    @pos INT,
    @match_start INT,
    @left_alias SYSNAME,
    @left_col SYSNAME,
    @right_alias SYSNAME,
    @right_col SYSNAME,
    @left_schema SYSNAME,
    @left_table SYSNAME,
    @right_schema SYSNAME,
    @right_table SYSNAME,
    @left_type NVARCHAR(256),
    @right_type NVARCHAR(256),
    @left_sys INT,
    @right_sys INT,
    @left_len INT,
    @right_len INT,
    @left_prec TINYINT,
    @right_prec TINYINT,
    @left_scale TINYINT,
    @right_scale TINYINT,
    @severity NVARCHAR(20),
    @detail NVARCHAR(4000),
    @context NVARCHAR(1000),
    @token NVARCHAR(400),
    @next_token NVARCHAR(400),
    @clause_pos INT,
    @clause_type NVARCHAR(20),
    @obj_name NVARCHAR(256),
    @alias_name SYSNAME,
    @scan_pos INT,
    @eq_pos INT,
    @pat INT;

DECLARE sp_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT Database_Name, Schema_Name, Procedure_Name, Object_Id, Definition
    FROM #StoredProcedures
    WHERE Definition IS NOT NULL
    ORDER BY Database_Name, Schema_Name, Procedure_Name;

OPEN sp_cursor;
FETCH NEXT FROM sp_cursor INTO @sp_db, @sp_schema, @sp_name, @sp_object_id, @sp_definition;

WHILE @@FETCH_STATUS = 0
BEGIN
    DELETE FROM #TableAliases WHERE Database_Name = @sp_db AND Object_Id = @sp_object_id;

    SET @normalized = UPPER(@sp_definition);
    SET @normalized = REPLACE(REPLACE(REPLACE(REPLACE(@normalized, CHAR(13), N' '), CHAR(10), N' '), CHAR(9), N' '), NCHAR(160), N' ');

    WHILE CHARINDEX(N'/*', @normalized) > 0
    BEGIN
        SET @pos = CHARINDEX(N'/*', @normalized);
        SET @match_start = CHARINDEX(N'*/', @normalized, @pos + 2);
        IF @match_start = 0 BREAK;
        SET @normalized = STUFF(@normalized, @pos, @match_start - @pos + 2, REPLICATE(N' ', @match_start - @pos + 2));
    END;

    WHILE CHARINDEX(N'--', @normalized) > 0
    BEGIN
        SET @pos = CHARINDEX(N'--', @normalized);
        SET @match_start = CHARINDEX(CHAR(10), @normalized, @pos);
        IF @match_start = 0 SET @match_start = LEN(@normalized) + 1;
        SET @normalized = STUFF(@normalized, @pos, @match_start - @pos, REPLICATE(N' ', @match_start - @pos));
    END;

    WHILE CHARINDEX(N'  ', @normalized) > 0
        SET @normalized = REPLACE(@normalized, N'  ', N' ');

    SET @scan_pos = 1;
    WHILE @scan_pos <= LEN(@normalized)
    BEGIN
        SET @clause_pos = NULL;
        SET @clause_type = NULL;

        SET @pat = CHARINDEX(N' FROM ', @normalized, @scan_pos);
        IF @pat > 0 AND (@clause_pos IS NULL OR @pat < @clause_pos)
        BEGIN
            SET @clause_pos = @pat;
            SET @clause_type = N'FROM';
        END;

        SET @pat = CHARINDEX(N' JOIN ', @normalized, @scan_pos);
        IF @pat > 0 AND (@clause_pos IS NULL OR @pat < @clause_pos)
        BEGIN
            SET @clause_pos = @pat;
            SET @clause_type = N'JOIN';
        END;

        IF @clause_pos IS NULL BREAK;

        SET @scan_pos = @clause_pos + CASE @clause_type WHEN N'FROM' THEN 6 ELSE 6 END;
        SET @token = LTRIM(SUBSTRING(@normalized, @scan_pos, 400));

        IF LEFT(@token, 5) = N'INNER' SET @token = LTRIM(SUBSTRING(@token, 6, 400));
        IF LEFT(@token, 4) = N'LEFT' SET @token = LTRIM(SUBSTRING(@token, 5, 400));
        IF LEFT(@token, 5) = N'RIGHT' SET @token = LTRIM(SUBSTRING(@token, 6, 400));
        IF LEFT(@token, 4) = N'FULL' SET @token = LTRIM(SUBSTRING(@token, 5, 400));
        IF LEFT(@token, 5) = N'OUTER' SET @token = LTRIM(SUBSTRING(@token, 6, 400));
        IF LEFT(@token, 5) = N'CROSS' SET @token = LTRIM(SUBSTRING(@token, 6, 400));

        SET @obj_name = NULL;
        SET @alias_name = NULL;

        IF LEFT(@token, 1) = N'['
        BEGIN
            SET @match_start = CHARINDEX(N']', @token);
            IF @match_start > 0
            BEGIN
                SET @obj_name = SUBSTRING(@token, 2, @match_start - 2);
                SET @token = LTRIM(SUBSTRING(@token, @match_start + 1, 400));
            END;
        END
        ELSE
        BEGIN
            SET @match_start = CHARINDEX(N' ', @token + N' ');
            SET @obj_name = LEFT(@token, @match_start - 1);
            SET @token = LTRIM(SUBSTRING(@token, @match_start, 400));
        END;

        IF @obj_name IS NULL OR @obj_name = N''
        BEGIN
            SET @scan_pos = @clause_pos + 5;
            CONTINUE;
        END;

        IF LEFT(@token, 2) = N'AS' SET @token = LTRIM(SUBSTRING(@token, 3, 400));

        IF @token <> N'' AND LEFT(@token, 2) NOT IN (N'ON', N'WI', N'IN', N'LE', N'OU', N'CR', N'SE', N'UP', N'GO', N'UN', N'WH', N'GR', N'HA', N'OR', N')')
        BEGIN
            IF LEFT(@token, 1) = N'['
            BEGIN
                SET @match_start = CHARINDEX(N']', @token);
                SET @alias_name = SUBSTRING(@token, 2, @match_start - 2);
            END
            ELSE
            BEGIN
                SET @match_start = CHARINDEX(N' ', @token + N' ');
                SET @alias_name = LEFT(@token, @match_start - 1);
            END;
        END;

        IF @alias_name IS NULL OR @alias_name IN (N'ON', N'WHERE', N'INNER', N'LEFT', N'RIGHT', N'FULL', N'OUTER', N'CROSS', N'JOIN', N'SET')
            SET @alias_name = PARSENAME(@obj_name, 1);

        IF @alias_name IS NOT NULL AND @alias_name <> N''
        BEGIN
            INSERT INTO #TableAliases (Database_Name, Object_Id, Alias_Name, Schema_Name, Table_Name, Source_Clause)
            SELECT
                @sp_db,
                @sp_object_id,
                @alias_name,
                COALESCE(PARSENAME(@obj_name, 2), N'dbo'),
                PARSENAME(@obj_name, 1),
                @clause_type
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM #TableAliases AS ta
                WHERE ta.Database_Name = @sp_db
                  AND ta.Object_Id = @sp_object_id
                  AND ta.Alias_Name = @alias_name
            );
        END;

        SET @scan_pos = @clause_pos + 5;
    END;

    SET @search = @normalized;
    SET @scan_pos = 1;

    WHILE @scan_pos <= LEN(@search) - 7
    BEGIN
        SET @eq_pos = CHARINDEX(N'=', @search, @scan_pos);
        IF @eq_pos = 0 BREAK;

        SET @left_alias = NULL;
        SET @left_col = NULL;
        SET @right_alias = NULL;
        SET @right_col = NULL;

        SET @pos = @eq_pos - 1;
        WHILE @pos >= 1 AND SUBSTRING(@search, @pos, 1) LIKE N'[A-Z0-9_@#]'
            SET @pos -= 1;
        SET @left_col = SUBSTRING(@search, @pos + 1, @eq_pos - @pos - 1);

        IF @pos < 1 OR SUBSTRING(@search, @pos, 1) <> N'.'
        BEGIN
            SET @scan_pos = @eq_pos + 1;
            CONTINUE;
        END;

        SET @match_start = @pos;
        SET @pos -= 1;
        WHILE @pos >= 1 AND SUBSTRING(@search, @pos, 1) LIKE N'[A-Z0-9_@#]'
            SET @pos -= 1;
        SET @left_alias = SUBSTRING(@search, @pos + 1, @match_start - @pos - 1);

        SET @pos = @eq_pos + 1;
        WHILE @pos <= LEN(@search) AND SUBSTRING(@search, @pos, 1) = N' '
            SET @pos += 1;

        SET @match_start = @pos;
        WHILE @match_start <= LEN(@search) AND SUBSTRING(@search, @match_start, 1) LIKE N'[A-Z0-9_@#]'
            SET @match_start += 1;
        SET @right_alias = SUBSTRING(@search, @pos, @match_start - @pos);

        IF @match_start <= LEN(@search) AND SUBSTRING(@search, @match_start, 1) = N'.'
        BEGIN
            SET @pos = @match_start + 1;
            SET @match_start = @pos;
            WHILE @match_start <= LEN(@search) AND SUBSTRING(@search, @match_start, 1) LIKE N'[A-Z0-9_@#]'
                SET @match_start += 1;
            SET @right_col = SUBSTRING(@search, @pos, @match_start - @pos);
        END;

        IF @left_alias IS NULL OR @left_col IS NULL OR @right_alias IS NULL OR @right_col IS NULL
           OR @left_alias = N'' OR @left_col = N'' OR @right_alias = N'' OR @right_col = N''
        BEGIN
            SET @scan_pos = @eq_pos + 1;
            CONTINUE;
        END;

        SET @left_schema = NULL;
        SET @left_table = NULL;
        SET @right_schema = NULL;
        SET @right_table = NULL;
        SET @left_type = NULL;
        SET @right_type = NULL;
        SET @left_sys = NULL;
        SET @right_sys = NULL;
        SET @left_len = NULL;
        SET @right_len = NULL;
        SET @left_prec = NULL;
        SET @right_prec = NULL;
        SET @left_scale = NULL;
        SET @right_scale = NULL;

        SELECT TOP (1)
            @left_schema = cc.Schema_Name,
            @left_table = cc.Table_Name,
            @left_type = cc.Full_Type_Description,
            @left_sys = cc.System_Type_Id,
            @left_len = cc.Max_Length,
            @left_prec = cc.Precision,
            @left_scale = cc.Scale
        FROM #TableAliases AS ta
        INNER JOIN #ColumnCatalog AS cc
            ON cc.Database_Name = ta.Database_Name
           AND cc.Schema_Name = ta.Schema_Name
           AND cc.Table_Name = ta.Table_Name
           AND cc.Column_Name = @left_col
        WHERE ta.Database_Name = @sp_db
          AND ta.Object_Id = @sp_object_id
          AND ta.Alias_Name = @left_alias;

        IF @left_schema IS NULL
        BEGIN
            SELECT TOP (1)
                @left_schema = cc.Schema_Name,
                @left_table = cc.Table_Name,
                @left_type = cc.Full_Type_Description,
                @left_sys = cc.System_Type_Id,
                @left_len = cc.Max_Length,
                @left_prec = cc.Precision,
                @left_scale = cc.Scale
            FROM #ColumnCatalog AS cc
            WHERE cc.Database_Name = @sp_db
              AND cc.Table_Name = @left_alias
              AND cc.Column_Name = @left_col;
        END;

        SELECT TOP (1)
            @right_schema = cc.Schema_Name,
            @right_table = cc.Table_Name,
            @right_type = cc.Full_Type_Description,
            @right_sys = cc.System_Type_Id,
            @right_len = cc.Max_Length,
            @right_prec = cc.Precision,
            @right_scale = cc.Scale
        FROM #TableAliases AS ta
        INNER JOIN #ColumnCatalog AS cc
            ON cc.Database_Name = ta.Database_Name
           AND cc.Schema_Name = ta.Schema_Name
           AND cc.Table_Name = ta.Table_Name
           AND cc.Column_Name = @right_col
        WHERE ta.Database_Name = @sp_db
          AND ta.Object_Id = @sp_object_id
          AND ta.Alias_Name = @right_alias;

        IF @right_schema IS NULL
        BEGIN
            SELECT TOP (1)
                @right_schema = cc.Schema_Name,
                @right_table = cc.Table_Name,
                @right_type = cc.Full_Type_Description,
                @right_sys = cc.System_Type_Id,
                @right_len = cc.Max_Length,
                @right_prec = cc.Precision,
                @right_scale = cc.Scale
            FROM #ColumnCatalog AS cc
            WHERE cc.Database_Name = @sp_db
              AND cc.Table_Name = @right_alias
              AND cc.Column_Name = @right_col;
        END;

        IF @left_schema IS NOT NULL AND @right_schema IS NOT NULL
           AND NOT (@left_sys = @right_sys AND @left_len = @right_len AND @left_prec = @right_prec AND @left_scale = @right_scale)
        BEGIN
            SET @severity = N'Medium';
            SET @detail = N'Column comparison ' + @left_alias + N'.' + @left_col + N' (' + @left_type + N') = '
                + @right_alias + N'.' + @right_col + N' (' + @right_type + N') may cause implicit conversion and prevent efficient index usage.';

            IF (@left_sys IN (167, 175, 231, 239) AND @right_sys IN (48, 52, 56, 127, 106, 62, 59, 60, 61, 40, 41, 42, 43, 58))
             OR (@right_sys IN (167, 175, 231, 239) AND @left_sys IN (48, 52, 56, 127, 106, 62, 59, 60, 61, 40, 41, 42, 43, 58))
                SET @severity = N'Critical';
            ELSE IF (@left_sys = 167 AND @right_sys = 231) OR (@left_sys = 231 AND @right_sys = 167)
                 OR (@left_sys = 175 AND @right_sys = 239) OR (@left_sys = 239 AND @right_sys = 175)
                 OR (@left_sys = 167 AND @right_sys = 175) OR (@left_sys = 175 AND @right_sys = 167)
                SET @severity = N'High';
            ELSE IF (@left_sys IN (48, 52, 56) AND @right_sys IN (48, 52, 56, 127))
                  OR (@right_sys IN (48, 52, 56) AND @left_sys IN (48, 52, 56, 127))
                SET @severity = N'Medium';
            ELSE IF (@left_sys IN (61, 42, 40, 58) AND @right_sys IN (61, 42, 40, 58))
                 AND (@left_sys <> @right_sys)
                SET @severity = N'Medium';

            SET @context = @left_alias + N'.' + @left_col + N' = ' + @right_alias + N'.' + @right_col;

            IF NOT EXISTS
            (
                SELECT 1
                FROM #Findings AS f
                WHERE f.Database_Name = @sp_db
                  AND f.Object_Id = @sp_object_id
                  AND f.Issue_Code = N'JOIN_COLUMN_TYPE_MISMATCH'
                  AND f.Left_Object = @left_schema + N'.' + @left_table + N'.' + @left_col
                  AND f.Right_Object = @right_schema + N'.' + @right_table + N'.' + @right_col
            )
            BEGIN
                INSERT INTO #Findings
                (
                    Database_Name, Schema_Name, Procedure_Name, Object_Id,
                    Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation,
                    Source_Context, Left_Object, Left_Data_Type, Right_Object, Right_Data_Type
                )
                VALUES
                (
                    @sp_db, @sp_schema, @sp_name, @sp_object_id,
                    N'JOIN_TYPE_MISMATCH', N'JOIN_COLUMN_TYPE_MISMATCH', @severity,
                    N'Join/WHERE column data type mismatch',
                    @detail,
                    N'Alter one column or add explicit CONVERT/CAST on the non-indexed side so both sides share the same type, length, and precision. Prefer aligning table schema over wrapping indexed columns.',
                    @context,
                    @left_schema + N'.' + @left_table + N'.' + @left_col,
                    @left_type,
                    @right_schema + N'.' + @right_table + N'.' + @right_col,
                    @right_type
                );
            END;
        END;

        SET @scan_pos = @eq_pos + 1;
    END;

    IF @normalized LIKE N'%DECLARE%CURSOR%' OR @normalized LIKE N'%OPEN %' AND @normalized LIKE N'%FETCH %' AND @normalized LIKE N'%DEALLOCATE %'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'CURSOR_USAGE', N'High',
            N'Cursor-based processing detected',
            N'Cursors process rows one at a time and usually perform far worse than set-based T-SQL.',
            N'Refactor to set-based INSERT/UPDATE/DELETE/MERGE or window functions. If a cursor is unavoidable, use LOCAL FAST_FORWARD and keep scope minimal.');
    END;

    IF @normalized LIKE N'%WHILE %' OR @normalized LIKE N'% WHILE(%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'WHILE_LOOP', N'Medium',
            N'WHILE loop detected',
            N'Row-by-row or iterative loops often scale poorly compared with set-based operations.',
            N'Review whether the loop can be replaced with a single set-based statement or batch operation.');
    END;

    IF @normalized LIKE N'%SELECT %* %' AND @normalized NOT LIKE N'%COUNT(%*%' AND @normalized NOT LIKE N'%EXISTS(SELECT%*%' 
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'SELECT_STAR', N'Medium',
            N'SELECT * usage detected',
            N'SELECT * retrieves unused columns, increases memory grants, breaks covering indexes, and makes plans fragile when schema changes.',
            N'List required columns explicitly.');
    END;

    IF @normalized LIKE N'%(NOLOCK)%' OR @normalized LIKE N'% WITH (NOLOCK)%' OR @normalized LIKE N'%READ UNCOMMITTED%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'NOLOCK_HINT', N'High',
            N'NOLOCK / READ UNCOMMITTED detected',
            N'Dirty reads, non-repeatable reads, and missed rows are possible. This also complicates troubleshooting and can hide blocking root causes.',
            N'Remove NOLOCK unless the business explicitly accepts inconsistent reads. Prefer READ COMMITTED SNAPSHOT isolation where readers block writers.');
    END;

    IF @normalized LIKE N'%@@IDENTITY%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'AT_IDENTITY', N'Medium',
            N'@@IDENTITY used instead of SCOPE_IDENTITY()',
            N'@@IDENTITY returns the last identity from any scope and can capture identity values from triggers or other sessions.',
            N'Use SCOPE_IDENTITY() or OUTPUT clause to capture inserted keys safely.');
    END;

    IF @normalized LIKE N'% CROSS JOIN %'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'CROSS_JOIN', N'High',
            N'CROSS JOIN detected',
            N'Cartesian products multiply row counts and are rarely intended in production procedures.',
            N'Add an explicit join predicate or replace with INNER/LEFT JOIN. If intentional, document and constrain input cardinality.');
    END;

    IF @normalized LIKE N'% NOT IN (%' OR @normalized LIKE N'% NOT IN(%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'NOT_IN_SUBQUERY', N'Medium',
            N'NOT IN (subquery) detected',
            N'NOT IN returns unknown when the subquery contains NULL, often producing incorrect results. It can also generate poor plans versus NOT EXISTS.',
            N'Replace with NOT EXISTS or LEFT JOIN ... IS NULL pattern.');
    END;

    IF @normalized LIKE N'% LIKE ''%%' OR @normalized LIKE N'% LIKE N''%%' OR @normalized LIKE N'% LIKE ''%[%]%' OR @normalized LIKE N'% LIKE N''%[%]%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'LEADING_WILDCARD_LIKE', N'High',
            N'Leading wildcard LIKE predicate detected',
            N'Predicates such as LIKE ''%value'' are non-SARGable and typically force scans.',
            N'Use full-text search, persisted computed columns, or redesign filtering to avoid leading wildcards.');
    END;

    IF @normalized LIKE N'%WHERE %CONVERT(%' OR @normalized LIKE N'% AND %CONVERT(%'
       OR @normalized LIKE N'%WHERE %CAST(%' OR @normalized LIKE N'% AND %CAST(%'
       OR @normalized LIKE N'%ON %CONVERT(%' OR @normalized LIKE N'%ON %CAST(%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'FUNCTION_ON_PREDICATE', N'High',
            N'CONVERT/CAST found in predicate context',
            N'Applying functions or conversions to a column in WHERE/ON clauses usually prevents index seeks.',
            N'Convert the parameter/literal instead of the column, or persist a computed column with an index.');
    END;

    IF @normalized LIKE N'%WHERE %ISNULL(%' OR @normalized LIKE N'% AND %ISNULL(%'
       OR @normalized LIKE N'%WHERE %COALESCE(%' OR @normalized LIKE N'% AND %COALESCE(%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'ISNULL_ON_PREDICATE', N'Medium',
            N'ISNULL/COALESCE on column in predicate',
            N'Wrapping columns with ISNULL/COALESCE in filters often blocks index usage and skews cardinality estimates.',
            N'Rewrite to explicit OR logic with separate predicates or use filtered indexes for known NULL patterns.');
    END;

    IF @normalized LIKE N'%EXEC(%' OR @normalized LIKE N'% EXEC @%' OR @normalized LIKE N'%SP_EXECUTESQL%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'DYNAMIC_SQL', N'Info',
            N'Dynamic SQL detected',
            N'Dynamic SQL can prevent plan reuse, hide implicit conversions from static analysis, and increase SQL injection risk if inputs are concatenated.',
            N'Use sp_executesql with typed parameters, avoid string concatenation of user input, and consider Query Store for runtime review.');
    END;

    IF @normalized LIKE N'% DISTINCT %' AND @normalized NOT LIKE N'SELECT DISTINCT COUNT%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'DISTINCT_USAGE', N'Low',
            N'SELECT DISTINCT detected',
            N'DISTINCT often hides duplicate-causing join logic and adds sort/hash overhead.',
            N'Fix join keys or GROUP BY intentionally instead of using DISTINCT as a band-aid.');
    END;

    IF @normalized LIKE N'%TOP %' AND @normalized NOT LIKE N'%ORDER BY%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'TOP_WITHOUT_ORDER_BY', N'Medium',
            N'TOP without ORDER BY detected',
            N'Without ORDER BY, TOP returns an arbitrary row set which can vary between executions.',
            N'Add an explicit ORDER BY that reflects the intended business ordering.');
    END;

    IF @normalized NOT LIKE N'%NOCOUNT ON%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'MISSING_NOCOUNT_ON', N'Low',
            N'SET NOCOUNT ON not found',
            N'Procedures that leave NOCOUNT OFF send extra DONE_IN_PROC messages to clients and can inflate network traffic.',
            N'Add SET NOCOUNT ON near the beginning of the procedure.');
    END;

    IF @normalized LIKE N'%ORDER BY 1%' OR @normalized LIKE N'%ORDER BY 2%' OR @normalized LIKE N'%ORDER BY 3%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'ORDER_BY_ORDINAL', N'Low',
            N'ORDER BY ordinal position detected',
            N'Ordering by column position is fragile when SELECT lists change.',
            N'Order by explicit column names or aliases.');
    END;

    IF @normalized LIKE N'%OPTION (RECOMPILE)%' OR @normalized LIKE N'%OPTION(RECOMPILE)%'
    BEGIN
        INSERT INTO #Findings (Database_Name, Schema_Name, Procedure_Name, Object_Id, Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation)
        VALUES (@sp_db, @sp_schema, @sp_name, @sp_object_id, N'STATIC_ANTIPATTERN', N'OPTION_RECOMPILE', N'Info',
            N'OPTION (RECOMPILE) detected',
            N'Per-execution recompile can solve parameter sniffing but adds CPU overhead on every call.',
            N'Validate this is intentional. Consider OPTIMIZE FOR, filtered indexes, or Query Store baselines as alternatives.');
    END;

    FETCH NEXT FROM sp_cursor INTO @sp_db, @sp_schema, @sp_name, @sp_object_id, @sp_definition;
END;

CLOSE sp_cursor;
DEALLOCATE sp_cursor;

IF @IncludeRuntimePlanAnalysis = 1
BEGIN
    PRINT 'Scanning plan cache for runtime implicit conversions by stored procedure...';

    ;WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'),
    RuntimeConversions AS
    (
        SELECT
            sp.Database_Name,
            sp.Schema_Name,
            sp.Procedure_Name,
            sp.Object_Id,
            qs.execution_count,
            qs.total_worker_time / 1000 AS Total_CPU_ms,
            qs.last_execution_time,
            conversion_node.n.value('@ScalarString[1]', 'NVARCHAR(4000)') AS Conversion_Expression,
            NULLIF(REPLACE(REPLACE(conversion_node.n.value('(descendant::ColumnReference[1]/@Database)[1]', 'NVARCHAR(258)'), N'[', N''), N']', N''), N'') AS Referenced_Column_Database,
            NULLIF(REPLACE(REPLACE(conversion_node.n.value('(descendant::ColumnReference[1]/@Schema)[1]', 'NVARCHAR(258)'), N'[', N''), N']', N''), N'') AS Referenced_Column_Schema,
            NULLIF(REPLACE(REPLACE(conversion_node.n.value('(descendant::ColumnReference[1]/@Table)[1]', 'NVARCHAR(258)'), N'[', N''), N']', N''), N'') AS Referenced_Column_Table,
            NULLIF(REPLACE(REPLACE(conversion_node.n.value('(descendant::ColumnReference[1]/@Column)[1]', 'NVARCHAR(258)'), N'[', N''), N']', N''), N'') AS Referenced_Column_Name,
            SUBSTRING(
                st.text,
                (qs.statement_start_offset / 2) + 1,
                ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1
            ) AS Statement_Text,
            ROW_NUMBER() OVER (
                PARTITION BY sp.Database_Name, sp.Object_Id, conversion_node.n.value('@ScalarString[1]', 'NVARCHAR(4000)')
                ORDER BY qs.total_worker_time DESC
            ) AS Row_Num
        FROM sys.dm_exec_query_stats AS qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
        INNER JOIN #StoredProcedures AS sp
            ON st.dbid = DB_ID(sp.Database_Name)
           AND st.objectid = sp.Object_Id
        CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
        CROSS APPLY
        (
            SELECT qp.query_plan
            WHERE qp.query_plan IS NOT NULL
              AND qp.query_plan.exist('//ScalarOperator[contains(@ScalarString, "CONVERT_IMPLICIT")]') = 1
        ) AS filtered_plan
        CROSS APPLY filtered_plan.query_plan.nodes('//ScalarOperator[contains(@ScalarString, "CONVERT_IMPLICIT")]') AS conversion_node(n)
    )
    INSERT INTO #Findings
    (
        Database_Name, Schema_Name, Procedure_Name, Object_Id,
        Finding_Category, Issue_Code, Severity, Issue_Title, Issue_Detail, Recommendation,
        Source_Context, Left_Object, Left_Data_Type, Runtime_Execution_Count, Runtime_Total_CPU_ms, Runtime_Last_Execution
    )
    SELECT
        rc.Database_Name,
        rc.Schema_Name,
        rc.Procedure_Name,
        rc.Object_Id,
        N'RUNTIME_IMPLICIT_CONVERSION',
        N'PLAN_CACHE_CONVERT_IMPLICIT',
        CASE WHEN rc.Conversion_Expression LIKE N'%CONVERT_IMPLICIT%' THEN N'High' ELSE N'Medium' END,
        N'Runtime implicit conversion in cached plan',
        N'Execution plan contains CONVERT_IMPLICIT on '
            + COALESCE(rc.Referenced_Column_Schema + N'.' + rc.Referenced_Column_Table + N'.' + rc.Referenced_Column_Name, N'<column not resolved>')
            + N'. Expression: ' + rc.Conversion_Expression,
        N'Match parameter, variable, and join column data types. Avoid converting indexed columns. Recompile and compare plans after schema or parameter changes.',
        LEFT(COALESCE(rc.Statement_Text, N''), 1000),
        COALESCE(rc.Referenced_Column_Schema + N'.' + rc.Referenced_Column_Table + N'.' + rc.Referenced_Column_Name, NULL),
        rc.Conversion_Expression,
        rc.execution_count,
        rc.Total_CPU_ms,
        rc.last_execution_time
    FROM RuntimeConversions AS rc
    WHERE rc.Row_Num <= @RuntimePlanTopPerProc;
END;

DECLARE @MinRank TINYINT = CASE @MinSeverityFilter
    WHEN 4 THEN 4
    WHEN 3 THEN 3
    WHEN 2 THEN 2
    ELSE 0
END;

PRINT '';
PRINT '================================================================';
PRINT 'Result Set 1: Stored Procedure Audit Summary';
PRINT '================================================================';

SELECT
    sp.Database_Name,
    sp.Schema_Name,
    sp.Procedure_Name,
    sp.Object_Id,
    sp.Definition_Length,
    sp.Parameter_Count,
    sp.Create_Date,
    sp.Modify_Date,
    CASE WHEN sp.Is_Encrypted = 1 THEN N'Yes' ELSE N'No' END AS [Is_Encrypted],
    COALESCE(SUM(CASE WHEN sr.RankValue = 4 THEN 1 END), 0) AS [Critical_Findings],
    COALESCE(SUM(CASE WHEN sr.RankValue = 3 THEN 1 END), 0) AS [High_Findings],
    COALESCE(SUM(CASE WHEN sr.RankValue = 2 THEN 1 END), 0) AS [Medium_Findings],
    COALESCE(SUM(CASE WHEN sr.RankValue = 1 THEN 1 END), 0) AS [Low_Findings],
    COALESCE(SUM(CASE WHEN sr.RankValue = 0 THEN 1 END), 0) AS [Info_Findings],
    COALESCE(COUNT(f.Finding_Id), 0) AS [Total_Findings],
    COALESCE(SUM(CASE WHEN f.Finding_Category = N'JOIN_TYPE_MISMATCH' THEN 1 END), 0) AS [Join_Type_Mismatch_Count],
    COALESCE(SUM(CASE WHEN f.Finding_Category = N'STATIC_ANTIPATTERN' THEN 1 END), 0) AS [Static_Antipattern_Count],
    COALESCE(SUM(CASE WHEN f.Finding_Category = N'RUNTIME_IMPLICIT_CONVERSION' THEN 1 END), 0) AS [Runtime_Conversion_Count],
    CASE
        WHEN sp.Definition IS NULL THEN N'Encrypted or unavailable definition — static review skipped'
        WHEN COALESCE(COUNT(f.Finding_Id), 0) = 0 THEN N'No findings at selected severity threshold'
        ELSE N'Review detailed result sets below'
    END AS [Review_Status]
FROM #StoredProcedures AS sp
LEFT JOIN #Findings AS f
    ON f.Database_Name = sp.Database_Name
   AND f.Object_Id = sp.Object_Id
LEFT JOIN #SeverityRank AS sr
    ON sr.Severity = f.Severity
WHERE sp.Is_Encrypted = 0 OR @IncludeEncryptedProcedures = 1
GROUP BY
    sp.Database_Name,
    sp.Schema_Name,
    sp.Procedure_Name,
    sp.Object_Id,
    sp.Definition_Length,
    sp.Parameter_Count,
    sp.Create_Date,
    sp.Modify_Date,
    sp.Is_Encrypted,
    sp.Definition
HAVING COALESCE(MAX(sr.RankValue), 0) >= @MinRank OR COALESCE(COUNT(f.Finding_Id), 0) = 0
ORDER BY
    COALESCE(SUM(CASE WHEN sr.RankValue = 4 THEN 1 END), 0) DESC,
    COALESCE(SUM(CASE WHEN sr.RankValue = 3 THEN 1 END), 0) DESC,
    COALESCE(COUNT(f.Finding_Id), 0) DESC,
    sp.Database_Name,
    sp.Schema_Name,
    sp.Procedure_Name;

PRINT '';
PRINT '================================================================';
PRINT 'Result Set 2: Join / Column Type Mismatch Details';
PRINT '================================================================';

SELECT
    f.Database_Name,
    f.Schema_Name,
    f.Procedure_Name,
    f.Severity,
    f.Left_Object,
    f.Left_Data_Type,
    f.Right_Object,
    f.Right_Data_Type,
    f.Issue_Detail,
    f.Recommendation,
    f.Source_Context
FROM #Findings AS f
INNER JOIN #SeverityRank AS sr
    ON sr.Severity = f.Severity
WHERE f.Finding_Category = N'JOIN_TYPE_MISMATCH'
  AND sr.RankValue >= @MinRank
ORDER BY sr.RankValue DESC, f.Database_Name, f.Schema_Name, f.Procedure_Name, f.Left_Object;

PRINT '';
PRINT '================================================================';
PRINT 'Result Set 3: Static Anti-Pattern Details';
PRINT '================================================================';

SELECT
    f.Database_Name,
    f.Schema_Name,
    f.Procedure_Name,
    f.Severity,
    f.Issue_Code,
    f.Issue_Title,
    f.Issue_Detail,
    f.Recommendation
FROM #Findings AS f
INNER JOIN #SeverityRank AS sr
    ON sr.Severity = f.Severity
WHERE f.Finding_Category = N'STATIC_ANTIPATTERN'
  AND sr.RankValue >= @MinRank
ORDER BY sr.RankValue DESC, f.Database_Name, f.Schema_Name, f.Procedure_Name, f.Issue_Code;

PRINT '';
PRINT '================================================================';
PRINT 'Result Set 4: Runtime Implicit Conversion Details (Plan Cache)';
PRINT '================================================================';

SELECT
    f.Database_Name,
    f.Schema_Name,
    f.Procedure_Name,
    f.Severity,
    f.Left_Object AS [Affected_Column],
    f.Left_Data_Type AS [Conversion_Expression],
    f.Runtime_Execution_Count,
    f.Runtime_Total_CPU_ms,
    f.Runtime_Last_Execution,
    f.Source_Context AS [Statement_Text],
    f.Issue_Detail,
    f.Recommendation
FROM #Findings AS f
INNER JOIN #SeverityRank AS sr
    ON sr.Severity = f.Severity
WHERE f.Finding_Category = N'RUNTIME_IMPLICIT_CONVERSION'
  AND sr.RankValue >= @MinRank
ORDER BY f.Runtime_Total_CPU_ms DESC, f.Database_Name, f.Schema_Name, f.Procedure_Name;

PRINT '';
PRINT '================================================================';
PRINT 'Result Set 5: Issue Code Reference';
PRINT '================================================================';

SELECT *
FROM
(
    VALUES
        (N'JOIN_COLUMN_TYPE_MISMATCH', N'JOIN_TYPE_MISMATCH', N'Critical/High/Medium', N'Join or WHERE equality compares two columns with different data types'),
        (N'PLAN_CACHE_CONVERT_IMPLICIT', N'RUNTIME_IMPLICIT_CONVERSION', N'High', N'Cached execution plan shows CONVERT_IMPLICIT for this procedure'),
        (N'CURSOR_USAGE', N'STATIC_ANTIPATTERN', N'High', N'Cursor detected in procedure body'),
        (N'WHILE_LOOP', N'STATIC_ANTIPATTERN', N'Medium', N'WHILE loop detected'),
        (N'SELECT_STAR', N'STATIC_ANTIPATTERN', N'Medium', N'SELECT * detected'),
        (N'NOLOCK_HINT', N'STATIC_ANTIPATTERN', N'High', N'NOLOCK or READ UNCOMMITTED hint detected'),
        (N'AT_IDENTITY', N'STATIC_ANTIPATTERN', N'Medium', N'@@IDENTITY used'),
        (N'CROSS_JOIN', N'STATIC_ANTIPATTERN', N'High', N'CROSS JOIN detected'),
        (N'NOT_IN_SUBQUERY', N'STATIC_ANTIPATTERN', N'Medium', N'NOT IN (subquery) detected'),
        (N'LEADING_WILDCARD_LIKE', N'STATIC_ANTIPATTERN', N'High', N'LIKE with leading wildcard detected'),
        (N'FUNCTION_ON_PREDICATE', N'STATIC_ANTIPATTERN', N'High', N'CONVERT/CAST applied in predicate context'),
        (N'ISNULL_ON_PREDICATE', N'STATIC_ANTIPATTERN', N'Medium', N'ISNULL/COALESCE applied in predicate context'),
        (N'DYNAMIC_SQL', N'STATIC_ANTIPATTERN', N'Info', N'Dynamic SQL detected'),
        (N'DISTINCT_USAGE', N'STATIC_ANTIPATTERN', N'Low', N'SELECT DISTINCT detected'),
        (N'TOP_WITHOUT_ORDER_BY', N'STATIC_ANTIPATTERN', N'Medium', N'TOP without ORDER BY detected'),
        (N'MISSING_NOCOUNT_ON', N'STATIC_ANTIPATTERN', N'Low', N'SET NOCOUNT ON not found'),
        (N'ORDER_BY_ORDINAL', N'STATIC_ANTIPATTERN', N'Low', N'ORDER BY ordinal detected'),
        (N'OPTION_RECOMPILE', N'STATIC_ANTIPATTERN', N'Info', N'OPTION (RECOMPILE) detected')
) AS ref(Issue_Code, Finding_Category, Default_Severity, Description)
ORDER BY Finding_Category, Default_Severity DESC, Issue_Code;

IF OBJECT_ID(N'tempdb..#Findings') IS NOT NULL DROP TABLE #Findings;
IF OBJECT_ID(N'tempdb..#TableAliases') IS NOT NULL DROP TABLE #TableAliases;
IF OBJECT_ID(N'tempdb..#ColumnCatalog') IS NOT NULL DROP TABLE #ColumnCatalog;
IF OBJECT_ID(N'tempdb..#StoredProcedures') IS NOT NULL DROP TABLE #StoredProcedures;
IF OBJECT_ID(N'tempdb..#SeverityRank') IS NOT NULL DROP TABLE #SeverityRank;
IF OBJECT_ID(N'tempdb..#DbTargets') IS NOT NULL DROP TABLE #DbTargets;

PRINT '';
PRINT 'Stored procedure performance audit complete.';
