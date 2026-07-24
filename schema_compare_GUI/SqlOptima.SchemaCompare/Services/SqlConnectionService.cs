using Microsoft.Data.SqlClient;
using SqlOptima.SchemaCompare.Models;

namespace SqlOptima.SchemaCompare.Services;

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
}
