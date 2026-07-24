/*
================================================================================
03_Database_Options_Post_Restore.sql
Purpose : Safe database options after restore onto SQL 2022.
================================================================================
*/
USE [YourDB]; -- <<< change
GO

-- Verify page checksum (should already be on from modern sources)
SELECT name, page_verify_option_desc, is_auto_shrink_on, is_auto_close_on,
       is_auto_create_stats_on, is_auto_update_stats_on, is_auto_update_stats_async_on,
       target_recovery_time_in_seconds, compatibility_level
FROM sys.databases WHERE name = DB_NAME();

/*
RECOMMENDED (uncomment as needed)

ALTER DATABASE CURRENT SET PAGE_VERIFY CHECKSUM WITH NO_WAIT;
ALTER DATABASE CURRENT SET AUTO_SHRINK OFF;
ALTER DATABASE CURRENT SET AUTO_CLOSE OFF;
ALTER DATABASE CURRENT SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS ON;
-- Async stats: can reduce blocking on stats updates; validate for your workload
-- ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS_ASYNC ON;

-- Target recovery time (indirect checkpoint) - often 60 on modern systems
-- ALTER DATABASE CURRENT SET TARGET_RECOVERY_TIME = 60 SECONDS;

-- RCSI: reduces reader/writer blocking; test carefully (row versioning in TempDB)
-- ALTER DATABASE CURRENT SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
*/

-- Keep compatibility at 130 until Query Store baseline exists:
-- ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 130;

-- Target end state after remediation:
-- ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 160;
