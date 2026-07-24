using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class CompareEngineHelperTests
{
    [Fact]
    public void BuildRequestDictionary_IncludesCoreFields()
    {
        var src = new ConnectionInfo { Instance = "SRC", Database = "DbA", Port = 1433, Auth = AuthMode.Windows };
        var tgt = new ConnectionInfo { Instance = "TGT", Auth = AuthMode.Sql, UserName = "sa" };
        var opt = new CompareOptions
        {
            GenerateSyncScript = true,
            IncludeDrops = true,
            NetworkProtocol = "NamedPipes",
            ExcludeSchemas = "sys,guest",
            OutputPath = @"D:\out"
        };

        var dict = CompareEngine.BuildRequestDictionary(
            src, tgt, CompareMode.OneToMany, new[] { "T1", "T2" }, null, opt, @"D:\result.json",
            compareScriptOverride: @"D:\Compare-SqlSchema.ps1");

        Assert.Equal("SRC", dict["SourceSqlInstance"]);
        Assert.Equal("TGT", dict["TargetSqlInstance"]);
        Assert.Equal(1433, dict["SourcePort"]);
        Assert.Equal("DbA", dict["SourceDatabase"]);
        Assert.Equal("OneToMany", dict["Mode"]);
        Assert.Equal("NamedPipes", dict["NetworkProtocol"]);
        Assert.True((bool)dict["GenerateSyncScript"]!);
        Assert.True((bool)dict["IncludeDrops"]!);
        Assert.Equal(@"D:\result.json", dict["ResultJsonPath"]);
        Assert.Equal(@"D:\Compare-SqlSchema.ps1", dict["CompareScript"]);
        var schemas = Assert.IsType<string[]>(dict["ExcludeSchema"]);
        Assert.Contains("sys", schemas);
        Assert.Contains("guest", schemas);
    }

    [Fact]
    public async Task BuildScriptPreviewAsync_MissingFolder_ReturnsMessage()
    {
        var text = await CompareEngine.BuildScriptPreviewAsync(
            Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N")), CancellationToken.None);
        Assert.Contains("No sync scripts", text);
    }

    [Fact]
    public async Task BuildScriptPreviewAsync_ReadsMasterAndCapsSize()
    {
        var dir = Path.Combine(Path.GetTempPath(), "PreviewTest_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var big = new string('A', 50_000);
            await File.WriteAllTextAsync(Path.Combine(dir, "_master_auto_only.sql"), big);
            var text = await CompareEngine.BuildScriptPreviewAsync(dir, CancellationToken.None);
            Assert.Contains("master auto-only", text, StringComparison.OrdinalIgnoreCase);
            Assert.True(text.Length > 1000);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch { /* ignore */ }
        }
    }

    [Fact]
    public void ResolvePowerShell_ReturnsExistingExecutableName()
    {
        var ps = CompareEngine.ResolvePowerShell();
        Assert.False(string.IsNullOrWhiteSpace(ps));
        Assert.True(
            ps.EndsWith("powershell.exe", StringComparison.OrdinalIgnoreCase) ||
            ps.EndsWith("pwsh.exe", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void SchemaComparePaths_ResolvesFromGuiFolder()
    {
        // Walk from this test assembly up to repo schema_compare_GUI
        var start = AppContext.BaseDirectory;
        var ok = SchemaComparePaths.TryResolveGuiRoot(start, out var gui, out var compare);
        Assert.True(ok);
        Assert.True(Directory.Exists(gui));
        Assert.True(File.Exists(Path.Combine(compare, "Compare-SqlSchema.ps1")));
        Assert.True(File.Exists(Path.Combine(gui, "tools", "Invoke-CompareForGui.ps1")));
    }

    [Fact]
    public void CompareEngine_DefaultConstructor_FindsBridge()
    {
        using var engine = new CompareEngine(AppContext.BaseDirectory);
        Assert.True(File.Exists(engine.BridgeScriptPath));
        Assert.True(Directory.Exists(engine.SchemaCompareRoot));
        engine.Shutdown();
    }
}
