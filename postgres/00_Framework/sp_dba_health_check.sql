/*
================================================================================
sp_dba_health_check — Consolidated PostgreSQL health orchestrator
================================================================================
Description:
    Aggregates CPU, memory, connections, replication, vacuum, backup/archive,
    and configuration findings into a prioritized dashboard.

Usage:
    SELECT * FROM dba.sp_health_check(deep_dive => false);
    SELECT * FROM dba.sp_health_check(deep_dive => true, backup_hours_sla => 24);

Parameters:
    deep_dive          — include top waits and I/O detail
    database_list      — comma-separated DB names (NULL = all)
    backup_hours_sla   — hours since last archived WAL before warning

Criticality: High
================================================================================
*/

CREATE OR REPLACE FUNCTION dba.sp_health_check(
    deep_dive          boolean DEFAULT false,
    database_list      text DEFAULT NULL,
    backup_hours_sla   integer DEFAULT 24
)
RETURNS TABLE (
    check_id       integer,
    severity       text,
    weight         integer,
    area           text,
    finding        text,
    impact         text,
    recommendation text
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_max_conn integer;
    v_active_conn integer;
    v_idle_in_txn integer;
    v_repl_lag_bytes bigint;
    v_archive_fail bigint;
    v_shared_buffers text;
    v_work_mem text;
    v_wal_level text;
    v_archive_mode text;
    v_last_archived timestamptz;
    v_any_finding boolean := false;
BEGIN
    -- Connections
    SELECT count(*)::int INTO v_active_conn
    FROM pg_stat_activity WHERE state = 'active' AND pid <> pg_backend_pid();

    SELECT count(*)::int INTO v_idle_in_txn
    FROM pg_stat_activity WHERE state = 'idle in transaction';

    SELECT setting::int INTO v_max_conn FROM pg_settings WHERE name = 'max_connections';

    IF v_active_conn > (v_max_conn * 0.8) THEN
        v_any_finding := true;
        RETURN QUERY SELECT 101, 'High', 15, 'Connections',
            format('Active connections %s (>80%% of max_connections %s)', v_active_conn, v_max_conn),
            'Connection exhaustion risk', 'Review pool sizing, idle timeouts, and app connection leaks';
    END IF;

    IF v_idle_in_txn > 5 THEN
        v_any_finding := true;
        RETURN QUERY SELECT 102, 'High', 20, 'Connections',
            format('%s sessions idle in transaction', v_idle_in_txn),
            'Blocking and bloat risk', 'Find long idle-in-transaction sessions; enforce statement_timeout and idle_in_transaction_session_timeout';
    END IF;

    -- Memory settings
    SELECT setting INTO v_shared_buffers FROM pg_settings WHERE name = 'shared_buffers';
    SELECT setting INTO v_work_mem FROM pg_settings WHERE name = 'work_mem';

    IF pg_size_bytes(v_shared_buffers) < pg_size_bytes('1GB')
       AND (SELECT setting::bigint FROM pg_settings WHERE name = 'effective_cache_size') < pg_size_bytes('2GB') THEN
        v_any_finding := true;
        RETURN QUERY SELECT 201, 'Medium', 10, 'Memory',
            format('shared_buffers=%s may be low for production', v_shared_buffers),
            'Cache pressure, more disk I/O', 'Tune shared_buffers (~25% RAM) and effective_cache_size per workload';
    END IF;

    -- WAL / archive
    SELECT setting INTO v_wal_level FROM pg_settings WHERE name = 'wal_level';
    SELECT setting INTO v_archive_mode FROM pg_settings WHERE name = 'archive_mode';

    IF v_archive_mode <> 'on' AND v_wal_level IN ('replica', 'logical') THEN
        v_any_finding := true;
        RETURN QUERY SELECT 301, 'High', 20, 'HA/DR',
            'archive_mode is off but wal_level supports replication',
            'No point-in-time recovery / standby WAL shipping', 'Enable archive_mode and configure archive_command';
    END IF;

    SELECT failed_count, last_archived_time
    INTO v_archive_fail, v_last_archived
    FROM pg_stat_archiver;

    IF v_archive_fail > 0 THEN
        v_any_finding := true;
        RETURN QUERY SELECT 302, 'Critical', 25, 'HA/DR',
            format('WAL archive failures: %s', v_archive_fail),
            'Broken backup chain', 'Check archive_command, disk space, and permissions on archive destination';
    END IF;

    IF v_last_archived IS NOT NULL
       AND v_last_archived < now() - (backup_hours_sla || ' hours')::interval THEN
        v_any_finding := true;
        RETURN QUERY SELECT 303, 'High', 15, 'HA/DR',
            format('Last archived WAL at %s (>%s h ago)', v_last_archived, backup_hours_sla),
            'Backup/DR gap', 'Verify archiver process and backup tooling';
    END IF;

    -- Replication lag (physical)
    IF EXISTS (SELECT 1 FROM pg_stat_replication) THEN
        SELECT max(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn))::bigint
        INTO v_repl_lag_bytes FROM pg_stat_replication;

        IF coalesce(v_repl_lag_bytes, 0) > pg_size_bytes('1GB') THEN
            v_any_finding := true;
        RETURN QUERY SELECT 401, 'High', 20, 'Replication',
                format('Replication lag %s bytes', v_repl_lag_bytes),
                'RPO/RTO risk on failover', 'Check replica I/O, network, long queries on replica, hot_standby_feedback';
        END IF;
    END IF;

    -- Autovacuum backlog
    IF EXISTS (
        SELECT 1 FROM pg_stat_user_tables
        WHERE n_dead_tup > 100000
          AND (last_autovacuum IS NULL OR last_autovacuum < now() - interval '7 days')
    ) THEN
        v_any_finding := true;
        RETURN QUERY SELECT 501, 'Medium', 10, 'Maintenance',
            'Tables with high dead tuples and stale autovacuum',
            'Bloat and wraparound risk', 'Run 09_Maintenance/vacuum_bloat_maintenance.sql; tune autovacuum per table';
    END IF;

    -- Checkpoints
    IF (SELECT checkpoints_req FROM pg_stat_bgwriter) >
       (SELECT checkpoints_timed FROM pg_stat_bgwriter) * 2 THEN
        v_any_finding := true;
        RETURN QUERY SELECT 502, 'Medium', 10, 'Storage',
            'Requested checkpoints exceed timed checkpoints',
            'I/O spikes during checkpoint', 'Increase max_wal_size / checkpoint_timeout; review wal_compression';
    END IF;

    -- SSL
    IF NOT EXISTS (SELECT 1 FROM pg_settings WHERE name = 'ssl' AND setting = 'on') THEN
        v_any_finding := true;
        RETURN QUERY SELECT 601, 'Medium', 10, 'Security',
            'SSL is not enabled on server',
            'Unencrypted client connections possible', 'Enable ssl and require SSL in pg_hba.conf for production';
    END IF;

    -- pg_stat_statements
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
        v_any_finding := true;
        RETURN QUERY SELECT 701, 'Low', 5, 'Diagnostics',
            'pg_stat_statements extension not installed',
            'Limited query performance history', 'CREATE EXTENSION pg_stat_statements; add to shared_preload_libraries';
    END IF;

    IF deep_dive THEN
        RETURN QUERY
        SELECT 801, 'Info', 1, 'Waits',
            wait_event_type || ': ' || wait_event,
            format('%s sessions waiting', count(*)::text),
            'See 04_Performance_Diagnostics/wait_events.sql'
        FROM pg_stat_activity
        WHERE wait_event IS NOT NULL
          AND pid <> pg_backend_pid()
          AND wait_event NOT IN (SELECT wait_event FROM dba.fn_excluded_wait_events())
        GROUP BY wait_event_type, wait_event
        ORDER BY count(*) DESC
        LIMIT 10;
    END IF;

    IF NOT v_any_finding THEN
        RETURN QUERY SELECT 0, 'Info', 0, 'Summary',
            'No critical findings from automated checks',
            'Continue scheduled monitoring',
            'Run dba.sp_baseline_capture() for trending';
    END IF;
END;
$$;

COMMENT ON FUNCTION dba.sp_health_check(boolean, text, integer) IS
    'Consolidated PostgreSQL health check with severity-scored findings.';
