# SQL Server Post-Migration Performance Troubleshooting (Prod_Migration)

Production-grade playbook for **severe slowdown after SQL Server edition/version upgrade** — especially patterns like:

- Application queries suddenly very slow
- **SSMS Object Explorer** slow to expand databases
- **Low CPU, low logical reads, but very high elapsed time**
- Query hints (`MAXDOP 1`, `RECOMPILE`, `ARITHABORT`, `FORCE ORDER`) **do not help**
- Same slowness when running the query **on the VM locally** (rules out network)

---

## Why your symptoms point to WAITING, not a bad plan


| Metric            | What it measures                 | Your pattern |
| ----------------- | -------------------------------- | ------------ |
| **Elapsed time**  | Wall-clock time (start → finish) | High         |
| **CPU time**      | Time SQL spent executing on CPU  | Low          |
| **Logical reads** | Pages read from buffer pool      | Low          |


**Interpretation:** The query is spending most of its time **idle — waiting for something else**. Optimizer hints change *how* work runs; they do **not** remove blocking, latch contention, disk stalls, compilation queues, metadata security checks, or thread starvation.

**Why hints failed:** `MAXDOP`, `RECOMPILE`, `ARITHABORT`, and `FORCE ORDER` address parallelism skew, plan reuse, floating-point behavior, and join order. None of them fix:

- Blocking (`LCK_`* waits)
- Metadata / latch contention (`LATCH_*`, `METADATA_LATCH_*`) — common with **SSMS expand**
- Storage latency (`PAGEIOLATCH_`*, `WRITELOG`, `IO_COMPLETION`)
- Memory grant queues (`RESOURCE_SEMAPHORE`)
- Compilation storms (`RESOURCE_SEMAPHORE_QUERY_COMPILE`)
- Thread pool exhaustion (`THREADPOOL`)
- Windows / filter-driver delays (`PREEMPTIVE_OS_*`)

**Why local VM is still slow:** Running on the same server eliminates **network** (`ASYNC_NETWORK_IO`) as the cause. The bottleneck is **inside SQL Server or the OS** (locks, latches, I/O subsystem, AV scanning, AD token resolution, misconfigured memory/parallelism left from Express).

---

## Triage order (run today)

```
┌─────────────────────────────────────────────────────────────────┐
│ 0. 02_Upgrade_Validation/04_complete_post_upgrade_configuration_report.sql │
│    → FULL REPORT: instance, DBs, waits, TempDB, I/O, findings   │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. 01_Quick_Triage/00_RUN_FIRST_triage_playbook.sql            │
│    → Snapshot: version, memory, blocking, top waits, compat      │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. 03_Elapsed_Time_Diagnostics/01_elapsed_vs_worker_time_gap   │
│    → Confirm wait vs work gap on your slow query                 │
└────────────────────────────┬────────────────────────────────────┘
                             ▼
        ┌────────────────────┴────────────────────┐
        ▼                                         ▼
┌───────────────────┐                   ┌───────────────────────────┐
│ Blocking?         │                   │ No blocking → Wait stats  │
│ 05_Concurrency/   │                   │ 04_Wait_Stats/ delta +    │
│ 01_blocking...    │                   │ decoder scripts           │
└─────────┬─────────┘                   └─────────────┬─────────────┘
          ▼                                           ▼
   Fix head blocker                          Match wait pattern →
   / transaction scope                       targeted script below
```

### Wait pattern → next script


| Top wait types                               | Likely cause (post-migration)                | Next script                                                                                 |
| -------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `LCK_M_*`, `LCK_M_SCH_*`                     | Blocking, schema locks, long transactions    | `05_Concurrency/01_blocking_and_locks.sql`                                                  |
| `LATCH_*`, `PAGELATCH_*`, `METADATA_LATCH_*` | Metadata contention, TempDB, security cache  | `04_Wait_Stats/03_latch_metadata_waits.sql`, `05_Concurrency/02_ssms_metadata_slowness.sql` |
| `PAGEIOLATCH_*`, `WRITELOG`, `IO_COMPLETION` | Disk / SAN / AV / misaligned files           | `08_Storage_OS/01_io_latency_deep_dive.sql`                                                 |
| `RESOURCE_SEMAPHORE`                         | Memory grants (sort/hash)                    | `07_Instance_Config/01_post_migration_config_audit.sql`                                     |
| `RESOURCE_SEMAPHORE_QUERY_COMPILE`           | Plan compilation storm                       | `06_Optimizer_Plans/03_query_store_regression.sql`, clear plan cache (controlled)           |
| `SOS_SCHEDULER_YIELD` + high signal waits    | CPU scheduling pressure                      | `07_Instance_Config/01_post_migration_config_audit.sql` (MAXDOP/CTFP)                       |
| `PREEMPTIVE_OS_*`                            | Windows API (AD, file system, AV)            | `08_Storage_OS/02_os_integration_post_migration.sql`                                        |
| `THREADPOOL`                                 | Worker thread starvation                     | **Critical** — reduce load, check `max worker threads`                                      |
| `CXPACKET` / `CXCONSUMER`                    | Parallelism (less likely if MAXDOP 1 tested) | `06_Optimizer_Plans/01_compatibility_and_ce.sql`                                            |


---

## Common root causes: Express → Developer / 2019 → 2025

1. `**max server memory` still capped** at Express-era value (~1.4 GB effective limit on Express; config may still be low)
2. **Compatibility level still 150** while running on 2025 engine — mixed CE behavior, different defaults
3. **Query Store forced bad plan** carried over from migration
4. **Statistics / cardinality** — upgrade changed CE thresholds; plans look fine but wait on grants/locks
5. **TempDB** — single file, wrong size, PFS/SGAM latch contention after increased parallelism
6. **Instant File Initialization (IFI) off** — file growth zero-fills cause `PREEMPTIVE_OS_WRITEFILEGATHER`
7. **Antivirus / backup agent** scanning `.mdf`/`.ldf` after migration to new paths
8. **Orphaned Express parallelism settings** — MAXDOP, CTFP, limited schedulers; **NUMA topology expansion** (see `02_Upgrade_Validation/03_cpu_numa_topology.sql`)
9. **Database auto_close / auto_shrink** enabled (disastrous on user DBs)
10. **AD / Windows auth latency** for metadata enumeration (SSMS expand triggers security checks)
11. **DBCC or maintenance job** holding schema-mod locks during business hours
12. **Trace flags** from old environment conflicting with 2025 optimizer

---

## How to read `sys.dm_os_sys_info` and `sys.dm_os_waiting_tasks`

- `**sqlserver_start_time`** — wait stats are cumulative since then; use `04_Wait_Stats/01_wait_stats_delta_capture.sql` for clean deltas
- `**scheduler_id`, `status`, `runnable_tasks_count**` — sustained `runnable_tasks_count > 0` = CPU pressure
- `**wait_type` on active requests** — the **smoking gun** for high elapsed / low CPU queries
- `**wait_resource`** — lock hash, page address, or latch class; use with blocking scripts

---

## Query hints — when to use and when to stop

See `06_Optimizer_Plans/02_query_hint_guide.sql` for copy-paste examples.

**Use hints when:** plan regression is proven (Query Store / plan XML), CE mismatch is confirmed, or parallelism skew is the top wait.

**Stop using hints when:** elapsed >> CPU time and session `wait_type` is not `CXPACKET` — pivot to **wait analysis** instead.

---

## Extended Events (single-query capture)

If wait stats are inconclusive, deploy:

`09_Extended_Events/01_xe_single_query_wait_capture.sql`

Run your slow query, then review the XE output for per-statement `wait_info` — this is the industry-standard method when DMVs show conflicting signals.

---

## Safe remediation

All fix scripts with rollback notes: `07_Instance_Config/02_recommended_fixes_with_rollback.sql`

**Never** in production without a change window:

- Blind `DBCC FREEPROCCACHE`
- Compatibility level change without testing
- `KILL` head blockers without identifying root cause

---

## Script index


| Folder                         | Scripts                                                                                                 |
| ------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `01_Quick_Triage/`             | `00_RUN_FIRST_triage_playbook.sql`                                                                      |
| `02_Upgrade_Validation/`       | `04_complete_post_upgrade_configuration_report.sql`, `01_instance_upgrade_validation.sql`, `02_express_to_developer_limits_check.sql`, `03_cpu_numa_topology.sql` |
| `03_Elapsed_Time_Diagnostics/` | `01_elapsed_vs_worker_time_gap.sql`, `02_capture_live_session_waits.sql`                                |
| `04_Wait_Stats/`               | `01_wait_stats_delta_capture.sql`, `02_post_migration_wait_decoder.sql`, `03_latch_metadata_waits.sql`  |
| `05_Concurrency/`              | `01_blocking_and_locks.sql`, `02_ssms_metadata_slowness.sql`                                            |
| `06_Optimizer_Plans/`          | `01_compatibility_and_ce.sql`, `02_query_hint_guide.sql`, `03_query_store_regression.sql`               |
| `07_Instance_Config/`          | `01_post_migration_config_audit.sql`, `02_recommended_fixes_with_rollback.sql`                          |
| `08_Storage_OS/`               | `01_io_latency_deep_dive.sql`, `02_os_integration_post_migration.sql`, `03_tempdb_autogrowth_audit.sql` |
| `09_Extended_Events/`          | `01_xe_single_query_wait_capture.sql`                                                                   |


Run `MASTER_INDEX.sql` in SSMS for a printable execution checklist.