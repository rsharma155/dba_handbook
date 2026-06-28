# DBA Framework — PostgreSQL

Deploy order (handled by `00_Deploy_Framework.sql`):

1. `fn_dba_excluded_wait_events.sql`
2. `sp_dba_active_sessions.sql`
3. `sp_dba_wait_analysis.sql`
4. `sp_dba_index_review.sql`
5. `sp_dba_backup_review.sql`
6. `sp_dba_security_audit.sql`
7. `sp_dba_baseline_capture.sql`
8. `sp_dba_health_check.sql`

All objects live in the `dba` schema on `dba_repository`.
