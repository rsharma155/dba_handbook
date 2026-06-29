/*
================================================================================
SSMS Object Explorer / Metadata Slowness Diagnosis
================================================================================
Purpose:
    Diagnose slow "expand databases" and Object Explorer timeouts after upgrade.
    These operations query system catalogs — NOT user data — so logical reads
    on user queries can be low while SSMS is still slow.

Common post-migration causes:
    (1) LATCH / METADATA waits on system catalog
    (2) Schema locks (LCK_M_SCH_*) from open table designers / DDL
    (3) Orphaned database owners → permission resolution delays
    (4) Very large number of objects per database
    (5) Antivirus scanning on database file paths during metadata access
    (6) Windows/AD authentication latency (PREEMPTIVE_OS_AUTHENTICATIONOPS)
    (7) Policy-Based Management / audit triggers
    (8) Always On DMVs misconfiguration

Tests:
    (1) Compare sqlcmd metadata query time vs SSMS (isolates client vs server)
    (2) Active metadata-related waits
    (3) Database owner issues
    (4) Synonym/view count per database (enumeration cost)

How to test server-side only (run in sqlcmd on VM):
    SET STATISTICS TIME ON;
    SELECT name, state_desc, recovery_model_desc FROM sys.databases;
    SELECT COUNT(*) FROM sys.tables;
    SET STATISTICS TIME OFF;
    If fast in sqlcmd but slow in SSMS → client/AD/network to domain controller.

Next action:
    Orphaned owner → ALTER AUTHORIZATION ON DATABASE
    AD latency → use SQL auth test login temporarily to compare
    AV → 08_Storage_OS/02_os_integration_post_migration.sql

Criticality: High for reported SSMS symptom
================================================================================
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

PRINT '=== SERVER-SIDE METADATA BASELINE (should complete in < 2 sec on healthy instance) ===';
DECLARE @Start DATETIME2 = SYSDATETIME();

SELECT name, database_id, state_desc, recovery_model_desc, compatibility_level
FROM sys.databases
ORDER BY name;

SELECT @Start = SYSDATETIME();
-- object count from each online user DB
DECLARE @db SYSNAME, @sql NVARCHAR(MAX);
DECLARE dbcur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0;

CREATE TABLE #ObjCounts (Database_Name SYSNAME, Table_Count INT, View_Count INT);

OPEN dbcur;
FETCH NEXT FROM dbcur INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'USE ' + QUOTENAME(@db) + N';
    INSERT INTO #ObjCounts SELECT DB_NAME(), (SELECT COUNT(*) FROM sys.tables), (SELECT COUNT(*) FROM sys.views);';
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #ObjCounts VALUES (@db, -1, -1);
    END CATCH;
    FETCH NEXT FROM dbcur INTO @db;
END;
CLOSE dbcur; DEALLOCATE dbcur;

SELECT * FROM #ObjCounts ORDER BY Table_Count DESC;
DROP TABLE #ObjCounts;

PRINT 'Elapsed for metadata scan — check Messages tab for duration.';

PRINT '=== ORPHANED DATABASE OWNERS (breaks SSMS permission checks) ===';
SELECT
    name AS [Database_Name],
    SUSER_SNAME(owner_sid) AS [Owner],
    CASE WHEN SUSER_SNAME(owner_sid) IS NULL THEN N'FIX IMMEDIATELY' ELSE N'OK' END AS [Status]
FROM sys.databases
WHERE database_id > 4;

PRINT '=== ACTIVE METADATA / SCHEMA WAITS ===';
SELECT
    r.session_id,
    r.wait_type,
    r.wait_time,
    r.wait_resource,
    s.login_name,
    s.program_name,
    st.text
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.wait_type LIKE N'LCK_M_SCH%'
   OR r.wait_type LIKE N'LATCH%'
   OR r.wait_type LIKE N'METADATA%'
   OR r.wait_type LIKE N'PREEMPTIVE_OS_AUTHENTICATION%'
ORDER BY r.wait_time DESC;

PRINT '=== SSMS / SMO SESSIONS (often hold schema locks) ===';
SELECT
    session_id,
    login_name,
    host_name,
    program_name,
    status,
    open_transaction_count,
    last_request_start_time
FROM sys.dm_exec_sessions
WHERE program_name LIKE N'%Management Studio%'
   OR program_name LIKE N'%SMO%'
ORDER BY last_request_start_time DESC;

PRINT '=== DAC TEST (when instance appears hung) ===';
SELECT
    N'Connect via Dedicated Admin Connection: ADMIN:ServerName' AS [DAC_Instruction],
    N'If DAC is fast but normal SSMS slow → connection pool or login trigger issue' AS [Interpretation];

PRINT 'If sys.databases query is slow HERE (sqlcmd), problem is server-side.';
PRINT 'If fast here but slow in SSMS UI only, test SQL auth login vs Windows auth.';
