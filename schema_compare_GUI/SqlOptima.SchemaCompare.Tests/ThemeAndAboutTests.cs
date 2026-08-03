// =============================================================================
// Module:   SqlOptima.SchemaCompare.Tests.ThemeAndAboutTests
// Purpose:  Verifies light/dark palette switching (UiTheme + ThemeSwitcher +
//           NavRail toggle) and the About dialog content (README extract, MIT).
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using SqlOptima.SchemaCompare.Forms;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class ThemeTests
{
    [Fact]
    public void SetDarkMode_SwapsTokens_AndRestoresLight()
    {
        try
        {
            UiTheme.SetDarkMode(true);
            Assert.True(UiTheme.IsDark);
            Assert.Equal(UiTheme.Dk.AppBackground.ToArgb(), UiTheme.AppBackground.ToArgb());
            Assert.Equal(UiTheme.Dk.CardBackground.ToArgb(), UiTheme.CardBackground.ToArgb());
            Assert.Equal(UiTheme.Dk.TextPrimary.ToArgb(), UiTheme.TextPrimary.ToArgb());
        }
        finally
        {
            UiTheme.SetDarkMode(false);
        }

        Assert.False(UiTheme.IsDark);
        Assert.Equal(UiTheme.Lt.AppBackground.ToArgb(), UiTheme.AppBackground.ToArgb());
        Assert.Equal(UiTheme.Lt.CardBackground.ToArgb(), UiTheme.CardBackground.ToArgb());
        Assert.Equal(UiTheme.Lt.TextPrimary.ToArgb(), UiTheme.TextPrimary.ToArgb());
    }

    [StaFact]
    public void ThemeSwitcher_RemapsControlTree_BothWays()
    {
        using var form = new Form { BackColor = UiTheme.Lt.AppBackground };
        var card = new Panel { BackColor = Color.White };
        var label = new Label { ForeColor = UiTheme.Lt.TextPrimary };
        var input = new TextBox { BackColor = Color.White };
        card.Controls.Add(label);
        form.Controls.Add(card);
        form.Controls.Add(input);

        try
        {
            ThemeSwitcher.SwitchTo(true, form);
            Assert.Equal(UiTheme.Dk.AppBackground.ToArgb(), form.BackColor.ToArgb());
            Assert.Equal(UiTheme.Dk.CardBackground.ToArgb(), card.BackColor.ToArgb());
            Assert.Equal(UiTheme.Dk.TextPrimary.ToArgb(), label.ForeColor.ToArgb());
            Assert.Equal(UiTheme.Dk.InputBackground.ToArgb(), input.BackColor.ToArgb());
        }
        finally
        {
            ThemeSwitcher.SwitchTo(false, form);
        }

        Assert.Equal(UiTheme.Lt.AppBackground.ToArgb(), form.BackColor.ToArgb());
        Assert.Equal(Color.White.ToArgb(), card.BackColor.ToArgb());
        Assert.Equal(UiTheme.Lt.TextPrimary.ToArgb(), label.ForeColor.ToArgb());
        Assert.Equal(Color.White.ToArgb(), input.BackColor.ToArgb());
    }

    [StaFact]
    public void NavRail_ThemeClicked_IsRaised()
    {
        using var rail = new NavRail();
        var raised = false;
        rail.ThemeClicked += (_, _) => raised = true;
        rail.PerformThemeClick();
        Assert.True(raised);
    }
}

public class AboutFormTests
{
    [Fact]
    public void About_ContainsDescriptionAuthorAndMitLicense()
    {
        Assert.Contains("SQL Server", AboutForm.Description);
        Assert.Contains("Manual Actions", AboutForm.Description);
        Assert.Contains("Ravi Sharma", AboutForm.Credits);
        Assert.Contains("MIT License", AboutForm.MitLicense);
        Assert.Contains("Copyright (c) 2026 Ravi Sharma", AboutForm.MitLicense);
        Assert.Contains("WITHOUT WARRANTY OF ANY KIND", AboutForm.MitLicense);
        Assert.StartsWith("Version ", AboutForm.VersionText);
    }

    [StaFact]
    public void AboutForm_Constructs_WithExpectedTitle()
    {
        using var dlg = new AboutForm();
        Assert.Contains("About SQL Optima", dlg.Text);
    }
}

public class QuickHelpFormTests
{
    [Fact]
    public void HelpContent_CoversWorkflowFeaturesAndSafety()
    {
        Assert.Contains("QUICK START", QuickHelpForm.HelpContent);
        Assert.Contains("One-to-Many", QuickHelpForm.HelpContent);
        Assert.Contains("UNDERSTANDING THE RESULTS", QuickHelpForm.HelpContent);
        Assert.Contains("AUTO-DEPLOY (APPLY)", QuickHelpForm.HelpContent);
        Assert.Contains("SCRIPTS AND MANUAL ACTIONS", QuickHelpForm.HelpContent);
        Assert.Contains("SECURITY AND TROUBLESHOOTING", QuickHelpForm.HelpContent);
    }

    [StaFact]
    public void QuickHelpForm_UsesScrollableRichTextContent()
    {
        using var dlg = new QuickHelpForm();
        var content = FindAll<RichTextBox>(dlg).Single();

        Assert.True(content.ReadOnly);
        Assert.Equal(RichTextBoxScrollBars.ForcedVertical, content.ScrollBars);
        Assert.Contains("Quick Help", dlg.Text);
    }

    private static IEnumerable<T> FindAll<T>(Control root) where T : Control
    {
        foreach (Control child in root.Controls)
        {
            if (child is T match) yield return match;
            foreach (var nested in FindAll<T>(child)) yield return nested;
        }
    }
}
