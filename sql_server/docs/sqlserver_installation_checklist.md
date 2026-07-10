For a fresh production SQL Server 2025 deployment on Windows Server 2025, treat the installation as a complete platform build, not just “install SQL Server and create databases”. The goal is:

predictable performance
easy troubleshooting
separation of workloads
recoverability
security hardening
operational readiness

Below is a production-grade baseline.

1. Pre-installation Architecture Planning
1.1 Decide server role

Recommended:

Component	Recommendation
OS	Windows Server 2025
SQL Version	SQL Server 2025 Enterprise/Standard depending workload
Installation Type	Standalone instance unless clustering required
Instance	Default instance preferred
Authentication	Windows + SQL mixed mode
Service Accounts	Dedicated domain accounts/gMSA
Storage	Separate volumes
Backup	Separate storage/network target
Monitoring	Enabled from day one
2. Windows Server 2025 Preparation
2.1 OS Patching

Before SQL installation:

Install:

latest Windows cumulative updates
latest security updates
firmware updates
storage controller drivers
NIC drivers

Restart server.

Verify:

winver
3. Windows Configuration
3.1 Disable unnecessary services

Review:

services.msc

Disable if not required:

Print Spooler
Fax
Remote Registry

Do not disable:

Windows Time
DNS Client
RPC
Event Log
3.2 Power Plan

Set:

Control Panel
 -> Power Options
 -> High Performance

Verify:

powercfg /list
3.3 Configure Windows Defender exclusions

Exclude SQL paths:

Example:

D:\SQLData
E:\SQLLog
F:\SQLTempDB
G:\SQLBackup

PowerShell:

Add-MpPreference `
-ExclusionPath `
"D:\SQLData",
"E:\SQLLog",
"F:\SQLTempDB",
"G:\SQLBackup"

Also exclude:

SQL Server binaries:

C:\Program Files\Microsoft SQL Server
4. Storage Design

A production SQL server should not have everything on C:.

Recommended:

Drive	Purpose
C	OS
D	Data files
E	Log files
F	TempDB
G	Backups
H	SQL binaries

Example:

C:\ Windows

D:\SQLData
   DB1.mdf
   DB2.ndf

E:\SQLLog
   DB1_log.ldf

F:\SQLTempDB

G:\SQLBackup
5. Storage Formatting

For SQL volumes:

NTFS:

Allocation Unit Size:

64 KB

Check:

fsutil fsinfo ntfsinfo D:

Look for:

Bytes Per Cluster : 65536
6. SQL Service Accounts

Do NOT use:

LocalSystem
Administrator
Network Service

Use:

Example:

DOMAIN\svc_sqlengine
DOMAIN\svc_sqlagent
DOMAIN\svc_backup

Permissions:

SQL Engine:

Perform Volume Maintenance Tasks
Lock Pages In Memory
Log on as service
7. SQL Server Installation

Launch:

setup.exe

Select:

New SQL Server standalone installation
8. Feature Selection

Usually:

Install:

✔ Database Engine Services
✔ SQL Agent
✔ Full Text Search (if required)
✔ Replication (if required)

Avoid unnecessary:

SSAS
SSRS
PolyBase
9. Instance Configuration

Production recommendation:

Default:

MSSQLSERVER

Reason:

easier tools compatibility
easier monitoring
fewer connection issues
10. Service Configuration

Set accounts:

Example:

Database Engine:

DOMAIN\svc_sqlengine

Startup:

Automatic

SQL Agent:

DOMAIN\svc_sqlagent

Startup:

Automatic
11. Database Engine Configuration

Authentication:

Choose:

Mixed Mode

Enable:

SQL Server administrators

Add:

DOMAIN\DBA_Group
12. Data Directory Configuration

VERY IMPORTANT.

Change:

Default root:

C:\Program Files\Microsoft SQL Server

to:

Data:

D:\SQLData

Log:

E:\SQLLog

Backup:

G:\SQLBackup

Temp:

F:\SQLTempDB
13. Post Installation Configuration

Connect using SSMS.

14. Memory Configuration

Default SQL uses all memory.

Configure:

Example:

Server RAM:

128 GB

Reserve:

Windows:

16 GB

SQL:

112 GB

Set:

EXEC sp_configure 'show advanced options',1;
RECONFIGURE;


EXEC sp_configure 
'max server memory',
114688;

RECONFIGURE;

Value is MB.

15. MAXDOP Configuration

Check CPU:

SELECT cpu_count
FROM sys.dm_os_sys_info;

Recommended:

SQL 2025:

Usually:

MAXDOP = 8

or

<= number of cores per NUMA node

Configure:

EXEC sp_configure 'max degree of parallelism',8;
RECONFIGURE;
16. Cost Threshold for Parallelism

Default:

5

Too low.

Production baseline:

50

Set:

EXEC sp_configure 
'cost threshold for parallelism',
50;

RECONFIGURE;
17. TempDB Configuration

TempDB is critical.

Find CPUs:

SELECT cpu_count
FROM sys.dm_os_sys_info;

Example:

32 cores:

Create:

8 tempdb files

Do NOT create 32.

Example:

Files:

F:\SQLTempDB\tempdb1.ndf
F:\SQLTempDB\tempdb2.ndf
...

Size:

Example:

8 GB each

Growth:

512 MB

Avoid:

10%

Example:

ALTER DATABASE tempdb
MODIFY FILE
(
NAME='tempdev',
SIZE=8192MB,
FILEGROWTH=512MB
);

Add files:

ALTER DATABASE tempdb
ADD FILE
(
NAME=tempdev2,
FILENAME='F:\SQLTempDB\tempdb2.ndf',
SIZE=8192MB,
FILEGROWTH=512MB
);

Restart SQL Server.

18. Instant File Initialization

Enable:

Windows:

Add SQL service account:

Perform Volume Maintenance Tasks

Restart SQL service.

Check:

SELECT *
FROM sys.dm_server_services;
19. Database File Configuration

For every database:

Data:

initial size = planned size
growth = fixed MB

Example:

Bad:

10%

Good:

1024 MB
20. Transaction Log Configuration

Example:

Database:

500GB

Log:

50GB

Configure:

ALTER DATABASE Sales
MODIFY FILE
(
NAME='Sales_log',
SIZE=50GB,
FILEGROWTH=2048MB
);
21. Recovery Model

Production:

Usually:

FULL

Check:

SELECT 
name,
recovery_model_desc
FROM sys.databases;

Set:

ALTER DATABASE DBName
SET RECOVERY FULL;
22. Backup Configuration

Recommended:

Full

Daily:

12 AM
Differential

Every:

4 hours
Log

Every:

5-15 minutes

Example:

FULL
 |
 + Differential
 |
 + Log backups
23. Backup Compression

Enable:

EXEC sp_configure 
'backup compression default',
1;

RECONFIGURE;
24. Backup Folder Structure

Example:

G:\SQLBackup

   \FULL

   \DIFF

   \LOG

   \SYSTEM
25. Database Maintenance

Install:

Ola Hallengren Maintenance Solution

Use:

Index maintenance
Statistics update
Backup jobs
26. SQL Agent Configuration

Enable:

SELECT SERVERPROPERTY('IsIntegratedSecurityOnly');

Check:

SQL Server Agent = Running
27. Security Hardening

Disable:

SA if possible:

ALTER LOGIN sa DISABLE;

Rename default:

sa

Create DBA role:

CREATE LOGIN DBA_Admin
FROM WINDOWS;
28. Database Mail

Configure:

Management
 |
 Database Mail

Used for:

alerts
failed jobs
blocking notifications
29. SQL Alerts

Configure:

Severity:

16-25

Example:

Deadlock:

1205
30. Monitoring Baseline

Enable collection:

Important DMVs:

Memory:

sys.dm_os_memory_clerks

CPU:

sys.dm_exec_query_stats

IO:

sys.dm_io_virtual_file_stats

Waits:

sys.dm_os_wait_stats
31. Query Store

Enable for every database:

ALTER DATABASE DBName
SET QUERY_STORE = ON;

Recommended:

ALTER DATABASE DBName
SET QUERY_STORE
(
OPERATION_MODE = READ_WRITE,
MAX_STORAGE_SIZE_MB = 2048,
QUERY_CAPTURE_MODE = AUTO
);
32. Final Validation Checklist

Before production go-live:

OS

✔ Patch completed
✔ Defender exclusions
✔ Power plan
✔ Drivers updated

SQL

✔ Memory configured
✔ MAXDOP configured
✔ Cost threshold changed
✔ TempDB optimized
✔ Backup tested
✔ Restore tested
✔ Query Store enabled

Recovery

Test:

RESTORE VERIFYONLY

Perform:

Full restore test.

Recommended Production Directory Layout
C:
 └── Windows


D:
 └── SQLData
      ├── UserDB1.mdf
      └── UserDB2.ndf


E:
 └── SQLLog
      ├── UserDB1.ldf


F:
 └── SQLTempDB
      ├── tempdb1.ndf


G:
 └── SQLBackup
      ├── FULL
      ├── DIFF
      └── LOG


H:
 └── SQLInstall

This is the baseline I would use for a new SQL Server 2025 production build. For a large enterprise deployment, I would additionally add: NUMA validation, storage latency baseline, Always On planning, security baseline, auditing, Extended Events, and automated health-check framework.