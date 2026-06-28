/*
================================================================================
sp_dba_baseline_capture — Persist performance snapshot
================================================================================
Description:
    Captures connection counts, buffer/cache stats, checkpoint counters,
    and top wait events into dba.baseline_snapshot for trending.

Usage:
    SELECT dba.sp_baseline_capture();

Prerequisite: dba.baseline_snapshot table (00_Repository/00_create_repository.sql)

Criticality: Low
================================================================================
*/

CREATE OR REPLACE FUNCTION dba.sp_baseline_capture()
RETURNS bigint
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_id bigint;
BEGIN
    INSERT INTO dba.baseline_snapshot (metric_area, metric_name, metric_value)
    SELECT 'Connections', state, count(*)::numeric
    FROM pg_stat_activity
    WHERE backend_type = 'client backend'
    GROUP BY state;

    INSERT INTO dba.baseline_snapshot (metric_area, metric_name, metric_value)
    SELECT 'Buffer', 'blks_hit', blks_hit::numeric FROM pg_stat_database WHERE datname = current_database()
    UNION ALL
    SELECT 'Buffer', 'blks_read', blks_read::numeric FROM pg_stat_database WHERE datname = current_database();

    INSERT INTO dba.baseline_snapshot (metric_area, metric_name, metric_value)
    SELECT 'BGWriter', 'checkpoints_timed', checkpoints_timed::numeric FROM pg_stat_bgwriter
    UNION ALL
    SELECT 'BGWriter', 'checkpoints_req', checkpoints_req::numeric FROM pg_stat_bgwriter
    UNION ALL
    SELECT 'BGWriter', 'buffers_checkpoint', buffers_checkpoint::numeric FROM pg_stat_bgwriter;

    INSERT INTO dba.baseline_snapshot (metric_area, metric_name, metric_value, metric_text)
    SELECT 'Waits', wait_event, count(*)::numeric, wait_event_type
    FROM pg_stat_activity
    WHERE wait_event IS NOT NULL AND pid <> pg_backend_pid()
    GROUP BY wait_event_type, wait_event;

    SELECT max(snapshot_id) INTO v_id FROM dba.baseline_snapshot;
    RETURN v_id;
END;
$$;
