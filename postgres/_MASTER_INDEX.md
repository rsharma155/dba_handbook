# PostgreSQL DBA Scripts — Master Index

Run scripts with: `psql -h HOST -U USER -d DATABASE -f <path>`

## Framework (`00_Framework/`)

| File | Description |
|------|-------------|
| `00_Deploy_Framework.sql` | Deploy all framework objects |
| `fn_dba_excluded_wait_events.sql` | Benign wait event filter |
| `sp_dba_health_check.sql` | Health orchestrator |
| `sp_dba_active_sessions.sql` | Session monitor |
| `sp_dba_wait_analysis.sql` | Wait analysis |
| `sp_dba_index_review.sql` | Index health |
| `sp_dba_backup_review.sql` | Backup/archive review |
| `sp_dba_security_audit.sql` | Security audit |
| `sp_dba_baseline_capture.sql` | Baseline persistence |

## Diagnostics by layer

| Folder | Files |
|--------|-------|
| `01_Server_OS/` | cpu_utilization, memory_diagnostics, disk_io_analysis |
| `02_Instance_Config/` | postgresql_conf_audit, connection_settings, extension_audit |
| `03_Storage/` | database_size_and_growth, tablespace_audit, bloat_analysis, wal_archiving |
| `04_Performance_Diagnostics/` | wait_events, wait_events_reference, blocking_and_locks, top_resource_queries, vacuum_analyze_status |
| `05_Index_Statistics/` | index_usage_efficiency, unused_indexes, statistics_freshness, duplicate_indexes |
| `06_HA_DR/` | streaming_replication_status, replication_lag, logical_replication_status, backup_verification |
| `07_Security/` | role_privilege_audit, connection_encryption, password_policy_audit |
| `08_Advanced/` | autovacuum_health, checkpoint_and_wal, pg_stat_statements_deep, connection_analysis |
| `09_Maintenance/` | vacuum_bloat_maintenance, long_running_transactions, pg_cron_job_status |
| `10_Capacity_Planning/` | database_growth_forecast |
| `11_Query_Analysis/` | query_regression |
| `12_Extensions/` | extension_health |
| `13_Connection_Pooling/` | connection_pool_audit |
| `14_Baselines/` | performance_snapshot |

## Preventive measures

| File | Description |
|------|-------------|
| `01_create_governance_schema.sql` | Alert and policy tables |
| `02_capture_long_queries.sql` | Log long-running queries |
| `03_blocking_detection.sql` | Log blocking chains |
| `04_statement_timeout_policy.sql` | Timeout policy review |
| `05_alert_views.sql` | Dashboard views |
