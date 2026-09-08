/* SQL_Server_Assessment */
SELECT d.name AS DatabaseName, d.is_published AS IsPublished,
       d.is_subscribed AS IsSubscribed, d.is_merge_published AS IsMergePublished,
       d.is_distributor AS IsDistributor
FROM sys.databases d
WHERE d.is_published=1 OR d.is_subscribed=1 OR d.is_merge_published=1 OR d.is_distributor=1;
