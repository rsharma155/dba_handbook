using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

public sealed class OptionsForm : Form
{
    private readonly CheckBox _chkGenerate = new() { Text = "Generate sync scripts (auto_ / manual_)", AutoSize = true, Checked = true };
    private readonly CheckBox _chkDrops = new()
    {
        Text = "Include drops for non-table objects (views, procs, indexes…)",
        AutoSize = true
    };
    private readonly Label _lblDropsHint = new()
    {
        Text = "DROP TABLE is never auto-applied — always written as a manual_ script for review.",
        AutoSize = true,
        ForeColor = UiTheme.Warning,
        Font = UiTheme.UiFont(8.5f)
    };
    private readonly CheckBox _chkApply = new() { Text = "Apply auto_ scripts on target after compare", AutoSize = true, ForeColor = UiTheme.Danger };
    private readonly CheckBox _chkTrust = new() { Text = "Trust server certificate", AutoSize = true, Checked = true };
    private readonly ComboBox _cmbProtocol = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 160 };
    private readonly NumericUpDown _numTimeout = new() { Minimum = 5, Maximum = 300, Value = 30, Width = 80 };
    private readonly TextBox _txtExclude = new() { Width = 360, Text = "sys,INFORMATION_SCHEMA,guest" };
    private readonly TextBox _txtOutput = new() { Width = 320 };
    private readonly ModernButton _btnBrowse = new() { Text = "...", Width = 42, Height = 28 };

    public CompareOptions Options { get; private set; }

    public OptionsForm(CompareOptions current)
    {
        Options = current;
        Text = "Compare Options";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MinimizeBox = false;
        MaximizeBox = false;
        ClientSize = new Size(520, 400);
        Font = UiTheme.UiFont();
        BackColor = UiTheme.AppBackground;
        ForeColor = UiTheme.TextPrimary;

        var header = new Panel { Dock = DockStyle.Top, Height = 48, BackColor = UiTheme.HeaderBackground };
        header.Controls.Add(new Label
        {
            Text = "Compare options",
            ForeColor = UiTheme.TextOnDark,
            Font = new Font("Segoe UI", 12f, FontStyle.Bold),
            AutoSize = true,
            Location = new Point(16, 14)
        });
        Controls.Add(header);

        var y = 64;
        Controls.Add(UiTheme.MakeLabel("Network protocol:", 16, y));
        _cmbProtocol.Items.AddRange(new object[] { "TcpIp", "NamedPipes", "SharedMemory" });
        _cmbProtocol.SelectedItem = current.NetworkProtocol;
        _cmbProtocol.Location = new Point(160, y - 2);
        UiTheme.StyleCombo(_cmbProtocol);
        Controls.Add(_cmbProtocol);

        y += 36;
        Controls.Add(UiTheme.MakeLabel("Connection timeout (s):", 16, y));
        _numTimeout.Value = Math.Clamp(current.ConnectionTimeout, 5, 300);
        _numTimeout.Location = new Point(190, y - 2);
        Controls.Add(_numTimeout);

        y += 36;
        _chkTrust.Checked = current.TrustServerCertificate;
        _chkTrust.Location = new Point(16, y);
        _chkTrust.ForeColor = UiTheme.TextPrimary;
        Controls.Add(_chkTrust);

        y += 30;
        _chkGenerate.Checked = current.GenerateSyncScript;
        _chkGenerate.Location = new Point(16, y);
        _chkGenerate.ForeColor = UiTheme.TextPrimary;
        Controls.Add(_chkGenerate);

        y += 28;
        _chkDrops.Checked = current.IncludeDrops;
        _chkDrops.Location = new Point(16, y);
        _chkDrops.ForeColor = UiTheme.TextPrimary;
        Controls.Add(_chkDrops);

        y += 24;
        _lblDropsHint.Location = new Point(34, y);
        Controls.Add(_lblDropsHint);

        y += 28;
        _chkApply.Checked = current.Apply;
        _chkApply.Location = new Point(16, y);
        Controls.Add(_chkApply);

        y += 36;
        Controls.Add(UiTheme.MakeLabel("Exclude schemas:", 16, y));
        UiTheme.StyleTextBox(_txtExclude);
        _txtExclude.Text = current.ExcludeSchemas;
        _txtExclude.Location = new Point(140, y - 2);
        Controls.Add(_txtExclude);

        y += 36;
        Controls.Add(UiTheme.MakeLabel("Output folder:", 16, y));
        UiTheme.StyleTextBox(_txtOutput);
        _txtOutput.Text = current.OutputPath;
        _txtOutput.Location = new Point(140, y - 2);
        Controls.Add(_txtOutput);
        UiTheme.StyleSecondary(_btnBrowse);
        _btnBrowse.Location = new Point(468, y - 2);
        _btnBrowse.Click += (_, _) =>
        {
            using var dlg = new FolderBrowserDialog { Description = "Sync script output folder" };
            if (!string.IsNullOrWhiteSpace(_txtOutput.Text) && Directory.Exists(_txtOutput.Text))
                dlg.SelectedPath = _txtOutput.Text;
            if (dlg.ShowDialog(this) == DialogResult.OK)
                _txtOutput.Text = dlg.SelectedPath;
        };
        Controls.Add(_btnBrowse);

        var ok = new ModernButton { Text = "OK", DialogResult = DialogResult.OK, Location = new Point(300, 350), Width = 96, Height = 34 };
        var cancel = new ModernButton { Text = "Cancel", DialogResult = DialogResult.Cancel, Location = new Point(406, 350), Width = 96, Height = 34 };
        UiTheme.StylePrimary(ok);
        UiTheme.StyleSecondary(cancel);
        ok.Click += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(_txtOutput.Text))
            {
                MessageBox.Show(this, "Output folder is required.", "Validation",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                DialogResult = DialogResult.None;
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
        Controls.Add(ok);
        Controls.Add(cancel);
        AcceptButton = ok;
        CancelButton = cancel;
    }
}
