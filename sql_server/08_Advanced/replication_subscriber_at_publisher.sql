/*
================================================================================
Replication Subscriptions for a Subscriber (Publisher)
================================================================================
Description:
    Publisher-side view of publications/articles for a given subscriber.

Source Attribution:
    Adapted from Kendal Van Dyke's SQL-Server-Scripts
    https://github.com/kendalvandyke/SQL-Server-Scripts
    Original file: Replication - Show Subscriptions and Articles for Subscriber at Publisher.sql
    Original license requires the author header below to be preserved.
    Free for personal, educational, and internal corporate use; redistribution
    or sale without the author's express written consent is prohibited.

Action:
    Set @SubscriberName. Run in published database on publisher.

Criticality: Medium
Integrated into DBA Handbook: 2026-07-23
================================================================================
*/
/*********************************************************************************************
Replication - Show Subscriptions and Articles for Subscriber at Publisher v1.00 (2010-11-01)
(C) 2010, Kendal Van Dyke

Feedback: mailto:kendal.vandyke@gmail.com

License: 
	This query is free to download and use for personal, educational, and internal 
	corporate purposes, provided that this header is preserved. Redistribution or sale 
	of this query, in whole or in part, is prohibited without the author's express 
	written consent.
	
Note: 
	Execute this query on the PUBLISHER

*********************************************************************************************/

-- Show Publications and Articles for Subscriber
-- Run this in the published database on the PUBLISHER
DECLARE @SubscriberName sysname,
	@serverid smallint

SET @SubscriberName = 'WIN-1VGMTQ5PHHP'

SELECT @serverid = srvid
FROM master..sysservers WITH (NOLOCK)
WHERE srvname = @SubscriberName

SELECT syspublications.name, sysarticles.dest_table, @SubscriberName, syssubscriptions.dest_db
FROM syspublications WITH (NOLOCK)
	INNER JOIN sysarticles WITH (NOLOCK) ON syspublications.pubid = sysarticles.pubid
	LEFT OUTER JOIN syssubscriptions WITH (NOLOCK) ON sysarticles.artid = syssubscriptions.artid
														AND syssubscriptions.srvid = @serverid
WHERE syspublications.pubid IN (
	SELECT sysarticles.pubid
	FROM syssubscriptions WITH (NOLOCK)
		INNER JOIN sysarticles WITH (NOLOCK) ON syssubscriptions.artid = sysarticles.artid
	WHERE syssubscriptions.srvid = @serverid
)
ORDER BY syspublications.name, sysarticles.dest_table, syssubscriptions.dest_db


