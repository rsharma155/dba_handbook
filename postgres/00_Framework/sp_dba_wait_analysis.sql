/*
================================================================================
sp_dba_wait_analysis — Wait event analysis with categories
================================================================================
Description:
    Aggregates current wait events from pg_stat_activity with categories and
    recommendations (point-in-time snapshot, not cumulative like SQL Server).

Usage:
    SELECT * FROM dba.sp_wait_analysis(top_n => 20);

Criticality: High
================================================================================
*/

CREATE OR REPLACE FUNCTION dba.sp_wait_analysis(top_n integer DEFAULT 20)
RETURNS TABLE (
    wait_event_type  text,
    wait_event       text,
    session_count    bigint,
    pct_of_waiting   numeric,
    category         text,
    recommendation   text
)
LANGUAGE sql
STABLE
AS $$
    WITH waiting AS (
        SELECT wait_event_type, wait_event, count(*) AS cnt
        FROM pg_stat_activity
        WHERE wait_event IS NOT NULL
          AND pid <> pg_backend_pid()
          AND wait_event NOT IN (SELECT wait_event FROM dba.fn_excluded_wait_events())
        GROUP BY wait_event_type, wait_event
    ),
    totals AS (
        SELECT sum(cnt) AS total FROM waiting
    )
    SELECT
        w.wait_event_type,
        w.wait_event,
        w.cnt,
        round(100.0 * w.cnt / nullif(t.total, 0), 2),
        CASE
            WHEN w.wait_event ILIKE 'Lock%' OR w.wait_event_type = 'Lock' THEN 'Locking'
            WHEN w.wait_event_type = 'IO' THEN 'Storage I/O'
            WHEN w.wait_event ILIKE 'LWLock%' THEN 'Internal latch'
            WHEN w.wait_event = 'WalSync' THEN 'WAL I/O'
            WHEN w.wait_event_type = 'Client' THEN 'Client/Network'
            ELSE 'Other'
        END,
        CASE
            WHEN w.wait_event ILIKE 'Lock%' THEN 'Run blocking_and_locks.sql; shorten transactions'
            WHEN w.wait_event_type = 'IO' THEN 'Check disk latency, checkpoint rate, and missing indexes'
            WHEN w.wait_event = 'WalSync' THEN 'Review wal_buffers, synchronous_commit, storage throughput'
            WHEN w.wait_event_type = 'Client' THEN 'Application not consuming results fast enough'
            ELSE 'Correlate with pg_stat_statements and active query plans'
        END
    FROM waiting w
    CROSS JOIN totals t
    ORDER BY w.cnt DESC
    LIMIT top_n;
$$;
