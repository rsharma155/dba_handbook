/* SQL_Server_Assessment */
SELECT p.name AS LoginName, p.type_desc AS LoginType, p.is_disabled AS IsDisabled,
       p.create_date AS CreateDate, p.modify_date AS ModifyDate,
       LOGINPROPERTY(p.name,'IsLocked') AS IsLocked,
       LOGINPROPERTY(p.name,'IsExpired') AS IsExpired,
       CASE WHEN IS_SRVROLEMEMBER('sysadmin',p.name)=1 THEN 'Yes' ELSE 'No' END AS IsSysadmin,
       p.default_database_name AS DefaultDatabase
FROM sys.server_principals p
WHERE p.type IN ('S','U','G') AND p.name NOT LIKE '##%##'
ORDER BY IsSysadmin DESC,p.name;
