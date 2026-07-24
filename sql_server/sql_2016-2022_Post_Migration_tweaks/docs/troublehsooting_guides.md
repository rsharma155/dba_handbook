SQL Server 2016 to 2022 Migration: Performance Troubleshooting Guide
📋 Executive Summary
The performance degradation when changing compatibility level from 130 (SQL 2016) to 160 (SQL 2022) is a known pattern caused by changes in the Cardinality Estimator (CE), new Intelligent Query Processing (IQP) features, and query optimizer behavior changes. This guide provides a systematic approach to diagnose and resolve these issues.

🔍 Part 1: Understanding Root Causes
What Changes Between CL 130 and CL 160
text

┌─────────────────────────────────────────────────────────────────────────────┐
│                    COMPATIBILITY LEVEL IMPACT MATRIX                       │
├─────────────────────────┬───────────────────────────────────────────────────┤
│ Component               │ Impact at CL 160                                  │
├─────────────────────────┼───────────────────────────────────────────────────┤
│ Cardinality Estimator   │ CE 160 with enhanced correlation detection        │
│ Query Store             │ Enhanced features, different plan forcing         │
│ Scalar UDF Inlining     │ ENABLED - can cause plan changes                 │
│ Batch Mode on Rowstore  │ ENABLED - different memory grants                │
│ Memory Grant Feedback   │ ENABLED - row mode feedback active               │
│ DOP Feedback            │ ENABLED - automatic DOP adjustments              │
│ CE Feedback             │ ENABLED - automatic CE adjustments               │
│ Approximate Count Dist  │ New behavior for COUNT(DISTINCT)                 │
│ Parameter Sensitive     │ New PSPO behavior                                │
│ Plan Sensitivity        │ Optimizer enhancements                          │
│ Index Matching          │ Enhanced index matching logic                    │
└─────────────────────────┴───────────────────────────────────────────────────┘
Common Regression Patterns
sql

-- Pattern 1: Ascending Key Problem (Most Common)
-- Statistics show stale histogram, new CE handles differently
SELECT * FROM Orders 
WHERE OrderDate > '2024-01-01'  -- Affects estimates differently in CE 160

-- Pattern 2: Multi-Predicate Correlation
-- CE 160 detects correlations differently
SELECT * FROM Orders 
WHERE Status = 'Active' AND Region = 'North' AND Amount > 1000

-- Pattern 3: Variable Injection Before Filter
-- Different estimation for filtered indexes
DECLARE @Status VARCHAR(20) = 'Active'
SELECT * FROM Orders WHERE Status = @Status

-- Pattern 4: UDF Inlining Side Effects
-- Scalar UDFs get inlined, changing plan shape
SELECT dbo.CalculateDiscount(Amount) FROM Orders

-- Pattern 5: Batch Mode Memory Grants
-- Different memory allocation for batch mode operations
SELECT CustomerID, SUM(Amount) FROM Orders GROUP BY CustomerID
📊 Part 2: Diagnostic Scripts
Script 2.1: Initialize Query Store for Analysis
sql

-- Run on BOTH servers (or before/after CL change)
USE [YourDatabase];
GO

-- Configure Query Store for detailed analysis
ALTER DATABASE [YourDatabase] SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 60),
    DATA_FLUSH_INTERVAL_SECONDS = 60,
    INTERVAL_LENGTH_MINUTES = 10,
    MAX_STORAGE_SIZE_MB = 1000,
    QUERY_CAPTURE_MODE = ALL  -- Temporary for troubleshooting
);
GO

-- Enable additional Query Store options
ALTER DATABASE [YourDatabase] SET QUERY_STORE = ON (
    WAIT_STATS_CAPTURE_MODE = ON
);
GO

-- Set custom capture policy (SQL 2022)
ALTER DATABASE [YourDatabase]
SET QUERY_STORE (QUERY_CAPTURE_POLICY = (
    EXECUTION_COUNT = 1,
    TOTAL_COMPILE_CPU_TIME_MS = 0,
    TOTAL_EXECUTION_CPU_TIME_MS = 0,
    STALE_AGE_DAYS = 0,
    MIN_QUERY_PLANS_COUNT = 0
));
GO
Script 2.2: Identify Regressed Queries
sql

-- Find queries that degraded after compatibility level change
-- This compares recent performance (CL 160) with baseline (CL 130)
USE [YourDatabase];
GO

WITH BaselineMetrics AS (
    -- Queries captured before CL change (adjust date range)
    SELECT 
        q.query_id,
        q.query_text_id,
        qt.query_sql_text,
        AVG(rs.avg_duration) AS baseline_avg_duration,
        AVG(rs.avg_cpu_time) AS baseline_avg_cpu,
        AVG(rs.avg_logical_io_reads) AS baseline_avg_io,
        COUNT(DISTINCT rs.plan_id) AS baseline_plan_count
    FROM sys.query_store_query q
    INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
    INNER JOIN sys.query_store_runtime_stats rs ON q.query_id = rs.query_id
    INNER JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time >= '2024-01-01 00:00:00'  -- Before CL change
      AND rsi.end_time <= '2024-01-15 23:59:59'
    GROUP BY q.query_id, q.query_text_id, qt.query_sql_text
),
CurrentMetrics AS (
    -- Queries captured after CL change
    SELECT 
        q.query_id,
        AVG(rs.avg_duration) AS current_avg_duration,
        AVG(rs.avg_cpu_time) AS current_avg_cpu,
        AVG(rs.avg_logical_io_reads) AS current_avg_io,
        COUNT(DISTINCT rs.plan_id) AS current_plan_count
    FROM sys.query_store_query q
    INNER JOIN sys.query_store_runtime_stats rs ON q.query_id = rs.query_id
    INNER JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time >= '2024-01-16 00:00:00'  -- After CL change
    GROUP BY q.query_id
)
SELECT 
    b.query_id,
    b.query_sql_text,
    b.baseline_avg_duration AS baseline_duration_ms,
    c.current_avg_duration AS current_duration_ms,
    CAST((c.current_avg_duration - b.baseline_avg_duration) * 100.0 / NULLIF(b.baseline_avg_duration, 0) AS DECIMAL(10,2)) AS duration_change_pct,
    b.baseline_avg_cpu AS baseline_cpu_ms,
    c.current_avg_cpu AS current_cpu_ms,
    CAST((c.current_avg_cpu - b.baseline_avg_cpu) * 100.0 / NULLIF(b.baseline_avg_cpu, 0) AS DECIMAL(10,2)) AS cpu_change_pct,
    b.baseline_avg_io AS baseline_logical_reads,
    c.current_avg_io AS current_logical_reads,
    CAST((c.current_avg_io - b.baseline_avg_io) * 100.0 / NULLIF(b.baseline_avg_io, 0) AS DECIMAL(10,2)) AS io_change_pct,
    b.baseline_plan_count AS baseline_plans,
    c.current_plan_count AS current_plans,
    CASE 
        WHEN c.current_plan_count > b.baseline_plan_count THEN 'Plan Regression Possible'
        WHEN c.current_plan_count < b.baseline_plan_count THEN 'Plan Consolidation'
        ELSE 'Same Plan Count'
    END AS plan_analysis
FROM BaselineMetrics b
INNER JOIN CurrentMetrics c ON b.query_id = c.query_id
WHERE (c.current_avg_duration > b.baseline_avg_duration * 1.5  -- 50% slower
    OR c.current_avg_cpu > b.baseline_avg_cpu * 1.5
    OR c.current_avg_io > b.baseline_avg_io * 1.5)
ORDER BY duration_change_pct DESC;
GO
Script 2.3: Compare Execution Plans Side by Side
sql

-- Get plan comparison details for specific query
DECLARE @QueryID INT = 42;  -- Replace with actual query_id from previous script

-- Show all plans for the query with their performance
SELECT 
    p.plan_id,
    p.query_plan_hash,
    CAST(p.query_plan AS XML) AS query_plan_xml,
    rs.count_executions,
    rs.avg_duration,
    rs.avg_cpu_time,
    rs.avg_logical_io_reads,
    rs.avg_physical_io_reads,
    rs.avg_logical_io_writes,
    rs.avg_rowcount,
    rs.avg_memory_grant_kb,
    rs.avg_max_memory_grant_kb,
    p.last_execution_time,
    p.is_forced_plan,
    p.force_failure_count,
    p.last_force_failure_reason_desc
FROM sys.query_store_plan p
LEFT JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE p.query_id = @QueryID
ORDER BY rs.avg_duration DESC;
GO

-- Extract plan differences
SELECT 
    p.plan_id,
    p.query_plan_hash,
    -- Extract estimated rows from plan
    qry.nodes('//RelOp') AS rel(n),
    rel.n.value('@LogicalOp', 'nvarchar(128)') AS logical_operator,
    rel.n.value('@PhysicalOp', 'nvarchar(128)') AS physical_operator,
    rel.n.value('@EstimateRows', 'decimal(20,2)') AS estimated_rows,
    rel.n.value('@EstimatedTotalSubtreeCost', 'decimal(20,6)') AS subtree_cost,
    rel.n.value('@Table', 'nvarchar(256)') AS table_name
FROM sys.query_store_plan p
CROSS APPLY (SELECT CAST(p.query_plan AS XML)) AS x(qry)
CROSS APPLY x.qry.nodes('//RelOp') AS rel(n)
WHERE p.query_id = @QueryID
ORDER BY p.plan_id, subtree_cost DESC;
GO
Script 2.4: Identify CE-Related Regressions
sql

-- Find queries where CE version change likely caused regression
USE [YourDatabase];
GO

SELECT 
    q.query_id,
    SUBSTRING(qt.query_sql_text, 1, 200) AS query_start,
    p.plan_id,
    p.query_plan_hash,
    -- Check if plan uses legacy CE hints
    CASE WHEN qp.query_plan LIKE '%LegacyCardinalityEstimation="1"%' THEN 'Legacy CE Forced'
         WHEN qp.query_plan LIKE '%CardinalityEstimationModel="70"%' OR
              qp.query_plan LIKE '%CardinalityEstimationModel="80"%' OR
              qp.query_plan LIKE '%CardinalityEstimationModel="100"%' OR
              qp.query_plan LIKE '%CardinalityEstimationModel="120"%' OR
              qp.query_plan LIKE '%CardinalityEstimationModel="130"%' THEN 'Explicit CE Version'
         ELSE 'Using CL Default CE (160)' 
    END AS ce_version_used,
    -- Check for UDF inlining
    CASE WHEN qp.query_plan LIKE '%IsInlineable="1"%' AND qp.query_plan LIKE '%IsInlined="1"%' THEN 'UDF Inlined'
         WHEN qp.query_plan LIKE '%IsInlineable="1"%' AND qp.query_plan LIKE '%IsInlined="0"%' THEN 'UDF NOT Inlined'
         ELSE 'No UDF'
    END AS udf_inlining_status,
    -- Check for batch mode
    CASE WHEN qp.query_plan LIKE '%BatchMode="true"%' THEN 'Batch Mode'
         ELSE 'Row Mode'
    END AS execution_mode,
    rs.avg_duration,
    rs.avg_cpu_time,
    rs.avg_logical_io_reads
FROM sys.query_store_query q
INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
CROSS APPLY (SELECT CAST(p.query_plan AS XML) AS query_plan) qp
WHERE q.query_id IN (
    -- Get top 50 regressed queries from Script 2.2
    SELECT TOP 50 query_id 
    FROM sys.query_store_runtime_stats rs
    INNER JOIN sys.query_store_plan p ON rs.plan_id = p.plan_id
    ORDER BY rs.avg_duration DESC
)
ORDER BY rs.avg_duration DESC;
GO
Script 2.5: Analyze Plan Forcing Candidates
sql

-- Identify queries that are good candidates for plan forcing
USE [YourDatabase];
GO

WITH QueryPerformance AS (
    SELECT 
        q.query_id,
        qt.query_sql_text,
        p.plan_id,
        p.query_plan_hash,
        p.is_forced_plan,
        rs.avg_duration,
        rs.avg_cpu_time,
        rs.avg_logical_io_reads,
        rs.count_executions,
        ROW_NUMBER() OVER (PARTITION BY q.query_id ORDER BY rs.avg_duration ASC) AS best_plan_rank,
        ROW_NUMBER() OVER (PARTITION BY q.query_id ORDER BY rs.avg_duration DESC) AS worst_plan_rank
    FROM sys.query_store_query q
    INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
    INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
)
SELECT 
    qp.query_id,
    SUBSTRING(qp.query_sql_text, 1, 100) AS query_start,
    best.plan_id AS best_plan_id,
    best.query_plan_hash AS best_plan_hash,
    best.avg_duration AS best_duration_ms,
    worst.plan_id AS worst_plan_id,
    worst.query_plan_hash AS worst_plan_hash,
    worst.avg_duration AS worst_duration_ms,
    CAST((worst.avg_duration - best.avg_duration) * 100.0 / NULLIF(best.avg_duration, 0) AS DECIMAL(10,2)) AS performance_variance_pct,
    CASE 
        WHEN qp.is_forced_plan = 0 
             AND worst.avg_duration > best.avg_duration * 2  -- More than 2x slower
             AND best.count_executions > 10  -- Has sufficient execution history
        THEN 'GOOD CANDIDATE FOR FORCING'
        WHEN qp.is_forced_plan = 1 THEN 'ALREADY FORCED'
        ELSE 'REVIEW NEEDED'
    END AS forcing_recommendation
FROM (
    SELECT DISTINCT query_id, query_sql_text, is_forced_plan
    FROM QueryPerformance
) qp
LEFT JOIN QueryPerformance best ON qp.query_id = best.query_id AND best.best_plan_rank = 1
LEFT JOIN QueryPerformance worst ON qp.query_id = worst.query_id AND worst.worst_plan_rank = 1
WHERE worst.avg_duration > best.avg_duration * 1.5
ORDER BY performance_variance_pct DESC;
GO
Script 2.6: Check for Wait Statistics Changes
sql

-- Compare wait statistics before and after CL change
USE [YourDatabase];
GO

WITH WaitStatsBefore AS (
    SELECT 
        wait_category,
        SUM(total_query_wait_time_ms) AS total_wait_before,
        SUM(total_query_wait_time_ms) * 1.0 / NULLIF(SUM(count_executions), 0) AS avg_wait_before
    FROM sys.query_store_wait_stats ws
    INNER JOIN sys.query_store_runtime_stats_interval rsi 
        ON ws.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time >= '2024-01-01'  -- Before CL change
      AND rsi.end_time <= '2024-01-15'
    GROUP BY wait_category
),
WaitStatsAfter AS (
    SELECT 
        wait_category,
        SUM(total_query_wait_time_ms) AS total_wait_after,
        SUM(total_query_wait_time_ms) * 1.0 / NULLIF(SUM(count_executions), 0) AS avg_wait_after
    FROM sys.query_store_wait_stats ws
    INNER JOIN sys.query_store_runtime_stats_interval rsi 
        ON ws.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time >= '2024-01-16'  -- After CL change
      AND rsi.end_time <= '2024-01-31'
    GROUP BY wait_category
)
SELECT 
    COALESCE(b.wait_category, a.wait_category) AS wait_category,
    b.total_wait_before,
    a.total_wait_after,
    a.total_wait_after - b.total_wait_before AS wait_increase_ms,
    CAST((a.total_wait_after - b.total_wait_before) * 100.0 / NULLIF(b.total_wait_before, 0) AS DECIMAL(10,2)) AS wait_change_pct,
    b.avg_wait_before AS avg_wait_before_per_exec,
    a.avg_wait_after AS avg_wait_after_per_exec
FROM WaitStatsAfter a
FULL OUTER JOIN WaitStatsBefore b ON a.wait_category = b.wait_category
WHERE a.total_wait_after > b.total_wait_before * 1.5  -- 50% increase
ORDER BY wait_increase_ms DESC;
GO
Script 2.7: Memory Grant Analysis
sql

-- Find queries with significant memory grant changes
-- Memory grant changes are common with CL 160 due to batch mode and CE changes
USE [YourDatabase];
GO

SELECT 
    q.query_id,
    SUBSTRING(qt.query_sql_text, 1, 150) AS query_start,
    p.plan_id,
    rs.avg_memory_grant_kb,
    rs.avg_used_memory_grant_kb,
    rs.max_used_memory_grant_kb,
    CAST(rs.avg_used_memory_grant_kb * 100.0 / NULLIF(rs.avg_memory_grant_kb, 0) AS DECIMAL(10,2)) AS memory_utilization_pct,
    rs.avg_spills,
    rs.max_spills,
    rs.avg_duration,
    -- Check for memory grant feedback activity
    CASE WHEN qp.query_plan LIKE '%MemoryGrantFeedback="1"%' THEN 'MGF Active'
         ELSE 'MGF Not Active'
    END AS memory_grant_feedback_status
FROM sys.query_store_query q
INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
CROSS APPLY (SELECT CAST(p.query_plan AS XML) AS query_plan) qp
WHERE (rs.avg_spills > 0  -- Spills occurring
    OR rs.avg_memory_grant_kb > 100 * 1024  -- Large grants (>100MB)
    OR rs.avg_used_memory_grant_kb < rs.avg_memory_grant_kb * 0.3)  -- Under-utilization
ORDER BY rs.avg_spills DESC, rs.avg_memory_grant_kb DESC;
GO
⚙️ Part 3: Configuration Solutions
Solution 3.1: Database-Scoped Legacy Cardinality Estimator
sql

-- Option A: Enable Legacy CE at Database Level (Quickest Fix)
USE [YourDatabase];
GO

-- This forces CE 130 behavior even at CL 160
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;
GO

-- Verify the setting
SELECT 
    name AS database_name,
    compatibility_level,
    is_legacy_cardinality_estimation_enabled
FROM sys.databases d
INNER JOIN sys.database_scoped_configurations c 
    ON d.database_id = c.database_id
WHERE d.name = DB_NAME()
  AND c.name = 'LEGACY_CARDINALITY_ESTIMATION';
GO

/*
PROS:
- Immediate fix for all CE-related regressions
- No code changes required
- Can be toggled easily

CONS:
- Disables all CE 140/150/160 improvements
- May prevent other IQP features from working optimally
- Not a long-term solution
*/
Solution 3.2: Granular Database Scoped Configurations
sql

-- Apply specific configurations instead of blanket legacy CE
USE [YourDatabase];
GO

-- 1. Disable only UDF inlining (common regression cause)
ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = OFF;
GO

-- 2. Disable batch mode on rowstore (memory grant issues)
ALTER DATABASE SCOPED CONFIGURATION SET BATCH_MODE_ON_ROWSTORE = OFF;
GO

-- 3. Keep parameterization as is
-- ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = OFF;  -- Use with caution

-- 4. Disable row mode memory grant feedback if causing issues
ALTER DATABASE SCOPED CONFIGURATION SET ROW_MODE_MEMORY_GRANT_FEEDBACK = OFF;
GO

-- 5. Disable DOP feedback if causing issues
ALTER DATABASE SCOPED CONFIGURATION SET DOP_FEEDBACK = OFF;
GO

-- 6. Disable CE feedback if causing issues
ALTER DATABASE SCOPED CONFIGURATION SET CE_FEEDBACK = OFF;
GO

-- View all database scoped configurations
SELECT 
    configuration_id,
    name,
    value,
    value_for_secondary,
    description
FROM sys.database_scoped_configurations
ORDER BY name;
GO
Solution 3.3: Query-Level Hints (Most Granular Control)
sql

-- Use USE HINT to control behavior per-query

-- Example 1: Force Legacy CE for specific query
SELECT * 
FROM Orders o
INNER JOIN OrderDetails od ON o.OrderID = od.OrderID
WHERE o.OrderDate >= '2024-01-01'
OPTION (USE HINT('ENABLE_LEGACY_CARDINALITY_ESTIMATION'));
GO

-- Example 2: Disable UDF inlining for specific query
SELECT 
    o.OrderID,
    dbo.CalculateTotal(o.OrderID) AS OrderTotal  -- UDF
FROM Orders o
WHERE o.Status = 'Active'
OPTION (USE HINT('DISABLE_TSQL_SCALAR_UDF_INLINING'));
GO

-- Example 3: Disable batch mode for specific query
SELECT 
    CustomerID, 
    SUM(Amount) AS TotalAmount
FROM Orders
GROUP BY CustomerID
OPTION (USE HINT('DISABLE_BATCH_MODE_ON_ROWSTORE'));
GO

-- Example 4: Disable parameter sniffing optimization
SELECT * 
FROM Orders 
WHERE CustomerID = @CustomerID
OPTION (USE HINT('DISABLE_PARAMETER_SNIFFING'));
GO

-- Example 5: Force specific CE version
SELECT * 
FROM Orders 
WHERE Status = 'Active'
OPTION (USE HINT('QUERY_OPTIMIZER_COMPATIBILITY_LEVEL_130'));
GO

-- Example 6: Multiple hints combined
SELECT * 
FROM Orders o
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
WHERE o.Status = 'Active' AND c.Region = 'North'
OPTION (
    USE HINT('ENABLE_LEGACY_CARDINALITY_ESTIMATION'),
    USE HINT('DISABLE_BATCH_MODE_ON_ROWSTORE'),
    MAXDOP 4
);
GO
Solution 3.4: Query Store Plan Forcing
sql

-- Force a better performing plan for regressed queries
USE [YourDatabase];
GO

-- Step 1: Identify the best plan_id for a query (from Script 2.5)
-- Let's say query_id = 42, best_plan_id = 7

-- Step 2: Force the plan
EXEC sp_query_store_force_plan 
    @query_id = 42, 
    @plan_id = 7;
GO

-- Step 3: Verify the plan is forced
SELECT 
    q.query_id,
    p.plan_id,
    p.is_forced_plan,
    p.force_failure_count,
    p.last_force_failure_reason_desc,
    p.last_execution_time
FROM sys.query_store_query q
INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
WHERE q.query_id = 42;
GO

-- Step 4: Unforce if needed
-- EXEC sp_query_store_unforce_plan @query_id = 42, @plan_id = 7;

-- Batch force multiple good plans
DECLARE @ForcingTable TABLE (
    QueryID INT,
    PlanID INT
);

-- Populate with your identified good plans
INSERT INTO @ForcingTable (QueryID, PlanID) VALUES
    (42, 7),
    (55, 12),
    (78, 15),
    (93, 20);

-- Force all plans in the table
DECLARE @QID INT, @PID INT;
DECLARE force_cursor CURSOR FOR 
    SELECT QueryID, PlanID FROM @ForcingTable;

OPEN force_cursor;
FETCH NEXT FROM force_cursor INTO @QID, @PID;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC sp_query_store_force_plan @query_id = @QID, @plan_id = @PID;
        PRINT CONCAT('Forced Plan ', @PID, ' for Query ', @QID);
    END TRY
    BEGIN CATCH
        PRINT CONCAT('ERROR forcing Plan ', @PID, ' for Query ', @QID, ': ', ERROR_MESSAGE());
    END CATCH
    
    FETCH NEXT FROM force_cursor INTO @QID, @PID;
END

CLOSE force_cursor;
DEALLOCATE force_cursor;
GO
Solution 3.5: Automatic Tuning (SQL 2022 Feature)
sql

-- Enable automatic tuning for automatic plan correction
USE [YourDatabase];
GO

-- Enable automatic tuning
ALTER DATABASE [YourDatabase]
SET AUTOMATIC_TUNING (ON);
GO

-- Configure which features to enable
ALTER DATABASE [YourDatabase]
SET AUTOMATIC_TUNING (
    FORCE_LAST_GOOD_PLAN = ON,
    CREATE_INDEX = OFF,      -- Be cautious with auto index creation
    DROP_INDEX = OFF         -- Be cautious with auto index dropping
);
GO

-- View automatic tuning recommendations
SELECT 
    reason,
    score,
    current_state,
    current_state_desc,
    details,
    script,
    plan_id,
    query_id,
    recommended_action,
    estimated_impact,
    time_generated
FROM sys.dm_db_tuning_recommendations
ORDER BY score DESC;
GO

-- Apply a specific recommendation manually
EXEC sp_execute_sql 
    N'ALTER DATABASE [YourDatabase] SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON)';
GO

-- View automatic tuning history
SELECT 
    dtr.reason,
    dtr.details,
    dtrh.action_name,
    dtrh.state,
    dtrh.state_desc,
    dtrh.execution_time,
    dtrh.success
FROM sys.dm_db_tuning_recommendations dtr
INNER JOIN sys.dm_db_tuning_recommendation_actions dtra 
    ON dtr.name = dtra.recommendation_name
INNER JOIN sys.dm_db_tuning_recommendation_details dtrh 
    ON dtr.name = dtrh.recommendation_name
ORDER BY dtrh.execution_time DESC;
GO
🔧 Part 4: Statistics and Index Optimization
Script 4.1: Comprehensive Statistics Update
sql

-- Update statistics with full scan for critical tables
USE [YourDatabase];
GO

-- Option A: Update all statistics with full scan (for critical migration period)
DECLARE @TableName NVARCHAR(256);
DECLARE @StatsName NVARCHAR(256);
DECLARE @SQL NVARCHAR(MAX);

DECLARE stats_cursor CURSOR FOR
SELECT 
    t.name AS table_name,
    s.name AS stats_name
FROM sys.tables t
INNER JOIN sys.stats s ON t.object_id = s.object_id
WHERE t.is_ms_shipped = 0
ORDER BY t.name, s.name;

OPEN stats_cursor;
FETCH NEXT FROM stats_cursor INTO @TableName, @StatsName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = N'UPDATE STATISTICS [' + @TableName + N'] [' + @StatsName + N'] WITH FULLSCAN';
    
    BEGIN TRY
        EXEC sp_executesql @SQL;
        PRINT CONCAT('Updated: ', @TableName, '.', @StatsName);
    END TRY
    BEGIN CATCH
        PRINT CONCAT('ERROR: ', @TableName, '.', @StatsName, ' - ', ERROR_MESSAGE());
    END CATCH
    
    FETCH NEXT FROM stats_cursor INTO @TableName, @StatsName;
END

CLOSE stats_cursor;
DEALLOCATE stats_cursor;
GO

-- Option B: Targeted update for tables with ascending key issues
-- Identify tables where ascending keys might cause issues
SELECT 
    t.name AS table_name,
    c.name AS column_name,
    s.name AS stats_name,
    sp.last_updated,
    sp.rows,
    sp.rows_sampled,
    CAST(sp.rows_sampled * 100.0 / NULLIF(sp.rows, 0) AS DECIMAL(10,2)) AS sample_pct,
    sp.modification_counter
FROM sys.tables t
INNER JOIN sys.columns c ON t.object_id = c.object_id
INNER JOIN sys.stats_columns sc ON c.object_id = sc.object_id AND c.column_id = sc.column_id
INNER JOIN sys.stats s ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE t.is_ms_shipped = 0
  AND c.is_identity = 1  -- Identity columns (ascending keys)
  AND sp.modification_counter > sp.rows * 0.1  -- >10% modified
ORDER BY sp.modification_counter DESC;
GO
Script 4.2: Identify Missing Indexes for Regressed Queries
sql

-- Get missing index recommendations from Query Store
USE [YourDatabase];
GO

SELECT 
    q.query_id,
    SUBSTRING(qt.query_sql_text, 1, 100) AS query_start,
    migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    migs.avg_total_user_cost,
    migs.avg_user_impact,
    migs.user_seeks,
    migs.user_scans,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    mid.statement AS table_name,
    'CREATE INDEX [IX_' + REPLACE(REPLACE(REPLACE(
        COALESCE(mid.equality_columns, '') + 
        CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN '_' ELSE '' END +
        COALESCE(mid.inequality_columns, ''), ', ', '_'), ']', ''), '[', '') + 
        '] ON ' + mid.statement + ' (' + 
        COALESCE(mid.equality_columns, '') + 
        CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ', ' ELSE '' END +
        COALESCE(mid.inequality_columns, '') + ')' +
        CASE WHEN mid.included_columns IS NOT NULL THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END
        AS create_index_statement
FROM sys.dm_db_missing_index_details mid
INNER JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle = mig.index_handle
INNER JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
WHERE mid.database_id = DB_ID()
ORDER BY improvement_measure DESC;
GO
Script 4.3: Check for Filtered Index Issues
sql

-- Filtered indexes may behave differently with new CE
SELECT 
    t.name AS table_name,
    i.name AS index_name,
    i.filter_definition,
    s.name AS stats_name,
    sp.last_updated,
    sp.rows,
    sp.rows_sampled,
    sp.modification_counter,
    CASE 
        WHEN sp.modification_counter > sp.rows * 0.2 THEN 'HIGH - Update Recommended'
        WHEN sp.modification_counter > sp.rows * 0.1 THEN 'MEDIUM - Monitor'
        ELSE 'LOW'
    END AS staleness_level
FROM sys.indexes i
INNER JOIN sys.tables t ON i.object_id = t.object_id
INNER JOIN sys.stats s ON i.object_id = s.object_id AND i.index_id = s.stats_id
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE i.has_filter = 1
ORDER BY sp.modification_counter DESC;
GO

-- Update filtered index statistics specifically
UPDATE STATISTICS [YourTable] [IX_YourFilteredIndex] WITH FULLSCAN;
GO
💻 Part 5: Query Rewrite Recommendations
Pattern 5.1: Fix Ascending Key Problem
sql

-- PROBLEM: Ascending key causes underestimation
-- Bad: Direct parameter comparison
DECLARE @CutoffDate DATE = '2024-01-01';
SELECT * 
FROM Orders 
WHERE OrderDate >= @CutoffDate;

-- SOLUTION 1: Use OPTIMIZE FOR UNKNOWN (makes CE use average density)
SELECT * 
FROM Orders 
WHERE OrderDate >= @CutoffDate
OPTION (OPTIMIZE FOR UNKNOWN);
GO

-- SOLUTION 2: Use RECOMPILE (generates fresh plan with actual values)
SELECT * 
FROM Orders 
WHERE OrderDate >= @CutoffDate
OPTION (RECOMPILE);
GO

-- SOLUTION 3: Use dynamic SQL with parameter embedding
DECLARE @SQL NVARCHAR(MAX);
DECLARE @CutoffDate DATE = '2024-01-01';

SET @SQL = N'SELECT * FROM Orders WHERE OrderDate >= ''' + CAST(@CutoffDate AS VARCHAR(10)) + '''';
EXEC sp_executesql @SQL;
GO

-- SOLUTION 4: Use local variable trick (works in some cases)
DECLARE @CutoffDate DATE = '2024-01-01';
SELECT * 
FROM Orders 
WHERE OrderDate >= DATEADD(DAY, 0, @CutoffDate);  -- Wrapping in function
GO

-- SOLUTION 5: Use query hint for legacy CE
SELECT * 
FROM Orders 
WHERE OrderDate >= @CutoffDate
OPTION (USE HINT('ENABLE_LEGACY_CARDINALITY_ESTIMATION'));
GO
Pattern 5.2: Fix Multi-Predicate Correlation Issues
sql

-- PROBLEM: CE 160 may over/underestimate correlated predicates
-- Bad: Multiple correlated predicates
SELECT * 
FROM Orders
WHERE Status = 'Active' 
  AND Region = 'North' 
  AND Amount > 1000
  AND CustomerType = 'Premium';

-- SOLUTION 1: Add multi-column statistics
CREATE STATISTICS [Stats_Orders_Status_Region_Amount]
ON Orders (Status, Region, Amount)
WITH FULLSCAN;
GO

-- SOLUTION 2: Use temporary table to break correlation estimation
SELECT OrderID
INTO #FilteredOrders
FROM Orders
WHERE Status = 'Active';

SELECT o.* 
FROM Orders o
INNER JOIN #FilteredOrders f ON o.OrderID = f.OrderID
WHERE o.Region = 'North' 
  AND o.Amount > 1000
  AND o.CustomerType = 'Premium';

DROP TABLE #FilteredOrders;
GO

-- SOLUTION 3: Use materialized CTE
WITH ActiveOrders AS (
    SELECT * 
    FROM Orders 
    WHERE Status = 'Active'
)
SELECT * 
FROM ActiveOrders
WHERE Region = 'North' 
  AND Amount > 1000
  AND CustomerType = 'Premium';
GO

-- SOLUTION 4: Use legacy CE hint if statistics don't help
SELECT * 
FROM Orders
WHERE Status = 'Active' 
  AND Region = 'North' 
  AND Amount > 1000
  AND CustomerType = 'Premium'
OPTION (USE HINT('ENABLE_LEGACY_CARDINALITY_ESTIMATION'));
GO
Pattern 5.3: Fix UDF Performance Issues
sql

-- PROBLEM: UDF inlining may cause unexpected plan changes
-- Original scalar UDF
CREATE FUNCTION dbo.CalculateDiscount(@Amount DECIMAL(18,2), @CustomerLevel VARCHAR(20))
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @Discount DECIMAL(18,2);
    
    IF @CustomerLevel = 'Premium'
        SET @Discount = @Amount * 0.20;
    ELSE IF @CustomerLevel = 'Gold'
        SET @Discount = @Amount * 0.15;
    ELSE IF @CustomerLevel = 'Silver'
        SET @Discount = @Amount * 0.10;
    ELSE
        SET @Discount = @Amount * 0.05;
        
    RETURN @Discount;
END;
GO

-- Original query with UDF
SELECT 
    OrderID,
    Amount,
    dbo.CalculateDiscount(Amount, CustomerLevel) AS Discount,
    Amount - dbo.CalculateDiscount(Amount, CustomerLevel) AS FinalAmount
FROM Orders
WHERE Status = 'Active';

-- SOLUTION 1: Inline the logic directly
SELECT 
    OrderID,
    Amount,
    CASE CustomerLevel
        WHEN 'Premium' THEN Amount * 0.20
        WHEN 'Gold' THEN Amount * 0.15
        WHEN 'Silver' THEN Amount * 0.10
        ELSE Amount * 0.05
    END AS Discount,
    Amount - CASE CustomerLevel
        WHEN 'Premium' THEN Amount * 0.20
        WHEN 'Gold' THEN Amount * 0.15
        WHEN 'Silver' THEN Amount * 0.10
        ELSE Amount * 0.05
    END AS FinalAmount
FROM Orders
WHERE Status = 'Active';
GO

-- SOLUTION 2: Use CROSS APPLY to compute once
SELECT 
    o.OrderID,
    o.Amount,
    d.Discount,
    o.Amount - d.Discount AS FinalAmount
FROM Orders o
CROSS APPLY (
    SELECT CASE o.CustomerLevel
        WHEN 'Premium' THEN o.Amount * 0.20
        WHEN 'Gold' THEN o.Amount * 0.15
        WHEN 'Silver' THEN o.Amount * 0.10
        ELSE o.Amount * 0.05
    END AS Discount
) d
WHERE o.Status = 'Active';
GO

-- SOLUTION 3: Disable inlining for specific query
SELECT 
    OrderID,
    Amount,
    dbo.CalculateDiscount(Amount, CustomerLevel) AS Discount
FROM Orders
WHERE Status = 'Active'
OPTION (USE HINT('DISABLE_TSQL_SCALAR_UDF_INLINING'));
GO

-- SOLUTION 4: Mark UDF as not inlineable (if you want to keep UDF but prevent inlining)
ALTER FUNCTION dbo.CalculateDiscount(@Amount DECIMAL(18,2), @CustomerLevel VARCHAR(20))
RETURNS DECIMAL(18,2)
WITH INLINE = OFF  -- Explicitly disable inlining
AS
BEGIN
    -- Same logic
    DECLARE @Discount DECIMAL(18,2);
    
    IF @CustomerLevel = 'Premium'
        SET @Discount = @Amount * 0.20;
    ELSE IF @CustomerLevel = 'Gold'
        SET @Discount = @Amount * 0.15;
    ELSE IF @CustomerLevel = 'Silver'
Pattern 5.4: Fix Table Variable Issues
sql

-- PROBLEM: Table variables have different cardinality estimation in CE 160
-- Bad: Table variable with no hint
DECLARE @OrderIDs TABLE (OrderID INT PRIMARY KEY);

INSERT INTO @OrderIDs (OrderID)
SELECT TOP 1000 OrderID FROM Orders WHERE Status = 'Active';

SELECT o.*
FROM Orders o
INNER JOIN @OrderIDs t ON o.OrderID = t.OrderID;

-- SOLUTION 1: Use RECOMPILE (allows accurate estimation)
DECLARE @OrderIDs TABLE (OrderID INT PRIMARY KEY);

INSERT INTO @OrderIDs (OrderID)
SELECT TOP 1000 OrderID FROM Orders WHERE Status = 'Active';

SELECT o.*
FROM Orders o
INNER JOIN @OrderIDs t ON o.OrderID = t.OrderID
OPTION (RECOMPILE);
GO

-- SOLUTION 2: Use temp table instead (better statistics)
CREATE TABLE #OrderIDs (OrderID INT PRIMARY KEY);

INSERT INTO #OrderIDs (OrderID)
SELECT TOP 1000 OrderID FROM Orders WHERE Status = 'Active';

-- Create statistics
UPDATE STATISTICS #OrderIDs WITH FULLSCAN;

SELECT o.*
FROM Orders o
INNER JOIN #OrderIDs t ON o.OrderID = t.OrderID;

DROP TABLE #OrderIDs;
GO

-- SOLUTION 3: Use table type with default cardinality hint
CREATE TYPE OrderIDTableType AS TABLE (OrderID INT PRIMARY KEY);
GO

DECLARE @OrderIDs AS OrderIDTableType;

INSERT INTO @OrderIDs (OrderID)
SELECT TOP 1000 OrderID FROM Orders WHERE Status = 'Active';

-- Use with sp_executesql for better estimation
DECLARE @SQL NVARCHAR(MAX) = N'
SELECT o.*
FROM Orders o
INNER JOIN @OrderIDs t ON o.OrderID = t.OrderID
OPTION (RECOMPILE);';

EXEC sp_executesql @SQL, N'@OrderIDs OrderIDTableType READONLY', @OrderIDs = @OrderIDs;
GO
Pattern 5.5: Fix Optional Parameter Problems
sql

-- PROBLEM: Optional parameters with OR logic causes bad plans
-- Bad: Optional parameter pattern
CREATE PROCEDURE GetOrders
    @CustomerID INT = NULL,
    @Status VARCHAR(20) = NULL,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SELECT * 
    FROM Orders
    WHERE (@CustomerID IS NULL OR CustomerID = @CustomerID)
      AND (@Status IS NULL OR Status = @Status)
      AND (@StartDate IS NULL OR OrderDate >= @StartDate)
      AND (@EndDate IS NULL OR OrderDate <= @EndDate);
END;
GO

-- SOLUTION 1: Use dynamic SQL with parameter embedding
CREATE OR ALTER PROCEDURE GetOrders_Dynamic
    @CustomerID INT = NULL,
    @Status VARCHAR(20) = NULL,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM Orders WHERE 1=1';
    DECLARE @Params NVARCHAR(MAX) = N'';
    
    IF @CustomerID IS NOT NULL
    BEGIN
        SET @SQL += N' AND CustomerID = @CustomerID';
        SET @Params += N', @CustomerID INT';
    END
    
    IF @Status IS NOT NULL
    BEGIN
        SET @SQL += N' AND Status = @Status';
        SET @Params += N', @Status VARCHAR(20)';
    END
    
    IF @StartDate IS NOT NULL
    BEGIN
        SET @SQL += N' AND OrderDate >= @StartDate';
        SET @Params += N', @StartDate DATE';
    END
    
    IF @EndDate IS NOT NULL
    BEGIN
        SET @SQL += N' AND OrderDate <= @EndDate';
        SET @Params += N', @EndDate DATE';
    END
    
    SET @Params = STUFF(@Params, 1, 1, '');  -- Remove leading comma
    
    EXEC sp_executesql @SQL, @Params, 
        @CustomerID = @CustomerID, 
        @Status = @Status, 
        @StartDate = @StartDate, 
        @EndDate = @EndDate;
END;
GO

-- SOLUTION 2: Use separate procedures for common combinations
CREATE OR ALTER PROCEDURE GetOrders_ByCustomerAndStatus
    @CustomerID INT,
    @Status VARCHAR(20)
AS
BEGIN
    SELECT * FROM Orders WHERE CustomerID = @CustomerID AND Status = @Status;
END;
GO

CREATE OR ALTER PROCEDURE GetOrders_ByDateRange
    @StartDate DATE,
    @EndDate DATE
AS
BEGIN
    SELECT * FROM Orders WHERE OrderDate BETWEEN @StartDate AND @EndDate;
END;
Pattern 5.6: Fix IN Clause with Variables
sql

-- PROBLEM: IN clause with variable or table-valued parameter
-- Bad: IN clause with variable
DECLARE @StatusList VARCHAR(100) = 'Active,Pending,Processing';

-- This doesn't work - need to split
SELECT * 
FROM Orders 
WHERE Status IN (SELECT value FROM STRING_SPLIT(@StatusList, ','));

-- SOLUTION 1: Use JOIN with string split
DECLARE @StatusList VARCHAR(100) = 'Active,Pending,Processing';

SELECT o.*
FROM Orders o
INNER JOIN STRING_SPLIT(@StatusList, ',') s ON o.Status = s.value
OPTION (RECOMPILE);  -- Important for accurate estimation
GO

-- SOLUTION 2: Use temp table for large lists
DECLARE @StatusList VARCHAR(100) = 'Active,Pending,Processing';

CREATE TABLE #Statuses (Status VARCHAR(20) PRIMARY KEY);

INSERT INTO #Statuses (Status)
SELECT value FROM STRING_SPLIT(@StatusList, ',');

UPDATE STATISTICS #Statuses WITH FULLSCAN;

SELECT o.*
FROM Orders o
INNER JOIN #Statuses s ON o.Status = s.Status;

DROP TABLE #Statuses;
GO

-- SOLUTION 3: Hard-code for known combinations
SELECT * 
FROM Orders 
WHERE Status IN ('Active', 'Pending', 'Processing');
GO
Pattern 5.7: Fix LIKE with Leading Wildcard
sql

-- PROBLEM: Leading wildcard prevents index usage regardless of CL
-- Bad
SELECT * FROM Customers WHERE CustomerName LIKE '%Smith%';

-- SOLUTION 1: Full-Text Search (best for large tables)
-- Requires full-text catalog setup
SELECT * 
FROM Customers 
WHERE CONTAINS(CustomerName, 'Smith');
GO

-- SOLUTION 2: Use REVERSE trick for trailing wildcard only
-- If you need "ends with":
SELECT * FROM Customers WHERE REVERSE(CustomerName) LIKE REVERSE('%Smith');
GO

-- SOLUTION 3: Consider if leading wildcard is really needed
-- Often users mean "contains" but data could be normalized
SELECT * FROM Customers WHERE CustomerName LIKE 'Smith%';  -- Starts with
GO
📈 Part 6: Monitoring and Validation Scripts
Script 6.1: Real-Time Performance Comparison
sql

-- Monitor query performance in real-time after changes
USE [YourDatabase];
GO

-- Create a monitoring table
IF OBJECT_ID('dbo.QueryPerformanceLog') IS NOT NULL
    DROP TABLE dbo.QueryPerformanceLog;

CREATE TABLE dbo.QueryPerformanceLog (
    LogID BIGINT IDENTITY(1,1) PRIMARY KEY,
    LogTime DATETIME2 DEFAULT SYSDATETIME(),
    QueryID INT,
    PlanID INT,
    DurationMs BIGINT,
    CpuMs BIGINT,
    LogicalReads BIGINT,
    PhysicalReads BIGINT,
    Writes BIGINT,
    MemoryGrantKB BIGINT,
    RowCount BIGINT,
    Spills BIGINT
);

-- Create a job to capture snapshots (run every 5 minutes)
INSERT INTO dbo.QueryPerformanceLog (QueryID, PlanID, DurationMs, CpuMs, LogicalReads, PhysicalReads, Writes, MemoryGrantKB, RowCount, Spills)
SELECT 
    q.query_id,
    p.plan_id,
    rs.avg_duration,
    rs.avg_cpu_time,
    rs.avg_logical_io_reads,
    rs.avg_physical_io_reads,
    rs.avg_logical_io_writes,
    rs.avg_memory_grant_kb,
    rs.avg_rowcount,
    rs.avg_spills
FROM sys.query_store_query q
INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
INNER JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.end_time >= DATEADD(MINUTE, -5, SYSDATETIME())
  AND q.query_id IN (
      -- Add your monitored query IDs
      SELECT TOP 20 query_id 
      FROM sys.query_store_runtime_stats rs
      INNER JOIN sys.query_store_plan p ON rs.plan_id = p.plan_id
      GROUP BY query_id
      ORDER BY AVG(avg_duration) DESC
  );
GO

-- Analyze trends
SELECT 
    QueryID,
    PlanID,
    DATEADD(DAY, DATEDIFF(DAY, 0, LogTime), 0) AS LogDate,
    AVG(DurationMs) AS AvgDurationMs,
    AVG(CpuMs) AS AvgCpuMs,
    AVG(LogicalReads) AS AvgLogicalReads,
    MAX(MemoryGrantKB) AS MaxMemoryGrantKB,
    AVG(Spills) AS AvgSpills,
    COUNT(*) AS SampleCount
FROM dbo.QueryPerformanceLog
GROUP BY QueryID, PlanID, DATEADD(DAY, DATEDIFF(DAY, 0, LogTime), 0)
ORDER BY QueryID, LogDate;
GO
Script 6.2: Plan Stability Analysis
sql

-- Check for plan instability (frequent plan changes)
USE [YourDatabase];
GO

WITH PlanChanges AS (
    SELECT 
        q.query_id,
        p.plan_id,
        p.query_plan_hash,
        p.first_execution_time,
        p.last_execution_time,
        LAG(p.plan_id) OVER (PARTITION BY q.query_id ORDER BY p.first_execution_time) AS prev_plan_id,
        rs.avg_duration,
        rs.count_executions
    FROM sys.query_store_query q
    INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
)
SELECT 
    pc.query_id,
    COUNT(DISTINCT pc.plan_id) AS unique_plans,
    SUM(CASE WHEN pc.plan_id <> pc.prev_plan_id THEN 1 ELSE 0 END) AS plan_changes,
    MIN(pc.avg_duration) AS min_duration_ms,
    MAX(pc.avg_duration) AS max_duration_ms,
    CAST((MAX(pc.avg_duration) - MIN(pc.avg_duration)) * 100.0 / NULLIF(MIN(pc.avg_duration), 0) AS DECIMAL(10,2)) AS duration_variance_pct,
    SUM(pc.count_executions) AS total_executions,
    CASE 
        WHEN COUNT(DISTINCT pc.plan_id) > 3 THEN 'HIGH INSTABILITY'
        WHEN COUNT(DISTINCT pc.plan_id) > 1 THEN 'SOME INSTABILITY'
        ELSE 'STABLE'
    END AS stability_status
FROM PlanChanges pc
GROUP BY pc.query_id
HAVING COUNT(DISTINCT pc.plan_id) > 1
ORDER BY plan_changes DESC;
GO
Script 6.3: Comprehensive Health Check After CL Change
sql

-- Complete health check script after compatibility level change
USE [YourDatabase];
GO

PRINT '=== DATABASE COMPATIBILITY LEVEL HEALTH CHECK ===';
PRINT '';

-- 1. Current Configuration
PRINT '1. CURRENT CONFIGURATION';
SELECT 
    'Compatibility Level' AS Setting,
    CAST(compatibility_level AS VARCHAR(10)) AS Value,
    CASE compatibility_level
        WHEN 130 THEN 'SQL Server 2016'
        WHEN 140 THEN 'SQL Server 2017'
        WHEN 150 THEN 'SQL Server 2019'
        WHEN 160 THEN 'SQL Server 2022'
    END AS Description
FROM sys.databases WHERE name = DB_NAME()

UNION ALL

SELECT 
    'Legacy CE',
    CAST(value AS VARCHAR(10)),
    CASE CAST(value AS INT) WHEN 1 THEN 'ENABLED (Legacy CE 130)' ELSE 'DISABLED (Using CE 160)' END
FROM sys.database_scoped_configurations WHERE name = 'LEGACY_CARDINALITY_ESTIMATION'

UNION ALL

SELECT 
    'UDF Inlining',
    CAST(value AS VARCHAR(10)),
    CASE CAST(value AS INT) WHEN 1 THEN 'ENABLED' ELSE 'DISABLED' END
FROM sys.database_scoped_configurations WHERE name = 'TSQL_SCALAR_UDF_INLINING'

UNION ALL

SELECT 
    'Batch Mode on Rowstore',
    CAST(value AS VARCHAR(10)),
    CASE CAST(value AS INT) WHEN 1 THEN 'ENABLED' ELSE 'DISABLED' END
FROM sys.database_scoped_configurations WHERE name = 'BATCH_MODE_ON_ROWSTORE';
PRINT '';

-- 2. Query Store Status
PRINT '2. QUERY STORE STATUS';
SELECT 
    actual_state_desc,
    readonly_reason_desc,
    current_storage_size_mb,
    max_storage_size_mb,
    CAST(current_storage_size_mb * 100.0 / max_storage_size_mb AS DECIMAL(10,2)) AS storage_used_pct,
    query_capture_mode_desc
FROM sys.database_query_store_options;
PRINT '';

-- 3. Top 10 Slowest Queries
PRINT '3. TOP 10 SLOWEST QUERIES (Last 24 Hours)';
SELECT TOP 10
    q.query_id,
    SUBSTRING(qt.query_sql_text, 1, 100) AS query_start,
    p.plan_id,
    p.is_forced_plan,
    rs.avg_duration / 1000.0 AS avg_duration_sec,
    rs.avg_cpu_time / 1000.0 AS avg_cpu_sec,
    rs.avg_logical_io_reads,
    rs.count_executions
FROM sys.query_store_query q
INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
INNER JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.end_time >= DATEADD(HOUR, -24, SYSDATETIME())
ORDER BY rs.avg_duration DESC;
PRINT '';

-- 4. Forced Plans Status
PRINT '4. FORCED PLANS STATUS';
SELECT 
    COUNT(*) AS total_forced_plans,
    SUM(CASE WHEN force_failure_count > 0 THEN 1 ELSE 0 END) AS failed_forces,
    SUM(CASE WHEN last_force_failure_reason_desc IS NOT NULL THEN 1 ELSE 0 END) AS plans_with_errors
FROM sys.query_store_plan
🎯 Part 7: Recommended Migration Strategy
Step-by-Step Approach
text

┌─────────────────────────────────────────────────────────────────────────────┐
│                    RECOMMENDED MIGRATION STRATEGY                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  PHASE 1: PREPARATION (Before CL Change)                                    │
│  ══════════════════════════════════════════════                              │
│  □ Enable Query Store with sufficient storage                               │
│  □ Run workload for 1-2 weeks to establish baseline                         │
│  □ Update ALL statistics with FULLSCAN                                      │
│  □ Document top 50 queries by resource usage                                │
│  □ Capture baseline execution plans                                         │
│                                                                             │
│  PHASE 2: INITIAL CHANGE (Controlled)                                       │
│  ══════════════════════════════════════════════                              │
│  □ Change CL to 160 during maintenance window                              │
│  □ IMMEDIATELY enable: LEGACY_CARDINALITY_ESTIMATION = ON                  │
│  □ Verify application functionality                                         │
│  □ Run basic smoke tests                                                    │
│                                                                             │
│  PHASE 3: GRADUAL OPTIMIZATION (1-2 Weeks)                                 │
│  ══════════════════════════════════════════════                              │
│  □ Analyze Query Store for top resource consumers                           │
│  □ Identify queries that might benefit from new CE                          │
│  □ Test individual queries with USE HINT to disable legacy CE               │
│  □ Force good plans where needed                                           │
│  □ Address UDF inlining opportunities                                      │
│                                                                             │
│  PHASE 4: SELECTIVE MIGRATION                                               │
│  ══════════════════════════════════════════════                              │
│  □ For tested/beneficial queries: Remove legacy CE hint                    │
│  □ Monitor each change for 24-48 hours                                     │
│  □ Keep legacy CE for regressed queries                                    │
│  □ Document all changes and results                                        │
│                                                                             │
│  PHASE 5: FULL OPTIMIZATION (Optional)                                     │
│  ══════════════════════════════════════════════                              │
│  □ Consider disabling legacy CE at database level                          │
│  □ Enable IQP features selectively                                         │
│  □ Implement query rewrites for remaining regressions                      │
│  □ Enable automatic tuning for ongoing maintenance                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
Quick Fix Script (For Immediate Relief)
sql

-- RUN THIS IMMEDIATELY AFTER CL CHANGE TO 160 FOR STABILITY
USE [YourDatabase];
GO

-- Step 1: Enable legacy CE at database level
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;
PRINT 'Legacy CE enabled - CE behavior now matches CL 130';
GO

-- Step 2: Disable potentially problematic IQP features initially
ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = OFF;
PRINT 'UDF Inlining disabled - prevents UDF-related plan changes';
GO

-- Step 3: Keep batch mode enabled (usually beneficial)
-- ALTER DATABASE SCOPED CONFIGURATION SET BATCH_MODE_ON_ROWSTORE = OFF;
PRINT 'Batch Mode on Rowstore left ENABLED - usually beneficial';
GO

-- Step 4: Disable feedback features initially (can enable later)
ALTER DATABASE SCOPED CONFIGURATION SET ROW_MODE_MEMORY_GRANT_FEEDBACK = OFF;
PRINT 'Row Mode Memory Grant Feedback disabled initially';
GO

-- Step 5: Configure Query Store for monitoring
ALTER DATABASE [YourDatabase] SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    MAX_STORAGE_SIZE_MB = 2000,
    INTERVAL_LENGTH_MINUTES = 5,
    QUERY_CAPTURE_MODE = AUTO
);
PRINT 'Query Store configured for monitoring';
GO

-- Step 6: Update all statistics
EXEC sp_MSforeachtable 'UPDATE STATISTICS ? WITH FULLSCAN';
PRINT 'All statistics updated with FULLSCAN';
GO

PRINT '';
PRINT '=== INITIAL STABILIZATION COMPLETE ===';
PRINT 'Database is now running CL 160 with CL 130 CE behavior.';
PRINT 'Monitor Query Store and gradually migrate queries to new CE.';
GO
Verification Script After Changes
sql

-- Run this to verify your changes took effect
USE [YourDatabase];
GO

SELECT 
    'Database' AS [Setting],
    DB_NAME() AS [Value],
    '' AS [Notes]
UNION ALL
SELECT 
    'Compatibility Level',
    CAST(compatibility_level AS VARCHAR(10)),
    CASE compatibility_level WHEN 160 THEN '✓ SQL 2022' ELSE '✗ Not 160' END
FROM sys.databases WHERE name = DB_NAME()
UNION ALL
SELECT 
    'Legacy CE',
    CAST(value AS VARCHAR(10)),
    CASE CAST(value AS INT) WHEN 1 THEN '✓ ON (CE 130 behavior)' ELSE '✗ OFF (CE 160 behavior)' END
FROM sys.database_scoped_configurations WHERE name = 'LEGACY_CARDINALITY_ESTIMATION'
UNION ALL
SELECT 
    'UDF Inlining',
    CAST(value AS VARCHAR(10)),
    CASE CAST(value AS INT) WHEN 1 THEN '✓ ON' ELSE '✗ OFF' END
FROM sys.database_scoped_configurations WHERE name = 'TSQL_SCALAR_UDF_INLINING'
UNION ALL
SELECT 
    'Batch Mode on Rowstore',
    CAST(value AS VARCHAR(10)),
    CASE CAST(value AS INT) WHEN 1 THEN '✓ ON' ELSE '✗ OFF' END
FROM sys.database_scoped_configurations WHERE name = 'BATCH_MODE_ON_ROWSTORE'
UNION ALL
SELECT 
    'Query Store',
    (SELECT actual_state_desc FROM sys.database_query_store_options),
    CASE WHEN (SELECT actual_state FROM sys.database_query_store_options) = 2 THEN '✓ Read Write' ELSE '✗ Not Read Write' END;
GO
📝 Summary Checklist
Priority
Action
Impact
Effort
🔴 Critical	Enable Legacy CE at DB level	Immediate stabilization	Low
🔴 Critical	Update all statistics with FULLSCAN	Fixes stale data issues	Low
🟠 High	Disable UDF inlining initially	Prevents UDF regressions	Low
🟠 High	Configure Query Store properly	Enables monitoring	Low
🟡 Medium	Force good plans for top queries	Fixes specific regressions	Medium
🟡 Medium	Add multi-column statistics	Improves CE accuracy	Medium
🟢 Low	Rewrite problematic queries	Long-term fix	High
🟢 Low	Gradually migrate to new CE	Gets IQP benefits	High

This guide provides a comprehensive approach to handling the compatibility level migration issue. Start with the Quick Fix Script for immediate relief, then use the diagnostic scripts to identify specific problem queries, and finally apply targeted solutions as needed.





Send a Message




Generated by AI. For reference only.
Tech Blog
Contact us
Terms of Service
and
Privacy Policy
