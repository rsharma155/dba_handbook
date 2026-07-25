// =============================================================================
// Module:   SqlOptima.SchemaCompare.Models.CompareModels
// Purpose:  Domain models - connection info, compare options and modes, difference items, and compare/deploy results.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Text.Json.Serialization;

namespace SqlOptima.SchemaCompare.Models;

public enum AuthMode
{
    Windows,
    Sql
}

public enum CompareMode
{
    OneToOne,
    OneToMany
}

public sealed class ConnectionInfo
{
    public string Instance { get; set; } = "";
    public int Port { get; set; }
    public AuthMode Auth { get; set; } = AuthMode.Windows;
    public string UserName { get; set; } = "";
    public string Password { get; set; } = "";
    public string Database { get; set; } = "";
    public bool TrustServerCertificate { get; set; } = true;

    public string BuildDataSource()
    {
        if (Port > 0 && !Instance.Contains(','))
            return $"{Instance},{Port}";
        return Instance;
    }

    public string BuildConnectionString(string? database = null)
    {
        var db = string.IsNullOrWhiteSpace(database) ? "master" : database;
        var b = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder
        {
            DataSource = BuildDataSource(),
            InitialCatalog = db,
            Encrypt = false,
            TrustServerCertificate = TrustServerCertificate,
            ConnectTimeout = 30
        };
        if (Auth == AuthMode.Windows)
        {
            b.IntegratedSecurity = true;
        }
        else
        {
            b.IntegratedSecurity = false;
            b.UserID = UserName;
            b.Password = Password;
        }
        return b.ConnectionString;
    }
}

public sealed class CompareOptions
{
    public string NetworkProtocol { get; set; } = "TcpIp";
    public int ConnectionTimeout { get; set; } = 30;
    public bool GenerateSyncScript { get; set; } = true;
    public bool IncludeDrops { get; set; }
    public bool Apply { get; set; }
    public bool TrustServerCertificate { get; set; } = true;
    public string ExcludeSchemas { get; set; } = "sys,INFORMATION_SCHEMA,guest";
    public string OutputPath { get; set; } = "";
    public List<string> IncludeObjectTypes { get; set; } = new();
}

public sealed class AppSessionSettings
{
    public CompareMode Mode { get; set; } = CompareMode.OneToOne;
    public ConnectionInfo Source { get; set; } = new();
    public ConnectionInfo Target { get; set; } = new();
    public List<string> TargetDatabases { get; set; } = new();
    public string DestinationListFile { get; set; } = "";
    public CompareOptions Options { get; set; } = new();

    // Window chrome (feedback_2 — remember size/position)
    public int WindowX { get; set; } = int.MinValue;
    public int WindowY { get; set; } = int.MinValue;
    public int WindowWidth { get; set; }
    public int WindowHeight { get; set; }
    public bool WindowMaximized { get; set; }
}

public sealed class DifferenceItem
{
    public string Database { get; set; } = "";
    public string ObjectType { get; set; } = "";
    public string ObjectName { get; set; } = "";
    public string Status { get; set; } = "";
    public string Details { get; set; } = "";

    [JsonIgnore]
    public string ActionLabel => Status switch
    {
        "Missing in Target" => "Add to Target",
        "Definition Mismatch" => "Update on Target",
        "Extra in Target" => "Extra on Target",
        _ => Status
    };

    [JsonIgnore]
    public DiffKind Kind => Status switch
    {
        "Missing in Target" => DiffKind.Add,
        "Definition Mismatch" => DiffKind.Update,
        "Extra in Target" => DiffKind.Extra,
        _ => DiffKind.Other
    };
}

public enum DiffKind
{
    Add,
    Update,
    Extra,
    Other
}

public sealed class CompareSummary
{
    public string Database { get; set; } = "";
    public string TargetDatabase { get; set; } = "";
    public int DifferenceCount { get; set; }
    public int AutoScripts { get; set; }
    public int ManualScripts { get; set; }
    public string? ScriptFolder { get; set; }
    public string? ReportPath { get; set; }
    public List<DifferenceItem> Differences { get; set; } = new();
}

public sealed class CompareResult
{
    public bool Success { get; set; }
    public string? Error { get; set; }
    public string? RunFolder { get; set; }
    public string? ReportPath { get; set; }
    public string? ManifestPath { get; set; }
    public List<CompareSummary> Summaries { get; set; } = new();
    public List<DifferenceItem> AllDifferences { get; set; } = new();
    public string Log { get; set; } = "";
    public string CombinedScriptPreview { get; set; } = "";
}

public sealed class GuiExportPayload
{
    public List<CompareSummaryDto> Summaries { get; set; } = new();
    public string? ReportPath { get; set; }
    public string? RunFolder { get; set; }
    public string? ManifestPath { get; set; }
}

public sealed class CompareSummaryDto
{
    public string? Database { get; set; }
    public string? TargetDatabase { get; set; }
    public int DifferenceCount { get; set; }
    public int AutoScripts { get; set; }
    public int ManualScripts { get; set; }
    public string? ScriptFolder { get; set; }
    public string? ReportPath { get; set; }
    public List<DifferenceItem> Differences { get; set; } = new();
}
