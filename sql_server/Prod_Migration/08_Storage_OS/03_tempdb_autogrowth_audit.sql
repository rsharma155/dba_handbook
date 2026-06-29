/*
================================================================================
TempDB Configuration and Autogrowth Audit
================================================================================
Purpose:
    TempDB misconfiguration is a top cause of PAGELATCH_* waits after upgrading
    from Express (limited cores) to Developer (more parallelism).

Checks:
    (1) TempDB data file count vs CPU count
    (2) Equal file sizes
    (3) Autogrowth settings (fixed MB vs percent)
    (4) TempDB version store / user object usage
    (5) Free space in tempdb

Remediation:
    - 1 tempdb data file per CPU up to 8, equal size
    - Fixed growth in MB (64-256), not percent
    - Pre-size tempdb to avoid autogrowth during business hours

Next if tempdb looks OK:
    04_Wait_Stats/03_latch_metadata_waits.sql for non-tempdb latches

Criticality: High after edition upgrade with more cores
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @CPU INT = (SELECT cpu_count FROM sys.dm_os_sys_info);
DECLARE @RecommendedFiles INT = CASE WHEN @CPU > 8 THEN 8 ELSE @CPU END;
DECLARE @DataFiles INT = (SELECT COUNT(*) FROM tempdb.sys.database_files WHERE type = 0);

PRINT '=== TEMPDB FILE LAYOUT ===';
SELECT
    file_id,
    name,
    physical_name,
    size * 8 / 1024 AS [Size_MB],
    growth AS [Growth_Value],
    is_percent_growth,
    CASE is_percent_growth WHEN 1 THEN N'WARNING: Percent growth causes uneven files' ELSE N'OK' END AS [Growth_Status]
FROM tempdb.sys.database_files
ORDER BY type_desc, file_id;

PRINT '=== FILE COUNT vs CPU ===';
SELECT
    @CPU AS [Logical_CPUs],
    @DataFiles AS [TempDB_Data_Files],
    @RecommendedFiles AS [Recommended_Files],
    CASE
        WHEN @DataFiles = 1 AND @CPU > 4 THEN N'CRITICAL: Single tempdb file on multi-core — add files'
        WHEN @DataFiles < @RecommendedFiles THEN N'WARNING: Add more equal-sized data files'
        ELSE N'OK'
    END AS [Status];

PRINT '=== TEMPDB SPACE USAGE ===';
SELECT
    SUM(unallocated_extent_page_count) * 8 / 1024 AS [Free_Space_MB],
    SUM(user_object_reserved_page_count) * 8 / 1024 AS [User_Objects_MB],
    SUM(internal_object_reserved_page_count) * 8 / 1024 AS [Internal_Objects_MB],
    SUM(version_store_reserved_page_count) * 8 / 1024 AS [Version_Store_MB]
FROM sys.dm_db_file_space_usage;

PRINT '=== PAGELATCH WAITS ON TEMPDB (if any) ===';
SELECT TOP (10)
    wt.session_id,
    wt.wait_type,
    wt.wait_duration_ms,
    wt.resource_description,
    s.login_name,
    s.program_name
FROM sys.dm_os_waiting_tasks AS wt
LEFT JOIN sys.dm_exec_sessions AS s ON wt.session_id = s.session_id
WHERE wt.wait_type LIKE N'PAGELATCH%'
  AND wt.resource_description LIKE N'2:%'  -- db_id 2 = tempdb
ORDER BY wt.wait_duration_ms DESC;

PRINT '=== REMEDIATION TEMPLATE ===';
SELECT N'
-- Example: add tempdb file (size must match existing primary data file)
ALTER DATABASE tempdb ADD FILE (
    NAME = tempdev2,
    FILENAME = N''C:\SQL\Data\tempdb2.ndf'',
    SIZE = 1024MB,
    FILEGROWTH = 256MB
);
' AS [Add_File_Template];
