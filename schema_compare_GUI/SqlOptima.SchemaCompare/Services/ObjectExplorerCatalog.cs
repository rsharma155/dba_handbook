// =============================================================================
// Module:   SqlOptima.SchemaCompare.Services.ObjectExplorerCatalog
// Purpose:  System-catalog queries backing the Object Explorer - table columns, keys, constraints, indexes, triggers, and CREATE TABLE scripting.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Text;
using Microsoft.Data.SqlClient;
using SqlOptima.SchemaCompare.Models;

namespace SqlOptima.SchemaCompare.Services;

/// <summary>Which child folder under a table in Object explorer.</summary>
public enum TableFolderKind
{
    Columns,
    Keys,
    Constraints,
    Indexes,
    Triggers
}

/// <summary>Side + DB context for browse-mode tree nodes.</summary>
public sealed record BrowseSideContext(bool IsSource, string Database);

/// <summary>Tag on a table node that can expand into SSMS-style folders.</summary>
public sealed record TableBrowseNode(
    BrowseSideContext Side,
    string SchemaName,
    string TableName)
{
    public string FullName => $"{SchemaName}.{TableName}";
}

/// <summary>Tag on Columns/Keys/Constraints/Indexes/Triggers folder under a table.</summary>
public sealed record TableFolderNode(
    TableBrowseNode Table,
    TableFolderKind Kind,
    bool Loaded = false);

/// <summary>Leaf under a table folder (column, key, index, …).</summary>
public sealed record TableChildItem(
    TableFolderKind Kind,
    string Name,
    string DisplayText,
    string DetailText = "");

/// <summary>Pure formatting helpers for Object explorer / CREATE TABLE scripting.</summary>
public static class ObjectExplorerFormat
{
    public static string FolderLabel(TableFolderKind kind) => kind switch
    {
        TableFolderKind.Columns => "Columns",
        TableFolderKind.Keys => "Keys",
        TableFolderKind.Constraints => "Constraints",
        TableFolderKind.Indexes => "Indexes",
        TableFolderKind.Triggers => "Triggers",
        _ => kind.ToString()
    };

    public static string FolderIcon(TableFolderKind kind) => kind switch
    {
        TableFolderKind.Columns => "column",
        TableFolderKind.Keys => "key",
        TableFolderKind.Constraints => "constraint",
        TableFolderKind.Indexes => "index",
        TableFolderKind.Triggers => "trig",
        _ => "type"
    };

    public static string ChildIcon(TableFolderKind kind) => FolderIcon(kind);

    public static string FormatColumnDisplay(
        string name, string typeName, int maxLength, byte precision, byte scale,
        bool isNullable, bool isIdentity)
    {
        var type = FormatDataType(typeName, maxLength, precision, scale);
        var nullPart = isNullable ? "NULL" : "NOT NULL";
        var idPart = isIdentity ? " IDENTITY" : "";
        return $"{name} ({type}, {nullPart}{idPart})";
    }

    public static string FormatDataType(string typeName, int maxLength, byte precision, byte scale)
    {
        var t = (typeName ?? "").ToLowerInvariant();
        return t switch
        {
            "varchar" or "nvarchar" or "varbinary" or "char" or "nchar" or "binary" =>
                maxLength < 0 ? $"{t}(max)" : $"{t}({maxLength})",
            "decimal" or "numeric" => $"{t}({precision},{scale})",
            // Fractional seconds live in scale for these types (sys.columns.precision is often 0).
            "datetime2" or "datetimeoffset" or "time" => $"{t}({scale})",
            "float" => precision > 0 ? $"{t}({precision})" : t,
            _ => t
        };
    }

    public static string FormatKeyColumn(IndexKeyColumn c) =>
        QuoteIdent(c.Name) + (c.IsDescending ? " DESC" : " ASC");

    /// <summary>
    /// Ensures PK/UQ constraints have columns (fall back to matching index rows) and
    /// picks up constraint indexes that were missing from <paramref name="keys"/>.
    /// </summary>
    public static IReadOnlyList<KeyScriptRow> MergeConstraintKeys(
        IReadOnlyList<KeyScriptRow> keys,
        IReadOnlyList<IndexScriptRow> indexes)
    {
        var result = new List<KeyScriptRow>();
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var k in keys)
        {
            if (k.Columns.Count == 0)
            {
                var ix = indexes.FirstOrDefault(i =>
                    i.Name.Equals(k.Name, StringComparison.OrdinalIgnoreCase) &&
                    (i.IsPrimaryKey || i.IsUniqueConstraint) &&
                    i.KeyColumns.Count > 0);
                if (ix != null)
                {
                    result.Add(k with { Columns = ix.KeyColumns, IsClustered = ix.IsClustered });
                    names.Add(k.Name);
                    continue;
                }
            }

            result.Add(k);
            names.Add(k.Name);
        }

        foreach (var ix in indexes.Where(i => i.IsPrimaryKey || i.IsUniqueConstraint))
        {
            if (names.Contains(ix.Name) || ix.KeyColumns.Count == 0) continue;
            result.Add(new KeyScriptRow(
                ix.Name,
                ix.IsPrimaryKey,
                ix.IsUniqueConstraint || (!ix.IsPrimaryKey && ix.IsUnique),
                ix.IsClustered,
                ix.KeyColumns));
            names.Add(ix.Name);
        }

        return result;
    }

    public static string QuoteIdent(string name)
    {
        if (string.IsNullOrEmpty(name)) return "[]";
        return "[" + name.Replace("]", "]]", StringComparison.Ordinal) + "]";
    }

    public static string BracketName(string schema, string name) =>
        $"{QuoteIdent(schema)}.{QuoteIdent(name)}";

    /// <summary>
    /// Parses engine display names such as <c>[dbo].[Companies]</c>,
    /// <c>dbo.Companies</c>, or <c>[Companies]</c> into schema + name.
    /// </summary>
    public static bool TryParseObjectName(string? display, out string schema, out string name)
    {
        schema = "dbo";
        name = "";
        if (string.IsNullOrWhiteSpace(display)) return false;

        var s = display.Trim();
        // [schema].[name]
        var m = System.Text.RegularExpressions.Regex.Match(s,
            @"^\[(?<sch>[^\]]+)\]\.\[(?<nm>[^\]]+)\]$");
        if (m.Success)
        {
            schema = m.Groups["sch"].Value;
            name = m.Groups["nm"].Value;
            return !string.IsNullOrWhiteSpace(name);
        }

        // schema.name (unquoted)
        var dot = s.IndexOf('.');
        if (dot > 0 && dot < s.Length - 1 && !s.Contains('['))
        {
            schema = s[..dot].Trim();
            name = s[(dot + 1)..].Trim();
            return !string.IsNullOrWhiteSpace(schema) && !string.IsNullOrWhiteSpace(name);
        }

        // [name] or bare name
        if (s.StartsWith('[') && s.EndsWith(']') && s.Length > 2)
            name = s[1..^1];
        else
            name = s;
        return !string.IsNullOrWhiteSpace(name);
    }

    /// <summary>Maps SMO collection / browse type labels to a scripting kind.</summary>
    public static string NormalizeObjectType(string? objectType)
    {
        var t = (objectType ?? "").Trim().ToUpperInvariant();
        return t switch
        {
            "TABLES" or "TABLE" or "U" => "TABLE",
            "VIEWS" or "VIEW" or "V" => "VIEW",
            "STOREDPROCEDURES" or "STORED PROCEDURES" or "STORED_PROCEDURE" or "PROCEDURE" or "PROC" or "P" => "PROCEDURE",
            "USERDEFINEDFUNCTIONS" or "FUNCTIONS" or "FUNCTION" or "FN" or "IF" or "TF" => "FUNCTION",
            "TRIGGERS" or "TRIGGER" or "TR" or "DATABASETRIGGERS" => "TRIGGER",
            "SCHEMAS" or "SCHEMA" => "SCHEMA",
            "SEQUENCES" or "SEQUENCE" => "SEQUENCE",
            "SYNONYMS" or "SYNONYM" => "SYNONYM",
            "USERDEFINEDDATATYPES" or "USERDEFINEDTABLETYPES" or "TYPE" or "TYPES" => "TYPE",
            _ => t
        };
    }

    /// <summary>
    /// Builds a CREATE TABLE script from catalog rows (unit-testable without SQL Server).
    /// </summary>
    public static string BuildCreateTableScript(
        string schema,
        string table,
        IReadOnlyList<ColumnScriptRow> columns,
        IReadOnlyList<KeyScriptRow> keys,
        IReadOnlyList<CheckScriptRow> checks,
        IReadOnlyList<DefaultScriptRow> defaults,
        IReadOnlyList<ForeignKeyScriptRow> foreignKeys,
        IReadOnlyList<IndexScriptRow> indexes)
    {
        var sb = new StringBuilder();
        var full = BracketName(schema, table);
        var mergedKeys = MergeConstraintKeys(keys, indexes);
        sb.AppendLine($"-- Script Table as CREATE for {schema}.{table}");
        sb.AppendLine($"CREATE TABLE {full}");
        sb.AppendLine("(");

        var defaultByColumn = defaults
            .Where(d => !string.IsNullOrWhiteSpace(d.ColumnName))
            .GroupBy(d => d.ColumnName, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);

        var colLines = new List<string>();
        foreach (var c in columns.OrderBy(x => x.ColumnId))
        {
            var type = FormatDataType(c.TypeName, c.MaxLength, c.Precision, c.Scale);
            var line = $"    {QuoteIdent(c.Name)} {type}";
            if (c.IsIdentity)
                line += $" IDENTITY({c.IdentitySeed},{c.IdentityIncrement})";
            line += c.IsNullable ? " NULL" : " NOT NULL";
            if (defaultByColumn.TryGetValue(c.Name, out var def) && !string.IsNullOrWhiteSpace(def.Definition))
                line += $" CONSTRAINT {QuoteIdent(def.Name)} DEFAULT {NormalizeDefault(def.Definition)}";
            colLines.Add(line);
        }

        // Inline PK / unique key constraints in CREATE TABLE (SSMS-style ASC/DESC)
        foreach (var k in mergedKeys
                     .Where(k => (k.IsPrimaryKey || k.IsUnique) && k.Columns.Count > 0)
                     .OrderBy(k => k.IsPrimaryKey ? 0 : 1)
                     .ThenBy(k => k.Name))
        {
            var cols = string.Join(", ", k.Columns.Select(FormatKeyColumn));
            if (k.IsPrimaryKey)
                colLines.Add($"    CONSTRAINT {QuoteIdent(k.Name)} PRIMARY KEY {(k.IsClustered ? "CLUSTERED" : "NONCLUSTERED")} ({cols})");
            else
                colLines.Add($"    CONSTRAINT {QuoteIdent(k.Name)} UNIQUE {(k.IsClustered ? "CLUSTERED" : "NONCLUSTERED")} ({cols})");
        }

        foreach (var chk in checks.OrderBy(c => c.Name))
        {
            var def = string.IsNullOrWhiteSpace(chk.Definition) ? "(1 = 1)" : chk.Definition.Trim();
            colLines.Add($"    CONSTRAINT {QuoteIdent(chk.Name)} CHECK {def}");
        }

        for (var i = 0; i < colLines.Count; i++)
        {
            sb.Append(colLines[i]);
            sb.AppendLine(i < colLines.Count - 1 ? "," : "");
        }

        sb.AppendLine(");");
        sb.AppendLine("GO");

        foreach (var chk in checks.Where(c => c.IsDisabled).OrderBy(c => c.Name))
        {
            sb.AppendLine();
            sb.AppendLine($"ALTER TABLE {full} NOCHECK CONSTRAINT {QuoteIdent(chk.Name)};");
            sb.AppendLine("GO");
        }

        foreach (var fk in foreignKeys.OrderBy(f => f.Name))
        {
            var cols = string.Join(", ", fk.Columns.Select(QuoteIdent));
            var refCols = string.Join(", ", fk.ReferencedColumns.Select(QuoteIdent));
            var withCheck = fk.IsDisabled || fk.IsNotTrusted ? "WITH NOCHECK" : "WITH CHECK";
            sb.AppendLine();
            sb.AppendLine($"ALTER TABLE {full} {withCheck}");
            sb.AppendLine($"    ADD CONSTRAINT {QuoteIdent(fk.Name)} FOREIGN KEY ({cols})");
            sb.AppendLine($"    REFERENCES {BracketName(fk.ReferencedSchema, fk.ReferencedTable)} ({refCols})");
            if (!string.IsNullOrWhiteSpace(fk.DeleteAction) && !fk.DeleteAction.Equals("NO_ACTION", StringComparison.OrdinalIgnoreCase))
                sb.AppendLine($"    ON DELETE {MapAction(fk.DeleteAction)}");
            if (!string.IsNullOrWhiteSpace(fk.UpdateAction) && !fk.UpdateAction.Equals("NO_ACTION", StringComparison.OrdinalIgnoreCase))
                sb.AppendLine($"    ON UPDATE {MapAction(fk.UpdateAction)}");
            sb.AppendLine(";");
            sb.AppendLine("GO");
            if (fk.IsDisabled)
            {
                sb.AppendLine($"ALTER TABLE {full} NOCHECK CONSTRAINT {QuoteIdent(fk.Name)};");
                sb.AppendLine("GO");
            }
        }

        // Non-constraint indexes only (PK / UNIQUE constraints already inlined above)
        var pkOrUniqueNames = new HashSet<string>(
            mergedKeys.Select(k => k.Name), StringComparer.OrdinalIgnoreCase);

        foreach (var ix in indexes
                     .Where(i => !i.IsPrimaryKey && !i.IsUniqueConstraint)
                     .OrderBy(i => i.Name))
        {
            if (pkOrUniqueNames.Contains(ix.Name)) continue;
            if (ix.KeyColumns.Count == 0) continue;
            var unique = ix.IsUnique ? "UNIQUE " : "";
            var clustered = ix.IsClustered ? "CLUSTERED" : "NONCLUSTERED";
            var cols = string.Join(", ", ix.KeyColumns.Select(FormatKeyColumn));
            sb.AppendLine();
            sb.Append($"CREATE {unique}{clustered} INDEX {QuoteIdent(ix.Name)} ON {full}");
            sb.AppendLine($" ({cols})");
            if (ix.IncludedColumns.Count > 0)
            {
                var incl = string.Join(", ", ix.IncludedColumns.Select(QuoteIdent));
                sb.AppendLine($"INCLUDE ({incl})");
            }
            if (!string.IsNullOrWhiteSpace(ix.FilterDefinition))
                sb.AppendLine($"WHERE {ix.FilterDefinition.Trim()}");
            sb.AppendLine(";");
            sb.AppendLine("GO");
        }

        return sb.ToString();
    }

    private static string NormalizeDefault(string definition)
    {
        var d = definition.Trim();
        // sys.default_constraints.definition often includes surrounding parentheses
        return d;
    }

    private static string MapAction(string action) => action.ToUpperInvariant() switch
    {
        "CASCADE" => "CASCADE",
        "SET_NULL" => "SET NULL",
        "SET_DEFAULT" => "SET DEFAULT",
        _ => "NO ACTION"
    };
}

public sealed record ColumnScriptRow(
    int ColumnId,
    string Name,
    string TypeName,
    int MaxLength,
    byte Precision,
    byte Scale,
    bool IsNullable,
    bool IsIdentity,
    long IdentitySeed = 1,
    long IdentityIncrement = 1);

public sealed record KeyScriptRow(
    string Name,
    bool IsPrimaryKey,
    bool IsUnique,
    bool IsClustered,
    IReadOnlyList<IndexKeyColumn> Columns);

public sealed record CheckScriptRow(string Name, string Definition, bool IsDisabled = false);

public sealed record DefaultScriptRow(string Name, string ColumnName, string Definition);

public sealed record ForeignKeyScriptRow(
    string Name,
    IReadOnlyList<string> Columns,
    string ReferencedSchema,
    string ReferencedTable,
    IReadOnlyList<string> ReferencedColumns,
    string DeleteAction,
    string UpdateAction,
    bool IsDisabled = false,
    bool IsNotTrusted = false);

public sealed record IndexKeyColumn(string Name, bool IsDescending);

public sealed record IndexScriptRow(
    string Name,
    bool IsUnique,
    bool IsClustered,
    bool IsPrimaryKey,
    bool IsUniqueConstraint,
    IReadOnlyList<IndexKeyColumn> KeyColumns,
    IReadOnlyList<string> IncludedColumns,
    string? FilterDefinition);

/// <summary>Loads table children and CREATE TABLE scripts from system catalogs.</summary>
public static class ObjectExplorerCatalog
{
    public static async Task<IReadOnlyList<TableChildItem>> ListTableFolderAsync(
        ConnectionInfo info,
        string database,
        string schema,
        string table,
        TableFolderKind kind,
        CancellationToken ct = default)
    {
        return kind switch
        {
            TableFolderKind.Columns => await ListColumnsAsync(info, database, schema, table, ct).ConfigureAwait(false),
            TableFolderKind.Keys => await ListKeysAsync(info, database, schema, table, ct).ConfigureAwait(false),
            TableFolderKind.Constraints => await ListConstraintsAsync(info, database, schema, table, ct).ConfigureAwait(false),
            TableFolderKind.Indexes => await ListIndexesAsync(info, database, schema, table, ct).ConfigureAwait(false),
            TableFolderKind.Triggers => await ListTriggersAsync(info, database, schema, table, ct).ConfigureAwait(false),
            _ => Array.Empty<TableChildItem>()
        };
    }

    public static async Task<string> ScriptCreateTableAsync(
        ConnectionInfo info,
        string database,
        string schema,
        string table,
        CancellationToken ct = default)
    {
        await using var conn = new SqlConnection(info.BuildConnectionString(database));
        await conn.OpenAsync(ct).ConfigureAwait(false);

        var columns = await ReadColumnsAsync(conn, schema, table, ct).ConfigureAwait(false);
        if (columns.Count == 0)
            return $"-- Table {schema}.{table} was not found or has no columns.";

        var keys = await ReadKeysAsync(conn, schema, table, ct).ConfigureAwait(false);
        var checks = await ReadChecksAsync(conn, schema, table, ct).ConfigureAwait(false);
        var defaults = await ReadDefaultsAsync(conn, schema, table, ct).ConfigureAwait(false);
        var fks = await ReadForeignKeysAsync(conn, schema, table, ct).ConfigureAwait(false);
        var indexes = await ReadIndexesAsync(conn, schema, table, ct).ConfigureAwait(false);

        return ObjectExplorerFormat.BuildCreateTableScript(
            schema, table, columns, keys, checks, defaults, fks, indexes);
    }

    /// <summary>
    /// Scripts the live definition of an object from a connection for the
    /// Source | Target Object Details compare view.
    /// </summary>
    public static async Task<string> ScriptObjectDefinitionAsync(
        ConnectionInfo info,
        string database,
        string objectType,
        string schema,
        string name,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(database))
            return "-- No database selected.";
        if (string.IsNullOrWhiteSpace(name))
            return "-- Object name is empty.";

        var kind = ObjectExplorerFormat.NormalizeObjectType(objectType);
        try
        {
            if (kind == "TABLE")
                return await ScriptCreateTableAsync(info, database, schema, name, ct).ConfigureAwait(false);

            if (kind is "VIEW" or "PROCEDURE" or "FUNCTION" or "TRIGGER")
                return await ScriptModuleDefinitionAsync(info, database, schema, name, kind, ct).ConfigureAwait(false);

            return await ScriptMetadataObjectAsync(info, database, schema, name, kind, ct).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return $"-- Could not script [{schema}].[{name}] ({kind}) from [{database}]:\r\n-- {ex.Message}";
        }
    }

    private static async Task<string> ScriptModuleDefinitionAsync(
        ConnectionInfo info, string database, string schema, string name, string kind, CancellationToken ct)
    {
        await using var conn = new SqlConnection(info.BuildConnectionString(database));
        await conn.OpenAsync(ct).ConfigureAwait(false);
        await using var cmd = conn.CreateCommand();
        cmd.CommandTimeout = 60;
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@name", name);
        cmd.CommandText = @"
SELECT m.definition, o.type_desc
FROM sys.objects AS o
INNER JOIN sys.schemas AS s ON s.schema_id = o.schema_id
LEFT JOIN sys.sql_modules AS m ON m.object_id = o.object_id
WHERE o.is_ms_shipped = 0
  AND s.name = @schema
  AND o.name = @name;";
        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        if (!await reader.ReadAsync(ct).ConfigureAwait(false))
            return $"-- {kind} {ObjectExplorerFormat.BracketName(schema, name)} was not found in [{database}].";

        var definition = reader.IsDBNull(0) ? null : reader.GetString(0);
        var typeDesc = reader.IsDBNull(1) ? kind : reader.GetString(1);
        if (string.IsNullOrWhiteSpace(definition))
            return $"-- {typeDesc} {ObjectExplorerFormat.BracketName(schema, name)} has no scriptable definition in [{database}].";

        return $"-- {typeDesc} from [{database}]\r\n" + definition.TrimEnd() + "\r\n";
    }

    private static async Task<string> ScriptMetadataObjectAsync(
        ConnectionInfo info, string database, string schema, string name, string kind, CancellationToken ct)
    {
        await using var conn = new SqlConnection(info.BuildConnectionString(database));
        await conn.OpenAsync(ct).ConfigureAwait(false);
        await using var cmd = conn.CreateCommand();
        cmd.CommandTimeout = 30;
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@name", name);

        switch (kind)
        {
            case "SCHEMA":
                cmd.CommandText = "SELECT name FROM sys.schemas WHERE name = @name;";
                cmd.Parameters.Clear();
                cmd.Parameters.AddWithValue("@name", name);
                var sch = await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false);
                return sch == null
                    ? $"-- Schema [{name}] was not found in [{database}]."
                    : $"-- Schema from [{database}]\r\nCREATE SCHEMA [{name}];\r\n";

            case "SEQUENCE":
                cmd.CommandText = @"
SELECT s.name, sch.name, TYPE_NAME(s.user_type_id), s.start_value, s.increment, s.minimum_value, s.maximum_value, s.is_cycling
FROM sys.sequences s
INNER JOIN sys.schemas sch ON sch.schema_id = s.schema_id
WHERE sch.name = @schema AND s.name = @name;";
                await using (var r = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false))
                {
                    if (!await r.ReadAsync(ct).ConfigureAwait(false))
                        return $"-- Sequence {ObjectExplorerFormat.BracketName(schema, name)} was not found in [{database}].";
                    return
                        $"-- Sequence from [{database}]\r\n" +
                        $"CREATE SEQUENCE {ObjectExplorerFormat.BracketName(r.GetString(1), r.GetString(0))} AS {r.GetString(2)}\r\n" +
                        $"    START WITH {r.GetValue(3)}\r\n" +
                        $"    INCREMENT BY {r.GetValue(4)}\r\n" +
                        $"    MINVALUE {r.GetValue(5)}\r\n" +
                        $"    MAXVALUE {r.GetValue(6)}\r\n" +
                        $"    {(r.GetBoolean(7) ? "CYCLE" : "NO CYCLE")};\r\n";
                }

            case "SYNONYM":
                cmd.CommandText = @"
SELECT syn.name, sch.name, syn.base_object_name
FROM sys.synonyms syn
INNER JOIN sys.schemas sch ON sch.schema_id = syn.schema_id
WHERE sch.name = @schema AND syn.name = @name;";
                await using (var r = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false))
                {
                    if (!await r.ReadAsync(ct).ConfigureAwait(false))
                        return $"-- Synonym {ObjectExplorerFormat.BracketName(schema, name)} was not found in [{database}].";
                    return
                        $"-- Synonym from [{database}]\r\n" +
                        $"CREATE SYNONYM {ObjectExplorerFormat.BracketName(r.GetString(1), r.GetString(0))} FOR {r.GetString(2)};\r\n";
                }

            default:
                return
                    $"-- Object type '{kind}' is not fully scripted in Object Details.\r\n" +
                    $"-- Name: {ObjectExplorerFormat.BracketName(schema, name)}\r\n" +
                    $"-- Database: [{database}]\r\n";
        }
    }

    private static async Task<IReadOnlyList<TableChildItem>> ListColumnsAsync(
        ConnectionInfo info, string database, string schema, string table, CancellationToken ct)
    {
        await using var conn = new SqlConnection(info.BuildConnectionString(database));
        await conn.OpenAsync(ct).ConfigureAwait(false);
        var rows = await ReadColumnsAsync(conn, schema, table, ct).ConfigureAwait(false);
        return rows.Select(c =>
        {
            var display = ObjectExplorerFormat.FormatColumnDisplay(
                c.Name, c.TypeName, c.MaxLength, c.Precision, c.Scale, c.IsNullable, c.IsIdentity);
            return new TableChildItem(TableFolderKind.Columns, c.Name, display,
                $"Column\r\n  {c.Name}\r\n\r\nType\r\n  {ObjectExplorerFormat.FormatDataType(c.TypeName, c.MaxLength, c.Precision, c.Scale)}\r\n\r\nNullable\r\n  {c.IsNullable}\r\n\r\nIdentity\r\n  {c.IsIdentity}");
        }).ToList();
    }

    private static async Task<IReadOnlyList<TableChildItem>> ListKeysAsync(
        ConnectionInfo info, string database, string schema, string table, CancellationToken ct)
    {
        await using var conn = new SqlConnection(info.BuildConnectionString(database));
        await conn.OpenAsync(ct).ConfigureAwait(false);
        var list = new List<TableChildItem>();

        var keys = await ReadKeysAsync(conn, schema, table, ct).ConfigureAwait(false);
        foreach (var k in keys)
        {
            var kind = k.IsPrimaryKey ? "PK" : "UQ";
            var cols = string.Join(", ", k.Columns.Select(c => c.Name + (c.IsDescending ? " DESC" : "")));
            var display = $"{k.Name} ({kind}: {cols})";
            list.Add(new TableChildItem(TableFolderKind.Keys, k.Name, display,
                $"Key\r\n  {k.Name}\r\n\r\nType\r\n  {(k.IsPrimaryKey ? "PRIMARY KEY" : "UNIQUE")}\r\n\r\nColumns\r\n  {cols}"));
        }

        var fks = await ReadForeignKeysAsync(conn, schema, table, ct).ConfigureAwait(false);
        foreach (var fk in fks)
        {
            var cols = string.Join(", ", fk.Columns);
            var refs = $"{fk.ReferencedSchema}.{fk.ReferencedTable} ({string.Join(", ", fk.ReferencedColumns)})";
            var display = $"{fk.Name} (FK: {cols} → {refs})";
            list.Add(new TableChildItem(TableFolderKind.Keys, fk.Name, display,
                $"Foreign key\r\n  {fk.Name}\r\n\r\nColumns\r\n  {cols}\r\n\r\nReferences\r\n  {refs}"));
        }

        return list;
    }

    private static async Task<IReadOnlyList<TableChildItem>> ListConstraintsAsync(
        ConnectionInfo info, string database, string schema, string table, CancellationToken ct)
    {
        await using var conn = new SqlConnection(info.BuildConnectionString(database));
        await conn.OpenAsync(ct).ConfigureAwait(false);
        var list = new List<TableChildItem>();

        foreach (var c in await ReadChecksAsync(conn, schema, table, ct).ConfigureAwait(false))
        {
            var display = $"{c.Name} (CHECK)";
            list.Add(new TableChildItem(TableFolderKind.Constraints, c.Name, display,
                $"Check constraint\r\n  {c.Name}\r\n\r\nDefinition\r\n  {c.Definition}"));
        }

        foreach (var d in await ReadDefaultsAsync(conn, schema, table, ct).ConfigureAwait(false))
        {
            var display = $"{d.Name} (DEFAULT on {d.ColumnName})";
            list.Add(new TableChildItem(TableFolderKind.Constraints, d.Name, display,
                $"Default constraint\r\n  {d.Name}\r\n\r\nColumn\r\n  {d.ColumnName}\r\n\r\nDefinition\r\n  {d.Definition}"));
        }

        return list;
    }

    private static async Task<IReadOnlyList<TableChildItem>> ListIndexesAsync(
        ConnectionInfo info, string database, string schema, string table, CancellationToken ct)
    {
        await using var conn = new SqlConnection(info.BuildConnectionString(database));
        await conn.OpenAsync(ct).ConfigureAwait(false);
        var indexes = await ReadIndexesAsync(conn, schema, table, ct).ConfigureAwait(false);
        return indexes.Select(ix =>
        {
            var flags = new List<string>();
            if (ix.IsPrimaryKey) flags.Add("PK");
            else if (ix.IsUniqueConstraint) flags.Add("UQ");
            else if (ix.IsUnique) flags.Add("UNIQUE");
            flags.Add(ix.IsClustered ? "CLUSTERED" : "NONCLUSTERED");
            var cols = string.Join(", ", ix.KeyColumns.Select(c => c.Name + (c.IsDescending ? " DESC" : "")));
            var display = $"{ix.Name} ({string.Join(", ", flags)}: {cols})";
            return new TableChildItem(TableFolderKind.Indexes, ix.Name, display,
                $"Index\r\n  {ix.Name}\r\n\r\nType\r\n  {string.Join(" ", flags)}\r\n\r\nColumns\r\n  {cols}");
        }).ToList();
    }

    private static async Task<IReadOnlyList<TableChildItem>> ListTriggersAsync(
        ConnectionInfo info, string database, string schema, string table, CancellationToken ct)
    {
        await using var conn = new SqlConnection(info.BuildConnectionString(database));
        await conn.OpenAsync(ct).ConfigureAwait(false);
        await using var cmd = conn.CreateCommand();
        cmd.CommandTimeout = 60;
        cmd.CommandText = @"
SELECT tr.name
FROM sys.triggers AS tr
INNER JOIN sys.tables AS t ON t.object_id = tr.parent_id
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = @schema AND t.name = @table AND tr.is_ms_shipped = 0
ORDER BY tr.name;";
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", table);
        var list = new List<TableChildItem>();
        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false))
        {
            var name = reader.GetString(0);
            list.Add(new TableChildItem(TableFolderKind.Triggers, name, name,
                $"Trigger\r\n  {name}\r\n\r\nParent\r\n  {schema}.{table}"));
        }
        return list;
    }

    private static async Task<List<ColumnScriptRow>> ReadColumnsAsync(
        SqlConnection conn, string schema, string table, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandTimeout = 60;
        cmd.CommandText = @"
SELECT
    c.column_id,
    c.name,
    ty.name AS type_name,
    CASE
        WHEN ty.name IN (N'nchar', N'nvarchar') AND c.max_length > 0 THEN c.max_length / 2
        WHEN ty.name IN (N'nchar', N'nvarchar') AND c.max_length < 0 THEN -1
        ELSE c.max_length
    END AS max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.is_identity,
    ISNULL(CONVERT(bigint, ic.seed_value), 1) AS seed_value,
    ISNULL(CONVERT(bigint, ic.increment_value), 1) AS increment_value
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
INNER JOIN sys.columns AS c ON c.object_id = t.object_id
INNER JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.identity_columns AS ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE s.name = @schema AND t.name = @table
ORDER BY c.column_id;";
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", table);
        var list = new List<ColumnScriptRow>();
        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false))
        {
            list.Add(new ColumnScriptRow(
                reader.GetInt32(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetInt32(3),
                reader.GetByte(4),
                reader.GetByte(5),
                reader.GetBoolean(6),
                reader.GetBoolean(7),
                reader.GetInt64(8),
                reader.GetInt64(9)));
        }
        return list;
    }

    private static async Task<List<KeyScriptRow>> ReadKeysAsync(
        SqlConnection conn, string schema, string table, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandTimeout = 60;
        cmd.CommandText = @"
SELECT
    kc.name,
    kc.type,
    ISNULL(i.type_desc, N'NONCLUSTERED') AS index_type,
    c.name AS column_name,
    ISNULL(ic.is_descending_key, 0) AS is_descending_key,
    ic.key_ordinal
FROM sys.key_constraints AS kc
INNER JOIN sys.tables AS t ON t.object_id = kc.parent_object_id
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
LEFT JOIN sys.indexes AS i ON i.object_id = kc.parent_object_id AND i.index_id = kc.unique_index_id
LEFT JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
LEFT JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE s.name = @schema AND t.name = @table
  AND kc.type IN (N'PK', N'UQ')
ORDER BY kc.name, ic.key_ordinal;";
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", table);

        var map = new Dictionary<string, (string Type, string IndexType, List<IndexKeyColumn> Cols)>(StringComparer.OrdinalIgnoreCase);
        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false))
        {
            var name = reader.GetString(0);
            var type = reader.GetString(1).Trim();
            var indexType = reader.IsDBNull(2) ? "NONCLUSTERED" : reader.GetString(2);
            if (!map.TryGetValue(name, out var entry))
            {
                entry = (type, indexType, new List<IndexKeyColumn>());
                map[name] = entry;
            }
            if (!reader.IsDBNull(3))
            {
                var col = reader.GetString(3);
                var desc = !reader.IsDBNull(4) && reader.GetBoolean(4);
                if (entry.Cols.All(k => !k.Name.Equals(col, StringComparison.OrdinalIgnoreCase)))
                    entry.Cols.Add(new IndexKeyColumn(col, desc));
            }
        }

        return map.Select(kv => new KeyScriptRow(
            kv.Key,
            kv.Value.Type.Equals("PK", StringComparison.OrdinalIgnoreCase),
            kv.Value.Type.Equals("UQ", StringComparison.OrdinalIgnoreCase),
            kv.Value.IndexType.Equals("CLUSTERED", StringComparison.OrdinalIgnoreCase),
            kv.Value.Cols)).ToList();
    }

    private static async Task<List<CheckScriptRow>> ReadChecksAsync(
        SqlConnection conn, string schema, string table, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandTimeout = 60;
        cmd.CommandText = @"
SELECT cc.name, cc.definition, cc.is_disabled
FROM sys.check_constraints AS cc
INNER JOIN sys.tables AS t ON t.object_id = cc.parent_object_id
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = @schema AND t.name = @table
ORDER BY cc.name;";
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", table);
        var list = new List<CheckScriptRow>();
        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false))
            list.Add(new CheckScriptRow(
                reader.GetString(0),
                reader.IsDBNull(1) ? "" : reader.GetString(1),
                reader.GetBoolean(2)));
        return list;
    }

    private static async Task<List<DefaultScriptRow>> ReadDefaultsAsync(
        SqlConnection conn, string schema, string table, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandTimeout = 60;
        cmd.CommandText = @"
SELECT dc.name, c.name AS column_name, dc.definition
FROM sys.default_constraints AS dc
INNER JOIN sys.tables AS t ON t.object_id = dc.parent_object_id
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
INNER JOIN sys.columns AS c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE s.name = @schema AND t.name = @table
ORDER BY dc.name;";
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", table);
        var list = new List<DefaultScriptRow>();
        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false))
            list.Add(new DefaultScriptRow(
                reader.GetString(0),
                reader.GetString(1),
                reader.IsDBNull(2) ? "" : reader.GetString(2)));
        return list;
    }

    private static async Task<List<ForeignKeyScriptRow>> ReadForeignKeysAsync(
        SqlConnection conn, string schema, string table, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandTimeout = 60;
        cmd.CommandText = @"
SELECT
    fk.name,
    pc.name AS parent_col,
    rs.name AS ref_schema,
    rt.name AS ref_table,
    rc.name AS ref_col,
    fk.delete_referential_action_desc,
    fk.update_referential_action_desc,
    fkc.constraint_column_id,
    fk.is_disabled,
    fk.is_not_trusted
FROM sys.foreign_keys AS fk
INNER JOIN sys.tables AS t ON t.object_id = fk.parent_object_id
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
INNER JOIN sys.foreign_key_columns AS fkc ON fkc.constraint_object_id = fk.object_id
INNER JOIN sys.columns AS pc ON pc.object_id = fkc.parent_object_id AND pc.column_id = fkc.parent_column_id
INNER JOIN sys.tables AS rt ON rt.object_id = fk.referenced_object_id
INNER JOIN sys.schemas AS rs ON rs.schema_id = rt.schema_id
INNER JOIN sys.columns AS rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id
WHERE s.name = @schema AND t.name = @table
ORDER BY fk.name, fkc.constraint_column_id;";
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", table);

        var map = new Dictionary<string, (List<string> Cols, string RefSchema, string RefTable, List<string> RefCols, string Del, string Upd, bool Disabled, bool NotTrusted)>(
            StringComparer.OrdinalIgnoreCase);
        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false))
        {
            var name = reader.GetString(0);
            if (!map.TryGetValue(name, out var entry))
            {
                entry = (
                    new List<string>(),
                    reader.GetString(2),
                    reader.GetString(3),
                    new List<string>(),
                    reader.GetString(5),
                    reader.GetString(6),
                    reader.GetBoolean(8),
                    reader.GetBoolean(9));
                map[name] = entry;
            }
            entry.Cols.Add(reader.GetString(1));
            entry.RefCols.Add(reader.GetString(4));
        }

        return map.Select(kv => new ForeignKeyScriptRow(
            kv.Key,
            kv.Value.Cols,
            kv.Value.RefSchema,
            kv.Value.RefTable,
            kv.Value.RefCols,
            kv.Value.Del,
            kv.Value.Upd,
            kv.Value.Disabled,
            kv.Value.NotTrusted)).ToList();
    }

    private static async Task<List<IndexScriptRow>> ReadIndexesAsync(
        SqlConnection conn, string schema, string table, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandTimeout = 60;
        cmd.CommandText = @"
SELECT
    i.name,
    i.is_unique,
    CASE WHEN i.type_desc = N'CLUSTERED' THEN 1 ELSE 0 END AS is_clustered,
    i.is_primary_key,
    i.is_unique_constraint,
    c.name AS column_name,
    ic.is_descending_key,
    ic.is_included_column,
    ic.key_ordinal,
    i.filter_definition
FROM sys.indexes AS i
INNER JOIN sys.tables AS t ON t.object_id = i.object_id
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
INNER JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
INNER JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE s.name = @schema AND t.name = @table
  AND i.name IS NOT NULL
  AND i.type IN (1, 2) -- clustered / nonclustered rowstore only
  AND i.is_hypothetical = 0
ORDER BY i.name, ic.is_included_column, ic.key_ordinal, ic.index_column_id;";
        cmd.Parameters.AddWithValue("@schema", schema);
        cmd.Parameters.AddWithValue("@table", table);

        var map = new Dictionary<string, (
            bool Unique, bool Clustered, bool Pk, bool Uq,
            List<IndexKeyColumn> Keys, List<string> Incl, string? Filter)>(StringComparer.OrdinalIgnoreCase);

        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false))
        {
            var name = reader.GetString(0);
            if (!map.TryGetValue(name, out var entry))
            {
                entry = (
                    reader.GetBoolean(1),
                    reader.GetInt32(2) == 1,
                    reader.GetBoolean(3),
                    reader.GetBoolean(4),
                    new List<IndexKeyColumn>(),
                    new List<string>(),
                    reader.IsDBNull(9) ? null : reader.GetString(9));
                map[name] = entry;
            }

            var colName = reader.GetString(5);
            var desc = reader.GetBoolean(6);
            var included = reader.GetBoolean(7);
            if (included)
            {
                if (!entry.Incl.Contains(colName, StringComparer.OrdinalIgnoreCase))
                    entry.Incl.Add(colName);
            }
            else
            {
                if (entry.Keys.All(k => !k.Name.Equals(colName, StringComparison.OrdinalIgnoreCase)))
                    entry.Keys.Add(new IndexKeyColumn(colName, desc));
            }
        }

        return map.Select(kv => new IndexScriptRow(
            kv.Key,
            kv.Value.Unique,
            kv.Value.Clustered,
            kv.Value.Pk,
            kv.Value.Uq,
            kv.Value.Keys,
            kv.Value.Incl,
            kv.Value.Filter)).ToList();
    }
}
