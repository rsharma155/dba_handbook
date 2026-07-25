// =============================================================================
// Module:   SqlOptima.SchemaCompare.Tests.ShellComponentsTests
// Purpose:  TDD tests for the redesigned shell UI - nav rail, status badges,
//           collapsible connection card, header actions, tabs, and status bar.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using SqlOptima.SchemaCompare.Forms;
using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class NavRailTests
{
    [StaFact]
    public void Rail_HasMockupItemsInOrder()
    {
        using var rail = new NavRail();
        Assert.Equal(new[] { "compare", "history", "scripts", "reports", "settings" }, rail.ItemKeys);
        Assert.Equal("Compare", rail.LabelFor("compare"));
        Assert.Equal("History", rail.LabelFor("history"));
        Assert.Equal("Scripts", rail.LabelFor("scripts"));
        Assert.Equal("Reports", rail.LabelFor("reports"));
        Assert.Equal("Settings", rail.LabelFor("settings"));
    }

    [StaFact]
    public void Rail_DefaultActive_IsCompare()
    {
        using var rail = new NavRail();
        Assert.Equal("compare", rail.ActiveKey);
    }

    [StaFact]
    public void Rail_ItemClicked_RaisesEventAndActivates()
    {
        using var rail = new NavRail();
        string? clicked = null;
        rail.ItemClicked += (_, key) => clicked = key;
        rail.PerformItemClick("reports");
        Assert.Equal("reports", clicked);
        Assert.Equal("reports", rail.ActiveKey);
    }
}

public class StatusBadgeTests
{
    [StaFact]
    public void Badge_ShowsTitleAndZeroByDefault()
    {
        using var badge = new StatusBadge("Added", UiTheme.BadgeAdded);
        Assert.Equal("Added", badge.Title);
        Assert.Equal(0, badge.Value);
        Assert.Contains("Added", badge.CaptionText);
        Assert.Contains("0", badge.CaptionText);
    }

    [StaFact]
    public void Badge_SetValue_UpdatesCaption()
    {
        using var badge = new StatusBadge("Changed", UiTheme.BadgeChanged);
        badge.SetValue(42);
        Assert.Equal(42, badge.Value);
        Assert.Contains("42", badge.CaptionText);
    }

    [StaFact]
    public void Badge_WidthGrowsWithText_NoTruncation()
    {
        using var badge = new StatusBadge("Identical", UiTheme.BadgeIdentical);
        badge.SetValue(1234567);
        var needed = TextRenderer.MeasureText(badge.CaptionText, badge.Font).Width;
        Assert.True(badge.Width >= needed, $"badge width {badge.Width} must fit caption width {needed}");
    }
}

public class CollapsibleCardTests
{
    [StaFact]
    public void Card_ExposesTitleAndSubtitle()
    {
        using var card = new CollapsibleCard("1. Connect to Source and Target", "Select databases to compare.");
        Assert.Equal("1. Connect to Source and Target", card.Title);
        Assert.Equal("Select databases to compare.", card.Subtitle);
        Assert.False(card.Collapsed);
    }

    [StaFact]
    public void Card_Collapse_ShrinksAndHidesContent()
    {
        using var card = new CollapsibleCard("T", "S") { ExpandedHeight = 300 };
        card.Collapsed = true;
        Assert.True(card.Height < 80, $"collapsed height was {card.Height}");
        Assert.False(card.ContentHost.Visible);

        card.Collapsed = false;
        Assert.Equal(300, card.Height);
        Assert.True(card.ContentHost.Visible);
    }

    [StaFact]
    public void Card_Collapse_RaisesEvent()
    {
        using var card = new CollapsibleCard("T", "S");
        var fired = 0;
        card.CollapsedChanged += (_, _) => fired++;
        card.Collapsed = true;
        card.Collapsed = true; // no-op, must not re-fire
        card.Collapsed = false;
        Assert.Equal(2, fired);
    }
}

public class ConnectionPanelUiTests
{
    [StaFact]
    public void Panel_HasBrowseAndTestConnectionButtons()
    {
        using var panel = new ConnectionPanel("Source");
        var buttons = FindAll<Button>(panel).Select(b => b.Text).ToList();
        Assert.Contains("Test Connection", buttons);
        Assert.Contains("Browse", buttons);
    }

    [StaFact]
    public void Panel_PasswordEye_TogglesMasking()
    {
        using var panel = new ConnectionPanel("Source");
        // Eye is only enabled for SQL Login (password is disabled for Windows auth).
        panel.Apply(new ConnectionInfo { Instance = "SQLDEV", Auth = AuthMode.Sql, UserName = "sa" });
        var password = FindAll<TextBox>(panel).First(t => t.AccessibleName == "Password");
        var eye = FindAll<Button>(panel).First(b => b.AccessibleName == "Show password");
        Assert.True(eye.Enabled);
        Assert.True(password.UseSystemPasswordChar);
        eye.PerformClick();
        Assert.False(password.UseSystemPasswordChar);
        eye.PerformClick();
        Assert.True(password.UseSystemPasswordChar);
    }

    [StaFact]
    public void Panel_ShowsConnectedSuccessMessage()
    {
        using var panel = new ConnectionPanel("Source");
        panel.SetConnectionStatus(true, "AdventureWorks");
        var msg = FindAll<Label>(panel).FirstOrDefault(l => l.Text.Contains("Connected successfully"));
        Assert.NotNull(msg);
        Assert.True(msg!.Visible);
    }

    internal static IEnumerable<T> FindAll<T>(Control root) where T : Control
    {
        foreach (Control c in root.Controls)
        {
            if (c is T t) yield return t;
            foreach (var nested in FindAll<T>(c)) yield return nested;
        }
    }
}

public class MainFormShellTests
{
    private static MainForm NewForm()
    {
        // Keep tests deterministic: don't restore the developer's saved session.
        Environment.SetEnvironmentVariable("SQLOPTIMA_NO_SETTINGS", "1");
        return new MainForm(new CompareEngine(AppContext.BaseDirectory));
    }

    [StaFact]
    public void Tabs_MatchMockupNamesAndOrder()
    {
        using var form = NewForm();
        var names = form.Tabs.TabPages.Cast<TabPage>().Select(p => p.Text).ToList();
        Assert.Equal(new[] { "Overview", "Object Details", "Script Preview", "Manual Actions", "Progress Log" }, names);
    }

    [StaFact]
    public void Badges_MatchMockupTitles()
    {
        using var form = NewForm();
        var titles = form.Badges.Select(b => b.Title).ToList();
        Assert.Equal(new[] { "Added", "Removed", "Changed", "Identical", "Ignored" }, titles);
    }

    [StaFact]
    public void ComparisonProfile_HasDefaultProfile()
    {
        using var form = NewForm();
        var profile = ConnectionPanelUiTests.FindAll<ComboBox>(form)
            .FirstOrDefault(c => c.Items.Count > 0 && c.Items[0]?.ToString() == "Default Profile");
        Assert.NotNull(profile);
        Assert.Equal(0, profile!.SelectedIndex);
    }

    [StaFact]
    public void ConnectionCard_TitleMatchesMockup()
    {
        using var form = NewForm();
        Assert.Equal("1. Connect to Source and Target", form.ConnectionCard.Title);
        Assert.Equal("Select databases to compare.", form.ConnectionCard.Subtitle);
    }

    [StaFact]
    public void HeaderActions_MatchMockup()
    {
        using var form = NewForm();
        Assert.Equal("Compare Schemas  \u2192", form.CompareHeaderButton.Text);
        Assert.Equal("\u25B6  Compare Now", form.CompareNowButton.Text);
        Assert.Equal("Save Script", form.SaveScriptButton.Text);
        Assert.Contains("Presets", form.PresetsButton.Text);
    }

    [StaFact]
    public void StatusBar_MatchesMockupPlaceholders()
    {
        using var form = NewForm();
        Assert.Equal("Ready", form.StatusTextForTest);
        Assert.Equal("Source: Not selected", form.StatusSourceForTest);
        Assert.Equal("Target: Not selected", form.StatusTargetForTest);
        Assert.Equal("Objects: 0", form.StatusObjectsForTest);
    }

    [StaFact]
    public void SwapConnections_SwapsSourceAndTargetIncludingPassword()
    {
        using var form = NewForm();
        form.SourcePanelForTest.Apply(new ConnectionInfo
        {
            Instance = "HOST_01", Port = 1433, Auth = AuthMode.Sql, UserName = "src_user"
        });
        form.SourcePanelForTest.SetPassword("src_secret");
        form.TargetPanelForTest.Apply(new ConnectionInfo
        {
            Instance = "HOST_02", Port = 1533, Auth = AuthMode.Sql, UserName = "tgt_user"
        });
        form.TargetPanelForTest.SetPassword("tgt_secret");
        form.SwapConnections();
        Assert.Equal("HOST_02", form.SourcePanelForTest.GetConnectionInfo(false).Instance);
        Assert.Equal("HOST_01", form.TargetPanelForTest.GetConnectionInfo(false).Instance);
        Assert.Equal(1533, form.SourcePanelForTest.GetConnectionInfo(false).Port);
        Assert.Equal(AuthMode.Sql, form.SourcePanelForTest.GetConnectionInfo(false).Auth);
        Assert.Equal("tgt_secret", form.SourcePanelForTest.GetConnectionInfo(false).Password);
        Assert.Equal("src_secret", form.TargetPanelForTest.GetConnectionInfo(false).Password);
    }

    [StaFact]
    public void DualCompareButtons_ShareSameCaptionFamily()
    {
        using var form = NewForm();
        Assert.Contains("Compare", form.CompareHeaderButton.Text, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Compare", form.CompareNowButton.Text, StringComparison.OrdinalIgnoreCase);
    }

    [StaFact]
    public void ObjectExplorer_ShowsMockupCategoryFoldersBeforeConnect()
    {
        using var form = NewForm();
        form.Show();
        Application.DoEvents();
        // RebuildTree runs on construct; stub folders should be present when no browse data.
        var tree = ConnectionPanelUiTests.FindAll<TreeView>(form).FirstOrDefault();
        Assert.NotNull(tree);
        var names = tree!.Nodes.Cast<TreeNode>().Select(n => n.Text).ToList();
        Assert.Contains("Tables", names);
        Assert.Contains("Views", names);
        Assert.Contains("Stored Procedures", names);
        Assert.All(names, n => Assert.False(tree.Nodes.Cast<TreeNode>().First(x => x.Text == n).IsExpanded));
    }

    [StaFact]
    public void ObjectExplorer_HasMockupTitleAndSearchPlaceholder()
    {
        using var form = NewForm();
        var title = ConnectionPanelUiTests.FindAll<Label>(form).FirstOrDefault(l => l.Text == "Object Explorer");
        Assert.NotNull(title);
        Assert.Equal("Search objects...", form.ExplorerSearchBox.PlaceholderText);
    }

    [StaFact]
    public void Overview_ShowsEmptyStateBeforeCompare()
    {
        using var form = NewForm();
        var empty = ConnectionPanelUiTests.FindAll<Label>(form)
            .FirstOrDefault(l => l.Text.Contains("Run a comparison to see summary and results"));
        Assert.NotNull(empty);
    }

    [StaFact]
    public void CompareStart_AutoCollapsesConnectionCard()
    {
        using var form = NewForm();
        Assert.False(form.ConnectionCard.Collapsed);
        form.CollapseConnectionCardForCompare();
        Assert.True(form.ConnectionCard.Collapsed);
    }

    [StaFact]
    public void EnsureOutputRoot_IsSharedSchemaCompareOutputFolder()
    {
        using var form = NewForm();
        var root = form.EnsureOutputRoot();
        Assert.True(Directory.Exists(root));
        Assert.Equal(Path.GetFullPath(Path.Combine(form.EnsureOutputRoot(), ".")), Path.GetFullPath(root));
        Assert.True(
            root.EndsWith(Path.Combine("schema_compare", "output"), StringComparison.OrdinalIgnoreCase) ||
            root.Contains($"{Path.DirectorySeparatorChar}output", StringComparison.OrdinalIgnoreCase));
        // Calling again must return the same root (History / Scripts / Save Script share it).
        Assert.Equal(root, form.EnsureOutputRoot());
    }
}
