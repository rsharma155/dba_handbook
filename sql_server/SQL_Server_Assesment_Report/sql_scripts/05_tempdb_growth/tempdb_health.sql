/* SQL_Server_Assessment */
;WITH f AS (
 SELECT name AS LogicalName, type_desc AS FileType, size*8.0/1024 AS SizeMB,
        CASE WHEN is_percent_growth=1 THEN CONVERT(varchar(20),growth)+'%'
             ELSE CONVERT(varchar(20),CONVERT(bigint,growth)*8/1024)+' MB' END AS Growth,
        physical_name AS PhysicalName
 FROM tempdb.sys.database_files
), u AS (
 SELECT SUM(user_object_reserved_page_count)*8.0/1024 AS UserObjectsMB,
        SUM(internal_object_reserved_page_count)*8.0/1024 AS InternalObjectsMB,
        SUM(version_store_reserved_page_count)*8.0/1024 AS VersionStoreMB,
        SUM(unallocated_extent_page_count)*8.0/1024 AS FreeSpaceMB
 FROM tempdb.sys.dm_db_file_space_usage
)
SELECT f.*, CAST(u.UserObjectsMB AS decimal(18,1)) AS UserObjectsMB,
       CAST(u.InternalObjectsMB AS decimal(18,1)) AS InternalObjectsMB,
       CAST(u.VersionStoreMB AS decimal(18,1)) AS VersionStoreMB,
       CAST(u.FreeSpaceMB AS decimal(18,1)) AS FreeSpaceMB
FROM f CROSS JOIN u ORDER BY FileType,LogicalName;
