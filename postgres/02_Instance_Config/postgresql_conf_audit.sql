/*
================================================================================
PostgreSQL Configuration Audit — Production-critical GUC parameters
================================================================================
Description:
    Flags misconfigured parameters for OLTP/OLAP production workloads.

Action:  Review flagged settings against workload; change via ALTER SYSTEM + reload.

Criticality: Medium
================================================================================
*/

WITH settings AS (
    SELECT name, setting, unit, source, pending_restart
    FROM pg_settings
    WHERE name IN (
        'max_connections', 'shared_buffers', 'effective_cache_size', 'work_mem',
        'maintenance_work_mem', 'wal_buffers', 'checkpoint_timeout', 'max_wal_size',
        'min_wal_size', 'random_page_cost', 'effective_io_concurrency',
        'max_parallel_workers', 'max_parallel_workers_per_gather',
        'autovacuum', 'autovacuum_max_workers', 'autovacuum_naptime',
        'log_min_duration_statement', 'log_checkpoints', 'log_lock_waits',
        'track_io_timing', 'shared_preload_libraries', 'synchronous_commit',
        'full_page_writes', 'wal_compression', 'jit'
    )
)
SELECT name, setting, unit, source, pending_restart,
       CASE name
           WHEN 'max_connections' THEN
               CASE WHEN setting::int > 500 THEN 'REVIEW: Very high max_connections — prefer pooling'
                    WHEN setting::int > 200 THEN 'INFO: Consider PgBouncer' END
           WHEN 'shared_buffers' THEN
               CASE WHEN pg_size_bytes(setting || coalesce(unit, '')) < pg_size_bytes('256MB')
                    THEN 'WARNING: shared_buffers may be too low' END
           WHEN 'autovacuum' THEN
               CASE WHEN setting = 'off' THEN 'CRITICAL: autovacuum disabled' END
           WHEN 'log_min_duration_statement' THEN
               CASE WHEN setting = '-1' THEN 'INFO: No slow query logging enabled' END
           WHEN 'track_io_timing' THEN
               CASE WHEN setting = 'off' THEN 'INFO: Enable for I/O wait analysis' END
           WHEN 'shared_preload_libraries' THEN
               CASE WHEN setting NOT LIKE '%pg_stat_statements%'
                    THEN 'INFO: Add pg_stat_statements to shared_preload_libraries' END
       END AS audit_note
FROM settings
ORDER BY name;
