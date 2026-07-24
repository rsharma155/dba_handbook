/* SQL_Server_Assessment */
DECLARE @path nvarchar(260);
SELECT @path=path FROM sys.traces WHERE is_default=1;
IF @path IS NOT NULL
 SELECT TOP (200) DatabaseName, FileName, StartTime, Duration/1000.0 AS DurationMs,
        IntegerData*8.0/1024 AS GrowthMB,
        CASE EventClass WHEN 92 THEN 'Data File Auto Grow' WHEN 93 THEN 'Log File Auto Grow' END AS EventName
 FROM fn_trace_gettable(@path,DEFAULT)
 WHERE EventClass IN (92,93) AND StartTime>=DATEADD(DAY,-{{DaysToAnalyze}},GETDATE())
 ORDER BY StartTime DESC;
