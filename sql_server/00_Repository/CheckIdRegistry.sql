/*
================================================================================
CheckIdRegistry.sql - Stable CheckId definitions for all findings
================================================================================
Purpose:
    Registry of all CheckId values used by sp_DBA_HealthCheck and section
    collectors. Stable IDs enable ticketing integration and trend analysis.

Usage:
    Deploy into DBARepository. PowerShell and SQL consumers reference this
    table to map CheckId → human-readable description.
================================================================================
*/
IF OBJECT_ID(N'dbo.CheckIdRegistry', N'U') IS NOT NULL
    DROP TABLE dbo.CheckIdRegistry;
GO

CREATE TABLE dbo.CheckIdRegistry (
    [CheckId]           INT             NOT NULL PRIMARY KEY,
    [Area]              VARCHAR(50)     NOT NULL,
    [Finding]           VARCHAR(255)    NOT NULL,
    [Severity]          VARCHAR(20)     NOT NULL DEFAULT 'Medium',
    [Weight]            INT             NOT NULL DEFAULT 10,
    [Description]       VARCHAR(MAX)    NULL,
    [Remediation]       VARCHAR(MAX)    NULL,
    [ReferenceUrl]      VARCHAR(500)    NULL,
    [IsActive]          BIT             NOT NULL DEFAULT 1
);
GO

-- ============================================================================
-- CPU Checks (100-199)
-- ============================================================================
INSERT INTO dbo.CheckIdRegistry (CheckId, Area, Finding, Severity, Weight, Description) VALUES
(101, 'CPU',        'High Runnable Task Count',                      'High',     15, 'Queries waiting for CPU cycles. Check sys.dm_os_schedulers.'),
(102, 'CPU',        'High SQL Server CPU Utilization',               'High',     20, 'Historical CPU from ring buffers exceeds 80%.'),
(103, 'CPU',        'High External CPU Usage',                       'Medium',   10, 'Non-SQL processes consuming significant CPU.'),
(104, 'CPU',        'High Signal Waits',                             'High',     15, 'Signal wait ratio above 25% indicates CPU scheduling pressure.'),
(105, 'Performance', 'Plan Cache Bloat (Single-Use Adhoc)',          'Low',       5, 'Over 500MB of single-use adhoc plans in cache.');

-- ============================================================================
-- Security Checks (200-299)
-- ============================================================================
INSERT INTO dbo.CheckIdRegistry (CheckId, Area, Finding, Severity, Weight, Description) VALUES
(201, 'Security',    'Trustworthy Database Enabled',                  'High',     15, 'Privilege escalation risk via TRUSTWORTHY.'),
(202, 'Security',    'Guest User CONNECT Permission Granted',         'Medium',   10, 'Lateral movement risk if guest user has CONNECT.'),
(203, 'Best Practice','Page Verification not CHECKSUM',              'Critical', 25, 'Undetected corruption risk. All databases should use CHECKSUM.'),
(204, 'Best Practice','Auto-Shrink/Auto-Close Enabled',              'Critical', 20, 'Causes performance spikes and fragmentation.'),
(205, 'Indexes',     'Unused Indexes Detected',                      'Low',       5, 'Indexes with writes but no reads since last restart.'),
(206, 'Statistics',  'Stale Statistics Detected',                    'Medium',   10, 'Modification counter exceeds 20% of row count.'),
(207, 'Advanced',    'Query Store in READ_ONLY Mode',                'Medium',   10, 'Query Store cannot capture new plans.'),
(208, 'Advanced',    'High CDC Capture Latency',                     'Medium',   10, 'CDC latency exceeds 1 hour. Log may not reuse.');

-- ============================================================================
-- Configuration Checks (300-399)
-- ============================================================================
INSERT INTO dbo.CheckIdRegistry (CheckId, Area, Finding, Severity, Weight, Description) VALUES
(301, 'Config',      'Default Cost Threshold for Parallelism',       'Medium',   10, 'CTFP is at default 5. Trivial queries may parallelize.'),
(302, 'Config',      'MAXDOP is 0 (unlimited)',                      'Medium',   10, 'Single query may consume all CPU cores.'),
(303, 'Config',      'Optimize for Ad Hoc Workloads OFF',            'Low',       5, 'Plan cache bloat risk from ad-hoc queries.'),
(304, 'Config',      'Backup Compression Default OFF',               'Low',       5, 'Larger, slower backups without compression.'),
(305, 'Config',      'Dedicated Admin Connection (DAC) OFF',         'Medium',   10, 'Cannot connect when instance is hung.'),
(306, 'OS',          'Instant File Initialization DISABLED',          'Medium',   10, 'Slow file growth and restores.'),
(307, 'OS',          'Locked Pages in Memory (LPIM) not active',     'Medium',   10, 'OS may page SQL Server memory to disk.');

-- ============================================================================
-- Memory Checks (400-499)
-- ============================================================================
INSERT INTO dbo.CheckIdRegistry (CheckId, Area, Finding, Severity, Weight, Description) VALUES
(401, 'Memory',      'SQL Server not reaching Target Memory',        'High',     15, 'Possible OS memory pressure or max server memory cap.'),
(402, 'Memory',      'Low Page Life Expectancy',                     'Medium',   10, 'Buffer pool churn. Check scans, missing indexes, memory grants.'),
(403, 'Memory',      'Active Memory Grant Waits',                    'High',     20, 'Queries waiting for memory to execute.');

-- ============================================================================
-- Performance Checks (500-599)
-- ============================================================================
INSERT INTO dbo.CheckIdRegistry (CheckId, Area, Finding, Severity, Weight, Description) VALUES
(501, 'Performance',  'High Locking/Blocking Waits',                 'Critical', 25, 'LCK waits exceed 10% of total. Application timeouts likely.'),
(502, 'Performance',  'High Disk Read Waits (PAGEIOLATCH_SH)',       'High',     15, 'Data pages coming from disk. Check disk latency and indexing.'),
(503, 'Memory',       'Query Memory Grant Starvation',               'High',     20, 'Large queries waiting for memory grants.');

-- ============================================================================
-- Storage Checks (600-699)
-- ============================================================================
INSERT INTO dbo.CheckIdRegistry (CheckId, Area, Finding, Severity, Weight, Description) VALUES
(601, 'I/O',         'High Disk Latency Detected (>20ms)',           'High',     15, 'Slow query response due to storage latency.'),
(602, 'Storage',     'Critical VLF Count (>=1000)',                  'High',     15, 'Slow recovery and log backups. Rebuild log structure.'),
(603, 'Storage',     'Elevated VLF Count (200-999)',                 'Medium',   10, 'Log operations may slow. Plan maintenance.'),
(604, 'TempDB',      'Few TempDB Data Files',                        'Medium',   10, 'Possible PAGELATCH contention with fewer than 4 files.'),
(605, 'TempDB',      'Uneven TempDB File Growths',                   'High',     15, 'Proportional fill imbalance across TempDB files.'),
(606, 'Storage',     'Percentage-based Autogrowth Enabled',          'Medium',   10, 'Unpredictable growth pauses. Switch to fixed MB.');

-- ============================================================================
-- Index Checks (700-799)
-- ============================================================================
INSERT INTO dbo.CheckIdRegistry (CheckId, Area, Finding, Severity, Weight, Description) VALUES
(701, 'Indexes',     'High-Impact Missing Indexes Detected',         'Low',       5, 'Optimizer sees large potential gains. Validate before creating.');

-- ============================================================================
-- Backup Checks (800-899)
-- ============================================================================
INSERT INTO dbo.CheckIdRegistry (CheckId, Area, Finding, Severity, Weight, Description) VALUES
(801, 'Backups',     'Databases Missing Recent Backups',             'Critical', 30, 'Data loss risk. Verify backup jobs and msdb history.');

-- ============================================================================
-- AlwaysOn Checks (900-999)
-- ============================================================================
INSERT INTO dbo.CheckIdRegistry (CheckId, Area, Finding, Severity, Weight, Description) VALUES
(901, 'AlwaysOn',    'Availability Group Replica Not Healthy',       'Critical', 25, 'Failover or data loss risk. Check sync state and queues.');

PRINT N'CheckIdRegistry populated with ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + N' check definitions.';
GO
