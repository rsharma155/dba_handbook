/*
================================================================================
01_Before_After_Examples.sql
Purpose : T-SQL rewrite templates for SQL 2016 -> 2022 (compat 160) regressions.
          Each section: ISSUE | WHY AT CL 160 | HOW THE FIX HELPS | BEFORE/AFTER
Note    : Examples use placeholder objects (dbo.Orders, etc.). Adapt to your schema.
          Run sections individually in SSMS; not all blocks execute end-to-end.
================================================================================
*/
USE [YourDB];  -- <<< change
GO

SET NOCOUNT ON;

/*############################################################################
  PATTERN A) OR across columns
  ISSUE     : WHERE Email = @v OR Phone = @v forces broad scan + residual filter.
  AT CL 160 : CE often mis-estimates OR selectivity; may pick hash + large grant.
  FIX HELPS : Each branch uses its own index seek; estimates are per-branch.
##############################################################################*/
/*
-- BEFORE
SELECT * FROM dbo.Customers WHERE Email = @v OR Phone = @v;

-- AFTER (UNION removes duplicate rows if both match)
SELECT * FROM dbo.Customers WHERE Email = @v
UNION
SELECT * FROM dbo.Customers WHERE Phone = @v AND (Email IS NULL OR Email <> @v);
*/

/*############################################################################
  PATTERN B) Non-SARGable date function on column
  ISSUE     : YEAR(OrderDate)=2024 or CONVERT(date, Col)=@d prevents index seek.
  AT CL 160 : Same anti-pattern, but new CE may choose worse join on scanned heap.
  FIX HELPS : Range predicate is SARGable; seek on index; stable row estimate.
##############################################################################*/
/*
-- BEFORE
WHERE CONVERT(date, CreatedAt) = @d

-- AFTER
*/
DECLARE @d date = '2024-01-15';
DECLARE @dEnd date = DATEADD(DAY, 1, @d);
-- SELECT * FROM dbo.Events WHERE CreatedAt >= @d AND CreatedAt < @dEnd;

/*############################################################################
  PATTERN C) ISNULL / COALESCE on filtered column
  ISSUE     : WHERE ISNULL(Status, 0) = 1 is not SARGable; scans all rows.
  AT CL 160 : Underestimated scans + bad join order on large tables.
  FIX HELPS : Explicit NULL logic allows index on Status when most rows non-null.
##############################################################################*/
/*
-- BEFORE
WHERE ISNULL(Status, 0) = 1

-- AFTER
WHERE Status = 1 OR Status IS NULL   -- only if NULL should match; else Status = 1
*/

/*############################################################################
  PATTERN D) Leading-wildcard LIKE
  ISSUE     : LIKE '%' + @name + '%' cannot use B-tree index.
  AT CL 160 : Full scan cost amplified if CE picks nested loops on huge estimate error.
  FIX HELPS : Prefix search uses index; Full-Text for contains; or trigram/GIN elsewhere.
##############################################################################*/
/*
-- BEFORE
WHERE CustomerName LIKE '%' + @name + '%'

-- AFTER (prefix only)
WHERE CustomerName LIKE @name + N'%'
*/

/*############################################################################
  PATTERN E) NOT IN (subquery) — NULL trap
  ISSUE     : NOT IN returns UNKNOWN if subquery has NULL; often becomes scan.
  AT CL 160 : Bad CE + anti-semi join confusion; unpredictable plans.
  FIX HELPS : NOT EXISTS is NULL-safe and typically gets better anti-semi plan.
##############################################################################*/
/*
-- BEFORE
WHERE CustomerId NOT IN (SELECT CustomerId FROM dbo.Blacklist)

-- AFTER
*/
-- SELECT c.*
-- FROM dbo.Customers AS c
-- WHERE NOT EXISTS (
--     SELECT 1 FROM dbo.Blacklist AS b WHERE b.CustomerId = c.CustomerId
-- );

/*############################################################################
  PATTERN F) IN (large list) vs EXISTS / temp table
  ISSUE     : WHERE Id IN (500+ literals) bloats plan, bad compile time.
  AT CL 160 : Large IN lists + new CE = compile-heavy, unstable plans.
  FIX HELPS : #ids temp table + join gives stats after INSERT; reusable plan.
##############################################################################*/
/*
-- BEFORE
WHERE OrderId IN (1,2,3, ... hundreds ...)

-- AFTER
*/
IF OBJECT_ID('tempdb..#OrderIds') IS NOT NULL DROP TABLE #OrderIds;
CREATE TABLE #OrderIds (OrderId int NOT NULL PRIMARY KEY);
-- INSERT #OrderIds VALUES (1),(2),(3);  -- or INSERT...SELECT from app list
-- SELECT o.* FROM dbo.Orders o INNER JOIN #OrderIds i ON i.OrderId = o.OrderId;

/*############################################################################
  PATTERN G) CROSS APPLY TOP 1 per group
  ISSUE     : Correlated TOP 1 per row; CE guesses rows wrong on APPLY.
  AT CL 160 : Nested loops explosion or hash on wrong estimate.
  FIX HELPS : ROW_NUMBER once over partition; filter rn=1; single pass sort/scan.
##############################################################################*/
/*
-- BEFORE
SELECT c.*, la.LastOrderDate
FROM dbo.Customers c
CROSS APPLY (
    SELECT TOP (1) o.OrderDate AS LastOrderDate
    FROM dbo.Orders o
    WHERE o.CustomerId = c.CustomerId
    ORDER BY o.OrderDate DESC
) la;

-- AFTER
-- ;WITH Ranked AS (
--     SELECT o.CustomerId, o.OrderDate,
--            ROW_NUMBER() OVER (PARTITION BY o.CustomerId ORDER BY o.OrderDate DESC) AS rn
--     FROM dbo.Orders AS o
-- )
-- SELECT c.*, r.OrderDate AS LastOrderDate
-- FROM dbo.Customers c
-- LEFT JOIN Ranked r ON r.CustomerId = c.CustomerId AND r.rn = 1;
*/

/*############################################################################
  PATTERN H) Multi-statement TVF -> inline TVF (iTVF)
  ISSUE     : MSTVF fixed cardinality (~1 row pre-2019); opaque to optimizer.
  AT CL 160 : Interleaved execution helps some MSTVFs; many still regress.
  FIX HELPS : iTVF inlines into parent query; real estimates on base tables.
##############################################################################*/
/*
-- BEFORE: CREATE FUNCTION dbo.mstvf_Orders(@CustomerId int) ... INSERT @t SELECT ...

-- AFTER
*/
CREATE OR ALTER FUNCTION dbo.ifn_OrdersForCustomer (@CustomerId int)
RETURNS TABLE
AS
RETURN
(
    SELECT OrderId, OrderDate, Amount
    FROM dbo.Orders
    WHERE CustomerId = @CustomerId
);
GO

/*############################################################################
  PATTERN I) Scalar UDF in SELECT — inline logic or INLINE=OFF
  ISSUE     : Non-inlineable UDF = per-row UDF operator (hidden cursor cost).
  AT CL 160 : UDF inlining may CHANGE plan (sometimes faster, sometimes worse).
  FIX HELPS : Inline CASE/expression = set-based; or INLINE=OFF to restore old shape.
##############################################################################*/
/*
-- BEFORE
SELECT o.OrderId, dbo.fn_CalcTax(o.Amount) AS Tax FROM dbo.Orders o;

-- AFTER (inline expression)
SELECT o.OrderId,
       CASE WHEN o.Region = N'EU' THEN o.Amount * 0.20 ELSE o.Amount * 0.08 END AS Tax
FROM dbo.Orders o;

-- OR keep UDF but prevent inlining if CL 160 plan regresses:
-- ALTER FUNCTION dbo.fn_CalcTax ... WITH INLINE = OFF;
*/

/*############################################################################
  PATTERN J) Implicit conversion (nvarchar param vs varchar column)
  ISSUE     : WHERE VarcharCol = @nvarcharParam converts column; index not used.
  AT CL 160 : CE + CONVERT_IMPLICIT warning; scans on large tables.
  FIX HELPS : Convert parameter to column type; seek on index resumes.
##############################################################################*/
/*
DECLARE @AppId nvarchar(20) = N'ABC123';
-- BEFORE: WHERE ExternalId = @AppId   -- ExternalId is varchar(20)

-- AFTER
*/
DECLARE @AppId nvarchar(20) = N'ABC123';
DECLARE @id varchar(20) = CAST(@AppId AS varchar(20));
-- SELECT * FROM dbo.ExternalKeys WHERE ExternalId = @id;

/*############################################################################
  PATTERN K) Table variable vs temp table for intermediate sets
  ISSUE     : Table variable @t had fixed low estimate (unless RECOMPILE).
  AT CL 160 : Table variable deferred compilation helps; still weak for large sets.
  FIX HELPS : #temp gets stats after INSERT; CE picks correct join (NL vs hash).
##############################################################################*/
/*
-- BEFORE (large intermediate set)
DECLARE @ids TABLE (Id int PRIMARY KEY);
INSERT @ids SELECT OrderId FROM dbo.Orders WHERE OrderDate >= @From;
SELECT * FROM @ids i JOIN dbo.OrderDetails d ON d.OrderId = i.Id;

-- AFTER
*/
IF OBJECT_ID('tempdb..#ids') IS NOT NULL DROP TABLE #ids;
CREATE TABLE #ids (Id int NOT NULL PRIMARY KEY);
-- INSERT #ids SELECT OrderId FROM dbo.Orders WHERE OrderDate >= @From;
-- SELECT * FROM #ids i JOIN dbo.OrderDetails d ON d.OrderId = i.Id;

/*############################################################################
  PATTERN L) Stage selective keys — break multi-predicate CE correlation
  ISSUE     : 4+ AND filters on different tables; CE correlates selectivity wrong.
  AT CL 160 : Hash join on massive estimate; memory grant spill to TempDB.
  FIX HELPS : Materialize tiny selective set first; join to large tables second.
##############################################################################*/
IF OBJECT_ID('tempdb..#keys') IS NOT NULL DROP TABLE #keys;
/*
DECLARE @Region varchar(20) = 'North', @FromDate date = '2024-01-01';

SELECT CustomerId
INTO #keys
FROM dbo.Customers
WHERE Region = @Region AND IsActive = 1;

CREATE CLUSTERED INDEX CX_keys ON #keys(CustomerId);

SELECT o.*
FROM #keys k
JOIN dbo.Orders o ON o.CustomerId = k.CustomerId
WHERE o.OrderDate >= @FromDate;
*/

/*############################################################################
  PATTERN M) Optional parameters (OR @p IS NULL pattern)
  ISSUE     : WHERE (@Status IS NULL OR Status = @Status) — single plan for all.
  AT CL 160 : CE assumes unknown selectivity; often scan + bad join.
  FIX HELPS : Dynamic SQL adds only supplied filters; each shape gets right plan.
##############################################################################*/
/*
-- BEFORE
CREATE PROC dbo.usp_Search @Status int = NULL, @Region varchar(20) = NULL AS
SELECT * FROM dbo.Orders
WHERE (@Status IS NULL OR StatusId = @Status)
  AND (@Region IS NULL OR Region = @Region);

-- AFTER (dynamic SQL skeleton)
*/
CREATE OR ALTER PROCEDURE dbo.usp_SearchOrders
    @StatusId int = NULL,
    @Region   varchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql nvarchar(max) = N'
        SELECT OrderId, CustomerId, OrderDate, StatusId, Region
        FROM dbo.Orders
        WHERE 1 = 1';
    IF @StatusId IS NOT NULL SET @sql += N' AND StatusId = @StatusId';
    IF @Region   IS NOT NULL SET @sql += N' AND Region = @Region';
    EXEC sp_executesql @sql,
        N'@StatusId int, @Region varchar(20)',
        @StatusId = @StatusId, @Region = @Region;
END;
GO

/*############################################################################
  PATTERN N) Parameter sniffing — OPTIMIZE FOR UNKNOWN / RECOMPILE
  ISSUE     : Plan compiled for first @StatusId (e.g. rare=1 row vs common=millions).
  AT CL 160 : PSP may help; may also flip to worse variant — verify in Query Store.
  FIX HELPS : UNKNOWN = average density; RECOMPILE = plan per execution (CPU cost).
##############################################################################*/
CREATE OR ALTER PROCEDURE dbo.usp_OrdersByStatus
    @StatusId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT OrderId, CustomerId, OrderDate
    FROM dbo.Orders
    WHERE StatusId = @StatusId
    OPTION (OPTIMIZE FOR UNKNOWN);
    -- Heavy report run rarely: OPTION (RECOMPILE);
    -- Known typical value: OPTION (OPTIMIZE FOR (@StatusId = 2));
END;
GO

/*############################################################################
  PATTERN O) Local variable in proc (sniffing mitigation — use carefully)
  ISSUE     : Proc parameter sniffed at compile; variable copied = density estimate.
  AT CL 160 : Same as 130 but CE 160 density math differs — test both ways.
  FIX HELPS : Can flatten skew when PSP not available; can also hide good sniff.
##############################################################################*/
CREATE OR ALTER PROCEDURE dbo.usp_OrdersByCustomer
    @CustomerId int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cid int = @CustomerId;  -- copy parameter
    SELECT OrderId, OrderDate, Amount
    FROM dbo.Orders
    WHERE CustomerId = @cid;
END;
GO

/*############################################################################
  PATTERN P) SELECT * on wide tables in joins
  ISSUE     : All columns flow through hash/sort; wide rows = memory grant bloat.
  AT CL 160 : Batch/hash operators on wide rows spill more often.
  FIX HELPS : Project only needed columns; smaller grants; better chance of merge join.
##############################################################################*/
/*
-- BEFORE
SELECT o.*, c.* FROM dbo.Orders o JOIN dbo.Customers c ON c.CustomerId = o.CustomerId;

-- AFTER
SELECT o.OrderId, o.OrderDate, o.Amount, c.Name, c.Region
FROM dbo.Orders o
JOIN dbo.Customers c ON c.CustomerId = o.CustomerId;
*/

/*############################################################################
  PATTERN Q) Pre-aggregate before join (DISTINCT / GROUP BY explosion)
  ISSUE     : GROUP BY on huge join output; CE underestimates distinct keys.
  AT CL 160 : Hash aggregate + spill; serial plan on large grant wait.
  FIX HELPS : Aggregate one table first; join smaller aggregated set.
##############################################################################*/
/*
-- BEFORE
SELECT p.CategoryId, SUM(d.Qty * d.UnitPrice)
FROM dbo.Orders o
JOIN dbo.OrderDetails d ON d.OrderId = o.OrderId
JOIN dbo.Products p ON p.ProductId = d.ProductId
WHERE o.OrderDate >= @From
GROUP BY p.CategoryId;

-- AFTER (pre-filter orders, then aggregate)
*/
IF OBJECT_ID('tempdb..#ord') IS NOT NULL DROP TABLE #ord;
-- SELECT OrderId INTO #ord FROM dbo.Orders WHERE OrderDate >= @From;
-- CREATE CLUSTERED INDEX CX ON #ord(OrderId);
-- SELECT p.CategoryId, SUM(d.Qty * d.UnitPrice)
-- FROM #ord o
-- JOIN dbo.OrderDetails d ON d.OrderId = o.OrderId
-- JOIN dbo.Products p ON p.ProductId = d.ProductId
-- GROUP BY p.CategoryId;

/*############################################################################
  PATTERN R) Ascending key / latest rows (MAX(Id), open-ended range)
  ISSUE     : WHERE Id > @maxId or recent dates — histogram stale on ascending key.
  AT CL 160 : CE thinks few rows; nested loops; or opposite — huge hash grant.
  FIX HELPS : RECOMPILE uses runtime values; OPTIMIZE FOR UNKNOWN for steady plan.
##############################################################################*/
/*
DECLARE @Since date = DATEADD(DAY, -7, CAST(GETDATE() AS date));
SELECT * FROM dbo.Orders WHERE OrderDate >= @Since
OPTION (RECOMPILE);
*/

/*############################################################################
  PATTERN S) EXISTS vs IN for correlated subqueries
  ISSUE     : IN (subquery) sometimes gets semi-join rewrite; not always optimal.
  AT CL 160 : Plan shape change vs 130; EXISTS often more predictable.
  FIX HELPS : EXISTS short-circuits; optimizer typically uses hash/merge semi-join.
##############################################################################*/
/*
-- BEFORE
SELECT * FROM dbo.Customers c
WHERE c.CustomerId IN (SELECT CustomerId FROM dbo.Orders WHERE OrderDate >= @From);

-- AFTER
SELECT * FROM dbo.Customers c
WHERE EXISTS (
    SELECT 1 FROM dbo.Orders o
    WHERE o.CustomerId = c.CustomerId AND o.OrderDate >= @From
);
*/

/*############################################################################
  PATTERN T) Linked server — pull keys locally first
  ISSUE     : Four-part name join; remote CE assumes ~1 row per lookup.
  AT CL 160 : Same issue, worse with parallel nested loops across network.
  FIX HELPS : OPENQUERY/INSERT #remote with filter pushdown; join locally with stats.
##############################################################################*/
/*
-- BEFORE
SELECT * FROM dbo.Local l
JOIN [LINKED].RemoteDb.dbo.Remote r ON r.Id = l.RemoteId;

-- AFTER
SELECT Id, Col INTO #r FROM OPENQUERY(LINKED, 'SELECT Id, Col FROM RemoteDb.dbo.Remote WHERE Active = 1');
CREATE CLUSTERED INDEX CX ON #r(Id);
SELECT * FROM dbo.Local l JOIN #r r ON r.Id = l.RemoteId;
*/

/*############################################################################
  PATTERN U) Query Store hints — no deploy (SQL 2022)
  ISSUE     : Cannot change app code quickly; need per-query CE/RECOMPILE control.
  AT CL 160 : Bridge while rewriting; document query_id and review date.
  FIX HELPS : Hint applied via QS; remove after permanent T-SQL fix validated.
##############################################################################*/
/*
EXEC sys.sp_query_store_set_hints
    @query_id = 42,
    @query_hints = N'OPTION (USE HINT(''FORCE_LEGACY_CARDINALITY_ESTIMATION''))';

-- Audit: SELECT * FROM sys.query_store_query_hints;
-- Remove: EXEC sys.sp_query_store_clear_hints @query_id = 42;
*/

/*############################################################################
  PATTERN V) Filtered index + parameterized predicate (filtered index mismatch)
  ISSUE     : Proc uses Status='Active' but parameter @Status — filtered index not chosen.
  AT CL 160 : CE may ignore filtered index benefit; scan base table instead.
  FIX HELPS : Match filter literal in proc branch, or RECOMPILE, or OPTIMIZE FOR value.
##############################################################################*/
/*
-- Index: CREATE INDEX IX_Orders_Active ON dbo.Orders(OrderDate) WHERE Status = 'Active';

-- BEFORE (parameter prevents filtered index match)
WHERE Status = @Status

-- AFTER (separate paths or static Active branch)
IF @Status = N'Active'
    SELECT ... FROM dbo.Orders WHERE Status = N'Active' AND OrderDate >= @From;
ELSE
    SELECT ... FROM dbo.Orders WHERE Status = @Status AND OrderDate >= @From;
*/

/*############################################################################
  QUICK REFERENCE — when to use which pattern
  --------------------------------------------------------------------------
  Scan where seek expected     -> B, C, D, J (SARGability / conversion)
  Spill / high memory grant    -> L, P, Q (stage keys, narrow select, pre-agg)
  Slow after CL 160 only       -> H, I, K (TVF / UDF / table variable)
  Fast for one param, slow else-> N, O, R (sniffing / ascending key)
  Optional report params       -> M (dynamic SQL)
  App cannot deploy            -> U (Query Store hints)
##############################################################################*/

PRINT '01_Before_After_Examples.sql loaded. Uncomment and run one pattern at a time.';
