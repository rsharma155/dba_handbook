/*
================================================================================
Checkpoint and WAL — Write amplification and tuning signals
================================================================================
Description:
    Checkpoint frequency, WAL generation rate, and bgwriter behavior.

Action:  Increase max_wal_size if checkpoints_req dominates; enable wal_compression if supported.

Criticality: Medium
================================================================================
*/

SELECT * FROM pg_stat_bgwriter;

SELECT name, setting, unit FROM pg_settings
WHERE name IN ('checkpoint_timeout', 'checkpoint_completion_target',
               'max_wal_size', 'min_wal_size', 'wal_compression', 'wal_level');

SELECT pg_current_wal_lsn(),
       pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') AS wal_bytes_generated;
