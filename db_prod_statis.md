for production environments, I recommend generating a Database Health Summary instead of only database sizes.

The report should produce one row per database and include the following:

Database	Size (GB)	User Tables	Fragmented Tables	Fragmented Indexes	Avg Fragmentation %	Outdated Statistics	Outdated Stats %	Last Stats Update	Recovery	Compatibility	Status

For example:

Database	Size GB	Tables	Frag Tables	Frag Indexes	Avg Frag %	Outdated Stats	Stats %
ERPProd	1250	1850	415	1382	34.2	298	16.1
CRM	640	925	102	318	18.5	54	5.8
HR	82	154	8	22	6.3	4	2.5

I would also include
Database Information
Database Size (GB)
Data Size
Log Size
User Tables
Views
Stored Procedures
Functions
Index Count
Row Count (Approx)
Compatibility Level
Recovery Model
Last Full Backup
Last Log Backup
State
Index Health

Using sys.dm_db_index_physical_stats

Report

Total indexes
Fragmented indexes (>5%)
Highly fragmented indexes (>30%)
Fragmented tables
Average fragmentation
Maximum fragmentation
Largest fragmented index
Largest fragmented table
Statistics Health

Using

sys.stats
sys.dm_db_stats_properties

Report

Total statistics
Outdated statistics
Percentage outdated
Never updated statistics
Auto Created
User Created
Auto Update OFF
NORECOMPUTE enabled

Typical threshold:

Modification Counter >
SQRT(Rows * 1000)

or

Modification Counter >
20% of rows

(configurable)

Bonus Health Metrics

Also include

Missing Index Count
Duplicate Index Count
Unused Index Count
Disabled Index Count
Heap Tables
Forwarded Records
Tables without Primary Key
Tables without Clustered Index
Color Coding

Return a Health Status

Status	Condition
Healthy	Fragmentation <5%, Stats <5% outdated
Warning	Fragmentation 5–30%, Stats 5–15% outdated
Critical	Fragmentation >30%, Stats >15% outdated
Performance Consideration

A script that gathers all of this cannot be written as a single static query, because:

sys.dm_db_index_physical_stats must execute in each database context.
sys.dm_db_stats_properties is also database-specific.
Table counts, row counts, and statistics are scoped to the current database.

The production approach is to:

Loop through each online user database.
Switch context with USE [database].
Collect metrics into a central temporary table (#DatabaseHealth).
Return a consolidated report sorted by database size.

This avoids unsupported cross-database DMV access and scales well across servers with hundreds of databases.

My recommendation

Given the SQL Server performance work we've been discussing (index optimization, statistics, top queries, and production health checks), I would build this as a single Production Database Health Assessment script rather than a simple database-size report.

The script would produce:

Report 1: Database Summary (size, tables, indexes, fragmentation, statistics)
Report 2: Top 20 largest databases
Report 3: Top fragmented tables in every database
Report 4: Top fragmented indexes (>30%)
Report 5: Outdated statistics ranked by modification counter
Report 6: Missing indexes
Report 7: Duplicate indexes
Report 8: Unused indexes
Report 9: Database health score (0–100) with Green/Yellow/Red status
Report 10: Maintenance recommendations (Rebuild, Reorganize, Update Statistics, or No Action)