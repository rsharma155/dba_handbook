/*
================================================================================
PostgreSQL — DBA Essential Scripts Permissions
================================================================================
Run once as superuser (customize password first):

    psql -U postgres -f postgres/permission.sql

Pair with repository root permission.sql (SQL Server section).
Author:        Ravi Sharma
================================================================================
*/

\set ON_ERROR_STOP on

-- >>> CUSTOMIZE <<<
\set dba_user dba_monitor
\set dba_password 'CHANGE_ME_STRONG_PASSWORD'

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dba_monitor') THEN
        EXECUTE format('CREATE ROLE dba_monitor LOGIN PASSWORD %L', 'CHANGE_ME_STRONG_PASSWORD');
    END IF;
END $$;

GRANT pg_monitor TO dba_monitor;
GRANT pg_read_all_stats TO dba_monitor;
GRANT pg_read_all_settings TO dba_monitor;

-- dba_repository — run 00_Repository/00_create_repository.sql first
\connect dba_repository

GRANT CONNECT ON DATABASE dba_repository TO dba_monitor;
GRANT USAGE ON SCHEMA dba TO dba_monitor;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA dba TO dba_monitor;
GRANT SELECT ON ALL TABLES IN SCHEMA dba TO dba_monitor;
ALTER DEFAULT PRIVILEGES IN SCHEMA dba GRANT SELECT ON TABLES TO dba_monitor;
ALTER DEFAULT PRIVILEGES IN SCHEMA dba GRANT EXECUTE ON FUNCTIONS TO dba_monitor;

-- Application databases — uncomment and repeat per database:
-- \connect your_app_db
-- GRANT CONNECT ON DATABASE your_app_db TO dba_monitor;
-- GRANT USAGE ON SCHEMA public TO dba_monitor;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO dba_monitor;
-- GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO dba_monitor;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
        GRANT SELECT ON pg_stat_statements TO dba_monitor;
    END IF;
END $$;

\echo ''
\echo 'PostgreSQL monitor tier grants applied for role: dba_monitor'
\echo 'Optional: GRANT pg_maintain (PG 18+) for maintenance script execution.'
\echo 'Framework deploy: superuser — 00_Repository, 00_Framework, preventive_measures.'
