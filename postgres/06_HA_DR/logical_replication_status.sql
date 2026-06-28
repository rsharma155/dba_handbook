/*
================================================================================
Logical Replication Status — Publications and subscriptions
================================================================================
Description:
    Logical replication slots, publications, subscriptions, and worker state.

Action:  Inactive replication slots can retain WAL — monitor pg_replication_slots.

Criticality: High
================================================================================
*/

SELECT slot_name, plugin, slot_type, database, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal,
       active_pid
FROM pg_replication_slots
ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) DESC;

SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete, pubtruncate
FROM pg_publication;

SELECT subname, subenabled, subconninfo, subslotname
FROM pg_subscription;

SELECT subname, relid::regclass, received_lsn, latest_end_lsn, last_msg_send_time, last_msg_receipt_time
FROM pg_stat_subscription;
