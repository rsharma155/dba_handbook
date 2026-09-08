/*
================================================================================
01_Database_Scoped_CE_and_Optimizer_Controls.sql
Purpose : Temporary bridges while remediating queries under compat 160.
Strategy: Prefer Query Store plan force / query hints for few offenders.
          Use database-scoped bridges only when regressions are widespread.
          Keep CL 160 ON so other engine features remain available.
================================================================================
*/
USE [YourDB]; -- <<< change
GO

SELECT name, value, value_for_secondary, is_value_default
FROM sys.database_scoped_configurations
ORDER BY name;

/*
--------------------------------------------------------------------------------
SAFE BRIDGES (keep CL 160; clear proc cache after each change)
Use when Step 5B: widespread regressions after flipping to 160.
--------------------------------------------------------------------------------

-- Option A: Legacy CE globally (emergency bridge - restores 2016-like estimates)
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;

-- Option B: Disable Scalar UDF Inlining (CPU spikes / bad UDF plans after skip from 2016)
ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = OFF;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;

-- Option C: Optimizer hotfixes (cumulative CE/optimizer fixes under modern CE)
ALTER DATABASE SCOPED CONFIGURATION SET QUERY_OPTIMIZER_HOTFIXES = ON;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;

-- Option D: Batch mode on rowstore OFF (only if spills / CX* after CL 160)
-- ALTER DATABASE SCOPED CONFIGURATION SET BATCH_MODE_ON_ROWSTORE = OFF;
-- ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;

-- Option E: PSP OFF (only if variant thrashing proven)
-- ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = OFF;
-- ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;

GOAL STATE (after rewrites / forced plans validated):
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF;
ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = ON;  -- if safe
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;

Parameter sniffing OFF is a last resort - prefer query-level OPTIMIZE FOR / RECOMPILE.
-- ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = OFF;
*/
GO
