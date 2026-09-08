List the deprecated features from sql server 2012 - 2022. This is to prepare for the sql server assessment report by looking at the current database server and generate report on what needs to be changed to match with the newer version of sql server. 

Thought Process
SQL Server Deprecated Features (2012-2022)
Assessment Report Reference Guide
📊 Quick Detection Query
Run this first to get an overview of deprecated feature usage:

sql

-- Check deprecated features being used (from trace events)
SELECT 
    de.feature_name AS DeprecatedFeature,
    COUNT(*) AS OccurrenceCount
FROM sys.fn_trace_gettable(
    CONVERT(VARCHAR(128), SERVERPROPERTY('ErrorLogFileName')), 
    1) AS t
CROSS APPLY sys.fn_trace_geteventinfo(t.EventID) AS ei
JOIN sys.trace_events AS te ON ei.eventid = te.trace_event_id
JOIN sys.trace_columns AS tc ON ei.columnid = tc.trace_column_id
JOIN sys.dm_xe_object_columns AS xoc ON xoc.object_name = 'deprecated_features'
WHERE te.name = 'Deprecation Announcement'
GROUP BY de.feature_name
ORDER BY COUNT(*) DESC;
🔴 REMOVED FEATURES (No Longer Available)
These features were deprecated and later completely removed. If found, they MUST be changed.

Removed in SQL Server 2012
Removed Feature
Replacement
Detection Query
SET ROWCOUNT for INSERT/UPDATE/DELETE	Use TOP()	SELECT OBJECT_NAME(id) FROM syscomments WHERE text LIKE '%SET ROWCOUNT%'
@@REMSERVER	Use linked servers	SELECT OBJECT_NAME(id) FROM syscomments WHERE text LIKE '%@@REMSERVER%'
DATABASEPROPERTY	DATABASEPROPERTYEX	SELECT OBJECT_NAME(id) FROM syscomments WHERE text LIKE '%DATABASEPROPERTY(%' AND text NOT LIKE '%DATABASEPROPERTYEX(%'
BACKUP LOG WITH NO_LOG	Simple recovery model or truncate-only	Search agent jobs, maintenance plans
BACKUP LOG WITH TRUNCATE_ONLY	Simple recovery model	Search agent jobs, maintenance plans
sp_addalias	Use database roles	SELECT * FROM sys.syslogins WHERE name IN (SELECT aliasname FROM sys.sysaliases)
sp_dropalias	Use database roles	Check legacy scripts
sys.sql_dependencies	sys.sql_expression_dependencies	SELECT * FROM sys.sql_dependencies
TEXT/NTEXT/IMAGE data types	Use VARCHAR(MAX), NVARCHAR(MAX), VARBINARY(MAX)	See detection query below

Removed in SQL Server 2016
Removed Feature
Replacement
Detection Query
sp_dboption	ALTER DATABASE	SELECT OBJECT_NAME(id) FROM syscomments WHERE text LIKE '%sp_dboption%'
DATABASEPROPERTYEX 'IsTornPageDetectionEnabled'	PAGE_VERIFY option	SELECT OBJECT_NAME(id) FROM syscomments WHERE text LIKE '%IsTornPageDetectionEnabled%'
ALTER DATABASE SET TORN_PAGE_DETECTION	ALTER DATABASE SET PAGE_VERIFY	Check database scripts
fn_virtualservernodes	sys.dm_os_cluster_nodes	SELECT OBJECT_NAME(id) FROM syscomments WHERE text LIKE '%fn_virtualservernodes%'
fn_servershareddrives	sys.dm_io_cluster_shared_drives	SELECT OBJECT_NAME(id) FROM syscomments WHERE text LIKE '%fn_servershareddrives%'
USER_ID()	DATABASE_PRINCIPAL_ID()	SELECT OBJECT_NAME(id) FROM syscomments WHERE text LIKE '%USER_ID(%'

Removed in SQL Server 2022
Removed Feature
Replacement
Detection Query
ALTER DATABASE SET EMERGENCY (single-user implicit)	Explicit ALTER DATABASE SET SINGLE_USER WITH ROLLBACK IMMEDIATE	Check DR scripts
ADO.NET SqlClient Encryption/Decryption	Use Always Encrypted	Check application code
SQL Server Service Broker External Activator	Use built-in activation	Check Service Broker configurations
Filestream filegroup with non-filestream files	Separate filegroups	SELECT * FROM sys.filegroups WHERE type = 2

🟡 DEPRECATED FEATURES (Still Working, Will Be Removed)
Database Engine - Data Types
sql

-- Detect legacy data types that should be migrated
SELECT 
    t.NAME AS TableName,
    c.NAME AS ColumnName,
    ty.NAME AS DataType,
    c.max_length,
    c.precision,
    c.scale
FROM sys.tables t
INNER JOIN sys.columns c ON t.object_id = c.object_id
INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
WHERE ty.NAME IN ('text', 'ntext', 'image', 'timestamp')  -- timestamp = rowversion
ORDER BY t.NAME, c.column_id;
Deprecated
Replacement
Version Deprecated
TEXT	VARCHAR(MAX)	2005
NTEXT	NVARCHAR(MAX)	2005
IMAGE	VARBINARY(MAX)	2005
TIMESTAMP (as data type)	ROWVERSION	2005

Transact-SQL Syntax
sql

-- Detect deprecated T-SQL patterns
SELECT 
    'Deprecated T-SQL' AS Category,
    o.type_desc AS ObjectType,
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.NAME AS ObjectName,
    m.definition
FROM sys.sql_modules m
INNER JOIN sys.objects o ON m.object_id = o.object_id
WHERE m.definition LIKE '%SELECT * FROM %, %'  -- Old-style joins
   OR m.definition LIKE '%=*%'                 -- Old-style outer join
   OR m_definition LIKE '%= *%'                -- Old-style outer join
   OR m.definition LIKE '%SET ROWCOUNT%'       -- (for non-DML)
   OR m.definition LIKE '%@@REMSERVER%'
   OR m.definition LIKE '%DATABASEPROPERTY(%'
   OR m.definition LIKE '%sp_dboption%'
   OR m.definition LIKE '%USER_ID(%'
ORDER BY o.type_desc, o.NAME;
Deprecated Syntax
Replacement
Version
SELECT * FROM t1, t2 WHERE t1.id =* t2.id	LEFT/RIGHT OUTER JOIN	2005
SELECT * FROM t1, t2 WHERE t1.id *= t2.id	LEFT/RIGHT OUTER JOIN	2005
INSERT INTO t1 SELECT * FROM t2 (without column list)	Explicit column list	Best practice
RAISERROR 50000 with string	Use THROW	2012+
SET CONTEXT_INFO	SESSION_CONTEXT	2016+

Deprecated System Stored Procedures
sql

-- Detect usage of deprecated system procedures
SELECT 
    o.type_desc AS ObjectType,
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.NAME AS ObjectName,
    m.definition
FROM sys.sql_modules m
INNER JOIN sys.objects o ON m.object_id = o.object_id
WHERE m.definition LIKE '%sp_addalias%'
   OR m.definition LIKE '%sp_dropalias%'
   OR m.definition LIKE '%sp_grantdbaccess%'
   OR m.definition LIKE '%sp_revokedbaccess%'
   OR m.definition LIKE '%sp_adduser%'
   OR m_definition LIKE '%sp_dropuser%'
   OR m.definition LIKE '%sp_changedbowner%'
   OR m.definition LIKE '%sp_helpuser%'
   OR m.definition LIKE '%sp_configure%''%'
ORDER BY o.NAME;
Deprecated Procedure
Replacement
Version
sp_addalias	Database roles	2012 (removed)
sp_dropalias	Database roles	2012 (removed)
sp_grantdbaccess	CREATE USER	2012 (removed)
sp_revokedbaccess	DROP USER	2012 (removed)
sp_adduser	CREATE USER	2012 (removed)
sp_dropuser	DROP USER	2012 (removed)
sp_changedbowner	ALTER AUTHORIZATION ON DATABASE	2012 (removed)
sp_helpuser	sys.database_principals	2016 (removed)
sp_addlogin	CREATE LOGIN	Deprecated
sp_droplogin	DROP LOGIN	Deprecated
sp_addrole	CREATE ROLE	Deprecated
sp_droprole	DROP ROLE	Deprecated
sp_addrolemember	ALTER ROLE ADD MEMBER	Deprecated
sp_droprolemember	ALTER ROLE DROP MEMBER	Deprecated

Deprecated Configuration Options
sql

-- Check deprecated sp_configure options
SELECT 
    name AS ConfigOption,
    description,
    CASE 
        WHEN name IN ('allow updates', 'locks', 'open objects', 'priority boost', 
                      'remote proc trans', 'set working set size') 
        THEN 'DEPRECATED/REMOVED'
        ELSE 'Active'
    END AS Status
FROM sys.configurations
WHERE name IN ('allow updates', 'locks', 'open objects', 'priority boost', 
               'remote proc trans', 'set working set size', 'fill factor',
               'max degree of parallelism', 'cost threshold for parallelism')
ORDER BY Status DESC, name;
Deprecated Option
Version Removed
allow updates	2012
locks	2012
open objects	2012
priority boost	2012
remote proc trans	2012
set working set size	2012
disallow results from triggers	2012

🟠 Version-Specific Deprecations
SQL Server 2012 Deprecations
sql

-- SQL Server 2012 specific checks
-- 1. Check for BACKUP with PASSWORD
SELECT j.name AS JobName, s.command
FROM msdb.dbo.sysjobsteps s
JOIN msdb.dbo.sysjobs j ON s.job_id = j.job_id
WHERE s.command LIKE '%BACKUP%PASSWORD%';

-- 2. Check for SET ANSI_DEFAULTS OFF
SELECT OBJECT_NAME(object_id) AS ObjectName, definition
FROM sys.sql_modules
WHERE definition LIKE '%SET ANSI_DEFAULTS OFF%';

-- 3. Check for sp_addserver usage
SELECT OBJECT_NAME(object_id) AS ObjectName, definition
FROM sys.sql_modules
WHERE definition LIKE '%sp_addserver%';
Feature
Replacement
BACKUP/RESTORE WITH PASSWORD	Remove password, use other security
SET ANSI_DEFAULTS OFF	Set individual options explicitly
sp_addserver	sp_addlinkedserver
SOUNDEX()	Consider full-text search
fn_trace_gettable (for new dev)	Extended Events

SQL Server 2014 Deprecations
sql

-- Check for deprecated cryptographic algorithms
SELECT 
    name AS CertificateName,
    pvt.algorithm_desc
FROM sys.certificates c
CROSS APPLY (SELECT CAST(c.thumbprint AS VARCHAR(128)) AS algo) p
WHERE 1=0  -- Need to check DMVs for actual algorithm info

-- Check for MD2, MD4, MD5, SHA, SHA1 usage
SELECT OBJECT_NAME(object_id), definition
FROM sys.sql_modules
WHERE definition LIKE '%HASHBYTES%''MD2%'
   OR definition LIKE '%HASHBYTES%''MD4%'
   OR definition LIKE '%HASHBYTES%''MD5%'
   OR definition LIKE '%HASHBYTES%''SHA%'
   OR definition LIKE '%HASHBYTES%''SHA1%';
Feature
Replacement
MD2, MD4, MD5, SHA, SHA1 algorithms	SHA2_256, SHA2_512
RC4 encryption	AES encryption
Remote servers (sp_addremoteserver)	Linked servers

SQL Server 2016 Deprecations
sql

-- Check for deprecated XQuery functions
SELECT OBJECT_NAME(object_id) AS ObjectName, definition
FROM sys.sql_modules
WHERE definition LIKE '%::node()%'
   OR definition LIKE '%::text()%';

-- Check for deprecated string functions
SELECT OBJECT_NAME(object_id) AS ObjectName, definition
FROM sys.sql_modules
WHERE definition LIKE '%TEXTPTR(%'
   OR definition LIKE '%TEXTVALID(%'
   OR definition LIKE '%UPDATETEXT%'
   OR definition LIKE '%WRITETEXT%'
   OR definition LIKE '%READTEXT%';
Feature
Replacement
::node() XQuery	::nodes()
::text() XQuery	text() function
TEXTPTR(), TEXTVALID()	Use VARCHAR(MAX)
UPDATETEXT, WRITETEXT, READTEXT	.WRITE() clause on VARCHAR(MAX)
SET FMTONLY ON	sp_describe_first_result_set
sp_db_vardecimal_storage_format	Always enabled in 2016+
DATABASEPROPERTYEX 'IsFullTextEnabled'	Always enabled

SQL Server 2017 Deprecations
sql

-- Check for deprecated trace flags
SELECT 
    trace_flag,
    status,
    value,
    value_in_use
FROM sys.dm_os_sys_info
WHERE 1=0;  -- Use DBCC TRACESTATUS(-1) instead

-- Run this to check active trace flags
DBCC TRACESTATUS(-1);
Feature
Replacement
Trace flag 823 (page checksum)	Default behavior
CONTAINS with FORMSOF INFLECTIONAL	Consider other search options
SQL Server PowerShell module (sqlps)	SqlServer module
sp_attach_db (single file)	CREATE DATABASE ... FOR ATTACH
sp_attach_single_file_db	CREATE DATABASE ... FOR ATTACH_REBUILD_LOG

SQL Server 2019 Deprecations
sql

-- Check for SQL Server Audit with file target
SELECT 
    a.name AS AuditName,
    d.name AS DatabaseAuditName,
    a.destination_type,
    a.on_failure
FROM sys.server_audits a
LEFT JOIN sys.database_audit_specifications d ON 1=0
WHERE a.destination_type = 0;  -- 0 = File

-- Check for deprecated string functions
SELECT OBJECT_NAME(object_id) AS ObjectName, definition
FROM sys.sql_modules
WHERE definition LIKE '%STRING_AGG%'  -- Not deprecated but verify compatibility
   OR definition LIKE '%CONCAT_WS%';  -- New in 2017, check compatibility level
Feature
Replacement
SQL Server Audit file target	Extended Events file target
旧版 compatibility_level < 100	Set to 100+
DRAWSEG hint	Remove
FASTFIRSTROW hint	Use FAST n
MAXDOP 1 in Resource Governor	Use MAXDOP 0 or specific value

SQL Server 2022 Deprecations
sql

-- Check for deprecated features in SQL 2022
-- 1. Check for PolyBase Hadoop connectivity (deprecated)
SELECT 
    name,
    provider,
    data_source_id
FROM sys.external_data_sources
WHERE provider LIKE '%Hadoop%';

-- 2. Check for old-style temporal table syntax
SELECT OBJECT_NAME(object_id), definition
FROM sys.sql_modules
WHERE definition LIKE '%HISTORY_TABLE%';
Feature
Replacement
PolyBase Hadoop connectivity	Azure Data Lake/Storage
SQL Server Management Studio 17.x	SSMS 19+
Data Quality Services (DQS)	Azure Purview or custom solutions
Master Data Services (MDS) Add-in for Excel	Web interface
Database Mail XPs (being phased out)	Use other notification methods

🔍 Comprehensive Assessment Script
sql

        WHEN j.command LIKE '%sp_adduser%' THEN 'sp_adduser usage'
        WHEN j.command LIKE '%sp_addlogin%' THEN 'sp_addlogin usage'
        ELSE 'Other deprecated feature in job'
    END,
    j.name,
    'SQL Agent Job',
    j.command,
    'HIGH',
    'Update job step to use modern syntax'
FROM msdb.dbo.sysjobsteps j
WHERE (j.command LIKE '%BACKUP%PASSWORD%'
    OR j.command LIKE '%sp_dboption%'
    OR j.command LIKE '%sp_adduser%'
    OR j.command LIKE '%sp_addlogin%'
    OR j.command LIKE '%sp_dropuser%'
    OR j.command LIKE '%sp_droplogin%');

-- ============================================
-- OUTPUT REPORT
-- ============================================
SELECT 
    Severity AS [!Priority],
    Category,
    Feature AS [Deprecated Feature],
    ObjectName AS [Affected Object],
    ObjectType,
    Details,
    ActionRequired AS [Recommended Action]
FROM #AssessmentResults
ORDER BY 
    CASE Severity 
        WHEN 'CRITICAL' THEN 1 
        WHEN 'HIGH' THEN 2 
        WHEN 'MEDIUM' THEN 3 
        WHEN 'LOW' THEN 4 
        WHEN 'INFO' THEN 5 
        ELSE 6 
    END,
    Category,
    ObjectName;

-- Summary statistics
SELECT 
    'SUMMARY' AS ReportSection,
    Severity,
    COUNT(*) AS IssueCount
FROM #AssessmentResults
GROUP BY Severity
ORDER BY 
    CASE Severity 
        WHEN 'CRITICAL' THEN 1 
        WHEN 'HIGH' THEN 2 
        WHEN 'MEDIUM' THEN 3 
        WHEN 'LOW' THEN 4 
        WHEN 'INFO' THEN 5 
        ELSE 6 
    END;

DROP TABLE #AssessmentResults;
📋 Migration Priority Matrix
Priority
Action Timeline
Examples
CRITICAL	Must fix BEFORE upgrade	sp_dboption, DATABASEPROPERTY, old data types with code references
HIGH	Fix before or immediately after upgrade	TEXT/NTEXT/IMAGE columns, deprecated procedures, weak crypto
MEDIUM	Plan for next 6 months	Old-style joins, deprecated functions, compatibility level
LOW	Backlog for future sprints	Trace flags now default, minor syntax variations
INFO	Documentation only	New features to adopt

📁 Export to CSV for Report
sql

-- Run after the assessment script to export
-- (Save results to CSV for inclusion in assessment report)
SELECT 
    Severity AS Priority,
    Category,
    Feature AS [Deprecated Feature],
    ObjectName AS [Affected Object],
    ObjectType,
    Details,
    ActionRequired AS [Recommended Action]
FROM #AssessmentResults
ORDER BY 
    CASE Severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 WHEN 'LOW' THEN 4 ELSE 5 END,
    Category;
 
 
