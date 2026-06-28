# DBA Framework (00_Framework)

Run these scripts **once per SQL Server instance** (recommended: dedicated admin database):

| Order | Script |
|-------|--------|
| 1 | `fn_DBA_ExcludedWaitTypes.sql` |
| 2 | `fn_DBA_AgentRunDurationSeconds.sql` |
| 3 | `sp_DBA_ForEachDatabase.sql` |
| 4 | `sp_DBA_QueryStoreRegressions.sql` |
| 5 | `sp_DBA_HealthCheck.sql` |
| 6 | `sp_DBA_WaitAnalysis.sql` |
| 7 | `sp_DBA_IndexReview.sql` |
| 8 | `sp_DBA_SecurityAudit.sql` |
| 9 | `sp_DBA_BackupReview.sql` |
| 10 | `sp_DBA_ActiveSessions.sql` |
| 11 | `sp_DBA_PlanCacheAnalyzer.sql` |
| 12 | `sp_DBA_BaselineCapture.sql` |
| 13 | `../00_Repository/AssessmentFindingTableType.sql` |
| 14 | `sp_DBA_SaveAssessmentRun.sql` |

## Objects

| Object | Purpose |
|--------|---------|
| `dbo.fn_DBA_ExcludedWaitTypes()` | Benign wait-type filter (single source of truth) |
| `dbo.fn_DBA_AgentRunDurationSeconds()` | msdb `run_duration` HHMMSS -> seconds |
| `dbo.sp_DBA_ForEachDatabase` | Cross-DB execution with `QUOTENAME`, `@DatabaseList`, `TRY/CATCH` |
| `dbo.sp_DBA_QueryStoreRegressions` | True multi-plan Query Store regression detection |
| `dbo.sp_DBA_HealthCheck` | Consolidated health findings orchestrator |
| `dbo.sp_DBA_WaitAnalysis` | Top wait types with categories and recommendations |
| `dbo.sp_DBA_IndexReview` | Unused, missing indexes, and fragmentation across DBs |
| `dbo.sp_DBA_SecurityAudit` | Orphaned users, sysadmin, guest, trustworthy, password policies |
| `dbo.sp_DBA_BackupReview` | Backup SLA, log chain, recovery model alignment |
| `dbo.sp_DBA_ActiveSessions` | Real-time active session monitor with DETAIL/SUMMARY/BLOCKING modes |
| `dbo.sp_DBA_PlanCacheAnalyzer` | Plan cache analysis with anti-pattern detection and multiple sort orders |
| `dbo.sp_DBA_BaselineCapture` | Performance snapshot persistence for trending (requires `BaselineSnapshot` table from `DBARepository_Persistence.sql`) |
| `dbo.sp_DBA_SaveAssessmentRun` | Save assessment run + metrics to history tables |

## Cross-database scripts

These scripts accept `@DatabaseList` and use `sp_DBA_ForEachDatabase` when deployed (with manual fallback):

- `05_Index_Statistics/index_usage_efficiency.sql`
- `05_Index_Statistics/physical_stats_and_heaps.sql`
- `05_Index_Statistics/advanced_index_analysis.sql`
- `05_Index_Statistics/statistics_freshness.sql`
- `03_Storage_Engine/database_files_growth.sql`
- `07_Security/authorization_audit.sql`
- `08_Advanced/inmemory_compression.sql`
- `08_Advanced/cdc_health.sql`
- `08_Advanced/query_store_health.sql`
- `11_Query_Store/regressed_queries.sql`

## Query Store regression

```sql
EXEC dbo.sp_DBA_QueryStoreRegressions
    @DatabaseList = N'SalesDB',
    @RegressionPctThreshold = 50,  -- slow plan must be 50%+ worse than best plan
    @RecentHours = 24,
    @LookbackHours = 168,
    @MinExecutions = 5;
```

Logic: finds `query_id` with **multiple plans** where the slowest recent plan exceeds the best plan by `@RegressionPctThreshold` and executed within `@RecentHours`.
