/*
================================================================================
Wait Events Reference — Common PostgreSQL waits with investigation steps
================================================================================
Description:
    Educational reference for junior DBAs mapping wait events to actions.

Criticality: Low (reference)
================================================================================
*/

SELECT wait_event, category, typical_cause, investigation
FROM (VALUES
    ('relation', 'Lock', 'Concurrent DDL/DML on same table', 'SELECT * FROM blocking_and_locks.sql'),
    ('transactionid', 'Lock', 'Row-level lock waiting for another xact', 'Find blocking pid via pg_blocking_pids()'),
    ('tuple', 'Lock', 'Hot page / concurrent updates', 'Reduce transaction duration; review HOT updates'),
    ('DataFileRead', 'IO', 'Reading heap/index pages from disk', 'Check buffer hit ratio; add indexes'),
    ('BufferIO', 'IO', 'Buffer manager I/O', 'Correlate with checkpoint and bgwriter stats'),
    ('WalSync', 'IO', 'WAL flush to disk', 'Review wal_sync_method, storage latency'),
    ('WalWrite', 'IO', 'Writing WAL buffers', 'High write load — batch commits if safe'),
    ('ClientRead', 'Client', 'Server waiting for client', 'App not fetching rows; reduce result sets'),
    ('ClientWrite', 'Client', 'Server waiting to send to client', 'Network or client processing delay'),
    ('ParallelBitmapScan', 'CPU', 'Parallel query execution', 'Review max_parallel_workers settings'),
    ('ProcArray', 'LWLock', 'Snapshot / proc array contention', 'Very high connection churn'),
    ('BufferContent', 'LWLock', 'Buffer page contention', 'Heavy concurrent access same pages')
) AS ref(wait_event, category, typical_cause, investigation)
ORDER BY category, wait_event;
