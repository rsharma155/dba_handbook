/*
    Migration 2016 -> 2022 | PolyBase Hadoop (HDFS) blocker check
    Hadoop external data sources removed in SQL Server 2022 — recreate with supported connectors.
    Risk: Read-only
*/
SET NOCOUNT ON;

IF OBJECT_ID('sys.external_data_sources') IS NULL
BEGIN
    SELECT N'PolyBase external data sources not available on this instance/version' AS [Note];
    RETURN;
END

SELECT
    eds.name AS [ExternalDataSource],
    eds.location,
    eds.type_desc,
    eds.resource_manager_location
FROM sys.external_data_sources AS eds
WHERE eds.type_desc LIKE N'%HADOOP%'
   OR eds.type = 5; -- legacy Hadoop type on some versions

SELECT
    et.name AS [ExternalTable],
    SCHEMA_NAME(et.schema_id) AS [SchemaName],
    eds.name AS [ExternalDataSource],
    eds.type_desc
FROM sys.external_tables AS et
JOIN sys.external_data_sources AS eds ON et.data_source_id = eds.data_source_id
WHERE eds.type_desc LIKE N'%HADOOP%'
   OR eds.type = 5;
