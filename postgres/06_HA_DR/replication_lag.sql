/*
================================================================================
Replication Lag — Byte and time lag with thresholds
================================================================================
Description:
    Quantifies replication lag for alerting and failover decisions.

Action:  Set monitoring alerts on replay_lag_bytes; investigate before automatic failover.

Criticality: High
================================================================================
*/

SELECT pid, application_name, state,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS replay_lag,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes,
       replay_lag AS replay_lag_time,
       CASE
           WHEN pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) > pg_size_bytes('1GB')
               THEN 'CRITICAL'
           WHEN pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) > pg_size_bytes('100MB')
               THEN 'WARNING'
           ELSE 'OK'
       END AS lag_status
FROM pg_stat_replication;
