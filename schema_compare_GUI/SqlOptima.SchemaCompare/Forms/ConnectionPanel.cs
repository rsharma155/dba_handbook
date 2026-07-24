using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>
/// Source or Destination connection card — modern high-contrast styling,
/// multi-select targets, and field-level validation via ErrorProvider.
/// </summary>
public sealed class ConnectionPanel : UserControl
{
    private readonly Label _title;
    private readonly Label _hint;
    private readonly TextBox _txtInstance = new();
    private readonly TextBox _txtPort = new();
    private readonly RadioButton _rbWindows = new() { Text = "Windows Authentication", Checked = true, AutoSize = true };
    private readonly RadioButton _rbSql = new() { Text = "SQL Server Authentication", AutoSize = true };
    private readonly TextBox _txtUser = new();
    private readonly TextBox _txtPassword = new() { UseSystemPasswordChar = true };
    private readonly ComboBox _cmbDatabase = new() { DropDownStyle = ComboBoxStyle.DropDown };
    private readonly CheckedListBox? _clbDatabases;
    private readonly ModernButton _btnTest = new() { Text = "Test", Width = 86, Height = 32 };
    private readonly ModernButton _btnRefresh = new() { Text = "Refresh DBs", Width = 110, Height = 32 };
    private readonly ModernButton? _btnSelectAll;
    private readonly ModernButton? _btnClear;
    private readonly Label? _lblSelection;
    private readonly ErrorProvider _errors = new() { BlinkStyle = ErrorBlinkStyle.NeverBlink };
    private readonly bool _multiSelect;
    private readonly string _sideLabel;

    public event EventHandler? TestClicked;
    public event EventHandler? RefreshClicked;

    public ConnectionPanel(string title, bool multiSelectTargets = false)
    {
        _multiSelect = multiSelectTargets;
        _sideLabel = multiSelectTargets ? "Destination" : "Source";
        BorderStyle = BorderStyle.None;
        BackColor = UiTheme.CardBackground;
        Padding = new Padding(14);
        Height = multiSelectTargets ? 286 : 232;
        DoubleBuffered = true;

        Paint += (_, e) =>
        {
            using var fill = new SolidBrush(UiTheme.CardBackground);
            e.Graphics.FillRectangle(fill, ClientRectangle);
            using var pen = new Pen(UiTheme.CardBorder, 1.5f);
            e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
            // Accent bar on the left
            using var accent = new SolidBrush(multiSelectTargets ? UiTheme.Success : UiTheme.Primary);
            e.Graphics.FillRectangle(accent, 0, 0, 4, Height);
        };

        _title = new Label
        {
            Text = title,
            Font = UiTheme.SemiBold(11f),
            ForeColor = UiTheme.TextPrimary,
            AutoSize = true,
            Location = new Point(16, 12)
        };
        Controls.Add(_title);

        _hint = new Label
        {
            Text = multiSelectTargets
                ? "Check one or more databases for one-to-many sync."
                : "Pick the source-of-truth database.",
            Font = UiTheme.UiFont(8.5f),
            ForeColor = UiTheme.TextMuted,
            AutoSize = true,
            Location = new Point(16, 36)
        };
        Controls.Add(_hint);

        Controls.Add(UiTheme.MakeLabel("Server host *", 16, 64));
        UiTheme.StyleTextBox(_txtInstance);
        _txtInstance.SetBounds(120, 60, 210, 26);
        _txtInstance.PlaceholderText = "hostname or .\\INSTANCE";
        Controls.Add(_txtInstance);

        Controls.Add(UiTheme.MakeLabel("Port", 340, 64));
        UiTheme.StyleTextBox(_txtPort);
        _txtPort.SetBounds(375, 60, 70, 26);
        _txtPort.PlaceholderText = "1433";
        Controls.Add(_txtPort);

        _rbWindows.Location = new Point(16, 96);
        _rbWindows.ForeColor = UiTheme.TextPrimary;
        _rbWindows.Font = UiTheme.UiFont(9f);
        _rbSql.Location = new Point(210, 96);
        _rbSql.ForeColor = UiTheme.TextPrimary;
        _rbSql.Font = UiTheme.UiFont(9f);
        Controls.Add(_rbWindows);
        Controls.Add(_rbSql);
        _rbWindows.CheckedChanged += (_, _) => UpdateAuthUi();
        _rbSql.CheckedChanged += (_, _) => UpdateAuthUi();

        Controls.Add(UiTheme.MakeLabel("User", 16, 128));
        UiTheme.StyleTextBox(_txtUser);
        _txtUser.SetBounds(120, 124, 145, 26);
        Controls.Add(_txtUser);

        Controls.Add(UiTheme.MakeLabel("Password", 275, 128));
        UiTheme.StyleTextBox(_txtPassword);
        _txtPassword.SetBounds(345, 124, 100, 26);
        Controls.Add(_txtPassword);

        Controls.Add(UiTheme.MakeLabel(multiSelectTargets ? "Database(s) *" : "Database *", 16, 162));
        if (multiSelectTargets)
        {
            _clbDatabases = new CheckedListBox
            {
                CheckOnClick = true,
                Location = new Point(120, 160),
                Size = new Size(325, 78),
                BorderStyle = BorderStyle.FixedSingle,
                IntegralHeight = false,
                Font = UiTheme.UiFont(9f),
                ForeColor = UiTheme.TextPrimary,
                BackColor = Color.White
            };
            _clbDatabases.ItemCheck += (_, _) =>
            {
                if (!IsHandleCreated) { UpdateSelectionLabel(); return; }
                try { BeginInvoke(new Action(UpdateSelectionLabel)); }
                catch (InvalidOperationException) { UpdateSelectionLabel(); }
            };
            Controls.Add(_clbDatabases);

            _btnSelectAll = new ModernButton { Text = "Select all", Width = 96, Height = 30 };
            _btnClear = new ModernButton { Text = "Clear", Width = 72, Height = 30 };
            UiTheme.StyleGhost(_btnSelectAll);
            UiTheme.StyleGhost(_btnClear);
            _btnSelectAll.Location = new Point(120, 246);
            _btnClear.Location = new Point(222, 246);
            _btnSelectAll.Click += (_, _) => CheckAllDatabases(true);
            _btnClear.Click += (_, _) => CheckAllDatabases(false);
            Controls.Add(_btnSelectAll);
            Controls.Add(_btnClear);

            _lblSelection = new Label
            {
                Text = "0 selected",
                AutoSize = true,
                ForeColor = UiTheme.TextMuted,
                Font = UiTheme.SemiBold(8.5f),
                Location = new Point(302, 252)
            };
            Controls.Add(_lblSelection);
        }
        else
        {
            UiTheme.StyleCombo(_cmbDatabase);
            _cmbDatabase.SetBounds(120, 158, 325, 26);
            Controls.Add(_cmbDatabase);
        }

        var btnY = multiSelectTargets ? 246 : 196;
        if (multiSelectTargets)
        {
            _btnTest.Location = new Point(370, btnY);
            _btnRefresh.Location = new Point(462, btnY);
            // Keep within ~560 width: shrink and shift left
            _btnTest.Width = 78;
            _btnRefresh.Width = 100;
            _btnTest.Location = new Point(368, btnY);
            _btnRefresh.Location = new Point(452, btnY);
        }
        else
        {
            _btnTest.Location = new Point(120, btnY);
            _btnRefresh.Location = new Point(214, btnY);
        }

        UiTheme.StylePrimary(_btnTest);
        UiTheme.StyleSecondary(_btnRefresh);
        Controls.Add(_btnTest);
        Controls.Add(_btnRefresh);
        _btnTest.Click += (_, _) =>
        {
            if (!ValidateForConnection(out var msg))
            {
                MessageBox.Show(FindForm(), msg, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            TestClicked?.Invoke(this, EventArgs.Empty);
        };
        _btnRefresh.Click += (_, _) =>
        {
            if (!ValidateForConnection(out var msg))
            {
                MessageBox.Show(FindForm(), msg, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            RefreshClicked?.Invoke(this, EventArgs.Empty);
        };

        _txtInstance.TextChanged += (_, _) => ClearError(_txtInstance);
        _txtPort.TextChanged += (_, _) => ClearError(_txtPort);
        _txtUser.TextChanged += (_, _) => ClearError(_txtUser);
        _txtPassword.TextChanged += (_, _) => ClearError(_txtPassword);

        UpdateAuthUi();
    }

    private void ClearError(Control c) => _errors.SetError(c, "");

    private void UpdateAuthUi()
    {
        var sql = _rbSql.Checked;
        _txtUser.Enabled = sql;
        _txtPassword.Enabled = sql;
        if (!sql)
        {
            ClearError(_txtUser);
            ClearError(_txtPassword);
        }
    }

    private void UpdateSelectionLabel()
    {
        if (_lblSelection == null || _clbDatabases == null) return;
        var n = 0;
        for (var i = 0; i < _clbDatabases.Items.Count; i++)
            if (_clbDatabases.GetItemChecked(i)) n++;
        _lblSelection.Text = n == 0 ? "0 selected" : $"{n} selected";
        _lblSelection.ForeColor = n > 0 ? UiTheme.Success : UiTheme.TextMuted;
    }

    public void SetMultiSelectVisible(bool multi)
    {
        if (_hint != null && _multiSelect)
        {
            _hint.Text = multi
                ? "Check one or more databases for one-to-many sync."
                : "Check a single destination database (or switch to One-to-Many).";
        }
    }

    /// <summary>Validate server fields before Test / Refresh.</summary>
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

    /// <summary>Validate including database selection for compare.</summary>
    public bool ValidateForCompare(bool oneToMany, out string message)
    {
        if (!ValidateForConnection(out message))
            return false;

        if (!_multiSelect)
        {
            if (string.IsNullOrWhiteSpace(_cmbDatabase.Text))
            {
                _errors.SetError(_cmbDatabase, "Select a database");
                message = $"{_sideLabel}: select a source database.";
                return false;
            }
            return true;
        }

        var checkedDbs = GetCheckedDatabases();
        if (!oneToMany && checkedDbs.Count > 1)
        {
            message = "Destination: One-to-One allows only one checked database.";
            if (_clbDatabases != null) _errors.SetError(_clbDatabases, "Pick one");
            return false;
        }
        if (checkedDbs.Count == 0)
        {
            message = $"{_sideLabel}: check at least one database.";
            if (_clbDatabases != null) _errors.SetError(_clbDatabases, "Required");
            return false;
        }
        return true;
    }

    public string PortText => _txtPort.Text.Trim();

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
        {
            if (_multiSelect && _clbDatabases != null)
            {
                var first = GetCheckedDatabases().FirstOrDefault();
                info.Database = first ?? "";
            }
            else
            {
                info.Database = _cmbDatabase.Text.Trim();
            }
        }
        return info;
    }

    public void Apply(ConnectionInfo info)
    {
        _txtInstance.Text = info.Instance;
        _txtPort.Text = info.Port > 0 ? info.Port.ToString() : "";
        if (info.Auth == AuthMode.Sql) _rbSql.Checked = true; else _rbWindows.Checked = true;
        _txtUser.Text = info.UserName;
        if (!_multiSelect)
            _cmbDatabase.Text = info.Database;
    }

    public void SetDatabases(IEnumerable<string> databases, IEnumerable<string>? preferredChecked = null)
    {
        var preferred = new HashSet<string>(preferredChecked ?? Array.Empty<string>(), StringComparer.OrdinalIgnoreCase);
        if (_multiSelect && _clbDatabases != null)
        {
            _clbDatabases.Items.Clear();
            foreach (var db in databases)
                _clbDatabases.Items.Add(db, preferred.Contains(db));
            UpdateSelectionLabel();
            ClearError(_clbDatabases);
        }
        else
        {
            var current = _cmbDatabase.Text;
            _cmbDatabase.Items.Clear();
            foreach (var db in databases)
                _cmbDatabase.Items.Add(db);
            if (!string.IsNullOrWhiteSpace(current) && _cmbDatabase.Items.Contains(current))
                _cmbDatabase.SelectedItem = current;
            else if (_cmbDatabase.Items.Count > 0)
                _cmbDatabase.SelectedIndex = 0;
            ClearError(_cmbDatabase);
        }
    }

    public IReadOnlyList<string> GetCheckedDatabases()
    {
        if (_clbDatabases == null) return Array.Empty<string>();
        var list = new List<string>();
        for (var i = 0; i < _clbDatabases.Items.Count; i++)
        {
            if (_clbDatabases.GetItemChecked(i))
                list.Add(_clbDatabases.Items[i]?.ToString() ?? "");
        }
        return list;
    }

    public void CheckAllDatabases(bool check)
    {
        if (_clbDatabases == null) return;
        for (var i = 0; i < _clbDatabases.Items.Count; i++)
            _clbDatabases.SetItemChecked(i, check);
        UpdateSelectionLabel();
    }

    public string SingleDatabase
    {
        get => _cmbDatabase.Text.Trim();
        set => _cmbDatabase.Text = value;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            try { _errors.Dispose(); } catch { /* ignore */ }
        }
        base.Dispose(disposing);
    }
}
