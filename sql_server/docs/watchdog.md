I want to add a preventive measures in sql server database so that it can block and warn users to run any ad-hoc queries more than configurable seconds thresholds (default 10 seconds) in production. Warning and alert generation if there any application/user running massive insert/update/delete in the server. Please share a detailed prompt along with pseudo sql scripts to start preparing the required measures/sql scripts for this. 

This is a good production hardening use case. In SQL Server, you usually cannot reliably block every dangerous query before execution using only T-SQL because the query optimizer, permissions, and execution lifecycle happen inside the engine. The production-grade approach is a multi-layer prevention + detection + enforcement framework:

Preventive controls
Resource Governor (best for SQL Server Enterprise)
Login/application workload classification
Query timeout policies
Permissions separation
DDL/DML governance
Real-time monitoring
Extended Events
DMVs
Query Store
Agent jobs
Automatic response
Alert
Kill session
Block login/application
Throttle workload

Below is a detailed implementation prompt you can give to an AI coding agent.

Implementation Prompt
Project Name

Production SQL Server Ad-hoc Query Protection & Workload Governance Framework

Objective

Build a SQL Server preventive monitoring and enforcement framework that:

Detects long-running ad-hoc queries
Warns users before executing expensive queries
Blocks dangerous workloads based on configurable thresholds
Detects massive INSERT/UPDATE/DELETE operations
Generates alerts
Maintains audit history
Supports production environments with minimal overhead

Default configuration:

Long running query threshold:
10 seconds

Large DML threshold:
100000 rows affected

Blocking action:
WARN / LOG / KILL / BLOCK

Monitoring interval:
5 seconds
Architecture
                    SQL Server Instance
                           |
                           |
              +------------+-------------+
              |
        Monitoring Layer
              |
    +---------+---------+
    |
    |-- Extended Events
    |
    |-- DMVs Collector
    |
    |-- Query Store
    |
    |-- SQL Agent Jobs
    |
              |
              |
       Repository Database
              |
              |
    +---------+----------+
    |
 Alerts
 Dashboard
 Audit Reports
 Automatic Actions
Phase 1 - Configuration Repository

Create governance database.

Example:

CREATE DATABASE DBA_Governance;
GO

USE DBA_Governance;
GO

Configuration table:

CREATE TABLE dbo.Policy_Config
(
    Config_ID INT IDENTITY PRIMARY KEY,

    Policy_Name VARCHAR(100),

    Long_Query_Threshold_Seconds INT DEFAULT 10,

    Large_DML_Row_Count BIGINT DEFAULT 100000,

    Action_Type VARCHAR(20)
        DEFAULT 'ALERT',

    Enabled BIT DEFAULT 1,

    Created_Date DATETIME DEFAULT GETDATE()
);

Insert default policy:

INSERT INTO dbo.Policy_Config
(
Policy_Name,
Long_Query_Threshold_Seconds,
Large_DML_Row_Count,
Action_Type
)
VALUES
(
'Production Query Protection',
10,
100000,
'ALERT'
);
Phase 2 - Capture Running Queries

Create collector procedure.

Purpose:

Capture:

Login
Host
Application
Database
Query text
Duration
CPU
Reads
Writes

Pseudo SQL:

CREATE PROCEDURE dbo.Capture_Running_Queries
AS
BEGIN

INSERT INTO dbo.Query_History
(
session_id,
login_name,
host_name,
program_name,
database_name,
query_text,
duration_ms,
cpu_time,
logical_reads,
writes,
captured_time
)

SELECT

r.session_id,

s.login_name,

s.host_name,

s.program_name,

DB_NAME(r.database_id),

t.text,

r.total_elapsed_time,

r.cpu_time,

r.logical_reads,

r.writes,

GETDATE()


FROM sys.dm_exec_requests r

JOIN sys.dm_exec_sessions s

ON r.session_id=s.session_id


CROSS APPLY

sys.dm_exec_sql_text(r.sql_handle) t


WHERE

r.session_id <> @@SPID;

END
Phase 3 - Detect Long Running Queries

Create monitoring job.

SQL Agent schedule:

Every 5 seconds

Procedure:

CREATE PROCEDURE dbo.Check_Long_Running_Query
AS
BEGIN


DECLARE @threshold INT;


SELECT 
@threshold =
Long_Query_Threshold_Seconds

FROM dbo.Policy_Config
WHERE Enabled=1;



INSERT INTO dbo.Alert_Log
(
Alert_Type,
Session_ID,
Message,
Created_Date
)


SELECT

'LONG_RUNNING_QUERY',

r.session_id,


'Query exceeded threshold: '
+
CAST(@threshold AS VARCHAR)
+
' seconds',


GETDATE()


FROM sys.dm_exec_requests r


WHERE

r.total_elapsed_time >
(@threshold*1000);


END
Phase 4 - Detect Massive INSERT/UPDATE/DELETE

Logic:

Capture:

command type
transaction size
row count
log usage

Example:

SELECT

r.session_id,

t.text,

r.command,

r.row_count,

r.total_elapsed_time/1000
AS seconds_running


FROM sys.dm_exec_requests r


CROSS APPLY
sys.dm_exec_sql_text(r.sql_handle)t


WHERE

r.command IN
(
'INSERT',
'UPDATE',
'DELETE'
)


AND

r.row_count >
100000;
Phase 5 - Automatic Blocking / Kill Logic

Add policy action.

Example:

ALERT
WARN
KILL

Procedure:

CREATE PROCEDURE dbo.Enforce_Query_Policy

AS
BEGIN


DECLARE 
@s INT;


SELECT @s=session_id

FROM dbo.Query_History

WHERE duration_ms >
10000;



IF EXISTS
(
SELECT 1
FROM dbo.Policy_Config
WHERE Action_Type='KILL'
)


BEGIN


EXEC
('KILL '+CAST(@s AS VARCHAR));


END


END
Phase 6 - Extended Events Implementation

Create lightweight XE session.

Purpose:

Capture completed queries > 10 seconds.

CREATE EVENT SESSION
Production_Long_Query_Monitor

ON SERVER


ADD EVENT sqlserver.sql_statement_completed

(
ACTION
(
sqlserver.client_app_name,

sqlserver.username,

sqlserver.database_name,

sqlserver.sql_text

)

WHERE

duration >
10000000
)


ADD TARGET package0.event_file
(
SET filename=
'C:\XE\long_queries.xel'
);


ALTER EVENT SESSION
Production_Long_Query_Monitor

ON SERVER

STATE=START;
Phase 7 - Detect Dangerous Applications

Create application blacklist.

CREATE TABLE dbo.Blocked_Applications
(
Application_Name varchar(200),

Reason varchar(500),

Enabled bit
);

Example:

INSERT INTO dbo.Blocked_Applications

VALUES

(
'SQLCMD',

'Production direct access',

1
);

Detection:

SELECT *

FROM sys.dm_exec_sessions

WHERE program_name IN

(
SELECT Application_Name
FROM dbo.Blocked_Applications
);
Phase 8 - SQL Server Resource Governor

For Enterprise Edition.

Create workload group:

CREATE RESOURCE POOL Production_User_Pool

WITH
(
MAX_CPU_PERCENT=50,
MAX_MEMORY_PERCENT=40
);

Classifier:

CREATE FUNCTION dbo.fn_Classify()

RETURNS SYSNAME

WITH SCHEMABINDING

AS

BEGIN


DECLARE @group SYSNAME


IF ORIGINAL_LOGIN()
LIKE 'developer%'

SET @group='Production_User_Pool'


RETURN @group


END

Enable:

ALTER RESOURCE GOVERNOR

WITH
(
CLASSIFIER_FUNCTION=
dbo.fn_Classify
);


ALTER RESOURCE GOVERNOR RECONFIGURE;
Phase 9 - Alert Framework

Table:

CREATE TABLE dbo.Alert_Log
(

Alert_ID BIGINT IDENTITY PRIMARY KEY,

Alert_Type varchar(100),

Severity varchar(20),

Session_ID int,

Login_Name varchar(100),

Message varchar(max),

Created_Date datetime

);

Example alerts:

CRITICAL:
UPDATE affecting > 1 million rows

WARNING:
Query running > 10 seconds

INFO:
High IO query detected
Phase 10 - Production Dashboard Metrics

Expose:

KPIs
Current Running Queries

Long Running Queries

Blocked Sessions

Large Transactions

Top CPU Queries

Top IO Queries

Killed Sessions
Tables
Query History

Alert History

Blocked Query History

User Activity
Charts
Queries/sec

Average Duration

DML Volume

Blocking Trend

CPU Consumption
Development Standards

Follow:

Database Design
Separate DBA_Governance database
No application table modification
Least privilege permissions
Stored procedures only
Security
Avoid storing sensitive query parameters
Mask literals
Encrypt audit tables
Restrict access
Testing

Create test scenarios:

Long Query
WAITFOR DELAY '00:00:15'

Expected:

Alert generated
Massive Update
UPDATE LargeTable
SET Column1='X'

Expected:

Detected as dangerous DML
Recommended Final Implementation Order
Phase 1
Configuration Repository

Phase 2
DMV Collector

Phase 3
Alert Engine

Phase 4
Extended Events

Phase 5
Automatic Enforcement

Phase 6
Resource Governor

Phase 7
Dashboard/API

For a production SQL Server estate, I would avoid directly killing queries initially. A safer rollout is:

Detect → Alert → Report → Warn → Controlled Kill

because false positives on large ETL jobs, index maintenance, and reporting workloads can otherwise create operational incidents.