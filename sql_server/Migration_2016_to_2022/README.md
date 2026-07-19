# SQL Server 2016 → 2022 Migration Scripts

Read-only assessment and validation scripts for the migration checklist.

| Script | Phase | Purpose |
| --- | --- | --- |
| `01_instance_version_and_patch.sql` | Discovery | Version, edition, SP/CU level |
| `02_server_configuration.sql` | Discovery | sp_configure, memory, MAXDOP, TempDB metadata |
| `03_trace_flags_documentation.sql` | Discovery | Active trace flags |
| `04_database_inventory.sql` | Discovery | Database sizes, compat, recovery |
| `05_database_features_tde_cdc.sql` | Discovery | TDE, CDC, In-Memory, FileStream |
| `06_ha_dr_topology.sql` | Discovery | AG, mirroring, log shipping |
| `07_logins_and_server_roles.sql` | Discovery | Logins, sysadmin, server roles |
| `08_orphaned_users_precheck.sql` | Discovery | Orphaned DB users (LOCK_TIMEOUT-safe multi-DB) |
| `09_linked_servers_and_jobs.sql` | Discovery | Linked servers, Agent jobs |
| `10_deprecated_features_usage.sql` | Discovery | Deprecated feature counters |
| `11_stretch_database_check.sql` | Blockers | Stretch Database objects |
| `12_polybase_hadoop_check.sql` | Blockers | PolyBase HDFS external sources |
| `13_pre_migration_readiness.sql` | Pre-migration | Combined readiness summary |
| `14_backup_chain_verification.sql` | Pre-migration | Last backup per database |
| `15_post_install_config_audit.sql` | Target build | Post-install config validation |
| `16_pre_cutover_baseline.sql` | Cutover | Wait stats + top sessions snapshot |
| `17_cutover_validation.sql` | Cutover | Version, DB state, Agent |
| `18_post_migration_validation.sql` | Post-migration | Full day-1 validation |
| `19_query_store_enable_and_status.sql` | Post-migration | Query Store status / enable |
| `20_compatibility_level_report.sql` | Post-migration | Compat level + database scoped configs |
| `21_rollback_evidence_capture.sql` | Rollback | Evidence + database scoped configs (CE/PSP) |
| `22_ag_health_check.sql` | HA/DR | Always On AG health |
| `23_tde_certificate_inventory.sql` | Security | TDE certs and encryption state |
| `24_post_restore_checkdb_and_stats.sql` | Post-restore | CHECKDB commands + sp_updatestats templates |

**HTML checklist:** `sql_server/output/SQL_2016_to_2022_Migration_Checklist.html`

**Shareable zip (HTML + scripts):** `sql_server/output/SQL_2016_to_2022_Migration_Package.zip`

Regenerate:

```powershell
cd sql_server\powershell
.\Generate-Migration2016To2022Checklist.ps1
```

Unzip the package, open the HTML, and click script links (Quick Links / Script Library) — scripts are embedded, so no server is required.