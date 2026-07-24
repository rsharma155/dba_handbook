# Client Checklist — SQL 2016 → 2022 (Compat 160 Performance)

> Script paths below are relative to the **package root** (parent of this `docs/` folder).

**Client / DB:** ______________________  
**DBA owner:** ______________________  
**Change window:** ______________________

## Current state
- [ ] SQL Server 2022 build / CU noted: ____________
- [ ] Database restored via backup/restore
- [ ] Production still on **compatibility 130** (recommended until remediated)
- [ ] Application verified OK at 130 on new server

## Must-do before 160
- [ ] Environment baseline captured (`01_Diagnostics/01_Capture_Environment_Baseline.sql`)
- [ ] Query Store enabled & sized (`03_QueryStore_PlanForce/01_Enable_QueryStore.sql`)
- [ ] 3–7 days of plans captured at 130
- [ ] UAT copy tested at 160 with same workload
- [ ] Regression list produced (`03_QueryStore_PlanForce/02_Find_Regressed_Queries.sql`)
- [ ] Statistics refreshed on hot tables (`04_Statistics_Indexes/01_Update_Statistics_PostMigration.sql`)
- [ ] Instance settings reviewed: MAXDOP, CTFP, max memory, TempDB (`02_Configuration/`)
- [ ] Or use interactive guide: `Compat160_Targeted_Fixes.html` → Guided approach

## Remediation choices (pick & document)
- [ ] Forced plans for top regressions (list plan_ids): ____________
- [ ] Query Store hints applied (list query_ids): ____________
- [ ] Temporary `LEGACY_CARDINALITY_ESTIMATION = ON` (yes/no): ____
- [ ] Code rewrites scheduled (ticket #s): ____________

## Production cutover
- [ ] Rollback rehearsed (`COMPATIBILITY_LEVEL = 130`)
- [ ] Flip to 160 + clear DB procedure cache
- [ ] Health check every 15–30 min for first 2 hours (`07_Monitoring_Baseline\02_Post_Cutover_Health_Check.sql`)
- [ ] App owners confirm latency/timeouts

## Exit criteria (done)
- [ ] Compat **160**
- [ ] `LEGACY_CARDINALITY_ESTIMATION` **OFF** (or approved exception with end date)
- [ ] No unresolved P1/P2 regressions vs 130 baseline
- [ ] Forced plans reviewed; debt tickets opened with dates

## Emergency contacts
- DBA: ____________  
- App lead: ____________  
- Rollback authority: ____________  
