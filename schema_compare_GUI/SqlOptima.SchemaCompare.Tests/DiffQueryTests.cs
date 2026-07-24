using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class DiffQueryTests
{
    private static List<DifferenceItem> Sample() => new()
    {
        new() { Database = "A", ObjectType = "Tables", ObjectName = "dbo.T1", Status = "Missing in Target", Details = "new" },
        new() { Database = "A", ObjectType = "Views", ObjectName = "dbo.V1", Status = "Definition Mismatch", Details = "changed" },
        new() { Database = "B", ObjectType = "Tables", ObjectName = "dbo.T2", Status = "Extra in Target", Details = "drop?" },
    };

    [Fact]
    public void Filter_Empty_ReturnsAll()
    {
        var r = DiffQuery.Filter(Sample(), "");
        Assert.Equal(3, r.Count);
    }

    [Fact]
    public void Filter_ByObjectName_IsCaseInsensitive()
    {
        var r = DiffQuery.Filter(Sample(), "t1");
        Assert.Single(r);
        Assert.Equal("dbo.T1", r[0].ObjectName);
    }

    [Fact]
    public void Filter_ByStatus()
    {
        var r = DiffQuery.Filter(Sample(), "mismatch");
        Assert.Single(r);
        Assert.Equal(DiffKind.Update, r[0].Kind);
    }

    [Fact]
    public void CountByKind_TalliesCorrectly()
    {
        var (add, upd, extra, total) = DiffQuery.CountByKind(Sample());
        Assert.Equal(1, add);
        Assert.Equal(1, upd);
        Assert.Equal(1, extra);
        Assert.Equal(3, total);
    }

    [Fact]
    public void GroupByDatabaseThenType_OrdersDatabases()
    {
        var groups = DiffQuery.GroupByDatabaseThenType(Sample()).ToList();
        Assert.Equal(2, groups.Count);
        Assert.Equal("A", groups[0].Key);
        Assert.Equal("B", groups[1].Key);
    }
}

public class CompareTargetResolverTests
{
    [Fact]
    public void OneToOne_DefaultsToSourceName_WhenNothingChecked()
    {
        var (targets, list) = CompareTargetResolver.Resolve(
            CompareMode.OneToOne, "Template", Array.Empty<string>(), null);
        Assert.Equal(new[] { "Template" }, targets);
        Assert.Null(list);
    }

    [Fact]
    public void OneToOne_UsesFirstCheckedOnly()
    {
        var (targets, list) = CompareTargetResolver.Resolve(
            CompareMode.OneToOne, "Template", new[] { "Db1", "Db2" }, null);
        Assert.Equal(new[] { "Db1" }, targets);
        Assert.Null(list);
    }

    [Fact]
    public void OneToMany_PrefersCheckedOverListFile()
    {
        var (targets, list) = CompareTargetResolver.Resolve(
            CompareMode.OneToMany, "Template", new[] { "T1", "T2" }, @"C:\list.json");
        Assert.Equal(new[] { "T1", "T2" }, targets);
        Assert.Null(list);
    }

    [Fact]
    public void OneToMany_UsesListFile_WhenNoChecks()
    {
        var (targets, list) = CompareTargetResolver.Resolve(
            CompareMode.OneToMany, "Template", Array.Empty<string>(), @"C:\list.json");
        Assert.Empty(targets);
        Assert.Equal(@"C:\list.json", list);
    }

    [Fact]
    public void OneToMany_Throws_WhenNoTargetsAndNoFile()
    {
        Assert.Throws<InvalidOperationException>(() =>
            CompareTargetResolver.Resolve(CompareMode.OneToMany, "Template", Array.Empty<string>(), "  "));
    }

    [Fact]
    public void OneToMany_DedupesCheckedTargets()
    {
        var (targets, _) = CompareTargetResolver.Resolve(
            CompareMode.OneToMany, "Template", new[] { "A", "a", "B" }, null);
        Assert.Equal(2, targets.Count);
    }
}

public class CappedStringBufferTests
{
    [Fact]
    public void AppendLine_Truncates_WhenOverMax()
    {
        var buf = new CappedStringBuffer(5000);
        for (var i = 0; i < 2000; i++)
            buf.AppendLine(new string('x', 80));

        Assert.True(buf.Length <= 5000);
        Assert.Contains("truncated", buf.Snapshot(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Clear_ResetsLength()
    {
        var buf = new CappedStringBuffer();
        buf.AppendLine("hello");
        buf.Clear();
        Assert.Equal(0, buf.Length);
        Assert.Equal("", buf.Snapshot());
    }

    [Fact]
    public void Constructor_RejectsTinyMax()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new CappedStringBuffer(100));
    }
}
