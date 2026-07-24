My Migration Troubleshooting Methodology

I normally divide the investigation into 8 phases.

Phase 1
Server Validation

↓

Phase 2
Database Validation

↓

Phase 3
Execution Plan Analysis

↓

Phase 4
Statistics Validation

↓

Phase 5
Index Validation

↓

Phase 6
Parameter Sniffing Analysis

↓

Phase 7
Intelligent Query Processing Analysis

↓

Phase 8
Code Refactoring
Phase 1 – Server Validation

First make sure SQL Server itself is configured correctly.

Check

SELECT
SERVERPROPERTY('ProductVersion'),
SERVERPROPERTY('ProductLevel'),
SERVERPROPERTY('Edition');

Should be latest CU.

Many migration issues disappear after installing the newest CU.

Max Degree of Parallelism
EXEC sp_configure 'max degree of parallelism';

Generally

8 CPUs

MAXDOP = 8

16 CPUs

MAXDOP = 8

32 CPUs

MAXDOP = 8

64 CPUs

MAXDOP = 8

unless workload dictates otherwise.

Cost Threshold for Parallelism

Default

5

is terrible.

Usually

40-60

works much better.

Example

EXEC sp_configure 'cost threshold for parallelism';
TempDB

Check

Number of files
Autogrowth
Trace Flags no longer needed
Instant File Initialization
Storage latency
Memory
EXEC sp_configure 'max server memory';

Never leave unlimited.

Phase 2 Database Validation

Check compatibility

SELECT
name,
compatibility_level
FROM sys.databases;

Check database scoped configurations.

SELECT *
FROM sys.database_scoped_configurations;

Pay special attention to

LEGACY_CARDINALITY_ESTIMATION

PARAMETER_SNIFFING

QUERY_OPTIMIZER_HOTFIXES

OPTIONAL_PARAMETER_PLAN_OPTIMIZATION

PARAMETER_SENSITIVE_PLAN_OPTIMIZATION
Phase 3 Capture Regressed Queries

This is the MOST IMPORTANT STEP.

Enable Query Store.

ALTER DATABASE YourDB
SET QUERY_STORE = ON;

Then compare plans.

SELECT
q.query_id,
p.plan_id,
rs.avg_duration,
rs.avg_cpu_time,
rs.avg_logical_io_reads
FROM sys.query_store_runtime_stats rs
JOIN sys.query_store_plan p
ON rs.plan_id=p.plan_id
JOIN sys.query_store_query q
ON p.query_id=q.query_id
ORDER BY rs.avg_duration DESC;

Find

Fast plan under 130

↓

Slow plan under 160

Compare execution plans.

Phase 4 Statistics

After restore

Always run

EXEC sp_updatestats;

or better

UPDATE STATISTICS dbo.TableName
WITH FULLSCAN;

Large tables

FULLSCAN

Critical OLTP

FULLSCAN

Small tables

Sample is fine

Check stale statistics.

SELECT
OBJECT_NAME(object_id),
name,
STATS_DATE(object_id,stats_id)
FROM sys.stats;
Phase 5 Index Health

Check fragmentation

SELECT
OBJECT_NAME(object_id),
avg_fragmentation_in_percent,
page_count
FROM sys.dm_db_index_physical_stats
(
DB_ID(),
NULL,
NULL,
NULL,
'SAMPLED'
)
WHERE page_count>1000;

Check missing indexes

SELECT *
FROM sys.dm_db_missing_index_details;

Check unused indexes

SELECT *
FROM sys.dm_db_index_usage_stats;
Phase 6 Parameter Sniffing

One of the biggest causes.

Symptoms

Compatibility 130

Fast

Compatibility 160

Slow

Reason

Different execution plan selected.

Check

SELECT
qs.execution_count,
qs.total_elapsed_time,
st.text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st;

If parameter sniffing exists

Test

OPTION(RECOMPILE)

If query suddenly becomes fast

You found the issue.

SQL Server 2022 introduces

Parameter Sensitive Plan Optimization (PSP)

Sometimes it helps.

Sometimes it changes plans unexpectedly.

Phase 7 Intelligent Query Processing

SQL Server 2022 introduces many optimizer features.

Examples

Batch Mode

Scalar UDF Inlining

Memory Grant Feedback

Adaptive Joins

Table Variable Deferred Compilation

Approx Count Distinct

Parameter Sensitive Plans

CE Feedback

DOP Feedback

Optimized Plan Forcing

Optional Parameter Optimization

Each one may alter plans.

Sometimes disabling one feature is enough.

Example

ALTER DATABASE SCOPED CONFIGURATION
SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = OFF;

Test again.

Disable Optional Parameter Optimization

ALTER DATABASE SCOPED CONFIGURATION
SET OPTIONAL_PARAMETER_OPTIMIZATION = OFF;

Disable CE Feedback

ALTER DATABASE SCOPED CONFIGURATION
SET CE_FEEDBACK = OFF;

Test individually.

Never disable everything together.

Phase 8 Execution Plan Comparison

This is where 90% of time is spent.

Compare

Estimated Rows

Actual Rows

Seek

Scan

Nested Loop

Hash Join

Merge Join

Memory Grant

Spills

Sort

Warnings

Missing Indexes

Residual Predicate

Implicit Conversion

Parallelism

Common Query Rewrites
1. Functions on WHERE clause

Bad

WHERE YEAR(OrderDate)=2024

Better

WHERE OrderDate
BETWEEN '20240101'
AND '20241231'
2. ISNULL

Bad

WHERE ISNULL(Status,0)=1

Better

WHERE Status=1
OR Status IS NULL
3. SELECT *

Bad

SELECT *

Good

SELECT
CustomerID,
Name,
Address
4. Scalar UDF

Bad

SELECT dbo.CalculatePrice(ID)

Better

Inline TVF

or

JOIN

5. Multi-statement TVF

Avoid.

Inline TVF is much faster.

6. Cursor

Replace with

MERGE

Window Functions

CTEs

Set-based UPDATE
7. Table Variables

SQL 2022 improves them.

But temp tables are still often better.

8. OR Conditions

Instead of

WHERE
ID=@ID
OR Name=@Name

Use

Dynamic SQL

or

UNION ALL

Cardinality Estimator Testing

One excellent diagnostic test is

ALTER DATABASE SCOPED CONFIGURATION
SET LEGACY_CARDINALITY_ESTIMATION = ON;

If everything becomes fast

You found

Cardinality Estimator regression

Then compare plans.

Query Store Hints (SQL Server 2022)

This is one of my favorite SQL Server 2022 features.

Instead of changing code

Force

MAXDOP

RECOMPILE

USE HINT

OPTIMIZE FOR

LEGACY CE


using Query Store.

Example

EXEC sys.sp_query_store_set_hints
     @query_id = 123,
     @query_hints = N'OPTION(RECOMPILE)';

No application deployment required.

Automatic Plan Correction

Enable Query Store Automatic Tuning.

ALTER DATABASE CURRENT
SET AUTOMATIC_TUNING
(
FORCE_LAST_GOOD_PLAN = ON
);

SQL Server can automatically revert to a previously known good plan if it detects a regression.

Extended Events

Create a lightweight session for:

sql_statement_completed
query_post_execution_showplan (use selectively due to overhead)
sort_warning
hash_warning
exchange_spill
query_memory_grant_usage
degree_of_parallelism
wait_info

This helps identify memory spills, excessive waits, and parallelism issues that may not be obvious from DMVs alone.

Wait Statistics Analysis

Capture waits before and after changing compatibility to 160:

SELECT
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type NOT LIKE 'SLEEP%'
ORDER BY wait_time_ms DESC;

Look for significant increases in waits such as PAGEIOLATCH_*, CXPACKET, CXCONSUMER, RESOURCE_SEMAPHORE, SOS_SCHEDULER_YIELD, or WRITELOG, as these can point to the underlying bottleneck rather than the optimizer alone.

Real-World Root Causes (Approximate Frequency)

Based on consulting experience with SQL Server 2016→2019→2022 upgrades, the most common causes are:

Cause	Approximate Frequency	Typical Resolution
Query Optimizer chose a different execution plan	~40%	Compare plans, Query Store hints, index tuning
Outdated or low-quality statistics	~20%	Update statistics (FULLSCAN for critical tables)
Parameter sniffing / parameter-sensitive queries	~15%	PSP optimization, OPTION (RECOMPILE), Query Store hints
Missing or suboptimal indexes	~10%	Create or redesign indexes based on actual workload
Cardinality Estimator behavior changes	~8%	Investigate estimates, test legacy CE temporarily
Intelligent Query Processing feature interactions	~5%	Test database scoped configurations individually
Other configuration or application-specific issues	~2%	Server configuration, code changes, resource bottlenecks
Recommended Engagement Workflow

For production systems, I recommend the following sequence:

Keep the database at compatibility level 130 to maintain stability.
Ensure SQL Server 2022 is patched to the latest Cumulative Update.
Enable and populate Query Store under the stable workload.
Restore a copy of the database to a non-production environment.
Switch the test database to compatibility level 160.
Use Query Store to identify regressed queries and compare execution plans.
Update statistics and review index design.
Test database scoped configurations one at a time (for example, LEGACY_CARDINALITY_ESTIMATION, PARAMETER_SENSITIVE_PLAN_OPTIMIZATION, OPTIONAL_PARAMETER_OPTIMIZATION, CE_FEEDBACK).
Apply Query Store hints or optimize individual queries where needed.
After validating performance, move production to compatibility level 160 and continue monitoring for regressions.

This targeted approach is far more effective than trying to optimize the entire application at once and is the strategy typically used in large enterprise SQL Server upgrades.