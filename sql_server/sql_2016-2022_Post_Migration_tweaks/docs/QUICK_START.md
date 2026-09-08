# Quick Start (Read This First)

## The situation
SQL Server **2016 → 2022** via backup/restore. App is fine at **compat 130**. Slow at **compat 160**.

## Most likely cause
**Cardinality Estimator / optimizer plan changes** under compatibility 160 — not a “broken” install.

## Fastest safe path

1. **Keep production at 130** for now.  
2. Enable **Query Store** → `../03_QueryStore_PlanForce/01_Enable_QueryStore.sql`  
3. On UAT, flip to **160** and find regressions → `../03_QueryStore_PlanForce/02_Find_Regressed_Queries.sql`  
4. Apply quick wins:
   - Update stats FULLSCAN on hot tables → `../04_Statistics_Indexes/`
   - Force last good plans / Query Store hints → `../03_QueryStore_PlanForce/` and `../05_Compatibility_CE_Controls/`
   - If *many* queries regress:  
     `ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;`
5. Align instance settings (MAXDOP, CTFP=50-ish, max memory, TempDB) → `../02_Configuration/`
6. Rewrite CE-sensitive T-SQL → `../06_Code_Rewrite_Patterns/` and `00_Rewrite_Guide.md`
7. Production cutover using `CLIENT_CUTOVER_CHECKLIST.md` + `../05_Compatibility_CE_Controls/03_Compatibility_Level_Change_Runbook.sql`

## Emergency rollback
```sql
ALTER DATABASE [YourDB] SET COMPATIBILITY_LEVEL = 130;
```

## Full playbook
See `00_README_Troubleshooting_Playbook.md` (this `docs/` folder).

## Interactive HTML
From the package root, open `../Compat160_Targeted_Fixes.html` (Guided approach + Script library).

## Sharing this package
Zip the whole package folder (parent of `docs/`) and open `Compat160_Targeted_Fixes.html` from the unzipped root.
See `HOW_TO_SHARE.md` - no hard-coded drive paths.
