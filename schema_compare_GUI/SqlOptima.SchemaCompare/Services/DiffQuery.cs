// =============================================================================
// Module:   SqlOptima.SchemaCompare.Services.DiffQuery
// Purpose:  Filtering, grouping, and counting of schema difference items for the explorer tree and summary counters.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using SqlOptima.SchemaCompare.Models;

namespace SqlOptima.SchemaCompare.Services;

/// <summary>
/// Pure helpers for path resolution, request shaping, filtering, and log capping — unit-test friendly.
/// Prefers the engine bundled under the GUI folder (<c>schema_compare/</c>) so the
/// whole tool can ship as a single zip; falls back to a sibling repo folder.
/// </summary>
public static class SchemaComparePaths
{
    /// <summary>
    /// Walks up from <paramref name="startDirectory"/> looking for the GUI root
    /// (folder that contains <c>tools/Invoke-CompareForGui.ps1</c> and the solution
    /// or the bundled <c>schema_compare/Compare-SqlSchema.ps1</c>).
    /// </summary>
    public static bool TryResolveGuiRoot(string startDirectory, out string guiRoot, out string compareRoot)
    {
        guiRoot = "";
        compareRoot = "";
        var dir = new DirectoryInfo(startDirectory);
        for (var i = 0; i < 12 && dir != null; i++, dir = dir.Parent)
        {
            // 1) Preferred: self-contained layout (engine nested under the GUI root)
            if (TryMatchGuiRoot(dir.FullName, out guiRoot, out compareRoot))
                return true;

            // 2) Named GUI folder with sibling engine (legacy monorepo layout)
            if (dir.Name.Equals("schema_compare_GUI", StringComparison.OrdinalIgnoreCase) &&
                dir.Parent != null)
            {
                var sibling = Path.Combine(dir.Parent.FullName, "schema_compare");
                if (File.Exists(Path.Combine(sibling, "Compare-SqlSchema.ps1")) &&
                    File.Exists(Path.Combine(dir.FullName, "tools", "Invoke-CompareForGui.ps1")))
                {
                    guiRoot = dir.FullName;
                    compareRoot = sibling;
                    return true;
                }
            }

            // 3) Parent that contains both schema_compare_GUI and schema_compare
            var nestedGui = Path.Combine(dir.FullName, "schema_compare_GUI");
            if (Directory.Exists(nestedGui) &&
                TryMatchGuiRoot(nestedGui, out guiRoot, out compareRoot))
                return true;

            if (Directory.Exists(nestedGui))
            {
                var sibling = Path.Combine(dir.FullName, "schema_compare");
                if (File.Exists(Path.Combine(sibling, "Compare-SqlSchema.ps1")) &&
                    File.Exists(Path.Combine(nestedGui, "tools", "Invoke-CompareForGui.ps1")))
                {
                    guiRoot = nestedGui;
                    compareRoot = sibling;
                    return true;
                }
            }
        }
        return false;
    }

    /// <summary>
    /// True when <paramref name="candidateGuiRoot"/> looks like a complete install:
    /// bridge script present and a bundled <c>schema_compare/Compare-SqlSchema.ps1</c>.
    /// </summary>
    public static bool TryMatchGuiRoot(string candidateGuiRoot, out string guiRoot, out string compareRoot)
    {
        guiRoot = "";
        compareRoot = "";
        var bridge = Path.Combine(candidateGuiRoot, "tools", "Invoke-CompareForGui.ps1");
        var bundled = Path.Combine(candidateGuiRoot, "schema_compare", "Compare-SqlSchema.ps1");
        if (File.Exists(bridge) && File.Exists(bundled))
        {
            guiRoot = candidateGuiRoot;
            compareRoot = Path.Combine(candidateGuiRoot, "schema_compare");
            return true;
        }
        return false;
    }
}

public static class DiffQuery
{
    public static IReadOnlyList<DifferenceItem> Filter(IEnumerable<DifferenceItem> items, string? filter)
    {
        var list = items as IList<DifferenceItem> ?? items.ToList();
        if (string.IsNullOrWhiteSpace(filter)) return list.ToList();

        var raw = filter.Trim();
        var tokens = raw.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        return list.Where(d => tokens.All(t => MatchToken(d, t))).ToList();
    }

    private static bool MatchToken(DifferenceItem d, string token)
    {
        // Smart filters: table:customer | type:view | added | modified | removed | schema:dbo | warning
        var colon = token.IndexOf(':');
        if (colon > 0)
        {
            var key = token[..colon].ToLowerInvariant();
            var val = token[(colon + 1)..];
            return key switch
            {
                "table" => Contains(d.ObjectType, "table") && (string.IsNullOrEmpty(val) || Contains(d.ObjectName, val)),
                "view" => Contains(d.ObjectType, "view") && (string.IsNullOrEmpty(val) || Contains(d.ObjectName, val)),
                "procedure" or "proc" => Contains(d.ObjectType, "procedure") && (string.IsNullOrEmpty(val) || Contains(d.ObjectName, val)),
                "function" => Contains(d.ObjectType, "function") && (string.IsNullOrEmpty(val) || Contains(d.ObjectName, val)),
                "trigger" => Contains(d.ObjectType, "trigger") && (string.IsNullOrEmpty(val) || Contains(d.ObjectName, val)),
                "index" => Contains(d.ObjectType, "index") && (string.IsNullOrEmpty(val) || Contains(d.ObjectName, val)),
                "type" or "object" => Contains(d.ObjectType, val) || Contains(d.ObjectName, val),
                "schema" => Contains(d.ObjectName, val) || Contains(d.Details, val),
                "db" or "database" => Contains(d.Database, val),
                "status" => Contains(d.Status, val) || Contains(d.ActionLabel, val),
                _ => Contains(d.ObjectName, token) || Contains(d.ObjectType, token)
                     || Contains(d.Status, token) || Contains(d.Database, token) || Contains(d.Details, token)
            };
        }

        return token.ToLowerInvariant() switch
        {
            "added" or "add" or "missing" => d.Kind == DiffKind.Add,
            "modified" or "changed" or "update" or "upd" => d.Kind == DiffKind.Update,
            "removed" or "extra" or "drop" => d.Kind == DiffKind.Extra,
            "warning" or "manual" => Contains(d.Status, "extra") || Contains(d.Details, "manual")
                                     || Contains(d.Details, "risk") || Contains(d.ActionLabel, "Extra"),
            _ => Contains(d.ObjectName, token) || Contains(d.ObjectType, token)
                 || Contains(d.Status, token) || Contains(d.Database, token) || Contains(d.Details, token)
        };
    }

    public static (int Add, int Update, int Extra, int Total) CountByKind(IEnumerable<DifferenceItem> items)
    {
        var add = 0;
        var upd = 0;
        var extra = 0;
        var total = 0;
        foreach (var d in items)
        {
            total++;
            switch (d.Kind)
            {
                case DiffKind.Add: add++; break;
                case DiffKind.Update: upd++; break;
                case DiffKind.Extra: extra++; break;
            }
        }
        return (add, upd, extra, total);
    }

    public static IEnumerable<IGrouping<string, DifferenceItem>> GroupByDatabaseThenType(
        IEnumerable<DifferenceItem> items)
    {
        return items
            .GroupBy(d => string.IsNullOrWhiteSpace(d.Database) ? "(database)" : d.Database)
            .OrderBy(g => g.Key);
    }

    /// <summary>Friendly folder label + icon key for object type groups.</summary>
    public static (string Label, string IconKey) DescribeObjectType(string objectType)
    {
        var t = objectType ?? "";
        var lower = t.ToLowerInvariant();
        if (lower.Contains("table")) return ($"Tables", "table");
        if (lower.Contains("view")) return ($"Views", "view");
        if (lower.Contains("procedure") || lower.Contains("proc")) return ($"Stored Procedures", "proc");
        if (lower.Contains("function")) return ($"Functions", "func");
        if (lower.Contains("trigger")) return ($"Triggers", "trig");
        if (lower.Contains("index")) return ($"Indexes", "index");
        if (lower.Contains("synonym")) return ($"Synonyms", "other");
        if (lower.Contains("sequence")) return ($"Sequences", "other");
        if (lower.Contains("schema")) return ($"Schemas", "other");
        if (lower.Contains("type")) return ($"Types", "other");
        return (string.IsNullOrWhiteSpace(t) ? "Objects" : t, "type");
    }

    private static bool Contains(string? hay, string needle) =>
        !string.IsNullOrEmpty(hay) &&
        hay.Contains(needle, StringComparison.OrdinalIgnoreCase);
}

/// <summary>
/// Caps in-memory log growth so long compares cannot balloon UI memory.
/// </summary>
public sealed class CappedStringBuffer
{
    private readonly int _maxChars;
    private readonly object _gate = new();
    private string _text = "";

    public CappedStringBuffer(int maxChars = 512_000)
    {
        if (maxChars < 4096) throw new ArgumentOutOfRangeException(nameof(maxChars));
        _maxChars = maxChars;
    }

    public int MaxChars => _maxChars;
    public int Length { get { lock (_gate) return _text.Length; } }

    public void AppendLine(string? line)
    {
        if (line == null) return;
        lock (_gate)
        {
            _text += line;
            if (!line.EndsWith('\n')) _text += Environment.NewLine;
            if (_text.Length > _maxChars)
            {
                var keep = _maxChars * 3 / 4;
                _text = "[... log truncated for memory ...]\r\n" + _text[^keep..];
            }
        }
    }

    public string Snapshot()
    {
        lock (_gate) return _text;
    }

    public void Clear()
    {
        lock (_gate) _text = "";
    }
}

public static class CompareTargetResolver
{
    /// <summary>
    /// Resolves which destinations to pass to the engine given UI mode/selection.
    /// </summary>
    public static (IReadOnlyList<string> Targets, string? ListFile) Resolve(
        CompareMode mode,
        string sourceDatabase,
        IReadOnlyList<string> checkedTargets,
        string? listFilePath)
    {
        var checkedList = checkedTargets?.Where(t => !string.IsNullOrWhiteSpace(t)).Distinct(StringComparer.OrdinalIgnoreCase).ToList()
                          ?? new List<string>();
        var listFile = string.IsNullOrWhiteSpace(listFilePath) ? null : listFilePath.Trim();

        if (mode == CompareMode.OneToOne)
        {
            if (checkedList.Count == 0)
                return (new[] { sourceDatabase }, null);
            return (new[] { checkedList[0] }, null);
        }

        // One-to-Many: prefer explicit checks; otherwise list file.
        if (checkedList.Count > 0)
            return (checkedList, null);
        if (listFile != null)
            return (Array.Empty<string>(), listFile);

        throw new InvalidOperationException(
            "One-to-Many requires checked destination databases or a destination list file.");
    }
}
