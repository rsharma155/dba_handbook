// =============================================================================
// Module:   SqlOptima.SchemaCompare.Services.CompareEngine
// Purpose:  Orchestrates the schema_compare PowerShell engine - process lifecycle, cancellation, log streaming, and result parsing.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Diagnostics;
using System.Text;
using System.Text.Json;
using SqlOptima.SchemaCompare.Models;

namespace SqlOptima.SchemaCompare.Services;

/// <summary>
/// Invokes the existing schema_compare PowerShell engine without modifying it.
/// Tracks child processes and cleans temp files; safe to Dispose on app exit.
/// </summary>
public sealed class CompareEngine : IDisposable
{
    public const int MaxScriptPreviewChars = 1_500_000;
    public const int MaxLogChars = 512_000;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly ChildProcessTracker _tracker = new();
    private readonly object _runGate = new();
    private Process? _activeProcess;
    private string? _activeWorkDir;
    private bool _disposed;

    public string SchemaCompareRoot { get; }
    public string BridgeScriptPath { get; }
    public string GuiRoot { get; }
    public ChildProcessTracker ProcessTracker => _tracker;

    public CompareEngine()
        : this(AppContext.BaseDirectory)
    {
    }

    /// <summary>Testable constructor — starts path discovery from <paramref name="startDirectory"/>.</summary>
    public CompareEngine(string startDirectory)
    {
        if (!SchemaComparePaths.TryResolveGuiRoot(startDirectory, out var guiRoot, out var compareRoot))
            throw new InvalidOperationException(
                "Cannot locate the Schema Compare install. Expected a folder that contains " +
                "tools\\Invoke-CompareForGui.ps1 and schema_compare\\Compare-SqlSchema.ps1 " +
                "(self-contained zip layout), or a sibling schema_compare folder.");

        GuiRoot = guiRoot;
        SchemaCompareRoot = compareRoot;
        BridgeScriptPath = Path.Combine(guiRoot, "tools", "Invoke-CompareForGui.ps1");
        if (!File.Exists(BridgeScriptPath))
            throw new InvalidOperationException($"Bridge script missing: {BridgeScriptPath}");
    }

    /// <summary>Fully explicit paths for unit tests (skips filesystem discovery of siblings).</summary>
    public CompareEngine(string guiRoot, string compareRoot, string bridgeScriptPath)
    {
        GuiRoot = guiRoot;
        SchemaCompareRoot = compareRoot;
        BridgeScriptPath = bridgeScriptPath;
    }

    public async Task<CompareResult> RunAsync(
        ConnectionInfo source,
        ConnectionInfo target,
        CompareMode mode,
        IReadOnlyList<string> targetDatabases,
        string? destinationListFile,
        CompareOptions options,
        IProgress<string>? progress,
        CancellationToken ct)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        var workDir = Path.Combine(RuntimeCleanup.TempRootPath, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(workDir);
        var requestPath = Path.Combine(workDir, "request.json");
        var resultPath = Path.Combine(workDir, "result.json");
        var logPath = Path.Combine(workDir, "run.log");
        lock (_runGate) _activeWorkDir = workDir;

        var request = BuildRequestDictionary(
            source, target, mode, targetDatabases, destinationListFile, options, resultPath);

        await File.WriteAllTextAsync(
                requestPath,
                JsonSerializer.Serialize(request, new JsonSerializerOptions { WriteIndented = true }),
                ct)
            .ConfigureAwait(false);

        var psi = new ProcessStartInfo
        {
            FileName = ResolvePowerShell(),
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{BridgeScriptPath}\" -RequestPath \"{requestPath}\"",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = SchemaCompareRoot
        };

        if (source.Auth == AuthMode.Sql)
            psi.Environment[RuntimeCleanup.EnvSrcPwd] = source.Password;
        if (target.Auth == AuthMode.Sql)
            psi.Environment[RuntimeCleanup.EnvTgtPwd] = target.Password;

        progress?.Report("Starting schema compare engine...");
        var log = new CappedStringBuffer(MaxLogChars);
        Process? proc = null;

        try
        {
            proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
            proc.OutputDataReceived += (_, e) =>
            {
                if (e.Data == null) return;
                log.AppendLine(e.Data);
                progress?.Report(e.Data);
            };
            proc.ErrorDataReceived += (_, e) =>
            {
                if (e.Data == null) return;
                log.AppendLine("ERR: " + e.Data);
                progress?.Report("ERR: " + e.Data);
            };

            if (!proc.Start())
                throw new InvalidOperationException("Failed to start PowerShell.");

            lock (_runGate) _activeProcess = proc;
            _tracker.Track(proc);

            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();

            try
            {
                await proc.WaitForExitAsync(ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                CancelActiveProcess();
                try
                {
                    // Give the process a moment to exit after Kill.
                    if (!proc.HasExited)
                        proc.WaitForExit(3000);
                }
                catch { /* ignore */ }
                throw;
            }

            try { await File.WriteAllTextAsync(logPath, log.Snapshot(), CancellationToken.None).ConfigureAwait(false); }
            catch { /* ignore log write failures */ }

            var result = await ReadResultAsync(proc, resultPath, log.Snapshot(), CancellationToken.None).ConfigureAwait(false);
            return result;
        }
        catch (OperationCanceledException)
        {
            CancelActiveProcess();
            return new CompareResult
            {
                Success = false,
                Error = "Compare cancelled.",
                Log = log.Snapshot()
            };
        }
        finally
        {
            RuntimeCleanup.ClearPasswordEnvironment();
            lock (_runGate)
            {
                _activeProcess = null;
                _activeWorkDir = null;
            }

            // Drop request/result temp folder for this run (best effort).
            RuntimeCleanup.DeleteDirectoryBestEffort(workDir);

            if (proc != null)
            {
                try { if (!proc.HasExited) proc.Kill(entireProcessTree: true); } catch { /* ignore */ }
                try { proc.Dispose(); } catch { /* ignore */ }
            }
        }
    }

    public void CancelActiveProcess()
    {
        Process? p;
        lock (_runGate) p = _activeProcess;
        if (p == null) return;
        try
        {
            if (!p.HasExited)
                p.Kill(entireProcessTree: true);
        }
        catch { /* ignore */ }
    }

    /// <summary>
    /// Shutdown hook: kill children, clear secrets, purge temp folders, reclaim memory.
    /// </summary>
    public void Shutdown()
    {
        try { CancelActiveProcess(); } catch { /* ignore */ }
        try { _tracker.KillAll(); } catch { /* ignore */ }
        RuntimeCleanup.ClearPasswordEnvironment();
        RuntimeCleanup.CleanupTempFolders(TimeSpan.FromMinutes(5));
        RuntimeCleanup.RequestMemoryReclaim();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Shutdown();
        _tracker.Dispose();
        GC.SuppressFinalize(this);
    }

    internal static Dictionary<string, object?> BuildRequestDictionary(
        ConnectionInfo source,
        ConnectionInfo target,
        CompareMode mode,
        IReadOnlyList<string> targetDatabases,
        string? destinationListFile,
        CompareOptions options,
        string resultJsonPath,
        string? compareScriptOverride = null)
    {
        return new Dictionary<string, object?>
        {
            ["CompareScript"] = compareScriptOverride,
            ["SourceSqlInstance"] = source.Instance,
            ["TargetSqlInstance"] = target.Instance,
            ["SourcePort"] = source.Port,
            ["TargetPort"] = target.Port,
            ["SourceDatabase"] = source.Database,
            ["TargetDatabases"] = targetDatabases.ToArray(),
            ["TargetDatabaseListFile"] = string.IsNullOrWhiteSpace(destinationListFile) ? null : destinationListFile,
            ["Mode"] = mode.ToString(),
            ["NetworkProtocol"] = options.NetworkProtocol,
            ["ConnectionTimeout"] = options.ConnectionTimeout,
            ["TrustServerCertificate"] = options.TrustServerCertificate,
            ["GenerateSyncScript"] = options.GenerateSyncScript,
            ["IncludeDrops"] = options.IncludeDrops,
            ["Apply"] = options.Apply,
            ["ExcludeSchema"] = options.ExcludeSchemas.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries),
            ["OutputPath"] = options.OutputPath,
            ["ResultJsonPath"] = resultJsonPath,
            ["SourceAuth"] = source.Auth.ToString(),
            ["TargetAuth"] = target.Auth.ToString(),
            ["SourceUser"] = source.UserName,
            ["TargetUser"] = target.UserName
        };
    }

    private Dictionary<string, object?> BuildRequestDictionary(
        ConnectionInfo source,
        ConnectionInfo target,
        CompareMode mode,
        IReadOnlyList<string> targetDatabases,
        string? destinationListFile,
        CompareOptions options,
        string resultJsonPath)
    {
        var dict = BuildRequestDictionary(
            source, target, mode, targetDatabases, destinationListFile, options, resultJsonPath,
            Path.Combine(SchemaCompareRoot, "Compare-SqlSchema.ps1"));
        if (string.IsNullOrWhiteSpace(options.OutputPath))
            dict["OutputPath"] = Path.Combine(SchemaCompareRoot, "output");
        return dict;
    }

    private static async Task<CompareResult> ReadResultAsync(
        Process proc, string resultPath, string logText, CancellationToken ct)
    {
        var result = new CompareResult { Log = logText };

        if (!File.Exists(resultPath))
        {
            result.Success = false;
            result.Error = proc.ExitCode != 0
                ? $"Compare failed (exit {proc.ExitCode}). See log."
                : "No result JSON produced by bridge script.";
            return result;
        }

        await using var fs = File.OpenRead(resultPath);
        var payload = await JsonSerializer.DeserializeAsync<GuiExportPayload>(fs, JsonOptions, ct)
            .ConfigureAwait(false);

        if (payload == null)
        {
            result.Success = false;
            result.Error = "Could not parse compare result JSON.";
            return result;
        }

        if (payload.Summaries.Count == 0 && proc.ExitCode != 0)
        {
            result.Success = false;
            result.Error = $"Compare failed (exit {proc.ExitCode}).";
            return result;
        }

        result.Success = proc.ExitCode == 0 || payload.Summaries.Count > 0;
        result.ReportPath = payload.ReportPath;
        result.RunFolder = payload.RunFolder;
        result.ManifestPath = payload.ManifestPath;

        foreach (var s in payload.Summaries)
        {
            var summary = new CompareSummary
            {
                Database = s.Database ?? "",
                TargetDatabase = s.TargetDatabase ?? "",
                DifferenceCount = s.DifferenceCount,
                AutoScripts = s.AutoScripts,
                ManualScripts = s.ManualScripts,
                ScriptFolder = s.ScriptFolder,
                ReportPath = s.ReportPath,
                Differences = s.Differences ?? new List<DifferenceItem>(),
                Applied = s.Applied,
                ApplyStatus = string.IsNullOrWhiteSpace(s.ApplyStatus) ? "Skipped" : s.ApplyStatus!,
                AppliedCount = s.AppliedCount,
                FailedCount = s.FailedCount,
                FailedScripts = s.FailedScripts ?? new List<DeployFailure>(),
                VerifyStatus = string.IsNullOrWhiteSpace(s.VerifyStatus) ? "NotVerified" : s.VerifyStatus!,
                RemainingDiffs = s.RemainingDiffs
            };
            // Engine tags each difference with the source DB name. For one-to-many
            // (same source → many targets) the GUI tree must group by destination.
            TagDifferencesByTarget(summary);
            result.Summaries.Add(summary);
            result.AllDifferences.AddRange(summary.Differences);
        }

        result.CombinedScriptPreview = await BuildScriptPreviewAsync(result.RunFolder, ct).ConfigureAwait(false);

        if (!result.Success && string.IsNullOrWhiteSpace(result.Error))
            result.Error = "Compare completed with errors. Review the log.";

        return result;
    }

    /// <summary>
    /// Retags difference rows with the destination database so the explorer
    /// groups per target in one-to-many runs (engine emits source DB names).
    /// </summary>
    internal static void TagDifferencesByTarget(CompareSummary summary)
    {
        if (summary.Differences.Count == 0) return;
        var target = summary.TargetDatabase?.Trim();
        if (string.IsNullOrWhiteSpace(target)) return;

        foreach (var d in summary.Differences)
            d.Database = target;
    }

    internal static async Task<string> BuildScriptPreviewAsync(string? runFolder, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(runFolder) || !Directory.Exists(runFolder))
            return "-- No sync scripts generated.";

        var sb = new StringBuilder();
        var masters = Directory.GetFiles(runFolder, "_master_auto_only.sql", SearchOption.AllDirectories)
            .OrderBy(f => f)
            .ToList();

        if (masters.Count == 0)
        {
            var autos = Directory.GetFiles(runFolder, "auto_*.sql", SearchOption.AllDirectories)
                .OrderBy(f => f)
                .Take(20)
                .ToList();
            if (autos.Count == 0)
                return "-- Schemas match, or no auto_ scripts were produced.";

            sb.AppendLine("/* Preview of first auto_ scripts (open output folder for full set) */");
            sb.AppendLine();
            foreach (var f in autos)
            {
                if (sb.Length > MaxScriptPreviewChars) break;
                sb.AppendLine($"-- ===== {Path.GetFileName(f)} =====");
                sb.AppendLine(await ReadCappedFileAsync(f, MaxScriptPreviewChars - sb.Length, ct).ConfigureAwait(false));
                sb.AppendLine("GO");
                sb.AppendLine();
            }
        }
        else
        {
            sb.AppendLine("/* Combined master auto-only runners (one per destination when multi-DB) */");
            sb.AppendLine();
            foreach (var m in masters)
            {
                if (sb.Length > MaxScriptPreviewChars) break;
                sb.AppendLine($"-- ===== {m} =====");
                sb.AppendLine(await ReadCappedFileAsync(m, MaxScriptPreviewChars - sb.Length, ct).ConfigureAwait(false));
                sb.AppendLine();
            }
        }

        if (sb.Length > MaxScriptPreviewChars)
        {
            sb.Length = MaxScriptPreviewChars;
            sb.AppendLine();
            sb.AppendLine("/* ... preview truncated for memory ... */");
        }

        return sb.ToString();
    }

    private static async Task<string> ReadCappedFileAsync(string path, int maxChars, CancellationToken ct)
    {
        if (maxChars <= 0) return string.Empty;
        var text = await File.ReadAllTextAsync(path, ct).ConfigureAwait(false);
        if (text.Length <= maxChars) return text;
        return text[..maxChars] + "\r\n/* ... file truncated ... */";
    }

    public static string ResolvePowerShell()
    {
        var pwsh = FindOnPath("pwsh.exe");
        if (pwsh != null) return pwsh;
        var windowsPs = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            @"WindowsPowerShell\v1.0\powershell.exe");
        if (File.Exists(windowsPs)) return windowsPs;
        return "powershell.exe";
    }

    private static string? FindOnPath(string fileName)
    {
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var candidate = Path.Combine(dir.Trim('"'), fileName);
                if (File.Exists(candidate)) return candidate;
            }
            catch { /* ignore */ }
        }
        return null;
    }
}
