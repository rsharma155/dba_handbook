/* SQL_Server_Assessment */
SELECT DB_NAME() AS DatabaseName,
       dp.name AS UserName,
       dp.type_desc AS UserType
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON dp.sid=sp.sid
WHERE dp.authentication_type_desc='INSTANCE'
  AND dp.type IN ('S','U','G')
  AND dp.principal_id>4
  AND sp.sid IS NULL;
