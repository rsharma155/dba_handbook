/* SQL_Server_Assessment */
-- CONVERT(bigint) before multiplying: max_size is int pages, and the common
-- 2 TB log default (268435456 pages) * 8 overflows int arithmetic.
SELECT DB_NAME(database_id) AS DatabaseName, name AS LogicalName, type_desc AS FileType,
       CAST(size*8.0/1024 AS decimal(18,1)) AS SizeMB,
       CASE WHEN is_percent_growth=1 THEN CONVERT(varchar(20),growth)+'%'
            ELSE CONVERT(varchar(20),CONVERT(bigint,growth)*8/1024)+' MB' END AS GrowthSetting,
       is_percent_growth AS IsPercentGrowth,
       CASE WHEN max_size=-1 THEN 'Unlimited'
            WHEN max_size=268435456 THEN '2 TB (log default)'
            ELSE CONVERT(varchar(30),CONVERT(bigint,max_size)*8/1024)+' MB' END AS MaxSize,
       physical_name AS PhysicalName
-- database_id > 4 skips master/tempdb/model/msdb; TempDB sizing and growth are
-- covered by the dedicated TempDB Health section.
FROM sys.master_files WHERE database_id > 4 ORDER BY database_id,type,file_id;
