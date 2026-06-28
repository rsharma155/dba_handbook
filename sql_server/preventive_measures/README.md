# Preventive Measures Framework

## Overview

A comprehensive preventive monitoring and enforcement framework for SQL Server production environments. Uses a **layered automation approach** to detect and respond to dangerous queries, massive DML operations, and blocked applications.

## Architecture: Layered Automation

```
┌─────────────────────────────────────────────────────────────────┐
│                    AUTOMATION LAYERS                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  LAYER 1: Extended Events (Always-On, Kernel-Level)              │
│  ├─ Governance_Long_Queries     (queries > 10s)                  │
│  ├─ Governance_Massive_DML      (DML > 100K rows)                │
│  ├─ Governance_Blocking         (blocking > 5s)                  │
│  └─ Governance_Login_Monitor    (failed logins)                  │
│      ↓ Near-zero overhead, real-time capture                     │
│      File: 07_Setup_Extended_Events.sql                          │
│                                                                  │
│  LAYER 2: Policy Enforcement (Scheduled Processing)              │
│  ├─ sp_Capture_Running_Queries    (DMV snapshot)                 │
│  ├─ sp_Check_Long_Running_Queries (process XE + DMV)            │
│  ├─ sp_Check_Massive_DML          (process XE + DMV)            │
│  ├─ sp_Check_Blocked_Applications (check blocked list)          │
│  └─ sp_Enforce_Query_Policy       (master orchestrator)         │
│      ↓ Processes events and takes action                         │
│      Files: 02-06                                                │
│                                                                  │
│  LAYER 3: Alert Management (Notifications)                       │
│  ├─ sp_View_Alerts              (view/filter alerts)             │
│  ├─ sp_Acknowledge_Alert        (acknowledge alerts)             │
│  ├─ sp_Process_XE_Alerts        (process XE into alerts)        │
│  └─ sp_Get_Alert_Summary        (statistics)                    │
│      ↓ Notifies DBA team                                         │
│      File: 08_Alert_Management.sql                               │
│                                                                  │
│  LAYER 4: Dashboard & Reporting                                   │
│  ├─ vw_Current_Running_Queries                                   │
│  ├─ vw_Long_Running_Queries                                      │
│  ├─ vw_Alert_Summary                                             │
│  └─ vw_Job_Status                                                │
│      ↓ Visualization                                             │
│      File: 09_Dashboard_Views.sql                                 │
│                                                                  │
│  AUTOMATION: SQL Agent Jobs                                       │
│  ├─ Governance_XE_Health_Monitor   (every 5 min)                 │
│  ├─ Governance_Query_Capture       (every 1 min)                 │
│  ├─ Governance_Enforcement         (every 1 min)                 │
│  ├─ Governance_Alert_Processor     (every 5 min)                 │
│  └─ Governance_Data_Cleanup        (daily 2 AM)                  │
│      ↓ Orchestrates all layers                                   │
│      File: 10_Create_SQL_Agent_Jobs.sql                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Key Features

| Feature | Description |
|---------|-------------|
| **Real-time Capture** | Extended Events capture events as they happen (no polling delay) |
| **Near-zero Overhead** | XE runs in kernel, not user mode |
| **Layered Defense** | Multiple automation layers ensure reliability |
| **Configurable Thresholds** | Adjust time/row thresholds via Policy_Config table |
| **Multiple Action Types** | WARN, LOG, ALERT, KILL, BLOCK |
| **Email Notifications** | Automatic alerts to DBA team |
| **Historical Analysis** | XE file targets for trend analysis |
| **Backward Compatible** | Works on SQL Server 2016, 2017, 2019, 2022 |

## Requirements

- SQL Server 2016, 2017, 2019, or 2022
- Sysadmin permissions for initial setup
- Enterprise Edition for Resource Governor features
- Database Mail configured for email notifications

## Installation (Layered Deployment)

### Step 1: Foundation - Create Governance Database

```sql
-- Creates database and all tables
:01_Create_Governance_Database.sql
```

### Step 2: Layer 1 - Extended Events (Primary Capture)

```sql
-- Creates XE sessions for real-time capture
:07_Setup_Extended_Events.sql
```

This is the **foundation** - XE captures events in real-time with near-zero overhead.

### Step 3: Layer 2 - Stored Procedures

Run these scripts in order:

1. `02_Capture_Running_Queries.sql` - DMV snapshot (supplements XE)
2. `03_Check_Long_Running_Queries.sql` - Process XE + DMV for long queries
3. `04_Check_Massive_DML.sql` - Process XE + DMV for massive DML
4. `05_Check_Blocked_Applications.sql` - Check blocked applications
5. `06_Enforce_Query_Policy.sql` - Master orchestrator

### Step 4: Layer 3 - Alert Management

```sql
-- Alert management and notifications
:08_Alert_Management.sql
```

### Step 5: Layer 4 - Dashboard Views

```sql
-- Monitoring views
:09_Dashboard_Views.sql
```

### Step 6: Automation - SQL Agent Jobs

```sql
-- Creates all automation jobs
:10_Create_SQL_Agent_Jobs.sql
```

### Step 7: Optional - Resource Governor (Enterprise Only)

```sql
-- Workload isolation (Enterprise Edition only)
:11_Setup_Resource_Governor.sql
```

## Usage

### Verify Installation

```sql
-- Check XE sessions are running
SELECT name, create_time, session_status_desc 
FROM sys.dm_xe_session_sessions 
WHERE name LIKE 'Governance_%';

-- Check SQL Agent jobs
SELECT name, enabled, date_created 
FROM msdb.dbo.sysjobs 
WHERE name LIKE 'Governance_%';
```

### Query Captured Events (Real-Time)

```sql
-- Query recent long queries from XE
SELECT TOP 20 *
FROM [DBA_Governance].[governance].[fn_Get_XE_Events]('Governance_Long_Queries', 20);

-- Query recent massive DML
SELECT TOP 20 *
FROM [DBA_Governance].[governance].[fn_Get_XE_Events]('Governance_Massive_DML', 20);
```

### View Alerts

```sql
-- View recent alerts
EXEC [governance].[sp_View_Alerts] @Hours_Back = 24;

-- View only critical alerts
EXEC [governance].[sp_View_Alerts] @Severity = 'CRITICAL';

-- Get alert summary
EXEC [governance].[sp_Get_Alert_Summary] @Hours_Back = 24;
```

### Run Enforcement Manually

```sql
-- Run all checks
EXEC [governance].[sp_Enforce_Query_Policy] @Verbose = 1;

-- Run specific checks
EXEC [governance].[sp_Check_Long_Running_Queries];
EXEC [governance].[sp_Check_Massive_DML];
EXEC [governance].[sp_Check_Blocked_Applications];
```

### Process XE Events into Alerts

```sql
-- Process XE events from last hour
EXEC [governance].[sp_Process_XE_Alerts] @Hours_Back = 1;
```

### Acknowledge Alerts

```sql
-- Acknowledge a single alert
EXEC [governance].[sp_Acknowledge_Alert] @Alert_ID = 123;

-- Acknowledge all critical alerts older than 1 hour
EXEC [governance].[sp_Acknowledge_Multiple_Alerts] 
    @Severity = 'CRITICAL', 
    @Older_Than_Hours = 1;
```

## Configuration

### Policy Configuration

Update thresholds via the Policy_Config table:

```sql
-- Update thresholds
UPDATE [governance].[Policy_Config]
SET [Long_Query_Threshold_Seconds] = 15,      -- 15 seconds
    [Large_DML_Row_Count] = 50000,             -- 50K rows
    [Action_Type] = 'KILL'                     -- Auto-kill violations
WHERE [Policy_Name] = 'Production Query Protection';
```

### Action Types

| Type | Description |
|------|-------------|
| `WARN` | Log warning only |
| `LOG` | Log to alert table |
| `ALERT` | Generate alert (default) |
| `KILL` | Kill offending sessions |
| `BLOCK` | Block and kill sessions |

### Block Applications

```sql
-- Block a new application
INSERT INTO [governance].[Blocked_Applications] ([Application_Name], [Reason])
VALUES ('MyApp', 'Not authorized for production');

-- Unblock an application
DELETE FROM [governance].[Blocked_Applications]
WHERE [Application_Name] = 'MyApp';
```

## Monitoring Views

| View | Description |
|------|-------------|
| `vw_Current_Running_Queries` | All currently running user queries |
| `vw_Long_Running_Queries` | Queries exceeding time threshold |
| `vw_Alert_Summary` | Alert statistics by type/severity |
| `vw_Query_History_Summary` | Historical query statistics |
| `vw_Top_Resource_Users` | Top resource consumers |
| `vw_Job_Status` | SQL Agent job status |

## Files

| File | Layer | Description |
|------|-------|-------------|
| `01_Create_Governance_Database.sql` | Foundation | Creates database and tables |
| `02_Capture_Running_Queries.sql` | 2 | DMV snapshot capture |
| `03_Check_Long_Running_Queries.sql` | 2 | Process XE + DMV for long queries |
| `04_Check_Massive_DML.sql` | 2 | Process XE + DMV for massive DML |
| `05_Check_Blocked_Applications.sql` | 2 | Check blocked applications |
| `06_Enforce_Query_Policy.sql` | 2 | Master enforcement orchestrator |
| `07_Setup_Extended_Events.sql` | 1 | XE sessions (primary capture) |
| `08_Alert_Management.sql` | 3 | Alert management and notifications |
| `09_Dashboard_Views.sql` | 4 | Monitoring views |
| `10_Create_SQL_Agent_Jobs.sql` | Automation | SQL Agent jobs |
| `11_Setup_Resource_Governor.sql` | Optional | RG configuration (Enterprise) |

## Best Practices

1. **Start with WARN mode** before enabling KILL to understand workload patterns
2. **Monitor XE overhead** - check `dropped_event_count` for data loss
3. **Review alerts regularly** and adjust thresholds as needed
4. **Use Resource Governor** on Enterprise for workload isolation
5. **Configure Database Mail** for email notifications
6. **Exclude ETL windows** by disabling jobs during maintenance
7. **Archive XE files** for historical analysis

## Troubleshooting

### XE Sessions Not Running

```sql
-- Check if XE sessions exist
SELECT name, create_time 
FROM sys.server_event_sessions 
WHERE name LIKE 'Governance_%';

-- Restart stopped sessions
ALTER EVENT SESSION [Governance_Long_Queries] ON SERVER STATE = START;
```

### Jobs Not Running

```sql
-- Check job status
SELECT name, enabled, date_created 
FROM msdb.dbo.sysjobs 
WHERE name LIKE 'Governance_%';

-- Enable disabled jobs
UPDATE msdb.dbo.sysjobs 
SET enabled = 1 
WHERE name = 'Governance_Enforcement';
```

### No Emails Received

```sql
-- Check Database Mail configuration
SELECT * FROM msdb.dbo.sysmail_account;

-- Test email
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = N'DBA_Alerts',
    @recipients = N'your-email@company.com',
    @subject = N'Test Email',
    @body = N'This is a test email from Governance framework.';
```