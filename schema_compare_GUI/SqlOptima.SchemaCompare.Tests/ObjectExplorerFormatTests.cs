// =============================================================================
// Module:   SqlOptima.SchemaCompare.Tests.ObjectExplorerFormatTests
// Purpose:  Unit tests for Object Explorer folder labels, icons, and child formatting.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class ObjectExplorerFormatTests
{
    [Theory]
    [InlineData("varchar", 50, (byte)0, (byte)0, "varchar(50)")]
    [InlineData("nvarchar", -1, (byte)0, (byte)0, "nvarchar(max)")]
    [InlineData("nvarchar", 100, (byte)0, (byte)0, "nvarchar(100)")]
    [InlineData("decimal", 0, (byte)18, (byte)2, "decimal(18,2)")]
    [InlineData("int", 4, (byte)10, (byte)0, "int")]
    [InlineData("datetime2", 0, (byte)0, (byte)7, "datetime2(7)")]
    [InlineData("datetime2", 0, (byte)0, (byte)0, "datetime2(0)")]
    [InlineData("time", 0, (byte)0, (byte)3, "time(3)")]
    public void FormatDataType_FormatsCommonTypes(
        string type, int maxLen, byte precision, byte scale, string expected)
    {
        Assert.Equal(expected, ObjectExplorerFormat.FormatDataType(type, maxLen, precision, scale));
    }

    [Fact]
    public void FormatColumnDisplay_IncludesNullabilityAndIdentity()
    {
        var text = ObjectExplorerFormat.FormatColumnDisplay(
            "Id", "int", 4, 10, 0, isNullable: false, isIdentity: true);
        Assert.Equal("Id (int, NOT NULL IDENTITY)", text);
    }

    [Fact]
    public void QuoteIdent_EscapesBrackets()
    {
        Assert.Equal("[Weird]]Name]", ObjectExplorerFormat.QuoteIdent("Weird]Name"));
        Assert.Equal("[dbo].[Orders]", ObjectExplorerFormat.BracketName("dbo", "Orders"));
    }

    [Fact]
    public void FolderLabel_And_Icon_MapKinds()
    {
        Assert.Equal("Columns", ObjectExplorerFormat.FolderLabel(TableFolderKind.Columns));
        Assert.Equal("Keys", ObjectExplorerFormat.FolderLabel(TableFolderKind.Keys));
        Assert.Equal("column", ObjectExplorerFormat.FolderIcon(TableFolderKind.Columns));
        Assert.Equal("key", ObjectExplorerFormat.FolderIcon(TableFolderKind.Keys));
        Assert.Equal("index", ObjectExplorerFormat.FolderIcon(TableFolderKind.Indexes));
    }

    [Fact]
    public void BuildCreateTableScript_IncludesAllConstraintTypes()
    {
        var columns = new[]
        {
            new ColumnScriptRow(1, "Id", "int", 4, 10, 0, false, true, 1, 1),
            new ColumnScriptRow(2, "Name", "nvarchar", 100, 0, 0, false, false),
            new ColumnScriptRow(3, "CustomerId", "int", 4, 10, 0, true, false),
            new ColumnScriptRow(4, "Status", "varchar", 20, 0, 0, false, false),
            new ColumnScriptRow(5, "CreatedAt", "datetime2", 0, 0, 3, false, false),
        };
        var keys = new[]
        {
            new KeyScriptRow("PK_Orders", true, false, true, new[]
            {
                new IndexKeyColumn("Id", false),
            }),
            new KeyScriptRow("UQ_Orders_Name", false, true, false, new[]
            {
                new IndexKeyColumn("Name", true),
            }),
        };
        var checks = new[]
        {
            new CheckScriptRow("CK_Orders_Status", "([Status]<>'')"),
        };
        var defaults = new[]
        {
            new DefaultScriptRow("DF_Orders_Status", "Status", "('New')"),
        };
        var fks = new[]
        {
            new ForeignKeyScriptRow(
                "FK_Orders_Customers",
                new[] { "CustomerId" },
                "dbo",
                "Customers",
                new[] { "Id" },
                "CASCADE",
                "NO_ACTION"),
        };
        var indexes = new[]
        {
            new IndexScriptRow("PK_Orders", true, true, true, false,
                new[] { new IndexKeyColumn("Id", false) }, Array.Empty<string>(), null),
            new IndexScriptRow("UQ_Orders_Name", true, false, false, true,
                new[] { new IndexKeyColumn("Name", true) }, Array.Empty<string>(), null),
            new IndexScriptRow("IX_Orders_CustomerId", false, false, false, false,
                new[] { new IndexKeyColumn("CustomerId", false) },
                new[] { "Status", "CreatedAt" },
                "([CustomerId] IS NOT NULL)"),
            new IndexScriptRow("UX_Orders_Status", true, false, false, false,
                new[] { new IndexKeyColumn("Status", false) }, Array.Empty<string>(), null),
        };

        var script = ObjectExplorerFormat.BuildCreateTableScript(
            "dbo", "Orders", columns, keys, checks, defaults, fks, indexes);

        Assert.Contains("CREATE TABLE [dbo].[Orders]", script);
        Assert.Contains("[Id] int IDENTITY(1,1) NOT NULL", script);
        Assert.Contains("[CreatedAt] datetime2(3) NOT NULL", script);
        Assert.Contains("CONSTRAINT [DF_Orders_Status] DEFAULT ('New')", script);
        Assert.Contains("CONSTRAINT [PK_Orders] PRIMARY KEY CLUSTERED ([Id] ASC)", script);
        Assert.Contains("CONSTRAINT [UQ_Orders_Name] UNIQUE NONCLUSTERED ([Name] DESC)", script);
        Assert.Contains("CONSTRAINT [CK_Orders_Status] CHECK ([Status]<>'')", script);
        Assert.Contains("ADD CONSTRAINT [FK_Orders_Customers] FOREIGN KEY ([CustomerId])", script);
        Assert.Contains("REFERENCES [dbo].[Customers] ([Id])", script);
        Assert.Contains("ON DELETE CASCADE", script);
        Assert.Contains("CREATE NONCLUSTERED INDEX [IX_Orders_CustomerId] ON [dbo].[Orders]", script);
        Assert.Contains("INCLUDE ([Status], [CreatedAt])", script);
        Assert.Contains("WHERE ([CustomerId] IS NOT NULL)", script);
        Assert.Contains("CREATE UNIQUE NONCLUSTERED INDEX [UX_Orders_Status] ON [dbo].[Orders]", script);
        Assert.DoesNotContain("CREATE CLUSTERED INDEX [PK_Orders]", script);
        Assert.DoesNotContain("CREATE UNIQUE NONCLUSTERED INDEX [UQ_Orders_Name]", script);
    }

    [Fact]
    public void BuildCreateTableScript_FallsBackToIndexWhenKeyColumnsEmpty()
    {
        var columns = new[]
        {
            new ColumnScriptRow(1, "Id", "int", 4, 10, 0, false, false),
            new ColumnScriptRow(2, "Code", "varchar", 20, 0, 0, false, false),
        };
        var keys = new[]
        {
            new KeyScriptRow("PK_T", true, false, true, Array.Empty<IndexKeyColumn>()),
        };
        var indexes = new[]
        {
            new IndexScriptRow("PK_T", true, true, true, false,
                new[] { new IndexKeyColumn("Id", false) }, Array.Empty<string>(), null),
            new IndexScriptRow("UQ_T_Code", true, false, false, true,
                new[] { new IndexKeyColumn("Code", false) }, Array.Empty<string>(), null),
        };

        var script = ObjectExplorerFormat.BuildCreateTableScript(
            "dbo", "T", columns, keys, Array.Empty<CheckScriptRow>(),
            Array.Empty<DefaultScriptRow>(), Array.Empty<ForeignKeyScriptRow>(), indexes);

        Assert.Contains("CONSTRAINT [PK_T] PRIMARY KEY CLUSTERED ([Id] ASC)", script);
        Assert.Contains("CONSTRAINT [UQ_T_Code] UNIQUE NONCLUSTERED ([Code] ASC)", script);
        Assert.DoesNotContain("PRIMARY KEY CLUSTERED ()", script);
    }

    [Fact]
    public void BuildCreateTableScript_EmitsNocheckForDisabledConstraints()
    {
        var columns = new[]
        {
            new ColumnScriptRow(1, "Id", "int", 4, 10, 0, false, false),
            new ColumnScriptRow(2, "ParentId", "int", 4, 10, 0, true, false),
            new ColumnScriptRow(3, "Flag", "int", 4, 10, 0, false, false),
        };
        var checks = new[]
        {
            new CheckScriptRow("CK_T_Flag", "([Flag]>=(0))", IsDisabled: true),
        };
        var fks = new[]
        {
            new ForeignKeyScriptRow(
                "FK_T_Parent",
                new[] { "ParentId" },
                "dbo",
                "T",
                new[] { "Id" },
                "NO_ACTION",
                "NO_ACTION",
                IsDisabled: true,
                IsNotTrusted: true),
        };

        var script = ObjectExplorerFormat.BuildCreateTableScript(
            "dbo", "T", columns, Array.Empty<KeyScriptRow>(), checks,
            Array.Empty<DefaultScriptRow>(), fks, Array.Empty<IndexScriptRow>());

        Assert.Contains("CONSTRAINT [CK_T_Flag] CHECK ([Flag]>=(0))", script);
        Assert.Contains("ALTER TABLE [dbo].[T] NOCHECK CONSTRAINT [CK_T_Flag];", script);
        Assert.Contains("ALTER TABLE [dbo].[T] WITH NOCHECK", script);
        Assert.Contains("ADD CONSTRAINT [FK_T_Parent] FOREIGN KEY ([ParentId])", script);
        Assert.Contains("ALTER TABLE [dbo].[T] NOCHECK CONSTRAINT [FK_T_Parent];", script);
    }

    [Fact]
    public void MergeConstraintKeys_FillsMissingUniqueFromIndexes()
    {
        var keys = new[]
        {
            new KeyScriptRow("PK_T", true, false, true, Array.Empty<IndexKeyColumn>()),
        };
        var indexes = new[]
        {
            new IndexScriptRow("PK_T", true, true, true, false,
                new[] { new IndexKeyColumn("Id", true) }, Array.Empty<string>(), null),
            new IndexScriptRow("UQ_T", true, false, false, true,
                new[] { new IndexKeyColumn("Code", false) }, Array.Empty<string>(), null),
        };

        var merged = ObjectExplorerFormat.MergeConstraintKeys(keys, indexes);
        Assert.Equal(2, merged.Count);
        Assert.Equal("Id", merged[0].Columns[0].Name);
        Assert.True(merged[0].Columns[0].IsDescending);
        Assert.Contains(merged, k => k.Name == "UQ_T" && k.IsUnique);
    }
}
