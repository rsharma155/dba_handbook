/* SQL_Server_Assessment */
SELECT DISTINCT vs.volume_mount_point AS Volume, vs.logical_volume_name AS Label,
       CAST(vs.total_bytes/1073741824.0 AS decimal(18,2)) AS TotalGB,
       CAST(vs.available_bytes/1073741824.0 AS decimal(18,2)) AS FreeGB,
       CAST(vs.available_bytes*100.0/NULLIF(vs.total_bytes,0) AS decimal(6,2)) AS FreePercent,
       vs.file_system_type AS FileSystem,
       STUFF((SELECT DISTINCT ', '+CASE mf2.type WHEN 0 THEN 'DATA' WHEN 1 THEN 'LOG' ELSE 'OTHER' END
              FROM sys.master_files mf2 CROSS APPLY sys.dm_os_volume_stats(mf2.database_id,mf2.file_id) v2
              WHERE v2.volume_mount_point=vs.volume_mount_point FOR XML PATH('')),1,2,'') AS SqlFileTypes
FROM sys.master_files mf CROSS APPLY sys.dm_os_volume_stats(mf.database_id,mf.file_id) vs
ORDER BY vs.volume_mount_point;
