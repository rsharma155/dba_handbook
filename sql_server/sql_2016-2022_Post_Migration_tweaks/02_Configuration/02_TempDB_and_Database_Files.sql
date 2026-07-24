/*
================================================================================
02_TempDB_and_Database_Files.sql
Purpose : TempDB and user DB file layout best practices on SQL 2022.
================================================================================
*/
SET NOCOUNT ON;

PRINT '=== Current TempDB layout ===';
SELECT
    file_id, type_desc, name,
    size*8/1024 AS size_mb,
    growth AS growth_pages_or_pct,
    is_percent_growth,
    physical_name
FROM tempdb.sys.database_files;

DECLARE @cpus int = (SELECT cpu_count FROM sys.dm_os_sys_info);
DECLARE @tempdb_files int = CASE WHEN @cpus >= 8 THEN 8 ELSE @cpus END;

SELECT
    @cpus AS logical_cpus,
    @tempdb_files AS recommended_tempdb_data_files,
    N'Equal size, equal growth (MB not %), pre-size to avoid autogrowth storms' AS guidance;

/*
EXAMPLE: resize / add TempDB files (edit paths & sizes)
--- Run during maintenance window ---

USE master;
ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev, SIZE = 8192MB, FILEGROWTH = 512MB);
ALTER DATABASE tempdb MODIFY FILE (NAME = templog, SIZE = 2048MB, FILEGROWTH = 256MB);

-- Add files if you only have 1 data file (example for 8 files total)
ALTER DATABASE tempdb ADD FILE (NAME = tempdev2, FILENAME = 'T:\TempDB\tempdev2.ndf', SIZE = 8192MB, FILEGROWTH = 512MB);
ALTER DATABASE tempdb ADD FILE (NAME = tempdev3, FILENAME = 'T:\TempDB\tempdev3.ndf', SIZE = 8192MB, FILEGROWTH = 512MB);
ALTER DATABASE tempdb ADD FILE (NAME = tempdev4, FILENAME = 'T:\TempDB\tempdev4.ndf', SIZE = 8192MB, FILEGROWTH = 512MB);
ALTER DATABASE tempdb ADD FILE (NAME = tempdev5, FILENAME = 'T:\TempDB\tempdev5.ndf', SIZE = 8192MB, FILEGROWTH = 512MB);
ALTER DATABASE tempdb ADD FILE (NAME = tempdev6, FILENAME = 'T:\TempDB\tempdev6.ndf', SIZE = 8192MB, FILEGROWTH = 512MB);
ALTER DATABASE tempdb ADD FILE (NAME = tempdev7, FILENAME = 'T:\TempDB\tempdev7.ndf', SIZE = 8192MB, FILEGROWTH = 512MB);
ALTER DATABASE tempdb ADD FILE (NAME = tempdev8, FILENAME = 'T:\TempDB\tempdev8.ndf', SIZE = 8192MB, FILEGROWTH = 512MB);
-- Restart SQL Server for all TempDB file count changes to fully stabilize (recommended).
*/

PRINT '=== User DB files with percent growth (fix these) ===';
SELECT DB_NAME(database_id) AS db_name, name, type_desc, growth, is_percent_growth, physical_name
FROM sys.master_files
WHERE is_percent_growth = 1
ORDER BY db_name;
