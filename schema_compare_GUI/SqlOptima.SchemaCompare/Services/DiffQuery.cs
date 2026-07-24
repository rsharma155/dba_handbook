using SqlOptima.SchemaCompare.Models;

namespace SqlOptima.SchemaCompare.Services;

/// <summary>
/// Pure helpers for path resolution, request shaping, filtering, and log capping — unit-test friendly.
/// </summary>
public static class SchemaComparePaths
{
    public static bool TryResolveGuiRoot(string startDirectory, out string guiRoot, out string compareRoot)
    {
        guiRoot = "";
        compareRoot = "";
        var dir = new DirectoryInfo(startDirectory);
        for (var i = 0; i < 10 && dir != null; i++, dir = dir.Parent)
        {
            if (dir.Name.Equals("schema_compare_GUI", StringComparison.OrdinalIgnoreCase))
            {
                var sibling = Path.Combine(dir.Parent!.FullName, "schema_compare");
                if (File.Exists(Path.Combine(sibling, "Compare-SqlSchema.ps1")))
                {
                    guiRoot = dir.FullName;
                    compareRoot = sibling;
                    return true;
                }
            }

            var nested = Path.Combine(dir.FullName, "schema_compare_GUI");
            if (Directory.Exists(nested))
            {
                var sibling = Path.Combine(dir.FullName, "schema_compare");
                if (File.Exists(Path.Combine(sibling, "Compare-SqlSchema.ps1")))
                {
                    guiRoot = nested;
                    compareRoot = sibling;
                    return true;
                }
            }
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

        return list.Where(d =>
                Contains(d.ObjectName, filter) ||
                Contains(d.ObjectType, filter) ||
                Contains(d.Status, filter) ||
                Contains(d.Database, filter) ||
                Contains(d.Details, filter))
            .ToList();
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
