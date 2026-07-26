// =============================================================================
// Module:   SqlOptima.SchemaCompare.Tests.DeployProgressTests
// Purpose:  Unit tests for structured deploy progress parsing and the
//           apply/verify summary payload round-trip.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Text.Json;
using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class DeployProgressTests
{
    [Fact]
    public void TryParse_DbLine_ReturnsIndexAndTotal()
    {
        Assert.True(DeployProgressParser.TryParse("##GUI:DB|Tenant_A|2|5", out var p));
        Assert.Equal("DB", p.Kind);
        Assert.Equal("Tenant_A", p.Database);
        Assert.Equal(2, p.Index);
        Assert.Equal(5, p.Total);
    }

    [Fact]
    public void TryParse_PhaseApply_ReturnsScriptProgress()
    {
        Assert.True(DeployProgressParser.TryParse("##GUI:PHASE|Db1|apply|3|8", out var p));
        Assert.Equal("PHASE", p.Kind);
        Assert.Equal("apply", p.Stage);
        Assert.Equal(3, p.Index);
        Assert.Equal(8, p.Total);
    }

    [Fact]
    public void TryParse_CompareAndVerifyPhases()
    {
        Assert.True(DeployProgressParser.TryParse("##GUI:PHASE|Db1|compare", out var c));
        Assert.Equal("compare", c.Stage);
        Assert.True(DeployProgressParser.TryParse("##GUI:PHASE|Db1|verify", out var v));
        Assert.Equal("verify", v.Stage);
    }

    [Fact]
    public void TryParse_ApplyResultAndVerify()
    {
        Assert.True(DeployProgressParser.TryParse("##GUI:APPLYRESULT|Db1|PartialFailure|4|2", out var a));
        Assert.Equal("PartialFailure", a.Status);
        Assert.Equal(4, a.Applied);
        Assert.Equal(2, a.Failed);

        Assert.True(DeployProgressParser.TryParse("##GUI:VERIFY|Db1|Diffs|7", out var v));
        Assert.Equal("Diffs", v.Status);
        Assert.Equal(7, v.Remaining);
    }

    [Fact]
    public void TryParse_IgnoresOrdinaryLogLines()
    {
        Assert.False(DeployProgressParser.TryParse("  Comparing Tables ...", out _));
        Assert.False(DeployProgressParser.TryParse("", out _));
        Assert.False(DeployProgressParser.TryParse(null, out _));
        Assert.False(DeployProgressParser.TryParse("##GUI:BOGUS|x", out _));
    }

    [Fact]
    public void TryParse_ToleratesLogPrefixBeforeMarker()
    {
        // Engine writes via Write-Host; some hosts prepend text on the same line.
        Assert.True(DeployProgressParser.TryParse("xx ##GUI:DB|Db1|1|1", out var p));
        Assert.Equal("Db1", p.Database);
    }

    [Fact]
    public void ComputePercent_AdvancesAcrossDatabasesAndStages()
    {
        var db1Compare = DeployProgressParser.ComputePercent(1, 2, "compare", 0, 0);
        var db1Apply = DeployProgressParser.ComputePercent(1, 2, "apply", 5, 10);
        var db1Verify = DeployProgressParser.ComputePercent(1, 2, "verify", 0, 0);
        var db2Apply = DeployProgressParser.ComputePercent(2, 2, "apply", 10, 10);

        Assert.True(db1Compare < db1Apply);
        Assert.True(db1Apply < db1Verify);
        Assert.True(db1Verify < db2Apply);
        Assert.InRange(db1Compare, 1, 49);
        Assert.InRange(db2Apply, 51, 100);
    }

    [Fact]
    public void ComputePercent_ClampsInvalidInput()
    {
        Assert.Equal(0, DeployProgressParser.ComputePercent(0, 0, "apply", 1, 1));
        Assert.InRange(DeployProgressParser.ComputePercent(9, 2, "verify", 0, 0), 0, 100);
    }

    [Fact]
    public void PayloadJson_RoundTripsApplyAndVerifyFields()
    {
        const string json = """
        {
          "Summaries": [
            {
              "Database": "Src",
              "TargetDatabase": "Tgt1",
              "DifferenceCount": 5,
              "AutoScripts": 4,
              "ManualScripts": 1,
              "Applied": true,
              "ApplyStatus": "PartialFailure",
              "AppliedCount": 3,
              "FailedCount": 1,
              "FailedScripts": [ { "FileName": "auto_x.sql", "Error": "Timeout expired" } ],
              "VerifyStatus": "Diffs",
              "RemainingDiffs": 2,
              "Differences": []
            },
            {
              "Database": "Src",
              "TargetDatabase": "Tgt2",
              "DifferenceCount": 0,
              "AutoScripts": 0,
              "ManualScripts": 0,
              "Applied": false,
              "ApplyStatus": "NothingToApply",
              "AppliedCount": 0,
              "FailedCount": 0,
              "FailedScripts": [],
              "VerifyStatus": "Synced",
              "RemainingDiffs": 0,
              "Differences": []
            }
          ],
          "ReportPath": null,
          "RunFolder": null,
          "ManifestPath": null
        }
        """;

        var payload = JsonSerializer.Deserialize<GuiExportPayload>(json,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        Assert.NotNull(payload);

        var s1 = payload!.Summaries[0];
        Assert.True(s1.Applied);
        Assert.Equal("PartialFailure", s1.ApplyStatus);
        Assert.Equal(3, s1.AppliedCount);
        Assert.Equal(1, s1.FailedCount);
        Assert.NotNull(s1.FailedScripts);
        Assert.Equal("auto_x.sql", s1.FailedScripts![0].FileName);
        Assert.Equal("Timeout expired", s1.FailedScripts![0].Error);
        Assert.Equal("Diffs", s1.VerifyStatus);
        Assert.Equal(2, s1.RemainingDiffs);

        var s2 = payload.Summaries[1];
        Assert.False(s2.Applied);
        Assert.Equal("NothingToApply", s2.ApplyStatus);
        Assert.Equal("Synced", s2.VerifyStatus);
    }

    [Fact]
    public void CompareResult_AppliedRun_TrueWhenAnySummaryApplied()
    {
        var result = new CompareResult();
        result.Summaries.Add(new CompareSummary { TargetDatabase = "A", Applied = false, ApplyStatus = "Skipped" });
        Assert.False(result.AppliedRun);

        result.Summaries.Add(new CompareSummary { TargetDatabase = "B", Applied = true, ApplyStatus = "Applied" });
        Assert.True(result.AppliedRun);

        var nothing = new CompareResult();
        nothing.Summaries.Add(new CompareSummary { TargetDatabase = "C", ApplyStatus = "NothingToApply" });
        Assert.True(nothing.AppliedRun);
    }

    [Fact]
    public void CompareSummary_ContinueOnErrorShape_MarksFailuresPerDatabase()
    {
        // 2A contract: a failed DB coexists with successfully deployed DBs.
        var result = new CompareResult();
        result.Summaries.Add(new CompareSummary
        {
            TargetDatabase = "GoodDb",
            Applied = true,
            ApplyStatus = "Applied",
            AppliedCount = 5,
            VerifyStatus = "Synced",
            RemainingDiffs = 0
        });
        result.Summaries.Add(new CompareSummary
        {
            TargetDatabase = "BadDb",
            Applied = true,
            ApplyStatus = "PartialFailure",
            AppliedCount = 2,
            FailedCount = 1,
            FailedScripts = { new DeployFailure { FileName = "auto_bad.sql", Error = "Constraint violation" } },
            VerifyStatus = "Diffs",
            RemainingDiffs = 3
        });

        Assert.True(result.AppliedRun);
        Assert.Equal(1, result.Summaries.Count(s => s.FailedCount > 0));
        Assert.Equal(1, result.Summaries.Count(s => s.VerifyStatus == "Synced"));
        Assert.Contains(result.Summaries, s => s.FailedScripts.Any(f => f.Error.Contains("Constraint")));
    }
}
