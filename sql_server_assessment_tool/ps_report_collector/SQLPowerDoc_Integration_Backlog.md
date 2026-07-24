# Backlog: Integrate SQL Power Doc Gaps

Location: `ps_report_collector`  
Source comparison: [kendalvandyke/sqlpowerdoc](https://github.com/kendalvandyke/sqlpowerdoc) vs `Invoke-SqlInitialAssessment.ps1`  
Created: 2026-07-23  
Purpose: Track SQL Server and Windows-level inventory/assessment gaps to integrate into this collector without turning it into a full documentation dump.

## Goals

- Close high-value documentation and best-practice gaps from SQL Power Doc.
- Keep the collector focused on **assessment evidence** (findings + actionable HTML sections).
- Prefer SQL/DMV collectors first; add Windows/WMI only where it materially improves risk/ops conclusions.
- Fail soft into **Collection Errors** (same pattern as existing collectors).

## Priority legend

| Priority | Meaning |
|----------|---------|
| P0 | High assessment value; cheap to collect; do soon |
| P1 | Strong consulting value; moderate effort |
| P2 | Nice-to-have documentation depth; do after P0/P1 |
| P3 | Optional / heavy / rare; only if a client asks |

## Out of scope (unless explicitly requested)

- Full 74-sheet object catalog dump (every column/parameter/definition for all objects)
- Network subnet/DNS discovery across an estate (multi-server scanner)
- Excel COM workbook generation as primary output
- Azure SQL Database–specific Power Doc paths beyond capability signals already covered

---

## 1. SQL Server level backlog

### P0 — Must integrate

| ID | Gap | Why it matters | Suggested collector / evidence | Status |
|----|-----|----------------|--------------------------------|--------|
| SQL-P0-01 | DBCC CHECKDB recency | Integrity risk before upgrade/migration | `msdb`/`Suspect_Pages` / `DBCC DBINFO` or last known good CHECKDB signals | Todo |
| SQL-P0-02 | Login password policy / blank password / password=login | Security assessment gap | `sys.sql_logins` policy flags + blank/same-as-name checks | Todo |
| SQL-P0-03 | Agent job steps + schedules | Ops contract is incomplete without step/schedule detail | Expand Agent Jobs: steps, subsystems, schedules, next run | Todo |
| SQL-P0-04 | Startup procedures | Hidden boot-time logic / risk | `sys.procedures` / `sp_procoption` startup procs | Todo |
| SQL-P0-05 | Server DDL triggers | Invisible instance-level side effects | `sys.server_triggers` inventory + enabled state | Todo |
| SQL-P0-06 | Endpoints inventory | HA, mirroring, Service Broker, and connectivity dependencies | `sys.endpoints` + state/type/payload | Todo |
| SQL-P0-07 | Credentials (and proxy mapping if cheap) | Job/security blast radius | `sys.credentials` + Agent proxy links | Todo |
| SQL-P0-08 | Collation mismatch (server vs DB / DB vs column heuristic) | Join/compare/upgrade friction | Server collation + DB collation + optional column outliers | Todo |

### P1 — Should integrate

| ID | Gap | Why it matters | Suggested collector / evidence | Status |
|----|-----|----------------|--------------------------------|--------|
| SQL-P1-01 | Server audits / audit specifications | Compliance and forensic readiness | `sys.server_audits`, specs, actions, status | Todo |
| SQL-P1-02 | Certificates / asymmetric / symmetric keys | Encryption/security surface beyond TDE bit | DB + server key/cert inventory (no secret material) | Todo |
| SQL-P1-03 | Assemblies / CLR usage | Migration and surface-area risk | `sys.assemblies` + permission set + referencing objects | Todo |
| SQL-P1-04 | Plan guides | Forced behavior that can break after upgrade | `sys.plan_guides` inventory + enabled state | Todo |
| SQL-P1-05 | Resource Governor | Workload isolation/config dependency | pools/groups/classifier presence | Todo |
| SQL-P1-06 | Synonyms | Cross-object/cross-DB coupling | `sys.synonyms` map | Todo |
| SQL-P1-07 | Sequences (deeper than current identity/sequence skim) | Key design / HA / merge risk | Expand existing Identity and Sequences section | Todo |
| SQL-P1-08 | Partition functions / schemes | Storage/scalability design evidence | `sys.partition_functions` / `sys.partition_schemes` + usage | Todo |
| SQL-P1-09 | Full-Text catalogs / indexes (summary) | Feature dependency for target platform | Catalogs, stoplists, index counts (not every FT column) | Todo |
| SQL-P1-10 | Service Broker object catalog (summary) | Integration coupling beyond “broker enabled” | Queues/services/contracts/routes counts + enabled | Todo |
| SQL-P1-11 | Agent job notifications per job | Alerting completeness | Job → operator/mail notifications | Todo |
| SQL-P1-12 | Database Mail security / profile-account links | Mail path hardening | Profile ↔ account ↔ principal mapping | Todo |
| SQL-P1-13 | Drive / file placement BP findings | Classic outage patterns | C: placement, mixed data/log, uneven growth rules as findings | Todo |
| SQL-P1-14 | Page verify / auto-close / auto-shrink / trustworthy BP pack | Power Doc-style hygiene rules we only partially cover | Expand findings from existing DB landscape/config | Todo |
| SQL-P1-15 | Guest permissions on user DBs | Security hygiene | CONNECT grants for guest | Todo |
| SQL-P1-16 | User tables in system DBs (master/model/msdb) | Bad practice / upgrade pain | Object scan in system DBs | Todo |
| SQL-P1-17 | Hypothetical / disabled indexes leftover | Maintenance debt | `is_hypothetical` / `is_disabled` index flags | Todo |
| SQL-P1-18 | Linked server login mappings | Security + migration dependency | Expand Linked Servers section | Todo |

### P2 — Later / documentation depth

| ID | Gap | Why it matters | Suggested collector / evidence | Status |
|----|-----|----------------|--------------------------------|--------|
| SQL-P2-01 | Object definitions dump (procs/views/triggers text) | Useful for rewrite workshops; heavy | Optional switch; sample or top-N only by default | Todo |
| SQL-P2-02 | Column-level table documentation | Full data-model workbook replacement | Optional deep mode | Todo |
| SQL-P2-03 | Function/procedure parameters inventory | API/contract documentation | Optional deep mode | Todo |
| SQL-P2-04 | User-defined types / table types / XML schema collections | Completeness for schema docs | Type catalog summary first | Todo |
| SQL-P2-05 | Defaults / rules (legacy) | Rare but upgrade-relevant | Legacy object scan | Todo |
| SQL-P2-06 | Extended stored procedures | Legacy risk | `xp_` / extended proc inventory | Todo |
| SQL-P2-07 | SQL Trace definitions (legacy traces) | Ops debt; mostly superseded by XE/QS | Trace list + status | Todo |
| SQL-P2-08 | Object-level permissions matrix | Security audits | Optional `-IncludeObjectPermissions` style switch | Todo |
| SQL-P2-09 | Always On deep config sheets | Beyond current AG status | Replica/AG config detail pages | Todo |
| SQL-P2-10 | Change tracking / CDC deep object detail | Beyond feature flags | CT tables / CDC capture detail | Todo |
| SQL-P2-11 | Mirroring deep config | Legacy HA documentation | Only if mirroring detected | Todo |
| SQL-P2-12 | Application roles | Less common security principal type | DB application roles | Todo |
| SQL-P2-13 | Clustering SMO/OS quorum detail from SQL side | HA topology completeness | Cluster members/quorum signals | Todo |

### P3 — Optional / client-request only

| ID | Gap | Notes | Status |
|----|-----|-------|--------|
| SQL-P3-01 | Full Power Doc–style Excel export pack | Prefer keep HTML; Excel export already exists client-side for tables | Todo |
| SQL-P3-02 | CLIXML portable inventory archive | Useful for offline compare; not needed for assessment HTML | Todo |
| SQL-P3-03 | Multi-instance concurrent inventory | Architectural change; out of current single-target design | Todo |
| SQL-P3-04 | Azure SQL Database–specific Power Doc paths | Only if engagements routinely include WASD | Todo |

---

## 2. Windows level backlog

### P0 — Must integrate (high signal, low/moderate effort)

| ID | Gap | Why it matters | Suggested collector | Status |
|----|-----|----------------|---------------------|--------|
| WIN-P0-01 | Windows power plan | Non-High Performance hurts SQL latency | WMI/CIM or `powercfg` remote/local where permitted | Todo |
| WIN-P0-02 | OS version / edition / build | Supportability and driver/SQL matrix | CIM `Win32_OperatingSystem` | Todo |
| WIN-P0-03 | CPU / sockets / logical processors (OS view) | Compare with SQL scheduling/affinity | CIM `Win32_Processor` | Todo |
| WIN-P0-04 | Physical memory + pagefile config | Memory pressure root-cause | CIM memory + pagefile settings | Todo |
| WIN-P0-05 | Volume free space + allocation unit size (where available) | Complements SQL file volume view | Expand infrastructure volumes / disk CIM | Todo |
| WIN-P0-06 | SQL-related Windows services (deeper account/start mode) | Already partial; enrich service account + delayed start | Service CIM + sc/WMI | Todo |

### P1 — Should integrate

| ID | Gap | Why it matters | Suggested collector | Status |
|----|-----|----------------|---------------------|--------|
| WIN-P1-01 | Installed patches / recent hotfixes (summary) | Supportability and known-issue correlation | CIM quick-fix / hotfix summary (top recent) | Todo |
| WIN-P1-02 | Local Administrators group membership | Privilege escalation / SQL service account risk | Local group members (needs admin) | Todo |
| WIN-P1-03 | SQL service account local rights summary | “Service account is local admin” classic finding | Compare service accounts vs Administrators | Todo |
| WIN-P1-04 | NIC configuration / speed / teaming signals | Throughput and AG/network assumptions | Network adapter CIM | Todo |
| WIN-P1-05 | Disk layout (physical disk → partition → volume) | Data/log/TempDB placement validation | Disk CIM map | Todo |
| WIN-P1-06 | Cluster / failover cluster node membership (OS) | HA topology beyond AG DMVs | Cluster CIM/registry where present | Todo |
| WIN-P1-07 | Antivirus exclusions heuristic note | Perf risk; cannot fully prove | Document checklist prompt + any discoverable exclude keys | Todo |
| WIN-P1-08 | Time sync / timezone | Auth, AG, job schedule correctness | TimeZone + w32tm status if accessible | Todo |

### P2 — Later

| ID | Gap | Why it matters | Suggested collector | Status |
|----|-----|----------------|---------------------|--------|
| WIN-P2-01 | BIOS / hardware model / serial | Asset documentation | CIM BIOS/ComputerSystemProduct | Todo |
| WIN-P2-02 | Installed applications inventory | Licensing/doc; noisy | Optional app list filter for SQL-related only | Todo |
| WIN-P2-03 | Shares | Accidental data exposure | Share CIM | Todo |
| WIN-P2-04 | Local users/groups full inventory | Broad security doc | Optional deep mode | Todo |
| WIN-P2-05 | Event log settings / recent critical errors | Ops signal; can be noisy | Optional recent System/Application errors | Todo |
| WIN-P2-06 | Printers / sound / video / tape devices | Low SQL value | Skip unless full Windows doc mode | Todo |
| WIN-P2-07 | IIS sites/apps | Only if SQL + web colocated is in scope | Optional IIS summary | Todo |
| WIN-P2-08 | RDS/desktop sessions | Ops noise for DBA assessment | Skip by default | Todo |
| WIN-P2-09 | Startup commands | Persistence/security review | Optional | Todo |
| WIN-P2-10 | Domain / OU / last logged-on user | Estate documentation | Optional | Todo |

### P3 — Optional

| ID | Gap | Notes | Status |
|----|-----|-------|--------|
| WIN-P3-01 | Full WindowsInventory Excel workbook parity | Only if product goal becomes “Power Doc replacement” | Todo |
| WIN-P3-02 | Network discovery of Windows hosts | Estate scanner; separate product concern | Todo |

---

## 3. Implementation workstreams

### Workstream A — SQL evidence collectors

1. Add `.sql` files under `sql_scripts/` (prefer new folders only if needed, e.g. `11_windows_host` stays PS/WMI).
2. Register in `$AssessmentSqlFiles`.
3. Wire collect + soft-fail.
4. Add section purpose text + report group placement.
5. Add findings where Critical/Warning is clear.
6. Update Assessment Scope matrix (auto vs heuristic vs interview).

### Workstream B — Windows host collectors

1. Add optional PowerShell/CIM collectors gated by switch, e.g. `-IncludeWindowsHostInfo`.
2. Do not require Windows admin for core SQL assessment; Windows section fails soft when rights/WMI blocked.
3. Place under report group **Current Architecture / Landscape** (or new **Windows Host** group).
4. Document permission needs in README.

### Workstream C — Findings / BP rules pack

Convert selected Power Doc assessment rules into our findings engine:

- Power plan not High Performance
- CHECKDB stale
- Weak login password policy
- System DB / user DB on C:
- Mixed data/log on same volume
- Guest enabled on user DB
- Startup procs present
- xp_cmdshell enabled (likely already covered)
- Trace flags unusual (partially covered)

### Workstream D — Docs / README

- Update coverage tables: Automated SQL / Automated Windows / Heuristic / Interview-only.
- Explicitly state Windows collection is optional and permission-sensitive.

---

## 4. Suggested delivery milestones

### Milestone 1 — Security & integrity quick wins (SQL P0)

- SQL-P0-01, SQL-P0-02, SQL-P0-04, SQL-P0-05, SQL-P0-06, SQL-P0-07, SQL-P0-08
- Plus findings for each

### Milestone 2 — Ops completeness (SQL Agent + mail)

- SQL-P0-03, SQL-P1-11, SQL-P1-12
- Keep failure history (already present)

### Milestone 3 — Windows host essentials

- WIN-P0-01 … WIN-P0-06
- WIN-P1-01 … WIN-P1-03
- Gated by `-IncludeWindowsHostInfo`

### Milestone 4 — Feature dependency catalog

- SQL-P1-01 … SQL-P1-10, SQL-P1-15 … SQL-P1-18
- Summary-level sections (counts + key attributes), not full object dumps

### Milestone 5 — Deep documentation mode (optional)

- SQL-P2-* and WIN-P2-* behind `-DeepDocumentation` / similar switch
- Default assessment run stays fast

---

## 5. Acceptance criteria (per backlog item)

An item is **Done** when:

1. Collector exists and is registered.
2. Section appears in HTML when data exists (or forced empty state if always-show).
3. Purpose summary (Why / Purpose / Assessment value) is present.
4. Failures land in Collection Errors without aborting the run.
5. At least one finding rule exists when Critical/Warning signal is objective.
6. README/Scope mentions whether it is automated, heuristic, or optional-Windows.
7. No secrets are written (passwords, private keys, connection strings).

---

## 6. Tracking

| Field | Value |
|-------|-------|
| Backlog owner | TBD |
| Default mode target | Assessment (fast) |
| Optional modes | `-IncludeWindowsHostInfo`, later `-DeepDocumentation` |
| Related script | `Invoke-SqlInitialAssessment.ps1` |
| Related docs | `README.md`, Assessment Scope panel |

Update the **Status** column (`Todo` → `In Progress` → `Done`) as items are implemented.
