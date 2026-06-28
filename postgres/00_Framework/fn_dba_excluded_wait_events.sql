/*
================================================================================
fn_dba_excluded_wait_events — Benign wait events filter
================================================================================
Description:
    Returns wait event types that are normal background activity and should
    be excluded from bottleneck analysis (similar to SQL Server fn_DBA_ExcludedWaitTypes).

Output:  Table of wait_event values to exclude.

Criticality: Low (framework helper)
================================================================================
*/

CREATE OR REPLACE FUNCTION dba.fn_excluded_wait_events()
RETURNS TABLE (wait_event text)
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT unnest(ARRAY[
        'Activity',
        'ArchiverMain',
        'AutoVacuumMain',
        'BgWriterHibernate',
        'BgWriterMain',
        'CheckpointerMain',
        'CheckpointerMain',
        'LogicalLauncherMain',
        'LogicalReplicationLauncherMain',
        'WalSenderMain',
        'WalWriterMain',
        'ClientRead',
        'ClientWrite',
        'Extension',
        'Timeout',
        'PgSleep',
        'SafeSnapshot'
    ]);
$$;

COMMENT ON FUNCTION dba.fn_excluded_wait_events() IS
    'Benign PostgreSQL wait events excluded from performance triage.';
