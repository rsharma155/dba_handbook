// =============================================================================
// Module:   SqlOptima.SchemaCompare.Tests.ObjectDiffDetailsTests
// Purpose:  Unit tests for object-name parsing and type normalization used by
//           the Source | Target Object Details compare view.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class ObjectDiffDetailsTests
{
    [Theory]
    [InlineData("[dbo].[Companies]", "dbo", "Companies")]
    [InlineData("[CRM].[Customers]", "CRM", "Customers")]
    [InlineData("dbo.Companies", "dbo", "Companies")]
    [InlineData("[Companies]", "dbo", "Companies")]
    [InlineData("Companies", "dbo", "Companies")]
    public void TryParseObjectName_AcceptsCommonFormats(string input, string schema, string name)
    {
        Assert.True(ObjectExplorerFormat.TryParseObjectName(input, out var s, out var n));
        Assert.Equal(schema, s);
        Assert.Equal(name, n);
    }

    [Fact]
    public void TryParseObjectName_RejectsEmpty()
    {
        Assert.False(ObjectExplorerFormat.TryParseObjectName("", out _, out _));
        Assert.False(ObjectExplorerFormat.TryParseObjectName(null, out _, out _));
        Assert.False(ObjectExplorerFormat.TryParseObjectName("   ", out _, out _));
    }

    [Theory]
    [InlineData("Tables", "TABLE")]
    [InlineData("TABLE", "TABLE")]
    [InlineData("Views", "VIEW")]
    [InlineData("StoredProcedures", "PROCEDURE")]
    [InlineData("UserDefinedFunctions", "FUNCTION")]
    [InlineData("Triggers", "TRIGGER")]
    [InlineData("Sequences", "SEQUENCE")]
    public void NormalizeObjectType_MapsSmoCollections(string input, string expected)
    {
        Assert.Equal(expected, ObjectExplorerFormat.NormalizeObjectType(input));
    }
}
