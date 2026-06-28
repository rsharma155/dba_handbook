/*
================================================================================
Purpose:        Monitors the health, status, and latency of SQL Server 
                Replication agents.
Provides:       Replication agent status (Snapshot, Log Reader, Distribution, 
                Merge) and undelivered command counts (latency).
Importance:     Essential for ensuring data consistency across replicated 
                environments and preventing subscriber lag.
Interpretation: Agents in 'Failed' or 'Retrying' state indicate stoppage. 
                High undelivered commands suggest backlog/latency.
Action: For agents in "Failed" state: review SQL Agent error logs and re-start the agent. For agents in "Retrying" state: check connectivity between publisher/distributor/subscriber (firewall, network, login). For high undelivered command counts: ensure the distribution agent is running and not backlogged. Consider increasing the poll interval or optimizing the publication design (filtered publications, batch processing).
Criticality:    High
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

-- 1. Replication Agent Status
PRINT 'Checking Replication Agent Status...';
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'distribution')
BEGIN
    SELECT 
        publisher_db,
        publication,
        agent_type = CASE agent_type WHEN 1 THEN 'Snapshot' WHEN 2 THEN 'Log Reader' WHEN 3 THEN 'Distribution' WHEN 4 THEN 'Merge' END,
        status = CASE status WHEN 1 THEN 'Started' WHEN 2 THEN 'Succeeded' WHEN 3 THEN 'InProgress' WHEN 4 THEN 'Idle' WHEN 5 THEN 'Retrying' WHEN 6 THEN 'Failed' END,
        last_timestamp,
        delivery_rate,
        delivery_latency,
        CAST('Replication agent status audit. ' +
             'Threshold: Agents in "Failed" or "Retrying" state indicate replication stoppage. ' +
             'Recommendation: Check agent history and replication monitor for network or permission errors.'
             AS VARCHAR(1000)) AS [Metric_Context]
    FROM distribution.dbo.MSreplication_monitordata WITH (NOLOCK)
    ORDER BY status DESC;
END
ELSE
BEGIN
    PRINT 'Distribution database not found. Replication might not be configured on this instance.';
END

-- 2. Undelivered Commands (Latency)
PRINT 'Checking Undelivered Commands...';
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'distribution')
BEGIN
    SELECT 
        s.name AS [Subscription],
        da.publisher_db,
        da.publication,
        h.pending_commands AS [Undelivered_Commands],
        h.delivery_latency / 1000 AS [Latency_s],
        CAST('Measures transactional replication backlog. ' +
             'Threshold: High undelivered command count indicates subscriber lag. ' +
             'Recommendation: Check subscriber I/O performance and network throughput between distributor and subscriber.'
             AS VARCHAR(1000)) AS [Metric_Context]
    FROM distribution.dbo.MSdistribution_status AS h WITH (NOLOCK)
    INNER JOIN distribution.dbo.MSdistribution_agents AS da WITH (NOLOCK) ON h.agent_id = da.id
    INNER JOIN master.sys.servers AS s ON da.subscriber_id = s.server_id
    ORDER BY h.pending_commands DESC;
END
