/*
================================================================================
Backup Verification — Archive chain and PITR readiness
================================================================================
Description:
    Validates WAL archiving health and settings required for point-in-time recovery.

Action:  Test restore monthly; integrate with pgBackRest/Barman/WAL-G where used.

Criticality: High
================================================================================
*/

SELECT * FROM dba.sp_backup_review(24)
WHERE EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'dba');

SELECT name, setting,
       CASE name
           WHEN 'archive_mode' THEN CASE WHEN setting <> 'on' THEN 'FAIL' ELSE 'PASS' END
           WHEN 'archive_command' THEN CASE WHEN setting = '' OR setting IS NULL THEN 'FAIL' ELSE 'PASS' END
           ELSE 'INFO'
       END AS check_result
FROM pg_settings
WHERE name IN ('archive_mode', 'archive_command', 'restore_command', 'wal_level')
  AND NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'dba');

SELECT failed_count, last_failed_wal, last_failed_time,
       last_archived_wal, last_archived_time,
       CASE WHEN failed_count > 0 THEN 'CRITICAL: Archive failures detected' ELSE 'OK' END AS status
FROM pg_stat_archiver;
