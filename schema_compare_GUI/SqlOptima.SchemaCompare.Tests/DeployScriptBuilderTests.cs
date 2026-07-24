using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class DeployScriptBuilderTests
{
    [Fact]
    public void ExtractIncludeOrder_IgnoresCommentedAndKeepsOrder()
    {
        var master = """
            USE [TenantA];
            GO
            :r auto_TenantA__Table__Customers__Create.sql
            GO
            -- :r manual_TenantA__PK__Customers.sql
            :r auto_TenantA__Index__IX_Customers.sql
            GO
            """;
        var order = DeployScriptBuilder.ExtractIncludeOrder(master);
        Assert.Equal(new[]
        {
            "auto_TenantA__Table__Customers__Create.sql",
            "auto_TenantA__Index__IX_Customers.sql"
        }, order);
    }

    [Fact]
    public void Build_MissingFolder_ReturnsEmpty()
    {
        var result = DeployScriptBuilder.Build(Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N")));
        Assert.Empty(result.Databases);
        Assert.False(result.HasAuto);
        Assert.False(result.HasManual);
    }

    [Fact]
    public void Build_InlinesAutoScripts_AndSurfacesManualWarning()
    {
        var dir = Path.Combine(Path.GetTempPath(), "DeployBuild_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "auto_Db1__Table__A__Create.sql"),
                "/* auto A */\r\nUSE [Db1];\r\nCREATE TABLE dbo.A (Id int);");
            File.WriteAllText(Path.Combine(dir, "auto_Db1__Index__IX_A.sql"),
                "/* auto IX */\r\nUSE [Db1];\r\nCREATE INDEX IX_A ON dbo.A(Id);");
            File.WriteAllText(Path.Combine(dir, "manual_Db1__PK__A.sql"),
                "/* MANUAL */\r\nUSE [Db1];\r\nALTER TABLE dbo.A ADD CONSTRAINT PK_A PRIMARY KEY (Id);");
            File.WriteAllText(Path.Combine(dir, "_master_auto_only.sql"),
                "/* Database : Db1 */\r\nUSE [Db1];\r\nGO\r\n" +
                ":r auto_Db1__Table__A__Create.sql\r\nGO\r\n" +
                ":r auto_Db1__Index__IX_A.sql\r\nGO\r\n" +
                "-- :r manual_Db1__PK__A.sql\r\n");

            var result = DeployScriptBuilder.Build(dir);

            Assert.Single(result.Databases);
            var db = result.Databases[0];
            Assert.Equal("Db1", db.Database);
            Assert.Equal(2, db.AutoFileCount);
            Assert.Single(db.ManualFiles);
            Assert.Contains("CREATE TABLE dbo.A", db.AutoDeployText);
            Assert.Contains("CREATE INDEX IX_A", db.AutoDeployText);
            Assert.DoesNotContain(":r ", db.AutoDeployText);

            var deploy = result.BuildCombinedDeployScript();
            Assert.Contains("DEPLOYABLE SYNC SCRIPT", deploy);
            Assert.Contains("CREATE TABLE dbo.A", deploy);
            Assert.Contains("Manual scripts", deploy);
            Assert.DoesNotContain(":r ", deploy);

            var manual = result.BuildManualScript();
            Assert.Contains("MANUAL ACTION REQUIRED", manual);
            Assert.Contains("DO NOT RUN BLINDLY", manual);
            Assert.Contains("PK_A", manual);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch { /* ignore */ }
        }
    }

    [Fact]
    public void Build_MultiDb_ProducesSeparateSections()
    {
        var root = Path.Combine(Path.GetTempPath(), "DeployMulti_" + Guid.NewGuid().ToString("N"));
        var a = Path.Combine(root, "TenantA");
        var b = Path.Combine(root, "TenantB");
        Directory.CreateDirectory(a);
        Directory.CreateDirectory(b);
        try
        {
            File.WriteAllText(Path.Combine(a, "auto_TenantA__T.sql"), "USE [TenantA];\r\nCREATE TABLE dbo.T(Id int);");
            File.WriteAllText(Path.Combine(a, "_master_auto_only.sql"),
                "/* Database : TenantA */\r\n:r auto_TenantA__T.sql\r\n");
            File.WriteAllText(Path.Combine(b, "auto_TenantB__T.sql"), "USE [TenantB];\r\nCREATE TABLE dbo.T(Id int);");
            File.WriteAllText(Path.Combine(b, "_master_auto_only.sql"),
                "/* Database : TenantB */\r\n:r auto_TenantB__T.sql\r\n");

            var result = DeployScriptBuilder.Build(root);
            Assert.Equal(2, result.Databases.Count);
            Assert.Equal(2, result.AutoFileCount);

            var deploy = result.BuildCombinedDeployScript();
            Assert.Contains("DATABASE: TenantA", deploy);
            Assert.Contains("DATABASE: TenantB", deploy);
            Assert.Contains("USE [TenantA]", deploy);
            Assert.Contains("USE [TenantB]", deploy);
        }
        finally
        {
            try { Directory.Delete(root, true); } catch { /* ignore */ }
        }
    }

    [Fact]
    public void ContainsDropTable_DetectsDropTable()
    {
        Assert.True(DeployScriptBuilder.ContainsDropTable("IF OBJECT_ID(N'[dbo].[T]') IS NOT NULL\r\n    DROP TABLE [dbo].[T];"));
        Assert.False(DeployScriptBuilder.ContainsDropTable("DROP VIEW [dbo].[V];"));
        Assert.False(DeployScriptBuilder.ContainsDropTable("ALTER TABLE [dbo].[T] DROP COLUMN X;"));
    }

    [Fact]
    public void Build_MovesDropTableOutOfAutoDeploy()
    {
        var dir = Path.Combine(Path.GetTempPath(), "DeployDrop_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "auto_Db1__T__cleanup_drop.sql"),
                "USE [Db1];\r\nDROP TABLE [dbo].[Orphan];");
            File.WriteAllText(Path.Combine(dir, "auto_Db1__T__column.sql"),
                "USE [Db1];\r\nALTER TABLE [dbo].[T] ADD X int NULL;");
            File.WriteAllText(Path.Combine(dir, "_master_auto_only.sql"),
                "/* Database : Db1 */\r\n" +
                ":r auto_Db1__T__cleanup_drop.sql\r\n" +
                ":r auto_Db1__T__column.sql\r\n");

            var result = DeployScriptBuilder.Build(dir);
            Assert.True(result.HasManual);
            Assert.Equal(1, result.AutoFileCount);
            Assert.DoesNotContain("DROP TABLE", result.BuildCombinedDeployScript(), StringComparison.OrdinalIgnoreCase);
            Assert.Contains("DROP TABLE", result.BuildManualScript(), StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch { /* ignore */ }
        }
    }
}
