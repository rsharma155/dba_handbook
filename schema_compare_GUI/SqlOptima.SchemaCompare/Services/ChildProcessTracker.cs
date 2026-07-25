// =============================================================================
// Module:   SqlOptima.SchemaCompare.Services.ChildProcessTracker
// Purpose:  Windows job-object tracking so child PowerShell processes are terminated when the application exits.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Diagnostics;

namespace SqlOptima.SchemaCompare.Services;

/// <summary>
/// Tracks child processes started by the app and ensures they are terminated on cancel/exit.
/// Prevents orphaned powershell.exe processes after the UI closes.
/// </summary>
public sealed class ChildProcessTracker : IDisposable
{
    private readonly object _gate = new();
    private readonly List<Process> _children = new();
    private bool _disposed;

    public int TrackedCount
    {
        get { lock (_gate) return _children.Count; }
    }

    public void Track(Process process)
    {
        ArgumentNullException.ThrowIfNull(process);
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            _children.Add(process);
            process.Exited += OnChildExited;
            process.EnableRaisingEvents = true;
            // If already exited between Start and Track, prune immediately.
            if (process.HasExited)
                RemoveUnlocked(process);
        }
    }

    private void OnChildExited(object? sender, EventArgs e)
    {
        if (sender is Process p)
        {
            lock (_gate) RemoveUnlocked(p);
        }
    }

    private void RemoveUnlocked(Process process)
    {
        process.Exited -= OnChildExited;
        _children.Remove(process);
    }

    /// <summary>
    /// Kill all still-running tracked children (and attempt to kill their process trees).
    /// </summary>
    public void KillAll(int waitMs = 2000)
    {
        List<Process> snapshot;
        lock (_gate)
        {
            snapshot = _children.ToList();
        }

        foreach (var p in snapshot)
        {
            try
            {
                if (p.HasExited) continue;
                TryKillTree(p);
                if (!p.WaitForExit(waitMs))
                {
                    try { if (!p.HasExited) p.Kill(entireProcessTree: true); } catch { /* ignore */ }
                }
            }
            catch
            {
                // Best-effort cleanup — never throw during shutdown.
            }
            finally
            {
                try { p.Dispose(); } catch { /* ignore */ }
                lock (_gate) RemoveUnlocked(p);
            }
        }
    }

    private static void TryKillTree(Process process)
    {
        try
        {
            // .NET 5+ Kill(entireProcessTree) works on Windows for child trees.
            process.Kill(entireProcessTree: true);
        }
        catch
        {
            try { process.Kill(); } catch { /* ignore */ }
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        KillAll();
        lock (_gate)
        {
            _disposed = true;
            _children.Clear();
        }
        GC.SuppressFinalize(this);
    }
}

/// <summary>
/// Clears sensitive env vars and temp work folders used by compare runs.
/// </summary>
public static class RuntimeCleanup
{
    public const string TempRootName = "SqlOptimaSchemaCompare";
    public const string EnvSrcPwd = "SCHEMA_COMPARE_SRC_PWD";
    public const string EnvTgtPwd = "SCHEMA_COMPARE_TGT_PWD";

    public static string TempRootPath => Path.Combine(Path.GetTempPath(), TempRootName);

    public static void ClearPasswordEnvironment()
    {
        try { Environment.SetEnvironmentVariable(EnvSrcPwd, null); } catch { /* ignore */ }
        try { Environment.SetEnvironmentVariable(EnvTgtPwd, null); } catch { /* ignore */ }
    }

    /// <summary>
    /// Deletes compare temp request/result folders older than <paramref name="maxAge"/>,
    /// plus any empty leftovers. Safe to call on exit.
    /// </summary>
    public static int CleanupTempFolders(TimeSpan? maxAge = null)
    {
        var age = maxAge ?? TimeSpan.FromHours(24);
        var root = TempRootPath;
        if (!Directory.Exists(root)) return 0;

        var removed = 0;
        var cutoff = DateTime.UtcNow - age;
        try
        {
            foreach (var dir in Directory.EnumerateDirectories(root))
            {
                try
                {
                    var info = new DirectoryInfo(dir);
                    if (info.CreationTimeUtc <= cutoff || IsDirectoryEmpty(dir))
                    {
                        Directory.Delete(dir, recursive: true);
                        removed++;
                    }
                }
                catch { /* in use — skip */ }
            }
        }
        catch { /* ignore */ }

        try
        {
            if (IsDirectoryEmpty(root))
                Directory.Delete(root, recursive: false);
        }
        catch { /* ignore */ }

        return removed;
    }

    public static void DeleteDirectoryBestEffort(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path)) return;
        try { Directory.Delete(path, recursive: true); } catch { /* ignore */ }
    }

    private static bool IsDirectoryEmpty(string path)
    {
        try
        {
            return !Directory.EnumerateFileSystemEntries(path).Any();
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Encourages GC after large compare results are discarded (UI close / cancel).
    /// </summary>
    public static void RequestMemoryReclaim()
    {
        try
        {
            GC.Collect(GC.MaxGeneration, GCCollectionMode.Optimized, blocking: false, compacting: true);
            GC.WaitForPendingFinalizers();
            GC.Collect(GC.MaxGeneration, GCCollectionMode.Optimized, blocking: false, compacting: true);
        }
        catch { /* ignore */ }
    }
}
