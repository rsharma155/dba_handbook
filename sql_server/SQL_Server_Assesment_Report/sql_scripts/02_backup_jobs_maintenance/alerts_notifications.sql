/* SQL_Server_Assessment */
SELECT 'Database Mail Account' AS Component, COUNT(*) AS ConfiguredCount FROM msdb.dbo.sysmail_account
UNION ALL SELECT 'SQL Agent Operator', COUNT(*) FROM msdb.dbo.sysoperators WHERE enabled=1
UNION ALL SELECT 'SQL Agent Alert', COUNT(*) FROM msdb.dbo.sysalerts WHERE enabled=1
UNION ALL SELECT 'Severity 19-25 Alert', COUNT(*) FROM msdb.dbo.sysalerts WHERE enabled=1 AND severity BETWEEN 19 AND 25
UNION ALL SELECT 'Error 823/824/825 Alert', COUNT(*) FROM msdb.dbo.sysalerts WHERE enabled=1 AND message_id IN (823,824,825);
