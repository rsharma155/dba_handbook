/*
================================================================================
Purpose:        Analyzes system error logs and connectivity ring buffers to 
                diagnose hidden login failures and critical system errors.
Provides:       Recent critical error log entries (I/O, Corruption, Memory) and 
                connectivity trace records (Login timeouts, drops).
Importance:     Critical for detecting network instability or hardware-related 
                errors that may not be immediately obvious.
Interpretation: Frequent "Login timeout" or "Connection drop" in ring buffers 
                 points to network or client-side issues.
Action: For error log entries showing I/O errors (823, 824, 825): run DBCC CHECKDB on affected databases immediately and check disk health. For connectivity issues (Login timeout, Connection drops): investigate network latency, firewall rules, and client driver configuration. For memory errors: run memory_diagnostics.sql to check PLE and memory pressure. Review the error log weekly as part of routine maintenance.
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

-- 1. Search Error Log for Critical Issues (Last 7 days)
PRINT 'Searching Error Log for Critical Issues...';
IF OBJECT_ID('tempdb..#ErrorLog') IS NOT NULL DROP TABLE #ErrorLog;
CREATE TABLE #ErrorLog (LogDate DATETIME, ProcessInfo VARCHAR(100), Text VARCHAR(MAX));

INSERT INTO #ErrorLog EXEC sp_readerrorlog 0, 1;

SELECT 
    LogDate, ProcessInfo, Text,
    CAST('Filters SQL Server Error Log for critical keywords. ' +
         'Threshold: Keywords like "corruption", "failed", "error", "IO" are high priority. ' +
         'Recommendation: Correlate error timestamps with application failures or performance drops.'
         AS VARCHAR(1000)) AS [Metric_Context]
FROM #ErrorLog
WHERE (Text LIKE '%error%' OR Text LIKE '%failed%' OR Text LIKE '%corruption%' OR Text LIKE '%IO%')
  AND LogDate > DATEADD(DAY, -7, GETDATE())
ORDER BY LogDate DESC;

-- 2. Connectivity Ring Buffer (Hidden Login Failures)
PRINT 'Analyzing Connectivity Ring Buffer...';
SELECT 
    CAST(record AS XML).value('(//Record/ConnectivityTraceRecord/RecordType)[1]', 'varchar(50)') AS [Record_Type],
    CAST(record AS XML).value('(//Record/ConnectivityTraceRecord/RecordSource)[1]', 'varchar(50)') AS [Source],
    CAST(record AS XML).value('(//Record/ConnectivityTraceRecord/Spid)[1]', 'int') AS [SPID],
    CAST(record AS XML).value('(//Record/ConnectivityTraceRecord/RemoteHost)[1]', 'varchar(100)') AS [Remote_Host],
    CAST(record AS XML).value('(//Record/ConnectivityTraceRecord/TdsErrorCode)[1]', 'varchar(10)') AS [TDS_Error],
    CAST(record AS XML).value('(//Record/ConnectivityTraceRecord/State)[1]', 'int') AS [State],
    [timestamp],
    CAST('Connectivity ring buffer identifies login timeouts and connection terminations not in the error log. ' +
         'Threshold: High frequency of "Error" record types indicates network or client-side issues. ' +
         'Recommendation: Check client connection strings and network stability.'
         AS VARCHAR(1000)) AS [Metric_Context]
FROM sys.dm_os_ring_buffers WITH (NOLOCK)
WHERE ring_buffer_type = 'RING_BUFFER_CONNECTIVITY'
ORDER BY [timestamp] DESC;

DROP TABLE #ErrorLog;
