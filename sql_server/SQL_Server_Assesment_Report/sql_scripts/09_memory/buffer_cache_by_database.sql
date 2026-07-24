/* SQL_Server_Assessment */
SELECT CASE WHEN database_id=32767 THEN 'Resource/Free Pages' ELSE DB_NAME(database_id) END AS DatabaseName,
       COUNT_BIG(*) AS PageCount,CAST(COUNT_BIG(*)*8.0/1024 AS decimal(18,1)) AS CachedMB,
       SUM(CASE WHEN is_modified=1 THEN 1 ELSE 0 END) AS DirtyPages,
       CAST(100.0*SUM(CASE WHEN is_modified=1 THEN 1 ELSE 0 END)/NULLIF(COUNT_BIG(*),0) AS decimal(6,2)) AS DirtyPercent
FROM sys.dm_os_buffer_descriptors
GROUP BY database_id ORDER BY COUNT_BIG(*) DESC;
