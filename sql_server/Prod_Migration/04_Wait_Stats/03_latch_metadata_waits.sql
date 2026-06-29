/*
================================================================================
Latch and Metadata Wait Deep Dive
================================================================================
Purpose:
    Investigate LATCH_*, PAGELATCH_*, METADATA_LATCH_* waits — the leading
    cause of SSMS Object Explorer slowness (expand databases) AND queries
    with high elapsed time but minimal logical reads.

Why post-migration:
    - More cores → more parallel metadata scans → latch contention
    - TempDB misconfiguration surfaces under higher parallelism
    - Security / ACL checks on database enumeration (SSMS)
    - Plan cache / metadata cache pressure after upgrade

Checks:
    (1) Top latch waits from dm_os_latch_stats
    (2) Waiting tasks on latch-related wait types right now
    (3) TempDB file layout and free space
    (4) Count of databases (large enumerations slow SSMS)
    (5) Sessions running DBCC or DDL

Interpretation:
    PAGELATCH_EX on tempdb page 1:1:2 etc → classic tempdb allocation latch
    LATCH_EX on ACCESS_METHODS_HOBT_COUNT → metadata heavy workload
    Many databases + AD auth → PREEMPTIVE_OS_AUTHENTICATIONOPS may accompany

Next action:
    TempDB: 08_Storage_OS/03_tempdb_autogrowth_audit.sql
    SSMS: 05_Concurrency/02_ssms_metadata_slowness.sql
    IF PAGELATCH on tempdb: add evenly-sized tempdb files

Criticality: High for SSMS + low-read slow queries
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

PRINT '=== TOP LATCH CLASSES (dm_os_latch_stats) ===';
SELECT TOP (25)
    ls.latch_class,
    ls.wait_time_ms / 1000.0 AS [Total_Wait_Sec],
    ls.waiting_requests_count AS [Wait_Count],
    CAST(ls.wait_time_ms * 1.0 / NULLIF(ls.waiting_requests_count, 0) AS DECIMAL(18,2)) AS [Avg_Wait_ms],
    CASE ls.latch_class
        WHEN N'ACCESS_METHODS_DATASET_PARENT' THEN N'Parallel scan coordination'
        WHEN N'ACCESS_METHODS_HOBT_COUNT' THEN N'Heap/B-tree metadata — many tables/indexes'
        WHEN N'DBCC_MULTIOBJECT_SCANNER' THEN N'DBCC running — blocks metadata'
        WHEN N'BUFFER' THEN N'Buffer manager latch — memory pressure'
        WHEN N'SOS_RESERVEDMEMBLOCKLIST' THEN N'Memory object list — compile pressure'
        ELSE N'Correlate with active queries'
    END AS [Typical_Cause]
FROM sys.dm_os_latch_stats AS ls
WHERE ls.waiting_requests_count > 0
ORDER BY ls.wait_time_ms DESC;

PRINT '=== ACTIVE LATCH / PAGELATCH WAITS ===';
SELECT
    wt.session_id,
    wt.wait_type,
    wt.wait_duration_ms,
    wt.resource_description,
    s.login_name,
    s.host_name,
    s.program_name,
    SUBSTRING(st.text, 1, 200) AS [Query_Start]
FROM sys.dm_os_waiting_tasks AS wt
INNER JOIN sys.dm_exec_sessions AS s ON wt.session_id = s.session_id
LEFT JOIN sys.dm_exec_requests AS r ON wt.session_id = r.session_id
LEFT JOIN sys.dm_exec_connections AS c ON c.session_id = wt.session_id
OUTER APPLY sys.dm_exec_sql_text(COALESCE(r.sql_handle, c.most_recent_sql_handle)) AS st
WHERE wt.wait_type LIKE N'LATCH%'
   OR wt.wait_type LIKE N'PAGELATCH%'
   OR wt.wait_type LIKE N'METADATA%'
ORDER BY wt.wait_duration_ms DESC;

PRINT '=== TEMPDB FILE LAYOUT ===';
SELECT
    name,
    physical_name,
    size * 8 / 1024 AS [Size_MB],
    growth,
    is_percent_growth
FROM tempdb.sys.database_files
ORDER BY type_desc, file_id;

PRINT '=== DATABASE COUNT (SSMS enumeration cost) ===';
SELECT
    COUNT(*) AS [User_Database_Count],
    SUM(CASE WHEN state_desc <> N'ONLINE' THEN 1 ELSE 0 END) AS [Non_Online_Count],
    CASE WHEN COUNT(*) > 100 THEN N'Large tree — SSMS expand inherently slower; test with sqlcmd'
         ELSE N'Normal count'
    END AS [SSMS_Note]
FROM sys.databases
WHERE database_id > 4;

PRINT '=== SESSIONS RUNNING DBCC / DDL (metadata blockers) ===';
SELECT
    r.session_id,
    r.command,
    r.wait_type,
    r.total_elapsed_time / 1000 AS [Elapsed_Sec],
    s.login_name,
    s.program_name,
    st.text
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.command LIKE N'DBCC%'
   OR st.text LIKE N'%ALTER%DATABASE%'
   OR st.text LIKE N'%DROP%DATABASE%'
   OR st.text LIKE N'%CREATE%INDEX%'
ORDER BY r.total_elapsed_time DESC;
