// =============================================================================
// Module:   SqlOptima.SchemaCompare.Forms.AboutForm
// Purpose:  About dialog - what the app does, who built it and why (extract
//           from README.md), version info, and the full MIT license text.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Reflection;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>
/// Modal About dialog. Content is a curated extract of README.md so it stays
/// accurate even when the app ships as a single EXE without the README.
/// </summary>
public sealed class AboutForm : Form
{
    /// <summary>Product description shown in the dialog (README extract).</summary>
    public const string Description =
        "SQL Optima - Schema Compare is a Windows desktop application (WinForms, .NET 8) " +
        "for comparing SQL Server schemas and generating reviewable sync scripts - " +
        "inspired by OpenDBDiff and powered by the bundled schema_compare PowerShell " +
        "engine (dbatools/SMO).\r\n\r\n" +
        "What it does:\r\n" +
        "  \u2022 Connects to a Source (\"source of truth\") and one or more Target databases.\r\n" +
        "  \u2022 Diffs all user objects - schemas, tables (columns, indexes, FKs, constraints,\r\n" +
        "    triggers), views, procedures, functions, UDTs, sequences, and synonyms.\r\n" +
        "  \u2022 Shows differences color-coded as Added / Removed / Changed / Identical /\r\n" +
        "    Ignored in an Object Explorer with search and filters.\r\n" +
        "  \u2022 Generates an ordered, self-contained deployable .sql script, plus a separate\r\n" +
        "    Manual Actions list for risky changes that must be reviewed and run by hand.\r\n" +
        "  \u2022 Supports One-to-Many fan-out, HTML reports, and optional auto-deploy with\r\n" +
        "    per-database progress and post-apply verification.\r\n\r\n" +
        "Nothing is ever applied automatically unless you explicitly enable Apply.";

    /// <summary>Who built it and why (README credit section).</summary>
    public const string Credits =
        "Built by Ravi Sharma as part of the DBA essential scripts toolkit - to give " +
        "DBAs and developers a safe, reviewable way to keep SQL Server schemas in sync " +
        "across Dev, UAT, and Production without hand-writing migration scripts.\r\n\r\n" +
        "UI concept inspired by OpenDBDiff. Compare engine: the bundled schema_compare " +
        "PowerShell toolkit.";

    /// <summary>Full MIT license text (SPDX: MIT).</summary>
    public const string MitLicense =
        "MIT License\r\n\r\n" +
        "Copyright (c) 2026 Ravi Sharma\r\n\r\n" +
        "Permission is hereby granted, free of charge, to any person obtaining a copy " +
        "of this software and associated documentation files (the \"Software\"), to deal " +
        "in the Software without restriction, including without limitation the rights " +
        "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell " +
        "copies of the Software, and to permit persons to whom the Software is " +
        "furnished to do so, subject to the following conditions:\r\n\r\n" +
        "The above copyright notice and this permission notice shall be included in all " +
        "copies or substantial portions of the Software.\r\n\r\n" +
        "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR " +
        "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, " +
        "FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE " +
        "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER " +
        "LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, " +
        "OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE " +
        "SOFTWARE.";

    /// <summary>Version string shown under the title, e.g. "Version 1.0.0".</summary>
    public static string VersionText
    {
        get
        {
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            return "Version " + (v == null ? "1.0" : $"{v.Major}.{v.Minor}.{v.Build}");
        }
    }

    public AboutForm()
    {
        Text = "About SQL Optima - Schema Compare";
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        ClientSize = new Size(640, 660);
        BackColor = UiTheme.AppBackground;
        Font = UiTheme.UiFont();

        // Dark brand header (matches the main shell chrome in both themes).
        var header = new Panel { Dock = DockStyle.Top, Height = 84, BackColor = UiTheme.HeaderBackground };
        header.Controls.Add(new Label
        {
            Text = "SQL Optima \u2014 Schema Compare",
            ForeColor = UiTheme.TextOnDark,
            Font = UiTheme.TitleFont(),
            AutoSize = true,
            Location = new Point(20, 16),
            BackColor = Color.Transparent
        });
        header.Controls.Add(new Label
        {
            Text = VersionText + "  \u00b7  MIT licensed  \u00b7  \u00a9 2026 Ravi Sharma",
            ForeColor = UiTheme.TextOnDarkMuted,
            Font = UiTheme.UiFont(9f),
            AutoSize = true,
            Location = new Point(21, 48),
            BackColor = Color.Transparent
        });
        header.Controls.Add(new Panel { Dock = DockStyle.Bottom, Height = 2, BackColor = UiTheme.HeaderAccent });

        var footer = new Panel { Dock = DockStyle.Bottom, Height = 56, BackColor = UiTheme.AppBackground };
        var btnClose = new ModernButton { Text = "Close", Width = 100, Height = 34 };
        UiTheme.StyleSecondary(btnClose);
        btnClose.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        btnClose.Location = new Point(ClientSize.Width - btnClose.Width - 20, 10);
        btnClose.Click += (_, _) => Close();
        footer.Controls.Add(btnClose);
        CancelButton = btnClose;

        var body = new Panel { Dock = DockStyle.Fill, Padding = new Padding(20, 14, 20, 4), BackColor = UiTheme.AppBackground };

        var txtLicense = new TextBox
        {
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Vertical,
            WordWrap = true,
            Dock = DockStyle.Bottom,
            Height = 170,
            BorderStyle = BorderStyle.FixedSingle,
            BackColor = UiTheme.InputBackground,
            ForeColor = UiTheme.TextMuted,
            Font = UiTheme.UiFont(8.5f),
            Text = MitLicense,
            TabStop = false
        };

        var lblLicenseTitle = new Label
        {
            Text = "LICENSE",
            Dock = DockStyle.Bottom,
            Height = 24,
            ForeColor = UiTheme.TextMuted,
            Font = UiTheme.SemiBold(8.5f),
            TextAlign = ContentAlignment.BottomLeft,
            BackColor = Color.Transparent
        };

        var txtAbout = new TextBox
        {
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Vertical,
            WordWrap = true,
            Dock = DockStyle.Fill,
            BorderStyle = BorderStyle.None,
            BackColor = UiTheme.CardBackground,
            ForeColor = UiTheme.TextPrimary,
            Font = UiTheme.UiFont(9.5f),
            Text = Description + "\r\n\r\n" + new string('\u2500', 40) + "\r\n\r\n" + Credits,
            TabStop = false
        };
        var aboutCard = new Panel
        {
            Dock = DockStyle.Fill,
            BackColor = UiTheme.CardBackground,
            Padding = new Padding(14, 12, 14, 12)
        };
        aboutCard.Controls.Add(txtAbout);

        body.Controls.Add(aboutCard);
        body.Controls.Add(lblLicenseTitle);
        body.Controls.Add(txtLicense);

        Controls.Add(body);
        Controls.Add(footer);
        Controls.Add(header);
    }
}
