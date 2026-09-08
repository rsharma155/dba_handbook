/* SQL_Server_Assessment */
SELECT j.name AS JobName, c.name AS Category, j.enabled AS Enabled,
       CASE WHEN j.name LIKE '%backup%' THEN 'Backup'
            WHEN j.name LIKE '%integrity%' OR j.name LIKE '%checkdb%' THEN 'Integrity'
            WHEN j.name LIKE '%index%' OR j.name LIKE '%stat%' THEN 'Index/Statistics'
            ELSE 'Other' END AS MaintenanceType
FROM msdb.dbo.sysjobs j LEFT JOIN msdb.dbo.syscategories c ON j.category_id=c.category_id
WHERE j.name LIKE '%backup%' OR j.name LIKE '%integrity%' OR j.name LIKE '%checkdb%'
   OR j.name LIKE '%index%' OR j.name LIKE '%stat%' OR c.name='Database Maintenance'
ORDER BY MaintenanceType,j.name;
