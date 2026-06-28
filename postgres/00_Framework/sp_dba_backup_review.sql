/*
================================================================================
sp_dba_backup_review — WAL archiving and backup readiness
================================================================================
Description:
    Reviews archive mode, archiver stats, WAL retention settings, and base
    backup indicators. Complements external tools (pgBackRest, Barman, WAL-G).

Usage:
    SELECT * FROM dba.sp_backup_review(backup_hours_sla => 24);

Criticality: High
================================================================================
*/

CREATE OR REPLACE FUNCTION dba.sp_backup_review(backup_hours_sla integer DEFAULT 24)
RETURNS TABLE (
    check_area       text,
    status           text,
    detail           text,
    recommendation   text
)
LANGUAGE sql
STABLE
AS $$
    SELECT 'Archive Mode', setting,
        CASE WHEN setting = 'on' THEN 'OK' ELSE 'WAL archiving disabled' END,
        CASE WHEN setting <> 'on' THEN 'Set archive_mode=on and configure archive_command' END
    FROM pg_settings WHERE name = 'archive_mode'

    UNION ALL

    SELECT 'WAL Level', setting, 'Current wal_level',
        CASE WHEN setting = 'minimal' THEN 'Use replica or logical for HA/DR' END
    FROM pg_settings WHERE name = 'wal_level'

    UNION ALL

    SELECT 'Archiver',
        CASE WHEN failed_count > 0 THEN 'CRITICAL' WHEN last_failed_time IS NOT NULL THEN 'WARNING' ELSE 'OK' END,
        format('last_archived=%s failed=%s', last_archived_wal, failed_count),
        CASE WHEN failed_count > 0 THEN 'Fix archive_command failures immediately' END
    FROM pg_stat_archiver

    UNION ALL

    SELECT 'Last Archive Age',
        CASE WHEN last_archived_time < now() - (backup_hours_sla || ' hours')::interval
             THEN 'WARNING' ELSE 'OK' END,
        coalesce(last_archived_time::text, 'never'),
        'Ensure continuous WAL archiving for PITR'
    FROM pg_stat_archiver

    UNION ALL

    SELECT 'max_wal_size', setting, 'Checkpoint / WAL sizing',
        'Increase if checkpoints_req is high (see checkpoint_and_wal.sql)'
    FROM pg_settings WHERE name = 'max_wal_size';
$$;
