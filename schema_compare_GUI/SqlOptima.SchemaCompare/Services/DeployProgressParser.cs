// =============================================================================
// Module:   SqlOptima.SchemaCompare.Services.DeployProgressParser
// Purpose:  Parses structured "##GUI:" progress lines emitted by the compare
//           engine so the UI can show per-database deploy progress.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

namespace SqlOptima.SchemaCompare.Services;

/// <summary>One structured progress event from the engine.</summary>
public sealed class DeployProgressUpdate
{
    /// <summary>DB | PHASE | APPLYRESULT | VERIFY</summary>
    public string Kind { get; set; } = "";
    public string Database { get; set; } = "";

    /// <summary>compare | apply | verify (PHASE only).</summary>
    public string Stage { get; set; } = "";

    /// <summary>For DB: pair index. For PHASE apply: script index.</summary>
    public int Index { get; set; }

    /// <summary>For DB: pair total. For PHASE apply: script total.</summary>
    public int Total { get; set; }

    /// <summary>APPLYRESULT: Applied/PartialFailure/Failed. VERIFY: Synced/Diffs/VerifyError.</summary>
    public string Status { get; set; } = "";

    /// <summary>APPLYRESULT: scripts applied.</summary>
    public int Applied { get; set; }

    /// <summary>APPLYRESULT: scripts failed.</summary>
    public int Failed { get; set; }

    /// <summary>VERIFY: remaining differences (-1 = unknown).</summary>
    public int Remaining { get; set; } = -1;
}

/// <summary>
/// Parses engine progress lines of the form
/// <c>##GUI:DB|db|i|n</c>, <c>##GUI:PHASE|db|compare</c>,
/// <c>##GUI:PHASE|db|apply|i|n</c>, <c>##GUI:PHASE|db|verify</c>,
/// <c>##GUI:APPLYRESULT|db|status|applied|failed</c>,
/// <c>##GUI:VERIFY|db|status|remaining</c>.
/// </summary>
public static class DeployProgressParser
{
    public const string Prefix = "##GUI:";

    public static bool TryParse(string? line, out DeployProgressUpdate update)
    {
        update = new DeployProgressUpdate();
        if (string.IsNullOrWhiteSpace(line)) return false;

        var idx = line.IndexOf(Prefix, StringComparison.Ordinal);
        if (idx < 0) return false;

        var parts = line[(idx + Prefix.Length)..].Trim().Split('|');
        if (parts.Length < 2) return false;

        update.Kind = parts[0].Trim().ToUpperInvariant();
        update.Database = parts[1].Trim();

        switch (update.Kind)
        {
            case "DB":
                if (parts.Length < 4) return false;
                if (!int.TryParse(parts[2], out var di) || !int.TryParse(parts[3], out var dn)) return false;
                update.Index = di;
                update.Total = dn;
                return true;

            case "PHASE":
                if (parts.Length < 3) return false;
                update.Stage = parts[2].Trim().ToLowerInvariant();
                if (update.Stage == "apply")
                {
                    if (parts.Length < 5) return false;
                    if (!int.TryParse(parts[3], out var si) || !int.TryParse(parts[4], out var sn)) return false;
                    update.Index = si;
                    update.Total = sn;
                }
                return update.Stage is "compare" or "apply" or "verify";

            case "APPLYRESULT":
                if (parts.Length < 5) return false;
                update.Status = parts[2].Trim();
                if (!int.TryParse(parts[3], out var ac) || !int.TryParse(parts[4], out var fc)) return false;
                update.Applied = ac;
                update.Failed = fc;
                return true;

            case "VERIFY":
                if (parts.Length < 4) return false;
                update.Status = parts[2].Trim();
                if (!int.TryParse(parts[3], out var rem)) return false;
                update.Remaining = rem;
                return true;

            default:
                return false;
        }
    }

    /// <summary>
    /// Overall percent across the run: each database occupies an equal slice;
    /// within a database the compare/apply/verify stages advance the slice.
    /// </summary>
    public static int ComputePercent(int dbIndex, int dbTotal, string stage, int scriptIndex, int scriptTotal)
    {
        if (dbTotal <= 0 || dbIndex <= 0) return 0;

        var stageFraction = stage switch
        {
            "compare" => 0.10,
            "apply" => scriptTotal > 0
                ? 0.10 + 0.75 * Math.Min(1.0, (double)scriptIndex / scriptTotal)
                : 0.50,
            "verify" => 0.90,
            _ => 0.0
        };

        var overall = ((dbIndex - 1) + stageFraction) / dbTotal * 100.0;
        return Math.Max(0, Math.Min(100, (int)Math.Round(overall)));
    }
}
