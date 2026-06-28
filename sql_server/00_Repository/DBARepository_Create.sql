/*
================================================================================
DBARepository_Create.sql - Create the dedicated DBA administration database
================================================================================
Purpose:
    Central database for all DBA framework objects, assessment history, and
    baseline snapshots. Deploy once per SQL Server instance.

Usage:
    Execute this script in the context of master or a suitable admin database.
    Then run DBARepository_Deploy.sql to install stored procedures and tables.
================================================================================
*/
IF DB_ID(N'DBARepository') IS NOT NULL
BEGIN
    PRINT N'Database DBARepository already exists. Skipping creation.';
    RETURN;
END;
GO

CREATE DATABASE DBARepository;
GO

ALTER DATABASE DBARepository SET RECOVERY SIMPLE;
GO

ALTER DATABASE DBARepository SET PAGE_VERIFY CHECKSUM;
GO

ALTER DATABASE DBARepository SET AUTO_SHRINK OFF;
GO

ALTER DATABASE DBARepository SET AUTO_CLOSE OFF;
GO

PRINT N'Database DBARepository created successfully.';
GO
