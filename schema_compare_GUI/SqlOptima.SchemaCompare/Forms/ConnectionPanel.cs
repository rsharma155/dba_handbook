// =============================================================================
// Module:   SqlOptima.SchemaCompare.Forms.ConnectionPanel
// Purpose:  Source/Target connection card - server, port, authentication,
//           credentials with show/hide password, database picker with Browse,
//           Test Connection with inline success/failure feedback.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>
/// Connection card using table/flow layout so labels, radios, and buttons
/// never truncate or overlap under DPI scaling.
/// </summary>
public sealed class ConnectionPanel : UserControl
{
    private readonly Label _title;
    private readonly Label _hint;
    private readonly Label _statusBadge;
    private readonly TextBox _txtInstance = new();
    private readonly TextBox _txtPort = new();
    private readonly RadioButton _rbWindows = new() { Text = "Windows", Checked = true, AutoSize = true };
    private readonly RadioButton _rbSql = new() { Text = "SQL Login", AutoSize = true };
    private readonly TextBox _txtUser = new();
    private readonly TextBox _txtPassword = new() { UseSystemPasswordChar = true };
    private readonly ComboBox _cmbDatabase = new() { DropDownStyle = ComboBoxStyle.DropDown };
    private readonly Label _lblDatabase;
    private readonly TextBox? _txtDbSearch;
    private readonly CheckedListBox? _clbDatabases;
    private readonly ModernButton _btnTest = new() { Text = "Test Connection" };
    private readonly ModernButton _btnBrowse = new() { Text = "Browse" };
    private readonly ModernButton _btnEye = new() { Text = "\uE7B3" }; // MDL2 RedEye
    private readonly Label _lblConnMsg = new() { AutoSize = true, Visible = false };
    private readonly ToolTip _tips = new();
    private ModernButton? _btnSelectAll;
    private ModernButton? _btnClear;
    private Label? _lblSelection;
    private readonly ErrorProvider _errors = new() { BlinkStyle = ErrorBlinkStyle.NeverBlink };
    private readonly TableLayoutPanel _grid;
    private readonly Panel _footer = new() { Dock = DockStyle.Fill, BackColor = Color.Transparent };
    private readonly bool _supportsMulti;
    private bool _multiSelectActive;
    private readonly string _sideLabel;
    private readonly Color _accent;
    private List<string> _allDatabases = new();
    private HashSet<string> _checkedRemember = new(StringComparer.OrdinalIgnoreCase);
    private bool _suppressDbEvent;

    public event EventHandler? TestClicked;
    public event EventHandler? RefreshClicked;
    public event EventHandler? DatabaseSelectionChanged;

    public ConnectionPanel(string title, bool multiSelectTargets = false)
    {
        _supportsMulti = multiSelectTargets;
        _multiSelectActive = multiSelectTargets;
        _sideLabel = multiSelectTargets ? "Destination" : "Source";
        _accent = multiSelectTargets ? UiTheme.Success : UiTheme.Primary;

        AutoScaleMode = AutoScaleMode.Dpi;
        BorderStyle = BorderStyle.None;
        BackColor = Color.Transparent;
        MinimumSize = new Size(380, multiSelectTargets ? 260 : 200);
        DoubleBuffered = true;
        Padding = new Padding(2);

        Paint += (_, e) =>
        {
            var g = e.Graphics;
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            var rect = new Rectangle(0, 0, Width - 1, Height - 1);
            using var path = RoundRect(rect, 10);
            using var fill = new SolidBrush(UiTheme.CardBackground);
            using var border = new Pen(UiTheme.CardBorder);
            g.FillPath(fill, path);
            g.DrawPath(border, path);
        };

        // Rows: title, hint, server, auth, user/pass, database, [list], footer
        _grid = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 4,
            RowCount = multiSelectTargets ? 8 : 7,
            Padding = new Padding(12, 8, 12, 4),
            BackColor = UiTheme.CardBackground
        };
        // Label | field | aux label | aux field — tight, aligned columns
        _grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 104));
        _grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        _grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 68));
        _grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 112));

        _grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));  // title
        _grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 18));  // hint
        _grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));  // server
        _grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));  // auth
        _grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));  // user/pass
        _grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));  // database
        if (multiSelectTargets)
            _grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 0f)); // list (grows when multi)
        _grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));  // footer — tight under DB

        Controls.Add(_grid);

        // Row 0 — title + status
        _title = new Label
        {
            Text = title,
            Font = UiTheme.SectionFont(),
            ForeColor = UiTheme.TextPrimary,
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 0, 0, 0)
        };
        _statusBadge = new Label
        {
            Text = "\u25CF  Not connected",
            AutoSize = true,
            Font = UiTheme.SemiBold(8.5f),
            ForeColor = UiTheme.TextMuted,
            BackColor = Color.FromArgb(243, 244, 246),
            Padding = new Padding(6, 2, 6, 2),
            Anchor = AnchorStyles.Right,
            Margin = new Padding(4, 0, 0, 0),
            TextAlign = ContentAlignment.MiddleRight
        };
        _grid.Controls.Add(_title, 0, 0);
        _grid.SetColumnSpan(_title, 2);
        _grid.Controls.Add(_statusBadge, 2, 0);
        _grid.SetColumnSpan(_statusBadge, 2);

        // Row 1 — hint
        _hint = new Label
        {
            Text = multiSelectTargets
                ? "Choose one or more destination databases"
                : "Connect to the source of truth",
            Font = UiTheme.UiFont(8.5f),
            ForeColor = UiTheme.TextMuted,
            AutoSize = true,
            Dock = DockStyle.Fill,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 0, 0, 0)
        };
        _grid.Controls.Add(_hint, 0, 1);
        _grid.SetColumnSpan(_hint, 4);

        // Row 2 — Server / Port
        _grid.Controls.Add(MakeLabel("Server"), 0, 2);
        UiTheme.StyleTextBox(_txtInstance);
        _txtInstance.Dock = DockStyle.Fill;
        _txtInstance.Margin = new Padding(0, 2, 6, 2);
        _txtInstance.PlaceholderText = "host or .\\INSTANCE";
        _grid.Controls.Add(_txtInstance, 1, 2);

        _grid.Controls.Add(MakeLabel("Port"), 2, 2);
        UiTheme.StyleTextBox(_txtPort);
        _txtPort.Dock = DockStyle.Fill;
        _txtPort.Margin = new Padding(0, 2, 0, 2);
        _txtPort.PlaceholderText = "1433";
        _grid.Controls.Add(_txtPort, 3, 2);

        // Row 3 — Authentication radios
        _grid.Controls.Add(MakeLabel("Authentication"), 0, 3);
        StyleRadio(_rbWindows);
        StyleRadio(_rbSql);
        var authFlow = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            AutoSize = false,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 2, 0, 0),
            Padding = new Padding(0)
        };
        authFlow.Controls.Add(_rbWindows);
        authFlow.Controls.Add(_rbSql);
        _grid.Controls.Add(authFlow, 1, 3);
        _grid.SetColumnSpan(authFlow, 3);
        _rbWindows.CheckedChanged += (_, _) => UpdateAuthUi();
        _rbSql.CheckedChanged += (_, _) => UpdateAuthUi();

        // Row 4 — Username / Password split 50/50 like the mockup
        _grid.Controls.Add(MakeLabel("Username"), 0, 4);
        UiTheme.StyleTextBox(_txtUser);
        _txtUser.Dock = DockStyle.Fill;
        _txtUser.Margin = new Padding(0, 0, 6, 0);
        _txtUser.PlaceholderText = "SQL login";

        UiTheme.StyleTextBox(_txtPassword);
        _txtPassword.Dock = DockStyle.Fill;
        _txtPassword.Margin = new Padding(0);
        _txtPassword.PlaceholderText = "Password";
        _txtPassword.AccessibleName = "Password";
        var pwdHost = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = new Padding(0)
        };
        pwdHost.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        pwdHost.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 28));
        pwdHost.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        _btnEye.Font = UiTheme.IconFont(10f);
        _btnEye.Dock = DockStyle.Fill;
        _btnEye.CornerRadius = 6;
        _btnEye.Margin = new Padding(4, 0, 0, 0);
        _btnEye.ApplyColors(Color.White, UiTheme.TextMuted, UiTheme.NeutralHover, UiTheme.Neutral);
        _btnEye.AccessibleName = "Show password";
        _tips.SetToolTip(_btnEye, "Show / hide password");
        _btnEye.Click += (_, _) => _txtPassword.UseSystemPasswordChar = !_txtPassword.UseSystemPasswordChar;
        pwdHost.Controls.Add(_txtPassword, 0, 0);
        pwdHost.Controls.Add(_btnEye, 1, 0);

        var credRow = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 1,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 2, 0, 2)
        };
        credRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50f));
        credRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 68));
        credRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50f));
        credRow.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        credRow.Controls.Add(_txtUser, 0, 0);
        credRow.Controls.Add(MakeLabel("Password"), 1, 0);
        credRow.Controls.Add(pwdHost, 2, 0);
        _grid.Controls.Add(credRow, 1, 4);
        _grid.SetColumnSpan(credRow, 3);

        // Row 5 — Database (combo / search constrained to field column — aligns with Server)
        _lblDatabase = MakeLabel(multiSelectTargets ? "Databases" : "Database");
        _grid.Controls.Add(_lblDatabase, 0, 5);

        UiTheme.StyleCombo(_cmbDatabase);
        _cmbDatabase.Dock = DockStyle.Fill;
        _cmbDatabase.Margin = new Padding(0, 2, 6, 2);
        _cmbDatabase.DropDownStyle = ComboBoxStyle.DropDown;
        _cmbDatabase.SelectedIndexChanged += (_, _) => OnDatabaseSelectionChanged();
        _cmbDatabase.SelectionChangeCommitted += (_, _) => OnDatabaseSelectionChanged();
        _grid.Controls.Add(_cmbDatabase, 1, 5);
        // No column span — width matches Server field

        // Browse loads the database list from the server (mockup: "Browse")
        UiTheme.StyleSecondary(_btnBrowse);
        _btnBrowse.Height = 28;
        UiTheme.FitButton(_btnBrowse, 96, 24);
        _btnBrowse.Margin = new Padding(0, 2, 0, 2);
        _btnBrowse.AccessibleName = "Browse databases";
        _tips.SetToolTip(_btnBrowse, "Load the database list from this server");
        _grid.Controls.Add(_btnBrowse, 3, 5);

        if (multiSelectTargets)
        {
            _txtDbSearch = new TextBox();
            UiTheme.StyleTextBox(_txtDbSearch);
            _txtDbSearch.Dock = DockStyle.Fill;
            _txtDbSearch.Margin = new Padding(0, 2, 6, 2);
            _txtDbSearch.PlaceholderText = "Search database...";
            _txtDbSearch.TextChanged += (_, _) => ApplyDbFilter();
            _grid.Controls.Add(_txtDbSearch, 1, 5);
            // Constrained to field column like the combo

            _clbDatabases = new CheckedListBox
            {
                CheckOnClick = true,
                Dock = DockStyle.Fill,
                BorderStyle = BorderStyle.FixedSingle,
                IntegralHeight = false,
                Font = UiTheme.UiFont(9.5f),
                ForeColor = UiTheme.TextPrimary,
                BackColor = Color.White,
                Margin = new Padding(0, 2, 0, 2)
            };
            _clbDatabases.ItemCheck += (_, e) =>
            {
                void Sync()
                {
                    var name = _clbDatabases.Items[e.Index]?.ToString() ?? "";
                    if (e.NewValue == CheckState.Checked) _checkedRemember.Add(name);
                    else _checkedRemember.Remove(name);
                    UpdateSelectionLabel();
                    OnDatabaseSelectionChanged();
                }
                if (!IsHandleCreated) { Sync(); return; }
                try { BeginInvoke(Sync); }
                catch (InvalidOperationException) { Sync(); }
            };
            _grid.Controls.Add(_clbDatabases, 1, 6);
            _grid.SetColumnSpan(_clbDatabases, 3);

            SetMultiSelectVisible(false);
        }

        var footerRow = multiSelectTargets ? 7 : 6;
        BuildFooter();
        _grid.Controls.Add(_footer, 0, footerRow);
        _grid.SetColumnSpan(_footer, 4);

        _txtInstance.TextChanged += (_, _) => ClearError(_txtInstance);
        _txtPort.TextChanged += (_, _) => ClearError(_txtPort);
        _txtUser.TextChanged += (_, _) => ClearError(_txtUser);
        _txtPassword.TextChanged += (_, _) => ClearError(_txtPassword);

        UpdateAuthUi();
    }

    private void BuildFooter()
    {
        var flow = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            AutoSize = false,
            BackColor = Color.Transparent,
            Padding = new Padding(0, 4, 0, 2),
            Margin = new Padding(0)
        };

        // Mockup: "Test Connection" bottom-left, inline result message beside it.
        UiTheme.StyleGhost(_btnTest);
        _btnTest.Height = 32;
        FitButton(_btnTest, 128);
        _btnTest.Margin = new Padding(0, 0, 10, 0);
        flow.Controls.Add(_btnTest);

        _lblConnMsg.Font = UiTheme.SemiBold(9f);
        _lblConnMsg.ForeColor = UiTheme.Success;
        _lblConnMsg.BackColor = Color.Transparent;
        _lblConnMsg.Margin = new Padding(0, 9, 12, 0);
        flow.Controls.Add(_lblConnMsg);

        if (_supportsMulti)
        {
            _btnSelectAll = new ModernButton { Text = "Select all", Height = 32 };
            _btnClear = new ModernButton { Text = "Clear", Height = 32 };
            UiTheme.StyleGhost(_btnSelectAll);
            UiTheme.StyleGhost(_btnClear);
            FitButton(_btnSelectAll, 88);
            FitButton(_btnClear, 64);
            _btnSelectAll.Margin = new Padding(0, 0, 6, 0);
            _btnClear.Margin = new Padding(0, 0, 10, 0);
            _btnSelectAll.Click += (_, _) => CheckAllDatabases(true);
            _btnClear.Click += (_, _) => CheckAllDatabases(false);
            flow.Controls.Add(_btnSelectAll);
            flow.Controls.Add(_btnClear);

            _lblSelection = new Label
            {
                Text = "Selected  0",
                AutoSize = true,
                ForeColor = UiTheme.TextMuted,
                Font = UiTheme.SemiBold(9f),
                BackColor = Color.Transparent,
                Margin = new Padding(4, 9, 0, 0)
            };
            flow.Controls.Add(_lblSelection);
        }

        _footer.Controls.Add(flow);

        _btnTest.Click += (_, _) =>
        {
            if (!ValidateForConnection(out var msg))
            {
                MessageBox.Show(FindForm(), msg, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            TestClicked?.Invoke(this, EventArgs.Empty);
        };
        _btnBrowse.Click += (_, _) =>
        {
            if (!ValidateForConnection(out var msg))
            {
                MessageBox.Show(FindForm(), msg, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            RefreshClicked?.Invoke(this, EventArgs.Empty);
        };
    }

    private static void StyleRadio(RadioButton rb)
    {
        rb.AutoSize = true;
        rb.FlatStyle = FlatStyle.System;
        rb.Font = UiTheme.UiFont(9.5f);
        rb.ForeColor = UiTheme.TextPrimary;
        rb.BackColor = Color.Transparent;
        rb.Margin = new Padding(0, 2, 12, 0);
        rb.UseCompatibleTextRendering = true;
        rb.MinimumSize = new Size(TextRenderer.MeasureText(rb.Text, rb.Font).Width + 28, 20);
    }

    private static Label MakeLabel(string text) => new()
    {
        Text = text,
        AutoSize = true,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
        ForeColor = UiTheme.TextMuted,
        Font = UiTheme.UiFont(9f),
        BackColor = Color.Transparent,
        Margin = new Padding(0, 0, 4, 0)
    };

    private static void FitButton(ModernButton b, int minWidth)
    {
        var textW = TextRenderer.MeasureText(b.Text, b.Font).Width;
        b.Width = Math.Max(minWidth, textW + 28);
        b.AutoEllipsis = false;
    }

    private static System.Drawing.Drawing2D.GraphicsPath RoundRect(Rectangle r, int radius)
    {
        var d = radius * 2;
        var p = new System.Drawing.Drawing2D.GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    private void ClearError(Control c) => _errors.SetError(c, "");

    private void UpdateAuthUi()
    {
        var sql = _rbSql.Checked;
        _txtUser.Enabled = sql;
        _txtPassword.Enabled = sql;
        _btnEye.Enabled = sql;
        if (!sql)
        {
            ClearError(_txtUser);
            ClearError(_txtPassword);
        }
    }

    private void UpdateSelectionLabel()
    {
        if (_lblSelection == null) return;
        var n = _checkedRemember.Count;
        _lblSelection.Text = $"Selected  {n}";
        _lblSelection.ForeColor = n > 0 ? _accent : UiTheme.TextMuted;
    }

    private void ApplyDbFilter()
    {
        if (_clbDatabases == null) return;
        var q = (_txtDbSearch?.Text ?? "").Trim();
        _clbDatabases.BeginUpdate();
        try
        {
            _clbDatabases.Items.Clear();
            foreach (var db in _allDatabases)
            {
                if (q.Length > 0 && db.IndexOf(q, StringComparison.OrdinalIgnoreCase) < 0)
                    continue;
                _clbDatabases.Items.Add(db, _checkedRemember.Contains(db));
            }
        }
        finally
        {
            _clbDatabases.EndUpdate();
        }
        UpdateSelectionLabel();
    }

    public void SetConnectionStatus(bool connected, string? detail = null)
    {
        if (connected)
        {
            _statusBadge.Text = string.IsNullOrWhiteSpace(detail)
                ? "\u25CF  Connected"
                : $"\u25CF  Connected  ·  {detail}";
            _statusBadge.ForeColor = UiTheme.Success;
            _statusBadge.BackColor = Color.FromArgb(220, 252, 231);
            _lblConnMsg.Text = "\u2713  Connected successfully";
            _lblConnMsg.ForeColor = UiTheme.Success;
            _lblConnMsg.Visible = true;
        }
        else if (!string.IsNullOrWhiteSpace(detail) &&
                 detail.Contains("fail", StringComparison.OrdinalIgnoreCase))
        {
            _statusBadge.Text = "\u26A0  Connection failed";
            _statusBadge.ForeColor = UiTheme.Danger;
            _statusBadge.BackColor = Color.FromArgb(254, 226, 226);
            _lblConnMsg.Text = "\u2717  Connection failed";
            _lblConnMsg.ForeColor = UiTheme.Danger;
            _lblConnMsg.Visible = true;
        }
        else
        {
            _statusBadge.Text = "\u25CF  Not connected";
            _statusBadge.ForeColor = UiTheme.TextMuted;
            _statusBadge.BackColor = Color.FromArgb(243, 244, 246);
            _lblConnMsg.Text = "";
            _lblConnMsg.Visible = false;
        }
    }

    private void OnDatabaseSelectionChanged()
    {
        if (_suppressDbEvent) return;
        DatabaseSelectionChanged?.Invoke(this, EventArgs.Empty);
    }

    public void SetMultiSelectVisible(bool multi)
    {
        if (!_supportsMulti) return;
        _multiSelectActive = multi;
        _hint.Text = multi
            ? "Choose one or more destination databases"
            : "Choose a single destination database";
        _lblDatabase.Text = multi ? "Databases" : "Database";

        _cmbDatabase.Visible = !multi;
        if (_txtDbSearch != null) _txtDbSearch.Visible = multi;
        if (_clbDatabases != null) _clbDatabases.Visible = multi;
        if (_btnSelectAll != null) _btnSelectAll.Visible = multi;
        if (_btnClear != null) _btnClear.Visible = multi;
        if (_lblSelection != null) _lblSelection.Visible = multi;

        // Grow/shrink the list row with a FIXED height so One-to-Many does not
        // stretch a huge empty Percent row between Database and Test Connection.
        if (_grid.RowStyles.Count > 6)
            _grid.RowStyles[6] = multi
                ? new RowStyle(SizeType.Absolute, 96f)
                : new RowStyle(SizeType.Absolute, 0f);

        if (!multi && _allDatabases.Count > 0)
            PopulateComboFromCache();
        else if (multi)
            ApplyDbFilter();

        // Relayout without a full form resize storm.
        _grid.SuspendLayout();
        try { PerformLayout(); }
        finally { _grid.ResumeLayout(true); }
    }

    public bool ValidateForConnection(out string message)
    {
        _errors.Clear();
        var info = GetConnectionInfo(false);
        var r = FormValidator.ValidatePortText(_txtPort.Text, _sideLabel);
        var s = FormValidator.ValidateServer(info, _sideLabel);
        foreach (var e in s.Errors) r.Add(e);

        if (!string.IsNullOrWhiteSpace(_txtPort.Text) && r.Errors.Any(x => x.Contains("port", StringComparison.OrdinalIgnoreCase)))
            _errors.SetError(_txtPort, "Invalid port");
        if (string.IsNullOrWhiteSpace(info.Instance))
            _errors.SetError(_txtInstance, "Required");
        if (info.Auth == AuthMode.Sql && string.IsNullOrWhiteSpace(info.UserName))
            _errors.SetError(_txtUser, "Required");
        if (info.Auth == AuthMode.Sql && string.IsNullOrWhiteSpace(info.Password))
            _errors.SetError(_txtPassword, "Required");

        message = r.AsMessage();
        return r.Ok;
    }

    public bool ValidateForCompare(bool oneToMany, out string message)
    {
        if (!ValidateForConnection(out message))
            return false;

        if (!_supportsMulti || !oneToMany)
        {
            if (string.IsNullOrWhiteSpace(SelectedDatabase))
            {
                _errors.SetError(_cmbDatabase, "Select a database");
                message = $"{_sideLabel}: select a database.";
                return false;
            }
            return true;
        }

        var checkedDbs = GetCheckedDatabases();
        if (checkedDbs.Count == 0)
        {
            message = $"{_sideLabel}: check at least one database.";
            if (_clbDatabases != null) _errors.SetError(_clbDatabases, "Required");
            return false;
        }
        return true;
    }

    public string PortText => _txtPort.Text.Trim();

    /// <summary>Primary selected database (combo for 1:1, first checked for 1:N).</summary>
    public string SelectedDatabase
    {
        get
        {
            if (_supportsMulti && _multiSelectActive)
                return GetCheckedDatabases().FirstOrDefault() ?? "";
            return _cmbDatabase.Text.Trim();
        }
    }

    public ConnectionInfo GetConnectionInfo(bool includeSelectedDatabase = true)
    {
        _ = int.TryParse(_txtPort.Text.Trim(), out var port);
        var info = new ConnectionInfo
        {
            Instance = _txtInstance.Text.Trim(),
            Port = port,
            Auth = _rbSql.Checked ? AuthMode.Sql : AuthMode.Windows,
            UserName = _txtUser.Text.Trim(),
            Password = _txtPassword.Text,
            TrustServerCertificate = true
        };
        if (includeSelectedDatabase)
            info.Database = SelectedDatabase;
        return info;
    }

    /// <summary>Sets the password field (used when swapping source/target).</summary>
    public void SetPassword(string password) => _txtPassword.Text = password ?? "";

    public void Apply(ConnectionInfo info)
    {
        _suppressDbEvent = true;
        try
        {
            _txtInstance.Text = info.Instance;
            _txtPort.Text = info.Port > 0 ? info.Port.ToString() : "";
            if (info.Auth == AuthMode.Sql) _rbSql.Checked = true; else _rbWindows.Checked = true;
            _txtUser.Text = info.UserName;
            if (!string.IsNullOrWhiteSpace(info.Database))
                _cmbDatabase.Text = info.Database;
        }
        finally
        {
            _suppressDbEvent = false;
        }
    }

    public void SetDatabases(IEnumerable<string> databases, IEnumerable<string>? preferredChecked = null)
    {
        _suppressDbEvent = true;
        try
        {
            _allDatabases = databases.ToList();
            if (preferredChecked != null)
                _checkedRemember = new HashSet<string>(preferredChecked, StringComparer.OrdinalIgnoreCase);

            PopulateComboFromCache();

            if (_supportsMulti && _multiSelectActive && _clbDatabases != null)
            {
                ApplyDbFilter();
                ClearError(_clbDatabases);
            }
            else
            {
                ClearError(_cmbDatabase);
            }
        }
        finally
        {
            _suppressDbEvent = false;
        }
        OnDatabaseSelectionChanged();
    }

    private void PopulateComboFromCache()
    {
        var current = _cmbDatabase.Text;
        _cmbDatabase.Items.Clear();
        foreach (var db in _allDatabases)
            _cmbDatabase.Items.Add(db);
        if (!string.IsNullOrWhiteSpace(current) && _cmbDatabase.Items.Contains(current))
            _cmbDatabase.SelectedItem = current;
        else if (_cmbDatabase.Items.Count > 0 && string.IsNullOrWhiteSpace(current))
            _cmbDatabase.SelectedIndex = 0;
        else if (!string.IsNullOrWhiteSpace(current))
            _cmbDatabase.Text = current;
    }

    public IReadOnlyList<string> GetCheckedDatabases()
    {
        if (!_supportsMulti)
        {
            var db = _cmbDatabase.Text.Trim();
            return string.IsNullOrWhiteSpace(db) ? Array.Empty<string>() : new[] { db };
        }

        if (!_multiSelectActive)
        {
            var db = _cmbDatabase.Text.Trim();
            return string.IsNullOrWhiteSpace(db) ? Array.Empty<string>() : new[] { db };
        }

        return _checkedRemember.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
    }

    public void CheckAllDatabases(bool check)
    {
        if (_clbDatabases == null) return;
        if (check)
        {
            foreach (var db in _allDatabases) _checkedRemember.Add(db);
        }
        else
        {
            _checkedRemember.Clear();
        }
        ApplyDbFilter();
        OnDatabaseSelectionChanged();
    }

    public string SingleDatabase
    {
        get => SelectedDatabase;
        set
        {
            _suppressDbEvent = true;
            try { _cmbDatabase.Text = value; }
            finally { _suppressDbEvent = false; }
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            try { _errors.Dispose(); } catch { /* ignore */ }
            try { _tips.Dispose(); } catch { /* ignore */ }
        }
        base.Dispose(disposing);
    }
}
