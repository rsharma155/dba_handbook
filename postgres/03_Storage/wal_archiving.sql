/*
================================================================================
WAL Archiving — Archive mode, status, and retention
================================================================================
Description:
    WAL level, archive settings, archiver statistics, and current WAL position.

Action:  Fix archive failures before they break PITR; verify archive_command in staging.

Criticality: High
================================================================================
*/

SELECT name, setting FROM pg_settings
WHERE name IN ('wal_level', 'archive_mode', 'archive_command', 'archive_timeout',
               'max_wal_size', 'min_wal_size', 'wal_compression');

SELECT * FROM pg_stat_archiver;

SELECT pg_current_wal_lsn() AS current_lsn,
       pg_walfile_name(pg_current_wal_lsn()) AS current_wal_file;
