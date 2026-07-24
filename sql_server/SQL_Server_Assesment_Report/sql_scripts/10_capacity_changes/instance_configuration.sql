/* SQL_Server_Assessment */
SELECT name AS ConfigurationName, value AS ConfiguredValue, value_in_use AS RunningValue,
       minimum AS MinimumValue, maximum AS MaximumValue, is_dynamic AS IsDynamic
FROM sys.configurations
WHERE name IN ('max server memory (MB)','min server memory (MB)','max degree of parallelism',
'cost threshold for parallelism','backup compression default','optimize for ad hoc workloads',
'remote admin connections','xp_cmdshell','Ole Automation Procedures','clr enabled',
'contained database authentication','default trace enabled')
ORDER BY name;
