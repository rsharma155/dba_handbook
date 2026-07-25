// =============================================================================
// Module:   SqlOptima.SchemaCompare.Services.SqlConnectionService
// Purpose:  SQL Server connectivity - connection test, database enumeration, and schema object listing.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using Microsoft.Data.SqlClient;
using SqlOptima.SchemaCompare.Models;

namespace SqlOptima.SchemaCompare.Services;

public sealed record SchemaObjectInfo(string ObjectType, string SchemaName, string ObjectName)
{
    public string FullName => string.IsNullOrWhiteSpace(SchemaName)
        ? ObjectName
        : $"{SchemaName}.{ObjectName}";
}

public static class SqlConnectionService
{
    public static async Task TestAsync(ConnectionInfo info, CancellationToken ct = default)
    {
        await using var conn = new SqlConnection(info.BuildConnectionString("master"));
        await conn.OpenAsync(ct).ConfigureAwait(false);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT @@VERSION";
        _ = await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false);
    }

    public static async Task<IReadOnlyList<string>> ListUserDatabasesAsync(
        ConnectionInfo info, CancellationToken ct = default)
    {
        var list = new List<string>();
        await using var conn = new SqlConnection(info.BuildConnectionString("master"));
        await conn.OpenAsync(ct).ConfigureAwait(false);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
SELECT name
FROM sys.databases
WHERE database_id > 4
  AND state_desc = N'ONLINE'
  AND name NOT IN (N'distribution')
ORDER BY name;";
        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false))
            list.Add(reader.GetString(0));
        return list;
    }

    /// <summary>
    /// Lists user schema objects in the given database (tables, views, procs, functions, triggers).
    /// </summary>
    public static async Task<IReadOnlyList<SchemaObjectInfo>> ListSchemaObjectsAsync(
        ConnectionInfo info, string database, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(database))
            return Array.Empty<SchemaObjectInfo>();

        var list = new List<SchemaObjectInfo>();
        await using var conn = new SqlConnection(info.BuildConnectionString(database));
        await conn.OpenAsync(ct).ConfigureAwait(false);
        await using var cmd = conn.CreateCommand();
        cmd.CommandTimeout = 60;
        cmd.CommandText = @"
SELECT
    CASE o.type
        WHEN N'U'  THEN N'TABLE'
        WHEN N'V'  THEN N'VIEW'
        WHEN N'P'  THEN N'PROCEDURE'
        WHEN N'FN' THEN N'FUNCTION'
        WHEN N'IF' THEN N'FUNCTION'
        WHEN N'TF' THEN N'FUNCTION'
        WHEN N'TR' THEN N'TRIGGER'
        ELSE o.type_desc
    END AS ObjectType,
    s.name AS SchemaName,
    o.name AS ObjectName
FROM sys.objects AS o
INNER JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE o.is_ms_shipped = 0
  AND o.type IN (N'U', N'V', N'P', N'FN', N'IF', N'TF', N'TR')
  AND s.name NOT IN (N'sys', N'INFORMATION_SCHEMA', N'guest')
ORDER BY
    CASE o.type
        WHEN N'U'  THEN 1
        WHEN N'V'  THEN 2
        WHEN N'P'  THEN 3
        WHEN N'FN' THEN 4
        WHEN N'IF' THEN 4
        WHEN N'TF' THEN 4
        WHEN N'TR' THEN 5
        ELSE 9
    END,
    s.name,
    o.name;";
        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false))
        {
            list.Add(new SchemaObjectInfo(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetString(2)));
        }
        return list;
    }
}
