// =============================================================================
// Module:   SqlOptima.SchemaCompare.Tests.MetadataHeaderTests
// Purpose:  Enforces the project-wide file metadata header (Module, Purpose,
//           Author, Created, Copyright, SPDX) on every C# and PowerShell file.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

namespace SqlOptima.SchemaCompare.Tests;

public class MetadataHeaderTests
{
    private static readonly string[] RequiredLines =
    {
        "Module:",
        "Purpose:",
        "Author:   Ravi Sharma",
        "Created:  2026-05-22",
        "Copyright (c) 2026 Ravi Sharma",
        "SPDX-License-Identifier: MIT"
    };

    [Fact]
    public void AllCSharpSourceFiles_HaveMetadataHeader()
    {
        var root = FindGuiRoot();
        var files = EnumerateSourceFiles(root, "*.cs").ToList();
        Assert.NotEmpty(files);
        AssertHeaders(files);
    }

    [Fact]
    public void AllPowerShellScripts_HaveMetadataHeader()
    {
        var root = FindGuiRoot();
        var files = EnumerateSourceFiles(root, "*.ps1").ToList();
        Assert.NotEmpty(files);
        AssertHeaders(files);
    }

    private static void AssertHeaders(IEnumerable<string> files)
    {
        var failures = new List<string>();
        foreach (var file in files)
        {
            var head = string.Join("\n", File.ReadLines(file).Take(15));
            foreach (var required in RequiredLines)
            {
                if (!head.Contains(required, StringComparison.Ordinal))
                {
                    failures.Add($"{file}  (missing '{required}')");
                    break;
                }
            }
        }
        Assert.True(failures.Count == 0,
            "Files missing the required metadata header:\n" + string.Join("\n", failures));
    }

    private static IEnumerable<string> EnumerateSourceFiles(string root, string pattern)
        => Directory.EnumerateFiles(root, pattern, SearchOption.AllDirectories)
            .Where(f =>
                !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase) &&
                !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase) &&
                !f.Contains($"{Path.DirectorySeparatorChar}publish{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase));

    /// <summary>Walks up from the test bin folder to the schema_compare_GUI root.</summary>
    private static string FindGuiRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "SqlOptima.SchemaCompare.sln")))
                return dir.FullName;
            dir = dir.Parent;
        }
        throw new InvalidOperationException("Could not locate schema_compare_GUI root (SqlOptima.SchemaCompare.sln).");
    }
}
