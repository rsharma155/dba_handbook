/*
================================================================================
sp_dba_active_sessions — Real-time session monitor
================================================================================
Description:
    Shows active, waiting, and blocking sessions with query text and wait info.
    Modes: DETAIL (default), SUMMARY, BLOCKING.

Usage:
    SELECT * FROM dba.sp_active_sessions();
    SELECT * FROM dba.sp_active_sessions(output_mode => 'BLOCKING');
    SELECT * FROM dba.sp_active_sessions(filter_database => 'salesdb', min_duration_sec => 30);

Criticality: High
================================================================================
*/

CREATE OR REPLACE FUNCTION dba.sp_active_sessions(
    filter_database    text DEFAULT NULL,
    filter_wait_event  text DEFAULT NULL,
    min_duration_sec   integer DEFAULT 0,
    output_mode        text DEFAULT 'DETAIL'
)
RETURNS TABLE (
    pid              integer,
    usename          text,
    datname          text,
    application_name text,
    client_addr      inet,
    state            text,
    wait_event_type  text,
    wait_event       text,
    duration_sec     numeric,
    blocking_pid     integer,
    query_snippet    text
)
LANGUAGE sql
STABLE
AS $$
    WITH sessions AS (
        SELECT
            a.pid,
            a.usename::text,
            a.datname::text,
            a.application_name::text,
            a.client_addr,
            a.state::text,
            a.wait_event_type::text,
            a.wait_event::text,
            round(extract(epoch FROM (now() - a.query_start))::numeric, 1) AS duration_sec,
            a.query::text AS query_snippet,
            pg_blocking_pids(a.pid) AS blockers
        FROM pg_stat_activity a
        WHERE a.pid <> pg_backend_pid()
          AND a.backend_type = 'client backend'
          AND (filter_database IS NULL OR a.datname = filter_database)
          AND (filter_wait_event IS NULL OR a.wait_event ILIKE filter_wait_event)
          AND extract(epoch FROM (now() - coalesce(a.query_start, a.backend_start))) >= min_duration_sec
    )
    SELECT
        s.pid,
        s.usename,
        s.datname,
        s.application_name,
        s.client_addr,
        s.state,
        s.wait_event_type,
        s.wait_event,
        s.duration_sec,
        CASE WHEN cardinality(s.blockers) > 0 THEN s.blockers[1] END AS blocking_pid,
        left(regexp_replace(s.query_snippet, '\s+', ' ', 'g'), 200) AS query_snippet
    FROM sessions s
    WHERE output_mode IN ('DETAIL', 'SUMMARY')
       OR (output_mode = 'BLOCKING' AND cardinality(s.blockers) > 0)
  ORDER BY s.duration_sec DESC NULLS LAST;
$$;

COMMENT ON FUNCTION dba.sp_active_sessions(text, text, integer, text) IS
    'Real-time PostgreSQL session monitor with blocking detection.';
