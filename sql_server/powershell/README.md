# SQL Optima Assessment Framework — PowerShell

Automated health assessment for SQL Server instances. Generates HTML reports with severity-scored findings, recommendations, and drill-down sections.

## Prerequisites

### PowerShell modules

Install once per machine:

```powershell
Install-Module dbatools -Scope CurrentUser -Force
Install-Module PSWriteHTML -Scope CurrentUser -Force
```

### SQL Server objects

Deploy framework objects to each instance before running:

```sql
-- 1. Create database (run once)
sqlcmd -S YourServer -d master -i "00_Repository/DBARepository_Create.sql" -C

-- 2. Deploy all SPs, functions, tables (run once)
sqlcmd -S YourServer -d DBARepository -i "00_Repository/DBARepository_Deploy.sql" -C
```

### Permissions

The assessment service account needs:

| Permission | Why |
|------------|-----|
| `VIEW SERVER STATE` | All DMV queries |
| `VIEW ANY DEFINITION` | Security, encryption, Extended Events |
| `msdb` read access | Backup history, job history |
| `DBARepository` owner | Deploy and execute framework objects |

---

## Quick Start

```powershell
# 1. Navigate to powershell folder
cd .\powershell\

# 2. Run a Quick assessment (30-90 seconds)
.\Invoke-SqlOptimaAssessment.ps1 -SqlInstance PROD-SQL01 -Profile Quick

# 3. Open the HTML report
# Output: ..\output\PROD-SQL01_20260616_1430.html
```

---

## Assessment Profiles

| Profile | Duration | Includes | Use when |
|---------|----------|----------|----------|
| **Quick** | 30–90 sec | Health check dashboard + findings | Daily triage, many servers |
| **Standard** | 3–8 min | Quick + waits, backup, security, config | Weekly assessment |
| **Deep** | 10–30+ min | Standard + index stats, QS regression | Off-peak, migration audit |

---

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SqlInstance` | string | *required* | SQL Server instance name |
| `-Profile` | string | `Quick` | Assessment profile |
| `-OutputPath` | string | `..\output` | HTML output directory |
| `-DatabaseList` | string | `NULL` | Comma-separated DBs to scope |
| `-BackupHoursSLA` | int | `24` | Backup SLA in hours |
| `-ConfigPath` | string | auto | Path to custom config JSON |
| `-Credential` | PSCredential | `NULL` | SQL auth credentials |
| `-Persist` | switch | `false` | Save to DBARepository history |
| `-OutputJson` | switch | `false` | Also export JSON |

---

## Examples

### Daily triage (Quick profile)

```powershell
.\Invoke-SqlOptimaAssessment.ps1 -SqlInstance PROD-SQL01 -Profile Quick
```

### Weekly assessment with specific databases

```powershell
.\Invoke-SqlOptimaAssessment.ps1 -SqlInstance PROD-SQL01 -Profile Standard -DatabaseList 'SalesDB,HRDB,FinanceDB'
```

### Deep assessment with JSON export

```powershell
.\Invoke-SqlOptimaAssessment.ps1 -SqlInstance PROD-SQL01 -Profile Deep -OutputJson -OutputPath C:\Reports
```

### Persist results for trending

```powershell
.\Invoke-SqlOptimaAssessment.ps1 -SqlInstance PROD-SQL01 -Profile Standard -Persist
```

### SQL authentication

```powershell
$cred = Get-Credential
.\Invoke-SqlOptimaAssessment.ps1 -SqlInstance PROD-SQL01 -Credential $cred
```

### Multiple servers (pipeline)

```powershell
@('PROD-SQL01', 'PROD-SQL02', 'PROD-SQL03') | ForEach-Object {
    .\Invoke-SqlOptimaAssessment.ps1 -SqlInstance $_ -Profile Quick
}
```

---

## HADR Checklist Generator

Generates an interactive HTML checklist for SQL Server Always On Availability Group deployment. Supports 1-3 secondary replicas, multiple witness types, and 1-2 domain controllers.

### Usage

```powershell
# Interactive mode (default) — walks you through configuration
.\Generate-HADRChecklist.ps1

# Non-interactive with parameters
.\Generate-HADRChecklist.ps1 -SecondaryReplicas 2 -WitnessType Cloud -DomainControllerCount 2

# With readable secondary and backup on secondary
.\Generate-HADRChecklist.ps1 -SecondaryReplicas 1 -IncludeReadableSecondary -IncludeBackupOnSecondary
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SecondaryReplicas` | int | `1` | Number of secondary replicas (1-3) |
| `-WitnessType` | string | `FileShare` | Cluster witness: FileShare, Cloud, Disk, or None |
| `-DomainControllerCount` | int | `1` | Number of domain controllers (1-2) |
| `-OutputPath` | string | `HADR_Checklist.html` | Output HTML file path |
| `-IncludeReadableSecondary` | switch | `false` | Enable read-only routing |
| `-IncludeBackupOnSecondary` | switch | `false` | Configure backups on secondary replica |
| `-Interactive` | switch | auto | Force interactive setup wizard |

### Checklist Phases

The generated checklist covers 22 phases:
1. Infrastructure Planning
2. Domain Controller Setup
3. Service Accounts & Security Groups
4. DNS Configuration
5. Network Configuration on SQL Servers
6. Join SQL Servers to Domain
7. SQL Server Installation
8. Enable Always On Availability Groups
9. Install WSFC Feature
10. Validate Cluster Configuration
11. Create WSFC Cluster
12. Configure Cluster Quorum
13. Configure SQL Server HADR Endpoints
14. Windows Firewall Configuration
15. Create Test Database and Prepare for AG
16. Restore Database on Secondary Nodes
17. Create Availability Group
18. Join Secondary Replicas to AG
19. Create AG Listener
20. Test Failover Scenarios
21. Configure Monitoring and Alerts
22. Operational Housekeeping & Final Verification

---

## Custom Configuration

Edit `config/assessment.config.json`:

```json
{
    "Profile": "Standard",
    "DatabaseList": null,
    "BackupHoursSLA": 24,
    "RegressionPctThreshold": 50,
    "Sections": {
        "Inventory": true,
        "HealthCheck": true,
        "Waits": true,
        "Backup": true,
        "Security": true,
        "Config": true,
        "DiskLatency": true,
        "TempDb": true,
        "QueryStore": true,
        "IndexDeep": false
    },
    "PersistToRepository": false
}
```

---

## Output

### HTML Report

The report includes:

- **Executive Summary** — Health score (0-100) with traffic light (GREEN/YELLOW/RED)
- **Dashboard Metrics** — CPU, memory, PLE, instance uptime
- **Findings Table** — All issues with CheckId, severity, area, impact, and remediation
- **Section Results** — Waits, backups, security, configuration, Query Store regressions

### JSON Export (`-OutputJson`)

Machine-readable output for automation pipelines:

```json
{
    "ServerName": "PROD-SQL01",
    "Profile": "Standard",
    "GeneratedUtc": "2026-06-16T14:30:00Z",
    "Dashboard": { "Health_Score": 78, "SQL_CPU_Pct": 45, ... },
    "Findings": [...],
    "Sections": [...]
}
```

---

## Folder Structure

```
powershell/
├── Invoke-SqlOptimaAssessment.ps1    # Main entry point
├── Generate-HADRChecklist.ps1        # Interactive HADR checklist generator
├── Private/
│   ├── Get-AssessmentConfig.ps1      # Config loader
│   ├── Invoke-SectionCollector.ps1   # SQL section runner
│   └── Export-AssessmentHtml.ps1     # HTML report generator
├── config/
│   └── assessment.config.json        # Default configuration
└── README.md                         # This file
```

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Cannot find module 'dbatools'` | Module not installed | `Install-Module dbatools -Scope CurrentUser` |
| `Cannot find module 'PSWriteHTML'` | Module not installed | `Install-Module PSWriteHTML -Scope CurrentUser` |
| `DBARepository not found` | Database not created | Run `DBARepository_Create.sql` |
| `fn_DBA_ExcludedWaitTypes missing` | Framework not deployed | Run `DBARepository_Deploy.sql` |
| `Access denied` | Insufficient permissions | Grant `VIEW SERVER STATE` and `msdb` access |
| `Connection timeout` | Network or instance down | Verify instance name and network connectivity |
