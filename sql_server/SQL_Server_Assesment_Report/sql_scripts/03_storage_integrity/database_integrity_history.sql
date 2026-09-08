/* SQL_Server_Assessment */
-- LastGoodCheckDbTime returns 1900-01-01 when CHECKDB has never completed;
-- NULLIF maps that sentinel to NULL so it reports as "never" instead of a date.
;WITH c AS (
    SELECT name,
           NULLIF(CONVERT(datetime,DATABASEPROPERTYEX(name,'LastGoodCheckDbTime')),'19000101') AS LastGoodCheckDb,
           state_desc
    FROM sys.databases WHERE database_id > 4 AND source_database_id IS NULL
)
SELECT name AS DatabaseName,
       LastGoodCheckDb,
       DATEDIFF(DAY,LastGoodCheckDb,GETDATE()) AS DaysSinceCheck,
       state_desc AS Status
FROM c ORDER BY name;
