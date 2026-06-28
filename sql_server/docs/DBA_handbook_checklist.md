I want to create handbook and checklist for a junior and new dba as well as experienced DBA for sql server. this handbook should be a guideline/reminder fand checklist for senior and experienced DBA, while it could be the first responder kit for a junior DBA and freshers. The handbook should have a series to checklists that a DBA should undertake or perform in live production environment. It should contain the real world problems, sitituations, scenarios, issues and how a senior dba, dba consultant would diagnose, troubleshoot and fix the issues. It should have multiple sections like: first key things to look at, check for the configuration, check for the settings, how to start? where to start? what are the next steps to look for? what to look for in an org where there exists DBA and has some process. 

This is a very good idea. A production DBA handbook should not be a SQL reference manual; it should behave like a field operations playbook: “I received an alert at 2 AM, what do I check first, what evidence do I collect, how do I isolate the problem, and what safe actions can I take?”

I would structure it as a SQL Server Production DBA Operations Handbook + Incident Response Checklist with two perspectives:

Junior DBA / New DBA: First responder kit → “Where do I start?”
Senior DBA / Consultant: Diagnostic framework → “How do I prove the root cause and prevent recurrence?”

Below is a proposed complete handbook blueprint.

SQL Server Production DBA Handbook
Production Operations, Troubleshooting & Incident Response Playbook

Audience

Junior DBA
SQL Server Administrator
Database Engineer
Senior DBA
DBA Consultant
Database Reliability Engineer (DBRE)

Purpose

A practical production guide for:

Daily operations
Monitoring
Troubleshooting
Incident response
Performance tuning
Security review
Capacity planning
Disaster recovery
Change management
Part 1 — DBA Mindset & Production Rules
1.1 The First Rule of Production DBA

Before changing anything:

Collect evidence

Never immediately:

Restart SQL Server
Kill sessions
Shrink databases
Rebuild all indexes
Change configuration
Increase memory
Restart server

First capture:

What happened?
When did it start?
Who reported it?
What changed?
Is it affecting:
    - CPU?
    - Memory?
    - Disk?
    - Network?
    - SQL workload?
    - Application?
Part 2 — New DBA First Response Kit
Production Incident Checklist

When receiving:

"Database is slow"

Do this sequence.

Step 1 — Is SQL Server Alive?

Checklist:

☐ Can I connect?

SELECT @@SERVERNAME,
       @@VERSION,
       GETDATE();

Check:

SQL Service running
SQL Agent running
Cluster status
Availability Group status
Step 2 — Check Overall Health

Run:

SELECT
cpu_count,
physical_memory_kb/1024 AS memory_MB,
sqlserver_start_time
FROM sys.dm_os_sys_info;

Look for:

Unexpected restart
Memory changes
CPU configuration changes
Step 3 — Check Current Blocking

One of the first things every DBA should check.

SELECT
blocking_session_id,
session_id,
wait_type,
wait_time,
command,
text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle)
WHERE blocking_session_id <> 0;

Questions:

Who is blocking?
What is the blocker doing?
Is it safe to kill?
Step 4 — Check Running Queries
SELECT
session_id,
status,
cpu_time,
total_elapsed_time,
logical_reads,
writes,
text
FROM sys.dm_exec_requests
CROSS APPLY sys.dm_exec_sql_text(sql_handle);

Look for:

Long running queries
Massive reads
Large writes
Bad plans
Part 3 — Production Environment Discovery Checklist

A new DBA joining an organization should first understand:

SQL Server Inventory

Maintain:

Item	Details
Server name	
Environment	PROD/UAT/DEV
SQL Version	
Edition	
OS Version	
CPU	
RAM	
Storage	
Cluster	
AlwaysOn	
Backup location	
Monitoring tool	
Database Inventory

For every database:

Checklist:

☐ Size

SELECT
DB_NAME(database_id),
SUM(size)*8/1024 size_MB
FROM sys.master_files
GROUP BY database_id;

☐ Recovery model

SELECT
name,
recovery_model_desc
FROM sys.databases;

☐ Compatibility level

☐ Owner

☐ Criticality

☐ RPO/RTO requirement

☐ Backup strategy

Part 4 — SQL Server Configuration Checklist
Memory Configuration

Check:

EXEC sp_configure 'max server memory';

Validate:

SQL Server should not consume all OS memory.

Common mistake:

max server memory = unlimited

Symptoms:

OS paging
Slow queries
Application timeout
MAXDOP Configuration

Check:

EXEC sp_configure 'max degree of parallelism';

Review:

CPU count
NUMA
workload type
Cost Threshold for Parallelism

Default:

5

Often too low.

Review:

EXEC sp_configure 
'cost threshold for parallelism';
TempDB Checklist

Every DBA must know TempDB.

Check:

SELECT *
FROM sys.database_files;

Validate:

☐ Multiple data files

☐ Equal file size

☐ Equal growth

☐ Fast storage

Common issues:

PAGELATCH contention
Temp table explosion
Sort spills
Part 5 — Daily DBA Checklist
Morning Health Check
SQL Server

☐ SQL Service running

☐ SQL Agent running

☐ Disk space

☐ CPU usage

☐ Memory pressure

☐ Failed jobs

Database

☐ Suspect databases

SELECT name,state_desc
FROM sys.databases;
Backup Validation

Check:

SELECT
database_name,
backup_finish_date,
type
FROM msdb.dbo.backupset
ORDER BY backup_finish_date DESC;

Verify:

☐ Full backup

☐ Differential

☐ Log backup

☐ Restore test

Job Monitoring

Check failed jobs:

SELECT *
FROM msdb.dbo.sysjobhistory
WHERE run_status <> 1;
Part 6 — Real Production Scenarios
Scenario 1
"Application is slow"
Junior DBA approach:

Check:

CPU
Blocking
Long queries
Disk
Senior DBA investigation:

Flow:

Application complaint
        |
        |
Check wait statistics
        |
        |
Identify bottleneck
        |
        |
Validate execution plan
        |
        |
Check recent changes
        |
        |
Fix
        |
        |
Prevent recurrence
Scenario 2
Blocking Storm

Symptoms:

Users cannot save
Queries hanging

Diagnosis:

sp_who2 active

Find:

Root blocker
Transaction age

Check:

DBCC OPENTRAN;

Resolution:

Possible:

Kill session
Application fix
Index improvement
Transaction redesign
Scenario 3
Transaction Log Full

Symptoms:

The transaction log for database is full

Checklist:

Check recovery:

SELECT recovery_model_desc
FROM sys.databases;

Find log reuse:

SELECT
name,
log_reuse_wait_desc
FROM sys.databases;

Common causes:

Missing log backup
Long running transaction
Replication delay
AG sync issue
Scenario 4
SQL Server CPU 100%

Checklist:

Find expensive queries:

SELECT TOP 20
total_worker_time,
execution_count,
text
FROM sys.dm_exec_query_stats
CROSS APPLY sys.dm_exec_sql_text(sql_handle)
ORDER BY total_worker_time DESC;

Investigate:

Bad plan
Parameter sniffing
Missing index
Data growth
Scenario 5
Database Growth Problem

Checklist:

Find largest tables:

EXEC sp_spaceused;

Questions:

Data growth expected?
Index growth?
Log growth?
Purging strategy?
Part 7 — Performance Tuning Checklist

Before tuning:

Collect:

☐ Query text

☐ Execution plan

☐ Wait stats

☐ IO stats

☐ CPU stats

Never tune based only on:

"query is slow"

Part 8 — Security Checklist

Review:

Login Audit
SELECT *
FROM sys.server_principals;

Check:

☐ Excess sysadmin users

☐ Disabled accounts

☐ Shared accounts

Part 9 — Backup & Disaster Recovery

Every DBA must know:

RPO

How much data loss is acceptable?

RTO

How quickly recovery must happen?

Checklist:

☐ Backup tested

☐ Restore tested

☐ DR documented

☐ Failover tested

Part 10 — Change Management Checklist

Before production change:

Impact

☐ Expected downtime

☐ Rollback plan

☐ Backup available

☐ Testing completed

☐ Approval received

Part 11 — Senior DBA Diagnostic Framework

When problem arrives:

Use:

The 5 Layer Model
Application
     |
SQL Query
     |
SQL Engine
     |
Operating System
     |
Hardware

Never assume SQL Server is the problem.

Part 12 — DBA Documentation Checklist

Every production environment should have:

☐ Server inventory

☐ Database inventory

☐ Backup policy

☐ Recovery document

☐ Monitoring dashboard

☐ Escalation matrix

☐ Maintenance window

☐ Known issues list

☐ Architecture diagram

Recommended Final Handbook Structure
SQL Server DBA Production Handbook

01 DBA Principles
02 Production Rules
03 First Responder Checklist
04 Environment Discovery
05 SQL Configuration Checklist
06 Daily Health Checks
07 Monitoring Checklist
08 Incident Response
09 Performance Troubleshooting
10 Blocking & Deadlocks
11 Backup Recovery
12 Security Audit
13 High Availability
14 Disaster Recovery
15 Capacity Planning
16 Change Management
17 Automation Scripts
18 Senior DBA Case Studies
19 Post Incident Review
20 DBA Career Growth Checklist

For a real organization, I would make this a living handbook with:

Markdown + Git repository
Version controlled scripts
PowerShell automation
SQL health check framework
Incident templates
RCA templates
Production readiness checklist

This structure can easily become a 150–200 page DBA operations manual used for onboarding and production support.

now with these details, write a prompt to generate a checklist in html format, with dynamic pages and UI and UX design and proper placement of header, text, table grids. 

Below is a complete AI development prompt you can use with a coding agent (Cursor, Claude Code, GPT Engineer, etc.) to generate the SQL Server DBA Handbook Checklist as a modern dynamic HTML application.

The prompt is designed to produce a production-quality interactive web handbook, not a static HTML document.

Prompt: Build SQL Server DBA Production Handbook Interactive Checklist Web Application
Role

Act as a Senior UI/UX Engineer, Full Stack Developer, SQL Server DBA Consultant, Technical Writer, and Enterprise Application Architect.

Your task is to build a modern interactive SQL Server DBA Production Handbook & Checklist Web Application.

The application should serve two personas:

Junior DBA / Fresh DBA
First responder guide
Step-by-step troubleshooting
What to check first
What commands to run
How to escalate
Senior DBA / DBA Consultant
Operational checklist
Production validation framework
Root cause analysis guide
Preventive controls
Best practices

The output should be a dynamic HTML-based documentation application with modern UI/UX, responsive design, searchable content, interactive checklist tracking, and professional enterprise documentation style.

Technology Requirements

Build using:

Frontend:

HTML5
CSS3
JavaScript ES6+
Bootstrap 5 or Tailwind CSS
Font Awesome / Lucide icons
Markdown-to-HTML rendering support
LocalStorage for checklist persistence

Optional enhancements:

React/Vue if required
Static site generator architecture
JSON-driven content model

Do not create a simple static page.

Build it like an internal enterprise DBA portal.

Application Goals

The application should provide:

DBA onboarding guide
Production incident response playbook
Daily operational checklist
Troubleshooting knowledge base
SQL scripts reference
Scenario based troubleshooting
RCA documentation guide
UI/UX Design Requirements
Overall Layout

Create a professional dashboard style interface.

Structure:

------------------------------------------------
Header
------------------------------------------------

Sidebar Navigation        Main Content Area

                         Page Content

                         Tables
                         Checklist
                         SQL Scripts
                         Diagrams

------------------------------------------------

Footer
------------------------------------------------
Header Design

Create sticky top navigation.

Include:

Left:

SQL Server DBA Production Handbook

Subtitle:

Operations | Troubleshooting | Incident Response

Right side:

Buttons:

Search
Dark Mode
Export Checklist
Progress Status
Sidebar Navigation

Create collapsible navigation.

Sections:

Dashboard

1. DBA Principles

2. First Responder Checklist

3. Production Environment Discovery

4. SQL Server Configuration

5. Daily Health Checks

6. Monitoring Checklist

7. Incident Response

8. Performance Troubleshooting

9. Blocking & Deadlocks

10. Transaction Log Issues

11. Backup & Recovery

12. Security Audit

13. High Availability

14. Disaster Recovery

15. Capacity Planning

16. Change Management

17. Automation Scripts

18. DBA Case Studies

19. RCA Templates

20. DBA Growth Path

Each menu item should dynamically load content without refreshing the page.

Dashboard Page

Create an executive DBA dashboard.

Cards:

Environment Health

Example:

SQL Server Health

✔ Configuration Reviewed
✔ Backup Verified
✔ Monitoring Enabled
Checklist Progress

Show:

Completed:
35%

Remaining:
65%

Use progress bars.

Quick Actions

Buttons:

Run Morning Checklist

Start Incident Investigation

Review Configuration

Backup Validation

Performance Analysis
Content Page Design

Every checklist page should follow this template:

Page Header

Example:

Blocking & Deadlock Troubleshooting

Description:

Production checklist for identifying and resolving blocking issues.
Section Layout

Each section:

Example:

First Checks

Use:

Card component

Problem:

Users reporting database slowness


Check:

☐ Identify blocking session

☐ Check active transactions

☐ Review wait statistics
Checklist Component

Every checklist item should have:

Checkbox

Status:

Not Started
In Progress
Completed

Notes field:

Example:

DBA Notes:
________________

Save state using LocalStorage.

Tables

Use modern responsive tables.

Example:

Check	Command	Expected Result
SQL Service	SELECT @@VERSION	Server responding
Blocking	sp_who2	No abnormal blockers

Requirements:

Searchable
Sortable
Mobile responsive
SQL Script Viewer Component

Create syntax highlighted SQL blocks.

Example:

SELECT
name,
state_desc
FROM sys.databases;

Features:

Buttons:

Copy

Runbook Reference

Explain Script

Incident Scenario Pages

Create real production scenarios.

Each scenario should follow:

Scenario

Example:

Application is slow
Symptoms
Users report timeout errors
Investigation Flow

Display as timeline:

Application Issue

↓

Check SQL Sessions

↓

Check Blocking

↓

Check CPU/Memory

↓

Analyze Query Plan

↓

Apply Fix

↓

Document RCA
Resolution

Include:

Immediate fix
Permanent fix
Prevention
Required Content Structure

Create JSON based content model:

Example:

{
"title":"Blocking Troubleshooting",
"type":"checklist",

"sections":[

{
"name":"Initial Checks",

"items":[

{
"text":"Check blocking sessions",
"sql":"sp_who2 active",
"priority":"High"
}

]

}

]
}

HTML pages should render dynamically from JSON.

Required Checklist Categories

Generate detailed content for:

1. First Production Response

Include:

SQL availability
CPU
Memory
Disk
Blocking
Long running queries
2. SQL Configuration Review

Include:

Max memory
MAXDOP
Cost threshold
TempDB
Trace flags
3. Daily DBA Checklist

Include:

Backup validation
Failed jobs
Disk monitoring
Error logs
4. Performance Troubleshooting

Include:

CPU issues
IO bottleneck
Wait statistics
Execution plans
Index issues
5. Database Recovery

Include:

Full backup
Differential backup
Transaction log backup
Restore testing
6. Security Checklist

Include:

Login review
Permission audit
SA account review
7. High Availability

Include:

Always On
Failover validation
Replication
Add Advanced Features
Global Search

Search:

Checklist items
SQL commands
Troubleshooting scenarios
Bookmark Feature

Allow DBA to bookmark:

Important checks
Common issues
Print / Export

Generate:

PDF friendly view
Printable checklist
Responsive Design

Must work on:

Desktop

Laptop

Tablet

Mobile

Visual Style

Use enterprise style:

Inspired by:

Azure Portal
AWS Console
Grafana
Datadog

Design principles:

Clean
Professional
Minimal
Technical
Easy navigation
Folder Structure

Generate:

dba-handbook/

│
├── index.html

├── assets/

│   ├── css/

│   ├── js/

│   └── icons/

│

├── data/

│   ├── checklist.json

│   ├── scenarios.json

│   └── scripts.json


├── pages/

│

├── README.md

└── CHANGELOG.md
Development Quality Requirements

Follow:

Clean code
Modular JavaScript
Reusable components
Proper comments
Documentation
Accessibility
Mobile first design
Final Output

Generate:

Complete HTML application
CSS styling
JavaScript logic
JSON content files
Sample DBA checklist content
Sample troubleshooting scenarios
Installation instructions
Extension guide for adding new checklist modules

The final application should look like a professional internal SQL Server DBA Operations Portal used by enterprise production support teams.

now since there's already a lot of sql scripts already in place for most of the actions. So, the prompt should be to utilze the existing scripts and the checklist should point to the specific sql scripts. It should show the absolute path of all the existing scripts locations

You should modify the prompt so the application is not generating SQL scripts, but acts as a DBA Operations Runbook + Script Execution Catalog that maps every checklist activity to the already existing SQL scripts repository.

The key design change:

Checklist = what DBA needs to do
Script Repository = how DBA performs it
Handbook = when/why to execute it
Path Mapping = where the script physically exists

Use the following updated prompt:

Prompt: Build SQL Server DBA Production Handbook with Existing SQL Script Integration & Runbook Mapping
Role

Act as a Senior SQL Server DBA Consultant, Enterprise Documentation Architect, Full Stack Developer, and DevOps Automation Engineer.

Build a production-grade SQL Server DBA Operations Handbook Web Application that integrates with an existing SQL script repository.

The application should NOT create duplicate SQL scripts.

The primary goal is:

Convert existing DBA scripts into an interactive production checklist system where every operational task points to the exact SQL script location, execution purpose, prerequisites, expected output, and troubleshooting guidance.

Core Requirement

The organization already has a large collection of SQL Server scripts.

The application must create a searchable knowledge layer on top of those scripts.

Example:

DBA Task:

Check database backup status

Checklist:

☐ Validate backup completion
☐ Verify backup age
☐ Check failed backup jobs

Linked Script:

Script Name:
backup_validation.sql


Absolute Path:

D:\DBA\Repository\Production\Backup\backup_validation.sql


Purpose:

Checks last successful FULL, DIFF and LOG backups


Run Frequency:

Daily


Risk:

Read Only
Application Architecture

Create a script-driven handbook.

Architecture:

                 DBA Handbook UI

                       |

              Checklist Engine

                       |

              Script Metadata Layer

                       |

              Existing SQL Scripts Repository

                       |

              SQL Server Environment
Script Repository Integration

Assume existing scripts are stored in:

Example:

D:\DBA\SQLScripts\

├── HealthCheck

├── Performance

├── Backup

├── Security

├── Maintenance

├── Monitoring

├── AlwaysOn

├── Troubleshooting

└── Emergency

The application must maintain metadata for every script.

Script Metadata Model

Create:

scripts.json

Example:

{
"id":"CHK001",

"name":"Database Health Check",

"category":"Health",

"script_file":"health_check.sql",

"absolute_path":
"D:\\DBA\\SQLScripts\\HealthCheck\\health_check.sql",

"description":
"Checks SQL Server database health status",

"execution_type":
"Read Only",

"frequency":
"Daily",

"risk_level":
"Low",

"related_checklist":[

"Morning DBA Health Check",

"Production Readiness Review"

],

"expected_output":

"Database state should be ONLINE"

}
Checklist Data Model

Create:

checklist.json

Example:

{

"id":"DAILY001",

"title":
"Morning Production Health Check",


"steps":[


{

"task":

"Verify SQL Server Availability",


"priority":

"Critical",


"script_reference":

"CHK001",


"script_path":

"D:\\DBA\\SQLScripts\\HealthCheck\\server_status.sql",


"expected_result":

"SQL Server responds successfully"

}

]

}
UI/UX Design

Build an enterprise DBA portal.

Main Screen Layout
------------------------------------------------

SQL Server DBA Operations Handbook


Search Scripts | Search Checklist | Export


------------------------------------------------


Sidebar


Dashboard

Health Checks

Backup

Performance

Security

HA/DR

Maintenance

Troubleshooting


------------------------------------------------


Content Area

Checklist + Script Mapping


------------------------------------------------
Checklist Page

Example:

Database Backup Validation

Description:

Validate production backup health.

Checklist:

Status	Task	Script	Location	Risk
☐	Check backup age	backup_check.sql	D:\DBA\Scripts\Backup	Low
☐	Validate failed jobs	job_monitor.sql	D:\DBA\Scripts\Monitoring	Low
Script Details Panel

When clicking a script:

Show:

Script Information


Name:

backup_check.sql


Location:

D:\DBA\SQLScripts\Backup\backup_check.sql


Purpose:

Validate backup completion


Owner:

DBA Team


Last Reviewed:

2026-01-01


Execution:

Read Only


Dependencies:

msdb access


Rollback:

Not Required
Add Script Explorer Module

Create a page:

SQL Script Repository

Features:

Search:

backup
blocking
deadlock
performance
index
security

Filters:

Category
Risk
Frequency
Environment

Display:

Script Name

Description

Path

Usage

Related Checklist

Last Updated
DBA Workflow

Example:

Incident:

"Application is slow"

DBA opens:

Performance Troubleshooting

Checklist:

☐ Check CPU pressure

☐ Check blocking

☐ Check expensive queries

☐ Review waits

Each item links:

CPU Check

↓

D:\DBA\Scripts\Performance\cpu_analysis.sql


Blocking Check

↓

D:\DBA\Scripts\Troubleshooting\blocking.sql
Required Handbook Sections

Generate modules:

1. Daily DBA Checklist

Mapping:

HealthCheck folder
Monitoring folder
2. Incident Response

Mapping:

Troubleshooting folder
Emergency folder
3. Performance Tuning

Mapping:

Performance folder
4. Backup Validation

Mapping:

Backup folder
5. Security Review

Mapping:

Security folder
6. Maintenance

Mapping:

Maintenance folder
7. High Availability

Mapping:

AlwaysOn folder
Add DBA Runbook Features
Execution History

Track:

Checklist Item

Executed By

Date

Environment

Result

Notes
Add Script Validation

Application should verify:

Script exists
Path valid
Metadata complete

Show:

Green:

Script Available

Red:

Missing Script
Import Existing Scripts

Create utility:

script_scanner

Function:

Scan:

D:\DBA\SQLScripts

Automatically generate:

scripts.json

Extract:

File name
Folder
Path
Extension
Last modified date
Size
Folder Structure
dba-handbook/


│

├── index.html


├── assets/

│   ├── css/

│   └── js/


├── data/

│

│   ├── checklist.json

│   ├── scripts.json

│   └── categories.json


├── scripts/

│

│   └── scanner/


├── repository/

│

│   └── README.md


└── docs/

    └── architecture.md

Additional Requirements

The application must:

Never duplicate SQL logic
Always reference existing scripts
Show absolute script path
Provide DBA explanation before execution
Explain expected output
Maintain audit history
Support adding new scripts easily
Support hundreds/thousands of scripts
Final Deliverables

Generate:

Interactive HTML DBA Handbook
Dynamic checklist engine
Script catalog module
JSON metadata structure
Script scanner utility
Search functionality
Export capability
Professional enterprise UI
Documentation

The final product should resemble an internal Enterprise SQL Server DBA Command Center / Operations Portal, where a DBA can quickly identify the issue, follow the checklist, and execute the correct approved script from the existing repository.