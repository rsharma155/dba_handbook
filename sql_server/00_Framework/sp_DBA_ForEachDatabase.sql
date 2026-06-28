/*
================================================================================
sp_DBA_ForEachDatabase - Standard cross-database execution helper
================================================================================
Description:
    Executes a SQL batch in each selected database context with QUOTENAME safety
    and optional error isolation.

Parameters:
    @Command            SQL batch to run after USE [database]. Use ? in @Command
                        only when you need the bare database name token replaced.
    @UserDatabasesOnly  When 1, skips master/tempdb/model/msdb (database_id <= 4)
    @IncludeReadOnly    When 0, skips read-only databases
    @DatabaseList       Comma-separated database names (overrides default selection)
    @ExcludeList        Comma-separated database names to skip
    @PrintOnly          When 1, prints commands instead of executing
    @ContinueOnError    When 1, logs errors and continues to next database

Usage:
    EXEC dbo.sp_DBA_ForEachDatabase
        @Command = N'SELECT DB_NAME() AS database_name, COUNT(*) AS user_tables FROM sys.tables WHERE type = ''U'';',
        @UserDatabasesOnly = 1;

    EXEC dbo.sp_DBA_ForEachDatabase
        @Command = N'SELECT * FROM sys.database_files;',
        @DatabaseList = N'AdventureWorks,SalesDB';
================================================================================
*/
IF OBJECT_ID(N'dbo.sp_DBA_ForEachDatabase', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.sp_DBA_ForEachDatabase AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_DBA_ForEachDatabase
    @Command            NVARCHAR(MAX),
    @UserDatabasesOnly  BIT = 1,
    @IncludeReadOnly    BIT = 0,
    @DatabaseList       NVARCHAR(MAX) = NULL,
    @ExcludeList        NVARCHAR(MAX) = NULL,
    @PrintOnly          BIT = 0,
    @ContinueOnError    BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @Command IS NULL OR LTRIM(RTRIM(@Command)) = N''
    BEGIN
        RAISERROR('sp_DBA_ForEachDatabase: @Command cannot be empty.', 16, 1);
        RETURN;
    END;

    DECLARE @DatabaseName SYSNAME;
    DECLARE @ExecSQL NVARCHAR(MAX);
    DECLARE @ErrMsg NVARCHAR(4000);
    DECLARE @ErrNum INT;
    DECLARE @ErrLine INT;

  IF OBJECT_ID('tempdb..#DBAList') IS NOT NULL DROP TABLE #DBAList;
    CREATE TABLE #DBAList (database_id INT NOT NULL PRIMARY KEY, database_name SYSNAME NOT NULL);

    IF @DatabaseList IS NOT NULL AND LTRIM(RTRIM(@DatabaseList)) <> N''
    BEGIN
        INSERT INTO #DBAList (database_id, database_name)
        SELECT d.database_id, d.name
        FROM sys.databases AS d
        INNER JOIN (
            SELECT LTRIM(RTRIM(value)) AS database_name
            FROM STRING_SPLIT(@DatabaseList, N',')
            WHERE LTRIM(RTRIM(value)) <> N''
        ) AS requested ON requested.database_name = d.name
        WHERE d.state = 0
          AND d.is_in_standby = 0;
    END
    ELSE
    BEGIN
        INSERT INTO #DBAList (database_id, database_name)
        SELECT d.database_id, d.name
        FROM sys.databases AS d
        WHERE d.state = 0
          AND d.is_in_standby = 0
          AND (@UserDatabasesOnly = 0 OR d.database_id > 4)
          AND (@IncludeReadOnly = 1 OR d.is_read_only = 0);
    END;

    IF @ExcludeList IS NOT NULL AND LTRIM(RTRIM(@ExcludeList)) <> N''
    BEGIN
        DELETE l
        FROM #DBAList AS l
        INNER JOIN (
            SELECT LTRIM(RTRIM(value)) AS database_name
            FROM STRING_SPLIT(@ExcludeList, N',')
            WHERE LTRIM(RTRIM(value)) <> N''
        ) AS excluded ON excluded.database_name = l.database_name;
    END;

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name FROM #DBAList ORDER BY database_name;

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DatabaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @ExecSQL = N'USE ' + QUOTENAME(@DatabaseName) + N'; '
                     + REPLACE(@Command, N'?', @DatabaseName);

        IF @PrintOnly = 1
        BEGIN
            PRINT N'-- Database: ' + @DatabaseName;
            PRINT @ExecSQL;
            PRINT N'GO';
        END
        ELSE
        BEGIN
            BEGIN TRY
                EXEC sys.sp_executesql @ExecSQL;
            END TRY
            BEGIN CATCH
                SET @ErrNum = ERROR_NUMBER();
                SET @ErrLine = ERROR_LINE();
                SET @ErrMsg = ERROR_MESSAGE();

                IF @ContinueOnError = 1
                BEGIN
                    RAISERROR(
                        N'sp_DBA_ForEachDatabase: Database [%s] failed (Error %d, Line %d): %s',
                        10, 1, @DatabaseName, @ErrNum, @ErrLine, @ErrMsg
                    );
                END
                ELSE
                BEGIN
                    CLOSE db_cursor;
                    DEALLOCATE db_cursor;
                    DROP TABLE #DBAList;
                    THROW;
                END;
            END CATCH;
        END;

        FETCH NEXT FROM db_cursor INTO @DatabaseName;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;
    DROP TABLE #DBAList;
END;
GO
