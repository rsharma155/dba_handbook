/*
================================================================================
SQL Server Database Compatibility Level Audit
================================================================================
Description:
    Flags databases that are not running on the instance's default compatibility
    level and checks for auto_close, auto_shrink, and orphaned database owners.
    Running at a lower compatibility level prevents access to new optimizer
    improvements and query store features.

Output:
    List of databases with their current vs. instance-default compatibility level,
    along with misconfigured settings (auto_close, auto_shrink) and owner info.

Action:
    For databases with "WARNING: Below instance level", test and upgrade the
    compatibility level during a maintenance window:
        ALTER DATABASE [DBName] SET COMPATIBILITY_LEVEL = <instance_default>;
    For auto_close or auto_shrink enabled, disable immediately:
        ALTER DATABASE [DBName] SET AUTO_CLOSE OFF, AUTO_SHRINK OFF;
    For orphaned owners, run:
        EXEC [DBName].dbo.sp_changedbowner @loginame = N'sa';

Parameters:
    @DatabaseList - comma-separated database names or NULL for all user DBs

Criticality: Medium
================================================================================
*/

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

DECLARE @DatabaseList NVARCHAR(MAX) = NULL;
DECLARE @InstanceCompat INT =
    COALESCE(
        CAST(SERVERPROPERTY(N'ProductMajorVersion') AS INT),
        CAST(PARSENAME(CAST(SERVERPROPERTY(N'ProductVersion') AS NVARCHAR(128)), 4) AS INT)
    ) * 10;

SELECT
    d.name AS [Database_Name],
    d.compatibility_level AS [Compatibility_Level],
    @InstanceCompat AS [Instance_Default_Compat_Level],
    d.collation_name,
    d.is_auto_close_on,
    d.is_auto_shrink_on,
    SUSER_SNAME(d.owner_sid) AS [Database_Owner],
    CASE
        WHEN d.compatibility_level < @InstanceCompat THEN N'WARNING: Below instance level'
        WHEN d.compatibility_level > @InstanceCompat THEN N'REVIEW: Above instance level'
        ELSE N'OK'
    END AS [Compat_Status],
    CASE
        WHEN SUSER_SNAME(d.owner_sid) IS NULL THEN N'CRITICAL: Orphaned database owner'
        WHEN SUSER_SNAME(d.owner_sid) = N'sa' THEN N'INFO: Owner is sa'
        ELSE N'OK'
    END AS [Owner_Status]
FROM sys.databases AS d
WHERE d.database_id > 4
  AND d.state = 0
  AND (
        @DatabaseList IS NULL
        OR d.name IN (
            SELECT LTRIM(RTRIM(value))
            FROM STRING_SPLIT(@DatabaseList, N',')
            WHERE LTRIM(RTRIM(value)) <> N''
        )
      )
ORDER BY d.compatibility_level, d.name;
