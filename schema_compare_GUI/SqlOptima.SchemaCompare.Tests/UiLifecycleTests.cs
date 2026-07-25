// =============================================================================
// Module:   SqlOptima.SchemaCompare.Tests.UiLifecycleTests
// Purpose:  Lifecycle tests for ConnectionPanel, OptionsForm, and MainForm - construction, shutdown, and safe double-dispose.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using SqlOptima.SchemaCompare.Forms;
using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class ConnectionPanelTests
{
    [StaFact]
    public void GetConnectionInfo_ReadsFields()
    {
        using var panel = new ConnectionPanel("Source");
        panel.Apply(new ConnectionInfo
        {
            Instance = "SQLDEV",
            Port = 1433,
            Auth = AuthMode.Sql,
            UserName = "appuser",
            Database = "Sales"
        });
        // Password not restored by Apply — set via Get after Apply leaves empty password
        var info = panel.GetConnectionInfo();
        Assert.Equal("SQLDEV", info.Instance);
        Assert.Equal(1433, info.Port);
        Assert.Equal(AuthMode.Sql, info.Auth);
        Assert.Equal("appuser", info.UserName);
        Assert.Equal("Sales", info.Database);
    }

    [StaFact]
    public void MultiSelect_CheckAll_And_GetChecked()
    {
        using var panel = new ConnectionPanel("Target", multiSelectTargets: true);
        panel.SetMultiSelectVisible(true);
        panel.SetDatabases(new[] { "A", "B", "C" }, preferredChecked: new[] { "B" });
        var checked1 = panel.GetCheckedDatabases();
        Assert.Contains("B", checked1);

        panel.CheckAllDatabases(true);
        Assert.Equal(3, panel.GetCheckedDatabases().Count);

        panel.CheckAllDatabases(false);
        Assert.Empty(panel.GetCheckedDatabases());
    }

    [StaFact]
    public void Buttons_HaveHighContrastText()
    {
        using var panel = new ConnectionPanel("Source");
        var buttons = EnumerateButtons(panel).ToList();
        Assert.NotEmpty(buttons);
        foreach (var b in buttons)
        {
            Assert.False(b.ForeColor.IsEmpty);
            Assert.NotEqual(b.ForeColor, b.BackColor);
            // ModernButton (and styled buttons) use FlatStyle.Flat with owner-draw text.
            Assert.Equal(FlatStyle.Flat, b.FlatStyle);
            Assert.False(string.IsNullOrWhiteSpace(b.Text));
        }
    }

    [StaFact]
    public void Target_OneToOne_UsesComboSelection()
    {
        using var panel = new ConnectionPanel("Target", multiSelectTargets: true);
        panel.SetMultiSelectVisible(false);
        panel.SetDatabases(new[] { "Alpha", "Beta" }, preferredChecked: null);
        Assert.Equal("Alpha", panel.SelectedDatabase);
        panel.SingleDatabase = "Beta";
        Assert.Equal("Beta", panel.SelectedDatabase);
        Assert.Equal(new[] { "Beta" }, panel.GetCheckedDatabases());
    }

    [StaFact]
    public void Target_OneToMany_UsesCheckedList()
    {
        using var panel = new ConnectionPanel("Target", multiSelectTargets: true);
        panel.SetMultiSelectVisible(true);
        panel.SetDatabases(new[] { "A", "B", "C" }, preferredChecked: new[] { "B" });
        Assert.Contains("B", panel.GetCheckedDatabases());
        panel.CheckAllDatabases(true);
        Assert.Equal(3, panel.GetCheckedDatabases().Count);
    }

    private static IEnumerable<Button> EnumerateButtons(Control root)
    {
        foreach (Control c in root.Controls)
        {
            if (c is Button b) yield return b;
            foreach (var nested in EnumerateButtons(c))
                yield return nested;
        }
    }
}

public class OptionsFormTests
{
    [StaFact]
    public void Ok_CommitsOptions()
    {
        var current = new CompareOptions
        {
            GenerateSyncScript = true,
            IncludeDrops = false,
            NetworkProtocol = "TcpIp",
            ConnectionTimeout = 30,
            OutputPath = Path.GetTempPath()
        };
        using var form = new OptionsForm(current);
        form.Show();
        try
        {
            var ok = FindButton(form, "OK");
            Assert.NotNull(ok);
            ok!.PerformClick();
            Assert.True(form.Options.GenerateSyncScript);
            Assert.Equal("TcpIp", form.Options.NetworkProtocol);
            Assert.False(string.IsNullOrWhiteSpace(form.Options.OutputPath));
        }
        finally
        {
            form.Close();
        }
    }

    [StaFact]
    public void Focus_IgnoreRules_OpensIgnoreTab()
    {
        using var form = new OptionsForm(new CompareOptions { OutputPath = Path.GetTempPath() }, OptionsFocus.IgnoreRules);
        Assert.Equal("Ignore rules", form.Text);
        Assert.Equal("Ignore rules", form.InitialTabText);
    }

    [StaFact]
    public void Focus_Advanced_OpensScriptsTab()
    {
        using var form = new OptionsForm(new CompareOptions { OutputPath = Path.GetTempPath() }, OptionsFocus.Advanced);
        Assert.Equal("Advanced options", form.Text);
        Assert.Equal("Scripts", form.InitialTabText);
    }

    [StaFact]
    public void Focus_Settings_OpensConnectionTab()
    {
        using var form = new OptionsForm(new CompareOptions { OutputPath = Path.GetTempPath() }, OptionsFocus.Settings);
        Assert.Equal("Settings", form.Text);
        Assert.Equal("Connection", form.InitialTabText);
    }

    [StaFact]
    public void Tabs_AreIgnoreScriptsConnectionOutput()
    {
        using var form = new OptionsForm(new CompareOptions { OutputPath = Path.GetTempPath() });
        form.Show();
        try
        {
            var tabs = FindAll<TabControl>(form).FirstOrDefault();
            Assert.NotNull(tabs);
            var names = tabs!.TabPages.Cast<TabPage>().Select(p => p.Text).ToList();
            Assert.Equal(new[] { "Ignore rules", "Scripts", "Connection", "Output" }, names);
        }
        finally
        {
            form.Close();
        }
    }

    private static Button? FindButton(Control root, string text)
    {
        foreach (Control c in root.Controls)
        {
            if (c is Button b && b.Text == text) return b;
            var nested = FindButton(c, text);
            if (nested != null) return nested;
        }
        return null;
    }

    private static IEnumerable<T> FindAll<T>(Control root) where T : Control
    {
        foreach (Control c in root.Controls)
        {
            if (c is T t) yield return t;
            foreach (var nested in FindAll<T>(c))
                yield return nested;
        }
    }
}

public class MainFormLifecycleTests
{
    [StaFact]
    public void MainForm_Construct_And_Shutdown_DoesNotThrow()
    {
        // Use real path discovery from test base directory (walks up to schema_compare_GUI).
        using var engine = new CompareEngine(AppContext.BaseDirectory);
        using var form = new MainForm(engine);
        form.Show();
        Assert.False(form.IsDisposed);
        form.ShutdownResources();
        form.Close();
    }

    [StaFact]
    public void MainForm_Dispose_KillsEngineTracker()
    {
        using var engine = new CompareEngine(AppContext.BaseDirectory);
        var form = new MainForm(engine);
        form.Show();
        form.ShutdownResources();
        form.Dispose();
        Assert.True(form.IsDisposed);
        // Second dispose / shutdown must be safe
        form.ShutdownResources();
        engine.Shutdown();
    }
}
