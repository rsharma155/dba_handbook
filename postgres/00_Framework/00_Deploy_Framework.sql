/*
================================================================================
00_Deploy_Framework.sql — Deploy all DBA framework objects
================================================================================
Description:
    Run once against dba_repository after 00_Repository/00_create_repository.sql

Usage:
    psql -d dba_repository -f 00_Deploy_Framework.sql

Criticality: Low (one-time)
================================================================================
*/

\echo 'Deploying DBA framework objects...'

\ir fn_dba_excluded_wait_events.sql
\ir sp_dba_active_sessions.sql
\ir sp_dba_wait_analysis.sql
\ir sp_dba_index_review.sql
\ir sp_dba_backup_review.sql
\ir sp_dba_security_audit.sql
\ir sp_dba_baseline_capture.sql
\ir sp_dba_health_check.sql

\echo 'Framework deployment complete.'
\df dba.*
