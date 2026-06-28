/*
================================================================================
Governance Schema — Long query and blocking policy tables
================================================================================
Description:
    Optional schema for capturing policy violations and alerts.
    Run in dba_repository after 00_create_repository.sql.

Criticality: Low (preventive layer)
================================================================================
*/

CREATE TABLE IF NOT EXISTS dba.governance_alert (
    alert_id        bigserial PRIMARY KEY,
    alert_utc       timestamptz NOT NULL DEFAULT now(),
    alert_type      text NOT NULL,
    severity        text NOT NULL DEFAULT 'WARNING',
    database_name   text,
    pid             integer,
    username        text,
    duration_sec    numeric,
    detail          text,
    query_snippet   text
);

CREATE INDEX IF NOT EXISTS ix_governance_alert_utc ON dba.governance_alert (alert_utc DESC);

CREATE TABLE IF NOT EXISTS dba.governance_policy (
    policy_name     text PRIMARY KEY,
    threshold_sec   integer NOT NULL,
    action          text NOT NULL DEFAULT 'LOG',
    is_enabled      boolean NOT NULL DEFAULT true
);

INSERT INTO dba.governance_policy (policy_name, threshold_sec, action)
VALUES
    ('long_running_query', 300, 'LOG'),
    ('idle_in_transaction', 600, 'LOG'),
    ('blocking_chain', 60, 'ALERT')
ON CONFLICT (policy_name) DO NOTHING;
