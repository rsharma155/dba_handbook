// =============================================================================
// Module:   SqlOptima.SchemaCompare.Tests.ProcessAndCleanupTests
// Purpose:  Tests for child process tracking and runtime cleanup (temp folders, password environment).
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Diagnostics;
using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class ChildProcessTrackerTests
{
    [Fact]
    public void KillAll_TerminatesTrackedProcess()
    {
        using var tracker = new ChildProcessTracker();
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -Command \"Start-Sleep -Seconds 60\"",
            UseShellExecute = false,
            CreateNoWindow = true
        };
        using var proc = Process.Start(psi)!;
        Assert.False(proc.HasExited);
        tracker.Track(proc);
        Assert.True(tracker.TrackedCount >= 1);

        tracker.KillAll(waitMs: 5000);

        // Process should be dead; HasExited may throw if disposed by tracker — refresh.
        try
        {
            Assert.True(proc.HasExited);
        }
        catch (InvalidOperationException)
        {
            // Disposed after kill — acceptable.
        }
        Assert.Equal(0, tracker.TrackedCount);
    }

    [Fact]
    public void Dispose_IsIdempotent()
    {
        var tracker = new ChildProcessTracker();
        tracker.Dispose();
        tracker.Dispose();
    }
}

public class RuntimeCleanupTests
{
    [Fact]
    public void ClearPasswordEnvironment_RemovesVars()
    {
        Environment.SetEnvironmentVariable(RuntimeCleanup.EnvSrcPwd, "x");
        Environment.SetEnvironmentVariable(RuntimeCleanup.EnvTgtPwd, "y");
        RuntimeCleanup.ClearPasswordEnvironment();
        Assert.Null(Environment.GetEnvironmentVariable(RuntimeCleanup.EnvSrcPwd));
        Assert.Null(Environment.GetEnvironmentVariable(RuntimeCleanup.EnvTgtPwd));
    }

    [Fact]
    public void CleanupTempFolders_RemovesOldDirs()
    {
        var root = RuntimeCleanup.TempRootPath;
        Directory.CreateDirectory(root);
        var oldDir = Path.Combine(root, "old_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(oldDir);
        File.WriteAllText(Path.Combine(oldDir, "x.txt"), "x");
        // Force old timestamp
        Directory.SetCreationTimeUtc(oldDir, DateTime.UtcNow.AddDays(-2));

        var removed = RuntimeCleanup.CleanupTempFolders(TimeSpan.FromHours(1));
        Assert.True(removed >= 1);
        Assert.False(Directory.Exists(oldDir));
    }

    [Fact]
    public void DeleteDirectoryBestEffort_IgnoresMissing()
    {
        RuntimeCleanup.DeleteDirectoryBestEffort(Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N")));
    }

    [Fact]
    public void RequestMemoryReclaim_DoesNotThrow()
    {
        RuntimeCleanup.RequestMemoryReclaim();
    }
}

public class SettingsStoreTests : IDisposable
{
    private readonly string _tempFile;

    public SettingsStoreTests()
    {
        _tempFile = Path.Combine(Path.GetTempPath(), "SqlOptimaSettingsTests_" + Guid.NewGuid().ToString("N") + ".json");
        SettingsStore.SettingsPathOverride = _tempFile;
    }

    public void Dispose()
    {
        SettingsStore.SettingsPathOverride = null;
        try { if (File.Exists(_tempFile)) File.Delete(_tempFile); } catch { /* ignore */ }
    }

    [Fact]
    public void Save_DoesNotPersistPasswords()
    {
        SettingsStore.Save(new AppSessionSettings
        {
            Source = new ConnectionInfo { Instance = "s1", Password = "p1", UserName = "u1", Auth = AuthMode.Sql },
            Target = new ConnectionInfo { Instance = "t1", Password = "p2", UserName = "u2", Auth = AuthMode.Sql },
            Mode = CompareMode.OneToMany
        });

        var loaded = SettingsStore.Load();
        Assert.NotNull(loaded);
        Assert.Equal("s1", loaded!.Source.Instance);
        Assert.Equal("u1", loaded.Source.UserName);
        Assert.True(string.IsNullOrEmpty(loaded.Source.Password));
        Assert.True(string.IsNullOrEmpty(loaded.Target.Password));
        Assert.Equal(CompareMode.OneToMany, loaded.Mode);
        Assert.True(SettingsStore.PasswordsWereStripped(loaded));
    }

    [Fact]
    public void Load_MissingFile_ReturnsNull()
    {
        SettingsStore.SettingsPathOverride = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".json");
        Assert.Null(SettingsStore.Load());
    }
}
