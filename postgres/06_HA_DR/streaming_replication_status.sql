/*
================================================================================
Streaming Replication Status — Physical replicas health
================================================================================
Description:
    Replica connection state, sync mode, lag bytes, and replay pause.

Action:  Lag > SLA → check replica I/O, network, long queries on replica, vacuum on primary.

Criticality: High
================================================================================
*/

SELECT application_name, client_addr, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS send_lag_bytes,
       pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) AS flush_lag_bytes,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes,
       write_lag, flush_lag, replay_lag,
       backend_start
FROM pg_stat_replication;

SELECT pg_is_in_recovery() AS is_replica,
       CASE WHEN pg_is_in_recovery() THEN pg_last_wal_receive_lsn() END AS receive_lsn,
       CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() END AS replay_lsn;
