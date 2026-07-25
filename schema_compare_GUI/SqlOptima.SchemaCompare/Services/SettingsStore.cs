// =============================================================================
// Module:   SqlOptima.SchemaCompare.Services.SettingsStore
// Purpose:  Persists the user session (connections, options, window placement) between application runs.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Text.Json;
using SqlOptima.SchemaCompare.Models;

namespace SqlOptima.SchemaCompare.Services;

public static class SettingsStore
{
    /// <summary>Optional override for unit tests.</summary>
    public static string? SettingsPathOverride { get; set; }

    private static string SettingsDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "SqlOptima", "SchemaCompare");

    private static string SettingsPath =>
        SettingsPathOverride ?? Path.Combine(SettingsDir, "session.json");

    public static void Save(AppSessionSettings settings)
    {
        var path = SettingsPath;
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);

        var copy = CloneWithoutPasswords(settings);
        var json = JsonSerializer.Serialize(copy, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(path, json);
    }

    public static AppSessionSettings? Load()
    {
        var path = SettingsPath;
        if (!File.Exists(path)) return null;
        try
        {
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<AppSessionSettings>(json);
        }
        catch
        {
            return null;
        }
    }

    public static bool PasswordsWereStripped(AppSessionSettings settings) =>
        string.IsNullOrEmpty(settings.Source.Password) &&
        string.IsNullOrEmpty(settings.Target.Password);

    private static AppSessionSettings CloneWithoutPasswords(AppSessionSettings s)
    {
        var json = JsonSerializer.Serialize(s);
        var copy = JsonSerializer.Deserialize<AppSessionSettings>(json) ?? new AppSessionSettings();
        copy.Source.Password = "";
        copy.Target.Password = "";
        return copy;
    }
}
