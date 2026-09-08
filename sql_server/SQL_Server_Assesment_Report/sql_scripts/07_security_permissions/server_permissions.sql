/* SQL_Server_Assessment */
-- COLLATE DATABASE_DEFAULT: permission_name uses the fixed catalog collation
-- (Latin1_General_CI_AS_KS_WS) while principal names use the instance collation,
-- so mixing them in COALESCE/ORDER BY raises a collation-conflict error.
SELECT COALESCE(sp.state_desc COLLATE DATABASE_DEFAULT,'ROLE MEMBER') AS PermissionState,
       COALESCE(sp.permission_name COLLATE DATABASE_DEFAULT,r.name COLLATE DATABASE_DEFAULT) AS PermissionOrRole,
       grantee.name AS Grantee, grantee.type_desc AS GranteeType,
       grantor.name AS Grantor
FROM sys.server_principals grantee
LEFT JOIN sys.server_permissions sp ON grantee.principal_id=sp.grantee_principal_id
LEFT JOIN sys.server_principals grantor ON sp.grantor_principal_id=grantor.principal_id
LEFT JOIN sys.server_role_members rm ON grantee.principal_id=rm.member_principal_id
LEFT JOIN sys.server_principals r ON rm.role_principal_id=r.principal_id
WHERE grantee.type IN ('S','U','G')
  AND (sp.permission_name IS NOT NULL OR r.name IS NOT NULL)
  AND grantee.name NOT LIKE '##%##'
ORDER BY grantee.name,PermissionOrRole;
