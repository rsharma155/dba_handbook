/* SQL_Server_Assessment */
SELECT TOP (20) type AS ClerkType, SUM(pages_kb)/1024 AS AllocatedMB,
       SUM(virtual_memory_reserved_kb)/1024 AS VirtualReservedMB,
       SUM(virtual_memory_committed_kb)/1024 AS VirtualCommittedMB,
       CASE WHEN type LIKE 'CACHESTORE_SQLCP%' OR type LIKE 'CACHESTORE_OBJCP%' THEN 'Plan cache'
            WHEN type LIKE 'USERSTORE%' THEN 'User/workspace store'
            WHEN type LIKE 'MEMORYCLERK_SQLBUFFERPOOL%' THEN 'Buffer pool'
            ELSE 'Other SQL memory' END AS Category
FROM sys.dm_os_memory_clerks
WHERE pages_kb>0 GROUP BY type ORDER BY SUM(pages_kb) DESC;
