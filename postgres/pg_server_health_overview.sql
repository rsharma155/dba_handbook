/*
================================================================================
pg_server_health_overview — One-Script Daily Snapshot
================================================================================
Description:
    Simple, standalone PostgreSQL script that returns overall server health in
    one pass. No framework install required. Safe for production (read-only).
    SQL Server counterpart: sql_server/sql_server_server_health_overview.sql

Reports:
    1.  Instance identity & uptime
    2.  Connections / backend pressure
    3.  Memory & cache settings
    4.  Key GUCs (configuration)
    5.  Database inventory
    6.  Database sizes
    7.  Tablespace / disk capacity
    8.  Database I/O & checkpoints
    9.  WAL / archive (backup) currency
    10. Blocking / locks
    11. Current wait events
    12. Long-running / idle-in-transaction sessions
    13. Autovacuum health
    14. Streaming replication (when configured)
    15. Quick findings summary

Notes:
    - PostgreSQL waits are point-in-time (pg_stat_activity), not cumulative.
    - Host CPU is not in catalog views; use OS tools alongside section 2.
    - Archive SLA for the summary is 24 hours (edit params CTE in section 15).

Prerequisites:
    PostgreSQL 12+. Role needs pg_monitor (or superuser) for fuller stats.
    Optional: pg_stat_statements for query-level history.

Criticality: High — daily / on-call triage
Author:      Ravi Sharma
================================================================================
*/

-------------------------------------------------------------------------------
-- 1. Instance identity & uptime
-------------------------------------------------------------------------------
SELECT
    inet_server_addr() AS server_addr,
    inet_server_port() AS server_port,
    current_setting('server_version') AS server_version,
    version() AS version_string,
    current_setting('server_encoding') AS server_encoding,
    current_setting('lc_collate') AS collation,
    pg_postmaster_start_time() AS postmaster_start_time,
    date_trunc('second', now() - pg_postmaster_start_time()) AS uptime,
    EXTRACT(EPOCH FROM (now() - pg_postmaster_start_time()))::bigint / 86400 AS uptime_days,
    current_setting('data_directory') AS data_directory,
    pg_is_in_recovery() AS is_in_recovery,
    current_database() AS connected_database,
    current_user AS connected_user;

-------------------------------------------------------------------------------
-- 2. Connections / backend pressure
-------------------------------------------------------------------------------
SELECT
    count(*) FILTER (WHERE backend_type = 'client backend') AS client_backends,
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle,
    count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction,
    count(*) FILTER (WHERE wait_event_type = 'Lock') AS waiting_on_lock,
    current_setting('max_connections')::int AS max_connections,
    round(
        100.0 * count(*) FILTER (WHERE backend_type = 'client backend')
        / nullif(current_setting('max_connections')::numeric, 0),
        1
    ) AS pct_of_max,
    CASE
        WHEN count(*) FILTER (WHERE state = 'idle in transaction') > 5
            THEN 'WARNING: Idle-in-transaction sessions'
        WHEN count(*) FILTER (WHERE backend_type = 'client backend')
             > (current_setting('max_connections')::int * 0.8)
            THEN 'WARNING: Connections > 80% of max_connections'
        ELSE 'OK'
    END AS connection_status
FROM pg_stat_activity;

-------------------------------------------------------------------------------
-- 3. Memory & cache settings
-------------------------------------------------------------------------------
SELECT
    name,
    setting,
    unit,
    source,
    CASE name
        WHEN 'shared_buffers' THEN
            CASE
                WHEN pg_size_bytes(setting || coalesce(unit, '')) < pg_size_bytes('256MB')
                    THEN 'WARNING: shared_buffers may be low'
                ELSE 'OK / review (~25% RAM typical)'
            END
        WHEN 'effective_cache_size' THEN
            CASE
                WHEN pg_size_bytes(setting || coalesce(unit, '')) < pg_size_bytes('1GB')
                    THEN 'WARNING: effective_cache_size may be low'
                ELSE 'OK'
            END
        WHEN 'work_mem' THEN
            CASE
                WHEN pg_size_bytes(setting || coalesce(unit, '')) > pg_size_bytes('256MB')
                    THEN 'REVIEW: High work_mem * connections can OOM'
                ELSE 'OK'
            END
        WHEN 'maintenance_work_mem' THEN 'OK / review for vacuum/index builds'
        WHEN 'wal_buffers' THEN 'OK'
        ELSE 'Review'
    END AS note
FROM pg_settings
WHERE name IN (
    'shared_buffers',
    'effective_cache_size',
    'work_mem',
    'maintenance_work_mem',
    'wal_buffers',
    'temp_buffers',
    'huge_pages'
)
ORDER BY name;

SELECT
    datname,
    blks_hit,
    blks_read,
    round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS cache_hit_pct,
    CASE
        WHEN blks_hit + blks_read = 0 THEN 'N/A'
        WHEN (100.0 * blks_hit / nullif(blks_hit + blks_read, 0)) < 90
            THEN 'WARNING: Cache hit ratio < 90%'
        ELSE 'OK'
    END AS cache_status
FROM pg_stat_database
WHERE datname NOT IN ('template0', 'template1')
ORDER BY blks_read DESC;

-------------------------------------------------------------------------------
-- 4. Key GUCs (configuration)
-------------------------------------------------------------------------------
SELECT
    name,
    setting,
    unit,
    source,
    pending_restart,
    CASE name
        WHEN 'max_connections' THEN
            CASE
                WHEN setting::int > 500 THEN 'REVIEW: Prefer connection pooling'
                WHEN setting::int > 200 THEN 'INFO: Consider PgBouncer'
                ELSE 'OK'
            END
        WHEN 'autovacuum' THEN
            CASE WHEN setting = 'off' THEN 'CRITICAL: autovacuum disabled' ELSE 'OK' END
        WHEN 'archive_mode' THEN
            CASE WHEN setting = 'off' THEN 'WARNING: archive_mode off (no WAL archive PITR)' ELSE 'OK' END
        WHEN 'wal_level' THEN
            CASE WHEN setting = 'minimal' THEN 'WARNING: minimal wal_level limits HA/PITR' ELSE 'OK' END
        WHEN 'synchronous_commit' THEN 'INFO'
        WHEN 'full_page_writes' THEN
            CASE WHEN setting = 'off' THEN 'WARNING: full_page_writes off (crash-safety risk)' ELSE 'OK' END
        WHEN 'log_min_duration_statement' THEN
            CASE WHEN setting = '-1' THEN 'INFO: Slow-query logging disabled' ELSE 'OK' END
        WHEN 'track_io_timing' THEN
            CASE WHEN setting = 'off' THEN 'INFO: Enable for I/O analysis' ELSE 'OK' END
        WHEN 'shared_preload_libraries' THEN
            CASE
                WHEN setting NOT LIKE '%pg_stat_statements%'
                    THEN 'INFO: Add pg_stat_statements'
                ELSE 'OK'
            END
        WHEN 'idle_in_transaction_session_timeout' THEN
            CASE WHEN setting = '0' THEN 'REVIEW: Consider a non-zero idle-in-txn timeout' ELSE 'OK' END
        WHEN 'statement_timeout' THEN
            CASE WHEN setting = '0' THEN 'INFO: No global statement_timeout' ELSE 'OK' END
        ELSE 'Review'
    END AS note
FROM pg_settings
WHERE name IN (
    'max_connections',
    'shared_buffers',
    'effective_cache_size',
    'work_mem',
    'maintenance_work_mem',
    'max_wal_size',
    'min_wal_size',
    'checkpoint_timeout',
    'wal_level',
    'archive_mode',
    'archive_command',
    'synchronous_commit',
    'full_page_writes',
    'autovacuum',
    'autovacuum_max_workers',
    'max_parallel_workers',
    'max_parallel_workers_per_gather',
    'log_min_duration_statement',
    'log_lock_waits',
    'track_io_timing',
    'shared_preload_libraries',
    'idle_in_transaction_session_timeout',
    'statement_timeout'
)
ORDER BY name;

-------------------------------------------------------------------------------
-- 5. Database inventory
-------------------------------------------------------------------------------
SELECT
    d.datname AS database_name,
    pg_catalog.pg_get_userbyid(d.datdba) AS owner,
    pg_encoding_to_char(d.encoding) AS encoding,
    d.datcollate AS collation,
    d.datctype AS ctype,
    d.datconnlimit AS connection_limit,
    d.datallowconn AS allow_connections,
    CASE
        WHEN NOT d.datallowconn THEN 'INFO: Connections not allowed'
        WHEN d.datconnlimit = 0 THEN 'OK'
        ELSE 'OK (limited)'
    END AS health_flag
FROM pg_database AS d
ORDER BY d.datname;

-------------------------------------------------------------------------------
-- 6. Database sizes
-------------------------------------------------------------------------------
SELECT
    datname AS database_name,
    pg_size_pretty(pg_database_size(datname)) AS size_pretty,
    pg_database_size(datname) AS size_bytes
FROM pg_database
WHERE datallowconn
ORDER BY pg_database_size(datname) DESC;

-------------------------------------------------------------------------------
-- 7. Tablespace / disk capacity
-------------------------------------------------------------------------------
SELECT
    spcname AS tablespace_name,
    pg_tablespace_location(oid) AS location,
    pg_size_pretty(pg_tablespace_size(oid)) AS size_pretty,
    pg_tablespace_size(oid) AS size_bytes
FROM pg_tablespace
ORDER BY pg_tablespace_size(oid) DESC;

-------------------------------------------------------------------------------
-- 8. Database I/O & checkpoints
-------------------------------------------------------------------------------
SELECT
    datname AS database_name,
    pg_size_pretty(pg_database_size(datname)) AS db_size,
    blks_read,
    blks_hit,
    tup_returned,
    tup_fetched,
    tup_inserted,
    tup_updated,
    tup_deleted,
    xact_commit,
    xact_rollback,
    conflicts,
    deadlocks,
    temp_files,
    pg_size_pretty(temp_bytes) AS temp_bytes
FROM pg_stat_database
WHERE datname NOT IN ('template0', 'template1')
ORDER BY blks_read DESC;

SELECT
    checkpoints_timed,
    checkpoints_req,
    checkpoint_write_time,
    checkpoint_sync_time,
    buffers_checkpoint,
    buffers_clean,
    maxwritten_clean,
    buffers_backend,
    buffers_backend_fsync,
    buffers_alloc,
    CASE
        WHEN checkpoints_req > checkpoints_timed * 2
            THEN 'WARNING: Frequent requested checkpoints — tune max_wal_size / checkpoint_timeout'
        ELSE 'OK'
    END AS checkpoint_status
FROM pg_stat_bgwriter;

-------------------------------------------------------------------------------
-- 9. WAL / archive (backup) currency
-------------------------------------------------------------------------------
SELECT
    name,
    setting,
    CASE name
        WHEN 'archive_mode' THEN
            CASE WHEN setting <> 'on' THEN 'FAIL / REVIEW' ELSE 'PASS' END
        WHEN 'archive_command' THEN
            CASE WHEN coalesce(setting, '') = '' THEN 'FAIL' ELSE 'PASS' END
        WHEN 'wal_level' THEN
            CASE WHEN setting = 'minimal' THEN 'FAIL / REVIEW' ELSE 'PASS' END
        ELSE 'INFO'
    END AS check_result
FROM pg_settings
WHERE name IN ('archive_mode', 'archive_command', 'restore_command', 'wal_level');

SELECT
    archived_count,
    failed_count,
    last_archived_wal,
    last_archived_time,
    last_failed_wal,
    last_failed_time,
    CASE
        WHEN failed_count > 0 THEN 'CRITICAL: Archive failures detected'
        WHEN last_archived_time IS NULL THEN 'WARNING: No WAL archived yet'
        WHEN last_archived_time < now() - interval '24 hours'
            THEN 'WARNING: Last archived WAL > 24 hours ago'
        ELSE 'OK'
    END AS archive_status
FROM pg_stat_archiver;

SELECT
    pg_is_in_recovery() AS is_in_recovery,
    CASE
        WHEN pg_is_in_recovery() THEN pg_last_wal_receive_lsn()
        ELSE pg_current_wal_lsn()
    END AS current_wal_lsn,
    CASE
        WHEN pg_is_in_recovery() THEN NULL
        ELSE pg_walfile_name(pg_current_wal_lsn())
    END AS current_wal_file;

-------------------------------------------------------------------------------
-- 10. Blocking / locks
-------------------------------------------------------------------------------
SELECT
    blocked.pid AS blocked_pid,
    blocked.usename AS blocked_user,
    blocked.datname AS database_name,
    blocked.application_name AS blocked_app,
    blocking.pid AS blocking_pid,
    blocking.usename AS blocking_user,
    blocking.application_name AS blocking_app,
    round(extract(epoch FROM (now() - blocked.query_start))::numeric, 1) AS blocked_sec,
    blocked.wait_event_type,
    blocked.wait_event,
    left(blocked.query, 100) AS blocked_query,
    left(blocking.query, 100) AS blocking_query
FROM pg_stat_activity AS blocked
JOIN pg_stat_activity AS blocking
    ON blocking.pid = ANY (pg_blocking_pids(blocked.pid))
WHERE blocked.pid <> pg_backend_pid()
ORDER BY blocked_sec DESC;

-------------------------------------------------------------------------------
-- 11. Current wait events (point-in-time)
-------------------------------------------------------------------------------
SELECT
    now() AS snapshot_time,
    'Waits are point-in-time, not cumulative since startup' AS metric_context;

SELECT
    wait_event_type,
    wait_event,
    count(*) AS sessions,
    round(100.0 * count(*) / nullif(sum(count(*)) OVER (), 0), 2) AS pct,
    CASE
        WHEN wait_event_type = 'Lock' THEN 'Blocking — see section 10'
        WHEN wait_event_type = 'IO' THEN 'Storage I/O — see section 8'
        WHEN wait_event IN ('WalSync', 'WalWrite') THEN 'WAL I/O — check storage / synchronous_commit'
        WHEN wait_event_type = 'LWLock' THEN 'Internal contention'
        WHEN wait_event_type = 'Client' THEN 'Often benign (client idle/read)'
        ELSE 'Review'
    END AS category
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
  AND pid <> pg_backend_pid()
  AND coalesce(wait_event, '') NOT IN ('ClientRead', 'ClientWrite', 'Timeout', 'PgSleep')
GROUP BY wait_event_type, wait_event
ORDER BY sessions DESC
LIMIT 20;

-------------------------------------------------------------------------------
-- 12. Long-running / idle-in-transaction sessions
-------------------------------------------------------------------------------
SELECT
    pid,
    usename,
    datname,
    application_name,
    client_addr,
    state,
    wait_event_type,
    wait_event,
    round(extract(epoch FROM (now() - xact_start))::numeric, 1) AS xact_age_sec,
    round(extract(epoch FROM (now() - query_start))::numeric, 1) AS query_age_sec,
    left(query, 120) AS query_snippet
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
  AND backend_type = 'client backend'
  AND
  (
      state = 'idle in transaction'
      OR (state = 'active' AND query_start < now() - interval '30 seconds')
      OR (xact_start IS NOT NULL AND xact_start < now() - interval '5 minutes')
  )
ORDER BY coalesce(xact_start, query_start);

-------------------------------------------------------------------------------
-- 13. Autovacuum health
-------------------------------------------------------------------------------
SELECT
    name,
    setting,
    unit
FROM pg_settings
WHERE name IN (
    'autovacuum',
    'autovacuum_max_workers',
    'autovacuum_naptime',
    'autovacuum_vacuum_scale_factor',
    'autovacuum_analyze_scale_factor',
    'autovacuum_vacuum_cost_limit'
)
ORDER BY name;

SELECT
    count(*) AS autovacuum_workers_active
FROM pg_stat_activity
WHERE query LIKE 'autovacuum:%';

SELECT
    schemaname,
    relname,
    n_live_tup,
    n_dead_tup,
    round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_tup_pct,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    CASE
        WHEN n_dead_tup > 100000
         AND (100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0)) > 20
            THEN 'WARNING: High dead tuples'
        ELSE 'OK'
    END AS vacuum_status
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC
LIMIT 25;

-------------------------------------------------------------------------------
-- 14. Streaming replication (when configured)
-------------------------------------------------------------------------------
SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    CASE
        WHEN NOT pg_is_in_recovery()
            THEN pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)
    END AS send_lag_bytes,
    CASE
        WHEN NOT pg_is_in_recovery()
            THEN pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)
    END AS flush_lag_bytes,
    CASE
        WHEN NOT pg_is_in_recovery()
            THEN pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)
    END AS replay_lag_bytes,
    write_lag,
    flush_lag,
    replay_lag,
    backend_start
FROM pg_stat_replication
ORDER BY application_name;

SELECT
    pg_is_in_recovery() AS is_replica,
    CASE WHEN pg_is_in_recovery() THEN pg_last_wal_receive_lsn() END AS receive_lsn,
    CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() END AS replay_lsn,
    CASE
        WHEN pg_is_in_recovery()
            THEN pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())
    END AS replay_lag_bytes_on_replica;

-------------------------------------------------------------------------------
-- 15. Quick findings summary
-------------------------------------------------------------------------------
WITH params AS (
    SELECT 24 AS backup_hours_sla
),
issues AS (
    SELECT
        'Connections'::text AS area,
        CASE
            WHEN (
                    SELECT count(*) FILTER (WHERE state = 'idle in transaction')
                    FROM pg_stat_activity
                 ) > 5
              OR (
                    SELECT count(*) FILTER (WHERE backend_type = 'client backend')
                    FROM pg_stat_activity
                 ) > (current_setting('max_connections')::int * 0.8)
                THEN 'WARNING'
            ELSE 'OK'
        END AS status,
        'Connection pressure / idle-in-transaction'::text AS check_name
    UNION ALL
    SELECT
        'Config',
        CASE
            WHEN current_setting('autovacuum') = 'off' THEN 'CRITICAL'
            ELSE 'OK'
        END,
        'Autovacuum enabled'
    UNION ALL
    SELECT
        'Archive',
        CASE
            WHEN (SELECT failed_count FROM pg_stat_archiver) > 0 THEN 'CRITICAL'
            WHEN (SELECT last_archived_time FROM pg_stat_archiver) IS NULL
                 AND current_setting('archive_mode') = 'on'
                THEN 'WARNING'
            WHEN (SELECT last_archived_time FROM pg_stat_archiver)
                 < now() - ((SELECT backup_hours_sla FROM params) || ' hours')::interval
                THEN 'WARNING'
            WHEN current_setting('archive_mode') = 'off' THEN 'WARNING'
            ELSE 'OK'
        END,
        'WAL archiving health'
    UNION ALL
    SELECT
        'Blocking',
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM pg_stat_activity AS a
                WHERE cardinality(pg_blocking_pids(a.pid)) > 0
            ) THEN 'WARNING'
            ELSE 'OK'
        END,
        'Active blocking chains'
    UNION ALL
    SELECT
        'Cache',
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM pg_stat_database
                WHERE datname NOT IN ('template0', 'template1')
                  AND blks_hit + blks_read > 1000
                  AND (100.0 * blks_hit / nullif(blks_hit + blks_read, 0)) < 90
            ) THEN 'WARNING'
            ELSE 'OK'
        END,
        'Database cache hit ratio'
    UNION ALL
    SELECT
        'Replication',
        CASE
            WHEN NOT pg_is_in_recovery()
             AND EXISTS (
                SELECT 1
                FROM pg_stat_replication
                WHERE pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) > 104857600  -- 100 MB
            ) THEN 'WARNING'
            ELSE 'OK'
        END,
        'Streaming replica lag (>100MB)'
)
SELECT
    area,
    status,
    check_name,
    CASE status
        WHEN 'CRITICAL' THEN 1
        WHEN 'WARNING' THEN 2
        ELSE 3
    END AS sort_order
FROM issues
ORDER BY sort_order, area;

-- Completion notice
DO $$
BEGIN
    RAISE NOTICE '=== SERVER HEALTH OVERVIEW COMPLETE ===';
    RAISE NOTICE 'For scored findings: SELECT * FROM dba.sp_health_check(deep_dive => false);';
    RAISE NOTICE 'For deeper drills, use folders 01_Server_OS through 09_Maintenance.';
END $$;
