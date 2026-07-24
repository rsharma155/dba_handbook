# T-SQL Rewrite Patterns for CE 160 Regressions

After moving to compatibility **160**, the optimizer often chooses different joins/aggregates because **row estimates change**. These patterns are the usual offenders. Prefer **fixing the estimate root cause** over sprinkling hints forever.

---

## 1. Multi-predicate filters (correlated selectivity)

**Problem:** Old CE under/over-estimated `Col1 = @a AND Col2 = @b AND Col3 BETWEEN ...`. New CE may pick hash join + huge memory grant.

**Rewrite ideas:**
- Ensure a supporting composite index matches equality columns first, then inequality.
- Split into two steps with a temp table when intermediate cardinality is tiny:

```sql
-- BEFORE (one complex statement)
SELECT ...
FROM dbo.Orders o
JOIN dbo.OrderDetails d ON d.OrderId = o.OrderId
JOIN dbo.Products p ON p.ProductId = d.ProductId
WHERE o.CustomerId = @CustomerId
  AND o.OrderDate >= @From AND o.OrderDate < @To
  AND p.CategoryId = @Cat;

-- AFTER (materialize selective set)
IF OBJECT_ID('tempdb..#o') IS NOT NULL DROP TABLE #o;
SELECT o.OrderId, o.OrderDate
INTO #o
FROM dbo.Orders o
WHERE o.CustomerId = @CustomerId
  AND o.OrderDate >= @From AND o.OrderDate < @To;

CREATE CLUSTERED INDEX CX ON #o(OrderId);

SELECT ...
FROM #o o
JOIN dbo.OrderDetails d ON d.OrderId = o.OrderId
JOIN dbo.Products p ON p.ProductId = d.ProductId
WHERE p.CategoryId = @Cat;
```

---

## 2. `OR` across columns / tables

**Problem:** `WHERE a = @x OR b = @x` often becomes scan under either CE; 160 may pick worse residual predicates.

**Rewrite:** `UNION ALL` / `UNION` branches that are each SARGable:

```sql
-- BEFORE
SELECT * FROM dbo.T WHERE ColA = @v OR ColB = @v;

-- AFTER
SELECT * FROM dbo.T WHERE ColA = @v
UNION
SELECT * FROM dbo.T WHERE ColB = @v AND ColA <> @v;  -- avoid dupes if needed
```

---

## 3. Non-SARGable predicates (same code, newly painful)

```sql
-- BAD
WHERE YEAR(OrderDate) = 2024
WHERE CONVERT(varchar(20), OrderDate, 112) = '20240101'
WHERE ISNULL(Status, 0) = 1
WHERE CONVERT(int, VarcharId) = @Id
WHERE CustomerName LIKE '%' + @name + '%'

-- GOOD
WHERE OrderDate >= '20240101' AND OrderDate < '20250101'
WHERE Status = 1 OR (Status IS NULL AND ... explicit logic)
WHERE VarcharId = CONVERT(varchar(20), @Id)  -- convert the parameter, match column type
WHERE CustomerName LIKE @name + '%'          -- leading wildcards still bad; use FTS if needed
```

**Implicit conversion:** Match parameter/column types (`nvarchar` vs `varchar`) — CE 160 + conversion frequently forces scans.

---

## 4. Table variables & multi-statement TVFs

**Problem:** Table variables historically had poor density; interleaved execution helps MSTVFs but not always.

```sql
-- Prefer temp tables when rowcount can be large / used in joins
DECLARE @t TABLE (Id int PRIMARY KEY);
-- vs
CREATE TABLE #t (Id int NOT NULL PRIMARY KEY);
```

For MSTVF → **inline TVF** (iTVF) when possible so the optimizer inlines the definition.

---

## 5. Local variable vs parameter sniffing

```sql
-- Pattern that mimics OPTIMIZE FOR UNKNOWN (can help skew; can hurt too)
CREATE PROCEDURE dbo.usp_Get
    @CustomerId int
AS
BEGIN
    DECLARE @cid int = @CustomerId;
    SELECT * FROM dbo.Orders WHERE CustomerId = @cid;
END;
```

Better modern options on SQL 2022:
- `OPTION (OPTIMIZE FOR UNKNOWN)`
- `OPTION (RECOMPILE)` for low-frequency heavy reports
- Rely on **Parameter Sensitive Plan (PSP) optimization** (compat 160) for qualifying predicates — verify with actual plans (`Dispatcher` / multiple variants in Query Store)

---

## 6. `SELECT *` + wide joins

New CE may choose hash join on wide rows → **memory grant / spill**.

- Project only needed columns.
- Cover with include columns for hot paths.
- Avoid key lookups exploding under new join order.

---

## 7. Scalar UDFs in SELECT / WHERE

```sql
-- BAD: row-by-row
SELECT dbo.fn_Format(c.Name), dbo.fn_Tax(o.Amount) FROM ...

-- GOOD: inline logic, iTVF, or computed persisted column
```

SQL 2019+ scalar UDF inlining helps at higher compat levels — if UDF is inlineable, **160 can improve**; if not inlineable, it still hurts. Check `is_inlineable` in `sys.sql_modules`.

---

## 8. `NOT IN (subquery)` with NULLs

```sql
-- RISKY / often slow
WHERE Id NOT IN (SELECT RefId FROM dbo.X)

-- PREFER
WHERE NOT EXISTS (SELECT 1 FROM dbo.X WHERE X.RefId = T.Id)
-- or LEFT JOIN ... WHERE X.RefId IS NULL
```

---

## 9. Distinct / Group By explosion

If 160 underestimates grouping keys, you get oversized hash aggregates and spills.

- Pre-aggregate in stages.
- Ensure statistics on group-by columns.
- Consider indexed view for stable aggregates (with schemabinding + matching edition features).

---

## 10. Linked server / remote queries

Remote CE is often “1 row” fantasy → nested loops storm.

- Pull remote keys into temp table, then join locally.
- Use `OPENQUERY` with filters pushed down.

---

## Hint policy (team rule)

| Situation | Prefer |
|-----------|--------|
| 1–10 queries regress | Query Store force plan or `sp_query_store_set_hints` |
| Same pattern in many procs | Rewrite pattern + stats/index |
| Hundreds regress | Temporary `LEGACY_CARDINALITY_ESTIMATION = ON` + weekly burn-down |
| Skewed params | `OPTIMIZE FOR` / `RECOMPILE` / PSP verification |

Never ship permanent `FORCE ORDER` / join hints without a ticket and revisit date.

---

See also: `../06_Code_Rewrite_Patterns/01_Before_After_Examples.sql`
