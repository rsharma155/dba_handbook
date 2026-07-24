/* SQL_Server_Assessment */
DECLARE @path nvarchar(260);
SELECT @path=path FROM sys.traces WHERE is_default=1;
IF @path IS NOT NULL
 SELECT TOP (100) StartTime, LoginName, HostName, ApplicationName,
        DatabaseName, ObjectName, TextData
 FROM fn_trace_gettable(@path,DEFAULT)
 WHERE EventClass=164 AND StartTime>=DATEADD(DAY,-{{DaysToAnalyze}},GETDATE())
   -- Skip system databases; tempdb object churn in particular is noise. NULL
   -- DatabaseName rows (server-scope events) are kept.
   AND (DatabaseName IS NULL OR DatabaseName NOT IN (N'master',N'model',N'msdb',N'tempdb'))
 ORDER BY StartTime DESC;
