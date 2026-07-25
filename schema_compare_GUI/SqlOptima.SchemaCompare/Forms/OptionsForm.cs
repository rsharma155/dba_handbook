// =============================================================================
// Module:   SqlOptima.SchemaCompare.Forms.OptionsForm
// Purpose:  Tabbed compare options dialog - Ignore rules, Scripts, Connection,
//           and Output. Entry points (Settings / Advanced / Ignore rules /
//           Profile) open the matching tab so each button has a clear purpose.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>Which section of the options dialog to show first.</summary>
public enum OptionsFocus
{
    /// <summary>Header Settings gear — full options, Connection tab first.</summary>
    Settings,

    /// <summary>Advanced Options — Scripts tab (generate / drops / apply).</summary>
    Advanced,

    /// <summary>Configure ignore rules — Ignore rules tab.</summary>
    IgnoreRules,

    /// <summary>Comparison profile pencil — Scripts tab (profile behaviour).</summary>
    Profile
}

public sealed class OptionsForm : Form
{
    private readonly TabControl _tabs = new();
    private readonly CheckBox _chkGenerate = new() { Text = "Generate sync scripts (auto_ / manual_)", Checked = true };
    private readonly CheckBox _chkDrops = new()
    {
        Text = "Include drops for non-table objects (views, procs, indexes…)"
    };
    private readonly Label _lblDropsHint = new()
    {
        Text = "DROP TABLE is never auto-applied — always written as a manual_ script for review.",
        AutoSize = true,
        MaximumSize = new Size(500, 0),
        ForeColor = UiTheme.Warning,
        Font = UiTheme.UiFont(9f)
    };
    private readonly CheckBox _chkApply = new() { Text = "Apply auto_ scripts on target after compare" };
    private readonly CheckBox _chkTrust = new() { Text = "Trust server certificate", Checked = true };
    private readonly ComboBox _cmbProtocol = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
    private readonly NumericUpDown _numTimeout = new() { Minimum = 5, Maximum = 300, Value = 30, Width = 88 };
    private readonly TextBox _txtExclude = new() { Width = 440, Text = "sys,INFORMATION_SCHEMA,guest" };
    private readonly TextBox _txtOutput = new() { Width = 360 };
    private readonly ModernButton _btnBrowse = new() { Text = "Browse…", Width = 96, Height = 32 };
    private readonly Label _hdrTitle = new();
    private readonly Label _hdrSubtitle = new();

    public CompareOptions Options { get; private set; }

    /// <summary>Tab that was selected when the dialog opened (for tests).</summary>
    public string InitialTabText { get; private set; } = "";

    public OptionsForm(CompareOptions current, OptionsFocus focus = OptionsFocus.Settings)
    {
        Options = current;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MinimizeBox = false;
        MaximizeBox = false;
        ShowInTaskbar = false;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(600, 560);
        Font = UiTheme.UiFont();
        BackColor = UiTheme.AppBackground;
        ForeColor = UiTheme.TextPrimary;

        ApplyFocusChrome(focus);

        var header = new Panel
        {
            Dock = DockStyle.Top,
            Height = 56,
            BackColor = UiTheme.HeaderBackground,
            Padding = new Padding(UiTheme.Margin, 0, UiTheme.Margin, 0)
        };
        _hdrTitle.ForeColor = UiTheme.TextOnDark;
        _hdrTitle.Font = UiTheme.SemiBold(13f);
        _hdrTitle.AutoSize = true;
        _hdrTitle.Location = new Point(UiTheme.Margin, 10);
        _hdrTitle.BackColor = Color.Transparent;
        _hdrSubtitle.ForeColor = UiTheme.TextOnDarkMuted;
        _hdrSubtitle.Font = UiTheme.UiFont(9f);
        _hdrSubtitle.AutoSize = true;
        _hdrSubtitle.Location = new Point(UiTheme.Margin, 32);
        _hdrSubtitle.BackColor = Color.Transparent;
        header.Controls.Add(_hdrTitle);
        header.Controls.Add(_hdrSubtitle);

        var accent = new Panel
        {
            Dock = DockStyle.Top,
            Height = 3,
            BackColor = UiTheme.HeaderAccent
        };

        var footer = BuildFooter(out var ok, out var cancel);

        _tabs.Dock = DockStyle.Fill;
        _tabs.Font = UiTheme.UiFont(9.5f);
        _tabs.Padding = new Point(12, 6);
        _tabs.TabPages.Add(BuildIgnoreTab(current));
        _tabs.TabPages.Add(BuildScriptsTab(current));
        _tabs.TabPages.Add(BuildConnectionTab(current));
        _tabs.TabPages.Add(BuildOutputTab(current));

        // Dock order: Fill first, then Bottom, then Top (last Top sits at the outer edge).
        Controls.Add(_tabs);
        Controls.Add(footer);
        Controls.Add(accent);
        Controls.Add(header);

        SelectTabForFocus(focus);
        InitialTabText = _tabs.SelectedTab?.Text ?? "";

        ok.Click += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(_txtOutput.Text))
            {
                MessageBox.Show(this, "Output folder is required.", "Validation",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                DialogResult = DialogResult.None;
                _tabs.SelectedIndex = 3; // Output
                return;
            }
            Options = new CompareOptions
            {
                NetworkProtocol = _cmbProtocol.SelectedItem?.ToString() ?? "TcpIp",
                ConnectionTimeout = (int)_numTimeout.Value,
                TrustServerCertificate = _chkTrust.Checked,
                GenerateSyncScript = _chkGenerate.Checked,
                IncludeDrops = _chkDrops.Checked,
                Apply = _chkApply.Checked,
                ExcludeSchemas = _txtExclude.Text.Trim(),
                OutputPath = _txtOutput.Text.Trim()
            };
        };

        AcceptButton = ok;
        CancelButton = cancel;
    }

    private void ApplyFocusChrome(OptionsFocus focus)
    {
        switch (focus)
        {
            case OptionsFocus.IgnoreRules:
                Text = "Ignore rules";
                _hdrTitle.Text = "Ignore rules";
                _hdrSubtitle.Text = "Schemas (and later patterns) skipped during schema compare.";
                break;
            case OptionsFocus.Advanced:
                Text = "Advanced options";
                _hdrTitle.Text = "Advanced options";
                _hdrSubtitle.Text = "Script generation, apply behaviour, connection, and output paths.";
                break;
            case OptionsFocus.Profile:
                Text = "Comparison profile";
                _hdrTitle.Text = "Comparison profile";
                _hdrSubtitle.Text = "Default Profile settings used when you click Compare Now.";
                break;
            default:
                Text = "Settings";
                _hdrTitle.Text = "Settings";
                _hdrSubtitle.Text = "Application compare settings — ignore rules, scripts, connection, output.";
                break;
        }
    }

    private void SelectTabForFocus(OptionsFocus focus)
    {
        _tabs.SelectedIndex = focus switch
        {
            OptionsFocus.IgnoreRules => 0,
            OptionsFocus.Advanced => 1,
            OptionsFocus.Profile => 1,
            OptionsFocus.Settings => 2,
            _ => 0
        };
    }

    private Panel BuildFooter(out ModernButton ok, out ModernButton cancel)
    {
        var footer = new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 64,
            BackColor = UiTheme.PanelBackground,
            Padding = new Padding(UiTheme.Margin)
        };
        footer.Paint += (_, e) =>
        {
            using var pen = new Pen(UiTheme.CardBorder);
            e.Graphics.DrawLine(pen, 0, 0, footer.Width, 0);
        };

        ok = new ModernButton
        {
            Text = "OK",
            DialogResult = DialogResult.OK,
            Width = 108,
            Height = UiTheme.ButtonHeight,
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };
        cancel = new ModernButton
        {
            Text = "Cancel",
            DialogResult = DialogResult.Cancel,
            Width = 108,
            Height = UiTheme.ButtonHeight,
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };
        UiTheme.StylePrimary(ok);
        UiTheme.StyleSecondary(cancel);
        cancel.Height = UiTheme.ButtonHeight;

        var okBtn = ok;
        var cancelBtn = cancel;
        void Place()
        {
            cancelBtn.Location = new Point(footer.ClientSize.Width - cancelBtn.Width - UiTheme.Margin, 12);
            okBtn.Location = new Point(cancelBtn.Left - UiTheme.ControlGap - okBtn.Width, 12);
        }
        footer.Resize += (_, _) => Place();
        footer.Controls.Add(okBtn);
        footer.Controls.Add(cancelBtn);
        Place();
        return footer;
    }

    private TabPage BuildIgnoreTab(CompareOptions current)
    {
        var page = new TabPage("Ignore rules") { BackColor = Color.White, Padding = new Padding(16) };
        var y = 12;
        page.Controls.Add(MakeHelp(
            "Objects in these schemas are excluded from the comparison. " +
            "Comma-separated names, case-insensitive. System schemas are listed by default.",
            12, y, 540));
        y += 48;

        page.Controls.Add(UiTheme.MakeLabel("Exclude schemas", 12, y + 6));
        UiTheme.StyleTextBox(_txtExclude);
        _txtExclude.Text = current.ExcludeSchemas;
        _txtExclude.Location = new Point(140, y);
        _txtExclude.Width = 420;
        _txtExclude.Height = UiTheme.InputHeight;
        page.Controls.Add(_txtExclude);
        y += 44;

        page.Controls.Add(MakeHelp(
            "Tip: add custom schemas you never want synced (e.g. staging, audit). " +
            "Object-name ignore patterns will appear here in a later release.",
            12, y, 540));
        return page;
    }

    private TabPage BuildScriptsTab(CompareOptions current)
    {
        var page = new TabPage("Scripts") { BackColor = Color.White, Padding = new Padding(16) };
        var y = 12;
        page.Controls.Add(MakeHelp(
            "Controls what SQL the engine writes after a compare, and whether auto_ scripts may run on the target.",
            12, y, 540));
        y += 44;

        UiTheme.StyleCheckBox(_chkGenerate);
        _chkGenerate.Checked = current.GenerateSyncScript;
        _chkGenerate.Location = new Point(12, y);
        page.Controls.Add(_chkGenerate);
        y += 32;

        UiTheme.StyleCheckBox(_chkDrops);
        _chkDrops.Checked = current.IncludeDrops;
        _chkDrops.Location = new Point(12, y);
        page.Controls.Add(_chkDrops);
        y += 28;

        _lblDropsHint.Location = new Point(34, y);
        page.Controls.Add(_lblDropsHint);
        y += 36;

        UiTheme.StyleCheckBox(_chkApply);
        _chkApply.FlatStyle = FlatStyle.Standard;
        _chkApply.Checked = current.Apply;
        _chkApply.ForeColor = UiTheme.Danger;
        _chkApply.Location = new Point(12, y);
        page.Controls.Add(_chkApply);
        y += 36;

        page.Controls.Add(MakeHelp(
            "Leave Apply off until you have reviewed Script Preview and Manual Actions.",
            12, y, 540));
        return page;
    }

    private TabPage BuildConnectionTab(CompareOptions current)
    {
        var page = new TabPage("Connection") { BackColor = Color.White, Padding = new Padding(16) };
        var y = 12;
        page.Controls.Add(MakeHelp(
            "Defaults used when testing connections and running the compare engine (protocol / timeout / TLS).",
            12, y, 540));
        y += 48;

        page.Controls.Add(UiTheme.MakeLabel("Network protocol", 12, y + 6));
        _cmbProtocol.Items.AddRange(new object[] { "TcpIp", "NamedPipes", "SharedMemory" });
        _cmbProtocol.SelectedItem = current.NetworkProtocol;
        if (_cmbProtocol.SelectedIndex < 0) _cmbProtocol.SelectedIndex = 0;
        _cmbProtocol.Location = new Point(160, y);
        _cmbProtocol.Height = UiTheme.InputHeight;
        UiTheme.StyleCombo(_cmbProtocol);
        page.Controls.Add(_cmbProtocol);
        y += 40;

        page.Controls.Add(UiTheme.MakeLabel("Timeout (seconds)", 12, y + 6));
        _numTimeout.Value = Math.Clamp(current.ConnectionTimeout, 5, 300);
        _numTimeout.Location = new Point(160, y);
        UiTheme.StyleNumeric(_numTimeout);
        page.Controls.Add(_numTimeout);
        y += 40;

        UiTheme.StyleCheckBox(_chkTrust);
        _chkTrust.Checked = current.TrustServerCertificate;
        _chkTrust.Location = new Point(12, y);
        page.Controls.Add(_chkTrust);
        return page;
    }

    private TabPage BuildOutputTab(CompareOptions current)
    {
        var page = new TabPage("Output") { BackColor = Color.White, Padding = new Padding(16) };
        var y = 12;
        page.Controls.Add(MakeHelp(
            "Where SchemaSync_* run folders, HTML reports, and Save Script exports are written. " +
            "History / Scripts / Reports in the nav rail all use this same root.",
            12, y, 540));
        y += 56;

        page.Controls.Add(UiTheme.MakeLabel("Output folder", 12, y + 6));
        UiTheme.StyleTextBox(_txtOutput);
        _txtOutput.Text = current.OutputPath;
        _txtOutput.Location = new Point(140, y);
        _txtOutput.Height = UiTheme.InputHeight;
        _txtOutput.Width = 320;
        page.Controls.Add(_txtOutput);

        UiTheme.StyleSecondary(_btnBrowse);
        _btnBrowse.Height = UiTheme.InputHeight;
        _btnBrowse.Location = new Point(_txtOutput.Right + UiTheme.ControlGap, y);
        _btnBrowse.Click += (_, _) =>
        {
            using var dlg = new FolderBrowserDialog { Description = "Sync script output folder" };
            if (!string.IsNullOrWhiteSpace(_txtOutput.Text) && Directory.Exists(_txtOutput.Text))
                dlg.SelectedPath = _txtOutput.Text;
            if (dlg.ShowDialog(this) == DialogResult.OK)
                _txtOutput.Text = dlg.SelectedPath;
        };
        page.Controls.Add(_btnBrowse);
        return page;
    }

    private static Label MakeHelp(string text, int x, int y, int maxWidth) => new()
    {
        Text = text,
        AutoSize = true,
        MaximumSize = new Size(maxWidth, 0),
        Location = new Point(x, y),
        ForeColor = UiTheme.TextMuted,
        Font = UiTheme.UiFont(9f),
        BackColor = Color.Transparent
    };
}
