// =============================================================================
// Module:   SqlOptima.SchemaCompare.Forms.QuickHelpForm
// Purpose:  Scrollable, detailed in-app guide covering features, setup,
//           comparison, review, deployment, reports, and safe-use guidance.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>Detailed, scrollable instructions for using Schema Compare.</summary>
public sealed class QuickHelpForm : Form
{
    public const string HelpContent =
        "WHAT SQL OPTIMA SCHEMA COMPARE DOES\r\n" +
        "\r\n" +
        "SQL Optima compares the structure of a Source SQL Server database (the source " +
        "of truth) with one or more Target databases. It identifies missing, changed, " +
        "extra, identical, and ignored objects, then generates ordered SQL scripts and " +
        "an HTML report. Changes are never applied unless you explicitly enable Apply.\r\n" +
        "\r\n" +
        "Objects include schemas, tables, columns, primary and foreign keys, indexes, " +
        "constraints, triggers, views, stored procedures, functions, user-defined types, " +
        "sequences, and synonyms.\r\n" +
        "\r\n" +
        "QUICK START\r\n" +
        "\r\n" +
        "1. CHOOSE THE COMPARISON MODE\r\n" +
        "   • One-to-One compares one Source database with one Target database.\r\n" +
        "   • One-to-Many compares one Source database with several Target databases. " +
        "Select databases from the checklist or provide a JSON, YAML, or text destination list.\r\n" +
        "\r\n" +
        "2. CONFIGURE THE SOURCE\r\n" +
        "   • Enter the SQL Server host or host\\INSTANCE name.\r\n" +
        "   • Enter a port only when required; the normal SQL Server port is 1433.\r\n" +
        "   • Select Windows Authentication or SQL Login.\r\n" +
        "   • For SQL Login, provide the username and password.\r\n" +
        "   • Click Test Connection. After it succeeds, click Browse and select the Source database.\r\n" +
        "\r\n" +
        "3. CONFIGURE THE TARGET\r\n" +
        "   • Enter and test the Target connection in the same way.\r\n" +
        "   • Click Browse and select one database, or check all required databases in One-to-Many mode.\r\n" +
        "   • Use the swap button only when you intentionally want the current Target to become the Source.\r\n" +
        "\r\n" +
        "4. REVIEW OPTIONS BEFORE COMPARING\r\n" +
        "   • Settings controls connection defaults such as protocol, timeout, and TLS behavior.\r\n" +
        "   • Advanced Options controls script generation and deployment behavior.\r\n" +
        "   • Configure ignore rules for schemas or objects that should not participate in the comparison.\r\n" +
        "   • Choose an output folder if you do not want to use schema_compare\\output.\r\n" +
        "\r\n" +
        "5. RUN THE COMPARISON\r\n" +
        "   • Click Compare Now or Compare Schemas.\r\n" +
        "   • Follow the progress bar and Progress Log. One-to-Many runs report progress per database.\r\n" +
        "   • You can cancel a running comparison; child PowerShell processes are cleaned up automatically.\r\n" +
        "\r\n" +
        "UNDERSTANDING THE RESULTS\r\n" +
        "\r\n" +
        "Object Explorer\r\n" +
        "   • Added / Missing in Target: exists in Source and needs to be created on Target.\r\n" +
        "   • Changed / Definition Mismatch: exists on both sides but definitions differ.\r\n" +
        "   • Removed / Extra in Target: exists only on Target. Review carefully before dropping it.\r\n" +
        "   • Identical: definitions match.\r\n" +
        "   • Ignored: excluded by an ignore rule.\r\n" +
        "Use search and object-type filters to narrow the tree. Select a mismatched object to view " +
        "Source and Target definitions side by side; drag the vertical separator to resize either pane.\r\n" +
        "\r\n" +
        "Result tabs\r\n" +
        "   • Overview summarizes object counts and warnings.\r\n" +
        "   • Object Details shows the selected object's Source and Target definitions.\r\n" +
        "   • Script Preview shows the ordered deployable SQL generated for safe automatic changes.\r\n" +
        "   • Manual Actions lists risky changes requiring review and manual execution.\r\n" +
        "   • Deployment shows per-database apply status, errors, and post-deployment verification.\r\n" +
        "   • Progress Log shows detailed engine output useful for diagnosis.\r\n" +
        "\r\n" +
        "SCRIPTS AND MANUAL ACTIONS\r\n" +
        "\r\n" +
        "Click Save Script to save the combined deployable SQL. Always review it before execution, " +
        "especially DROP operations, destructive column changes, and dependency changes.\r\n" +
        "\r\n" +
        "Manual Actions are intentionally excluded from normal automatic deployment. Run them in the " +
        "displayed order. For a primary-key column datatype change, follow the generated sequence: " +
        "drop referencing foreign keys, drop the parent primary key, alter the parent column, drop child " +
        "indexes that use foreign-key columns, alter child columns, then recreate keys and indexes.\r\n" +
        "\r\n" +
        "AUTO-DEPLOY (APPLY)\r\n" +
        "\r\n" +
        "Apply is optional and must be explicitly enabled in Advanced Options. Confirm the listed Target " +
        "databases before proceeding. The app applies eligible generated scripts database by database, " +
        "continues reporting other databases if one fails, records script-level errors, and performs a " +
        "fresh comparison afterward to verify whether each Target is synchronized.\r\n" +
        "\r\n" +
        "A successful Apply does not mean Manual Actions were executed. Check both Deployment and Manual " +
        "Actions before declaring a database synchronized. Use a tested backup and an appropriate change " +
        "window for production deployments.\r\n" +
        "\r\n" +
        "OUTPUT, HISTORY, AND REPORTS\r\n" +
        "\r\n" +
        "Each run creates a SchemaSync_* folder under the configured output root. It contains generated SQL, " +
        "manifest and result data, deployment details when applicable, and an HTML comparison report.\r\n" +
        "\r\n" +
        "   • History opens the output root containing previous SchemaSync_* runs.\r\n" +
        "   • Scripts opens Script Preview when results are loaded, or the output location otherwise.\r\n" +
        "   • Reports opens the latest generated HTML report.\r\n" +
        "\r\n" +
        "SECURITY AND TROUBLESHOOTING\r\n" +
        "\r\n" +
        "Passwords are not stored in session settings. They are passed to the comparison process through " +
        "temporary environment variables and cleared afterward. If connection testing fails, verify host, " +
        "instance, port, authentication, firewall access, SQL permissions, and certificate/TLS settings.\r\n" +
        "\r\n" +
        "For comparison or deployment failures, read Progress Log first, then inspect the run folder and HTML " +
        "report. Correct the connection, permissions, object dependency, or SQL issue and run the comparison again.\r\n" +
        "\r\n" +
        "OTHER CONTROLS\r\n" +
        "\r\n" +
        "   • Presets selects a saved comparison profile.\r\n" +
        "   • Theme at the bottom of the left rail switches between light and dark mode.\r\n" +
        "   • About SQL Optima shows product, author, version, purpose, and MIT license information.";

    public QuickHelpForm()
    {
        Text = "Quick Help — SQL Optima Schema Compare";
        StartPosition = FormStartPosition.CenterParent;
        MinimumSize = new Size(640, 520);
        ClientSize = new Size(760, 720);
        ShowInTaskbar = false;
        BackColor = UiTheme.AppBackground;
        Font = UiTheme.UiFont();

        var header = new Panel
        {
            Dock = DockStyle.Top,
            Height = 76,
            BackColor = UiTheme.HeaderBackground
        };
        header.Controls.Add(new Label
        {
            Text = "Quick Help",
            AutoSize = true,
            Location = new Point(20, 13),
            ForeColor = UiTheme.TextOnDark,
            Font = UiTheme.TitleFont(),
            BackColor = Color.Transparent
        });
        header.Controls.Add(new Label
        {
            Text = "Detailed workflow, features, deployment, and troubleshooting",
            AutoSize = true,
            Location = new Point(21, 43),
            ForeColor = UiTheme.TextOnDarkMuted,
            Font = UiTheme.UiFont(9f),
            BackColor = Color.Transparent
        });
        header.Controls.Add(new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 2,
            BackColor = UiTheme.HeaderAccent
        });

        var footer = new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 56,
            Padding = new Padding(0, 10, 20, 10),
            BackColor = UiTheme.AppBackground
        };
        var close = new ModernButton
        {
            Text = "Close",
            Dock = DockStyle.Right,
            Width = 100
        };
        UiTheme.StyleSecondary(close);
        close.Click += (_, _) => Close();
        footer.Controls.Add(close);
        CancelButton = close;

        var contentHost = new Panel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(18, 16, 18, 8),
            BackColor = UiTheme.AppBackground
        };
        var content = new RichTextBox
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            DetectUrls = false,
            WordWrap = true,
            ScrollBars = RichTextBoxScrollBars.ForcedVertical,
            BorderStyle = BorderStyle.FixedSingle,
            BackColor = UiTheme.CardBackground,
            ForeColor = UiTheme.TextPrimary,
            Font = UiTheme.UiFont(10f),
            Text = HelpContent,
            TabStop = false,
            ZoomFactor = 1.0f
        };
        contentHost.Controls.Add(content);

        Controls.Add(contentHost);
        Controls.Add(footer);
        Controls.Add(header);
    }
}
