/*
================================================================================
Tablespace Audit — Locations, sizes, and disk mapping
================================================================================
Description:
    Lists tablespaces with filesystem locations and per-database usage.

Action:  Ensure tablespaces map to correct storage tiers; monitor disk free space.

Criticality: Medium
================================================================================
*/

SELECT spcname, pg_catalog.pg_get_userbyid(spcowner) AS owner,
       pg_tablespace_location(oid) AS location
FROM pg_tablespace
ORDER BY spcname;

SELECT t.spcname,
       pg_size_pretty(sum(pg_tablespace_size(t.oid))) AS total_size
FROM pg_tablespace t
GROUP BY t.spcname;
