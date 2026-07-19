/*
    Migration 2016 -> 2022 | Trace flag inventory
    Document all flags before migration; re-test on 2022 — many legacy flags are unnecessary or harmful.
    Risk: Read-only
*/
SET NOCOUNT ON;

DBCC TRACESTATUS(-1);

-- Startup trace flags from registry are not visible here — document separately from SQL Server Configuration Manager.
