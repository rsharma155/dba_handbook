/*
================================================================================
DBA Repository — PostgreSQL governance database bootstrap
================================================================================
Description:
    Creates the dba_repository database and dba schema for framework objects,
    baselines, and optional governance tables.

Action:
    Run as superuser: psql -f 00_create_repository.sql

Criticality: Low (one-time setup)
================================================================================
*/

SELECT format(
    'CREATE DATABASE dba_repository WITH OWNER = %I ENCODING = ''UTF8'' LC_COLLATE = %L LC_CTYPE = %L',
    current_user,
    current_setting('lc_collate'),
    current_setting('lc_ctype')
)
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'dba_repository')\gexec

\connect dba_repository

CREATE SCHEMA IF NOT EXISTS dba AUTHORIZATION CURRENT_USER;

COMMENT ON SCHEMA dba IS 'DBA essential scripts — framework and persistence objects';

CREATE TABLE IF NOT EXISTS dba.baseline_snapshot (
    snapshot_id       bigserial PRIMARY KEY,
    snapshot_utc      timestamptz NOT NULL DEFAULT now(),
    server_name       text NOT NULL DEFAULT current_setting('cluster_name', true),
    metric_area       text NOT NULL,
    metric_name       text NOT NULL,
    metric_value      numeric,
    metric_text       text,
    database_name     text
);

CREATE INDEX IF NOT EXISTS ix_baseline_snapshot_utc
    ON dba.baseline_snapshot (snapshot_utc DESC);

CREATE TABLE IF NOT EXISTS dba.assessment_run (
    run_id            bigserial PRIMARY KEY,
    run_utc           timestamptz NOT NULL DEFAULT now(),
    server_name       text NOT NULL,
    profile           text NOT NULL DEFAULT 'Standard',
    health_score      integer,
    notes             text
);

CREATE TABLE IF NOT EXISTS dba.assessment_finding (
    finding_id        bigserial PRIMARY KEY,
    run_id            bigint REFERENCES dba.assessment_run(run_id) ON DELETE CASCADE,
    check_id          integer,
    severity          text NOT NULL,
    area              text NOT NULL,
    finding           text NOT NULL,
    recommendation    text
);

COMMENT ON TABLE dba.baseline_snapshot IS 'Point-in-time performance snapshots for trending';
